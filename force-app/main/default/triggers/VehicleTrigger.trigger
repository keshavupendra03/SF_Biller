trigger VehicleTrigger on Vehicle__c (before insert, before update) {
    UpperCaseText.apply(Trigger.new, UpperCaseText.VEHICLE_FIELDS);
}
