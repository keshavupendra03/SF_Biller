/**
 * Apex tests run single-threaded — there is no literal OS-thread
 * parallelism available inside Test.startTest()/stopTest(). "100 simulated
 * concurrent bill creations" below means 100 rapid sequential calls
 * exercising the exact same FOR UPDATE locking code path each real
 * concurrent caller would hit, which proves the read-increment-write logic
 * has no off-by-one/duplicate bug. It does NOT directly observe lock-wait
 * behavior under true simultaneous contention — that's a platform
 * guarantee of FOR UPDATE, not something a single-threaded Apex test can
 * exercise. Documented here rather than implied by the test name alone.
 */
@isTest
private class InvoiceNumberingServiceTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    @isTest
    static void financialYearFor_aprilFirstStartsNewFy() {
        System.assertEquals(
            '2026-27',
            InvoiceNumberingService.financialYearFor(Date.newInstance(2026, 4, 1))
        );
        System.assertEquals(
            '2025-26',
            InvoiceNumberingService.financialYearFor(Date.newInstance(2026, 3, 31))
        );
        System.assertEquals(
            '2026-27',
            InvoiceNumberingService.financialYearFor(Date.newInstance(2026, 9, 19))
        );
    }

    @isTest
    static void assignNextInvoiceNumber_sequentialWithinOneFy() {
        Test.startTest();
        InvoiceNumberingService.InvoiceNumberResult first = InvoiceNumberingService.assignNextInvoiceNumber();
        InvoiceNumberingService.InvoiceNumberResult second = InvoiceNumberingService.assignNextInvoiceNumber();
        InvoiceNumberingService.InvoiceNumberResult third = InvoiceNumberingService.assignNextInvoiceNumber();
        Test.stopTest();

        String fy = InvoiceNumberingService.financialYearFor(Date.today());
        System.assertEquals('INV/' + fy + '/0001', first.invoiceNumber);
        System.assertEquals('INV/' + fy + '/0002', second.invoiceNumber);
        System.assertEquals('INV/' + fy + '/0003', third.invoiceNumber);
    }

    @isTest
    static void assignNextInvoiceNumber_rolloverResetsSequenceToOne() {
        Workshop_Profile__c profile = [SELECT Id FROM Workshop_Profile__c LIMIT 1];
        // Simulate the counter already having assigned numbers in a
        // *different*, past financial year.
        profile.Invoice_Sequence_Financial_Year__c = '2020-21';
        profile.Invoice_Sequence_Last_Number__c = 47;
        update profile;

        Test.startTest();
        InvoiceNumberingService.InvoiceNumberResult result = InvoiceNumberingService.assignNextInvoiceNumber();
        Test.stopTest();

        String currentFy = InvoiceNumberingService.financialYearFor(Date.today());
        System.assertEquals('INV/' + currentFy + '/0001', result.invoiceNumber);
        System.assertNotEquals('2020-21', result.financialYear);
    }

    @isTest
    static void assignNextInvoiceNumber_throwsWithNoWorkshopProfileSeeded() {
        delete [SELECT Id FROM Workshop_Profile__c];

        Test.startTest();
        Boolean threw = false;
        try {
            InvoiceNumberingService.assignNextInvoiceNumber();
        } catch (InvoiceNumberingService.InvoiceNumberingException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Expected an InvoiceNumberingException with no seeded profile.');
    }

    // The stage's stated exit criterion: 100 simulated concurrent bill
    // creations produce 100 unique sequential numbers.
    @isTest
    static void assignNextInvoiceNumber_100CallsProduce100UniqueSequentialNumbers() {
        // Named outright: looking up the primary company would be a 101st query.
        Id companyId = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id;
        Test.startTest();
        Set<String> numbers = new Set<String>();
        List<Integer> sequenceNumbers = new List<Integer>();
        for (Integer i = 0; i < 100; i++) {
            InvoiceNumberingService.InvoiceNumberResult result = InvoiceNumberingService.assignNextInvoiceNumber(companyId);
            numbers.add(result.invoiceNumber);
            List<String> parts = result.invoiceNumber.split('/');
            sequenceNumbers.add(Integer.valueOf(parts[2]));
        }
        Test.stopTest();

        System.assertEquals(100, numbers.size(), 'Expected 100 unique invoice numbers, found duplicates.');
        sequenceNumbers.sort();
        for (Integer i = 0; i < 100; i++) {
            System.assertEquals(i + 1, sequenceNumbers[i], 'Expected an unbroken 1..100 sequence, found a gap at index ' + i);
        }
    }

    // ---- numbering by the bill's own date (architecture.md §F, Thirty-seventh) ----

    private static Date lastYear() {
        return Date.today().addYears(-1);
    }

    private static Bill__c billDated(Date billDate) {
        Customer__c customer = [SELECT Id FROM Customer__c LIMIT 1];
        Bill__c bill = new Bill__c(Customer__c = customer.Id, Bill_Date__c = billDate);
        insert bill;
        return [SELECT Invoice_Number__c, Financial_Year__c, Invoice_Sequence__c FROM Bill__c WHERE Id = :bill.Id];
    }

    @isTest
    static void aBillDatedLastYear_joinsLastYearsSeries_andTodaysCarriesOn() {
        insert new Customer__c(Name = 'Ramesh', Phone__c = '9000011111');
        String thisFy = InvoiceNumberingService.financialYearFor(Date.today());
        String lastFy = InvoiceNumberingService.financialYearFor(lastYear());

        Test.startTest();
        Bill__c today1 = billDated(Date.today());
        Bill__c old1 = billDated(lastYear());
        Bill__c old2 = billDated(lastYear());
        Bill__c today2 = billDated(Date.today());
        Test.stopTest();

        System.assertEquals('INV/' + thisFy + '/0001', today1.Invoice_Number__c);
        System.assertEquals('INV/' + lastFy + '/0001', old1.Invoice_Number__c);
        System.assertEquals(lastFy, old1.Financial_Year__c);
        System.assertEquals('INV/' + lastFy + '/0002', old2.Invoice_Number__c);
        System.assertEquals(2, old2.Invoice_Sequence__c);
        System.assertEquals('INV/' + thisFy + '/0002', today2.Invoice_Number__c, 'Last year\'s bills don\'t move this year\'s counter.');
    }

    @isTest
    static void lastYearsSeries_continuesFromBillsSavedBeforeSequencesWereKept() {
        insert new Customer__c(Name = 'Ramesh', Phone__c = '9000011111');
        Customer__c customer = [SELECT Id FROM Customer__c LIMIT 1];
        String lastFy = InvoiceNumberingService.financialYearFor(lastYear());
        // A bill numbered before Invoice_Sequence__c existed: only the number says 7.
        insert new Bill__c(Customer__c = customer.Id, Invoice_Number__c = 'INV/' + lastFy + '/0007', Financial_Year__c = lastFy, Bill_Date__c = lastYear());
        billDated(Date.today());

        Test.startTest();
        Bill__c next = billDated(lastYear());
        Test.stopTest();

        System.assertEquals('INV/' + lastFy + '/0008', next.Invoice_Number__c);
    }

    @isTest
    static void lastYearsSeries_isPerCompany() {
        insert new Customer__c(Name = 'Ramesh', Phone__c = '9000011111');
        Workshop_Profile__c decor = new Workshop_Profile__c(Name = 'Speedy Decor', Invoice_Prefix__c = 'DEC');
        insert decor;
        Customer__c customer = [SELECT Id FROM Customer__c LIMIT 1];
        String lastFy = InvoiceNumberingService.financialYearFor(lastYear());
        billDated(Date.today());
        billDated(lastYear());
        billDated(lastYear());
        insert new Bill__c(Customer__c = customer.Id, Workshop_Profile__c = decor.Id, Bill_Date__c = Date.today());

        Test.startTest();
        Bill__c decorOld = new Bill__c(Customer__c = customer.Id, Workshop_Profile__c = decor.Id, Bill_Date__c = lastYear());
        insert decorOld;
        Test.stopTest();

        System.assertEquals('DEC/' + lastFy + '/0001', [SELECT Invoice_Number__c FROM Bill__c WHERE Id = :decorOld.Id].Invoice_Number__c);
    }

    @isTest
    static void sequenceOf_readsTheRunningNumber() {
        System.assertEquals(42, InvoiceNumberingService.sequenceOf('INV/2026-27/0042'));
        System.assertEquals(10000, InvoiceNumberingService.sequenceOf('DEC/2026-27/10000'));
        System.assertEquals(null, InvoiceNumberingService.sequenceOf('OLD-NUMBER'));
        System.assertEquals(null, InvoiceNumberingService.sequenceOf(null));
    }
}
