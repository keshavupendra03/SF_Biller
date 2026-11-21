trigger BillToPartyTrigger on Bill_To_Party__c (before insert, before update) {
    GstPartyDetails.apply(Trigger.new, Trigger.oldMap);
}
