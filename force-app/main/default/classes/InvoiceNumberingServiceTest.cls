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
}
