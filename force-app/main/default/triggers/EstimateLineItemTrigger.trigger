trigger EstimateLineItemTrigger on Estimate_Line_Item__c (after insert, after update, after delete) {
    EstimateLineItemTriggerHandler.handleChange(Trigger.new, Trigger.old, Trigger.isDelete, Trigger.isUpdate);
}
