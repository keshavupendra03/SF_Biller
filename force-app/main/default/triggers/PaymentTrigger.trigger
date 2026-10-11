trigger PaymentTrigger on Payment__c (after insert, after update, after delete) {
    PaymentTriggerHandler.handleChange(Trigger.new, Trigger.old, Trigger.isDelete, Trigger.isUpdate);
}
