@isTest
private class UpperCaseTextTest {

    @testSetup
    static void setup() {
        insert new Customer__c(Name = 'Ramesh', Phone__c = '9000011111');
    }

    @isTest
    static void aVehicle_isStoredInCapitals_onInsertAndUpdate() {
        Id customerId = [SELECT Id FROM Customer__c LIMIT 1].Id;
        Vehicle__c car = new Vehicle__c(Name = ' mp09ab1234 ', Customer__c = customerId, Chassis_Number__c = 'ma3abc123', Engine_Number__c = 'k12mn45');

        Test.startTest();
        insert car;
        car = [SELECT Name, Chassis_Number__c, Engine_Number__c FROM Vehicle__c WHERE Id = :car.Id];
        System.assertEquals('MP09AB1234', car.Name);
        System.assertEquals('MA3ABC123', car.Chassis_Number__c);
        System.assertEquals('K12MN45', car.Engine_Number__c);

        update new Vehicle__c(Id = car.Id, Name = 'mp 09 cd 5678', Chassis_Number__c = null);
        Test.stopTest();

        car = [SELECT Name, Chassis_Number__c FROM Vehicle__c WHERE Id = :car.Id];
        System.assertEquals('MP 09 CD 5678', car.Name, 'Spaces inside stay as typed.');
        System.assertEquals(null, car.Chassis_Number__c);
    }

    @isTest
    static void aJobSlipsBatteryNumber_andTheCompanysIfsc_toCapitals() {
        Id customerId = [SELECT Id FROM Customer__c LIMIT 1].Id;

        Test.startTest();
        Job_Slip__c slip = new Job_Slip__c(Customer__c = customerId, Battery_Number__c = 'ex1234b');
        insert slip;
        Workshop_Profile__c company = new Workshop_Profile__c(Name = 'Speedy Motors', Bank_IFSC__c = 'sbin0001234');
        insert company;
        Test.stopTest();

        System.assertEquals('EX1234B', [SELECT Battery_Number__c FROM Job_Slip__c WHERE Id = :slip.Id].Battery_Number__c);
        System.assertEquals('SBIN0001234', [SELECT Bank_IFSC__c FROM Workshop_Profile__c WHERE Id = :company.Id].Bank_IFSC__c);
    }

    @isTest
    static void aGstinIsStoredInCapitals_too() {
        Test.startTest();
        Customer__c buyer = new Customer__c(Name = 'Sharma Traders', Phone__c = '9000022222', GSTIN__c = '27aapfu0939f1zv');
        insert buyer;
        Test.stopTest();

        System.assertEquals('27AAPFU0939F1ZV', [SELECT GSTIN__c FROM Customer__c WHERE Id = :buyer.Id].GSTIN__c);
    }
}
