trigger CustomerTrigger on Customer__c (before insert, before update) {
    GstPartyDetails.apply(Trigger.new, Trigger.oldMap);
}
