trigger WorkshopProfileTrigger on Workshop_Profile__c (before insert, before update) {
    GstPartyDetails.apply(Trigger.new, Trigger.oldMap);
    UpperCaseText.apply(Trigger.new, UpperCaseText.COMPANY_FIELDS);
    if (Trigger.isInsert) {
        WorkshopProfileTriggerHandler.handleBeforeInsert(Trigger.new);
    } else {
        WorkshopProfileTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
