public with sharing class PaymentTriggerHandler {

    public static void handleChange(
        List<Payment__c> newItems,
        List<Payment__c> oldItems,
        Boolean isDelete,
        Boolean isUpdate
    ) {
        Set<Id> billIds = new Set<Id>();
        if (!isDelete) {
            for (Payment__c payment : newItems) {
                billIds.add(payment.Bill__c);
            }
        }
        if (isDelete || isUpdate) {
            for (Payment__c payment : oldItems) {
                billIds.add(payment.Bill__c);
            }
        }
        PaymentStatusService.recomputeStatus(billIds);
    }
}
