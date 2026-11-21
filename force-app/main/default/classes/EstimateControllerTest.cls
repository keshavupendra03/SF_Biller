@isTest
private class EstimateControllerTest {

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        return customer.Id;
    }

    private static BillController.LineItemInput makeLine(String description, Decimal qty, Decimal price, Decimal taxRate) {
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = description;
        line.quantity = qty;
        line.unitPrice = price;
        line.taxRatePercent = taxRate;
        return line;
    }

    @isTest
    static void createEstimate_createsRecordAndLineItemsWithAssignedNumber() {
        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = insertCustomer();
        request.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };

        Test.startTest();
        EstimateController.EstimateSummary summary = EstimateController.createEstimate(request);
        Test.stopTest();

        System.assert(summary.estimateNumber.startsWith('EST-'));
        System.assertEquals(1, summary.versionNumber);
        System.assertEquals(true, summary.isLatestVersion);
        System.assertEquals(590, summary.totalAmount);
        System.assertEquals(1, [SELECT COUNT() FROM Estimate_Line_Item__c WHERE Estimate__c = :summary.estimateId]);
    }

    @isTest
    static void createNewVersion_createsLinkedRecordAndMarksPreviousSuperseded() {
        EstimateController.CreateEstimateRequest firstRequest = new EstimateController.CreateEstimateRequest();
        firstRequest.customerId = insertCustomer();
        firstRequest.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };
        EstimateController.EstimateSummary first = EstimateController.createEstimate(firstRequest);

        EstimateController.CreateEstimateRequest secondRequest = new EstimateController.CreateEstimateRequest();
        secondRequest.customerId = first.customerId;
        secondRequest.lineItems = new List<BillController.LineItemInput>{
            makeLine('Diagnostic Fee', 1, 500, 18),
            makeLine('Extra part', 1, 200, 18)
        };

        Test.startTest();
        EstimateController.EstimateSummary second = EstimateController.createNewVersion(first.estimateId, secondRequest);
        Test.stopTest();

        System.assertEquals(2, second.versionNumber);
        System.assertNotEquals(first.estimateNumber, second.estimateNumber);

        Estimate__c previous = [SELECT Is_Latest_Version__c FROM Estimate__c WHERE Id = :first.estimateId];
        System.assertEquals(false, previous.Is_Latest_Version__c);

        Estimate__c latest = [SELECT Is_Latest_Version__c, Previous_Version__c, Root_Estimate__c FROM Estimate__c WHERE Id = :second.estimateId];
        System.assertEquals(true, latest.Is_Latest_Version__c);
        System.assertEquals(first.estimateId, latest.Previous_Version__c);
        System.assertEquals(first.estimateId, latest.Root_Estimate__c);
    }

    @isTest
    static void getEstimateVersions_returnsFullChainInOrder() {
        EstimateController.CreateEstimateRequest firstRequest = new EstimateController.CreateEstimateRequest();
        firstRequest.customerId = insertCustomer();
        firstRequest.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };
        EstimateController.EstimateSummary v1 = EstimateController.createEstimate(firstRequest);

        EstimateController.CreateEstimateRequest secondRequest = new EstimateController.CreateEstimateRequest();
        secondRequest.customerId = v1.customerId;
        secondRequest.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 600, 18) };
        EstimateController.EstimateSummary v2 = EstimateController.createNewVersion(v1.estimateId, secondRequest);

        Test.startTest();
        List<EstimateController.EstimateSummary> versions = EstimateController.getEstimateVersions(v2.estimateId);
        Test.stopTest();

        System.assertEquals(2, versions.size());
        System.assertEquals(1, versions[0].versionNumber);
        System.assertEquals(2, versions[1].versionNumber);
    }

    @isTest
    static void createEstimate_withNewBillToParty_createsAndLinksIt() {
        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = insertCustomer();
        request.lineItems = new List<BillController.LineItemInput>{ makeLine('Fleet service', 1, 2000, 18) };
        BillController.NewBillToPartyInput party = new BillController.NewBillToPartyInput();
        party.name = 'Acme Logistics Pvt Ltd';
        request.newBillToParty = party;

        Test.startTest();
        EstimateController.EstimateSummary summary = EstimateController.createEstimate(request);
        Test.stopTest();

        System.assertNotEquals(null, summary.billToPartyId);
    }

    @isTest
    static void createEstimate_noLineItems_throws() {
        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = insertCustomer();
        request.lineItems = new List<BillController.LineItemInput>();

        Boolean threw = false;
        try {
            EstimateController.createEstimate(request);
        } catch (EstimateController.EstimateControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void createEstimate_withJobId_linksTheJob() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;
        Job_Status_Stage__c stage = new Job_Status_Stage__c(Name = 'Received', Sort_Order__c = 1);
        insert stage;
        Job__c job = new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stage.Id);
        insert job;

        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = customerId;
        request.jobId = job.Id;
        request.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };

        Test.startTest();
        EstimateController.EstimateSummary summary = EstimateController.createEstimate(request);
        Test.stopTest();

        System.assertEquals(job.Id, summary.jobId);
    }

    @isTest
    static void getEstimateSummary_includesBillToPartyNameWhenPresent() {
        Bill_To_Party__c party = new Bill_To_Party__c(Name = 'Acme Logistics Pvt Ltd');
        insert party;

        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = insertCustomer();
        request.billToPartyId = party.Id;
        request.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };
        EstimateController.EstimateSummary created = EstimateController.createEstimate(request);

        Test.startTest();
        EstimateController.EstimateSummary summary = EstimateController.getEstimateSummary(created.estimateId);
        Test.stopTest();

        System.assertEquals('Acme Logistics Pvt Ltd', summary.billToPartyName);
    }

    @isTest
    static void createEstimate_withExistingVehicle_linksItAndReturnsLabel() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(
            Name = 'MH12AB1234', Customer__c = customerId, Make__c = 'Honda', Model__c = 'City',
            Chassis_Number__c = 'MA3ERLF1S00123456'
        );
        insert vehicle;

        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = customerId;
        request.vehicleId = vehicle.Id;
        request.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };

        Test.startTest();
        EstimateController.EstimateSummary summary = EstimateController.createEstimate(request);
        Test.stopTest();

        System.assertEquals(vehicle.Id, summary.vehicleId);
        System.assertEquals('MH12AB1234 — Honda City', summary.vehicleLabel);
        System.assertEquals('MA3ERLF1S00123456', summary.vehicleChassisNumber);
    }

    @isTest
    static void createEstimate_withNewVehicle_createsItUnderTheCustomer() {
        Id customerId = insertCustomer();

        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = customerId;
        CustomerController.NewVehicleInput newVehicle = new CustomerController.NewVehicleInput();
        newVehicle.registrationNumber = 'MH12CD5678';
        newVehicle.make = 'Maruti';
        newVehicle.model = 'Swift';
        newVehicle.chassisNumber = 'MA3ERLF1S00123456';
        request.newVehicle = newVehicle;
        request.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };

        Test.startTest();
        EstimateController.EstimateSummary summary = EstimateController.createEstimate(request);
        Test.stopTest();

        System.assertNotEquals(null, summary.vehicleId);
        Vehicle__c created = [SELECT Customer__c, Name, Chassis_Number__c FROM Vehicle__c WHERE Id = :summary.vehicleId];
        System.assertEquals(customerId, created.Customer__c, 'A vehicle created inline must be saved under the estimate\'s customer.');
        System.assertEquals('MA3ERLF1S00123456', created.Chassis_Number__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Vehicle_Make_Model__c WHERE Make__c = 'Maruti' AND Model__c = 'Swift'],
            'A new make/model typed on an estimate\'s inline vehicle must be remembered for future autocomplete suggestions.'
        );
    }

    @isTest
    static void createNewVersion_withoutExplicitVehicle_carriesForwardPreviousVehicle() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MH12AB1234', Customer__c = customerId);
        insert vehicle;

        EstimateController.CreateEstimateRequest firstRequest = new EstimateController.CreateEstimateRequest();
        firstRequest.customerId = customerId;
        firstRequest.vehicleId = vehicle.Id;
        firstRequest.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };
        EstimateController.EstimateSummary first = EstimateController.createEstimate(firstRequest);

        EstimateController.CreateEstimateRequest secondRequest = new EstimateController.CreateEstimateRequest();
        secondRequest.customerId = customerId;
        secondRequest.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 600, 18) };

        Test.startTest();
        EstimateController.EstimateSummary second = EstimateController.createNewVersion(first.estimateId, secondRequest);
        Test.stopTest();

        System.assertEquals(vehicle.Id, second.vehicleId);
    }

    @isTest
    static void createEstimate_withManualLine_createsSearchablePartButDoesNotTouchStock() {
        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = insertCustomer();
        request.lineItems = new List<BillController.LineItemInput>{ makeLine('Headlight Bulb', 2, 250, 18) };

        Test.startTest();
        EstimateController.createEstimate(request);
        Test.stopTest();

        List<Part__c> created = [SELECT Id, Price__c, Current_Stock__c FROM Part__c WHERE Name = 'Headlight Bulb'];
        System.assertEquals(1, created.size(), 'The manually typed line must create exactly one searchable Part__c, same as on a bill.');
        System.assertEquals(250, created[0].Price__c);
        System.assertEquals(0, created[0].Current_Stock__c, 'Estimates never touch inventory — only a real bill deducts stock.');

        BillController.PartSearchResult[] found = BillController.searchParts('Headlight');
        System.assertEquals(1, found.size());
    }

    @isTest
    static void listEstimates_showsLatestVersionsOnly_withTheParty_andSearchesByParty() {
        Bill_To_Party__c icici = new Bill_To_Party__c(Name = 'ICICI Lombard');
        insert icici;
        EstimateController.CreateEstimateRequest firstRequest = new EstimateController.CreateEstimateRequest();
        firstRequest.customerId = insertCustomer();
        firstRequest.billToPartyId = icici.Id;
        firstRequest.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };
        EstimateController.EstimateSummary first = EstimateController.createEstimate(firstRequest);
        EstimateController.EstimateSummary second = EstimateController.createNewVersion(first.estimateId, firstRequest);

        Test.startTest();
        List<EstimateController.EstimateListItem> all = EstimateController.listEstimates(null, null);
        List<EstimateController.EstimateListItem> byParty = EstimateController.listEstimates('icici', null);
        List<EstimateController.EstimateListItem> none = EstimateController.listEstimates('nobody', null);
        Test.stopTest();

        System.assertEquals(1, all.size(), 'Only the latest version is listed.');
        System.assertEquals(second.estimateId, all[0].id);
        System.assertEquals(second.estimateNumber, all[0].estimateNumber);
        System.assertEquals('Ramesh Kumar', all[0].customerName);
        System.assertEquals('ICICI Lombard', all[0].billToPartyName);
        System.assertEquals(590, all[0].totalAmount);
        System.assertEquals(1, byParty.size());
        System.assertEquals(0, none.size());
    }

    @isTest
    static void listEstimates_filtersToOneCompany() {
        Workshop_Profile__c main = new Workshop_Profile__c(Name = 'Speedy Motors');
        insert main;
        Workshop_Profile__c decor = new Workshop_Profile__c(Name = 'Speedy Decor', Invoice_Prefix__c = 'SD');
        insert decor;
        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = insertCustomer();
        request.workshopProfileId = decor.Id;
        request.lineItems = new List<BillController.LineItemInput>{ makeLine('Seat Covers', 1, 4000, 18) };
        EstimateController.createEstimate(request);

        Test.startTest();
        Integer forDecor = EstimateController.listEstimates(null, decor.Id).size();
        Integer forMain = EstimateController.listEstimates(null, main.Id).size();
        Test.stopTest();

        System.assertEquals(1, forDecor);
        System.assertEquals(0, forMain);
    }

    @isTest
    static void deleteEstimate_removesEveryVersionAndLine_andABillFromItKeepsGoing() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
        EstimateController.CreateEstimateRequest request = new EstimateController.CreateEstimateRequest();
        request.customerId = insertCustomer();
        request.lineItems = new List<BillController.LineItemInput>{ makeLine('Diagnostic Fee', 1, 500, 18) };
        EstimateController.EstimateSummary first = EstimateController.createEstimate(request);
        EstimateController.EstimateSummary second = EstimateController.createNewVersion(first.estimateId, request);
        BillController.CreateBillRequest bill = new BillController.CreateBillRequest();
        bill.customerId = request.customerId;
        bill.sourceEstimateId = second.estimateId;
        bill.lineItems = request.lineItems;
        BillController.BillSummary converted = BillController.createBill(bill);

        Test.startTest();
        EstimateController.deleteEstimate(second.estimateId);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Estimate__c], 'Every version goes.');
        System.assertEquals(0, [SELECT COUNT() FROM Estimate_Line_Item__c]);
        Bill__c kept = [SELECT Source_Estimate__c, Total_Amount__c FROM Bill__c WHERE Id = :converted.billId];
        System.assertEquals(null, kept.Source_Estimate__c);
        System.assertEquals(590, kept.Total_Amount__c);
    }
}
