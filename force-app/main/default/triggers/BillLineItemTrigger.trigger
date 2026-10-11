trigger BillLineItemTrigger on Bill_Line_Item__c (after insert, after update, after delete) {
    BillLineItemTriggerHandler.handleChange(
        Trigger.new, Trigger.old, Trigger.isInsert, Trigger.isDelete, Trigger.isUpdate
    );
}
