@isTest
private class BillControllerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        return customer.Id;
    }

    @isTest
    static void createBill_withPartAndManualLines_createsEverythingAndDeductsStock() {
        Id customerId = insertCustomer();
        Part__c part = new Part__c(Name = 'Brake Pad', Price__c = 500, Tax_Rate_Percent__c = 18, Gst_Type__c = 'CGST_SGST');
        insert part;

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        request.notes = 'Routine service';

        BillController.LineItemInput partLine = new BillController.LineItemInput();
        partLine.partId = part.Id;
        partLine.description = 'Brake Pad';
        partLine.quantity = 2;
        partLine.unitPrice = 500;
        partLine.taxRatePercent = 18;
        partLine.gstType = 'CGST_SGST';

        BillController.LineItemInput labourLine = new BillController.LineItemInput();
        labourLine.description = 'Labour';
        labourLine.quantity = 1;
        labourLine.unitPrice = 300;
        labourLine.taxRatePercent = 0;

        request.lineItems = new List<BillController.LineItemInput>{ partLine, labourLine };

        Test.startTest();
        BillController.BillSummary summary = BillController.createBill(request);
        Test.stopTest();

        System.assert(summary.invoiceNumber.startsWith('INV/'), 'Expected an assigned invoice number.');
        System.assertEquals(1300, summary.subtotal);
        System.assertEquals(90, summary.cgst);
        System.assertEquals(90, summary.sgst);
        System.assertEquals(0, summary.igst);
        System.assertEquals(1480, summary.totalAmount);
        System.assertEquals('Unpaid', summary.status);

        Part__c updatedPart = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(-2, updatedPart.Current_Stock__c);

        System.assertEquals(2, [SELECT COUNT() FROM Bill_Line_Item__c WHERE Bill__c = :summary.billId]);
    }

    @isTest
    static void createBill_withInitialPayment_setsStatusFromThatPayment() {
        Id customerId = insertCustomer();

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 1000;
        line.taxRatePercent = 0;
        request.lineItems = new List<BillController.LineItemInput>{ line };
        request.initialPaymentAmount = 1000;
        request.initialPaymentMethod = 'UPI';

        Test.startTest();
        BillController.BillSummary summary = BillController.createBill(request);
        Test.stopTest();

        System.assertEquals('Paid', summary.status);
        System.assertEquals(1, [SELECT COUNT() FROM Payment__c WHERE Bill__c = :summary.billId]);
    }

    @isTest
    static void createBill_withNewBillToParty_createsAndLinksIt() {
        Id customerId = insertCustomer();

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        BillController.NewBillToPartyInput party = new BillController.NewBillToPartyInput();
        party.name = 'Acme Logistics Pvt Ltd';
        party.gstin = '27AAACA1234A1Z5';
        party.state = 'Maharashtra';
        request.newBillToParty = party;

        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Fleet service';
        line.quantity = 1;
        line.unitPrice = 2000;
        line.taxRatePercent = 18;
        request.lineItems = new List<BillController.LineItemInput>{ line };

        Test.startTest();
        BillController.BillSummary summary = BillController.createBill(request);
        Test.stopTest();

        Bill__c bill = [SELECT Bill_To_Party__c, Bill_To_Party__r.Name FROM Bill__c WHERE Id = :summary.billId];
        System.assertNotEquals(null, bill.Bill_To_Party__c);
        System.assertEquals('Acme Logistics Pvt Ltd', bill.Bill_To_Party__r.Name);
    }

    @isTest
    static void createBill_mixedGstTypes_breakdownSplitsCorrectly() {
        Id customerId = insertCustomer();

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;

        BillController.LineItemInput local = new BillController.LineItemInput();
        local.description = 'Local part';
        local.quantity = 2;
        local.unitPrice = 500;
        local.taxRatePercent = 18;
        local.gstType = 'CGST_SGST';

        BillController.LineItemInput interstate = new BillController.LineItemInput();
        interstate.description = 'Out-of-state part';
        interstate.quantity = 5;
        interstate.unitPrice = 240;
        interstate.taxRatePercent = 28;
        interstate.gstType = 'IGST';

        request.lineItems = new List<BillController.LineItemInput>{ local, interstate };

        Test.startTest();
        BillController.BillSummary summary = BillController.createBill(request);
        Test.stopTest();

        System.assertEquals(90, summary.cgst);
        System.assertEquals(90, summary.sgst);
        System.assertEquals(336, summary.igst);
        System.assertEquals(2716, summary.totalAmount);
    }

    @isTest
    static void createBill_noCustomer_throws() {
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 100;
        request.lineItems = new List<BillController.LineItemInput>{ line };

        Boolean threw = false;
        try {
            BillController.createBill(request);
        } catch (BillController.BillControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void createBill_noLineItems_throws() {
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = insertCustomer();
        request.lineItems = new List<BillController.LineItemInput>();

        Boolean threw = false;
        try {
            BillController.createBill(request);
        } catch (BillController.BillControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void searchParts_matchesByNameSkuOrBarcode() {
        insert new Part__c(Name = 'Brake Pad', SKU__c = 'BP-001', Barcode__c = '1234567890', Price__c = 500);
        insert new Part__c(Name = 'Oil Filter', SKU__c = 'OF-002', Barcode__c = '9999999999', Price__c = 150);

        Test.startTest();
        List<BillController.PartSearchResult> byName = BillController.searchParts('Brake');
        List<BillController.PartSearchResult> bySku = BillController.searchParts('OF-002');
        Test.stopTest();

        System.assertEquals(1, byName.size());
        System.assertEquals('Brake Pad', byName[0].name);
        System.assertEquals(1, bySku.size());
        System.assertEquals('Oil Filter', bySku[0].name);
    }

    @isTest
    static void searchCustomers_matchesByNameOrPhone() {
        insert new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert new Customer__c(Name = 'Suresh Rao', Phone__c = '9000022222');

        Test.startTest();
        List<BillController.CustomerSearchResult> results = BillController.searchCustomers('Ramesh');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Ramesh Kumar', results[0].name);
    }

    @isTest
    static void createCustomer_withNameAndPhone_createsRecord() {
        BillController.NewCustomerInput input = new BillController.NewCustomerInput();
        input.name = 'New Customer';
        input.phone = '9000055555';
        input.state = 'Madhya Pradesh';

        Test.startTest();
        BillController.CustomerSearchResult result = BillController.createCustomer(input);
        Test.stopTest();

        System.assertEquals('New Customer', result.name);
        System.assertEquals(1, [SELECT COUNT() FROM Customer__c WHERE Name = 'New Customer']);
    }

    @isTest
    static void createCustomer_missingPhone_throws() {
        BillController.NewCustomerInput input = new BillController.NewCustomerInput();
        input.name = 'No Phone Customer';

        Boolean threw = false;
        try {
            BillController.createCustomer(input);
        } catch (BillController.BillControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void createBill_withJobId_linksTheJob() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;
        Job_Status_Stage__c stage = new Job_Status_Stage__c(Name = 'Received', Sort_Order__c = 1);
        insert stage;
        Job__c job = new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stage.Id);
        insert job;

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        request.jobId = job.Id;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 500;
        request.lineItems = new List<BillController.LineItemInput>{ line };

        Test.startTest();
        BillController.BillSummary summary = BillController.createBill(request);
        Test.stopTest();

        System.assertEquals(job.Id, summary.jobId);
    }

    @isTest
    static void createNewVersion_withoutExplicitJobId_carriesForwardPreviousJob() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;
        Job_Status_Stage__c stage = new Job_Status_Stage__c(Name = 'Received', Sort_Order__c = 1);
        insert stage;
        Job__c job = new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stage.Id);
        insert job;

        BillController.CreateBillRequest firstRequest = new BillController.CreateBillRequest();
        firstRequest.customerId = customerId;
        firstRequest.jobId = job.Id;
        BillController.LineItemInput firstLine = new BillController.LineItemInput();
        firstLine.description = 'Service';
        firstLine.quantity = 1;
        firstLine.unitPrice = 500;
        firstRequest.lineItems = new List<BillController.LineItemInput>{ firstLine };
        BillController.BillSummary first = BillController.createBill(firstRequest);

        BillController.CreateBillRequest secondRequest = new BillController.CreateBillRequest();
        secondRequest.customerId = customerId;
        BillController.LineItemInput secondLine = new BillController.LineItemInput();
        secondLine.description = 'Service';
        secondLine.quantity = 1;
        secondLine.unitPrice = 600;
        secondRequest.lineItems = new List<BillController.LineItemInput>{ secondLine };

        Test.startTest();
        BillController.BillSummary second = BillController.createNewVersion(first.billId, secondRequest);
        Test.stopTest();

        System.assertEquals(job.Id, second.jobId);
    }

    @isTest
    static void getBillSummary_returnsLiveBreakdown() {
        Id customerId = insertCustomer();
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 1000;
        line.taxRatePercent = 18;
        request.lineItems = new List<BillController.LineItemInput>{ line };
        BillController.BillSummary created = BillController.createBill(request);

        Test.startTest();
        BillController.BillSummary fetched = BillController.getBillSummary(created.billId);
        Test.stopTest();

        System.assertEquals(created.invoiceNumber, fetched.invoiceNumber);
        System.assertEquals(90, fetched.cgst);
        System.assertEquals(90, fetched.sgst);
    }

    @isTest
    static void createBill_withSourceEstimate_marksEstimateConverted() {
        Id customerId = insertCustomer();
        Estimate__c estimate = new Estimate__c(Customer__c = customerId);
        insert estimate;

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        request.sourceEstimateId = estimate.Id;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 500;
        request.lineItems = new List<BillController.LineItemInput>{ line };

        Test.startTest();
        BillController.BillSummary summary = BillController.createBill(request);
        Test.stopTest();

        System.assertEquals(estimate.Id, summary.sourceEstimateId);
        Estimate__c updated = [SELECT Status__c FROM Estimate__c WHERE Id = :estimate.Id];
        System.assertEquals('Converted', updated.Status__c);
    }

    @isTest
    static void createNewVersion_reversesOldStockAndDeductsNewStockWithoutDoubleCounting() {
        Id customerId = insertCustomer();
        Part__c part = new Part__c(Name = 'Brake Pad', Price__c = 500, Tax_Rate_Percent__c = 18);
        insert part;

        BillController.CreateBillRequest firstRequest = new BillController.CreateBillRequest();
        firstRequest.customerId = customerId;
        BillController.LineItemInput firstLine = new BillController.LineItemInput();
        firstLine.partId = part.Id;
        firstLine.description = 'Brake Pad';
        firstLine.quantity = 2;
        firstLine.unitPrice = 500;
        firstLine.taxRatePercent = 18;
        firstRequest.lineItems = new List<BillController.LineItemInput>{ firstLine };
        BillController.BillSummary first = BillController.createBill(firstRequest);

        Part__c afterFirst = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(-2, afterFirst.Current_Stock__c);

        BillController.CreateBillRequest secondRequest = new BillController.CreateBillRequest();
        secondRequest.customerId = customerId;
        BillController.LineItemInput secondLine = new BillController.LineItemInput();
        secondLine.partId = part.Id;
        secondLine.description = 'Brake Pad';
        secondLine.quantity = 3;
        secondLine.unitPrice = 500;
        secondLine.taxRatePercent = 18;
        secondRequest.lineItems = new List<BillController.LineItemInput>{ secondLine };

        Test.startTest();
        BillController.BillSummary second = BillController.createNewVersion(first.billId, secondRequest);
        Test.stopTest();

        // Old version's -2 is reversed (+2), new version deducts -3: net -3, not -5.
        Part__c afterSecond = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(-3, afterSecond.Current_Stock__c);

        System.assertEquals(2, second.versionNumber);
        System.assertNotEquals(first.invoiceNumber, second.invoiceNumber);

        Bill__c previous = [SELECT Is_Latest_Version__c FROM Bill__c WHERE Id = :first.billId];
        System.assertEquals(false, previous.Is_Latest_Version__c);
    }

    @isTest
    static void createNewVersion_doesNotCarryForwardPreviousPayments() {
        Id customerId = insertCustomer();
        BillController.CreateBillRequest firstRequest = new BillController.CreateBillRequest();
        firstRequest.customerId = customerId;
        BillController.LineItemInput firstLine = new BillController.LineItemInput();
        firstLine.description = 'Service';
        firstLine.quantity = 1;
        firstLine.unitPrice = 1000;
        firstRequest.lineItems = new List<BillController.LineItemInput>{ firstLine };
        firstRequest.initialPaymentAmount = 1000;
        BillController.BillSummary first = BillController.createBill(firstRequest);
        System.assertEquals('Paid', first.status);

        BillController.CreateBillRequest secondRequest = new BillController.CreateBillRequest();
        secondRequest.customerId = customerId;
        BillController.LineItemInput secondLine = new BillController.LineItemInput();
        secondLine.description = 'Service';
        secondLine.quantity = 1;
        secondLine.unitPrice = 1200;
        secondRequest.lineItems = new List<BillController.LineItemInput>{ secondLine };

        Test.startTest();
        BillController.BillSummary second = BillController.createNewVersion(first.billId, secondRequest);
        Test.stopTest();

        System.assertEquals('Unpaid', second.status);
        System.assertEquals(1, [SELECT COUNT() FROM Payment__c WHERE Bill__c = :first.billId]);
        System.assertEquals(0, [SELECT COUNT() FROM Payment__c WHERE Bill__c = :second.billId]);
    }

    @isTest
    static void getBillVersions_returnsFullChainInOrder() {
        Id customerId = insertCustomer();
        BillController.CreateBillRequest firstRequest = new BillController.CreateBillRequest();
        firstRequest.customerId = customerId;
        BillController.LineItemInput firstLine = new BillController.LineItemInput();
        firstLine.description = 'Service';
        firstLine.quantity = 1;
        firstLine.unitPrice = 1000;
        firstRequest.lineItems = new List<BillController.LineItemInput>{ firstLine };
        BillController.BillSummary v1 = BillController.createBill(firstRequest);

        BillController.CreateBillRequest secondRequest = new BillController.CreateBillRequest();
        secondRequest.customerId = customerId;
        BillController.LineItemInput secondLine = new BillController.LineItemInput();
        secondLine.description = 'Service';
        secondLine.quantity = 1;
        secondLine.unitPrice = 1200;
        secondRequest.lineItems = new List<BillController.LineItemInput>{ secondLine };
        BillController.BillSummary v2 = BillController.createNewVersion(v1.billId, secondRequest);

        Test.startTest();
        List<BillController.BillSummary> versions = BillController.getBillVersions(v2.billId);
        Test.stopTest();

        System.assertEquals(2, versions.size());
        System.assertEquals(1, versions[0].versionNumber);
        System.assertEquals(2, versions[1].versionNumber);
    }

    @isTest
    static void listBills_duesOnlyFilter_excludesPaidAndOldVersions() {
        Id customerId = insertCustomer();

        BillController.CreateBillRequest unpaidRequest = new BillController.CreateBillRequest();
        unpaidRequest.customerId = customerId;
        BillController.LineItemInput unpaidLine = new BillController.LineItemInput();
        unpaidLine.description = 'Service';
        unpaidLine.quantity = 1;
        unpaidLine.unitPrice = 500;
        unpaidRequest.lineItems = new List<BillController.LineItemInput>{ unpaidLine };
        BillController.createBill(unpaidRequest);

        BillController.CreateBillRequest paidRequest = new BillController.CreateBillRequest();
        paidRequest.customerId = customerId;
        BillController.LineItemInput paidLine = new BillController.LineItemInput();
        paidLine.description = 'Oil Change';
        paidLine.quantity = 1;
        paidLine.unitPrice = 300;
        paidRequest.lineItems = new List<BillController.LineItemInput>{ paidLine };
        paidRequest.initialPaymentAmount = 300;
        BillController.createBill(paidRequest);

        Test.startTest();
        List<BillController.BillListItem> all = BillController.listBills('All', null);
        List<BillController.BillListItem> duesOnly = BillController.listBills('DuesOnly', null);
        Test.stopTest();

        System.assertEquals(2, all.size());
        System.assertEquals(1, duesOnly.size());
        System.assertEquals('Unpaid', duesOnly[0].status);
    }

    @isTest
    static void listBills_withSearchTerm_matchesByInvoiceNumberCustomerNameOrPhone() {
        Id ramesh = insertCustomer();
        BillController.CreateBillRequest rameshRequest = new BillController.CreateBillRequest();
        rameshRequest.customerId = ramesh;
        BillController.LineItemInput rameshLine = new BillController.LineItemInput();
        rameshLine.description = 'Service';
        rameshLine.quantity = 1;
        rameshLine.unitPrice = 500;
        rameshRequest.lineItems = new List<BillController.LineItemInput>{ rameshLine };
        BillController.BillSummary rameshBill = BillController.createBill(rameshRequest);

        Customer__c suresh = new Customer__c(Name = 'Suresh Rao', Phone__c = '9000022222');
        insert suresh;
        BillController.CreateBillRequest sureshRequest = new BillController.CreateBillRequest();
        sureshRequest.customerId = suresh.Id;
        BillController.LineItemInput sureshLine = new BillController.LineItemInput();
        sureshLine.description = 'Oil Change';
        sureshLine.quantity = 1;
        sureshLine.unitPrice = 300;
        sureshRequest.lineItems = new List<BillController.LineItemInput>{ sureshLine };
        BillController.createBill(sureshRequest);

        Test.startTest();
        List<BillController.BillListItem> byCustomerName = BillController.listBills('All', 'Ramesh');
        List<BillController.BillListItem> byPhone = BillController.listBills('All', '9000022222');
        List<BillController.BillListItem> byInvoiceNumber = BillController.listBills('All', rameshBill.invoiceNumber);
        Test.stopTest();

        System.assertEquals(1, byCustomerName.size());
        System.assertEquals('Ramesh Kumar', byCustomerName[0].customerName);

        System.assertEquals(1, byPhone.size());
        System.assertEquals('Suresh Rao', byPhone[0].customerName);

        System.assertEquals(1, byInvoiceNumber.size());
        System.assertEquals(rameshBill.invoiceNumber, byInvoiceNumber[0].invoiceNumber);
    }

    @isTest
    static void recordPayment_addsAPaymentAndRecomputesStatusWithoutTouchingLineItems() {
        Id customerId = insertCustomer();
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 1000;
        request.lineItems = new List<BillController.LineItemInput>{ line };
        BillController.BillSummary created = BillController.createBill(request);

        Test.startTest();
        BillController.BillSummary afterFirstPayment = BillController.recordPayment(created.billId, 400, 'UPI');
        BillController.BillSummary afterSecondPayment = BillController.recordPayment(created.billId, 600, 'Cash');
        Test.stopTest();

        System.assertEquals('Partial', afterFirstPayment.status);
        System.assertEquals(400, afterFirstPayment.amountPaid);
        System.assertEquals(600, afterFirstPayment.amountDue);
        System.assertEquals(1, afterFirstPayment.payments.size());

        System.assertEquals('Paid', afterSecondPayment.status);
        System.assertEquals(1000, afterSecondPayment.amountPaid);
        System.assertEquals(0, afterSecondPayment.amountDue);
        System.assertEquals(2, afterSecondPayment.payments.size());
        System.assertEquals(1, afterSecondPayment.lineItems.size(), 'Recording a payment must never touch line items.');
    }

    @isTest
    static void recordPayment_zeroOrNegativeAmount_throws() {
        Id customerId = insertCustomer();
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 1000;
        request.lineItems = new List<BillController.LineItemInput>{ line };
        BillController.BillSummary created = BillController.createBill(request);

        Boolean threw = false;
        try {
            BillController.recordPayment(created.billId, 0, 'Cash');
        } catch (BillController.BillControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void getBillSummary_includesBillToPartyNameWhenPresent() {
        Id customerId = insertCustomer();
        Bill_To_Party__c party = new Bill_To_Party__c(Name = 'Acme Logistics Pvt Ltd');
        insert party;

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        request.billToPartyId = party.Id;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 500;
        request.lineItems = new List<BillController.LineItemInput>{ line };
        BillController.BillSummary created = BillController.createBill(request);

        Test.startTest();
        BillController.BillSummary summary = BillController.getBillSummary(created.billId);
        Test.stopTest();

        System.assertEquals('Acme Logistics Pvt Ltd', summary.billToPartyName);
    }

    @isTest
    static void createBill_withExistingVehicle_linksItAndReturnsLabel() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(
            Name = 'MH12AB1234', Customer__c = customerId, Make__c = 'Honda', Model__c = 'City',
            Chassis_Number__c = 'MA3ERLF1S00123456'
        );
        insert vehicle;

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        request.vehicleId = vehicle.Id;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 500;
        request.lineItems = new List<BillController.LineItemInput>{ line };

        Test.startTest();
        BillController.BillSummary summary = BillController.createBill(request);
        Test.stopTest();

        System.assertEquals(vehicle.Id, summary.vehicleId);
        System.assertEquals('MH12AB1234 — Honda City', summary.vehicleLabel);
        System.assertEquals('MA3ERLF1S00123456', summary.vehicleChassisNumber);
    }

    @isTest
    static void createBill_withNewVehicle_createsItUnderTheCustomer() {
        Id customerId = insertCustomer();

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        CustomerController.NewVehicleInput newVehicle = new CustomerController.NewVehicleInput();
        newVehicle.registrationNumber = 'MH12CD5678';
        newVehicle.make = 'Maruti';
        newVehicle.model = 'Swift';
        newVehicle.chassisNumber = 'MA3ERLF1S00123456';
        request.newVehicle = newVehicle;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = 'Service';
        line.quantity = 1;
        line.unitPrice = 500;
        request.lineItems = new List<BillController.LineItemInput>{ line };

        Test.startTest();
        BillController.BillSummary summary = BillController.createBill(request);
        Test.stopTest();

        System.assertNotEquals(null, summary.vehicleId);
        Vehicle__c created = [SELECT Customer__c, Name, Chassis_Number__c FROM Vehicle__c WHERE Id = :summary.vehicleId];
        System.assertEquals(customerId, created.Customer__c, 'A vehicle created inline must be saved under the bill\'s customer.');
        System.assertEquals('MH12CD5678', created.Name);
        System.assertEquals('MA3ERLF1S00123456', created.Chassis_Number__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Vehicle_Make_Model__c WHERE Make__c = 'Maruti' AND Model__c = 'Swift'],
            'A new make/model typed on a bill\'s inline vehicle must be remembered for future autocomplete suggestions.'
        );
    }

    @isTest
    static void createNewVersion_withoutExplicitVehicle_carriesForwardPreviousVehicle() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MH12AB1234', Customer__c = customerId);
        insert vehicle;

        BillController.CreateBillRequest firstRequest = new BillController.CreateBillRequest();
        firstRequest.customerId = customerId;
        firstRequest.vehicleId = vehicle.Id;
        BillController.LineItemInput firstLine = new BillController.LineItemInput();
        firstLine.description = 'Service';
        firstLine.quantity = 1;
        firstLine.unitPrice = 500;
        firstRequest.lineItems = new List<BillController.LineItemInput>{ firstLine };
        BillController.BillSummary first = BillController.createBill(firstRequest);

        BillController.CreateBillRequest secondRequest = new BillController.CreateBillRequest();
        secondRequest.customerId = customerId;
        BillController.LineItemInput secondLine = new BillController.LineItemInput();
        secondLine.description = 'Service';
        secondLine.quantity = 1;
        secondLine.unitPrice = 600;
        secondRequest.lineItems = new List<BillController.LineItemInput>{ secondLine };

        Test.startTest();
        BillController.BillSummary second = BillController.createNewVersion(first.billId, secondRequest);
        Test.stopTest();

        System.assertEquals(vehicle.Id, second.vehicleId);
    }

    @isTest
    static void createBill_withManualLine_createsSearchablePartAndDeductsStock() {
        Id customerId = insertCustomer();

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        BillController.LineItemInput manualLine = new BillController.LineItemInput();
        manualLine.description = 'Headlight Bulb';
        manualLine.quantity = 2;
        manualLine.unitPrice = 250;
        manualLine.taxRatePercent = 18;
        manualLine.gstType = 'CGST_SGST';
        manualLine.hsnSacCode = '8539';
        manualLine.unitLabel = 'pcs';
        request.lineItems = new List<BillController.LineItemInput>{ manualLine };

        Test.startTest();
        BillController.createBill(request);
        Test.stopTest();

        List<Part__c> created = [SELECT Id, Price__c, Current_Stock__c FROM Part__c WHERE Name = 'Headlight Bulb'];
        System.assertEquals(1, created.size(), 'The manually typed line must create exactly one searchable Part__c.');
        System.assertEquals(250, created[0].Price__c);
        System.assertEquals(-2, created[0].Current_Stock__c, 'A manual line now goes through the same stock deduction as a real inventory line.');

        BillController.PartSearchResult[] found = BillController.searchParts('Headlight');
        System.assertEquals(1, found.size(), 'The new part must be searchable immediately, with no further setup needed.');
        System.assertEquals('Headlight Bulb', found[0].name);
    }

    @isTest
    static void createBill_withTwoManualLinesSharingAName_reusesTheSamePart() {
        Id customerId = insertCustomer();
        Part__c existing = new Part__c(Name = 'Wiper Blade', Price__c = 200, Tax_Rate_Percent__c = 18, Gst_Type__c = 'CGST_SGST');
        insert existing;

        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = customerId;
        BillController.LineItemInput manualLine = new BillController.LineItemInput();
        manualLine.description = 'Wiper Blade';
        manualLine.quantity = 1;
        manualLine.unitPrice = 200;
        request.lineItems = new List<BillController.LineItemInput>{ manualLine };

        Test.startTest();
        BillController.BillSummary summary = BillController.createBill(request);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Part__c WHERE Name = 'Wiper Blade'], 'Must reuse the existing part, never create a duplicate.');
        System.assertEquals(existing.Id, summary.lineItems[0].partId);
    }
}
