/**
 * Backs "Use Manual Line Instead" on the Bill/Estimate create screens.
 * A manually-typed line (no partId) is, from here on, treated exactly
 * like one picked from Inventory search: this finds an existing Part__c
 * with the same name, or creates one from the line's own price/tax/GST/
 * HSN/unit, and fills the line's partId in before it's inserted — so the
 * item is searchable in Inventory next time instead of needing to be
 * typed in from scratch again, and (for bills) its stock deducts through
 * the same BillStockService/trigger path a real inventory line already
 * uses, rather than a separate mechanism.
 */
public with sharing class PartUpsertService {

    /**
     * Mutates lineItems in place. Bulk-safe: at most one SELECT and one
     * INSERT for the whole list, never per line, and lines sharing the
     * same description within one call resolve to the same Part__c
     * instead of creating a duplicate each.
     */
    public static void fillManualPartIds(List<BillController.LineItemInput> lineItems) {
        Map<String, BillController.LineItemInput> firstLineByDescription = new Map<String, BillController.LineItemInput>();
        for (BillController.LineItemInput li : lineItems) {
            if (li.partId == null && String.isNotBlank(li.description) && !firstLineByDescription.containsKey(li.description)) {
                firstLineByDescription.put(li.description, li);
            }
        }
        if (firstLineByDescription.isEmpty()) {
            return;
        }

        Map<String, Id> partIdByName = new Map<String, Id>();
        for (Part__c p : [SELECT Id, Name FROM Part__c WHERE Name IN :firstLineByDescription.keySet()]) {
            partIdByName.put(p.Name, p.Id);
        }

        List<Part__c> toInsert = new List<Part__c>();
        List<String> toInsertNames = new List<String>();
        for (String description : firstLineByDescription.keySet()) {
            if (partIdByName.containsKey(description)) {
                continue;
            }
            BillController.LineItemInput li = firstLineByDescription.get(description);
            toInsert.add(new Part__c(
                Name = description,
                Price__c = li.unitPrice == null ? 0 : li.unitPrice,
                Tax_Rate_Percent__c = li.taxRatePercent == null ? 0 : li.taxRatePercent,
                Gst_Type__c = String.isBlank(li.gstType) ? 'CGST_SGST' : li.gstType,
                HSN_Code__c = li.hsnSacCode,
                Unit__c = li.unitLabel
            ));
            toInsertNames.add(description);
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
            for (Integer i = 0; i < toInsert.size(); i++) {
                partIdByName.put(toInsertNames[i], toInsert[i].Id);
            }
        }

        for (BillController.LineItemInput li : lineItems) {
            if (li.partId == null && String.isNotBlank(li.description) && partIdByName.containsKey(li.description)) {
                li.partId = partIdByName.get(li.description);
            }
        }
    }
}
