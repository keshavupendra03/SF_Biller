@isTest
private class BillTriggerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        return customer.Id;
    }

    @isTest
    static void newBillWithNoInvoiceNumber_getsAutoAssignedOne() {
        Id customerId = insertCustomer();

        Test.startTest();
        Bill__c bill = new Bill__c(Customer__c = customerId);
        insert bill;
        Test.stopTest();

        Bill__c inserted = [
            SELECT Invoice_Number__c, Financial_Year__c FROM Bill__c WHERE Id = :bill.Id
        ];
        String expectedFy = InvoiceNumberingService.financialYearFor(Date.today());
        System.assertEquals('INV/' + expectedFy + '/0001', inserted.Invoice_Number__c);
        System.assertEquals(expectedFy, inserted.Financial_Year__c);
    }

    @isTest
    static void billWithInvoiceNumberAlreadySet_isNeverRenumbered() {
        Id customerId = insertCustomer();

        Test.startTest();
        Bill__c bill = new Bill__c(
            Customer__c = customerId,
            Invoice_Number__c = 'INV/2020-21/9999',
            Financial_Year__c = '2020-21'
        );
        insert bill;
        Test.stopTest();

        Bill__c inserted = [SELECT Invoice_Number__c FROM Bill__c WHERE Id = :bill.Id];
        System.assertEquals('INV/2020-21/9999', inserted.Invoice_Number__c);
    }

    @isTest
    static void bulkInsertOfUnnumberedBills_eachGetsAUniqueSequentialNumber() {
        Id customerId = insertCustomer();
        List<Bill__c> bills = new List<Bill__c>();
        for (Integer i = 0; i < 5; i++) {
            bills.add(new Bill__c(Customer__c = customerId));
        }

        Test.startTest();
        insert bills;
        Test.stopTest();

        Set<String> numbers = new Set<String>();
        for (Bill__c b : [SELECT Invoice_Number__c FROM Bill__c WHERE Id IN :bills]) {
            numbers.add(b.Invoice_Number__c);
        }
        System.assertEquals(5, numbers.size(), 'Expected 5 unique invoice numbers.');
    }

    @isTest
    static void aBillDatedInTheFuture_isRefused() {
        Id customerId = insertCustomer();
        Decimal counterBefore = [SELECT Invoice_Sequence_Last_Number__c FROM Workshop_Profile__c LIMIT 1].Invoice_Sequence_Last_Number__c;

        Test.startTest();
        Database.SaveResult result = Database.insert(new Bill__c(Customer__c = customerId, Bill_Date__c = Date.today().addDays(1)), false);
        Test.stopTest();

        System.assert(!result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('can\'t be dated in the future'), result.getErrors()[0].getMessage());
        System.assertEquals(counterBefore, [SELECT Invoice_Sequence_Last_Number__c FROM Workshop_Profile__c LIMIT 1].Invoice_Sequence_Last_Number__c,
            'A refused bill uses up no number.');
    }

    @isTest
    static void aFutureBill_fromAScreen_saysWhyInItsOwnWords() {
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = insertCustomer();
        request.billDate = Date.today().addDays(3);
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Washing';
        line.quantity = 1;
        line.unitPrice = 200;
        line.taxRatePercent = 18;
        request.lineItems = new List<BillController.LineItemInput>{ line };

        Test.startTest();
        try {
            BillController.createBill(request);
            System.assert(false, 'Expected the future date to be refused.');
        } catch (ReadableErrors.ReadableException e) {
            System.assert(e.getMessage().contains('can\'t be dated in the future'), e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void placeOfSupply_isTheCustomersState_withNoGstinForAWalkIn() {
        Customer__c customer = new Customer__c(Name = 'Ramesh', Phone__c = '9000011111', State__c = 'Goa');
        insert customer;

        Test.startTest();
        Bill__c bill = new Bill__c(Customer__c = customer.Id);
        insert bill;
        Test.stopTest();

        Bill__c saved = [SELECT Place_Of_Supply__c, Recipient_GSTIN__c FROM Bill__c WHERE Id = :bill.Id];
        System.assertEquals('30', saved.Place_Of_Supply__c);
        System.assertEquals(null, saved.Recipient_GSTIN__c);
    }

    @isTest
    static void aPartyBill_isToTheParty_andKeepsItsGstinIfTheyChangeLater() {
        Id customerId = insertCustomer();
        Bill_To_Party__c party = new Bill_To_Party__c(Name = 'Sharma Traders', GSTIN__c = '27AAPFU0939F1ZV');
        insert party;

        Bill__c bill = new Bill__c(Customer__c = customerId, Bill_To_Party__c = party.Id);
        insert bill;
        Test.startTest();
        update new Bill_To_Party__c(Id = party.Id, GSTIN__c = '23AAACI7904G1ZV', State__c = 'Madhya Pradesh');
        Test.stopTest();

        Bill__c saved = [SELECT Place_Of_Supply__c, Recipient_GSTIN__c FROM Bill__c WHERE Id = :bill.Id];
        System.assertEquals('27', saved.Place_Of_Supply__c);
        System.assertEquals('27AAPFU0939F1ZV', saved.Recipient_GSTIN__c);
    }

    @isTest
    static void aBuyerWithNoState_isSuppliedWhereTheCompanyIs() {
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, State__c = 'Madhya Pradesh');
        Id customerId = insertCustomer();

        Test.startTest();
        Bill__c bill = new Bill__c(Customer__c = customerId);
        insert bill;
        Test.stopTest();

        System.assertEquals('23', [SELECT Place_Of_Supply__c FROM Bill__c WHERE Id = :bill.Id].Place_Of_Supply__c);
    }

    @isTest
    static void aCompanyWithOnlyAGstin_stillGivesThePlaceOfSupply() {
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, GSTIN__c = '23AAACI7904G1ZV', State__c = null);
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, State__c = null);
        Id customerId = insertCustomer();

        Test.startTest();
        Bill__c bill = new Bill__c(Customer__c = customerId);
        insert bill;
        Test.stopTest();

        System.assertEquals('23', [SELECT Place_Of_Supply__c FROM Bill__c WHERE Id = :bill.Id].Place_Of_Supply__c);
    }
}
