/**
 * Deducts/restores Part__c.Current_Stock__c directly for a bill's lines that
 * reference a part (architecture.md §C.2, revised 2026-10-10) — no ledger, no
 * per-bill trace by design; see PartStockService for the row-locking that
 * keeps this safe under concurrent bill creation against the same part.
 *
 * A bill's lines are fixed once saved (a change is a new version), so this is
 * only ever called with a whole bill's lines: deducted when the bill is saved,
 * restored when it's replaced by a new version or deleted. A part deleted
 * since is skipped (PartStockService only updates the parts it finds).
 */
public with sharing class BillStockService {

    public static void deduct(List<BillController.LineItemInput> lines) {
        applyDelta(lines, -1);
    }

    public static void restore(List<BillController.LineItemInput> lines) {
        applyDelta(lines, 1);
    }

    private static void applyDelta(List<BillController.LineItemInput> lines, Integer sign) {
        Map<Id, Decimal> deltaByPartId = new Map<Id, Decimal>();
        for (BillController.LineItemInput line : lines) {
            if (line.partId != null && line.quantity != null) {
                Decimal existing = deltaByPartId.containsKey(line.partId) ? deltaByPartId.get(line.partId) : 0;
                deltaByPartId.put(line.partId, existing + (sign * line.quantity));
            }
        }
        PartStockService.adjustStock(deltaByPartId);
    }
}
