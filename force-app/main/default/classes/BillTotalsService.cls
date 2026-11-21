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
            SELECT Bill__c, Description__c, Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c, Discount__c
            FROM Bill_Line_Item__c
            WHERE Bill__c IN :billIds
        ]) {
            inputsByBill.get(item.Bill__c).add(GstCalculatorService.inputFor(item));
        }

        // Round-off is the company's choice, made when the lines are saved.
        Map<Id, Bill__c> records = new Map<Id, Bill__c>([SELECT Workshop_Profile__c FROM Bill__c WHERE Id IN :billIds]);
        Set<Id> companyIds = new Set<Id>();
        for (Bill__c record : records.values()) {
            companyIds.add(record.Workshop_Profile__c);
        }
        Map<Id, Boolean> roundsOff = WorkshopProfileService.roundsOff(companyIds);

        List<Bill__c> toUpdate = new List<Bill__c>();
        for (Id billId : billIds) {
            GstCalculatorService.GstBillResult totals =
                GstCalculatorService.calculateBill(inputsByBill.get(billId));
            Bill__c record = records.get(billId);
            Decimal roundOff = record != null && roundsOff.get(record.Workshop_Profile__c) == true
                ? GstCalculatorService.roundOff(totals.grandTotal)
                : 0;
            toUpdate.add(new Bill__c(
                Id = billId,
                Subtotal__c = totals.subtotal,
                GST_Amount__c = totals.gst,
                Round_Off__c = roundOff,
                Total_Amount__c = totals.grandTotal + roundOff
            ));
        }
        update toUpdate;
    }
}
