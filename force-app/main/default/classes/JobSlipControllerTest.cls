@isTest
private class JobSlipControllerTest {

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Deepak Sharma', Phone__c = '9425012345', Address__c = 'Vijay Nagar, Indore');
        insert customer;
        return customer.Id;
    }

    private static Vehicle__c insertVehicle(Id customerId, String registrationNumber) {
        Vehicle__c vehicle = new Vehicle__c(
            Name = registrationNumber, Customer__c = customerId, Make__c = 'Tata', Model__c = 'Punch',
            Chassis_Number__c = 'MAT867015SPJB9663', Engine_Number__c = 'ENG123', Date_Of_Sale__c = Date.newInstance(2025, 10, 22)
        );
        insert vehicle;
        return vehicle;
    }

    private static JobSlipController.JobSlipLine line(String request, String observation, Decimal labour, Decimal spares) {
        JobSlipController.JobSlipLine l = new JobSlipController.JobSlipLine();
        l.customerRequest = request;
        l.observation = observation;
        l.labourEstimate = labour;
        l.sparesEstimate = spares;
        return l;
    }

    private static JobSlipController.JobSlipData filledInput(Id customerId, Id vehicleId) {
        JobSlipController.JobSlipData input = new JobSlipController.JobSlipData();
        input.customerId = customerId;
        input.vehicleId = vehicleId;
        input.slipDate = Date.newInstance(2026, 10, 30);
        input.timeIn = '10:16:00.000';
        input.currentKm = 17773;
        input.visitReason = 'Accident';
        input.fuelLevel = '1/2';
        input.accessories = new List<String>{ 'spareWheel', 'jackAndHandle', 'mats' };
        input.batteryMake = 'Amaron';
        input.batteryNumber = 'AM12345';
        input.tyreMake = 'CEAT';
        input.serviceAdvisorName = 'Rahul';
        input.promisedDelivery = '30-35 days';
        input.chassisNumber = 'MAT867015SPJB9663';
        input.engineNumber = 'ENG999';
        input.dateOfSale = Date.newInstance(2025, 10, 22);
        input.lines = new List<JobSlipController.JobSlipLine>{
            line('Front bumper damaged', 'Bumper replacement', 1500, 6500),
            line('', '', null, null),
            line('Headlamp broken', 'Insurance - IFFCO TOKIO', null, null)
        };
        return input;
    }

    @isTest
    static void getJobSlipForm_newSlip_prefillsTodayAdvisorAndNewestVehicle() {
        Id customerId = insertCustomer();
        Vehicle__c older = insertVehicle(customerId, 'MP09AA1111');
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-30));
        Vehicle__c newest = insertVehicle(customerId, 'MP70ZD3946');

        Test.startTest();
        JobSlipController.JobSlipForm form = JobSlipController.getJobSlipForm(null, customerId, null);
        Test.stopTest();

        System.assertEquals(null, form.slip.id);
        System.assertEquals(Date.today(), form.slip.slipDate);
        System.assertNotEquals(null, form.slip.timeIn);
        System.assertEquals(UserInfo.getName(), form.slip.serviceAdvisorName);
        System.assertEquals('Deepak Sharma', form.customer.name);
        System.assertEquals(2, form.vehicles.size());
        System.assertEquals(newest.Id, form.slip.vehicleId, 'With no vehicle passed in, the newest vehicle is preselected.');
        System.assertEquals('ENG123', form.slip.engineNumber);
    }

    @isTest
    static void getJobSlipForm_newSlipForVehicle_carriesBatteryAndTyreFromItsLastSlip() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = insertVehicle(customerId, 'MP70ZD3946');
        insertVehicle(customerId, 'MP09AA1111');
        insert new Job_Slip__c(
            Customer__c = customerId, Vehicle__c = vehicle.Id, Slip_Date__c = Date.today().addDays(-90),
            Battery_Make__c = 'Amaron', Battery_Number__c = 'AM12345', Tyre_Make__c = 'CEAT'
        );

        Test.startTest();
        JobSlipController.JobSlipForm form = JobSlipController.getJobSlipForm(null, customerId, vehicle.Id);
        Test.stopTest();

        System.assertEquals(vehicle.Id, form.slip.vehicleId);
        System.assertEquals('Amaron', form.slip.batteryMake);
        System.assertEquals('AM12345', form.slip.batteryNumber);
        System.assertEquals('CEAT', form.slip.tyreMake);
    }

    @isTest
    static void saveJobSlip_newSlip_savesFieldsLinesAndWritesVehicleFactsBack() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = insertVehicle(customerId, 'MP70ZD3946');

        Test.startTest();
        Id slipId = JobSlipController.saveJobSlip(filledInput(customerId, vehicle.Id));
        Test.stopTest();

        Job_Slip__c saved = [
            SELECT Name, Customer__c, Vehicle__c, Time_In__c, Current_Km__c, Fuel_Level__c,
                   Spare_Wheel__c, Jack_And_Handle__c, Mats__c, Tool_Kit__c, Battery_Make__c
            FROM Job_Slip__c WHERE Id = :slipId
        ];
        System.assert(saved.Name.startsWith('JS-'));
        System.assertEquals(customerId, saved.Customer__c);
        System.assertEquals(Time.newInstance(10, 16, 0, 0), saved.Time_In__c);
        System.assertEquals(17773, saved.Current_Km__c);
        System.assertEquals('1/2', saved.Fuel_Level__c);
        System.assertEquals(true, saved.Spare_Wheel__c);
        System.assertEquals(true, saved.Mats__c);
        System.assertEquals(false, saved.Tool_Kit__c);

        List<Job_Slip_Line__c> lines = [
            SELECT Customer_Request__c, Labour_Estimate__c, Sort_Order__c FROM Job_Slip_Line__c
            WHERE Job_Slip__c = :slipId ORDER BY Sort_Order__c
        ];
        System.assertEquals(2, lines.size(), 'A completely blank row must not be saved.');
        System.assertEquals('Front bumper damaged', lines[0].Customer_Request__c);
        System.assertEquals(2, lines[1].Sort_Order__c);

        Vehicle__c updatedVehicle = [SELECT Engine_Number__c FROM Vehicle__c WHERE Id = :vehicle.Id];
        System.assertEquals('ENG999', updatedVehicle.Engine_Number__c);
    }

    @isTest
    static void saveJobSlip_existingSlip_updatesInPlaceAndDeletesRemovedLines() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = insertVehicle(customerId, 'MP70ZD3946');
        Id slipId = JobSlipController.saveJobSlip(filledInput(customerId, vehicle.Id));

        JobSlipController.JobSlipData loaded = JobSlipController.getJobSlipForm(slipId, null, null).slip;
        System.assertEquals('10:16', loaded.timeIn);
        System.assertEquals(3, loaded.accessories.size());
        System.assertEquals(2, loaded.lines.size());

        loaded.lines.remove(1);
        loaded.lines[0].observation = 'Bumper + grille replacement';
        loaded.accessories = new List<String>{ 'toolKit' };
        loaded.fuelLevel = 'F';

        Test.startTest();
        Id savedId = JobSlipController.saveJobSlip(loaded);
        Test.stopTest();

        System.assertEquals(slipId, savedId);
        System.assertEquals(1, [SELECT COUNT() FROM Job_Slip__c]);
        List<Job_Slip_Line__c> lines = [SELECT Id, Observation__c FROM Job_Slip_Line__c WHERE Job_Slip__c = :slipId];
        System.assertEquals(1, lines.size());
        System.assertEquals(loaded.lines[0].id, lines[0].Id, 'The kept line must be updated in place, not recreated.');
        System.assertEquals('Bumper + grille replacement', lines[0].Observation__c);
        Job_Slip__c saved = [SELECT Fuel_Level__c, Tool_Kit__c, Mats__c FROM Job_Slip__c WHERE Id = :slipId];
        System.assertEquals('F', saved.Fuel_Level__c);
        System.assertEquals(true, saved.Tool_Kit__c);
        System.assertEquals(false, saved.Mats__c);
    }

    @isTest
    static void saveJobSlip_newVehicle_createsItUnderTheCustomer() {
        Id customerId = insertCustomer();
        JobSlipController.JobSlipData input = filledInput(customerId, null);
        input.newVehicle = new CustomerController.NewVehicleInput();
        input.newVehicle.registrationNumber = 'MP09ZZ0001';
        input.newVehicle.make = 'Tata';
        input.newVehicle.model = 'Nexon';

        Test.startTest();
        Id slipId = JobSlipController.saveJobSlip(input);
        Test.stopTest();

        Job_Slip__c saved = [SELECT Vehicle__r.Name, Vehicle__r.Customer__c, Vehicle__r.Chassis_Number__c FROM Job_Slip__c WHERE Id = :slipId];
        System.assertEquals('MP09ZZ0001', saved.Vehicle__r.Name);
        System.assertEquals(customerId, saved.Vehicle__r.Customer__c);
        System.assertEquals('MAT867015SPJB9663', saved.Vehicle__r.Chassis_Number__c);
    }

    @isTest
    static void saveJobSlip_noVehicle_throws() {
        JobSlipController.JobSlipData input = filledInput(insertCustomer(), null);
        Boolean threw = false;
        try {
            JobSlipController.saveJobSlip(input);
        } catch (JobSlipController.JobSlipControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void saveJobSlip_vehicleOfAnotherCustomer_throws() {
        Id customerId = insertCustomer();
        Customer__c other = new Customer__c(Name = 'Someone Else', Phone__c = '9000000000');
        insert other;
        Vehicle__c othersVehicle = insertVehicle(other.Id, 'MP09XX0000');

        Boolean threw = false;
        try {
            JobSlipController.saveJobSlip(filledInput(customerId, othersVehicle.Id));
        } catch (JobSlipController.JobSlipControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void getJobSlipForm_noCustomerOrSlip_throws() {
        Boolean threw = false;
        try {
            JobSlipController.getJobSlipForm(null, null, null);
        } catch (JobSlipController.JobSlipControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void parseTime_acceptsPickerFormatAndRejectsGarbage() {
        System.assertEquals(Time.newInstance(9, 5, 0, 0), JobSlipController.parseTime('09:05'));
        System.assertEquals(Time.newInstance(18, 30, 0, 0), JobSlipController.parseTime('18:30:00.000'));
        System.assertEquals(null, JobSlipController.parseTime(''));
        Boolean threw = false;
        try {
            JobSlipController.parseTime('half past ten');
        } catch (JobSlipController.JobSlipControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }
}
