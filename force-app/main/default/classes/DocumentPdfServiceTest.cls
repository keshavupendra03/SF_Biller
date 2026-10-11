@isTest
private class DocumentPdfServiceTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static BillController.LineItemInput line() {
        BillController.LineItemInput li = new BillController.LineItemInput();
        li.description = 'Service';
        li.quantity = 1;
        li.unitPrice = 500;
        li.taxRatePercent = 18;
        return li;
    }

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        return customer.Id;
    }

    @isTest
    static void getPdfDownload_forBill_returnsSanitizedFileNameAndData() {
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = insertCustomer();
        request.lineItems = new List<BillController.LineItemInput>{ line() };
        BillController.BillSummary bill = BillController.createBill(request);

        Test.startTest();
        DocumentPdfService.PdfDownload download = DocumentPdfService.getPdfDownload(bill.billId);
        Test.stopTest();

        System.assertEquals(bill.invoiceNumber.replace('/', '-') + '.pdf', download.fileName);
        System.assertEquals(EncodingUtil.base64Encode(Blob.valueOf('test-pdf')), download.base64Data);
    }

    @isTest
    static void getPdfDownload_forEstimate_usesEstimateNumber() {
        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = insertCustomer();
        request.lineItems = new List<BillController.LineItemInput>{ line() };
        EstimateController.EstimateSummary estimate = EstimateController.createEstimate(request);

        Test.startTest();
        DocumentPdfService.PdfDownload download = DocumentPdfService.getPdfDownload(estimate.estimateId);
        Test.stopTest();

        System.assertEquals(estimate.estimateNumber + '.pdf', download.fileName);
    }

    private static BillController.BillSummary createBill() {
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = insertCustomer();
        request.lineItems = new List<BillController.LineItemInput>{ line() };
        return BillController.createBill(request);
    }

    @isTest
    static void getPublicLink_firstCall_attachesFileAndCreatesExpiringLink() {
        BillController.BillSummary bill = createBill();

        Test.startTest();
        DocumentPdfService.PublicLink link = DocumentPdfService.getPublicLink(bill.billId);
        Test.stopTest();

        System.assertNotEquals(null, link.downloadUrl);
        System.assertEquals(bill.invoiceNumber, link.documentNumber);
        Id billId = bill.billId;
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :billId]);
    }

    @isTest
    static void getPublicLink_calledAgain_reusesSameFileAndDistributionButAFreshVersionLink() {
        BillController.BillSummary bill = createBill();

        Test.startTest();
        DocumentPdfService.PublicLink first = DocumentPdfService.getPublicLink(bill.billId);
        DocumentPdfService.PublicLink second = DocumentPdfService.getPublicLink(bill.billId);
        Test.stopTest();

        // downloadUrl points at a specific ContentVersion, so it's expected
        // to change on every call — what must stay the same across calls is
        // the underlying File (ContentDocument) and its one Distribution.
        System.assertNotEquals(first.downloadUrl, second.downloadUrl);
        Id billId = bill.billId;
        Id documentId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :billId].ContentDocumentId;
        System.assertEquals(2, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :documentId]);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDistribution WHERE ContentDocumentId = :documentId]);
    }

    @isTest
    static void getPublicLink_inTestContext_doesNotScheduleCleanup() {
        BillController.BillSummary bill = createBill();
        Integer before = [SELECT COUNT() FROM CronTrigger];

        Test.startTest();
        DocumentPdfService.getPublicLink(bill.billId);
        Test.stopTest();

        System.assertEquals(before, [SELECT COUNT() FROM CronTrigger], 'Test.isRunningTest() must skip System.scheduleBatch, or every test run would leave a CronTrigger behind.');
    }

    @isTest
    static void getPdfDownload_unsupportedRecord_throws() {
        Id customerId = insertCustomer();
        Boolean threw = false;
        try {
            DocumentPdfService.getPdfDownload(customerId);
        } catch (DocumentPdfService.DocumentPdfServiceException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }
}
