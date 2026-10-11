/**
 * Recomputes Estimate__c totals from its Estimate_Line_Item__c rows via
 * GstCalculatorService — mirrors BillTotalsService exactly, including
 * per-line Gst_Type__c deciding CGST+SGST vs IGST (architecture.md §C.3).
 */
public with sharing class EstimateTotalsService {

    public static void recomputeTotals(Set<Id> estimateIds) {
        if (estimateIds.isEmpty()) {
            return;
        }

        Map<Id, List<GstCalculatorService.GstLineItemInput>> inputsByEstimate =
            new Map<Id, List<GstCalculatorService.GstLineItemInput>>();
        for (Id estimateId : estimateIds) {
            inputsByEstimate.put(estimateId, new List<GstCalculatorService.GstLineItemInput>());
        }

        for (Estimate_Line_Item__c item : [
            SELECT Estimate__c, Description__c, Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c
            FROM Estimate_Line_Item__c
            WHERE Estimate__c IN :estimateIds
        ]) {
            inputsByEstimate.get(item.Estimate__c).add(new GstCalculatorService.GstLineItemInput(
                item.Description__c,
                item.Quantity__c,
                item.Unit_Price__c,
                item.Tax_Rate_Percent__c,
                GstCalculatorService.supplyTypeFromGstType(item.Gst_Type__c)
            ));
        }

        List<Estimate__c> estimatesToUpdate = new List<Estimate__c>();
        for (Id estimateId : estimateIds) {
            GstCalculatorService.GstBillResult totals =
                GstCalculatorService.calculateBill(inputsByEstimate.get(estimateId));
            estimatesToUpdate.add(new Estimate__c(
                Id = estimateId,
                Subtotal__c = totals.subtotal,
                GST_Amount__c = totals.gst,
                Total_Amount__c = totals.grandTotal
            ));
        }
        update estimatesToUpdate;
    }
}
