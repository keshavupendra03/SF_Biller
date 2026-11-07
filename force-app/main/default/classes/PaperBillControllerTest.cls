@isTest
private class PaperBillControllerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', Phone__c = '9000000000');
    }

    private static BillController.LineItemInput line(String description, Decimal qty, Decimal price) {
        BillController.LineItemInput li = new BillController.LineItemInput();
        li.description = description;
        li.hsnSacCode = '8708';
        li.quantity = qty;
        li.unitPrice = price;
        li.taxRatePercent = 18;
        li.gstType = 'CGST_SGST';
        return li;
    }

    private static PaperBillController.PaperRequest request() {
        PaperBillController.PaperRequest r = new PaperBillController.PaperRequest();
        r.documentType = 'bill';
        r.lineItems = new List<BillController.LineItemInput>{ line('Engine Oil 1L', 2, 500) };
        return r;
    }

    @isTest
    static void savesANormalBill_withHsn_andNoGstByDefault() {
        PaperBillController.PaperRequest r = request();
        r.documentDate = Date.newInstance(2026, 11, 1);
        r.notes = 'Thank you';

        Test.startTest();
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(r);
        Test.stopTest();

        System.assert(saved.documentNumber.startsWith('INV/'));
        System.assertEquals(1000, saved.totalAmount);
        System.assertEquals(QuickBillController.WALK_IN_NAME, saved.customerName, 'A bill with no name goes to the Walk-in Customer.');
        Bill__c bill = [SELECT Bill_Date__c, Notes__c FROM Bill__c WHERE Id = :saved.recordId];
        System.assertEquals(Date.newInstance(2026, 11, 1), bill.Bill_Date__c);
        System.assertEquals('Thank you', bill.Notes__c);
        Bill_Line_Item__c item = [SELECT HSN_SAC_Code__c, Tax_Rate_Percent__c FROM Bill_Line_Item__c WHERE Bill__c = :saved.recordId];
        System.assertEquals('8708', item.HSN_SAC_Code__c);
        System.assertEquals(0, item.Tax_Rate_Percent__c);
        System.assertEquals(18, [SELECT Tax_Rate_Percent__c FROM Part__c WHERE Name = 'Engine Oil 1L'].Tax_Rate_Percent__c,
            'A part created from a typed line keeps the typed rate for later bills.');
    }

    @isTest
    static void savesANormalEstimate_withGstAdded_andLeavesStockAlone() {
        Part__c part = new Part__c(Name = 'Brake Pad Set', Price__c = 1000, Tax_Rate_Percent__c = 18, Current_Stock__c = 4);
        insert part;
        PaperBillController.PaperRequest r = request();
        r.documentType = 'estimate';
        r.includeGst = true;
        BillController.LineItemInput partLine = line('Brake Pad Set', 1, 1000);
        partLine.partId = part.Id;
        r.lineItems = new List<BillController.LineItemInput>{ partLine };

        Test.startTest();
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(r);
        Test.stopTest();

        System.assert(saved.documentNumber.startsWith('EST-'));
        System.assertEquals(1180, saved.totalAmount);
        System.assertEquals(1, [SELECT COUNT() FROM Estimate__c WHERE Id = :saved.recordId]);
        System.assertEquals(4, [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id].Current_Stock__c);
    }

    @isTest
    static void billDeductsStockLikeAnyOtherBill() {
        Part__c part = new Part__c(Name = 'Brake Pad Set', Price__c = 1000, Tax_Rate_Percent__c = 18, Current_Stock__c = 4);
        insert part;
        PaperBillController.PaperRequest r = request();
        BillController.LineItemInput partLine = line('Brake Pad Set', 3, 1000);
        partLine.partId = part.Id;
        r.lineItems = new List<BillController.LineItemInput>{ partLine };

        Test.startTest();
        PaperBillController.saveDocument(r);
        Test.stopTest();

        System.assertEquals(1, [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id].Current_Stock__c);
    }

    @isTest
    static void nameWithNoPhone_printsThatName_andReusesTheSameRecordNextTime() {
        PaperBillController.PaperRequest first = request();
        first.customerName = 'Ramesh Kumar';
        first.customerAddress = 'Vijay Nagar';
        PaperBillController.PaperRequest second = request();
        second.customerName = 'Ramesh Kumar';

        Test.startTest();
        PaperBillController.SavedDocument a = PaperBillController.saveDocument(first);
        PaperBillController.SavedDocument b = PaperBillController.saveDocument(second);
        Test.stopTest();

        System.assertEquals('Ramesh Kumar', a.customerName);
        System.assertEquals('Ramesh Kumar', b.customerName);
        System.assertEquals(1, [SELECT COUNT() FROM Customer__c WHERE Name = 'Ramesh Kumar']);

        PageReference page = Page.InvoicePdf;
        page.getParameters().put('id', a.recordId);
        Test.setCurrentPage(page);
        InvoicePdfController pdf = new InvoicePdfController();
        System.assertEquals('Ramesh Kumar', pdf.billToName);
        System.assertEquals(null, pdf.billToContact, 'The placeholder phone must not print.');
        System.assertEquals('Vijay Nagar', pdf.billToAddress);
    }

    @isTest
    static void newPhone_createsCustomerAndVehicle_andRemembersMakeAndModel() {
        PaperBillController.PaperRequest r = request();
        r.customerName = 'Suresh Patel';
        r.customerPhone = '9826011111';
        r.customerGstin = '23ABCDE1234F1Z5';
        r.registrationNumber = 'MP09CD5678';
        r.make = 'Maruti';
        r.model = 'Swift';
        r.chassisNumber = 'CH123';

        Test.startTest();
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(r);
        Test.stopTest();

        Bill__c bill = [
            SELECT Customer__r.Phone__c, Customer__r.GSTIN__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Chassis_Number__c
            FROM Bill__c WHERE Id = :saved.recordId
        ];
        System.assertEquals('9826011111', bill.Customer__r.Phone__c);
        System.assertEquals('23ABCDE1234F1Z5', bill.Customer__r.GSTIN__c);
        System.assertEquals('MP09CD5678', bill.Vehicle__r.Name);
        System.assertEquals('CH123', bill.Vehicle__r.Chassis_Number__c);
        System.assertEquals(1, [SELECT COUNT() FROM Vehicle_Make_Model__c WHERE Make__c = 'Maruti' AND Model__c = 'Swift']);
    }

    @isTest
    static void pickedCustomerAndVehicle_takeExactlyWhatIsOnThePage() {
        Customer__c customer = new Customer__c(Name = 'Ramesh K', Phone__c = '9000011111', Address__c = 'Old Address', GSTIN__c = 'OLDGST');
        insert customer;
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customer.Id, Make__c = 'Tata', Chassis_Number__c = 'OLD');
        insert vehicle;

        PaperBillController.PaperRequest r = request();
        r.customerId = customer.Id;
        r.customerName = 'Ramesh Kumar';
        r.customerPhone = '9000022222';
        r.customerAddress = 'New Address';
        r.customerGstin = '';
        r.vehicleId = vehicle.Id;
        r.registrationNumber = 'MP09AB1234';
        r.make = 'Tata Motors';
        r.chassisNumber = '';

        Test.startTest();
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(r);
        Test.stopTest();

        Customer__c after = [SELECT Name, Phone__c, Address__c, GSTIN__c FROM Customer__c WHERE Id = :customer.Id];
        System.assertEquals('Ramesh Kumar', after.Name);
        System.assertEquals('9000022222', after.Phone__c);
        System.assertEquals('New Address', after.Address__c);
        System.assertEquals(null, after.GSTIN__c, 'A box cleared on the page is cleared on the record, or it would still print.');
        Vehicle__c afterVehicle = [SELECT Make__c, Chassis_Number__c FROM Vehicle__c WHERE Id = :vehicle.Id];
        System.assertEquals('Tata Motors', afterVehicle.Make__c);
        System.assertEquals(null, afterVehicle.Chassis_Number__c);
        System.assertEquals(vehicle.Id, [SELECT Vehicle__c FROM Bill__c WHERE Id = :saved.recordId].Vehicle__c);
    }

    @isTest
    static void typedKnownPhone_reusesCustomer_andOnlyReplacesWhatWasTyped() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111', Address__c = 'Kept Address');
        insert customer;
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customer.Id, Make__c = 'Tata');
        insert vehicle;

        PaperBillController.PaperRequest r = request();
        r.customerPhone = '+91 90000 11111';
        r.customerState = '23-Madhya Pradesh';
        r.registrationNumber = 'mp09ab1234';
        r.model = 'Punch';

        Test.startTest();
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(r);
        Test.stopTest();

        System.assertEquals('Ramesh Kumar', saved.customerName);
        System.assertEquals(1, [SELECT COUNT() FROM Customer__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Vehicle__c]);
        Customer__c after = [SELECT Address__c, State__c FROM Customer__c WHERE Id = :customer.Id];
        System.assertEquals('Kept Address', after.Address__c);
        System.assertEquals('23-Madhya Pradesh', after.State__c);
        Vehicle__c afterVehicle = [SELECT Make__c, Model__c FROM Vehicle__c WHERE Id = :vehicle.Id];
        System.assertEquals('Tata', afterVehicle.Make__c);
        System.assertEquals('Punch', afterVehicle.Model__c);
    }

    @isTest
    static void editedWorkshopDetails_areSavedOnTheProfile() {
        PaperBillController.PaperRequest r = request();
        r.workshop = new WorkshopProfileController.ProfileData();
        r.workshop.name = 'Speedy Motors & Sons';
        r.workshop.termsAndConditions = 'Goods once sold will not be taken back.';

        Test.startTest();
        PaperBillController.saveDocument(r);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Workshop_Profile__c]);
        Workshop_Profile__c profile = [SELECT Name, Terms_And_Conditions__c FROM Workshop_Profile__c];
        System.assertEquals('Speedy Motors & Sons', profile.Name);
        System.assertEquals('Goods once sold will not be taken back.', profile.Terms_And_Conditions__c);
    }

    @isTest
    static void noWorkshopEdits_leaveTheProfileAlone() {
        Test.startTest();
        PaperBillController.saveDocument(request());
        Test.stopTest();

        System.assertEquals('9000000000', [SELECT Phone__c FROM Workshop_Profile__c].Phone__c);
    }

    @isTest
    static void badRequests_throwAndSaveNothing() {
        List<PaperBillController.PaperRequest> bad = new List<PaperBillController.PaperRequest>();
        PaperBillController.PaperRequest noItems = request();
        noItems.lineItems = new List<BillController.LineItemInput>();
        bad.add(noItems);
        PaperBillController.PaperRequest phoneNoName = request();
        phoneNoName.customerPhone = '9826099999';
        bad.add(phoneNoName);
        PaperBillController.PaperRequest makeNoNumber = request();
        makeNoNumber.make = 'Tata';
        bad.add(makeNoNumber);

        Integer threw = 0;
        for (PaperBillController.PaperRequest r : bad) {
            try {
                PaperBillController.saveDocument(r);
            } catch (PaperBillController.PaperBillControllerException e) {
                threw++;
            }
        }
        System.assertEquals(3, threw);
    }

    @isTest
    static void vehicleOfAnotherCustomer_throws() {
        Customer__c other = new Customer__c(Name = 'Other', Phone__c = '9111111111');
        insert other;
        Vehicle__c othersVehicle = new Vehicle__c(Name = 'MP09XX0000', Customer__c = other.Id);
        insert othersVehicle;
        PaperBillController.PaperRequest r = request();
        r.vehicleId = othersVehicle.Id;

        Boolean threw = false;
        try {
            PaperBillController.saveDocument(r);
        } catch (PaperBillController.PaperBillControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void getCustomer_returnsDetailsAndVehicles_hidingThePlaceholderPhone() {
        Customer__c noPhone = new Customer__c(Name = 'Ramesh', Phone__c = QuickBillController.WALK_IN_PHONE, Address__c = 'Indore');
        insert noPhone;
        insert new Vehicle__c(Name = 'MP09AB1234', Customer__c = noPhone.Id);

        Test.startTest();
        QuickBillController.CustomerMatch match = PaperBillController.getCustomer(noPhone.Id);
        Test.stopTest();

        System.assertEquals('Ramesh', match.name);
        System.assertEquals('Indore', match.address);
        System.assertEquals(null, match.phone);
        System.assertEquals(1, match.vehicles.size());
    }

    @isTest
    static void amountInWords_matchesTheInvoiceService() {
        System.assertEquals(AmountInWordsService.convert(1180), PaperBillController.amountInWords(1180));
        System.assertEquals('', PaperBillController.amountInWords(null));
    }

    private static InvoicePdfController printed(Id recordId) {
        PageReference page = Page.InvoicePdf;
        page.getParameters().put('id', recordId);
        Test.setCurrentPage(page);
        return new InvoicePdfController();
    }

    @isTest
    static void noGstBill_printsAsABillWithNoGstColumns() {
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(request());

        Test.startTest();
        InvoicePdfController pdf = printed(saved.recordId);
        Test.stopTest();

        System.assertEquals('Bill', pdf.documentTitle);
        System.assertEquals(false, pdf.hasGst);
        System.assertEquals(false, pdf.showUnit);
        System.assertEquals(54, pdf.productColumnWidth);
        System.assertEquals(1000, pdf.grandTotal);
    }

    @isTest
    static void gstBill_printsAsATaxInvoiceWithGstColumns() {
        PaperBillController.PaperRequest r = request();
        r.includeGst = true;
        r.lineItems[0].unitLabel = 'Ltr';
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(r);

        Test.startTest();
        InvoicePdfController pdf = printed(saved.recordId);
        Test.stopTest();

        System.assertEquals('Tax Invoice', pdf.documentTitle);
        System.assertEquals(true, pdf.hasGst);
        System.assertEquals(true, pdf.showUnit);
        System.assertEquals(22, pdf.productColumnWidth);
    }

    @isTest
    static void noGstEstimate_staysTitledEstimate() {
        PaperBillController.PaperRequest r = request();
        r.documentType = 'estimate';
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(r);

        Test.startTest();
        InvoicePdfController pdf = printed(saved.recordId);
        Test.stopTest();

        System.assertEquals('Estimate', pdf.documentTitle);
        System.assertEquals(false, pdf.hasGst);
    }
}
