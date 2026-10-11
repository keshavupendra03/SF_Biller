/**
 * Recomputes Bill__c.Status__c from the sum of its Payment__c rows,
 * locking each affected Bill__c row first so two concurrent payments
 * against the same bill can't race and leave Status__c reflecting only
 * one of them.
 */
public with sharing class PaymentStatusService {

    public static void recomputeStatus(Set<Id> billIds) {
        if (billIds.isEmpty()) {
            return;
        }

        Map<Id, Decimal> paidByBill = new Map<Id, Decimal>();
        for (Id billId : billIds) {
            paidByBill.put(billId, 0);
        }

        for (AggregateResult result : [
            SELECT Bill__c billId, SUM(Amount__c) total
            FROM Payment__c
            WHERE Bill__c IN :billIds
            GROUP BY Bill__c
        ]) {
            paidByBill.put((Id) result.get('billId'), (Decimal) result.get('total'));
        }

        List<Bill__c> bills = [
            SELECT Id, Total_Amount__c FROM Bill__c WHERE Id IN :billIds FOR UPDATE
        ];
        List<Bill__c> billsToUpdate = new List<Bill__c>();
        for (Bill__c bill : bills) {
            Decimal paid = paidByBill.get(bill.Id);
            Decimal total = bill.Total_Amount__c == null ? 0 : bill.Total_Amount__c;
            String status;
            if (paid <= 0) {
                status = 'Unpaid';
            } else if (paid >= total) {
                status = 'Paid';
            } else {
                status = 'Partial';
            }
            billsToUpdate.add(new Bill__c(Id = bill.Id, Status__c = status));
        }
        update billsToUpdate;
    }
}
