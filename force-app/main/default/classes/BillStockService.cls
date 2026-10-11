/**
 * Deducts/restores Part__c.Current_Stock__c directly for Bill_Line_Item__c
 * rows that reference a part (architecture.md §C.2, revised 2026-10-10) —
 * no ledger, no per-bill trace by design; see PartStockService for the
 * row-locking that keeps this safe under concurrent bill creation against
 * the same part.
 *
 * Scope: insert (deduct) and delete (restore) are both handled, since
 * they're symmetric. Changing an existing line's Quantity__c or Part__c on
 * an already-saved bill is NOT reconciled here — that needs the net
 * already-deducted amount, which isn't tracked per line anymore, and is
 * real work left for whenever Stage 4's "edit an already-created bill's
 * line items" need actually surfaces, rather than built speculatively now.
 */
public with sharing class BillStockService {

    public static void deductForNewLineItems(List<Bill_Line_Item__c> newItems) {
        applyDelta(newItems, -1);
    }

    public static void restoreForRemovedLineItems(List<Bill_Line_Item__c> oldItems) {
        applyDelta(oldItems, 1);
    }

    private static void applyDelta(List<Bill_Line_Item__c> items, Integer sign) {
        Map<Id, Decimal> deltaByPartId = new Map<Id, Decimal>();
        for (Bill_Line_Item__c item : items) {
            if (item.Part__c != null) {
                Decimal existing = deltaByPartId.containsKey(item.Part__c) ? deltaByPartId.get(item.Part__c) : 0;
                deltaByPartId.put(item.Part__c, existing + (sign * item.Quantity__c));
            }
        }
        PartStockService.adjustStock(deltaByPartId);
    }
}
