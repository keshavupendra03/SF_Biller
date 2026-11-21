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
            SELECT Estimate__c, Description__c, Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c, Discount__c
            FROM Estimate_Line_Item__c
            WHERE Estimate__c IN :estimateIds
        ]) {
            inputsByEstimate.get(item.Estimate__c).add(GstCalculatorService.inputFor(item));
        }

        // Round-off is the company's choice, made when the lines are saved.
        Map<Id, Estimate__c> records = new Map<Id, Estimate__c>([SELECT Workshop_Profile__c FROM Estimate__c WHERE Id IN :estimateIds]);
        Set<Id> companyIds = new Set<Id>();
        for (Estimate__c record : records.values()) {
            companyIds.add(record.Workshop_Profile__c);
        }
        Map<Id, Boolean> roundsOff = WorkshopProfileService.roundsOff(companyIds);

        List<Estimate__c> toUpdate = new List<Estimate__c>();
        for (Id estimateId : estimateIds) {
            GstCalculatorService.GstBillResult totals =
                GstCalculatorService.calculateBill(inputsByEstimate.get(estimateId));
            Estimate__c record = records.get(estimateId);
            Decimal roundOff = record != null && roundsOff.get(record.Workshop_Profile__c) == true
                ? GstCalculatorService.roundOff(totals.grandTotal)
                : 0;
            toUpdate.add(new Estimate__c(
                Id = estimateId,
                Subtotal__c = totals.subtotal,
                GST_Amount__c = totals.gst,
                Round_Off__c = roundOff,
                Total_Amount__c = totals.grandTotal + roundOff
            ));
        }
        update toUpdate;
    }
}
