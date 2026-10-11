public with sharing class EstimateLineItemTriggerHandler {

    public static void handleChange(
        List<Estimate_Line_Item__c> newItems,
        List<Estimate_Line_Item__c> oldItems,
        Boolean isDelete,
        Boolean isUpdate
    ) {
        Set<Id> estimateIds = new Set<Id>();
        if (!isDelete) {
            for (Estimate_Line_Item__c item : newItems) {
                estimateIds.add(item.Estimate__c);
            }
        }
        if (isDelete || isUpdate) {
            for (Estimate_Line_Item__c item : oldItems) {
                estimateIds.add(item.Estimate__c);
            }
        }
        EstimateTotalsService.recomputeTotals(estimateIds);
    }
}
