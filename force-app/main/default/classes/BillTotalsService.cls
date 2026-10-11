/**
 * Recomputes Bill__c totals from its Bill_Line_Item__c rows via
 * GstCalculatorService. Line items are Lookup, not Master-Detail (to keep
 * this exact computation as the one source of truth instead of a
 * declarative rollup duplicating it), so this trigger-driven recompute is
 * what keeps totals correct whenever a line item is added, edited, or
 * removed. Each line's own Gst_Type__c decides CGST+SGST vs IGST for that
 * line (architecture.md §C.3) — a single bill can mix both.
 */
public with sharing class BillTotalsService {

    public static void recomputeTotals(Set<Id> billIds) {
        if (billIds.isEmpty()) {
            return;
        }

        Map<Id, List<GstCalculatorService.GstLineItemInput>> inputsByBill =
            new Map<Id, List<GstCalculatorService.GstLineItemInput>>();
        for (Id billId : billIds) {
            inputsByBill.put(billId, new List<GstCalculatorService.GstLineItemInput>());
        }

        for (Bill_Line_Item__c item : [
            SELECT Bill__c, Description__c, Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c
            FROM Bill_Line_Item__c
            WHERE Bill__c IN :billIds
        ]) {
            inputsByBill.get(item.Bill__c).add(new GstCalculatorService.GstLineItemInput(
                item.Description__c,
                item.Quantity__c,
                item.Unit_Price__c,
                item.Tax_Rate_Percent__c,
                GstCalculatorService.supplyTypeFromGstType(item.Gst_Type__c)
            ));
        }

        List<Bill__c> billsToUpdate = new List<Bill__c>();
        for (Id billId : billIds) {
            GstCalculatorService.GstBillResult totals =
                GstCalculatorService.calculateBill(inputsByBill.get(billId));
            billsToUpdate.add(new Bill__c(
                Id = billId,
                Subtotal__c = totals.subtotal,
                GST_Amount__c = totals.gst,
                Total_Amount__c = totals.grandTotal
            ));
        }
        update billsToUpdate;
    }
}
