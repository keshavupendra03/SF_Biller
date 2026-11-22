/**
 * A bill's or estimate's item lines, kept inside the record itself
 * (Line_Items__c, as JSON) instead of one child record per line. Salesforce
 * counts every record as 2 KB of data storage however little it holds, and a
 * Developer org has 5 MB, so a bill of four lines and a payment used six
 * records; it now uses one (architecture.md, Forty-second).
 *
 * The lines are the same BillController.LineItemInput the screens send and
 * get back, so nothing outside this class knows how they're stored. They're
 * stored the way the old Bill_Line_Item__c fields held them: amounts to two
 * places, a blank GST rate as 0, a blank GST type as CGST_SGST, a blank
 * discount as 0, and the same text lengths.
 */
public with sharing class StoredLines {

    public class StoredLinesException extends Exception {}

    // A Long Text Area's size.
    public static final Integer MAX_LENGTH = 131072;
    private static final Integer DESCRIPTION_LENGTH = 255;
    private static final Integer CODE_LENGTH = 20;
    private static final Set<String> GST_TYPES = new Set<String>{ 'CGST_SGST', 'IGST' };

    public static List<BillController.LineItemInput> read(String stored) {
        if (String.isBlank(stored)) {
            return new List<BillController.LineItemInput>();
        }
        return (List<BillController.LineItemInput>) JSON.deserialize(stored, List<BillController.LineItemInput>.class);
    }

    /** The lines as they're stored. Throws if one couldn't have been saved as a line record. */
    public static String write(List<BillController.LineItemInput> lines) {
        List<BillController.LineItemInput> stored = new List<BillController.LineItemInput>();
        for (BillController.LineItemInput li : lines == null ? new List<BillController.LineItemInput>() : lines) {
            stored.add(normalised(li));
        }
        String body = JSON.serialize(stored, true);
        if (body.length() > MAX_LENGTH) {
            throw new StoredLinesException('There are too many items to save on one document. Split it into two.');
        }
        return body;
    }

    /**
     * Puts the lines on a bill or estimate that's about to be saved, with the
     * totals worked out from them: Line_Items__c, Subtotal__c, GST_Amount__c,
     * Round_Off__c (the company's choice) and Total_Amount__c. No company means
     * the primary one.
     */
    public static void store(SObject record, Id companyId, List<BillController.LineItemInput> lines) {
        String body = write(lines);
        GstCalculatorService.GstBillResult totals = GstCalculatorService.calculateBill(gstInputs(read(body)));
        Decimal roundOff = WorkshopProfileService.roundsOff(new Set<Id>{ companyId }).get(companyId) == true
            ? GstCalculatorService.roundOff(totals.grandTotal)
            : 0;
        record.put('Line_Items__c', body);
        record.put('Subtotal__c', totals.subtotal);
        record.put('GST_Amount__c', totals.gst);
        record.put('Round_Off__c', roundOff);
        record.put('Total_Amount__c', totals.grandTotal + roundOff);
    }

    public static List<GstCalculatorService.GstLineItemInput> gstInputs(List<BillController.LineItemInput> lines) {
        List<GstCalculatorService.GstLineItemInput> inputs = new List<GstCalculatorService.GstLineItemInput>();
        for (BillController.LineItemInput li : lines) {
            inputs.add(GstCalculatorService.inputFor(li));
        }
        return inputs;
    }

    private static BillController.LineItemInput normalised(BillController.LineItemInput li) {
        String description = li.description;
        requireLength(description, DESCRIPTION_LENGTH, 'An item name');
        requireLength(li.hsnSacCode, CODE_LENGTH, 'An HSN/SAC code');
        requireLength(li.unitLabel, CODE_LENGTH, 'A unit');
        String gstType = String.isBlank(li.gstType) ? 'CGST_SGST' : li.gstType.toUpperCase();
        if (!GST_TYPES.contains(gstType)) {
            throw new StoredLinesException('"' + li.gstType + '" is not a GST type. Use CGST_SGST or IGST.');
        }

        BillController.LineItemInput copy = new BillController.LineItemInput();
        copy.partId = li.partId;
        copy.description = description;
        copy.quantity = twoPlaces(li.quantity);
        copy.unitPrice = twoPlaces(li.unitPrice);
        copy.taxRatePercent = li.taxRatePercent == null ? 0 : twoPlaces(li.taxRatePercent);
        copy.gstType = gstType;
        copy.hsnSacCode = String.isBlank(li.hsnSacCode) ? null : li.hsnSacCode;
        copy.unitLabel = String.isBlank(li.unitLabel) ? null : li.unitLabel;
        copy.discount = li.discount == null ? 0 : twoPlaces(li.discount);
        return copy;
    }

    private static void requireLength(String value, Integer maxLength, String what) {
        if (value != null && value.length() > maxLength) {
            throw new StoredLinesException(what + ' can be at most ' + maxLength + ' characters: "' + value.abbreviate(40) + '".');
        }
    }

    private static Decimal twoPlaces(Decimal value) {
        return value == null ? null : value.setScale(2, System.RoundingMode.HALF_UP);
    }
}
