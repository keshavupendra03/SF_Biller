public with sharing class BillLineItemTriggerHandler {

    public static void handleChange(
        List<Bill_Line_Item__c> newItems,
        List<Bill_Line_Item__c> oldItems,
        Boolean isInsert,
        Boolean isDelete,
        Boolean isUpdate
    ) {
        Set<Id> billIds = new Set<Id>();
        if (!isDelete) {
            for (Bill_Line_Item__c item : newItems) {
                billIds.add(item.Bill__c);
            }
        }
        // Covers both delete (only oldItems has data) and the edge case of
        // a line item's Bill__c lookup itself being changed on update,
        // where the OLD bill's total needs recomputing too.
        if (isDelete || isUpdate) {
            for (Bill_Line_Item__c item : oldItems) {
                billIds.add(item.Bill__c);
            }
        }
        BillTotalsService.recomputeTotals(billIds);

        if (isInsert) {
            BillStockService.deductForNewLineItems(newItems);
        } else if (isDelete) {
            BillStockService.restoreForRemovedLineItems(oldItems);
        }
    }
}
