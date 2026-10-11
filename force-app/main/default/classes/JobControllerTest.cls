@isTest
private class JobControllerTest {

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        return customer.Id;
    }

    private static List<Id> insertStages() {
        List<Job_Status_Stage__c> stages = new List<Job_Status_Stage__c>{
            new Job_Status_Stage__c(Name = 'Received', Sort_Order__c = 1),
            new Job_Status_Stage__c(Name = 'In Progress', Sort_Order__c = 2),
            new Job_Status_Stage__c(Name = 'Ready For Pickup', Sort_Order__c = 3)
        };
        insert stages;
        return new List<Id>{ stages[0].Id, stages[1].Id, stages[2].Id };
    }

    @isTest
    static void getBoardData_returnsActiveStagesInOrderAndJobsWithMechanics() {
        List<Id> stageIds = insertStages();
        insert new Job_Status_Stage__c(Name = 'Retired Stage', Sort_Order__c = 99, Is_Active__c = false);

        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId, Make__c = 'Maruti', Model__c = 'Swift');
        insert vehicle;
        Mechanic__c mechanic = new Mechanic__c(Name = 'Suresh');
        insert mechanic;

        Job__c job = new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stageIds[0]);
        insert job;
        insert new Job_Mechanic__c(Job__c = job.Id, Mechanic__c = mechanic.Id);

        Test.startTest();
        JobController.BoardData data = JobController.getBoardData(null);
        Test.stopTest();

        System.assertEquals(3, data.stages.size(), 'Inactive stage must be excluded.');
        System.assertEquals('Received', data.stages[0].name);
        System.assertEquals('In Progress', data.stages[1].name);

        System.assertEquals(1, data.jobs.size());
        JobController.JobCard card = data.jobs[0];
        System.assertEquals('Ramesh Kumar', card.customerName);
        System.assertEquals('MP09AB1234 — Maruti Swift', card.vehicleLabel);
        System.assertEquals('Suresh', card.mechanicNames);
        System.assertEquals(1, card.mechanicIds.size());
    }

    @isTest
    static void getBoardData_withSearchTerm_matchesByCustomerPhoneOrVehicleAndExcludesOthers() {
        List<Id> stageIds = insertStages();

        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;
        insert new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stageIds[0]);

        Id otherCustomerId;
        Customer__c otherCustomer = new Customer__c(Name = 'Suresh Rao', Phone__c = '9000022222');
        insert otherCustomer;
        otherCustomerId = otherCustomer.Id;
        Vehicle__c otherVehicle = new Vehicle__c(Name = 'MH14ZZ9999', Customer__c = otherCustomerId);
        insert otherVehicle;
        insert new Job__c(Customer__c = otherCustomerId, Vehicle__c = otherVehicle.Id, Job_Status_Stage__c = stageIds[0]);

        Test.startTest();
        JobController.BoardData byCustomerName = JobController.getBoardData('Ramesh');
        JobController.BoardData byPhone = JobController.getBoardData('9000022222');
        JobController.BoardData byVehicle = JobController.getBoardData('MP09AB1234');
        Test.stopTest();

        System.assertEquals(1, byCustomerName.jobs.size());
        System.assertEquals('Ramesh Kumar', byCustomerName.jobs[0].customerName);

        System.assertEquals(1, byPhone.jobs.size());
        System.assertEquals('Suresh Rao', byPhone.jobs[0].customerName);

        System.assertEquals(1, byVehicle.jobs.size());
        System.assertEquals('Ramesh Kumar', byVehicle.jobs[0].customerName);
    }

    @isTest
    static void createJob_withExistingVehicle_createsJobInFirstActiveStage() {
        List<Id> stageIds = insertStages();
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;

        JobController.CreateJobRequest request = new JobController.CreateJobRequest();
        request.customerId = customerId;
        request.vehicleId = vehicle.Id;

        Test.startTest();
        JobController.JobCard card = JobController.createJob(request);
        Test.stopTest();

        System.assertEquals(stageIds[0], card.stageId, 'A job with no explicit stage should land in the first active stage.');
        System.assert(card.jobNumber.startsWith('JOB-'));
    }

    @isTest
    static void createJob_withNewVehicle_createsVehicleThenJob() {
        insertStages();
        Id customerId = insertCustomer();

        JobController.CreateJobRequest request = new JobController.CreateJobRequest();
        request.customerId = customerId;
        JobController.NewVehicleInput newVehicle = new JobController.NewVehicleInput();
        newVehicle.registrationNumber = 'MP09ZZ9999';
        newVehicle.make = 'Hyundai';
        newVehicle.model = 'i20';
        request.newVehicle = newVehicle;

        Test.startTest();
        JobController.JobCard card = JobController.createJob(request);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Vehicle__c WHERE Name = 'MP09ZZ9999']);
        System.assertEquals('MP09ZZ9999 — Hyundai i20', card.vehicleLabel);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Vehicle_Make_Model__c WHERE Make__c = 'Hyundai' AND Model__c = 'i20'],
            'A new make/model typed on a job\'s inline vehicle must be remembered for future autocomplete suggestions.'
        );
    }

    @isTest
    static void createJob_withMechanics_linksThemImmediately() {
        insertStages();
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;
        Mechanic__c m1 = new Mechanic__c(Name = 'Suresh');
        Mechanic__c m2 = new Mechanic__c(Name = 'Ramesh');
        insert new List<Mechanic__c>{ m1, m2 };

        JobController.CreateJobRequest request = new JobController.CreateJobRequest();
        request.customerId = customerId;
        request.vehicleId = vehicle.Id;
        request.mechanicIds = new List<Id>{ m1.Id, m2.Id };

        Test.startTest();
        JobController.JobCard card = JobController.createJob(request);
        Test.stopTest();

        System.assertEquals(2, card.mechanicIds.size());
        System.assertEquals(2, [SELECT COUNT() FROM Job_Mechanic__c WHERE Job__c = :card.id]);
    }

    @isTest
    static void createJob_noVehicleProvided_throws() {
        insertStages();
        JobController.CreateJobRequest request = new JobController.CreateJobRequest();
        request.customerId = insertCustomer();

        Boolean threw = false;
        try {
            JobController.createJob(request);
        } catch (JobController.JobControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void moveJob_updatesStage() {
        List<Id> stageIds = insertStages();
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;
        Job__c job = new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stageIds[0]);
        insert job;

        Test.startTest();
        JobController.moveJob(job.Id, stageIds[1]);
        Test.stopTest();

        Job__c updated = [SELECT Job_Status_Stage__c FROM Job__c WHERE Id = :job.Id];
        System.assertEquals(stageIds[1], updated.Job_Status_Stage__c);
    }

    @isTest
    static void assignMechanics_addsAndRemovesToMatchTheGivenList() {
        List<Id> stageIds = insertStages();
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;
        Job__c job = new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stageIds[0]);
        insert job;

        Mechanic__c m1 = new Mechanic__c(Name = 'Suresh');
        Mechanic__c m2 = new Mechanic__c(Name = 'Ramesh');
        Mechanic__c m3 = new Mechanic__c(Name = 'Deepak');
        insert new List<Mechanic__c>{ m1, m2, m3 };

        JobController.assignMechanics(job.Id, new List<Id>{ m1.Id, m2.Id });
        System.assertEquals(2, [SELECT COUNT() FROM Job_Mechanic__c WHERE Job__c = :job.Id]);

        Test.startTest();
        JobController.assignMechanics(job.Id, new List<Id>{ m2.Id, m3.Id });
        Test.stopTest();

        List<Job_Mechanic__c> remaining = [SELECT Mechanic__c FROM Job_Mechanic__c WHERE Job__c = :job.Id];
        Set<Id> remainingMechanicIds = new Set<Id>();
        for (Job_Mechanic__c jm : remaining) {
            remainingMechanicIds.add(jm.Mechanic__c);
        }
        System.assertEquals(2, remaining.size());
        System.assert(remainingMechanicIds.contains(m2.Id));
        System.assert(remainingMechanicIds.contains(m3.Id));
        System.assert(!remainingMechanicIds.contains(m1.Id), 'm1 should have been unassigned.');
    }

    @isTest
    static void searchVehicles_filtersByCustomerAndRegistrationNumber() {
        Id customerId = insertCustomer();
        Id otherCustomerId = insertCustomer();
        insert new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert new Vehicle__c(Name = 'MP09ZZ9999', Customer__c = customerId);
        insert new Vehicle__c(Name = 'MP09AB1234', Customer__c = otherCustomerId);

        Test.startTest();
        List<JobController.VehicleOption> results = JobController.searchVehicles(customerId, 'AB');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('MP09AB1234', results[0].registrationNumber);
    }

    @isTest
    static void getActiveMechanicsAndSurveyors_excludeInactive() {
        insert new Mechanic__c(Name = 'Active Mechanic', Is_Active__c = true);
        insert new Mechanic__c(Name = 'Inactive Mechanic', Is_Active__c = false);
        insert new Surveyor__c(Name = 'Active Surveyor', Is_Active__c = true);
        insert new Surveyor__c(Name = 'Inactive Surveyor', Is_Active__c = false);

        Test.startTest();
        List<JobController.PersonOption> mechanics = JobController.getActiveMechanics();
        List<JobController.PersonOption> surveyors = JobController.getActiveSurveyors();
        Test.stopTest();

        System.assertEquals(1, mechanics.size());
        System.assertEquals('Active Mechanic', mechanics[0].name);
        System.assertEquals(1, surveyors.size());
        System.assertEquals('Active Surveyor', surveyors[0].name);
    }

    @isTest
    static void getJobDetail_returnsCustomerVehicleSurveyorAndMechanicDetails() {
        List<Id> stageIds = insertStages();
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId, Make__c = 'Maruti', Model__c = 'Swift', Year__c = 2022, Color__c = 'White');
        insert vehicle;
        Surveyor__c surveyor = new Surveyor__c(Name = 'Bhaiyo Jio', Is_Active__c = true);
        insert surveyor;
        Mechanic__c mechanic = new Mechanic__c(Name = 'Suresh', Is_Active__c = true);
        insert mechanic;

        Job__c job = new Job__c(
            Customer__c = customerId,
            Vehicle__c = vehicle.Id,
            Surveyor__c = surveyor.Id,
            Job_Status_Stage__c = stageIds[0],
            Notes__c = 'Front bumper repair'
        );
        insert job;
        insert new Job_Mechanic__c(Job__c = job.Id, Mechanic__c = mechanic.Id);

        Test.startTest();
        JobController.JobDetail detail = JobController.getJobDetail(job.Id);
        Test.stopTest();

        System.assertEquals(job.Id, detail.id);
        System.assert(detail.jobNumber.startsWith('JOB-'));
        System.assertNotEquals(null, detail.createdDate);
        System.assertEquals('Received', detail.stageName);
        System.assertEquals('Ramesh Kumar', detail.customerName);
        System.assertEquals('9000011111', detail.customerPhone);
        System.assertEquals('MP09AB1234', detail.vehicleRegistrationNumber);
        System.assertEquals('Maruti Swift', detail.vehicleMakeModel);
        System.assertEquals(2022, detail.vehicleYear);
        System.assertEquals('White', detail.vehicleColor);
        System.assertEquals('Bhaiyo Jio', detail.surveyorName);
        System.assertEquals('Suresh', detail.mechanicNames);
        System.assertEquals('Front bumper repair', detail.notes);
        System.assertEquals(0, detail.bills.size());
        System.assertEquals(0, detail.estimates.size());
    }

    @isTest
    static void getJobDetail_includesBillsAndEstimatesLinkedToTheJob() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
        List<Id> stageIds = insertStages();
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;
        Job__c job = new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stageIds[0]);
        insert job;

        BillController.CreateBillRequest billRequest = new BillController.CreateBillRequest();
        billRequest.customerId = customerId;
        billRequest.jobId = job.Id;
        BillController.LineItemInput billLine = new BillController.LineItemInput();
        billLine.description = 'Service';
        billLine.quantity = 1;
        billLine.unitPrice = 500;
        billRequest.lineItems = new List<BillController.LineItemInput>{ billLine };
        BillController.BillSummary bill = BillController.createBill(billRequest);

        EstimateController.CreateEstimateRequest estimateRequest = new EstimateController.CreateEstimateRequest();
        estimateRequest.customerId = customerId;
        estimateRequest.jobId = job.Id;
        BillController.LineItemInput estimateLine = new BillController.LineItemInput();
        estimateLine.description = 'Diagnostic Fee';
        estimateLine.quantity = 1;
        estimateLine.unitPrice = 300;
        estimateRequest.lineItems = new List<BillController.LineItemInput>{ estimateLine };
        EstimateController.EstimateSummary estimate = EstimateController.createEstimate(estimateRequest);

        Test.startTest();
        JobController.JobDetail detail = JobController.getJobDetail(job.Id);
        Test.stopTest();

        System.assertEquals(1, detail.bills.size());
        System.assertEquals(bill.invoiceNumber, detail.bills[0].documentNumber);
        System.assertEquals(1, detail.estimates.size());
        System.assertEquals(estimate.estimateNumber, detail.estimates[0].documentNumber);
    }

    @isTest
    static void getJobDetail_noSurveyorOrMechanics_leavesThoseFieldsBlank() {
        List<Id> stageIds = insertStages();
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;
        Job__c job = new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stageIds[0]);
        insert job;

        Test.startTest();
        JobController.JobDetail detail = JobController.getJobDetail(job.Id);
        Test.stopTest();

        System.assertEquals('MP09AB1234', detail.vehicleRegistrationNumber, 'Vehicle is required on a Job, so it must always be present.');
        System.assertEquals(null, detail.surveyorName);
        System.assertEquals(null, detail.mechanicNames);
    }

    @isTest
    static void getJobDetail_noJobId_throws() {
        Boolean threw = false;
        try {
            JobController.getJobDetail(null);
        } catch (JobController.JobControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }
}
