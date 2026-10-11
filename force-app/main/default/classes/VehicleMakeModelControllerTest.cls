@isTest
private class VehicleMakeModelControllerTest {

    @testSetup
    static void setup() {
        insert new List<Vehicle_Make_Model__c>{
            new Vehicle_Make_Model__c(Name = 'Maruti Suzuki Swift', Make__c = 'Maruti Suzuki', Model__c = 'Swift'),
            new Vehicle_Make_Model__c(Name = 'Maruti Suzuki Baleno', Make__c = 'Maruti Suzuki', Model__c = 'Baleno'),
            new Vehicle_Make_Model__c(Name = 'Hyundai i20', Make__c = 'Hyundai', Model__c = 'i20'),
            new Vehicle_Make_Model__c(Name = 'Hyundai Creta', Make__c = 'Hyundai', Model__c = 'Creta')
        };
    }

    @isTest
    static void searchMakes_blankTerm_returnsAllDistinctMakes() {
        Test.startTest();
        List<String> results = VehicleMakeModelController.searchMakes('');
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assert(results.contains('Maruti Suzuki'));
        System.assert(results.contains('Hyundai'));
    }

    @isTest
    static void searchMakes_withTerm_filtersAndDoesNotDuplicate() {
        Test.startTest();
        List<String> results = VehicleMakeModelController.searchMakes('Maru');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Maruti Suzuki', results[0]);
    }

    @isTest
    static void searchModels_scopedToMake_onlyReturnsThatMakesModels() {
        Test.startTest();
        List<String> results = VehicleMakeModelController.searchModels('Maruti Suzuki', '');
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assert(results.contains('Swift'));
        System.assert(results.contains('Baleno'));
        System.assert(!results.contains('i20'));
    }

    @isTest
    static void searchModels_blankMake_searchesAcrossAllMakes() {
        Test.startTest();
        List<String> results = VehicleMakeModelController.searchModels(null, 'i2');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('i20', results[0]);
    }

    @isTest
    static void searchModels_termNarrowsWithinTheScopedMake() {
        Test.startTest();
        List<String> results = VehicleMakeModelController.searchModels('Hyundai', 'Cre');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Creta', results[0]);
    }
}
