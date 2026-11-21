/**
 * Builds a company's GST return for a month or quarter from its bills
 * (architecture.md §D.1, stage G3): GSTR-1's tables and the sales side of
 * GSTR-3B, with the GST checkup, all from one pass so they can't disagree.
 *
 * Which bills: dated in the period, of the company (a bill with no company is
 * the primary one's). Only live bills (latest version, not deleted) carry
 * amounts. Every number issued in the period is accounted for in Table 13,
 * documents issued, where deleted bills and versions replaced by an edit
 * (architecture.md §C.4) count as cancelled.
 *
 * Amounts come from GstCalculatorService line by line, as on the bills, and
 * are rounded once per reported row. Each line's CGST+SGST or IGST is reported
 * as charged (§C.3); the checkup flags any that don't fit the place of supply.
 */
public with sharing class GstReturnService {

    public class GstReturnException extends Exception {}

    // GSTR-1 Table 5: an inter-state sale to an unregistered buyer above this
    // is B2C (Large). One lakh since August 2024.
    public static final Decimal B2CL_LIMIT = 100000;

    public static final String NIL_INTER_REGISTERED = 'Inter-State supplies to registered persons';
    public static final String NIL_INTRA_REGISTERED = 'Intra-State supplies to registered persons';
    public static final String NIL_INTER_UNREGISTERED = 'Inter-State supplies to unregistered persons';
    public static final String NIL_INTRA_UNREGISTERED = 'Intra-State supplies to unregistered persons';
    public static final String DOCUMENT_NATURE = 'Invoices for outward supply';

    // ---- what a return holds ------------------------------------------------

    /** One invoice at one rate: a B2B (Table 4) or B2C Large (Table 5) row. */
    public class InvoiceRow {
        @AuraEnabled public Id billId { get; set; }
        @AuraEnabled public String gstin { get; set; }
        @AuraEnabled public String receiverName { get; set; }
        @AuraEnabled public String invoiceNumber { get; set; }
        @AuraEnabled public Date invoiceDate { get; set; }
        @AuraEnabled public Decimal invoiceValue { get; set; }
        @AuraEnabled public String placeOfSupply { get; set; }
        @AuraEnabled public Decimal rate { get; set; }
        @AuraEnabled public Decimal taxableValue { get; set; }
        @AuraEnabled public Decimal igst { get; set; }
        @AuraEnabled public Decimal cgst { get; set; }
        @AuraEnabled public Decimal sgst { get; set; }
    }

    /** B2C (Small) by place of supply and rate (Table 7), and GSTR-3B 3.2 by state. */
    public class SummaryRow {
        @AuraEnabled public String placeOfSupply { get; set; }
        @AuraEnabled public Decimal rate { get; set; }
        @AuraEnabled public Decimal taxableValue { get; set; }
        @AuraEnabled public Decimal igst { get; set; }
        @AuraEnabled public Decimal cgst { get; set; }
        @AuraEnabled public Decimal sgst { get; set; }
    }

    /** Table 8: nil rated supplies, by kind. */
    public class NilRow {
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal nilRated { get; set; }
    }

    /** Table 12: HSN-wise summary. */
    public class HsnRow {
        @AuraEnabled public String hsn { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String uqc { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal totalValue { get; set; }
        @AuraEnabled public Decimal rate { get; set; }
        @AuraEnabled public Decimal taxableValue { get; set; }
        @AuraEnabled public Decimal igst { get; set; }
        @AuraEnabled public Decimal cgst { get; set; }
        @AuraEnabled public Decimal sgst { get; set; }
    }

    /** Table 13: one unbroken run of invoice numbers issued in the period. */
    public class DocumentRow {
        @AuraEnabled public String nature { get; set; }
        @AuraEnabled public String fromNumber { get; set; }
        @AuraEnabled public String toNumber { get; set; }
        @AuraEnabled public Integer totalNumber { get; set; }
        @AuraEnabled public Integer cancelled { get; set; }
        @AuraEnabled public Integer netIssued { get; set; }
    }

    /** GSTR-3B's sales side. */
    public class Gstr3b {
        // 3.1(a): taxable supplies other than nil rated.
        @AuraEnabled public Decimal taxableValue { get; set; }
        @AuraEnabled public Decimal igst { get; set; }
        @AuraEnabled public Decimal cgst { get; set; }
        @AuraEnabled public Decimal sgst { get; set; }
        // 3.1(c): nil rated.
        @AuraEnabled public Decimal nilRated { get; set; }
        // 3.2: inter-state supplies to unregistered persons, by state.
        @AuraEnabled public List<SummaryRow> unregisteredInterState { get; set; }
    }

    /** Something to put right (error: stops "Mark as filed") or to know (warning). */
    public class Issue {
        @AuraEnabled public String severity { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id billId { get; set; }
        @AuraEnabled public String documentNumber { get; set; }
    }

    public class GstReturn {
        @AuraEnabled public Id companyId { get; set; }
        @AuraEnabled public String companyName { get; set; }
        @AuraEnabled public String gstin { get; set; }
        // The company's own GST state code: decides inter-state or not.
        @AuraEnabled public String companyStateCode { get; set; }
        @AuraEnabled public String registrationType { get; set; }
        @AuraEnabled public String filingFrequency { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public Date filedUpTo { get; set; }
        @AuraEnabled public Boolean isFiled { get; set; }
        @AuraEnabled public Integer billCount { get; set; }
        @AuraEnabled public Decimal invoiceValue { get; set; }
        @AuraEnabled public List<InvoiceRow> b2b { get; set; }
        @AuraEnabled public List<InvoiceRow> b2cl { get; set; }
        @AuraEnabled public List<SummaryRow> b2cs { get; set; }
        @AuraEnabled public List<NilRow> nil { get; set; }
        @AuraEnabled public List<HsnRow> hsnB2b { get; set; }
        @AuraEnabled public List<HsnRow> hsnB2c { get; set; }
        @AuraEnabled public List<DocumentRow> documents { get; set; }
        @AuraEnabled public Gstr3b gstr3b { get; set; }
        // A composition company files CMP-08 on its turnover, not GSTR-1.
        @AuraEnabled public Decimal compositionTurnover { get; set; }
        @AuraEnabled public List<Issue> issues { get; set; }
        @AuraEnabled public Integer errorCount { get; set; }
        @AuraEnabled public Integer warningCount { get; set; }
    }

    // Running sums, rounded once when a row is made.
    private class Amounts {
        Decimal taxable = 0;
        Decimal igst = 0;
        Decimal cgst = 0;
        Decimal sgst = 0;
        Decimal quantity = 0;
        String description;

        void add(GstCalculatorService.GstLineResult line) {
            taxable += line.subtotal;
            igst += line.igst;
            cgst += line.cgst;
            sgst += line.sgst;
        }
    }

    // ---- building it --------------------------------------------------------

    public static GstReturn build(Id companyId, Date startDate, Date endDate) {
        if (startDate == null || endDate == null || endDate < startDate) {
            throw new GstReturnException('Pick a month or quarter.');
        }
        Id primaryId = WorkshopProfileService.primaryId();
        Id profileId = companyId != null ? companyId : primaryId;
        if (profileId == null) {
            throw new GstReturnException('Save the workshop details first.');
        }
        Workshop_Profile__c company = [
            SELECT Name, GSTIN__c, State__c, GST_Registration_Type__c, GST_Filing_Frequency__c, GST_Filed_Up_To__c
            FROM Workshop_Profile__c WHERE Id = :profileId
        ];
        Id orNoCompany = profileId == primaryId ? null : profileId;

        GstReturn ret = new GstReturn();
        ret.companyId = profileId;
        ret.companyName = company.Name;
        ret.gstin = company.GSTIN__c;
        ret.registrationType = String.isBlank(company.GST_Registration_Type__c) ? 'Regular' : company.GST_Registration_Type__c;
        ret.filingFrequency = String.isBlank(company.GST_Filing_Frequency__c) ? 'Monthly' : company.GST_Filing_Frequency__c;
        ret.startDate = startDate;
        ret.endDate = endDate;
        ret.filedUpTo = company.GST_Filed_Up_To__c;
        ret.isFiled = GstFilingLock.isLocked(company.GST_Filed_Up_To__c, endDate);
        ret.issues = new List<Issue>();
        ret.b2b = new List<InvoiceRow>();
        ret.b2cl = new List<InvoiceRow>();
        ret.b2cs = new List<SummaryRow>();
        ret.nil = new List<NilRow>();
        ret.hsnB2b = new List<HsnRow>();
        ret.hsnB2c = new List<HsnRow>();
        ret.documents = new List<DocumentRow>();

        List<Bill__c> bills = [
            SELECT Invoice_Number__c, Invoice_Sequence__c, Financial_Year__c, Bill_Date__c, Is_Latest_Version__c,
                   Is_Cancelled__c, Recipient_GSTIN__c, Place_Of_Supply__c, Total_Amount__c,
                   Customer__r.Name, Bill_To_Party__r.Name, Bill_To_Party__c, Paired_Bill__c,
                   (SELECT Description__c, HSN_SAC_Code__c, Unit__c, Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c, Discount__c
                    FROM Bill_Line_Items__r ORDER BY CreatedDate, Id)
            FROM Bill__c
            WHERE Bill_Date__c >= :startDate AND Bill_Date__c <= :endDate
              AND (Workshop_Profile__c = :profileId OR Workshop_Profile__c = :orNoCompany)
            ORDER BY Bill_Date__c, Invoice_Number__c
        ];
        ret.billCount = 0;
        ret.invoiceValue = 0;
        for (Bill__c bill : bills) {
            if (isLive(bill)) {
                ret.billCount++;
                ret.invoiceValue += bill.Total_Amount__c == null ? 0 : bill.Total_Amount__c;
            }
        }

        if (ret.registrationType == 'Unregistered') {
            return finish(ret);
        }
        if (ret.registrationType == 'Composition') {
            // Composition: a bill of supply has no GST to report, only the turnover for CMP-08.
            ret.compositionTurnover = ret.invoiceValue;
            return finish(ret);
        }

        String companyState = GstRules.stateCode(company.State__c);
        if (companyState == null && GstRules.isValidGstin(company.GSTIN__c)) {
            companyState = company.GSTIN__c.left(2);
        }
        ret.companyStateCode = companyState;
        if (!GstRules.isValidGstin(company.GSTIN__c)) {
            addIssue(ret, 'error', 'The company\'s GSTIN "' + (company.GSTIN__c == null ? '' : company.GSTIN__c)
                + '" is not valid. Correct it on the Workshop Profile: every return is filed under it.', null, null);
        }
        if (companyState == null) {
            addIssue(ret, 'error', 'The company has no state. Pick it on the Workshop Profile: it decides which sales are inter-state.', null, null);
        }

        ret.documents = documentsIssued(bills, profileId, orNoCompany, startDate, endDate, ret);
        addSales(ret, bills, companyState);
        return finish(ret);
    }

    private static Boolean isLive(Bill__c bill) {
        return bill.Is_Latest_Version__c == true && bill.Is_Cancelled__c != true;
    }

    private static void addSales(GstReturn ret, List<Bill__c> bills, String companyState) {
        Map<String, Amounts> b2cs = new Map<String, Amounts>();
        Map<String, Amounts> hsn = new Map<String, Amounts>();
        Map<String, Amounts> unregisteredInterState = new Map<String, Amounts>();
        Map<String, Decimal> nil = new Map<String, Decimal>{
            NIL_INTER_REGISTERED => 0, NIL_INTRA_REGISTERED => 0, NIL_INTER_UNREGISTERED => 0, NIL_INTRA_UNREGISTERED => 0
        };
        Amounts taxed = new Amounts();
        List<String> noGstBills = new List<String>();
        Decimal noGstValue = 0;

        for (Bill__c bill : bills) {
            if (!isLive(bill)) {
                continue;
            }
            String placeOfSupply = bill.Place_Of_Supply__c != null ? bill.Place_Of_Supply__c : companyState;
            Boolean interState = placeOfSupply != null && companyState != null && placeOfSupply != companyState;
            String gstin = GstRules.normalizeGstin(bill.Recipient_GSTIN__c);
            Boolean registered = GstRules.isValidGstin(gstin);
            Decimal invoiceValue = bill.Total_Amount__c == null ? 0 : bill.Total_Amount__c;
            Boolean largeB2c = !registered && interState && invoiceValue > B2CL_LIMIT;

            checkBill(ret, bill, gstin, registered, placeOfSupply, companyState, interState);

            Map<String, Amounts> byRate = new Map<String, Amounts>();
            Map<String, Decimal> rates = new Map<String, Decimal>();
            Decimal billNil = 0;
            Boolean anyTaxed = false;
            ItemProblems problems = new ItemProblems();
            for (Bill_Line_Item__c line : bill.Bill_Line_Items__r) {
                Decimal rate = line.Tax_Rate_Percent__c == null ? 0 : line.Tax_Rate_Percent__c;
                GstCalculatorService.GstLineResult result = GstCalculatorService.calculateLine(GstCalculatorService.inputFor(line));
                String rateKey = GstRules.rateText(rate);
                if (rate == 0) {
                    billNil += result.subtotal;
                } else {
                    anyTaxed = true;
                    amountsFor(byRate, rateKey).add(result);
                    rates.put(rateKey, rate);
                    taxed.add(result);
                    if (!registered && interState) {
                        Amounts stateSum = amountsFor(unregisteredInterState, placeOfSupply);
                        stateSum.taxable += result.subtotal;
                        stateSum.igst += result.igst;
                    }
                    if (!registered && !largeB2c) {
                        amountsFor(b2cs, placeOfSupply + '|' + rateKey).add(result);
                    }
                }
                // The customer's half of an insurance claim: the goods' quantity is on the insurer's bill.
                Boolean countQuantity = !(bill.Paired_Bill__c != null && bill.Bill_To_Party__c == null);
                addHsn(hsn, line, result, rate, registered, problems, countQuantity);
            }
            problems.report(ret, bill);

            if (billNil != 0) {
                String kind = registered
                    ? (interState ? NIL_INTER_REGISTERED : NIL_INTRA_REGISTERED)
                    : (interState ? NIL_INTER_UNREGISTERED : NIL_INTRA_UNREGISTERED);
                nil.put(kind, nil.get(kind) + billNil);
            }
            if (!anyTaxed && !bill.Bill_Line_Items__r.isEmpty()) {
                noGstBills.add(bill.Invoice_Number__c);
                noGstValue += invoiceValue;
            }
            for (String rateKey : byRate.keySet()) {
                if (registered) {
                    ret.b2b.add(invoiceRow(bill, gstin, placeOfSupply, rates.get(rateKey), byRate.get(rateKey)));
                } else if (largeB2c) {
                    ret.b2cl.add(invoiceRow(bill, null, placeOfSupply, rates.get(rateKey), byRate.get(rateKey)));
                }
            }
        }

        if (!noGstBills.isEmpty()) {
            addIssue(ret, 'warning', noGstBills.size() + ' bill(s) worth Rs. ' + money(noGstValue) + ' have no GST ('
                + listed(noGstBills) + '). They are reported as nil rated. If these were taxable sales, GST should have '
                + 'been charged: check them with your CA.', null, null);
        }

        for (String key : sortedKeys(b2cs.keySet())) {
            Amounts sum = b2cs.get(key);
            SummaryRow row = summaryRow(key.substringBefore('|'), sum);
            row.rate = Decimal.valueOf(key.substringAfter('|'));
            ret.b2cs.add(row);
        }
        for (String kind : new List<String>{ NIL_INTER_REGISTERED, NIL_INTRA_REGISTERED, NIL_INTER_UNREGISTERED, NIL_INTRA_UNREGISTERED }) {
            NilRow row = new NilRow();
            row.description = kind;
            row.nilRated = GstCalculatorService.round2(nil.get(kind));
            ret.nil.add(row);
        }
        for (String key : sortedKeys(hsn.keySet())) {
            List<String> parts = key.split('\\|', -1);
            Amounts sum = hsn.get(key);
            HsnRow row = new HsnRow();
            row.hsn = parts[1];
            row.uqc = parts[2];
            row.rate = Decimal.valueOf(parts[3]);
            row.description = sum.description;
            row.quantity = sum.quantity;
            row.taxableValue = GstCalculatorService.round2(sum.taxable);
            row.igst = GstCalculatorService.round2(sum.igst);
            row.cgst = GstCalculatorService.round2(sum.cgst);
            row.sgst = GstCalculatorService.round2(sum.sgst);
            row.totalValue = GstCalculatorService.round2(sum.taxable + sum.igst + sum.cgst + sum.sgst);
            (parts[0] == 'B2B' ? ret.hsnB2b : ret.hsnB2c).add(row);
        }

        Gstr3b summary = new Gstr3b();
        summary.taxableValue = GstCalculatorService.round2(taxed.taxable);
        summary.igst = GstCalculatorService.round2(taxed.igst);
        summary.cgst = GstCalculatorService.round2(taxed.cgst);
        summary.sgst = GstCalculatorService.round2(taxed.sgst);
        Decimal nilTotal = 0;
        for (Decimal value : nil.values()) {
            nilTotal += value;
        }
        summary.nilRated = GstCalculatorService.round2(nilTotal);
        summary.unregisteredInterState = new List<SummaryRow>();
        for (String placeOfSupply : sortedKeys(unregisteredInterState.keySet())) {
            summary.unregisteredInterState.add(summaryRow(placeOfSupply, unregisteredInterState.get(placeOfSupply)));
        }
        ret.gstr3b = summary;
    }

    // A bill's item problems, said once per bill, naming every item, so a bill
    // with several items missing an HSN is one line in the checkup, not several.
    private class ItemProblems {
        List<String> noHsn = new List<String>();
        List<String> shortHsn = new List<String>();
        List<String> unknownUnit = new List<String>();

        void report(GstReturn ret, Bill__c bill) {
            if (!noHsn.isEmpty()) {
                GstReturnService.addIssue(ret, 'error', 'No HSN/SAC on ' + String.join(noHsn, ', ')
                    + '. Every item needs one for the HSN summary: add it to the part and change the bill.', bill.Id, bill.Invoice_Number__c);
            }
            if (!shortHsn.isEmpty()) {
                GstReturnService.addIssue(ret, 'warning', 'HSN/SAC should be at least 4 digits: ' + String.join(shortHsn, ', ') + '.', bill.Id, bill.Invoice_Number__c);
            }
            if (!unknownUnit.isEmpty()) {
                GstReturnService.addIssue(ret, 'warning', 'Not a GST unit, so reported as OTH-OTHERS: ' + String.join(unknownUnit, ', ')
                    + '. Pick a GST unit on the part.', bill.Id, bill.Invoice_Number__c);
            }
        }
    }

    private static void addProblem(List<String> items, String text) {
        if (!items.contains(text)) {
            items.add(text);
        }
    }

    private static void addHsn(Map<String, Amounts> hsn, Bill_Line_Item__c line, GstCalculatorService.GstLineResult result,
                               Decimal rate, Boolean registered, ItemProblems problems, Boolean countQuantity) {
        String code = line.HSN_SAC_Code__c == null ? '' : line.HSN_SAC_Code__c.deleteWhitespace();
        Boolean service = GstRules.isServiceCode(code);
        String uqc = GstRules.uqcFor(line.Unit__c);
        if (code == '') {
            addProblem(problems.noHsn, '"' + line.Description__c + '"');
        } else if (!code.isNumeric() || code.length() < 4) {
            addProblem(problems.shortHsn, '"' + code + '" on "' + line.Description__c + '"');
        }
        // A service has no unit; an item with none is counted in numbers.
        String uqcLabel;
        if (service) {
            uqcLabel = 'NA';
        } else if (uqc != null) {
            uqcLabel = GstRules.uqcLabel(uqc);
        } else if (String.isBlank(line.Unit__c)) {
            uqcLabel = GstRules.uqcLabel('NOS');
        } else {
            uqcLabel = GstRules.uqcLabel('OTH');
            addProblem(problems.unknownUnit, '"' + line.Unit__c + '" on "' + line.Description__c + '"');
        }
        String key = (registered ? 'B2B' : 'B2C') + '|' + code + '|' + uqcLabel + '|' + GstRules.rateText(rate);
        Amounts sum = amountsFor(hsn, key);
        sum.add(result);
        if (!service && countQuantity) {
            sum.quantity += line.Quantity__c == null ? 0 : line.Quantity__c;
        }
        if (sum.description == null) {
            sum.description = line.Description__c;
        }
    }

    // The checks that need a whole bill: buyer's GSTIN, place of supply, tax type, number series.
    private static void checkBill(GstReturn ret, Bill__c bill, String gstin, Boolean registered,
                                  String placeOfSupply, String companyState, Boolean interState) {
        if (gstin != null && !registered) {
            addIssue(ret, 'error', 'The buyer\'s GSTIN "' + gstin + '" is not valid, so this bill is shown as a sale to an unregistered buyer. Correct the customer or party, then change the bill.', bill.Id, bill.Invoice_Number__c);
        }
        if (bill.Place_Of_Supply__c == null) {
            addIssue(ret, 'warning', 'No place of supply was recorded; the company\'s own state is used.', bill.Id, bill.Invoice_Number__c);
        }
        if (companyState != null && placeOfSupply != null) {
            Boolean hasIgst = false;
            Boolean hasCgstSgst = false;
            for (Bill_Line_Item__c line : bill.Bill_Line_Items__r) {
                if (line.Tax_Rate_Percent__c != null && line.Tax_Rate_Percent__c > 0) {
                    if (line.Gst_Type__c == 'IGST') {
                        hasIgst = true;
                    } else {
                        hasCgstSgst = true;
                    }
                }
            }
            String stateLabel = placeLabel(placeOfSupply);
            if (interState && hasCgstSgst) {
                addIssue(ret, 'error', 'Charged CGST+SGST, but the place of supply is another state (' + stateLabel + '): it should be IGST.', bill.Id, bill.Invoice_Number__c);
            } else if (!interState && hasIgst) {
                addIssue(ret, 'error', 'Charged IGST on a sale within the state (' + stateLabel + '): it should be CGST+SGST.', bill.Id, bill.Invoice_Number__c);
            }
        }
        if (bill.Financial_Year__c != null && bill.Financial_Year__c != InvoiceNumberingService.financialYearFor(bill.Bill_Date__c)) {
            addIssue(ret, 'warning', 'Dated ' + GstFilingLock.formatDate(bill.Bill_Date__c) + ' but numbered in the ' + bill.Financial_Year__c
                + ' series (it was made before old-date bills got their own year\'s numbers).', bill.Id, bill.Invoice_Number__c);
        }
    }

    /**
     * Table 13. Within each number series, the numbers dated in the period
     * make unbroken runs; a number dated outside the period (an old-date bill)
     * breaks a run. A number with no bill at all left is counted as cancelled
     * and warned about. Replaced versions and deleted bills are cancelled.
     */
    private static List<DocumentRow> documentsIssued(List<Bill__c> bills, Id profileId, Id orNoCompany,
                                                     Date startDate, Date endDate, GstReturn ret) {
        Map<String, Map<Integer, Bill__c>> bySeries = new Map<String, Map<Integer, Bill__c>>();
        List<DocumentRow> rows = new List<DocumentRow>();
        Set<String> years = new Set<String>();
        for (Bill__c bill : bills) {
            Integer sequence = sequenceOf(bill);
            if (sequence == null) {
                // A number that doesn't follow the series pattern stands alone.
                rows.add(documentRow(bill.Invoice_Number__c, bill.Invoice_Number__c, 1, isLive(bill) ? 0 : 1));
                continue;
            }
            String series = bill.Invoice_Number__c.substringBeforeLast('/');
            if (!bySeries.containsKey(series)) {
                bySeries.put(series, new Map<Integer, Bill__c>());
            }
            bySeries.get(series).put(sequence, bill);
            years.add(bill.Financial_Year__c);
        }
        if (bySeries.isEmpty()) {
            return rows;
        }

        Map<String, Set<Integer>> elsewhere = new Map<String, Set<Integer>>();
        for (Bill__c other : [
            SELECT Invoice_Number__c, Invoice_Sequence__c FROM Bill__c
            WHERE Financial_Year__c IN :years
              AND (Workshop_Profile__c = :profileId OR Workshop_Profile__c = :orNoCompany)
              AND (Bill_Date__c < :startDate OR Bill_Date__c > :endDate)
        ]) {
            Integer sequence = sequenceOf(other);
            String series = other.Invoice_Number__c.substringBeforeLast('/');
            if (sequence != null && bySeries.containsKey(series)) {
                if (!elsewhere.containsKey(series)) {
                    elsewhere.put(series, new Set<Integer>());
                }
                elsewhere.get(series).add(sequence);
            }
        }

        List<String> missing = new List<String>();
        for (String series : sortedKeys(bySeries.keySet())) {
            Map<Integer, Bill__c> numbers = bySeries.get(series);
            List<Integer> sorted = new List<Integer>(numbers.keySet());
            sorted.sort();
            Set<Integer> outside = elsewhere.containsKey(series) ? elsewhere.get(series) : new Set<Integer>();
            Integer runStart;
            Integer runEnd;
            Integer runLive = 0;
            for (Integer n = sorted[0]; n <= sorted[sorted.size() - 1]; n++) {
                if (outside.contains(n)) {
                    if (runStart != null) {
                        rows.add(documentRow(numberIn(series, runStart), numberIn(series, runEnd), runEnd - runStart + 1, runEnd - runStart + 1 - runLive));
                        runStart = null;
                        runLive = 0;
                    }
                    continue;
                }
                if (!numbers.containsKey(n)) {
                    missing.add(numberIn(series, n));
                } else if (isLive(numbers.get(n))) {
                    runLive++;
                }
                if (runStart == null) {
                    runStart = n;
                }
                runEnd = n;
            }
            if (runStart != null) {
                rows.add(documentRow(numberIn(series, runStart), numberIn(series, runEnd), runEnd - runStart + 1, runEnd - runStart + 1 - runLive));
            }
        }
        if (!missing.isEmpty()) {
            addIssue(ret, 'warning', missing.size() + ' invoice number(s) have no bill left (' + listed(missing)
                + '). They are counted as cancelled in Documents issued.', null, null);
        }
        return rows;
    }

    // ---- small helpers --------------------------------------------------------

    private static Integer sequenceOf(Bill__c bill) {
        if (bill.Invoice_Sequence__c != null) {
            return bill.Invoice_Sequence__c.intValue();
        }
        return InvoiceNumberingService.sequenceOf(bill.Invoice_Number__c);
    }

    // As InvoiceNumberingService writes them: four digits at least.
    private static String numberIn(String series, Integer sequence) {
        return series + '/' + String.valueOf(sequence).leftPad(4, '0');
    }

    private static DocumentRow documentRow(String fromNumber, String toNumber, Integer total, Integer cancelled) {
        DocumentRow row = new DocumentRow();
        row.nature = DOCUMENT_NATURE;
        row.fromNumber = fromNumber;
        row.toNumber = toNumber;
        row.totalNumber = total;
        row.cancelled = cancelled;
        row.netIssued = total - cancelled;
        return row;
    }

    private static InvoiceRow invoiceRow(Bill__c bill, String gstin, String placeOfSupply, Decimal rate, Amounts sum) {
        InvoiceRow row = new InvoiceRow();
        row.billId = bill.Id;
        row.gstin = gstin;
        row.receiverName = bill.Bill_To_Party__r != null ? bill.Bill_To_Party__r.Name : (bill.Customer__r != null ? bill.Customer__r.Name : null);
        row.invoiceNumber = bill.Invoice_Number__c;
        row.invoiceDate = bill.Bill_Date__c;
        row.invoiceValue = bill.Total_Amount__c;
        row.placeOfSupply = placeLabel(placeOfSupply);
        row.rate = rate;
        row.taxableValue = GstCalculatorService.round2(sum.taxable);
        row.igst = GstCalculatorService.round2(sum.igst);
        row.cgst = GstCalculatorService.round2(sum.cgst);
        row.sgst = GstCalculatorService.round2(sum.sgst);
        return row;
    }

    private static SummaryRow summaryRow(String placeOfSupply, Amounts sum) {
        SummaryRow row = new SummaryRow();
        row.placeOfSupply = placeLabel(placeOfSupply);
        row.taxableValue = GstCalculatorService.round2(sum.taxable);
        row.igst = GstCalculatorService.round2(sum.igst);
        row.cgst = GstCalculatorService.round2(sum.cgst);
        row.sgst = GstCalculatorService.round2(sum.sgst);
        return row;
    }

    /** "23-Madhya Pradesh", as GSTR-1 writes a place of supply. */
    public static String placeLabel(String code) {
        String name = GstRules.stateNameForCode(code);
        return name == null ? code : code + '-' + name;
    }

    private static Amounts amountsFor(Map<String, Amounts> sums, String key) {
        if (!sums.containsKey(key)) {
            sums.put(key, new Amounts());
        }
        return sums.get(key);
    }

    private static List<String> sortedKeys(Set<String> keys) {
        List<String> sorted = new List<String>(keys);
        sorted.sort();
        return sorted;
    }

    // The first few, so a long list stays readable.
    private static String listed(List<String> items) {
        Integer shown = Math.min(items.size(), 10);
        List<String> first = new List<String>();
        for (Integer i = 0; i < shown; i++) {
            first.add(items[i]);
        }
        return String.join(first, ', ') + (items.size() > shown ? ' and ' + (items.size() - shown) + ' more' : '');
    }

    private static String money(Decimal value) {
        return String.valueOf(GstCalculatorService.round2(value));
    }

    private static void addIssue(GstReturn ret, String severity, String message, Id billId, String documentNumber) {
        // One bill can trip the same check on several lines: say it once.
        for (Issue existing : ret.issues) {
            if (existing.billId == billId && existing.message == message) {
                return;
            }
        }
        Issue issue = new Issue();
        issue.severity = severity;
        issue.message = message;
        issue.billId = billId;
        issue.documentNumber = documentNumber;
        ret.issues.add(issue);
    }

    private static GstReturn finish(GstReturn ret) {
        ret.errorCount = 0;
        ret.warningCount = 0;
        List<Issue> errors = new List<Issue>();
        List<Issue> warnings = new List<Issue>();
        for (Issue issue : ret.issues) {
            if (issue.severity == 'error') {
                errors.add(issue);
            } else {
                warnings.add(issue);
            }
        }
        ret.errorCount = errors.size();
        ret.warningCount = warnings.size();
        ret.issues = errors;
        ret.issues.addAll(warnings);
        return ret;
    }
}
