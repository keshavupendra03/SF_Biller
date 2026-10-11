@isTest
private class PaymentTriggerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static Id insertBillWithTotal(Decimal total) {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Bill__c bill = new Bill__c(Customer__c = customer.Id);
        insert bill;
        insert new Bill_Line_Item__c(
            Bill__c = bill.Id,
            Description__c = 'Service',
            Quantity__c = 1,
            Unit_Price__c = total,
            Tax_Rate_Percent__c = 0
        );
        return bill.Id;
    }

    @isTest
    static void noPayments_statusStaysUnpaid() {
        Id billId = insertBillWithTotal(1000);
        Bill__c bill = [SELECT Status__c FROM Bill__c WHERE Id = :billId];
        System.assertEquals('Unpaid', bill.Status__c);
    }

    @isTest
    static void partialPayment_statusBecomesPartial() {
        Id billId = insertBillWithTotal(1000);

        Test.startTest();
        insert new Payment__c(Bill__c = billId, Amount__c = 400, Method__c = 'Cash', Paid_At__c = Datetime.now());
        Test.stopTest();

        Bill__c bill = [SELECT Status__c FROM Bill__c WHERE Id = :billId];
        System.assertEquals('Partial', bill.Status__c);
    }

    @isTest
    static void fullPayment_statusBecomesPaid() {
        Id billId = insertBillWithTotal(1000);

        Test.startTest();
        insert new Payment__c(Bill__c = billId, Amount__c = 1000, Method__c = 'UPI', Paid_At__c = Datetime.now());
        Test.stopTest();

        Bill__c bill = [SELECT Status__c FROM Bill__c WHERE Id = :billId];
        System.assertEquals('Paid', bill.Status__c);
    }

    @isTest
    static void multiplePartialPayments_summedAcrossBoth_becomesPaid() {
        Id billId = insertBillWithTotal(1000);

        insert new Payment__c(Bill__c = billId, Amount__c = 600, Method__c = 'Cash', Paid_At__c = Datetime.now());

        Test.startTest();
        insert new Payment__c(Bill__c = billId, Amount__c = 400, Method__c = 'Card', Paid_At__c = Datetime.now());
        Test.stopTest();

        Bill__c bill = [SELECT Status__c FROM Bill__c WHERE Id = :billId];
        System.assertEquals('Paid', bill.Status__c);
    }

    @isTest
    static void deletingAPayment_recomputesBackToLowerStatus() {
        Id billId = insertBillWithTotal(1000);
        Payment__c payment = new Payment__c(
            Bill__c = billId, Amount__c = 1000, Method__c = 'Cash', Paid_At__c = Datetime.now()
        );
        insert payment;

        Test.startTest();
        delete payment;
        Test.stopTest();

        Bill__c bill = [SELECT Status__c FROM Bill__c WHERE Id = :billId];
        System.assertEquals('Unpaid', bill.Status__c);
    }

    @isTest
    static void overpayment_statusIsPaidNotRejected() {
        Id billId = insertBillWithTotal(1000);

        Test.startTest();
        insert new Payment__c(Bill__c = billId, Amount__c = 1200, Method__c = 'Cash', Paid_At__c = Datetime.now());
        Test.stopTest();

        Bill__c bill = [SELECT Status__c FROM Bill__c WHERE Id = :billId];
        System.assertEquals('Paid', bill.Status__c);
    }
}
