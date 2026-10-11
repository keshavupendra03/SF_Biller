/**
 * Job_Status_Stage__c drives the Jobs board's columns (JobController) and
 * is admin-editable rather than a fixed picklist (architecture.md §B).
 * Reordering uses explicit up/down swaps on Sort_Order__c rather than
 * free-form drag-and-drop — more reliable on a touch/mobile LWC than a
 * drag handle, and the only operation the reference app's UI actually
 * needs (move a stage earlier or later).
 */
public with sharing class JobStageController {

    public class JobStageControllerException extends Exception {}

    public class StageItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Integer sortOrder { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
    }

    @AuraEnabled
    public static List<StageItem> listStages(Boolean includeInactive) {
        List<Job_Status_Stage__c> records = includeInactive
            ? [SELECT Name, Sort_Order__c, Is_Active__c FROM Job_Status_Stage__c ORDER BY Sort_Order__c]
            : [
                SELECT Name, Sort_Order__c, Is_Active__c FROM Job_Status_Stage__c
                WHERE Is_Active__c = true
                ORDER BY Sort_Order__c
            ];
        List<StageItem> results = new List<StageItem>();
        for (Job_Status_Stage__c s : records) {
            results.add(toItem(s));
        }
        return results;
    }

    @AuraEnabled
    public static StageItem createStage(String name) {
        if (String.isBlank(name)) {
            throw new JobStageControllerException('A stage name is required.');
        }
        Integer maxSortOrder = 0;
        for (AggregateResult result : [SELECT MAX(Sort_Order__c) maxOrder FROM Job_Status_Stage__c]) {
            Object maxOrder = result.get('maxOrder');
            maxSortOrder = maxOrder == null ? 0 : ((Decimal) maxOrder).intValue();
        }
        Job_Status_Stage__c stage = new Job_Status_Stage__c(
            Name = name,
            Sort_Order__c = maxSortOrder + 1,
            Is_Active__c = true
        );
        insert stage;
        return toItem(stage);
    }

    @AuraEnabled
    public static void renameStage(Id stageId, String name) {
        if (stageId == null || String.isBlank(name)) {
            throw new JobStageControllerException('A stage and a name are required.');
        }
        update new Job_Status_Stage__c(Id = stageId, Name = name);
    }

    @AuraEnabled
    public static void setStageActive(Id stageId, Boolean active) {
        if (stageId == null) {
            throw new JobStageControllerException('A stage is required.');
        }
        update new Job_Status_Stage__c(Id = stageId, Is_Active__c = active);
    }

    @AuraEnabled
    public static void moveStage(Id stageId, Boolean moveUp) {
        if (stageId == null) {
            throw new JobStageControllerException('A stage is required.');
        }
        List<Job_Status_Stage__c> all = [
            SELECT Sort_Order__c FROM Job_Status_Stage__c ORDER BY Sort_Order__c
        ];
        Integer currentIndex = -1;
        for (Integer i = 0; i < all.size(); i++) {
            if (all[i].Id == stageId) {
                currentIndex = i;
                break;
            }
        }
        if (currentIndex == -1) {
            throw new JobStageControllerException('Stage not found.');
        }
        Integer swapIndex = moveUp ? currentIndex - 1 : currentIndex + 1;
        if (swapIndex < 0 || swapIndex >= all.size()) {
            return;
        }
        Decimal currentOrder = all[currentIndex].Sort_Order__c;
        Decimal swapOrder = all[swapIndex].Sort_Order__c;
        update new List<Job_Status_Stage__c>{
            new Job_Status_Stage__c(Id = all[currentIndex].Id, Sort_Order__c = swapOrder),
            new Job_Status_Stage__c(Id = all[swapIndex].Id, Sort_Order__c = currentOrder)
        };
    }

    private static StageItem toItem(Job_Status_Stage__c s) {
        StageItem item = new StageItem();
        item.id = s.Id;
        item.name = s.Name;
        item.sortOrder = s.Sort_Order__c == null ? 0 : s.Sort_Order__c.intValue();
        item.isActive = s.Is_Active__c;
        return item;
    }
}
