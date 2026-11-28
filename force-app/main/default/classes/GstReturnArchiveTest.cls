/**
 * A GST return for a month whose bills are archived (architecture.md,
 * Forty-eighth) comes out exactly as before they were archived, and a later
 * month's documents issued still knows the archived numbers.
 */
@isTest
private class GstReturnArchiveTest {

    private static final String MP_GSTIN = '23ABCDE1234F1Z8';

    // Two years back, and its next month in the same financial year.
    private static Date monthA() {
        Date m = Date.today().toStartOfMonth().addMonths(-24);
        return m.month() == 3 ? m.addMonths(-1) : m;
    }

    private static Date monthB() {
        return monthA().addMonths(1);
    }

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GSTIN__c = '23AAACI7904G1ZV', State__c = 'Madhya Pradesh',
            GST_Registration_Type__c = 'Regular');
        Customer__c sharma = new Customer__c(Name = 'Sharma Traders', Phone__c = '9000011111', GSTIN__c = MP_GSTIN);
        Customer__c ramesh = new Customer__c(Name = 'Ramesh', Phone__c = '9000022222');
        insert new List<Customer__c>{ sharma, ramesh };
        // Numbered in this order: 1 in month B, 2-4 in month A (4 deleted), 5 in month B.
        bill(ramesh.Id, monthB(), 300, 18);
        bill(sharma.Id, monthA().addDays(1), 1000, 18);
        bill(ramesh.Id, monthA().addDays(2), 500, 18);
        Bill__c deleted = bill(ramesh.Id, monthA().addDays(3), 999, 18);
        update new Bill__c(Id = deleted.Id, Is_Cancelled__c = true, Cancelled_On__c = Date.today());
        bill(ramesh.Id, monthB().addDays(1), 200, 18);
    }

    private static Bill__c bill(Id customerId, Date d, Decimal price, Decimal rate) {
        Bill__c b = new Bill__c(Customer__c = customerId, Bill_Date__c = d);
        insert b;
        TestLines.attach(b.Id, new List<BillController.LineItemInput>{ TestLines.line('Service', 1, price, rate, 'CGST_SGST', '998714', null) });
        return b;
    }

    private static Id companyId() {
        return [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id;
    }

    private static GstReturnService.GstReturn returnFor(Date month) {
        return GstReturnService.build(companyId(), month, GstFilingLock.monthEnd(month));
    }

    // Everything a return reports, less the archive file the rows point at.
    private static String figures(GstReturnService.GstReturn r) {
        List<Object> parts = new List<Object>{ r.billCount, r.invoiceValue, r.b2cs, r.nil, r.hsnB2b, r.hsnB2c, r.documents, r.gstr3b, r.errorCount, r.warningCount };
        List<Decimal> b2b = new List<Decimal>();
        for (GstReturnService.InvoiceRow row : r.b2b) {
            b2b.add(row.taxableValue);
            b2b.add(row.cgst);
            b2b.add(row.invoiceValue);
        }
        parts.add(b2b);
        return JSON.serialize(parts);
    }

    @isTest
    static void anArchivedMonthsReturn_isTheSameAsBefore_andPointsAtTheArchive() {
        GstReturnService.GstReturn before = returnFor(monthA());
        update new Workshop_Profile__c(Id = companyId(), GST_Filed_Up_To__c = GstFilingLock.monthEnd(monthA()));

        Test.startTest();
        BillArchive.Outcome outcome = BillArchive.archiveNextMonth(ArchiveSettings.current());
        GstReturnService.GstReturn after = returnFor(monthA());
        Test.stopTest();

        System.assertEquals(3, outcome.billsArchived);
        System.assertEquals(2, [SELECT COUNT() FROM Bill__c], 'Month B stays: its GST is not filed.');
        System.assertEquals(2, before.billCount);
        System.assertEquals(figures(before), figures(after));
        System.assertEquals(2, after.archivedCount);
        System.assertEquals(1, after.b2b.size());
        System.assertNotEquals(null, after.b2b[0].archiveId, 'The B2B row opens from the archive.');
        System.assertEquals(null, before.b2b[0].archiveId);
        System.assertEquals(3, after.documents[0].totalNumber);
        System.assertEquals(1, after.documents[0].cancelled);

        // The CA's download is made from the same figures.
        System.assertNotEquals(null, GstReturnController.downloadReturn(companyId(), monthA(), GstFilingLock.monthEnd(monthA())));
    }

    @isTest
    static void aLaterMonth_knowsTheArchivedNumbersAreNotMissing() {
        update new Workshop_Profile__c(Id = companyId(), GST_Filed_Up_To__c = GstFilingLock.monthEnd(monthA()));
        GstReturnService.GstReturn before = returnFor(monthB());

        Test.startTest();
        BillArchive.archiveNextMonth(ArchiveSettings.current());
        GstReturnService.GstReturn after = returnFor(monthB());
        Test.stopTest();

        System.assertEquals(figures(before), figures(after));
        System.assertEquals(2, after.documents.size(), 'Numbers 1 and 5, split by 2-4 dated in month A.');
        System.assertEquals(0, after.archivedCount);
        for (GstReturnService.Issue issue : after.issues) {
            System.assert(!issue.message.contains('have no bill left'), issue.message);
        }
    }

    @isTest
    static void aBillBroughtBack_isCountedOnce() {
        update new Workshop_Profile__c(Id = companyId(), GST_Filed_Up_To__c = GstFilingLock.monthEnd(monthA()));
        BillArchive.archiveNextMonth(ArchiveSettings.current());
        Id archivedId;
        for (ArchiveStore.IndexEntry e : ArchiveStore.index()) {
            if (e.c == 'Sharma Traders') {
                archivedId = e.id;
            }
        }

        Test.startTest();
        BillArchive.restore(archivedId);
        GstReturnService.GstReturn after = returnFor(monthA());
        Test.stopTest();

        System.assertEquals(2, after.billCount);
        System.assertEquals(1, after.archivedCount, 'One live again, one still archived.');
        System.assertEquals(null, after.b2b[0].archiveId);
    }
}
