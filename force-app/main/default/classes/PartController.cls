/**
 * The single Apex entry point for the Inventory LWC (architecture.md §B).
 * Current_Stock__c is written directly here (architecture.md §C.2,
 * revised 2026-10-10 — no Stock_Movement__c ledger, no per-bill audit
 * trail by design): createPart sets the opening balance directly on
 * insert, and adjustStock goes through PartStockService.adjustStock,
 * which locks the Part__c row before applying the delta. That same
 * service is also the path BillStockService uses for bill-driven
 * deductions, so every stock write funnels through one place.
 */
public with sharing class PartController {

    public class PartControllerException extends Exception {}

    public class PartListItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String sku { get; set; }
        @AuraEnabled public String barcode { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Decimal currentStock { get; set; }
        @AuraEnabled public Decimal lowStockThreshold { get; set; }
        @AuraEnabled public Boolean isLowStock { get; set; }
        @AuraEnabled public String gstType { get; set; }
        @AuraEnabled public Decimal taxRatePercent { get; set; }
        @AuraEnabled public String hsnCode { get; set; }
        @AuraEnabled public String unitLabel { get; set; }
    }

    public class PartDetail {
        @AuraEnabled public PartListItem part { get; set; }
    }

    public class PartInput {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String sku { get; set; }
        @AuraEnabled public String barcode { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Decimal lowStockThreshold { get; set; }
        @AuraEnabled public String gstType { get; set; }
        @AuraEnabled public Decimal taxRatePercent { get; set; }
        @AuraEnabled public String hsnCode { get; set; }
        @AuraEnabled public String unitLabel { get; set; }
        @AuraEnabled public Decimal openingStock { get; set; }
    }

    @AuraEnabled
    public static List<PartListItem> listParts(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(String.isBlank(searchTerm) ? '' : searchTerm) + '%';
        List<Part__c> parts = String.isBlank(searchTerm)
            ? [
                SELECT Name, SKU__c, Barcode__c, Price__c, Current_Stock__c, Low_Stock_Threshold__c,
                       Is_Low_Stock__c, Gst_Type__c, Tax_Rate_Percent__c, HSN_Code__c, Unit__c
                FROM Part__c
                ORDER BY Name
                LIMIT 200
            ]
            : [
                SELECT Name, SKU__c, Barcode__c, Price__c, Current_Stock__c, Low_Stock_Threshold__c,
                       Is_Low_Stock__c, Gst_Type__c, Tax_Rate_Percent__c, HSN_Code__c, Unit__c
                FROM Part__c
                WHERE Name LIKE :term OR SKU__c LIKE :term OR Barcode__c LIKE :term
                ORDER BY Name
                LIMIT 200
            ];

        List<PartListItem> results = new List<PartListItem>();
        for (Part__c p : parts) {
            results.add(toListItem(p));
        }
        return results;
    }

    @AuraEnabled
    public static PartDetail getPartDetail(Id partId) {
        if (partId == null) {
            throw new PartControllerException('A part is required.');
        }
        Part__c p = [
            SELECT Name, SKU__c, Barcode__c, Price__c, Current_Stock__c, Low_Stock_Threshold__c,
                   Is_Low_Stock__c, Gst_Type__c, Tax_Rate_Percent__c, HSN_Code__c, Unit__c
            FROM Part__c
            WHERE Id = :partId
        ];

        PartDetail detail = new PartDetail();
        detail.part = toListItem(p);
        return detail;
    }

    @AuraEnabled
    public static PartListItem createPart(PartInput input) {
        validate(input);
        Part__c part = new Part__c(
            Name = input.name,
            SKU__c = input.sku,
            Barcode__c = input.barcode,
            Price__c = input.price == null ? 0 : input.price,
            Current_Stock__c = input.openingStock == null ? 0 : input.openingStock,
            Low_Stock_Threshold__c = input.lowStockThreshold,
            Gst_Type__c = String.isBlank(input.gstType) ? 'CGST_SGST' : input.gstType,
            Tax_Rate_Percent__c = input.taxRatePercent == null ? 0 : input.taxRatePercent,
            HSN_Code__c = input.hsnCode,
            Unit__c = input.unitLabel
        );
        insert part;

        return toListItem([
            SELECT Name, SKU__c, Barcode__c, Price__c, Current_Stock__c, Low_Stock_Threshold__c,
                   Is_Low_Stock__c, Gst_Type__c, Tax_Rate_Percent__c, HSN_Code__c, Unit__c
            FROM Part__c
            WHERE Id = :part.Id
        ]);
    }

    @AuraEnabled
    public static void updatePart(Id partId, PartInput input) {
        if (partId == null) {
            throw new PartControllerException('A part is required.');
        }
        validate(input);
        update new Part__c(
            Id = partId,
            Name = input.name,
            SKU__c = input.sku,
            Barcode__c = input.barcode,
            Price__c = input.price == null ? 0 : input.price,
            Low_Stock_Threshold__c = input.lowStockThreshold,
            Gst_Type__c = String.isBlank(input.gstType) ? 'CGST_SGST' : input.gstType,
            Tax_Rate_Percent__c = input.taxRatePercent == null ? 0 : input.taxRatePercent,
            HSN_Code__c = input.hsnCode,
            Unit__c = input.unitLabel
        );
    }

    @AuraEnabled
    public static void adjustStock(Id partId, Decimal quantityDelta) {
        if (partId == null || quantityDelta == null || quantityDelta == 0) {
            throw new PartControllerException('A part and a non-zero quantity are required.');
        }
        PartStockService.adjustStock(new Map<Id, Decimal>{ partId => quantityDelta });
    }

    private static void validate(PartInput input) {
        if (input == null || String.isBlank(input.name)) {
            throw new PartControllerException('A part name is required.');
        }
    }

    private static PartListItem toListItem(Part__c p) {
        PartListItem item = new PartListItem();
        item.id = p.Id;
        item.name = p.Name;
        item.sku = p.SKU__c;
        item.barcode = p.Barcode__c;
        item.price = p.Price__c;
        item.currentStock = p.Current_Stock__c;
        item.lowStockThreshold = p.Low_Stock_Threshold__c;
        item.isLowStock = p.Is_Low_Stock__c;
        item.gstType = p.Gst_Type__c;
        item.taxRatePercent = p.Tax_Rate_Percent__c;
        item.hsnCode = p.HSN_Code__c;
        item.unitLabel = p.Unit__c;
        return item;
    }
}
