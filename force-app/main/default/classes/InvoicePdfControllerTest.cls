@isTest
private class InvoicePdfControllerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(
            Name = 'Speedy Motors',
            Address__c = '6 Durga Plaza Dewas Road Ujjain',
            Phone__c = '9039472001',
            GSTIN__c = '23ABCDE1234F1Z5',
            State__c = '23-Madhya Pradesh',
            Bank_Name__c = 'Yes Bank',
            Bank_Account_No__c = '139626900001772',
            Bank_IFSC__c = 'YESB0001396',
            Bank_Account_Holder__c = 'Speedy Motors'
        );
    }

    private static Id insertBillWithLines() {
        Customer__c customer = new Customer__c(
            Name = 'Ramesh Kumar', Phone__c = '9000011111', GSTIN__c = '23ABCDE1234F1Z5'
        );
        insert customer;
        Bill__c bill = new Bill__c(Customer__c = customer.Id, Notes__c = 'Front bumper repair');
        insert bill;
        insert new Bill_Line_Item__c(
            Bill__c = bill.Id,
            Description__c = 'Brake Pad',
            HSN_SAC_Code__c = '8708',
            Quantity__c = 2,
            Unit__c = 'Pcs',
            Unit_Price__c = 500,
            Tax_Rate_Percent__c = 18,
            Gst_Type__c = 'CGST_SGST'
        );
        insert new Payment__c(Bill__c = bill.Id, Amount__c = 700, Method__c = 'Cash');
        return bill.Id;
    }

    private static Id insertEstimateWithLines() {
        Customer__c customer = new Customer__c(Name = 'Deepak', Phone__c = '9333344444');
        insert customer;
        Estimate__c estimate = new Estimate__c(Customer__c = customer.Id, Status__c = 'Draft');
        insert estimate;
        insert new Estimate_Line_Item__c(
            Estimate__c = estimate.Id,
            Description__c = 'Diagnostic Fee',
            Quantity__c = 1,
            Unit_Price__c = 500,
            Tax_Rate_Percent__c = 18
        );
        return estimate.Id;
    }

    @isTest
    static void billRecord_populatesInvoiceLabelsAndTotals() {
        Id billId = insertBillWithLines();

        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', billId);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals(true, controller.recordFound);
        System.assertEquals(false, controller.isEstimate);
        System.assertEquals('Tax Invoice', controller.documentTitle);
        System.assertEquals('Bill To', controller.billToLabel);
        System.assertEquals('Invoice Details', controller.detailsLabel);
        System.assertEquals('Invoice No.', controller.numberLabel);
        System.assertEquals(true, controller.showPayment);
        System.assertEquals('Ramesh Kumar', controller.billToName);
        System.assertEquals(1000, controller.subtotal);
        System.assertEquals(90, controller.cgst);
        System.assertEquals(90, controller.sgst);
        System.assertEquals(false, controller.showIgst);
        System.assertEquals(1180, controller.grandTotal);
        System.assertEquals(700, controller.amountPaid);
        System.assertEquals(480, controller.amountDue);
        System.assertEquals('Cash', controller.paymentMode);
        System.assertEquals(1, controller.lines.size());
        System.assertEquals('Brake Pad', controller.lines[0].description);
        System.assertEquals(500, controller.lines[0].unitPrice);
        System.assert(controller.amountInWords.contains('Rupees'));
    }

    @isTest
    static void billWithMixedGstTypeLines_showsIgstBucketAndOmitsCgstSgst() {
        Customer__c customer = new Customer__c(Name = 'Out Of State Co', Phone__c = '9000099999');
        insert customer;
        Bill__c bill = new Bill__c(Customer__c = customer.Id);
        insert bill;
        insert new Bill_Line_Item__c(
            Bill__c = bill.Id, Description__c = 'Export part',
            Quantity__c = 2, Unit_Price__c = 500, Tax_Rate_Percent__c = 18, Gst_Type__c = 'IGST'
        );

        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', bill.Id);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals(true, controller.showIgst);
        System.assertEquals(180, controller.igst);
        System.assertEquals(0, controller.cgst);
        System.assertEquals(0, controller.sgst);
    }

    @isTest
    static void estimateRecord_populatesEstimateLabelsAndOmitsPaymentFields() {
        Id estimateId = insertEstimateWithLines();

        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', estimateId);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals(true, controller.recordFound);
        System.assertEquals(true, controller.isEstimate);
        System.assertEquals('Estimate', controller.documentTitle);
        System.assertEquals('Estimated For', controller.billToLabel);
        System.assertEquals('Estimate Details', controller.detailsLabel);
        System.assertEquals('Estimate No.', controller.numberLabel);
        System.assertEquals(false, controller.showPayment);
        System.assertEquals('Deepak', controller.billToName);
        System.assertEquals(590, controller.grandTotal); // 500 + 18%
        System.assert(controller.documentNumber.startsWith('EST-'));
    }

    @isTest
    static void billToPartyPresent_printsBuyersNameSeparatelyFromBillTo() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Bill_To_Party__c party = new Bill_To_Party__c(Name = 'IFFCO TOKIO GIC LTD');
        insert party;
        Bill__c bill = new Bill__c(Customer__c = customer.Id, Bill_To_Party__c = party.Id);
        insert bill;

        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', bill.Id);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals('IFFCO TOKIO GIC LTD', controller.billToName);
        System.assertEquals('Ramesh Kumar', controller.buyersName);
    }

    @isTest
    static void billWithVehicle_populatesVehicleRegNumberAndMakeModel() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Vehicle__c vehicle = new Vehicle__c(
            Name = 'MH12AB1234', Customer__c = customer.Id, Make__c = 'Honda', Model__c = 'City',
            Chassis_Number__c = 'MA3ERLF1S00123456'
        );
        insert vehicle;
        Bill__c bill = new Bill__c(Customer__c = customer.Id, Vehicle__c = vehicle.Id);
        insert bill;

        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', bill.Id);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals('MH12AB1234', controller.vehicleRegNumber);
        System.assertEquals('Honda City', controller.vehicleMakeModel);
        System.assertEquals('MA3ERLF1S00123456', controller.vehicleChassisNumber);
    }

    @isTest
    static void estimateWithVehicle_populatesVehicleRegNumberAndMakeModel() {
        Customer__c customer = new Customer__c(Name = 'Deepak', Phone__c = '9333344444');
        insert customer;
        Vehicle__c vehicle = new Vehicle__c(
            Name = 'MP09ZZ9999', Customer__c = customer.Id, Make__c = 'Maruti', Model__c = 'Swift',
            Chassis_Number__c = 'MALA851ALKM123456'
        );
        insert vehicle;
        Estimate__c estimate = new Estimate__c(Customer__c = customer.Id, Vehicle__c = vehicle.Id);
        insert estimate;

        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', estimate.Id);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals('MP09ZZ9999', controller.vehicleRegNumber);
        System.assertEquals('Maruti Swift', controller.vehicleMakeModel);
        System.assertEquals('MALA851ALKM123456', controller.vehicleChassisNumber);
    }

    @isTest
    static void billWithNoOwnVehicleButJobVehicle_fallsBackToTheJobsVehicle() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Vehicle__c vehicle = new Vehicle__c(
            Name = 'MP09AB1234', Customer__c = customer.Id, Make__c = 'Hyundai', Model__c = 'i20',
            Chassis_Number__c = 'MALA851ALKM123456'
        );
        insert vehicle;
        Job_Status_Stage__c stage = new Job_Status_Stage__c(Name = 'Received', Sort_Order__c = 1);
        insert stage;
        Job__c job = new Job__c(Customer__c = customer.Id, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stage.Id);
        insert job;
        Bill__c bill = new Bill__c(Customer__c = customer.Id, Job__c = job.Id);
        insert bill;

        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', bill.Id);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals('MP09AB1234', controller.vehicleRegNumber, 'Older bills with no Vehicle__c of their own must still show the vehicle carried on their Job.');
        System.assertEquals('Hyundai i20', controller.vehicleMakeModel);
        System.assertEquals('MALA851ALKM123456', controller.vehicleChassisNumber, 'Chassis number must also fall back to the Job\'s vehicle, same as reg number and make/model.');
    }

    @isTest
    static void billWithOwnVehicleAndDifferentJobVehicle_prefersItsOwnVehicle() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Vehicle__c jobVehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customer.Id);
        insert jobVehicle;
        Vehicle__c ownVehicle = new Vehicle__c(Name = 'MH12CD5678', Customer__c = customer.Id);
        insert ownVehicle;
        Job_Status_Stage__c stage = new Job_Status_Stage__c(Name = 'Received', Sort_Order__c = 1);
        insert stage;
        Job__c job = new Job__c(Customer__c = customer.Id, Vehicle__c = jobVehicle.Id, Job_Status_Stage__c = stage.Id);
        insert job;
        Bill__c bill = new Bill__c(Customer__c = customer.Id, Job__c = job.Id, Vehicle__c = ownVehicle.Id);
        insert bill;

        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', bill.Id);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals('MH12CD5678', controller.vehicleRegNumber);
    }

    @isTest
    static void noIdParameter_recordNotFoundButNoException() {
        Test.setCurrentPageReference(Page.InvoicePdf);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals(false, controller.recordFound);
    }

    @isTest
    static void formatParameter_switchesBetweenHtmlPreviewAndPdf() {
        Id billId = insertBillWithLines();
        PageReference htmlPage = Page.InvoicePdf;
        htmlPage.getParameters().put('id', billId);
        htmlPage.getParameters().put('format', 'html');
        Test.setCurrentPageReference(htmlPage);

        Test.startTest();
        InvoicePdfController htmlController = new InvoicePdfController();
        PageReference pdfPage = Page.InvoicePdf;
        pdfPage.getParameters().put('id', billId);
        Test.setCurrentPageReference(pdfPage);
        InvoicePdfController pdfController = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals('', htmlController.renderAs);
        System.assertEquals(true, htmlController.recordFound);
        System.assertEquals('pdf', pdfController.renderAs);
    }

    // Deliberately no automated test of actual PDF byte output:
    // PageReference.getContent()/getContentAsPDF() cannot be called from
    // within an Apex test method at all (a hard Salesforce platform
    // restriction) — "Methods defined as TestMethod do not support
    // getContent call". The tests above cover everything Apex *can*
    // verify — the controller assembles correct data for both document
    // types — the actual byte-level PDF rendering needs manual UAT:
    // opening /apex/InvoicePdf?id=<recordId> in a browser.
}
