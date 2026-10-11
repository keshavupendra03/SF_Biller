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
}
