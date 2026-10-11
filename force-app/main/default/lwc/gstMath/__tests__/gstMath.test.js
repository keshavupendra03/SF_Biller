import { calculateLine, calculateBillTotals } from 'c/gstMath';

describe('gstMath (client-preview mirror of GstCalculatorService.cls)', () => {
    describe('calculateLine — intra-state (CGST+SGST)', () => {
        it('single_line_qty2_x_500_at_18pct', () => {
            const result = calculateLine({ quantity: 2, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST' });
            expect(result.subtotal).toBe(1000);
            expect(result.cgst).toBe(90);
            expect(result.sgst).toBe(90);
            expect(result.igst).toBe(0);
            expect(result.gst).toBe(180);
            expect(result.total).toBe(1180);
        });

        it('zero_rated_line', () => {
            const result = calculateLine({ quantity: 1, unitPrice: 200, taxRatePercent: 0, gstType: 'CGST_SGST' });
            expect(result.subtotal).toBe(200);
            expect(result.gst).toBe(0);
            expect(result.total).toBe(200);
        });

        it('high_tax_rate_28pct', () => {
            const result = calculateLine({ quantity: 5, unitPrice: 240, taxRatePercent: 28, gstType: 'CGST_SGST' });
            expect(result.subtotal).toBe(1200);
            expect(result.cgst).toBe(168);
            expect(result.sgst).toBe(168);
            expect(result.total).toBe(1536);
        });
    });

    describe('calculateLine — inter-state (IGST)', () => {
        it('puts the full gst into igst, leaving cgst/sgst at zero', () => {
            const result = calculateLine({ quantity: 2, unitPrice: 500, taxRatePercent: 18, gstType: 'IGST' });
            expect(result.cgst).toBe(0);
            expect(result.sgst).toBe(0);
            expect(result.igst).toBe(180);
            expect(result.gst).toBe(180);
            expect(result.total).toBe(1180);
        });
    });

    describe('calculateBillTotals', () => {
        it('mixed_tax_rates_three_lines (intra-state)', () => {
            const totals = calculateBillTotals([
                { quantity: 1, unitPrice: 1000, taxRatePercent: 18, gstType: 'CGST_SGST' },
                { quantity: 3, unitPrice: 100, taxRatePercent: 12, gstType: 'CGST_SGST' },
                { quantity: 1, unitPrice: 500, taxRatePercent: 0, gstType: 'CGST_SGST' }
            ]);
            expect(totals.subtotal).toBe(1800);
            expect(totals.cgst).toBe(108);
            expect(totals.sgst).toBe(108);
            expect(totals.gst).toBe(216);
            expect(totals.grandTotal).toBe(2016);
        });

        it('empty_bill', () => {
            const totals = calculateBillTotals([]);
            expect(totals.subtotal).toBe(0);
            expect(totals.grandTotal).toBe(0);
        });

        it('mixes CGST+SGST and IGST lines within one bill, each bucket summed independently', () => {
            const totals = calculateBillTotals([
                { quantity: 2, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST' },
                { quantity: 5, unitPrice: 240, taxRatePercent: 28, gstType: 'IGST' }
            ]);
            expect(totals.subtotal).toBe(2200);
            expect(totals.cgst).toBe(90);
            expect(totals.sgst).toBe(90);
            expect(totals.igst).toBe(336);
            expect(totals.gst).toBe(516);
            expect(totals.grandTotal).toBe(2716);
        });

        it('rounds only at the bill level, not per line (fractional_paise_rounds_at_bill_level_only)', () => {
            const totals = calculateBillTotals([
                { quantity: 3, unitPrice: 33.33, taxRatePercent: 18, gstType: 'CGST_SGST' }
            ]);
            expect(totals.subtotal).toBe(99.99);
            expect(totals.cgst).toBe(9.0);
            expect(totals.sgst).toBe(9.0);
            expect(totals.grandTotal).toBe(117.99);
        });
    });
});
