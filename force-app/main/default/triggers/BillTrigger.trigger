trigger BillTrigger on Bill__c (before insert) {
    BillTriggerHandler.handleBeforeInsert(Trigger.new);
}
