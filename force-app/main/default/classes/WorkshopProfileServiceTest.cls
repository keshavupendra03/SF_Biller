@isTest
private class WorkshopProfileServiceTest {

    private static Workshop_Profile__c insertTwoCompanies() {
        Workshop_Profile__c first = new Workshop_Profile__c(Name = 'Speedy Motors', GSTIN__c = '23AAAAA0000A1Z5');
        insert first;
        Workshop_Profile__c second = new Workshop_Profile__c(Name = 'Speedy Decor', GSTIN__c = '23BBBBB0000B1Z5', Invoice_Prefix__c = 'DEC');
        insert second;
        return second;
    }

    private static BillController.LineItemInput line() {
        BillController.LineItemInput li = new BillController.LineItemInput();
        li.description = 'Seat Covers';
        li.quantity = 1;
        li.unitPrice = 1000;
        li.taxRatePercent = 18;
        return li;
    }

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        return customer.Id;
    }

    private static BillController.BillSummary createBill(Id customerId, Id companyId) {
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        request.workshopProfileId = companyId;
        request.lineItems = new List<BillController.LineItemInput>{ line() };
        return BillController.createBill(request);
    }

    private static EstimateController.EstimateSummary createEstimate(Id customerId, Id companyId) {
        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = customerId;
        request.workshopProfileId = companyId;
        request.lineItems = new List<BillController.LineItemInput>{ line() };
        return EstimateController.createEstimate(request);
    }

    private static InvoicePdfController printed(Id recordId) {
        PageReference page = Page.InvoicePdf;
        page.getParameters().put('id', recordId);
        Test.setCurrentPage(page);
        return new InvoicePdfController();
    }

    // ---- the limit of two ------------------------------------------------

    @isTest
    static void aThirdCompanyIsRefused_evenAddedDirectly() {
        insertTwoCompanies();

        Boolean refused = false;
        try {
            insert new Workshop_Profile__c(Name = 'Third', Invoice_Prefix__c = 'THR');
        } catch (DmlException e) {
            refused = e.getDmlMessage(0).contains('only have 2');
        }
        System.assertEquals(true, refused);
        System.assertEquals(2, [SELECT COUNT() FROM Workshop_Profile__c]);
    }

    @isTest
    static void threeInOneInsertAreRefused() {
        Boolean refused = false;
        try {
            insert new List<Workshop_Profile__c>{
                new Workshop_Profile__c(Name = 'A', Invoice_Prefix__c = 'AAA'),
                new Workshop_Profile__c(Name = 'B', Invoice_Prefix__c = 'BBB'),
                new Workshop_Profile__c(Name = 'C', Invoice_Prefix__c = 'CCC')
            };
        } catch (DmlException e) {
            refused = true;
        }
        System.assertEquals(true, refused);
        System.assertEquals(0, [SELECT COUNT() FROM Workshop_Profile__c]);
    }

    @isTest
    static void addProfile_refusesAThirdWithAMessageTheScreenCanShow() {
        insertTwoCompanies();
        WorkshopProfileController.ProfileData input = new WorkshopProfileController.ProfileData();
        input.name = 'Third';
        input.invoicePrefix = 'THR';

        String message;
        try {
            WorkshopProfileController.addProfile(input);
        } catch (WorkshopProfileController.WorkshopProfileControllerException e) {
            message = e.getMessage();
        }
        System.assert(message != null && message.contains('only have 2'), message);
    }

    // ---- invoice prefixes ------------------------------------------------

    @isTest
    static void prefixes_mustDifferAndBeShort() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');

        List<Workshop_Profile__c> bad = new List<Workshop_Profile__c>{
            new Workshop_Profile__c(Name = 'Blank prefix means INV'),
            new Workshop_Profile__c(Name = 'Same as default', Invoice_Prefix__c = 'inv'),
            new Workshop_Profile__c(Name = 'Symbol', Invoice_Prefix__c = 'D/C')
        };
        for (Workshop_Profile__c profile : bad) {
            Boolean refused = false;
            try {
                insert profile;
            } catch (DmlException e) {
                refused = true;
            }
            System.assertEquals(true, refused, profile.Name);
        }

        Workshop_Profile__c good = new Workshop_Profile__c(Name = 'Decor', Invoice_Prefix__c = 'dec');
        insert good;
        System.assertEquals('DEC', [SELECT Invoice_Prefix__c FROM Workshop_Profile__c WHERE Id = :good.Id].Invoice_Prefix__c);
    }

    @isTest
    static void changingAPrefixToTheOtherCompanysIsRefused() {
        Workshop_Profile__c second = insertTwoCompanies();

        Boolean refused = false;
        try {
            update new Workshop_Profile__c(Id = second.Id, Invoice_Prefix__c = 'INV');
        } catch (DmlException e) {
            refused = true;
        }
        System.assertEquals(true, refused);
    }

    // ---- numbering -------------------------------------------------------

    @isTest
    static void eachCompanyHasItsOwnInvoiceSeries() {
        Workshop_Profile__c second = insertTwoCompanies();
        Id customerId = insertCustomer();

        Test.startTest();
        String first1 = createBill(customerId, null).invoiceNumber;
        String decor1 = createBill(customerId, second.Id).invoiceNumber;
        String first2 = createBill(customerId, WorkshopProfileService.primaryId()).invoiceNumber;
        String decor2 = createBill(customerId, second.Id).invoiceNumber;
        Test.stopTest();

        String fy = InvoiceNumberingService.financialYearFor(Date.today());
        System.assertEquals('INV/' + fy + '/0001', first1);
        System.assertEquals('INV/' + fy + '/0002', first2);
        System.assertEquals('DEC/' + fy + '/0001', decor1);
        System.assertEquals('DEC/' + fy + '/0002', decor2);
        System.assert(decor2.length() <= 16, 'GST limits an invoice number to 16 characters.');
    }

    @isTest
    static void aBillWithNoCompanyGoesToThePrimaryOne() {
        insertTwoCompanies();

        Test.startTest();
        BillController.BillSummary summary = createBill(insertCustomer(), null);
        Test.stopTest();

        System.assertEquals(WorkshopProfileService.primaryId(), summary.workshopProfileId);
        System.assertEquals('Speedy Motors', summary.companyName);
    }

    // ---- printed documents -----------------------------------------------

    @isTest
    static void billPrintsTheCompanyItWasMadeFor() {
        Workshop_Profile__c second = insertTwoCompanies();
        Id customerId = insertCustomer();
        BillController.BillSummary decor = createBill(customerId, second.Id);
        BillController.BillSummary main = createBill(customerId, null);

        Test.startTest();
        InvoicePdfController decorPdf = printed(decor.billId);
        InvoicePdfController mainPdf = printed(main.billId);
        Test.stopTest();

        System.assertEquals('Speedy Decor', decorPdf.workshopName);
        System.assertEquals('23BBBBB0000B1Z5', decorPdf.workshopGstin);
        System.assertEquals('Speedy Motors', mainPdf.workshopName);
        System.assertEquals('23AAAAA0000A1Z5', mainPdf.workshopGstin);
    }

    @isTest
    static void estimatePrintsTheCompanyItWasMadeFor() {
        Workshop_Profile__c second = insertTwoCompanies();

        Test.startTest();
        EstimateController.EstimateSummary decor = createEstimate(insertCustomer(), second.Id);
        InvoicePdfController pdf = printed(decor.estimateId);
        Test.stopTest();

        System.assertEquals(second.Id, decor.workshopProfileId);
        System.assertEquals('Speedy Decor', decor.companyName);
        System.assertEquals('Speedy Decor', pdf.workshopName);
    }

    @isTest
    static void documentsFromBeforeASecondCompanyStillPrintThePrimaryOne() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
        Id customerId = insertCustomer();
        BillController.BillSummary old = createBill(customerId, null);
        update new Bill__c(Id = old.billId, Workshop_Profile__c = null);
        insert new Workshop_Profile__c(Name = 'Speedy Decor', Invoice_Prefix__c = 'DEC');

        Test.startTest();
        InvoicePdfController pdf = printed(old.billId);
        Test.stopTest();

        System.assertEquals('Speedy Motors', pdf.workshopName);
    }

    // ---- versions and conversion -----------------------------------------

    @isTest
    static void aNewVersionStaysWithTheSameCompanyAndSeries() {
        Workshop_Profile__c second = insertTwoCompanies();
        Id customerId = insertCustomer();
        BillController.BillSummary first = createBill(customerId, second.Id);

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        request.workshopProfileId = WorkshopProfileService.primaryId();
        request.lineItems = new List<BillController.LineItemInput>{ line() };

        Test.startTest();
        BillController.BillSummary next = BillController.createNewVersion(first.billId, request);
        Test.stopTest();

        System.assertEquals(second.Id, next.workshopProfileId, 'A later version cannot move to the other company.');
        System.assert(next.invoiceNumber.startsWith('DEC/'), next.invoiceNumber);
    }

    @isTest
    static void aNewEstimateVersionStaysWithTheSameCompany() {
        Workshop_Profile__c second = insertTwoCompanies();
        Id customerId = insertCustomer();
        EstimateController.EstimateSummary first = createEstimate(customerId, second.Id);

        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = customerId;
        request.lineItems = new List<BillController.LineItemInput>{ line() };

        Test.startTest();
        EstimateController.EstimateSummary next = EstimateController.createNewVersion(first.estimateId, request);
        Test.stopTest();

        System.assertEquals(second.Id, next.workshopProfileId);
    }

    @isTest
    static void aBillMadeFromAnEstimateDefaultsToTheEstimatesCompany() {
        Workshop_Profile__c second = insertTwoCompanies();
        Id customerId = insertCustomer();
        EstimateController.EstimateSummary estimate = createEstimate(customerId, second.Id);

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        request.sourceEstimateId = estimate.estimateId;
        request.lineItems = new List<BillController.LineItemInput>{ line() };

        Test.startTest();
        BillController.BillSummary bill = BillController.createBill(request);
        Test.stopTest();

        System.assertEquals(second.Id, bill.workshopProfileId);
    }

    // ---- quick screens ---------------------------------------------------

    @isTest
    static void quickAndEasyScreensUseTheSelectedCompany() {
        Workshop_Profile__c second = insertTwoCompanies();

        QuickBillController.QuickBillRequest quick = new QuickBillController.QuickBillRequest();
        quick.isWalkIn = true;
        quick.workshopProfileId = second.Id;
        quick.lineItems = new List<BillController.LineItemInput>{ line() };

        PaperBillController.PaperRequest paper = new PaperBillController.PaperRequest();
        paper.documentType = 'estimate';
        paper.workshopProfileId = second.Id;
        paper.lineItems = new List<BillController.LineItemInput>{ line() };

        Test.startTest();
        BillController.BillSummary quickBill = QuickBillController.createQuickBill(quick);
        quick.lineItems = new List<BillController.LineItemInput>{ line() };
        EstimateController.EstimateSummary quickEstimate = QuickBillController.createQuickEstimate(quick);
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(paper);
        Test.stopTest();

        System.assert(quickBill.invoiceNumber.startsWith('DEC/'), quickBill.invoiceNumber);
        System.assertEquals(second.Id, quickEstimate.workshopProfileId);
        System.assertEquals(second.Id, [SELECT Workshop_Profile__c FROM Estimate__c WHERE Id = :saved.recordId].Workshop_Profile__c);
    }

    @isTest
    static void easyBill_editingTheSelectedCompanyOnlyChangesThatCompany() {
        Workshop_Profile__c second = insertTwoCompanies();
        PaperBillController.PaperRequest paper = new PaperBillController.PaperRequest();
        paper.workshopProfileId = second.Id;
        paper.lineItems = new List<BillController.LineItemInput>{ line() };
        paper.workshop = new WorkshopProfileController.ProfileData();
        paper.workshop.id = second.Id;
        paper.workshop.name = 'Speedy Car Decor';
        paper.workshop.invoicePrefix = 'DEC';

        Test.startTest();
        PaperBillController.saveDocument(paper);
        Test.stopTest();

        System.assertEquals('Speedy Car Decor', [SELECT Name FROM Workshop_Profile__c WHERE Id = :second.Id].Name);
        System.assertEquals('Speedy Motors', [SELECT Name FROM Workshop_Profile__c WHERE Id = :WorkshopProfileService.primaryId()].Name);
    }

    // ---- job slips -------------------------------------------------------

    private static JobSlipPdfController printedSlip(Id recordId, Id companyId) {
        PageReference page = Page.JobSlipPdf;
        page.getParameters().put('id', recordId);
        if (companyId != null) {
            page.getParameters().put('workshop', companyId);
        }
        Test.setCurrentPage(page);
        return new JobSlipPdfController();
    }

    @isTest
    static void jobSlipsPrintTheirCompany() {
        Workshop_Profile__c second = insertTwoCompanies();
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;

        JobSlipController.JobSlipData input = new JobSlipController.JobSlipData();
        input.customerId = customerId;
        input.vehicleId = vehicle.Id;
        input.workshopProfileId = second.Id;

        Test.startTest();
        Id slipId = JobSlipController.saveJobSlip(input);
        JobSlipController.JobSlipForm form = JobSlipController.getJobSlipForm(slipId, null, null);
        System.assertEquals(second.Id, form.slip.workshopProfileId);
        System.assertEquals('Speedy Decor', printedSlip(slipId, null).workshopName);
        System.assertEquals('Speedy Decor', printedSlip(second.Id, null).workshopName, 'Completely blank slip for that company.');
        System.assertEquals('Speedy Decor', printedSlip(customerId, second.Id).workshopName, 'Blank slip for a customer, for that company.');
        System.assertEquals('Speedy Motors', printedSlip(customerId, null).workshopName);
        Test.stopTest();
    }

    // ---- screens listing and naming companies ----------------------------

    @isTest
    static void listProfiles_putsThePrimaryFirst() {
        Workshop_Profile__c second = insertTwoCompanies();

        Test.startTest();
        List<WorkshopProfileController.ProfileData> profiles = WorkshopProfileController.listProfiles();
        Test.stopTest();

        System.assertEquals(2, profiles.size());
        System.assertEquals('Speedy Motors', profiles[0].name);
        System.assertEquals(true, profiles[0].isPrimary);
        System.assertEquals('INV', profiles[0].invoicePrefix);
        System.assertEquals(second.Id, profiles[1].id);
        System.assertEquals(false, profiles[1].isPrimary);
        System.assertEquals('DEC', profiles[1].invoicePrefix);
    }

    @isTest
    static void saveProfile_updatesOnlyTheCompanyGiven() {
        Workshop_Profile__c second = insertTwoCompanies();
        WorkshopProfileController.ProfileData input = new WorkshopProfileController.ProfileData();
        input.id = second.Id;
        input.name = 'Renamed Decor';
        input.invoicePrefix = 'DEC';

        Test.startTest();
        WorkshopProfileController.ProfileData saved = WorkshopProfileController.saveProfile(input);
        Test.stopTest();

        System.assertEquals(second.Id, saved.id);
        System.assertEquals('Renamed Decor', saved.name);
        System.assertEquals(2, [SELECT COUNT() FROM Workshop_Profile__c]);
        System.assertEquals('Speedy Motors', [SELECT Name FROM Workshop_Profile__c WHERE Id = :WorkshopProfileService.primaryId()].Name);
    }

    @isTest
    static void saveProfile_badPrefixGivesAMessageTheScreenCanShow() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
        WorkshopProfileController.ProfileData input = new WorkshopProfileController.ProfileData();
        input.name = 'Decor';
        input.invoicePrefix = 'INV';

        String message;
        try {
            WorkshopProfileController.addProfile(input);
        } catch (WorkshopProfileController.WorkshopProfileControllerException e) {
            message = e.getMessage();
        }
        System.assert(message != null && message.contains('own invoice prefix'), message);
    }

    @isTest
    static void billingList_filtersByCompany_andOldBillsCountAsPrimary() {
        Workshop_Profile__c second = insertTwoCompanies();
        Id customerId = insertCustomer();
        BillController.BillSummary main = createBill(customerId, null);
        BillController.BillSummary decor = createBill(customerId, second.Id);
        BillController.BillSummary old = createBill(customerId, null);
        update new Bill__c(Id = old.billId, Workshop_Profile__c = null);

        Test.startTest();
        List<BillController.BillListItem> all = BillController.listBills('All', '', null);
        List<BillController.BillListItem> decorOnly = BillController.listBills('All', '', second.Id);
        List<BillController.BillListItem> mainOnly = BillController.listBills('All', 'INV', WorkshopProfileService.primaryId());
        Test.stopTest();

        System.assertEquals(3, all.size());
        System.assertEquals(1, decorOnly.size());
        System.assertEquals(decor.billId, decorOnly[0].id);
        System.assertEquals('Speedy Decor', decorOnly[0].companyName);
        System.assertEquals(2, mainOnly.size());
    }

    @isTest
    static void withOneCompany_noCompanyNameAppearsAnywhere() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
        Id customerId = insertCustomer();
        BillController.BillSummary bill = createBill(customerId, null);
        EstimateController.EstimateSummary estimate = createEstimate(customerId, null);

        Test.startTest();
        CustomerController.CustomerDetail detail = CustomerController.getCustomerDetail(customerId);
        List<BillController.BillListItem> bills = BillController.listBills('All', '', null);
        Test.stopTest();

        System.assertEquals(null, bill.companyName);
        System.assertEquals(null, estimate.companyName);
        System.assertEquals(null, bills[0].companyName);
        System.assertEquals(null, detail.bills[0].companyName);
    }

    @isTest
    static void customerDetail_namesTheCompanyOnEachDocument() {
        Workshop_Profile__c second = insertTwoCompanies();
        Id customerId = insertCustomer();
        createBill(customerId, second.Id);
        createEstimate(customerId, null);

        Test.startTest();
        CustomerController.CustomerDetail detail = CustomerController.getCustomerDetail(customerId);
        Test.stopTest();

        System.assertEquals('Speedy Decor', detail.bills[0].companyName);
        System.assertEquals('Speedy Motors', detail.estimates[0].companyName);
    }
}
