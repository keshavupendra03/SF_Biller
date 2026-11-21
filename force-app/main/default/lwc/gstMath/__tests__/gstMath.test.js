import { calculateLine, calculateBillTotals, roundOffFor, lineGross, splitClaim as split } from 'c/gstMath';

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

    describe('discount and round-off (G5, same figures as RoundOffDiscountTest.cls)', () => {
        it('a rupee discount comes off before GST: 2 x 500 - 100 @18% = 1062', () => {
            const line = { quantity: 2, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', discount: 100 };
            expect(calculateLine(line).subtotal).toBe(900);
            const totals = calculateBillTotals([line]);
            expect(totals.cgst).toBe(81);
            expect(totals.sgst).toBe(81);
            expect(totals.grandTotal).toBe(1062);
            expect(totals.roundOff).toBe(0);
        });

        it('a blank discount is none', () => {
            expect(calculateLine({ quantity: 1, unitPrice: 100, discount: '' }).subtotal).toBe(100);
        });

        it('rounds the total to whole rupees only when asked: 392.94 -> 393 (+0.06)', () => {
            const lines = [{ quantity: 1, unitPrice: 333, taxRatePercent: 18, gstType: 'CGST_SGST' }];
            expect(calculateBillTotals(lines).grandTotal).toBe(392.94);
            const rounded = calculateBillTotals(lines, { roundOff: true });
            expect(rounded.roundOff).toBe(0.06);
            expect(rounded.grandTotal).toBe(393);
            expect(rounded.subtotal).toBe(333);
        });

        it('rounds down too: 401.20 -> 401 (-0.20)', () => {
            const rounded = calculateBillTotals([{ quantity: 1, unitPrice: 340, taxRatePercent: 18, gstType: 'CGST_SGST' }], { roundOff: true });
            expect(rounded.roundOff).toBe(-0.2);
            expect(rounded.grandTotal).toBe(401);
        });

        it('half a rupee goes up, like Apex HALF_UP', () => {
            expect(roundOffFor(1390.5)).toBe(0.5);
            expect(roundOffFor(1390.4)).toBe(-0.4);
            expect(roundOffFor(1390)).toBe(0);
            expect(roundOffFor(0)).toBe(0);
        });

        it('lineGross is the most a line can be discounted', () => {
            expect(lineGross({ quantity: 2, unitPrice: 500 })).toBe(1000);
            expect(lineGross({ quantity: '', unitPrice: 500 })).toBe(0);
        });
    });
});

// Same job and figures as InsuranceSplitServiceTest.cls.
describe('splitClaim (G6, mirror of InsuranceSplitService.cls)', () => {
    const job = () => [
        { description: 'Bumper', quantity: 1, unitPrice: 1000, taxRatePercent: 18, gstType: 'CGST_SGST', partId: 'p1', insurerPercent: '' },
        { description: 'Headlamp', quantity: 1, unitPrice: 1000, taxRatePercent: 18, gstType: 'CGST_SGST', insurerPercent: '50' },
        { description: 'Labour', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', insurerPercent: 100 }
    ];
    const taxable = (lines) => Object.fromEntries(lines.map((l) => [l.description, l.quantity * l.unitPrice - l.discount]));

    it('splits each line by its percent, blank being 100', () => {
        const result = split(job(), 0);
        expect(taxable(result.insurerLines)).toEqual({ Bumper: 1000, Headlamp: 500, Labour: 500 });
        expect(taxable(result.customerLines)).toEqual({ Headlamp: 500 });
        expect(result.customerLines[0].unitPrice).toBe(1000);
    });

    it('moves the excess to the customer, and the two bills add up to the job', () => {
        const result = split(job(), 590);
        expect(taxable(result.insurerLines)).toEqual({ Bumper: 750, Headlamp: 375, Labour: 375 });
        expect(taxable(result.customerLines)).toEqual({ Bumper: 250, Headlamp: 625, Labour: 125 });
        const insurer = calculateBillTotals(result.insurerLines).grandTotal;
        const customer = calculateBillTotals(result.customerLines).grandTotal;
        expect(insurer).toBe(1770);
        expect(customer).toBe(1180);
        expect(result.customerLines.every((l) => l.partId === null)).toBe(true);
        expect(result.insurerLines[0].partId).toBe('p1');
    });

    it('refuses what cannot be split', () => {
        expect(split(job(), -1).error).toContain('less than zero');
        expect(split(job(), 3000).error).toContain("more than the insurance company's share");
        expect(split(job().map((l) => ({ ...l, insurerPercent: 120 })), 0).error).toContain('between 0 and 100%');
        expect(split(job().map((l) => ({ ...l, insurerPercent: 100 })), 0).error).toContain('The customer pays nothing');
        expect(split(job().map((l) => ({ ...l, insurerPercent: 0 })), 0).error).toContain('The insurance company pays nothing');
    });
});
