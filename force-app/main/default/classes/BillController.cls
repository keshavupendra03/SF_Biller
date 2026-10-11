/**
 * The single Apex entry point for the Billing LWC (architecture.md §B —
 * every staff workflow is a custom LWC backed by its own controller, never
 * a standard page). Creating a bill (or a new version of one) is atomic
 * and one-shot: the bill and all of its line items (and an optional first
 * payment) are submitted together in one call, one transaction.
 *
 * Versioning (architecture.md §C.4): editing an existing bill's line items
 * in place is never supported — "changing" a bill means creating a new
 * Bill__c record that supersedes it, with its own freshly, atomically
 * assigned Invoice_Number__c (Stage 1's locking logic, completely
 * unaffected by any of this). createNewVersion reverses the superseded
 * version's stock deductions (via BillStockService, the same mechanism a
 * line deletion already uses) before the new version's own line items
 * deduct stock again — otherwise a near-identical new version would double
 * count both bills' worth of parts against inventory. Payments are
 * deliberately NOT carried forward to a new version — they stay on the
 * superseded bill for its own audit trail; the new version starts Unpaid.
 */
public with sharing class BillController {

    public class BillControllerException extends Exception {}

    public class LineItemInput {
        @AuraEnabled public Id partId { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public Decimal taxRatePercent { get; set; }
        @AuraEnabled public String gstType { get; set; }
        @AuraEnabled public String hsnSacCode { get; set; }
        @AuraEnabled public String unitLabel { get; set; }
    }

    public class NewBillToPartyInput {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String contactPhone { get; set; }
        @AuraEnabled public String gstin { get; set; }
        @AuraEnabled public String state { get; set; }
    }

    public class CreateBillRequest {
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public Id jobId { get; set; }
        @AuraEnabled public Id billToPartyId { get; set; }
        @AuraEnabled public NewBillToPartyInput newBillToParty { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public CustomerController.NewVehicleInput newVehicle { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Date billDate { get; set; }
        @AuraEnabled public Id sourceEstimateId { get; set; }
        @AuraEnabled public List<LineItemInput> lineItems { get; set; }
        @AuraEnabled public Decimal initialPaymentAmount { get; set; }
        @AuraEnabled public String initialPaymentMethod { get; set; }
    }

    public class PartSearchResult {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String sku { get; set; }
        @AuraEnabled public String barcode { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Decimal taxRatePercent { get; set; }
        @AuraEnabled public String gstType { get; set; }
        @AuraEnabled public String hsnCode { get; set; }
        @AuraEnabled public String unitLabel { get; set; }
        @AuraEnabled public Decimal currentStock { get; set; }
    }

    public class CustomerSearchResult {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
    }

    public class NewCustomerInput {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String gstin { get; set; }
        @AuraEnabled public String state { get; set; }
    }

    public class PaymentItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String method { get; set; }
        @AuraEnabled public Datetime paidAt { get; set; }
    }

    public class BillListItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String invoiceNumber { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date billDate { get; set; }
    }

    public class BillSummary {
        @AuraEnabled public Id billId { get; set; }
        @AuraEnabled public String invoiceNumber { get; set; }
        @AuraEnabled public String financialYear { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date billDate { get; set; }
        @AuraEnabled public Integer versionNumber { get; set; }
        @AuraEnabled public Boolean isLatestVersion { get; set; }
        @AuraEnabled public Id sourceEstimateId { get; set; }
        @AuraEnabled public Id jobId { get; set; }
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public Id billToPartyId { get; set; }
        @AuraEnabled public String billToPartyName { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public String vehicleLabel { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Decimal subtotal { get; set; }
        @AuraEnabled public Decimal cgst { get; set; }
        @AuraEnabled public Decimal sgst { get; set; }
        @AuraEnabled public Decimal igst { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public List<LineItemInput> lineItems { get; set; }
        @AuraEnabled public List<PaymentItem> payments { get; set; }
        @AuraEnabled public Decimal amountPaid { get; set; }
        @AuraEnabled public Decimal amountDue { get; set; }
    }

    @AuraEnabled
    public static List<PartSearchResult> searchParts(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<PartSearchResult> results = new List<PartSearchResult>();
        for (Part__c part : [
            SELECT Id, Name, SKU__c, Barcode__c, Price__c, Tax_Rate_Percent__c,
                   Gst_Type__c, HSN_Code__c, Unit__c, Current_Stock__c
            FROM Part__c
            WHERE Name LIKE :term OR SKU__c LIKE :term OR Barcode__c LIKE :term
            ORDER BY Name
            LIMIT 25
        ]) {
            PartSearchResult r = new PartSearchResult();
            r.id = part.Id;
            r.name = part.Name;
            r.sku = part.SKU__c;
            r.barcode = part.Barcode__c;
            r.price = part.Price__c;
            r.taxRatePercent = part.Tax_Rate_Percent__c;
            r.gstType = part.Gst_Type__c;
            r.hsnCode = part.HSN_Code__c;
            r.unitLabel = part.Unit__c;
            r.currentStock = part.Current_Stock__c;
            results.add(r);
        }
        return results;
    }

    @AuraEnabled
    public static List<CustomerSearchResult> searchCustomers(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<CustomerSearchResult> results = new List<CustomerSearchResult>();
        for (Customer__c customer : [
            SELECT Id, Name, Phone__c
            FROM Customer__c
            WHERE Name LIKE :term OR Phone__c LIKE :term
            ORDER BY Name
            LIMIT 25
        ]) {
            CustomerSearchResult r = new CustomerSearchResult();
            r.id = customer.Id;
            r.name = customer.Name;
            r.phone = customer.Phone__c;
            results.add(r);
        }
        return results;
    }

    /**
     * Every staff workflow that needs a customer (billing, estimates, the
     * jobs board) must be able to onboard a brand-new one inline — without
     * this, the very first step of "new customer -> job -> estimate ->
     * bill" would force staff onto the standard Customer__c tab, breaking
     * the hard no-standard-tabs rule.
     */
    @AuraEnabled
    public static CustomerSearchResult createCustomer(NewCustomerInput input) {
        if (input == null || String.isBlank(input.name) || String.isBlank(input.phone)) {
            throw new BillControllerException('Customer name and phone are required.');
        }
        Customer__c customer = new Customer__c(
            Name = input.name,
            Phone__c = input.phone,
            Address__c = input.address,
            Email__c = input.email,
            GSTIN__c = input.gstin,
            State__c = input.state
        );
        insert customer;

        CustomerSearchResult result = new CustomerSearchResult();
        result.id = customer.Id;
        result.name = customer.Name;
        result.phone = customer.Phone__c;
        return result;
    }

    @AuraEnabled
    public static BillSummary createBill(CreateBillRequest request) {
        validate(request);
        PartUpsertService.fillManualPartIds(request.lineItems);
        Id billToPartyId = resolveBillToPartyId(request.billToPartyId, request.newBillToParty);
        Id vehicleId = resolveVehicleId(request.customerId, request.vehicleId, request.newVehicle);

        Bill__c bill = new Bill__c(
            Customer__c = request.customerId,
            Job__c = request.jobId,
            Bill_To_Party__c = billToPartyId,
            Vehicle__c = vehicleId,
            Notes__c = request.notes,
            Bill_Date__c = request.billDate != null ? request.billDate : Date.today(),
            Source_Estimate__c = request.sourceEstimateId
        );
        insert bill;

        insertLineItems(bill.Id, request.lineItems);
        insertInitialPayment(bill.Id, request);

        if (request.sourceEstimateId != null) {
            update new Estimate__c(Id = request.sourceEstimateId, Status__c = 'Converted');
        }

        return buildSummary(bill.Id);
    }

    /**
     * Creates a new version of previousBillId: reverses that bill's stock
     * deductions, inserts a brand-new Bill__c (its own Invoice_Number__c),
     * and deducts stock again for the new line items. The previous version
     * is marked Is_Latest_Version__c = false but is never deleted or
     * edited — it keeps its own number and its own payment history.
     */
    @AuraEnabled
    public static BillSummary createNewVersion(Id previousBillId, CreateBillRequest request) {
        validate(request);
        PartUpsertService.fillManualPartIds(request.lineItems);

        Bill__c previous = [
            SELECT Version_Number__c, Root_Bill__c, Source_Estimate__c, Job__c, Vehicle__c
            FROM Bill__c
            WHERE Id = :previousBillId
        ];
        Id rootId = previous.Root_Bill__c != null ? previous.Root_Bill__c : previousBillId;

        List<Bill_Line_Item__c> previousLineItems = [
            SELECT Part__c, Quantity__c FROM Bill_Line_Item__c WHERE Bill__c = :previousBillId
        ];
        BillStockService.restoreForRemovedLineItems(previousLineItems);

        Id billToPartyId = resolveBillToPartyId(request.billToPartyId, request.newBillToParty);
        Id vehicleId = request.vehicleId != null || request.newVehicle != null
            ? resolveVehicleId(request.customerId, request.vehicleId, request.newVehicle)
            : previous.Vehicle__c;

        Bill__c newVersion = new Bill__c(
            Customer__c = request.customerId,
            Job__c = request.jobId != null ? request.jobId : previous.Job__c,
            Bill_To_Party__c = billToPartyId,
            Vehicle__c = vehicleId,
            Notes__c = request.notes,
            Bill_Date__c = request.billDate != null ? request.billDate : Date.today(),
            Source_Estimate__c = request.sourceEstimateId != null ? request.sourceEstimateId : previous.Source_Estimate__c,
            Previous_Version__c = previousBillId,
            Root_Bill__c = rootId,
            Version_Number__c = (previous.Version_Number__c == null ? 1 : previous.Version_Number__c) + 1
        );
        insert newVersion;

        insertLineItems(newVersion.Id, request.lineItems);
        insertInitialPayment(newVersion.Id, request);

        update new Bill__c(Id = previousBillId, Is_Latest_Version__c = false);

        return buildSummary(newVersion.Id);
    }

    @AuraEnabled
    public static BillSummary getBillSummary(Id billId) {
        return buildSummary(billId);
    }

    /**
     * Records a payment against an existing bill outside of create/version
     * time (the Bill Details screen's "Record Payment" action) — a plain
     * Payment__c insert is all this needs, since PaymentTriggerHandler
     * already recomputes Bill__c.Status__c (architecture.md's lock-and-sum
     * pattern) from the full Payment__c ledger on every insert.
     */
    @AuraEnabled
    public static BillSummary recordPayment(Id billId, Decimal amount, String method) {
        if (billId == null || amount == null || amount <= 0) {
            throw new BillControllerException('A positive payment amount is required.');
        }
        insert new Payment__c(
            Bill__c = billId,
            Amount__c = amount,
            Method__c = String.isBlank(method) ? 'Cash' : method,
            Paid_At__c = Datetime.now()
        );
        return buildSummary(billId);
    }

    @AuraEnabled
    public static List<BillSummary> getBillVersions(Id anyVersionBillId) {
        Bill__c anyVersion = [SELECT Root_Bill__c FROM Bill__c WHERE Id = :anyVersionBillId];
        Id rootId = anyVersion.Root_Bill__c != null ? anyVersion.Root_Bill__c : anyVersionBillId;

        List<BillSummary> summaries = new List<BillSummary>();
        for (Bill__c b : [
            SELECT Id FROM Bill__c
            WHERE Id = :rootId OR Root_Bill__c = :rootId
            ORDER BY Version_Number__c
        ]) {
            summaries.add(buildSummary(b.Id));
        }
        return summaries;
    }

    /**
     * Backs the Billing LWC's list (architecture.md §B) — only the latest
     * version of each bill is shown, newest first, with an optional filter
     * down to the ones that still have money owed, and an optional search
     * across invoice number, customer name, and customer phone.
     */
    @AuraEnabled
    public static List<BillListItem> listBills(String filter, String searchTerm) {
        Boolean duesOnly = 'DuesOnly'.equals(filter);
        String term = '%' + String.escapeSingleQuotes(String.isBlank(searchTerm) ? '' : searchTerm) + '%';
        Boolean hasSearch = String.isNotBlank(searchTerm);

        List<Bill__c> bills;
        if (duesOnly && hasSearch) {
            bills = [
                SELECT Invoice_Number__c, Customer__r.Name, Total_Amount__c, Status__c, Bill_Date__c
                FROM Bill__c
                WHERE Is_Latest_Version__c = true AND Status__c != 'Paid'
                      AND (Invoice_Number__c LIKE :term OR Customer__r.Name LIKE :term OR Customer__r.Phone__c LIKE :term)
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        } else if (duesOnly) {
            bills = [
                SELECT Invoice_Number__c, Customer__r.Name, Total_Amount__c, Status__c, Bill_Date__c
                FROM Bill__c
                WHERE Is_Latest_Version__c = true AND Status__c != 'Paid'
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        } else if (hasSearch) {
            bills = [
                SELECT Invoice_Number__c, Customer__r.Name, Total_Amount__c, Status__c, Bill_Date__c
                FROM Bill__c
                WHERE Is_Latest_Version__c = true
                      AND (Invoice_Number__c LIKE :term OR Customer__r.Name LIKE :term OR Customer__r.Phone__c LIKE :term)
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        } else {
            bills = [
                SELECT Invoice_Number__c, Customer__r.Name, Total_Amount__c, Status__c, Bill_Date__c
                FROM Bill__c
                WHERE Is_Latest_Version__c = true
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }

        List<BillListItem> results = new List<BillListItem>();
        for (Bill__c b : bills) {
            BillListItem item = new BillListItem();
            item.id = b.Id;
            item.invoiceNumber = b.Invoice_Number__c;
            item.customerName = b.Customer__r != null ? b.Customer__r.Name : null;
            item.totalAmount = b.Total_Amount__c;
            item.status = b.Status__c;
            item.billDate = b.Bill_Date__c;
            results.add(item);
        }
        return results;
    }

    private static void validate(CreateBillRequest request) {
        if (request == null || request.customerId == null) {
            throw new BillControllerException('A customer is required.');
        }
        if (request.lineItems == null || request.lineItems.isEmpty()) {
            throw new BillControllerException('A bill needs at least one line item.');
        }
        for (LineItemInput li : request.lineItems) {
            if (String.isBlank(li.description)) {
                throw new BillControllerException('Every line item needs a description.');
            }
            if (li.quantity == null || li.quantity <= 0) {
                throw new BillControllerException('Every line item needs a quantity greater than zero.');
            }
            if (li.unitPrice == null || li.unitPrice < 0) {
                throw new BillControllerException('Every line item needs a non-negative unit price.');
            }
        }
    }

    private static Id resolveBillToPartyId(Id billToPartyId, NewBillToPartyInput newBillToParty) {
        if (billToPartyId != null) {
            return billToPartyId;
        }
        if (newBillToParty != null && String.isNotBlank(newBillToParty.name)) {
            Bill_To_Party__c party = new Bill_To_Party__c(
                Name = newBillToParty.name,
                Address__c = newBillToParty.address,
                Contact_Phone__c = newBillToParty.contactPhone,
                GSTIN__c = newBillToParty.gstin,
                State__c = newBillToParty.state
            );
            insert party;
            return party.Id;
        }
        return null;
    }

    /**
     * Mirrors resolveBillToPartyId: pick an existing vehicle if one was
     * selected, otherwise create one from the inline "new vehicle" fields —
     * under the same customer the bill belongs to, so it shows up on that
     * customer's record going forward, not just on this one bill.
     */
    private static Id resolveVehicleId(Id customerId, Id vehicleId, CustomerController.NewVehicleInput newVehicle) {
        if (vehicleId != null) {
            return vehicleId;
        }
        if (newVehicle != null && String.isNotBlank(newVehicle.registrationNumber)) {
            Vehicle__c vehicle = new Vehicle__c(
                Name = newVehicle.registrationNumber,
                Customer__c = customerId,
                Make__c = newVehicle.make,
                Model__c = newVehicle.model,
                Year__c = newVehicle.year,
                Color__c = newVehicle.color
            );
            insert vehicle;
            VehicleMakeModelService.rememberIfNew(vehicle.Make__c, vehicle.Model__c);
            return vehicle.Id;
        }
        return null;
    }

    private static String vehicleLabel(Id vehicleId, Vehicle__c vehicle) {
        if (vehicleId == null || vehicle == null) {
            return null;
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(vehicle.Make__c)) {
            parts.add(vehicle.Make__c);
        }
        if (String.isNotBlank(vehicle.Model__c)) {
            parts.add(vehicle.Model__c);
        }
        String makeModel = String.join(parts, ' ');
        return String.isBlank(makeModel) ? vehicle.Name : vehicle.Name + ' — ' + makeModel;
    }

    private static void insertLineItems(Id billId, List<LineItemInput> lineItems) {
        List<Bill_Line_Item__c> items = new List<Bill_Line_Item__c>();
        for (LineItemInput li : lineItems) {
            items.add(new Bill_Line_Item__c(
                Bill__c = billId,
                Part__c = li.partId,
                Description__c = li.description,
                Quantity__c = li.quantity,
                Unit_Price__c = li.unitPrice,
                Tax_Rate_Percent__c = li.taxRatePercent == null ? 0 : li.taxRatePercent,
                Gst_Type__c = String.isBlank(li.gstType) ? 'CGST_SGST' : li.gstType,
                HSN_SAC_Code__c = li.hsnSacCode,
                Unit__c = li.unitLabel
            ));
        }
        insert items;
    }

    private static void insertInitialPayment(Id billId, CreateBillRequest request) {
        if (request.initialPaymentAmount != null && request.initialPaymentAmount > 0) {
            insert new Payment__c(
                Bill__c = billId,
                Amount__c = request.initialPaymentAmount,
                Method__c = String.isBlank(request.initialPaymentMethod) ? 'Cash' : request.initialPaymentMethod,
                Paid_At__c = Datetime.now()
            );
        }
    }

    private static BillSummary buildSummary(Id billId) {
        Bill__c bill = [
            SELECT Invoice_Number__c, Financial_Year__c, Status__c, Bill_Date__c,
                   Version_Number__c, Is_Latest_Version__c, Source_Estimate__c, Job__c,
                   Customer__c, Customer__r.Name, Bill_To_Party__c, Bill_To_Party__r.Name,
                   Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c, Notes__c,
                   Subtotal__c, GST_Amount__c, Total_Amount__c
            FROM Bill__c
            WHERE Id = :billId
        ];

        List<LineItemInput> lineItemInputs = new List<LineItemInput>();
        List<GstCalculatorService.GstLineItemInput> gstInputs = new List<GstCalculatorService.GstLineItemInput>();
        for (Bill_Line_Item__c item : [
            SELECT Part__c, Description__c, Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c, HSN_SAC_Code__c, Unit__c
            FROM Bill_Line_Item__c
            WHERE Bill__c = :billId
        ]) {
            gstInputs.add(new GstCalculatorService.GstLineItemInput(
                item.Description__c,
                item.Quantity__c,
                item.Unit_Price__c,
                item.Tax_Rate_Percent__c,
                GstCalculatorService.supplyTypeFromGstType(item.Gst_Type__c)
            ));
            LineItemInput li = new LineItemInput();
            li.partId = item.Part__c;
            li.description = item.Description__c;
            li.quantity = item.Quantity__c;
            li.unitPrice = item.Unit_Price__c;
            li.taxRatePercent = item.Tax_Rate_Percent__c;
            li.gstType = item.Gst_Type__c;
            li.hsnSacCode = item.HSN_SAC_Code__c;
            li.unitLabel = item.Unit__c;
            lineItemInputs.add(li);
        }
        GstCalculatorService.GstBillResult breakdown = GstCalculatorService.calculateBill(gstInputs);

        BillSummary summary = new BillSummary();
        summary.billId = billId;
        summary.jobId = bill.Job__c;
        summary.invoiceNumber = bill.Invoice_Number__c;
        summary.financialYear = bill.Financial_Year__c;
        summary.status = bill.Status__c;
        summary.billDate = bill.Bill_Date__c;
        summary.versionNumber = bill.Version_Number__c == null ? 1 : bill.Version_Number__c.intValue();
        summary.isLatestVersion = bill.Is_Latest_Version__c;
        summary.sourceEstimateId = bill.Source_Estimate__c;
        summary.customerId = bill.Customer__c;
        summary.customerName = bill.Customer__r != null ? bill.Customer__r.Name : null;
        summary.billToPartyId = bill.Bill_To_Party__c;
        summary.billToPartyName = bill.Bill_To_Party__r != null ? bill.Bill_To_Party__r.Name : null;
        summary.vehicleId = bill.Vehicle__c;
        summary.vehicleLabel = vehicleLabel(bill.Vehicle__c, bill.Vehicle__r);
        summary.notes = bill.Notes__c;
        summary.subtotal = bill.Subtotal__c;
        summary.cgst = breakdown.cgst;
        summary.sgst = breakdown.sgst;
        summary.igst = breakdown.igst;
        summary.totalAmount = bill.Total_Amount__c;
        summary.lineItems = lineItemInputs;

        List<PaymentItem> paymentItems = new List<PaymentItem>();
        Decimal paid = 0;
        for (Payment__c payment : [
            SELECT Amount__c, Method__c, Paid_At__c
            FROM Payment__c
            WHERE Bill__c = :billId
            ORDER BY Paid_At__c
        ]) {
            PaymentItem item = new PaymentItem();
            item.id = payment.Id;
            item.amount = payment.Amount__c;
            item.method = payment.Method__c;
            item.paidAt = payment.Paid_At__c;
            paymentItems.add(item);
            paid += payment.Amount__c == null ? 0 : payment.Amount__c;
        }
        summary.payments = paymentItems;
        summary.amountPaid = paid;
        summary.amountDue = (bill.Total_Amount__c == null ? 0 : bill.Total_Amount__c) - paid;

        return summary;
    }
}
