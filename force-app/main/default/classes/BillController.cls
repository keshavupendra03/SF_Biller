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
 * unaffected by any of this). A bill's lines and payments are stored on the
 * bill itself (StoredLines, BillPayments), not as child records, to save
 * data storage (architecture.md, Forty-second). createNewVersion reverses
 * the superseded version's stock deductions (BillStockService, as deleting
 * a bill does) before the new version's own lines deduct stock again — otherwise a near-identical new version would double
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
        // Rupees off before GST.
        @AuraEnabled public Decimal discount { get; set; }
    }

    public class NewBillToPartyInput {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String contactPhone { get; set; }
        @AuraEnabled public String gstin { get; set; }
        @AuraEnabled public String state { get; set; }
    }

    public class CreateBillRequest {
        // The company this bill is for. Blank means the source estimate's
        // company if there is one, else the primary company.
        @AuraEnabled public Id workshopProfileId { get; set; }
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public Id jobId { get; set; }
        @AuraEnabled public Id billToPartyId { get; set; }
        @AuraEnabled public NewBillToPartyInput newBillToParty { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public CustomerController.NewVehicleInput newVehicle { get; set; }
        // The customer's half of an insurance claim pair: no stock, no part links.
        @AuraEnabled public Boolean takesNoStock { get; set; }
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
        // Its place on the bill ('p1', 'p2'...): payments are stored on the bill.
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String method { get; set; }
        @AuraEnabled public Datetime paidAt { get; set; }
    }

    public class BillListItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String invoiceNumber { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String billToPartyName { get; set; }
        @AuraEnabled public String companyName { get; set; }
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
        @AuraEnabled public Id workshopProfileId { get; set; }
        // Only set when the workshop has two companies.
        @AuraEnabled public String companyName { get; set; }
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public Id billToPartyId { get; set; }
        @AuraEnabled public String billToPartyName { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public String vehicleLabel { get; set; }
        @AuraEnabled public String vehicleChassisNumber { get; set; }
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
        // Deleted: kept, and reported for GST as a cancelled number.
        @AuraEnabled public Boolean isCancelled { get; set; }
        @AuraEnabled public Date cancelledOn { get; set; }
        // Dated in a month whose GST is filed: can't be changed or deleted.
        @AuraEnabled public Boolean isGstFiled { get; set; }
        @AuraEnabled public Date gstFiledUpTo { get; set; }
        @AuraEnabled public Decimal roundOff { get; set; }
        // An insurance claim's other bill (the customer's share, or the insurer's).
        @AuraEnabled public Id pairedBillId { get; set; }
        @AuraEnabled public String pairedInvoiceNumber { get; set; }
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
        // A save error (a bad GSTIN, a future date) is shown in its own words.
        try {
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
        } catch (DmlException e) {
            throw ReadableErrors.of(e);
        }
    }

    @AuraEnabled
    public static BillSummary createBill(CreateBillRequest request) {
        // A save error (a bad GSTIN, a future date) is shown in its own words.
        try {
            validate(request);
            // The customer's share of an insurance claim: its goods are on the
            // insurer's bill, which takes the stock, so its lines link no part.
            if (request.takesNoStock != true) {
                PartUpsertService.fillManualPartIds(request.lineItems);
            }
            prepareLines(companyFor(request), request.lineItems);
            Id billToPartyId = resolveBillToPartyId(request.billToPartyId, request.newBillToParty);
            Id vehicleId = resolveVehicleId(request.customerId, request.vehicleId, request.newVehicle);

            Bill__c bill = new Bill__c(
                Workshop_Profile__c = companyFor(request),
                Customer__c = request.customerId,
                Job__c = request.jobId,
                Bill_To_Party__c = billToPartyId,
                Vehicle__c = vehicleId,
                Notes__c = request.notes,
                Bill_Date__c = request.billDate != null ? request.billDate : Date.today(),
                Source_Estimate__c = request.sourceEstimateId
            );
            saveWithLines(bill, request);

            if (request.sourceEstimateId != null) {
                update new Estimate__c(Id = request.sourceEstimateId, Status__c = 'Converted');
            }

            return buildSummary(bill.Id);
        } catch (DmlException e) {
            throw ReadableErrors.of(e);
        }
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
        // A save error (a bad GSTIN, a future date) is shown in its own words.
        try {
            validate(request);
            Bill__c previous = [
                SELECT Version_Number__c, Root_Bill__c, Source_Estimate__c, Job__c, Vehicle__c, Workshop_Profile__c,
                       Invoice_Number__c, Bill_Date__c, Is_Cancelled__c, Paired_Bill__c, Bill_To_Party__c, Line_Items__c
                FROM Bill__c
                WHERE Id = :previousBillId
            ];
            // A new version replaces the bill's number, so not for a deleted
            // bill, or one in a month whose GST is already filed.
            if (previous.Is_Cancelled__c) {
                throw new BillControllerException(previous.Invoice_Number__c + ' was deleted, so it can\'t be changed.');
            }
            GstFilingLock.requireOpen(previous.Workshop_Profile__c, previous.Bill_Date__c, 'changed');
            prepareLines(previous.Workshop_Profile__c, request.lineItems);
            // The customer's half of an insurance claim (G6) links no parts: its
            // goods are on the insurer's bill, which took the stock.
            Boolean customerHalf = previous.Paired_Bill__c != null && previous.Bill_To_Party__c == null;
            if (customerHalf) {
                for (LineItemInput line : request.lineItems) {
                    line.partId = null;
                }
            } else {
                PartUpsertService.fillManualPartIds(request.lineItems);
            }
            Id rootId = previous.Root_Bill__c != null ? previous.Root_Bill__c : previousBillId;

            BillStockService.restore(StoredLines.read(previous.Line_Items__c));

            Id billToPartyId = resolveBillToPartyId(request.billToPartyId, request.newBillToParty);
            Id vehicleId = request.vehicleId != null || request.newVehicle != null
                ? resolveVehicleId(request.customerId, request.vehicleId, request.newVehicle)
                : previous.Vehicle__c;

            // A later version stays with its company and invoice series, whatever
            // the request says.
            Bill__c newVersion = new Bill__c(
                Workshop_Profile__c = previous.Workshop_Profile__c,
                Customer__c = request.customerId,
                Job__c = request.jobId != null ? request.jobId : previous.Job__c,
                Bill_To_Party__c = billToPartyId,
                Vehicle__c = vehicleId,
                Notes__c = request.notes,
                Bill_Date__c = request.billDate != null ? request.billDate : Date.today(),
                Source_Estimate__c = request.sourceEstimateId != null ? request.sourceEstimateId : previous.Source_Estimate__c,
                Previous_Version__c = previousBillId,
                Root_Bill__c = rootId,
                Paired_Bill__c = previous.Paired_Bill__c,
                Version_Number__c = (previous.Version_Number__c == null ? 1 : previous.Version_Number__c) + 1
            );
            saveWithLines(newVersion, request);
            // The other half of the claim now points at this version.
            if (previous.Paired_Bill__c != null) {
                update new Bill__c(Id = previous.Paired_Bill__c, Paired_Bill__c = newVersion.Id);
            }

            update new Bill__c(Id = previousBillId, Is_Latest_Version__c = false);

            return buildSummary(newVersion.Id);
        } catch (DmlException e) {
            throw ReadableErrors.of(e);
        }
    }

    /**
     * "Delete" for a bill (architecture.md §D.1, G2). A bill's number has been
     * issued, and GSTR-1 reports every number issued, so a bill is never really
     * deleted: it's cancelled, keeping its number to be reported as cancelled,
     * and its parts go back to stock. It then drops out of the Billing list,
     * customer and job screens, and revenue. Only the latest version, only
     * once, and not in a month whose GST is filed.
     */
    @AuraEnabled
    public static BillSummary cancelBill(Id billId) {
        Bill__c bill = [
            SELECT Invoice_Number__c, Is_Latest_Version__c, Is_Cancelled__c, Bill_Date__c, Workshop_Profile__c, Line_Items__c
            FROM Bill__c WHERE Id = :billId FOR UPDATE
        ];
        if (bill.Is_Cancelled__c) {
            throw new BillControllerException(bill.Invoice_Number__c + ' is already deleted.');
        }
        if (!bill.Is_Latest_Version__c) {
            throw new BillControllerException(bill.Invoice_Number__c + ' has been changed since. Delete its latest version from the Billing list.');
        }
        GstFilingLock.requireOpen(bill.Workshop_Profile__c, bill.Bill_Date__c, 'deleted');
        BillStockService.restore(StoredLines.read(bill.Line_Items__c));
        update new Bill__c(Id = billId, Is_Cancelled__c = true, Cancelled_On__c = Date.today());
        return buildSummary(billId);
    }

    @AuraEnabled
    public static BillSummary getBillSummary(Id billId) {
        return buildSummary(billId);
    }

    /**
     * Records a payment against an existing bill outside of create/version
     * time (the Bill Details screen's "Record Payment" action). BillPayments
     * locks the bill row, adds the payment and recomputes Status__c.
     */
    @AuraEnabled
    public static BillSummary recordPayment(Id billId, Decimal amount, String method) {
        if (billId == null || amount == null || amount <= 0) {
            throw new BillControllerException('A positive payment amount is required.');
        }
        try {
            BillPayments.add(billId, amount, method);
        } catch (BillPayments.BillPaymentsException e) {
            throw new BillControllerException(e.getMessage());
        }
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
    public static List<BillListItem> listBills(String filter, String searchTerm, Id workshopProfileId) {
        Boolean duesOnly = 'DuesOnly'.equals(filter);
        // Deleted bills only on asking for them ('Cancelled'), and then only them.
        Boolean cancelledOnly = 'Cancelled'.equals(filter);
        String term = '%' + String.escapeSingleQuotes(String.isBlank(searchTerm) ? '' : searchTerm) + '%';
        Boolean hasSearch = String.isNotBlank(searchTerm);

        String soql = 'SELECT Invoice_Number__c, Customer__r.Name, Bill_To_Party__r.Name, Total_Amount__c, Status__c, Bill_Date__c, Workshop_Profile__c'
            + ' FROM Bill__c WHERE Is_Latest_Version__c = true AND Is_Cancelled__c = :cancelledOnly';
        if (duesOnly) {
            soql += ' AND Status__c != \'Paid\'';
        }
        if (hasSearch) {
            soql += ' AND (Invoice_Number__c LIKE :term OR Customer__r.Name LIKE :term OR Customer__r.Phone__c LIKE :term'
                + ' OR Bill_To_Party__r.Name LIKE :term)';
        }
        if (workshopProfileId != null) {
            // A bill with no company recorded belongs to the primary company.
            Id orNoCompany = workshopProfileId == WorkshopProfileService.primaryId() ? null : workshopProfileId;
            soql += ' AND (Workshop_Profile__c = :workshopProfileId OR Workshop_Profile__c = :orNoCompany)';
        }
        List<Bill__c> bills = Database.query(soql + ' ORDER BY CreatedDate DESC LIMIT 200');
        Map<Id, String> companyNames = WorkshopProfileService.companyNames();

        List<BillListItem> results = new List<BillListItem>();
        for (Bill__c b : bills) {
            BillListItem item = new BillListItem();
            item.id = b.Id;
            item.invoiceNumber = b.Invoice_Number__c;
            item.customerName = b.Customer__r != null ? b.Customer__r.Name : null;
            item.billToPartyName = b.Bill_To_Party__r != null ? b.Bill_To_Party__r.Name : null;
            item.companyName = companyNames.get(b.Workshop_Profile__c);
            item.totalAmount = b.Total_Amount__c;
            item.status = b.Status__c;
            item.billDate = b.Bill_Date__c;
            results.add(item);
        }
        return results;
    }

    private static Id companyFor(CreateBillRequest request) {
        if (request.workshopProfileId != null || request.sourceEstimateId == null) {
            return request.workshopProfileId;
        }
        return [SELECT Workshop_Profile__c FROM Estimate__c WHERE Id = :request.sourceEstimateId].Workshop_Profile__c;
    }

    private static void validate(CreateBillRequest request) {
        if (request == null || request.customerId == null) {
            throw new BillControllerException('A customer is required.');
        }
        GstRules.requireGstRates(request.lineItems);
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
                Color__c = newVehicle.color,
                Chassis_Number__c = newVehicle.chassisNumber
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

    /**
     * Saves a new bill (or version) with its lines, totals and any first
     * payment on the one record (StoredLines, BillPayments), then takes its
     * parts out of stock.
     */
    private static void saveWithLines(Bill__c bill, CreateBillRequest request) {
        try {
            StoredLines.store(bill, bill.Workshop_Profile__c, request.lineItems);
            if (request.initialPaymentAmount != null && request.initialPaymentAmount > 0) {
                BillPayments.addFirst(bill, request.initialPaymentAmount, request.initialPaymentMethod);
            }
        } catch (StoredLines.StoredLinesException e) {
            throw new BillControllerException(e.getMessage());
        } catch (BillPayments.BillPaymentsException e) {
            throw new BillControllerException(e.getMessage());
        }
        insert bill;
        BillStockService.deduct(StoredLines.read(bill.Line_Items__c));
    }

    /**
     * A discount is rupees off a line, never more than the line itself. And a
     * company that doesn't charge GST (composition, or not registered) gets no
     * GST on any line, whatever the screen sent.
     */
    public static void prepareLines(Id companyId, List<LineItemInput> lineItems) {
        for (LineItemInput li : lineItems) {
            Decimal discount = li.discount == null ? 0 : li.discount;
            Decimal gross = (li.quantity == null ? 0 : li.quantity) * (li.unitPrice == null ? 0 : li.unitPrice);
            if (discount < 0 || discount > gross) {
                throw new BillControllerException('The discount on "' + li.description + '" must be between 0 and its price (Rs. ' + gross.setScale(2) + ').');
            }
        }
        if (!WorkshopProfileService.chargesGst(companyId)) {
            for (LineItemInput li : lineItems) {
                li.taxRatePercent = 0;
            }
        }
    }

    private static BillSummary buildSummary(Id billId) {
        Bill__c bill = [
            SELECT Invoice_Number__c, Financial_Year__c, Status__c, Bill_Date__c,
                   Version_Number__c, Is_Latest_Version__c, Source_Estimate__c, Job__c,
                   Customer__c, Customer__r.Name, Bill_To_Party__c, Bill_To_Party__r.Name,
                   Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                   Vehicle__r.Chassis_Number__c, Notes__c,
                   Subtotal__c, GST_Amount__c, Total_Amount__c, Workshop_Profile__c,
                   Is_Cancelled__c, Cancelled_On__c, Round_Off__c, Paired_Bill__c, Paired_Bill__r.Invoice_Number__c,
                   Line_Items__c, Payments__c
            FROM Bill__c
            WHERE Id = :billId
        ];

        List<LineItemInput> lineItemInputs = StoredLines.read(bill.Line_Items__c);
        GstCalculatorService.GstBillResult breakdown = GstCalculatorService.calculateBill(StoredLines.gstInputs(lineItemInputs));

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
        summary.workshopProfileId = bill.Workshop_Profile__c;
        summary.companyName = WorkshopProfileService.companyNames().get(bill.Workshop_Profile__c);
        summary.customerId = bill.Customer__c;
        summary.customerName = bill.Customer__r != null ? bill.Customer__r.Name : null;
        summary.billToPartyId = bill.Bill_To_Party__c;
        summary.billToPartyName = bill.Bill_To_Party__r != null ? bill.Bill_To_Party__r.Name : null;
        summary.isCancelled = bill.Is_Cancelled__c;
        summary.roundOff = bill.Round_Off__c == null ? 0 : bill.Round_Off__c;
        summary.pairedBillId = bill.Paired_Bill__c;
        summary.pairedInvoiceNumber = bill.Paired_Bill__c == null ? null : bill.Paired_Bill__r.Invoice_Number__c;
        summary.cancelledOn = bill.Cancelled_On__c;
        summary.gstFiledUpTo = GstFilingLock.filedUpTo(bill.Workshop_Profile__c);
        summary.isGstFiled = GstFilingLock.isLocked(summary.gstFiledUpTo, bill.Bill_Date__c);
        summary.vehicleId = bill.Vehicle__c;
        summary.vehicleLabel = vehicleLabel(bill.Vehicle__c, bill.Vehicle__r);
        summary.vehicleChassisNumber = bill.Vehicle__c != null ? bill.Vehicle__r.Chassis_Number__c : null;
        summary.notes = bill.Notes__c;
        summary.subtotal = bill.Subtotal__c;
        summary.cgst = breakdown.cgst;
        summary.sgst = breakdown.sgst;
        summary.igst = breakdown.igst;
        summary.totalAmount = bill.Total_Amount__c;
        summary.lineItems = lineItemInputs;

        List<PaymentItem> paymentItems = new List<PaymentItem>();
        List<BillPayments.Payment> payments = BillPayments.read(bill.Payments__c);
        for (BillPayments.Payment payment : payments) {
            PaymentItem item = new PaymentItem();
            item.id = 'p' + (paymentItems.size() + 1);
            item.amount = payment.amount;
            item.method = payment.method;
            item.paidAt = payment.paidAt;
            paymentItems.add(item);
        }
        Decimal paid = BillPayments.sum(payments);
        summary.payments = paymentItems;
        summary.amountPaid = paid;
        summary.amountDue = (bill.Total_Amount__c == null ? 0 : bill.Total_Amount__c) - paid;

        return summary;
    }
}
