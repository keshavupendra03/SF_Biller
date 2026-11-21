trigger JobSlipTrigger on Job_Slip__c (before insert, before update) {
    UpperCaseText.apply(Trigger.new, UpperCaseText.JOB_SLIP_FIELDS);
}
