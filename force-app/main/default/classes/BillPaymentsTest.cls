/**
 * Payments stored on the bill (BillPayments). Covers what the old payment
 * trigger test did: the status follows the sum of every payment.
 */
@isTest
private class BillPaymentsTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static Id insertBillWithTotal(Decimal total) {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Bill__c bill = new Bill__c(Customer__c = customer.Id);
        insert bill;
        TestLines.attach(bill.Id, TestLines.line('Service', 1, total, 0));
        return bill.Id;
    }

    private static Bill__c reload(Id billId) {
        return [SELECT Status__c, Amount_Paid__c, Payments__c FROM Bill__c WHERE Id = :billId];
    }

    @isTest
    static void noPayments_statusStaysUnpaid() {
        Id billId = insertBillWithTotal(1000);
        Bill__c bill = reload(billId);
        System.assertEquals('Unpaid', bill.Status__c);
        System.assertEquals(0, bill.Amount_Paid__c);
        System.assertEquals(0, BillPayments.read(bill.Payments__c).size());
    }

    @isTest
    static void partialPayment_statusBecomesPartial() {
        Id billId = insertBillWithTotal(1000);

        Test.startTest();
        BillPayments.add(billId, 400, 'Cash');
        Test.stopTest();

        System.assertEquals('Partial', reload(billId).Status__c);
        System.assertEquals(400, reload(billId).Amount_Paid__c);
    }

    @isTest
    static void fullPayment_statusBecomesPaid() {
        Id billId = insertBillWithTotal(1000);

        Test.startTest();
        BillPayments.add(billId, 1000, 'UPI');
        Test.stopTest();

        System.assertEquals('Paid', reload(billId).Status__c);
    }

    @isTest
    static void paymentsOneAfterAnother_areAllCounted_inOrder() {
        Id billId = insertBillWithTotal(1000);
        BillPayments.add(billId, 600, 'Cash');

        Test.startTest();
        BillController.BillSummary summary = BillController.recordPayment(billId, 400, 'Card');
        Test.stopTest();

        System.assertEquals('Paid', summary.status);
        System.assertEquals(1000, summary.amountPaid);
        System.assertEquals(0, summary.amountDue);
        System.assertEquals(2, summary.payments.size());
        System.assertEquals('p1', summary.payments[0].id);
        System.assertEquals(600, summary.payments[0].amount);
        System.assertEquals('Card', summary.payments[1].method);
        System.assertNotEquals(null, summary.payments[1].paidAt);
    }

    @isTest
    static void overpayment_statusIsPaidNotRejected() {
        Id billId = insertBillWithTotal(1000);

        Test.startTest();
        BillPayments.add(billId, 1200, 'Cash');
        Test.stopTest();

        System.assertEquals('Paid', reload(billId).Status__c);
    }

    @isTest
    static void aFirstPayment_isSetBeforeTheBillIsSaved() {
        Bill__c bill = new Bill__c(Total_Amount__c = 500);

        Test.startTest();
        BillPayments.addFirst(bill, 200, null);
        Test.stopTest();

        System.assertEquals('Partial', bill.Status__c);
        System.assertEquals(200, bill.Amount_Paid__c);
        System.assertEquals('Cash', BillPayments.read(bill.Payments__c)[0].method, 'No method given means cash.');
    }

    @isTest
    static void anUnknownMethod_orNoAmount_isRefused() {
        Id billId = insertBillWithTotal(1000);
        List<String> messages = new List<String>();

        Test.startTest();
        try {
            BillPayments.add(billId, 100, 'Cheque');
        } catch (BillPayments.BillPaymentsException e) {
            messages.add(e.getMessage());
        }
        try {
            BillPayments.add(billId, 0, 'Cash');
        } catch (BillPayments.BillPaymentsException e) {
            messages.add(e.getMessage());
        }
        try {
            BillController.recordPayment(billId, 100, 'Cheque');
        } catch (BillController.BillControllerException e) {
            messages.add(e.getMessage());
        }
        Test.stopTest();

        System.assertEquals('"Cheque" is not a payment method. Use Cash, Card, UPI, Bank Transfer.', messages[0]);
        System.assertEquals('A positive payment amount is required.', messages[1]);
        System.assertEquals(messages[0], messages[2]);
        System.assertEquals('Unpaid', reload(billId).Status__c, 'Nothing was recorded.');
    }

    @isTest
    static void aCustomersLifetimeSpend_addsUpEveryBillsPayments() {
        Id billId = insertBillWithTotal(1000);
        Id customerId = [SELECT Customer__c FROM Bill__c WHERE Id = :billId].Customer__c;
        Bill__c second = new Bill__c(Customer__c = customerId);
        insert second;
        TestLines.attach(second.Id, TestLines.line('Wash', 1, 300, 0));
        BillPayments.add(billId, 250, 'Cash');
        BillPayments.add(second.Id, 300, 'UPI');

        Test.startTest();
        CustomerController.CustomerDetail detail = CustomerController.getCustomerDetail(customerId);
        Test.stopTest();

        System.assertEquals(550, detail.lifetimeSpend);
    }
}
