@isTest
private class WorkArchiveTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GST_Registration_Type__c = 'Unregistered', State__c = 'Madhya Pradesh',
            Address__c = 'AB Road, Indore', Job_Slip_Terms__c = 'Pay at delivery.');
        Customer__c ramesh = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111', Address__c = 'Indore');
        insert ramesh;
        Vehicle__c swift = new Vehicle__c(Name = 'MP09AB1234', Customer__c = ramesh.Id, Make__c = 'Maruti', Model__c = 'Swift');
        insert swift;
        insert new Job_Status_Stage__c(Name = 'Delivered', Sort_Order__c = 5, Is_Active__c = true);
        insert new Mechanic__c(Name = 'Anil', Is_Active__c = true);
    }

    private static ArchiveSettings.Rules rules() {
        return ArchiveSettings.current();
    }

    private static Id customerId() {
        return [SELECT Id FROM Customer__c WHERE Name = 'Ramesh Kumar'].Id;
    }

    private static Id vehicleId() {
        return [SELECT Id FROM Vehicle__c WHERE Name = 'MP09AB1234'].Id;
    }

    private static Job__c job(String notes) {
        Job__c j = new Job__c(Customer__c = customerId(), Vehicle__c = vehicleId(), Notes__c = notes,
            Job_Status_Stage__c = [SELECT Id FROM Job_Status_Stage__c LIMIT 1].Id);
        insert j;
        return j;
    }

    private static Job_Slip__c slip(Date d, String reason) {
        Job_Slip__c s = new Job_Slip__c(Customer__c = customerId(), Vehicle__c = vehicleId(), Slip_Date__c = d, Visit_Reason__c = reason,
            Workshop_Profile__c = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, Current_Km__c = 42000, Spare_Wheel__c = true,
            Repair_Lines__c = '[{"customerRequest":"Brake noise","observation":"Pads worn","labourEstimate":300,"sparesEstimate":900}]');
        insert s;
        return s;
    }

    // Records made in a test were all changed just now.
    private static void everyJobIsOld() {
        WorkArchive.jobsCutForTest = Datetime.now().addMinutes(1);
    }

    @isTest
    static void finishedJobs_goWithTheirMechanicsNames_unlessABillStillPointsAtThem() {
        Job__c done = job('Clutch replaced');
        insert new Job_Mechanic__c(Job__c = done.Id, Mechanic__c = [SELECT Id FROM Mechanic__c LIMIT 1].Id);
        Job__c billed = job('Service');
        BillController.CreateBillRequest req = new BillController.CreateBillRequest();
        req.customerId = customerId();
        req.jobId = billed.Id;
        req.billDate = Date.today();
        req.lineItems = new List<BillController.LineItemInput>{ TestLines.line('Service', 1, 500, 0, 'CGST_SGST', '998714', null) };
        BillController.createBill(req);
        everyJobIsOld();

        Test.startTest();
        WorkArchive.Plan plan = WorkArchive.plan(rules());
        WorkArchive.Outcome outcome = WorkArchive.archiveReady(rules());
        Test.stopTest();

        System.assertEquals(1, plan.jobs);
        System.assertEquals(1, outcome.jobs);
        System.assertEquals(0, [SELECT COUNT() FROM Job__c WHERE Id = :done.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Job_Mechanic__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Job__c WHERE Id = :billed.Id], 'Its bill keeps it.');

        List<ArchiveController.ArchivedWorkRow> rows = ArchiveController.customerHistory(customerId());
        System.assertEquals(1, rows.size());
        System.assertEquals('job', rows[0].kind);
        System.assertEquals('MP09AB1234', rows[0].vehicle);
        System.assertEquals('Delivered', rows[0].detail);
        ArchiveController.ArchivedJob shown = ArchiveController.getArchivedJob(rows[0].documentId, rows[0].recordId);
        System.assertEquals('Anil', shown.mechanicNames);
        System.assertEquals('Clutch replaced', shown.notes);
        System.assertEquals('MP09AB1234 Maruti Swift', shown.vehicle);
        System.assertEquals(false, WorkArchive.isDue(), 'The nightly run waits 28 days before archiving jobs again.');
    }

    @isTest
    static void oldJobSlips_go_andStillPrintAsTheyWere() {
        Job_Slip__c old = slip(Date.today().addMonths(-8), 'Brake noise');
        Job_Slip__c recent = slip(Date.today().addMonths(-1), 'Service');

        Test.startTest();
        WorkArchive.Outcome outcome = WorkArchive.archiveReady(rules());
        Test.stopTest();

        System.assertEquals(1, outcome.slips);
        System.assertEquals(0, [SELECT COUNT() FROM Job_Slip__c WHERE Id = :old.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Job_Slip__c WHERE Id = :recent.Id]);

        // The company's header changes later; the archived slip keeps the old one.
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, Name = 'Speedy Motors 2');
        ArchiveController.ArchivedWorkRow row = ArchiveController.customerHistory(customerId())[0];
        System.assertEquals('slip', row.kind);
        System.assertEquals('Brake noise', row.detail);
        PageReference page = Page.JobSlipPdf;
        page.getParameters().put('id', row.recordId);
        page.getParameters().put('archive', row.documentId);
        page.getParameters().put('format', 'html');
        Test.setCurrentPage(page);
        JobSlipPdfController pdf = new JobSlipPdfController();
        System.assertEquals(true, pdf.recordFound);
        System.assertEquals('Speedy Motors', pdf.workshopName);
        System.assertEquals('Ramesh Kumar', pdf.customerName);
        System.assertEquals('MP09AB1234', pdf.registrationNumber);
        System.assertEquals('Maruti Swift', pdf.makeModel);
        System.assertEquals('Brake noise', pdf.lines[0].customerRequest);
        System.assertEquals('Pay at delivery.', pdf.terms[0]);

        DocumentPdfService.PdfDownload download = DocumentPdfService.getArchivedPdfDownload(row.recordId, row.documentId);
        System.assert(download.fileName.endsWith('.pdf'), download.fileName);
        System.assertNotEquals(null, DocumentPdfService.getArchivedPublicLink(row.recordId, row.documentId));
    }

    @isTest
    static void anArchivedSlipsDate_keepsItsCustomerFromBeingDormant() {
        Datetime longAgo = Datetime.now().addMonths(-30);
        Test.setCreatedDate(customerId(), longAgo);
        Test.setCreatedDate(vehicleId(), longAgo);
        slip(Date.today().addMonths(-7), 'Service');
        CustomerArchive.recentTouchDays = -1;

        Test.startTest();
        WorkArchive.archiveReady(rules());
        CustomerArchive.Plan plan = CustomerArchive.plan(rules());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Job_Slip__c]);
        System.assertEquals(0, plan.customers, 'Seen seven months ago, on the archived slip.');
    }

    @isTest
    static void theArchiveScreen_countsJobsAndSlips_andTheJobSaysWhatItDid() {
        job('Old one');
        slip(Date.today().addMonths(-9), 'Old');
        everyJobIsOld();
        ArchiveController.Status before = ArchiveController.getStatus();

        Test.startTest();
        System.enqueueJob(new ArchiveJob(true));
        Test.stopTest();

        ArchiveController.Status after = ArchiveController.getStatus();
        System.assertEquals(1, before.jobsReady);
        System.assertEquals(1, before.slipsReady);
        System.assertEquals(1, after.archivedJobs);
        System.assertEquals(1, after.archivedSlips);
        String result = ArchiveSettings.current().lastResult;
        System.assert(result.contains('archived 1 finished job') && result.contains('archived 1 job slip'), result);
    }
}
