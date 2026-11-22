/**
 * Client-side preview mirror of GstCalculatorService.cls / gst_rules.md.
 * This is NOT the system of record — the authoritative totals are always
 * whatever Apex (StoredLines) computes and persists on Bill__c once
 * the bill is actually saved. This exists only so the LWC can show live
 * running totals as staff add/edit lines, without a server round trip per
 * keystroke, for a formula simple enough that keeping two independent
 * implementations in sync (a third, alongside Dart and Apex) is low risk.
 */
const IGST = 'IGST';

function round2(value) {
    return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function calculateLine(line) {
    const quantity = Number(line.quantity) || 0;
    const unitPrice = Number(line.unitPrice) || 0;
    const taxRatePercent = Number(line.taxRatePercent) || 0;
    // A rupee discount on the line comes off before GST (G5).
    const discount = Number(line.discount) || 0;
    const subtotal = quantity * unitPrice - discount;
    const gst = (subtotal * taxRatePercent) / 100;
    const isInterState = line.gstType === IGST;

    return {
        subtotal,
        cgst: isInterState ? 0 : gst / 2,
        sgst: isInterState ? 0 : gst / 2,
        igst: isInterState ? gst : 0,
        gst,
        total: subtotal + gst
    };
}

/** What takes a total to whole rupees, half away from zero: 1390.40 gives -0.40, 1390.50 gives 0.50. */
export function roundOffFor(total) {
    const value = Number(total) || 0;
    const whole = Math.sign(value) * Math.round(Math.abs(value) + Number.EPSILON);
    return round2(whole - value);
}

/** The largest discount a line can take: its quantity times price. */
export function lineGross(line) {
    return round2((Number(line.quantity) || 0) * (Number(line.unitPrice) || 0));
}

/**
 * options.roundOff: take the grand total to whole rupees (the company's
 * roundOffTotals: Exact_Totals__c unticked), giving roundOff as the adjustment.
 */
export function calculateBillTotals(lines, options = {}) {
    let subtotalSum = 0;
    let cgstSum = 0;
    let sgstSum = 0;
    let igstSum = 0;

    lines.forEach((line) => {
        const result = calculateLine(line);
        subtotalSum += result.subtotal;
        cgstSum += result.cgst;
        sgstSum += result.sgst;
        igstSum += result.igst;
    });

    const cgst = round2(cgstSum);
    const sgst = round2(sgstSum);
    const igst = round2(igstSum);
    const exact = round2(subtotalSum + cgstSum + sgstSum + igstSum);
    const roundOff = options.roundOff ? roundOffFor(exact) : 0;

    return {
        subtotal: round2(subtotalSum),
        cgst,
        sgst,
        igst,
        gst: round2(cgst + sgst + igst),
        roundOff,
        grandTotal: round2(exact + roundOff)
    };
}

/**
 * An insurance claim split (G6), mirroring InsuranceSplitService.cls so the
 * screen can show both bills before saving. Each line's insurerPercent (blank
 * is 100) goes to the insurer; the GST-inclusive compulsory excess comes off
 * the insurer's lines in proportion to their cost to the insurer. Both sides
 * keep the full quantity and price, with the other side's share as discount.
 * Returns { insurerLines, customerLines } or { error }.
 */
export function splitClaim(lines, compulsoryExcess) {
    const excess = Number(compulsoryExcess) || 0;
    if (excess < 0) {
        return { error: 'The compulsory excess can\'t be less than zero.' };
    }
    const gross = [];
    const insurerTaxable = [];
    let insurerTotal = 0;
    for (const line of lines) {
        const text = line.insurerPercent === null || line.insurerPercent === undefined ? '' : String(line.insurerPercent).trim();
        const percent = text === '' ? 100 : Number(text);
        if (!(percent >= 0 && percent <= 100)) {
            return { error: `The insurance share on "${line.description}" must be between 0 and 100%.` };
        }
        const lineGrossValue = (Number(line.quantity) || 0) * (Number(line.unitPrice) || 0);
        const value = lineGrossValue - (Number(line.discount) || 0);
        const share = round2((value * percent) / 100);
        gross.push(lineGrossValue);
        insurerTaxable.push(share);
        insurerTotal += share * (1 + (Number(line.taxRatePercent) || 0) / 100);
    }
    if (excess > 0) {
        if (excess > round2(insurerTotal)) {
            return {
                error: `The compulsory excess (Rs. ${excess.toFixed(2)}) is more than the insurance company's share (Rs. ${round2(insurerTotal).toFixed(2)}).`
            };
        }
        for (let i = 0; i < insurerTaxable.length; i++) {
            insurerTaxable[i] = round2(insurerTaxable[i] - round2((excess * insurerTaxable[i]) / insurerTotal));
        }
    }
    const insurerLines = [];
    const customerLines = [];
    lines.forEach((line, i) => {
        const value = gross[i] - (Number(line.discount) || 0);
        const customerTaxable = round2(value - insurerTaxable[i]);
        if (insurerTaxable[i] > 0) {
            insurerLines.push({ ...line, discount: round2(gross[i] - insurerTaxable[i]) });
        }
        if (customerTaxable > 0) {
            customerLines.push({ ...line, partId: null, discount: round2(gross[i] - customerTaxable) });
        }
    });
    if (!insurerLines.length) {
        return { error: 'The insurance company pays nothing on these lines: turn the split off and bill the customer.' };
    }
    if (!customerLines.length) {
        return { error: 'The customer pays nothing: turn the split off and bill the insurance company.' };
    }
    return { insurerLines, customerLines };
}
