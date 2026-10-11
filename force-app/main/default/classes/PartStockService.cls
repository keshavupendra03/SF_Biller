/**
 * The only code path allowed to write Part__c.Current_Stock__c
 * (architecture.md §C.2, revised 2026-10-10 — Stock_Movement__c removed,
 * no ledger, no per-bill audit trail by explicit product decision). Locks
 * the affected Part__c rows with FOR UPDATE before adding each delta, the
 * same lock-then-read-then-write shape as InvoiceNumberingService and
 * PaymentStatusService, so two concurrent bill creations against the same
 * part serialize instead of one silently clobbering the other's
 * deduction. Bulk-safe: one SELECT ... FOR UPDATE, one update DML,
 * regardless of how many parts are touched in this transaction.
 */
public with sharing class PartStockService {

    public static void adjustStock(Map<Id, Decimal> deltaByPartId) {
        if (deltaByPartId.isEmpty()) {
            return;
        }

        List<Part__c> parts = [
            SELECT Id, Current_Stock__c
            FROM Part__c
            WHERE Id IN :deltaByPartId.keySet()
            FOR UPDATE
        ];

        List<Part__c> partsToUpdate = new List<Part__c>();
        for (Part__c part : parts) {
            Decimal current = part.Current_Stock__c == null ? 0 : part.Current_Stock__c;
            partsToUpdate.add(new Part__c(
                Id = part.Id,
                Current_Stock__c = current + deltaByPartId.get(part.Id)
            ));
        }
        update partsToUpdate;
    }
}
