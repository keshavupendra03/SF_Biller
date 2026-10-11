@isTest
private class JobStageControllerTest {

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
    static void listStages_defaultExcludesInactive() {
        List<Id> ids = insertStages();
        update new Job_Status_Stage__c(Id = ids[2], Is_Active__c = false);

        Test.startTest();
        List<JobStageController.StageItem> activeOnly = JobStageController.listStages(false);
        List<JobStageController.StageItem> all = JobStageController.listStages(true);
        Test.stopTest();

        System.assertEquals(2, activeOnly.size());
        System.assertEquals(3, all.size());
    }

    @isTest
    static void createStage_appendsAtEndOfSortOrder() {
        insertStages();

        Test.startTest();
        JobStageController.StageItem item = JobStageController.createStage('Quality Check');
        Test.stopTest();

        System.assertEquals(4, item.sortOrder);
        System.assertEquals(true, item.isActive);
    }

    @isTest
    static void createStage_firstStageEver_getsSortOrderOne() {
        Test.startTest();
        JobStageController.StageItem item = JobStageController.createStage('Vehicle Received');
        Test.stopTest();

        System.assertEquals(1, item.sortOrder);
    }

    @isTest
    static void renameStage_updatesName() {
        List<Id> ids = insertStages();

        Test.startTest();
        JobStageController.renameStage(ids[0], 'Vehicle Received');
        Test.stopTest();

        System.assertEquals('Vehicle Received', [SELECT Name FROM Job_Status_Stage__c WHERE Id = :ids[0]].Name);
    }

    @isTest
    static void setStageActive_togglesFlag() {
        List<Id> ids = insertStages();

        Test.startTest();
        JobStageController.setStageActive(ids[0], false);
        Test.stopTest();

        System.assertEquals(false, [SELECT Is_Active__c FROM Job_Status_Stage__c WHERE Id = :ids[0]].Is_Active__c);
    }

    @isTest
    static void moveStage_up_swapsSortOrderWithPreviousStage() {
        List<Id> ids = insertStages();

        Test.startTest();
        JobStageController.moveStage(ids[1], true);
        Test.stopTest();

        Map<Id, Decimal> orderById = new Map<Id, Decimal>();
        for (Job_Status_Stage__c s : [SELECT Id, Sort_Order__c FROM Job_Status_Stage__c]) {
            orderById.put(s.Id, s.Sort_Order__c);
        }
        System.assertEquals(2, orderById.get(ids[0]), '"Received" should have moved to position 2.');
        System.assertEquals(1, orderById.get(ids[1]), '"In Progress" should have moved to position 1.');
    }

    @isTest
    static void moveStage_atTop_movingUpIsANoOp() {
        List<Id> ids = insertStages();

        Test.startTest();
        JobStageController.moveStage(ids[0], true);
        Test.stopTest();

        System.assertEquals(1, [SELECT Sort_Order__c FROM Job_Status_Stage__c WHERE Id = :ids[0]].Sort_Order__c);
    }
}
