/**
 * Backs the Easy Bill screen: a screen laid out like the printed bill, for
 * staff who find forms hard, where every box is typed straight onto the page.
 * It saves a normal Bill__c or Estimate__c through BillController /
 * EstimateController, so numbering, stock and totals work as everywhere else.
 *
 * InvoicePdf.page prints the customer, vehicle and workshop live from their
 * records, so what's typed has to reach those records for the print to match
 * the screen. That's why, unlike Quick Bill, a customer or vehicle already
 * picked on screen is overwritten with what's on the page, blanks included.
 * Details typed without picking anyone only fill in or replace non-blank
 * values, because staff never saw what was already saved.
 */
public with sharing class PaperBillController {

    public class PaperBillControllerException extends Exception {}

    public class PaperRequest {
        @AuraEnabled public String documentType { get; set; }
        @AuraEnabled public Id workshopProfileId { get; set; }
        // Set when an existing customer/vehicle was picked or matched on screen.
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String customerPhone { get; set; }
        @AuraEnabled public String customerAddress { get; set; }
        @AuraEnabled public String customerGstin { get; set; }
        @AuraEnabled public String customerState { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public String registrationNumber { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String chassisNumber { get; set; }
        @AuraEnabled public Date documentDate { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Boolean includeGst { get; set; }
        @AuraEnabled public List<BillController.LineItemInput> lineItems { get; set; }
        // Only sent when the workshop details were unlocked and edited.
        @AuraEnabled public WorkshopProfileController.ProfileData workshop { get; set; }
    }

    public class SavedDocument {
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public String documentNumber { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
    }

    @AuraEnabled
    public static QuickBillController.CustomerMatch getCustomer(Id customerId) {
        Customer__c customer = [
            SELECT Id, Name, Phone__c, Address__c, GSTIN__c, State__c FROM Customer__c WHERE Id = :customerId
        ];
        QuickBillController.CustomerMatch match = QuickBillController.toMatch(customer);
        // A placeholder, not a number to show or print.
        if (match.phone == QuickBillController.WALK_IN_PHONE) {
            match.phone = null;
        }
        return match;
    }

    @AuraEnabled
    public static String amountInWords(Decimal amount) {
        return amount == null ? '' : AmountInWordsService.convert(amount);
    }

    @AuraEnabled
    public static SavedDocument saveDocument(PaperRequest request) {
        if (request == null || request.lineItems == null || request.lineItems.isEmpty()) {
            throw new PaperBillControllerException('Add at least one item.');
        }
        Id companyId = request.workshopProfileId;
        if (request.workshop != null) {
            companyId = WorkshopProfileController.saveProfile(request.workshop).id;
        }
        Id customerId = resolveCustomer(request);
        Id vehicleId = resolveVehicle(customerId, request);

        // Parts first: an item typed on a no-GST bill must still remember its
        // typed rate for later bills (same order as QuickBillController).
        PartUpsertService.fillManualPartIds(request.lineItems);
        if (request.includeGst != true) {
            for (BillController.LineItemInput line : request.lineItems) {
                line.taxRatePercent = 0;
            }
        }

        SavedDocument saved = new SavedDocument();
        if (request.documentType == 'estimate') {
            EstimateController.CreateEstimateRequest estimate = new EstimateController.CreateEstimateRequest();
            estimate.workshopProfileId = companyId;
            estimate.customerId = customerId;
            estimate.vehicleId = vehicleId;
            estimate.estimateDate = request.documentDate;
            estimate.notes = request.notes;
            estimate.lineItems = request.lineItems;
            EstimateController.EstimateSummary summary = EstimateController.createEstimate(estimate);
            saved.recordId = summary.estimateId;
            saved.documentNumber = summary.estimateNumber;
            saved.customerName = summary.customerName;
            saved.totalAmount = summary.totalAmount;
            return saved;
        }
        BillController.CreateBillRequest bill = new BillController.CreateBillRequest();
        bill.workshopProfileId = companyId;
        bill.customerId = customerId;
        bill.vehicleId = vehicleId;
        bill.billDate = request.documentDate;
        bill.notes = request.notes;
        bill.lineItems = request.lineItems;
        BillController.BillSummary summary = BillController.createBill(bill);
        saved.recordId = summary.billId;
        saved.documentNumber = summary.invoiceNumber;
        saved.customerName = summary.customerName;
        saved.totalAmount = summary.totalAmount;
        return saved;
    }

    private static Id resolveCustomer(PaperRequest request) {
        String name = String.isBlank(request.customerName) ? null : request.customerName.trim();
        String phone = String.isBlank(request.customerPhone) ? null : request.customerPhone.trim();

        if (request.customerId != null) {
            Customer__c picked = new Customer__c(
                Id = request.customerId,
                Address__c = request.customerAddress,
                GSTIN__c = request.customerGstin,
                State__c = request.customerState
            );
            if (name != null) {
                picked.Name = name;
            }
            if (phone != null) {
                picked.Phone__c = phone;
            }
            update picked;
            return picked.Id;
        }

        Customer__c existing;
        if (phone != null) {
            existing = QuickBillController.findByPhone(phone);
        } else if (name == null) {
            return QuickBillController.walkInCustomerId();
        } else {
            // A name with no number: reuse that name, so regular buyers who
            // never give a number don't become a new customer on every bill.
            List<Customer__c> sameName = [
                SELECT Id FROM Customer__c
                WHERE Name = :name AND Phone__c = :QuickBillController.WALK_IN_PHONE
                ORDER BY CreatedDate LIMIT 1
            ];
            existing = sameName.isEmpty() ? null : sameName[0];
        }

        if (existing == null) {
            if (name == null) {
                throw new PaperBillControllerException('Type the customer name.');
            }
            Customer__c created = new Customer__c(
                Name = name,
                Phone__c = phone != null ? phone : QuickBillController.WALK_IN_PHONE,
                Address__c = request.customerAddress,
                GSTIN__c = request.customerGstin,
                State__c = request.customerState
            );
            insert created;
            return created.Id;
        }

        Customer__c changes = new Customer__c(Id = existing.Id);
        if (name != null) {
            changes.Name = name;
        }
        if (String.isNotBlank(request.customerAddress)) {
            changes.Address__c = request.customerAddress;
        }
        if (String.isNotBlank(request.customerGstin)) {
            changes.GSTIN__c = request.customerGstin;
        }
        if (String.isNotBlank(request.customerState)) {
            changes.State__c = request.customerState;
        }
        update changes;
        return existing.Id;
    }

    private static Id resolveVehicle(Id customerId, PaperRequest request) {
        String registration = String.isBlank(request.registrationNumber) ? null : request.registrationNumber.trim();

        if (request.vehicleId != null) {
            Vehicle__c picked = [SELECT Customer__c FROM Vehicle__c WHERE Id = :request.vehicleId];
            if (picked.Customer__c != customerId) {
                throw new PaperBillControllerException('That vehicle belongs to a different customer.');
            }
            Vehicle__c changes = new Vehicle__c(
                Id = picked.Id,
                Make__c = request.make,
                Model__c = request.model,
                Chassis_Number__c = request.chassisNumber
            );
            if (registration != null) {
                changes.Name = registration;
            }
            update changes;
            VehicleMakeModelService.rememberIfNew(request.make, request.model);
            return picked.Id;
        }

        if (registration == null) {
            if (String.isNotBlank(request.make) || String.isNotBlank(request.model) || String.isNotBlank(request.chassisNumber)) {
                throw new PaperBillControllerException('Type the vehicle number, or clear the vehicle details.');
            }
            return null;
        }

        // SOQL "=" is case-insensitive, so "mp09ab1234" matches "MP09AB1234".
        List<Vehicle__c> sameNumber = [
            SELECT Id FROM Vehicle__c WHERE Customer__c = :customerId AND Name = :registration LIMIT 1
        ];
        if (sameNumber.isEmpty()) {
            CustomerController.NewVehicleInput vehicle = new CustomerController.NewVehicleInput();
            vehicle.registrationNumber = registration;
            vehicle.make = request.make;
            vehicle.model = request.model;
            vehicle.chassisNumber = request.chassisNumber;
            return CustomerController.createVehicle(customerId, vehicle).id;
        }

        Vehicle__c changes = new Vehicle__c(Id = sameNumber[0].Id);
        if (String.isNotBlank(request.make)) {
            changes.Make__c = request.make;
        }
        if (String.isNotBlank(request.model)) {
            changes.Model__c = request.model;
        }
        if (String.isNotBlank(request.chassisNumber)) {
            changes.Chassis_Number__c = request.chassisNumber;
        }
        update changes;
        VehicleMakeModelService.rememberIfNew(request.make, request.model);
        return changes.Id;
    }
}
