/**
 * No supplied test vectors exist for inter-state (IGST) math — the
 * reference project's contract scoped it out entirely (see
 * GstCalculatorService's class comment). Every numeric vector below is
 * derived directly from the already-approved intra-state vectors in
 * GstTestVectors (same name suffixed _interstate): GST's design guarantees
 * a line's IGST equals that line's CGST+SGST combined, since the total tax
 * owed can't change based on which bucket it's recorded in — only the
 * split does. So "igst" here is literally "cgst + sgst" from the approved
 * vector, not an independently chosen number.
 */
@isTest
private class GstCalculatorInterstateTest {

    @isTest
    static void supplyTypeFromGstType_igst_isInterState() {
        System.assertEquals(
            GstCalculatorService.SupplyType.INTER_STATE,
            GstCalculatorService.supplyTypeFromGstType('IGST')
        );
    }

    @isTest
    static void supplyTypeFromGstType_cgstSgst_isIntraState() {
        System.assertEquals(
            GstCalculatorService.SupplyType.INTRA_STATE,
            GstCalculatorService.supplyTypeFromGstType('CGST_SGST')
        );
    }

    @isTest
    static void supplyTypeFromGstType_blankOrUnrecognized_defaultsToIntraState() {
        System.assertEquals(
            GstCalculatorService.SupplyType.INTRA_STATE,
            GstCalculatorService.supplyTypeFromGstType(null)
        );
        System.assertEquals(
            GstCalculatorService.SupplyType.INTRA_STATE,
            GstCalculatorService.supplyTypeFromGstType('something_else')
        );
    }

    // single_line_qty2_x_500_at_18pct_interstate
    @isTest
    static void calculateLine_interstate_quantity2At500By18Percent() {
        GstCalculatorService.GstLineItemInput input = new GstCalculatorService.GstLineItemInput(
            'single_line_qty2_x_500_at_18pct_interstate', 2, 500, 18, GstCalculatorService.SupplyType.INTER_STATE
        );
        GstCalculatorService.GstLineResult result = GstCalculatorService.calculateLine(input);

        System.assertEquals(1000, result.subtotal);
        System.assertEquals(0, result.cgst);
        System.assertEquals(0, result.sgst);
        System.assertEquals(180, result.igst);
        System.assertEquals(180, result.gst);
        System.assertEquals(1180, result.total);
    }

    // zero_rated_line_interstate
    @isTest
    static void calculateLine_interstate_zeroRated() {
        GstCalculatorService.GstLineItemInput input = new GstCalculatorService.GstLineItemInput(
            'zero_rated_line_interstate', 1, 200, 0, GstCalculatorService.SupplyType.INTER_STATE
        );
        GstCalculatorService.GstLineResult result = GstCalculatorService.calculateLine(input);

        System.assertEquals(200, result.subtotal);
        System.assertEquals(0, result.igst);
        System.assertEquals(0, result.gst);
        System.assertEquals(200, result.total);
    }

    // high_tax_rate_28pct_interstate
    @isTest
    static void calculateLine_interstate_highTaxRate28Percent() {
        GstCalculatorService.GstLineItemInput input = new GstCalculatorService.GstLineItemInput(
            'high_tax_rate_28pct_interstate', 5, 240, 28, GstCalculatorService.SupplyType.INTER_STATE
        );
        GstCalculatorService.GstLineResult result = GstCalculatorService.calculateLine(input);

        System.assertEquals(1200, result.subtotal);
        System.assertEquals(336, result.igst);
        System.assertEquals(336, result.gst);
        System.assertEquals(1536, result.total);
    }

    // low_tax_rate_5pct_interstate
    @isTest
    static void calculateLine_interstate_lowTaxRate5Percent() {
        GstCalculatorService.GstLineItemInput input = new GstCalculatorService.GstLineItemInput(
            'low_tax_rate_5pct_interstate', 4, 100, 5, GstCalculatorService.SupplyType.INTER_STATE
        );
        GstCalculatorService.GstLineResult result = GstCalculatorService.calculateLine(input);

        System.assertEquals(400, result.subtotal);
        System.assertEquals(20, result.igst);
        System.assertEquals(20, result.gst);
        System.assertEquals(420, result.total);
    }

    // mixed_tax_rates_three_lines_interstate
    @isTest
    static void calculateBill_interstate_mixedTaxRatesThreeLines() {
        List<GstCalculatorService.GstLineItemInput> inputs = new List<GstCalculatorService.GstLineItemInput>{
            new GstCalculatorService.GstLineItemInput('line1', 1, 1000, 18, GstCalculatorService.SupplyType.INTER_STATE),
            new GstCalculatorService.GstLineItemInput('line2', 3, 100, 12, GstCalculatorService.SupplyType.INTER_STATE),
            new GstCalculatorService.GstLineItemInput('line3', 1, 500, 0, GstCalculatorService.SupplyType.INTER_STATE)
        };
        GstCalculatorService.GstBillResult result = GstCalculatorService.calculateBill(inputs);

        System.assertEquals(1800, result.subtotal);
        System.assertEquals(0, result.cgst);
        System.assertEquals(0, result.sgst);
        System.assertEquals(216, result.igst);
        System.assertEquals(216, result.gst);
        System.assertEquals(2016, result.grandTotal);
    }

    // fractional_paise_rounds_at_bill_level_only_interstate
    @isTest
    static void calculateBill_interstate_fractionalPaiseRoundsAtBillLevelOnly() {
        List<GstCalculatorService.GstLineItemInput> inputs = new List<GstCalculatorService.GstLineItemInput>{
            new GstCalculatorService.GstLineItemInput('line1', 3, 33.33, 18, GstCalculatorService.SupplyType.INTER_STATE)
        };
        GstCalculatorService.GstBillResult result = GstCalculatorService.calculateBill(inputs);

        System.assertEquals(99.99, result.subtotal);
        System.assertEquals(18.00, result.igst);
        System.assertEquals(18.00, result.gst);
        System.assertEquals(117.99, result.grandTotal);
    }

    // single_zero_tax_line_interstate
    @isTest
    static void calculateBill_interstate_singleZeroTaxLine() {
        List<GstCalculatorService.GstLineItemInput> inputs = new List<GstCalculatorService.GstLineItemInput>{
            new GstCalculatorService.GstLineItemInput('line1', 1, 500, 0, GstCalculatorService.SupplyType.INTER_STATE)
        };
        GstCalculatorService.GstBillResult result = GstCalculatorService.calculateBill(inputs);

        System.assertEquals(500, result.subtotal);
        System.assertEquals(0, result.igst);
        System.assertEquals(500, result.grandTotal);
    }

    // three_lines_clean_amounts_no_rounding_ambiguity_interstate
    @isTest
    static void calculateBill_interstate_threeLinesCleanAmounts() {
        List<GstCalculatorService.GstLineItemInput> inputs = new List<GstCalculatorService.GstLineItemInput>{
            new GstCalculatorService.GstLineItemInput('line1', 2, 6000, 18, GstCalculatorService.SupplyType.INTER_STATE),
            new GstCalculatorService.GstLineItemInput('line2', 3, 500, 12, GstCalculatorService.SupplyType.INTER_STATE),
            new GstCalculatorService.GstLineItemInput('line3', 1, 1000, 5, GstCalculatorService.SupplyType.INTER_STATE)
        };
        GstCalculatorService.GstBillResult result = GstCalculatorService.calculateBill(inputs);

        System.assertEquals(14500, result.subtotal);
        System.assertEquals(2390, result.igst);
        System.assertEquals(2390, result.gst);
        System.assertEquals(16890, result.grandTotal);
    }

    // empty_bill_interstate
    @isTest
    static void calculateBill_interstate_emptyBill() {
        GstCalculatorService.GstBillResult result = GstCalculatorService.calculateBill(
            new List<GstCalculatorService.GstLineItemInput>()
        );

        System.assertEquals(0, result.subtotal);
        System.assertEquals(0, result.igst);
        System.assertEquals(0, result.grandTotal);
    }

    /**
     * The actual confirmed business rule: GST type is per-part/per-line,
     * not per-bill — a single bill must be able to mix a CGST+SGST part
     * with an IGST part and have each line taxed independently while the
     * bill totals still sum correctly across both.
     */
    @isTest
    static void calculateBill_mixedSupplyTypesWithinOneBill_eachLineTaxedIndependently() {
        List<GstCalculatorService.GstLineItemInput> inputs = new List<GstCalculatorService.GstLineItemInput>{
            // Local part: CGST+SGST. qty2 x 500 @ 18% -> subtotal 1000, cgst 90, sgst 90.
            new GstCalculatorService.GstLineItemInput('local_part', 2, 500, 18, GstCalculatorService.SupplyType.INTRA_STATE),
            // Out-of-state part: IGST. qty5 x 240 @ 28% -> subtotal 1200, igst 336.
            new GstCalculatorService.GstLineItemInput('interstate_part', 5, 240, 28, GstCalculatorService.SupplyType.INTER_STATE)
        };
        GstCalculatorService.GstBillResult result = GstCalculatorService.calculateBill(inputs);

        System.assertEquals(2200, result.subtotal);
        System.assertEquals(90, result.cgst);
        System.assertEquals(90, result.sgst);
        System.assertEquals(336, result.igst);
        System.assertEquals(516, result.gst);
        System.assertEquals(2716, result.grandTotal);

        System.assertEquals(GstCalculatorService.SupplyType.INTRA_STATE, result.lines[0].input.supply);
        System.assertEquals(90, result.lines[0].cgst);
        System.assertEquals(0, result.lines[0].igst);

        System.assertEquals(GstCalculatorService.SupplyType.INTER_STATE, result.lines[1].input.supply);
        System.assertEquals(336, result.lines[1].igst);
        System.assertEquals(0, result.lines[1].cgst);
    }
}
