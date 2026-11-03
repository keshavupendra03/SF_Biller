/**
 * Backs the Quick Bill screen — one screen to bill a counter sale (spare
 * parts over the counter) or any car customer without first setting up a
 * customer/vehicle through the Customers screens.
 *
 * Bill__c.Customer__c and Customer__c.Phone__c stay required, so this
 * resolves the customer itself rather than relaxing the schema:
 *  - walk-in: every walk-in sale is billed to one shared "Walk-in
 *    Customer" record (found or created on first use);
 *  - otherwise the phone number is the customer's identity — an existing
 *    customer with that number is reused (blank details are filled in
 *    from what was typed), else a new one is created.
 * A vehicle is optional; a typed registration number reuses that
 * customer's existing vehicle with the same number, else creates one.
 * The bill itself goes through BillController.createBill, so invoice
 * numbering, stock deduction and manual-line part creation behave
 * exactly as on the New Bill screen.
 *
 * GST is off unless the request says includeGst. Lines still arrive with
 * the rate typed on screen: a part created from a typed line must remember
 * that rate for later bills, so parts are resolved first and only the
 * bill's own lines drop to 0%.
 */
public with sharing class QuickBillController {

    public class QuickBillControllerException extends Exception {}

    public static final String WALK_IN_NAME = 'Walk-in Customer';
    // Customer__c.Phone__c is required; InvoicePdfController leaves this
    // placeholder off the printed invoice.
    public static final String WALK_IN_PHONE = '0000000000';

    public class CustomerMatch {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String gstin { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public List<CustomerController.VehicleItem> vehicles { get; set; }
    }

    public class QuickBillRequest {
        @AuraEnabled public Boolean isWalkIn { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String customerPhone { get; set; }
        @AuraEnabled public String customerAddress { get; set; }
        @AuraEnabled public String customerGstin { get; set; }
        @AuraEnabled public String customerState { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public CustomerController.NewVehicleInput newVehicle { get; set; }
        @AuraEnabled public Date billDate { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Boolean includeGst { get; set; }
        @AuraEnabled public List<BillController.LineItemInput> lineItems { get; set; }
    }

    /**
     * Called as staff type a phone number, so the screen can show "existing
     * customer" and offer their vehicles before the bill is created.
     * Returns null when no customer has this number.
     */
    @AuraEnabled
    public static CustomerMatch findCustomerByPhone(String phone) {
        Customer__c customer = findByPhone(phone);
        if (customer == null) {
            return null;
        }
        CustomerMatch match = new CustomerMatch();
        match.id = customer.Id;
        match.name = customer.Name;
        match.phone = customer.Phone__c;
        match.address = customer.Address__c;
        match.gstin = customer.GSTIN__c;
        match.state = customer.State__c;
        match.vehicles = CustomerController.listVehiclesForCustomer(customer.Id);
        return match;
    }

    @AuraEnabled
    public static BillController.BillSummary createQuickBill(QuickBillRequest request) {
        if (request == null || request.lineItems == null || request.lineItems.isEmpty()) {
            throw new QuickBillControllerException('Add at least one item to the bill.');
        }
        Boolean walkIn = request.isWalkIn == true;
        Id customerId = walkIn ? walkInCustomerId() : resolveCustomer(request);

        PartUpsertService.fillManualPartIds(request.lineItems);
        if (request.includeGst != true) {
            for (BillController.LineItemInput line : request.lineItems) {
                line.taxRatePercent = 0;
            }
        }

        BillController.CreateBillRequest bill = new BillController.CreateBillRequest();
        bill.customerId = customerId;
        bill.billDate = request.billDate;
        bill.notes = request.notes;
        bill.lineItems = request.lineItems;
        if (!walkIn) {
            bill.vehicleId = resolveVehicleId(customerId, request);
            if (bill.vehicleId == null) {
                bill.newVehicle = hasRegistration(request.newVehicle) ? request.newVehicle : null;
            }
        }
        return BillController.createBill(bill);
    }

    private static Id resolveCustomer(QuickBillRequest request) {
        if (String.isBlank(request.customerPhone)) {
            throw new QuickBillControllerException('Enter the customer\'s phone number, or switch to Walk-in.');
        }
        Customer__c existing = findByPhone(request.customerPhone);
        if (existing == null) {
            if (String.isBlank(request.customerName)) {
                throw new QuickBillControllerException('Enter the customer\'s name.');
            }
            Customer__c created = new Customer__c(
                Name = request.customerName.trim(),
                Phone__c = request.customerPhone.trim(),
                Address__c = request.customerAddress,
                GSTIN__c = request.customerGstin,
                State__c = request.customerState
            );
            insert created;
            return created.Id;
        }

        // Fill in details the customer record doesn't have yet; never
        // overwrite what's already saved from a quick, counter-side entry.
        Customer__c updates = new Customer__c(Id = existing.Id);
        Boolean changed = false;
        if (String.isBlank(existing.Address__c) && String.isNotBlank(request.customerAddress)) {
            updates.Address__c = request.customerAddress;
            changed = true;
        }
        if (String.isBlank(existing.GSTIN__c) && String.isNotBlank(request.customerGstin)) {
            updates.GSTIN__c = request.customerGstin;
            changed = true;
        }
        if (String.isBlank(existing.State__c) && String.isNotBlank(request.customerState)) {
            updates.State__c = request.customerState;
            changed = true;
        }
        if (changed) {
            update updates;
        }
        return existing.Id;
    }

    private static Id resolveVehicleId(Id customerId, QuickBillRequest request) {
        if (request.vehicleId != null) {
            Vehicle__c vehicle = [SELECT Customer__c FROM Vehicle__c WHERE Id = :request.vehicleId];
            if (vehicle.Customer__c != customerId) {
                throw new QuickBillControllerException('That vehicle belongs to a different customer.');
            }
            return vehicle.Id;
        }
        if (!hasRegistration(request.newVehicle)) {
            return null;
        }
        // SOQL "=" is case-insensitive, so "mp09ab1234" matches "MP09AB1234".
        String registration = request.newVehicle.registrationNumber.trim();
        List<Vehicle__c> existing = [
            SELECT Id FROM Vehicle__c WHERE Customer__c = :customerId AND Name = :registration LIMIT 1
        ];
        return existing.isEmpty() ? null : existing[0].Id;
    }

    private static Boolean hasRegistration(CustomerController.NewVehicleInput vehicle) {
        return vehicle != null && String.isNotBlank(vehicle.registrationNumber);
    }

    private static Id walkInCustomerId() {
        List<Customer__c> existing = [
            SELECT Id FROM Customer__c WHERE Name = :WALK_IN_NAME AND Phone__c = :WALK_IN_PHONE
            ORDER BY CreatedDate LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        Customer__c walkIn = new Customer__c(Name = WALK_IN_NAME, Phone__c = WALK_IN_PHONE);
        insert walkIn;
        return walkIn.Id;
    }

    // Matches however the number was saved: as typed, digits only, the
    // last 10 digits, or with +91 in front.
    private static Customer__c findByPhone(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String digits = phone.replaceAll('[^0-9]', '');
        if (digits.length() < 6) {
            return null;
        }
        String lastTen = digits.right(10);
        Set<String> candidates = new Set<String>{ phone.trim(), digits, lastTen, '+91' + lastTen, '+91 ' + lastTen, '0' + lastTen };
        candidates.remove(WALK_IN_PHONE);
        List<Customer__c> matches = [
            SELECT Id, Name, Phone__c, Address__c, GSTIN__c, State__c
            FROM Customer__c
            WHERE Phone__c IN :candidates
            ORDER BY CreatedDate
            LIMIT 1
        ];
        return matches.isEmpty() ? null : matches[0];
    }
}
