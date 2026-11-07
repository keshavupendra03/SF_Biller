trigger WorkshopProfileTrigger on Workshop_Profile__c (before insert, before update) {
    if (Trigger.isInsert) {
        WorkshopProfileTriggerHandler.handleBeforeInsert(Trigger.new);
    } else {
        WorkshopProfileTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
