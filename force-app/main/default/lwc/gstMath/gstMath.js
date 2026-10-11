/**
 * Client-side preview mirror of GstCalculatorService.cls / gst_rules.md.
 * This is NOT the system of record — the authoritative totals are always
 * whatever Apex/BillTotalsService computes and persists on Bill__c once
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
    const subtotal = quantity * unitPrice;
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

export function calculateBillTotals(lines) {
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

    return {
        subtotal: round2(subtotalSum),
        cgst,
        sgst,
        igst,
        gst: round2(cgst + sgst + igst),
        grandTotal: round2(subtotalSum + cgstSum + sgstSum + igstSum)
    };
}
