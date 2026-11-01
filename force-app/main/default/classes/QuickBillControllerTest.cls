@isTest
private class QuickBillControllerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static BillController.LineItemInput line(String description, Decimal qty, Decimal price) {
        BillController.LineItemInput li = new BillController.LineItemInput();
        li.description = description;
        li.quantity = qty;
        li.unitPrice = price;
        li.taxRatePercent = 18;
        li.gstType = 'CGST_SGST';
        return li;
    }

    private static QuickBillController.QuickBillRequest request() {
        QuickBillController.QuickBillRequest r = new QuickBillController.QuickBillRequest();
        r.lineItems = new List<BillController.LineItemInput>{ line('Engine Oil 1L', 2, 500) };
        return r;
    }

    @isTest
    static void walkIn_billsTheSharedWalkInCustomer_andReusesIt() {
        QuickBillController.QuickBillRequest r = request();
        r.isWalkIn = true;

        Test.startTest();
        BillController.BillSummary first = QuickBillController.createQuickBill(r);
        BillController.BillSummary second = QuickBillController.createQuickBill(r);
        Test.stopTest();

        System.assert(first.invoiceNumber.startsWith('INV/'));
        System.assertEquals(1180, first.totalAmount);
        System.assertEquals(QuickBillController.WALK_IN_NAME, first.customerName);
        System.assertEquals(first.customerId, second.customerId, 'Every walk-in sale must reuse the one Walk-in Customer record.');
        System.assertEquals(1, [SELECT COUNT() FROM Customer__c]);
        System.assertEquals(null, first.vehicleId);
    }

    @isTest
    static void newPhone_createsCustomerAndVehicle() {
        QuickBillController.QuickBillRequest r = request();
        r.customerName = 'Suresh Patel';
        r.customerPhone = '98260 11111';
        r.customerGstin = '23ABCDE1234F1Z5';
        r.newVehicle = new CustomerController.NewVehicleInput();
        r.newVehicle.registrationNumber = 'MP09CD5678';
        r.newVehicle.make = 'Maruti';
        r.newVehicle.model = 'Swift';

        Test.startTest();
        BillController.BillSummary summary = QuickBillController.createQuickBill(r);
        Test.stopTest();

        Customer__c created = [SELECT Name, Phone__c, GSTIN__c FROM Customer__c WHERE Id = :summary.customerId];
        System.assertEquals('Suresh Patel', created.Name);
        System.assertEquals('23ABCDE1234F1Z5', created.GSTIN__c);
        Vehicle__c vehicle = [SELECT Name, Customer__c FROM Vehicle__c WHERE Id = :summary.vehicleId];
        System.assertEquals('MP09CD5678', vehicle.Name);
        System.assertEquals(summary.customerId, vehicle.Customer__c);
    }

    @isTest
    static void existingPhone_reusesCustomerFillsBlanksAndMatchesVehicleByRegistration() {
        Customer__c existing = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '+91 9000011111', Address__c = 'Old Address');
        insert existing;
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = existing.Id);
        insert vehicle;

        QuickBillController.QuickBillRequest r = request();
        r.customerName = 'Typed Differently';
        r.customerPhone = '9000011111';
        r.customerAddress = 'New Address';
        r.customerState = '23-Madhya Pradesh';
        r.newVehicle = new CustomerController.NewVehicleInput();
        r.newVehicle.registrationNumber = 'mp09ab1234';

        Test.startTest();
        BillController.BillSummary summary = QuickBillController.createQuickBill(r);
        Test.stopTest();

        System.assertEquals(existing.Id, summary.customerId);
        System.assertEquals(vehicle.Id, summary.vehicleId, 'A typed registration that matches the customer\'s vehicle must reuse it.');
        System.assertEquals(1, [SELECT COUNT() FROM Customer__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Vehicle__c]);
        Customer__c after = [SELECT Name, Address__c, State__c FROM Customer__c WHERE Id = :existing.Id];
        System.assertEquals('Ramesh Kumar', after.Name, 'An existing customer\'s name is never overwritten.');
        System.assertEquals('Old Address', after.Address__c, 'Saved details are never overwritten.');
        System.assertEquals('23-Madhya Pradesh', after.State__c, 'Blank details are filled in.');
    }

    @isTest
    static void selectedVehicleId_isUsed() {
        Customer__c existing = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert existing;
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = existing.Id);
        insert vehicle;

        QuickBillController.QuickBillRequest r = request();
        r.customerPhone = '9000011111';
        r.vehicleId = vehicle.Id;

        Test.startTest();
        BillController.BillSummary summary = QuickBillController.createQuickBill(r);
        Test.stopTest();

        System.assertEquals(vehicle.Id, summary.vehicleId);
    }

    @isTest
    static void vehicleOfAnotherCustomer_throws() {
        Customer__c other = new Customer__c(Name = 'Other', Phone__c = '9111111111');
        insert other;
        Vehicle__c othersVehicle = new Vehicle__c(Name = 'MP09XX0000', Customer__c = other.Id);
        insert othersVehicle;

        QuickBillController.QuickBillRequest r = request();
        r.customerName = 'Suresh Patel';
        r.customerPhone = '9826011111';
        r.vehicleId = othersVehicle.Id;

        Boolean threw = false;
        try {
            QuickBillController.createQuickBill(r);
        } catch (QuickBillController.QuickBillControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void manualLine_deductsNothingButPartLine_deductsStock() {
        Part__c part = new Part__c(Name = 'Brake Pad Set', Price__c = 1200, Tax_Rate_Percent__c = 18, Current_Stock__c = 10);
        insert part;
        QuickBillController.QuickBillRequest r = request();
        r.isWalkIn = true;
        BillController.LineItemInput partLine = line('Brake Pad Set', 3, 1200);
        partLine.partId = part.Id;
        r.lineItems.add(partLine);

        Test.startTest();
        QuickBillController.createQuickBill(r);
        Test.stopTest();

        System.assertEquals(7, [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id].Current_Stock__c);
    }

    @isTest
    static void missingDetails_throwFriendlyErrors() {
        List<QuickBillController.QuickBillRequest> bad = new List<QuickBillController.QuickBillRequest>();
        QuickBillController.QuickBillRequest noItems = request();
        noItems.isWalkIn = true;
        noItems.lineItems = new List<BillController.LineItemInput>();
        bad.add(noItems);
        QuickBillController.QuickBillRequest noPhone = request();
        noPhone.customerName = 'Suresh';
        bad.add(noPhone);
        QuickBillController.QuickBillRequest noName = request();
        noName.customerPhone = '9826099999';
        bad.add(noName);

        Integer threw = 0;
        for (QuickBillController.QuickBillRequest r : bad) {
            try {
                QuickBillController.createQuickBill(r);
            } catch (QuickBillController.QuickBillControllerException e) {
                threw++;
            }
        }
        System.assertEquals(3, threw);
    }

    @isTest
    static void findCustomerByPhone_matchesAnyFormatAndListsVehicles() {
        Customer__c existing = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert existing;
        insert new Vehicle__c(Name = 'MP09AB1234', Customer__c = existing.Id);

        Test.startTest();
        QuickBillController.CustomerMatch match = QuickBillController.findCustomerByPhone('+91 90000 11111');
        QuickBillController.CustomerMatch none = QuickBillController.findCustomerByPhone('9999999999');
        QuickBillController.CustomerMatch tooShort = QuickBillController.findCustomerByPhone('900');
        Test.stopTest();

        System.assertEquals(existing.Id, match.id);
        System.assertEquals(1, match.vehicles.size());
        System.assertEquals(null, none);
        System.assertEquals(null, tooShort);
    }

    @isTest
    static void findCustomerByPhone_neverMatchesTheWalkInPlaceholder() {
        insert new Customer__c(Name = QuickBillController.WALK_IN_NAME, Phone__c = QuickBillController.WALK_IN_PHONE);
        System.assertEquals(null, QuickBillController.findCustomerByPhone(QuickBillController.WALK_IN_PHONE));
    }

    @isTest
    static void walkInInvoice_doesNotPrintThePlaceholderPhone() {
        QuickBillController.QuickBillRequest r = request();
        r.isWalkIn = true;
        BillController.BillSummary summary = QuickBillController.createQuickBill(r);

        PageReference page = Page.InvoicePdf;
        page.getParameters().put('id', summary.billId);
        Test.setCurrentPage(page);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals(QuickBillController.WALK_IN_NAME, controller.billToName);
        System.assertEquals(null, controller.billToContact);
    }
}
