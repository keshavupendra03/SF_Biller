/**
 * Intra-state (CGST+SGST split) math has exact parity with the reference
 * project's calculator — see shared/contracts/gst_rules.md and
 * test_vectors.json (deployed here as the GstTestVectors static resource).
 * That contract scoped IGST out entirely and never decided how CGST+SGST
 * vs IGST gets chosen; this project's actual rule (confirmed over state
 * comparison) is that GST type is a property of the PART being sold —
 * Part__c.Gst_Type__c is the default, copied onto Bill_Line_Item__c /
 * Estimate_Line_Item__c when a line is added, and overridable per line —
 * so each line in a bill carries its own supply type independently; a
 * single bill can mix CGST+SGST parts with IGST parts.
 *
 * The GstCalculatorInterstateTest vectors are derived directly from the
 * already-approved intra-state vectors rather than invented from scratch —
 * GST's own design guarantees IGST on a line equals that line's CGST+SGST
 * combined (the total tax owed doesn't change based on the split, only
 * which bucket it lands in).
 *
 * The 4-arg GstLineItemInput constructor (no supply type) defaults to
 * INTRA_STATE so the ported reference test suite runs unmodified against
 * this class.
 */
public with sharing class GstCalculatorService {

    public enum SupplyType { INTRA_STATE, INTER_STATE }

    public class GstLineItemInput {
        public String description;
        public Decimal quantity;
        public Decimal unitPrice;
        public Decimal taxRatePercent;
        public SupplyType supply;

        public GstLineItemInput(
            String description,
            Decimal quantity,
            Decimal unitPrice,
            Decimal taxRatePercent
        ) {
            this(description, quantity, unitPrice, taxRatePercent, SupplyType.INTRA_STATE);
        }

        public GstLineItemInput(
            String description,
            Decimal quantity,
            Decimal unitPrice,
            Decimal taxRatePercent,
            SupplyType supply
        ) {
            this.description = description;
            this.quantity = quantity;
            this.unitPrice = unitPrice;
            this.taxRatePercent = taxRatePercent;
            this.supply = supply;
        }
    }

    /**
     * One line's computed breakdown. Values are unrounded — only the
     * bill's final totals get rounded, so per-line rounding doesn't
     * compound across many lines. Exactly one of (cgst, sgst) or igst is
     * non-zero on any given line, depending on that line's supply type.
     */
    public class GstLineResult {
        public GstLineItemInput input;
        public Decimal subtotal;
        public Decimal cgst;
        public Decimal sgst;
        public Decimal igst;
        public Decimal total;

        public Decimal gst {
            get { return cgst + sgst + igst; }
        }
    }

    /** A bill's totals, summed across lines regardless of each line's own supply type. */
    public class GstBillResult {
        public List<GstLineResult> lines;
        public Decimal subtotal;
        public Decimal cgst;
        public Decimal sgst;
        public Decimal igst;
        public Decimal grandTotal;

        public Decimal gst {
            get { return cgst + sgst + igst; }
        }
    }

    /**
     * Maps the Gst_Type__c picklist's API value to SupplyType. Unrecognized
     * or blank values fall back to INTRA_STATE, matching the field's own
     * default on Part__c/line items.
     */
    public static SupplyType supplyTypeFromGstType(String gstType) {
        return 'IGST'.equalsIgnoreCase(gstType) ? SupplyType.INTER_STATE : SupplyType.INTRA_STATE;
    }

    public static GstLineResult calculateLine(GstLineItemInput input) {
        Decimal subtotal = input.quantity * input.unitPrice;
        Decimal gst = subtotal * input.taxRatePercent / 100;

        GstLineResult result = new GstLineResult();
        result.input = input;
        result.subtotal = subtotal;
        if (input.supply == SupplyType.INTER_STATE) {
            result.cgst = 0;
            result.sgst = 0;
            result.igst = gst;
        } else {
            Decimal half = gst / 2;
            result.cgst = half;
            result.sgst = half;
            result.igst = 0;
        }
        result.total = subtotal + gst;
        return result;
    }

    public static GstBillResult calculateBill(List<GstLineItemInput> inputs) {
        List<GstLineResult> lines = new List<GstLineResult>();
        Decimal subtotalSum = 0;
        Decimal cgstSum = 0;
        Decimal sgstSum = 0;
        Decimal igstSum = 0;

        for (GstLineItemInput input : inputs) {
            GstLineResult line = calculateLine(input);
            lines.add(line);
            subtotalSum += line.subtotal;
            cgstSum += line.cgst;
            sgstSum += line.sgst;
            igstSum += line.igst;
        }

        GstBillResult bill = new GstBillResult();
        bill.lines = lines;
        bill.subtotal = round2(subtotalSum);
        bill.cgst = round2(cgstSum);
        bill.sgst = round2(sgstSum);
        bill.igst = round2(igstSum);
        bill.grandTotal = round2(subtotalSum + cgstSum + sgstSum + igstSum);
        return bill;
    }

    /** Round-half-away-from-zero to 2 decimals. */
    public static Decimal round2(Decimal value) {
        return value.setScale(2, System.RoundingMode.HALF_UP);
    }
}
