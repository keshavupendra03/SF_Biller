@isTest
private class BillArchiveTest {

    // Two years back: older than the default 18 months.
    private static Date oldDay() {
        return Date.today().toStartOfMonth().addMonths(-24).addDays(4);
    }

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GST_Registration_Type__c = 'Regular', State__c = 'Madhya Pradesh');
        insert new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
    }

    private static Workshop_Profile__c company() {
        return [SELECT Id, Invoice_Last_Numbers__c FROM Workshop_Profile__c LIMIT 1];
    }

    private static Id customerId() {
        return [SELECT Id FROM Customer__c WHERE Name = 'Ramesh Kumar'].Id;
    }

    private static BillController.BillSummary bill(Date d, Decimal price) {
        BillController.CreateBillRequest r = new BillController.CreateBillRequest();
        r.customerId = customerId();
        r.billDate = d;
        r.lineItems = new List<BillController.LineItemInput>{ TestLines.line('Service', 1, price, 18, 'CGST_SGST', '998714', null) };
        return BillController.createBill(r);
    }

    private static void fileGstUpTo(Date d) {
        update new Workshop_Profile__c(Id = company().Id, GST_Filed_Up_To__c = d);
    }

    private static ArchiveSettings.Rules rules() {
        return ArchiveSettings.current();
    }

    @isTest
    static void oldBillsOfAFiledMonth_goIntoOneFile_andLeaveSalesforce() {
        BillController.BillSummary first = bill(oldDay(), 1000);
        BillController.BillSummary second = bill(oldDay().addDays(1), 500);
        BillPayments.add(first.billId, 1180, 'Cash');
        BillController.BillSummary recent = bill(Date.today().addDays(-3), 200);
        fileGstUpTo(oldDay().addMonths(1).toStartOfMonth().addDays(-1));

        Test.startTest();
        BillArchive.Plan plan = BillArchive.plan(rules());
        BillArchive.Outcome outcome = BillArchive.archiveNextMonth(rules());
        Test.stopTest();

        System.assertEquals(2, plan.billCount);
        System.assertEquals(2, outcome.billsArchived);
        System.assertEquals(String.valueOf(oldDay()).left(7), outcome.month);
        System.assertEquals(1, [SELECT COUNT() FROM Bill__c], 'Only the recent bill is left.');
        System.assertEquals(recent.billId, [SELECT Id FROM Bill__c].Id);
        System.assertEquals(1, ArchiveStore.filesOfKind(ArchiveStore.KIND_BILLS).size());
        List<ArchiveStore.IndexEntry> index = ArchiveStore.index();
        System.assertEquals(2, index.size());
        System.assertEquals(1180, CustomerController.getCustomerDetail(customerId()).lifetimeSpend, 'What was paid still counts.');
        Integer seq = [SELECT Invoice_Sequence__c FROM Bill__c WHERE Id = :recent.billId].Invoice_Sequence__c.intValue();
        System.assert(BillArchive.lastNumbers(company()).size() == 1, company().Invoice_Last_Numbers__c);
        System.assertNotEquals(null, seq);
    }

    @isTest
    static void aMonthWhoseGstIsNotFiled_staysInSalesforce() {
        bill(oldDay(), 1000);
        fileGstUpTo(oldDay().toStartOfMonth().addDays(-1));

        Test.startTest();
        BillArchive.Outcome outcome = BillArchive.archiveNextMonth(rules());
        Test.stopTest();

        System.assertEquals(0, outcome.billsArchived);
        System.assertEquals(0, BillArchive.plan(rules()).billCount);
        System.assertEquals(1, [SELECT COUNT() FROM Bill__c]);
    }

    @isTest
    static void aCompanyWithoutGst_archivesByAgeAlone_andNeverReusesANumber() {
        update new Workshop_Profile__c(Id = company().Id, GST_Registration_Type__c = 'Unregistered');
        BillController.BillSummary old = bill(oldDay(), 1000);
        Integer oldSequence = [SELECT Invoice_Sequence__c FROM Bill__c WHERE Id = :old.billId].Invoice_Sequence__c.intValue();
        bill(Date.today(), 100);

        Test.startTest();
        BillArchive.archiveNextMonth(rules());
        BillController.BillSummary backDated = bill(oldDay().addDays(2), 300);
        Test.stopTest();

        Integer newSequence = [SELECT Invoice_Sequence__c FROM Bill__c WHERE Id = :backDated.billId].Invoice_Sequence__c.intValue();
        System.assertEquals(0, [SELECT COUNT() FROM Bill__c WHERE Id = :old.billId]);
        System.assertEquals(oldSequence + 1, newSequence, 'The archived number is not given out again.');
    }

    @isTest
    static void aBillWithANewerVersion_waitsForThatVersion() {
        BillController.BillSummary first = bill(oldDay(), 1000);
        BillController.CreateBillRequest change = new BillController.CreateBillRequest();
        change.customerId = customerId();
        change.billDate = Date.today().addDays(-1);
        change.lineItems = new List<BillController.LineItemInput>{ TestLines.line('Service', 1, 900, 18, 'CGST_SGST', '998714', null) };
        BillController.createNewVersion(first.billId, change);
        fileGstUpTo(Date.today().addDays(-1));

        Test.startTest();
        BillArchive.Outcome outcome = BillArchive.archiveNextMonth(rules());
        Test.stopTest();

        System.assertEquals(0, outcome.billsArchived, 'Its group reaches into a recent month.');
        System.assertEquals(2, [SELECT COUNT() FROM Bill__c]);
    }

    @isTest
    static void anInsuranceClaimsTwoBills_goTogether_andComeBackTogether() {
        BillController.BillSummary insurer = bill(oldDay(), 2000);
        BillController.BillSummary customer = bill(oldDay(), 500);
        update new List<Bill__c>{
            new Bill__c(Id = insurer.billId, Paired_Bill__c = customer.billId),
            new Bill__c(Id = customer.billId, Paired_Bill__c = insurer.billId)
        };
        fileGstUpTo(oldDay().addMonths(1).toStartOfMonth().addDays(-1));
        BillArchive.archiveNextMonth(rules());
        List<ArchiveStore.IndexEntry> index = ArchiveStore.index();
        System.assertEquals(2, index.size());
        System.assertEquals(index[0].g, index[1].g, 'One group.');

        Test.startTest();
        Id back = BillArchive.restore(insurer.billId);
        Test.stopTest();

        List<Bill__c> restored = [SELECT Id, Invoice_Number__c, Paired_Bill__c, Total_Amount__c FROM Bill__c ORDER BY Total_Amount__c];
        System.assertEquals(2, restored.size());
        System.assertEquals(insurer.invoiceNumber, [SELECT Invoice_Number__c FROM Bill__c WHERE Id = :back].Invoice_Number__c, 'Same number.');
        System.assertEquals(restored[1].Id, restored[0].Paired_Bill__c, 'Still paired, with the new Ids.');
        System.assertEquals(0, ArchiveStore.index().size(), 'Brought back: no longer listed in the archive.');
    }

    @isTest
    static void anArchivedBill_printsFromItsArchiveCopy() {
        BillController.BillSummary b = bill(oldDay(), 1000);
        fileGstUpTo(oldDay().addMonths(1).toStartOfMonth().addDays(-1));
        BillArchive.archiveNextMonth(rules());
        ArchiveStore.IndexEntry entry = ArchiveStore.index()[0];

        Test.startTest();
        PageReference page = Page.InvoicePdf;
        page.getParameters().put('id', entry.id);
        page.getParameters().put('archive', entry.f);
        Test.setCurrentPage(page);
        InvoicePdfController pdf = new InvoicePdfController();
        DocumentPdfService.PdfDownload download = DocumentPdfService.getArchivedPdfDownload(entry.id, entry.f);
        DocumentPdfService.PublicLink link = DocumentPdfService.getArchivedPublicLink(entry.id, entry.f);
        Test.stopTest();

        System.assertEquals(true, pdf.recordFound);
        System.assertEquals(b.invoiceNumber, pdf.documentNumber);
        System.assertEquals('Speedy Motors', pdf.workshopName, 'The company as it was when archived.');
        System.assertEquals(1, pdf.lines.size());
        System.assertEquals(1180, pdf.grandTotal);
        System.assertEquals(b.invoiceNumber.replace('/', '-') + '.pdf', download.fileName);
        System.assertEquals(b.invoiceNumber, link.documentNumber);
    }

    @isTest
    static void oldEstimates_areDeletedWithEveryVersion_recentOnesKept() {
        Estimate__c old = new Estimate__c(Customer__c = customerId(), Estimate_Date__c = Date.today().addMonths(-8));
        insert old;
        Estimate__c oldV2 = new Estimate__c(Customer__c = customerId(), Estimate_Date__c = Date.today().addMonths(-7), Root_Estimate__c = old.Id, Previous_Version__c = old.Id);
        insert oldV2;
        update new Estimate__c(Id = old.Id, Is_Latest_Version__c = false);
        insert new Estimate__c(Customer__c = customerId(), Estimate_Date__c = Date.today().addMonths(-2));

        Test.startTest();
        Integer counted = EstimatePurge.count(rules());
        Integer deleted = EstimatePurge.run(rules());
        Test.stopTest();

        System.assertEquals(2, counted);
        System.assertEquals(2, deleted);
        System.assertEquals(1, [SELECT COUNT() FROM Estimate__c]);
    }

    @isTest
    static void theNightlyJob_recordsWhatItDid() {
        bill(oldDay(), 1000);
        fileGstUpTo(oldDay().addMonths(1).toStartOfMonth().addDays(-1));
        ArchiveSettings.Rules r = rules();
        r.isOn = true;
        ArchiveSettings.save(r);

        Test.startTest();
        new BillEstimateFileCleanupScheduler().execute(null);
        Test.stopTest();

        ArchiveSettings.Rules after = rules();
        System.assertNotEquals(null, after.lastRun);
        System.assert(after.lastResult.startsWith('Archived 1 bill ('), after.lastResult);
        System.assertEquals(0, [SELECT COUNT() FROM Bill__c]);
    }

    @isTest
    static void settings_haveDefaults_andRefuseNonsense() {
        ArchiveSettings.Rules r = rules();
        System.assertEquals(false, r.isOn, 'Off until switched on.');
        System.assertEquals(18, r.billsAfterMonths);
        System.assertEquals(6, r.estimatesAfterMonths);
        System.assertEquals(24, r.customersDormantMonths);
        System.assertEquals(70, r.storageAlertPercent);

        r.billsAfterMonths = 2;
        String message;
        try {
            ArchiveSettings.save(r);
        } catch (ArchiveSettings.ArchiveSettingsException e) {
            message = e.getMessage();
        }
        System.assertEquals('Bills: type a number of months from 3 to 240.', message);

        r.billsAfterMonths = 12;
        r.estimatesAfterMonths = 3;
        ArchiveSettings.Rules saved = ArchiveSettings.save(r);
        System.assertEquals(12, saved.billsAfterMonths);
        System.assertEquals(3, saved.estimatesAfterMonths);
    }
}
