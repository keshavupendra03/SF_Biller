@isTest
private class VehicleControllerTest {

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        return customer.Id;
    }

    @isTest
    static void getVehicleDetail_returnsAllFieldsIncludingChassisNumberAndCustomer() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(
            Name = 'MP09AB1234',
            Customer__c = customerId,
            Make__c = 'Maruti Suzuki',
            Model__c = 'Swift',
            Year__c = 2022,
            Color__c = 'White',
            Chassis_Number__c = 'MA3ERLF1S00123456'
        );
        insert vehicle;

        Test.startTest();
        VehicleController.VehicleDetail detail = VehicleController.getVehicleDetail(vehicle.Id);
        Test.stopTest();

        System.assertEquals('MP09AB1234', detail.registrationNumber);
        System.assertEquals('Maruti Suzuki', detail.make);
        System.assertEquals('Swift', detail.model);
        System.assertEquals(2022, detail.year);
        System.assertEquals('White', detail.color);
        System.assertEquals('MA3ERLF1S00123456', detail.chassisNumber);
        System.assertEquals(customerId, detail.customerId);
        System.assertEquals('Ramesh Kumar', detail.customerName);
    }

    @isTest
    static void getVehicleDetail_noVehicleId_throws() {
        Boolean threw = false;
        try {
            VehicleController.getVehicleDetail(null);
        } catch (VehicleController.VehicleControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void updateVehicle_updatesEveryFieldIncludingChassisNumber() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;

        VehicleController.VehicleInput input = new VehicleController.VehicleInput();
        input.registrationNumber = 'MP09ZZ9999';
        input.make = 'Hyundai';
        input.model = 'i20';
        input.year = 2023;
        input.color = 'Red';
        input.chassisNumber = 'MALA851ALKM123456';

        Test.startTest();
        VehicleController.updateVehicle(vehicle.Id, input);
        Test.stopTest();

        Vehicle__c updated = [
            SELECT Name, Make__c, Model__c, Year__c, Color__c, Chassis_Number__c
            FROM Vehicle__c WHERE Id = :vehicle.Id
        ];
        System.assertEquals('MP09ZZ9999', updated.Name);
        System.assertEquals('Hyundai', updated.Make__c);
        System.assertEquals('i20', updated.Model__c);
        System.assertEquals(2023, updated.Year__c);
        System.assertEquals('Red', updated.Color__c);
        System.assertEquals('MALA851ALKM123456', updated.Chassis_Number__c);
    }

    @isTest
    static void updateVehicle_newMakeModel_isRememberedForAutocomplete() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;

        VehicleController.VehicleInput input = new VehicleController.VehicleInput();
        input.registrationNumber = 'MP09AB1234';
        input.make = 'Tata';
        input.model = 'Nexon';

        Test.startTest();
        VehicleController.updateVehicle(vehicle.Id, input);
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Vehicle_Make_Model__c WHERE Make__c = 'Tata' AND Model__c = 'Nexon']
        );
    }

    @isTest
    static void updateVehicle_missingRegistrationNumber_throws() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId);
        insert vehicle;

        VehicleController.VehicleInput input = new VehicleController.VehicleInput();

        Boolean threw = false;
        try {
            VehicleController.updateVehicle(vehicle.Id, input);
        } catch (VehicleController.VehicleControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }
}
