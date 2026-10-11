@isTest
private class VehicleMakeModelServiceTest {

    @isTest
    static void rememberIfNew_newCombination_insertsRow() {
        Test.startTest();
        VehicleMakeModelService.rememberIfNew('Maruti Suzuki', 'Swift');
        Test.stopTest();

        List<Vehicle_Make_Model__c> rows = [
            SELECT Make__c, Model__c FROM Vehicle_Make_Model__c WHERE Make__c = 'Maruti Suzuki' AND Model__c = 'Swift'
        ];
        System.assertEquals(1, rows.size());
    }

    @isTest
    static void rememberIfNew_existingCombination_doesNotInsertDuplicate() {
        insert new Vehicle_Make_Model__c(Name = 'Maruti Suzuki Swift', Make__c = 'Maruti Suzuki', Model__c = 'Swift');

        Test.startTest();
        VehicleMakeModelService.rememberIfNew('Maruti Suzuki', 'Swift');
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Vehicle_Make_Model__c WHERE Make__c = 'Maruti Suzuki' AND Model__c = 'Swift']
        );
    }

    @isTest
    static void rememberIfNew_caseInsensitiveMatch_doesNotInsertDuplicate() {
        insert new Vehicle_Make_Model__c(Name = 'Maruti Suzuki Swift', Make__c = 'Maruti Suzuki', Model__c = 'Swift');

        Test.startTest();
        VehicleMakeModelService.rememberIfNew('maruti suzuki', 'swift');
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Vehicle_Make_Model__c]);
    }

    @isTest
    static void rememberIfNew_blankMakeOrModel_isNoOp() {
        Test.startTest();
        VehicleMakeModelService.rememberIfNew('', 'Swift');
        VehicleMakeModelService.rememberIfNew('Maruti Suzuki', null);
        VehicleMakeModelService.rememberIfNew(null, null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Vehicle_Make_Model__c]);
    }
}
