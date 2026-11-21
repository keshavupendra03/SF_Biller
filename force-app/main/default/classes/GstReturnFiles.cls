/**
 * The GST return as files for the CA (architecture.md §D.1, G3): one CSV per
 * GSTR-1 section, in the layouts of the GSTR-1 offline tool's CSV import,
 * and a readable summary with GSTR-3B's figures and the checkup, all in one
 * zip. The layouts follow the offline tool's templates as known on
 * 2026-11-21; check one month against the current tool before relying on them.
 */
public with sharing class GstReturnFiles {

    public static final String B2B = 'b2b.csv';
    public static final String B2CL = 'b2cl.csv';
    public static final String B2CS = 'b2cs.csv';
    public static final String NIL = 'exemp.csv';
    public static final String HSN_B2B = 'hsn(b2b).csv';
    public static final String HSN_B2C = 'hsn(b2c).csv';
    public static final String DOCS = 'docs.csv';
    public static final String SUMMARY = 'summary.csv';

    private static final String HSN_HEADER = 'HSN,Description,UQC,Total Quantity,Total Value,Rate,Taxable Value,'
        + 'Integrated Tax Amount,Central Tax Amount,State/UT Tax Amount,Cess Amount';

    /** File name to contents. A composition or unregistered company gets only the summary. */
    public static Map<String, String> csvFiles(GstReturnService.GstReturn ret) {
        Map<String, String> files = new Map<String, String>();
        files.put(SUMMARY, summary(ret));
        if (ret.registrationType != 'Regular') {
            return files;
        }

        List<String> lines = new List<String>{
            'GSTIN/UIN of Recipient,Receiver Name,Invoice Number,Invoice date,Invoice Value,Place Of Supply,Reverse Charge,'
            + 'Applicable % of Tax Rate,Invoice Type,E-Commerce GSTIN,Rate,Taxable Value,Cess Amount'
        };
        for (GstReturnService.InvoiceRow row : ret.b2b) {
            lines.add(join(new List<String>{
                row.gstin, row.receiverName, row.invoiceNumber, gstDate(row.invoiceDate), amount(row.invoiceValue),
                row.placeOfSupply, 'N', '', 'Regular B2B', '', GstRules.rateText(row.rate), amount(row.taxableValue), '0.00'
            }));
        }
        files.put(B2B, String.join(lines, '\n') + '\n');

        lines = new List<String>{ 'Invoice Number,Invoice date,Invoice Value,Place Of Supply,Applicable % of Tax Rate,Rate,Taxable Value,Cess Amount,E-Commerce GSTIN' };
        for (GstReturnService.InvoiceRow row : ret.b2cl) {
            lines.add(join(new List<String>{
                row.invoiceNumber, gstDate(row.invoiceDate), amount(row.invoiceValue), row.placeOfSupply, '',
                GstRules.rateText(row.rate), amount(row.taxableValue), '0.00', ''
            }));
        }
        files.put(B2CL, String.join(lines, '\n') + '\n');

        lines = new List<String>{ 'Type,Place Of Supply,Applicable % of Tax Rate,Rate,Taxable Value,Cess Amount,E-Commerce GSTIN' };
        for (GstReturnService.SummaryRow row : ret.b2cs) {
            lines.add(join(new List<String>{ 'OE', row.placeOfSupply, '', GstRules.rateText(row.rate), amount(row.taxableValue), '0.00', '' }));
        }
        files.put(B2CS, String.join(lines, '\n') + '\n');

        lines = new List<String>{ 'Description,Nil Rated Supplies,Exempted(other than nil rated/non GST supply),Non-GST Supplies' };
        for (GstReturnService.NilRow row : ret.nil) {
            lines.add(join(new List<String>{ row.description, amount(row.nilRated), '0.00', '0.00' }));
        }
        files.put(NIL, String.join(lines, '\n') + '\n');

        files.put(HSN_B2B, hsn(ret.hsnB2b));
        files.put(HSN_B2C, hsn(ret.hsnB2c));

        lines = new List<String>{ 'Nature of Document,Sr. No. From,Sr. No. To,Total Number,Cancelled' };
        for (GstReturnService.DocumentRow row : ret.documents) {
            lines.add(join(new List<String>{ row.nature, row.fromNumber, row.toNumber, String.valueOf(row.totalNumber), String.valueOf(row.cancelled) }));
        }
        files.put(DOCS, String.join(lines, '\n') + '\n');
        return files;
    }

    // ---- GSTR-1 JSON for "Prepare offline > Upload" on the GST portal -----------
    // The portal's offline-upload schema as known on 2026-11-21 (G5). The portal
    // checks every upload and rejects a bad file whole, with an error report;
    // upload one month and check it before relying on it.

    public static final String JSON_VERSION = 'GST3.2.2';

    /** The GSTR-1 return file: "GSTR1_102026.json" for October 2026 (a quarter: its last month). */
    public static String jsonFileName(GstReturnService.GstReturn ret) {
        return 'GSTR1_' + returnPeriod(ret) + '.json';
    }

    private static String returnPeriod(GstReturnService.GstReturn ret) {
        return String.valueOf(ret.endDate.month()).leftPad(2, '0') + ret.endDate.year();
    }

    public static String portalJson(GstReturnService.GstReturn ret) {
        JSONGenerator g = JSON.createGenerator(true);
        g.writeStartObject();
        g.writeStringField('gstin', ret.gstin == null ? '' : ret.gstin);
        g.writeStringField('fp', returnPeriod(ret));
        g.writeStringField('version', JSON_VERSION);
        g.writeStringField('hash', 'hash');

        if (!ret.b2b.isEmpty()) {
            // By buyer, then invoice, then rate.
            Map<String, Map<String, List<GstReturnService.InvoiceRow>>> byBuyer = new Map<String, Map<String, List<GstReturnService.InvoiceRow>>>();
            for (GstReturnService.InvoiceRow row : ret.b2b) {
                if (!byBuyer.containsKey(row.gstin)) {
                    byBuyer.put(row.gstin, new Map<String, List<GstReturnService.InvoiceRow>>());
                }
                Map<String, List<GstReturnService.InvoiceRow>> invoices = byBuyer.get(row.gstin);
                if (!invoices.containsKey(row.invoiceNumber)) {
                    invoices.put(row.invoiceNumber, new List<GstReturnService.InvoiceRow>());
                }
                invoices.get(row.invoiceNumber).add(row);
            }
            g.writeFieldName('b2b');
            g.writeStartArray();
            for (String buyer : byBuyer.keySet()) {
                g.writeStartObject();
                g.writeStringField('ctin', buyer);
                g.writeFieldName('inv');
                g.writeStartArray();
                for (List<GstReturnService.InvoiceRow> rows : byBuyer.get(buyer).values()) {
                    writeInvoice(g, ret, rows, true);
                }
                g.writeEndArray();
                g.writeEndObject();
            }
            g.writeEndArray();
        }

        if (!ret.b2cl.isEmpty()) {
            Map<String, Map<String, List<GstReturnService.InvoiceRow>>> byPlace = new Map<String, Map<String, List<GstReturnService.InvoiceRow>>>();
            for (GstReturnService.InvoiceRow row : ret.b2cl) {
                String pos = row.placeOfSupply.left(2);
                if (!byPlace.containsKey(pos)) {
                    byPlace.put(pos, new Map<String, List<GstReturnService.InvoiceRow>>());
                }
                Map<String, List<GstReturnService.InvoiceRow>> invoices = byPlace.get(pos);
                if (!invoices.containsKey(row.invoiceNumber)) {
                    invoices.put(row.invoiceNumber, new List<GstReturnService.InvoiceRow>());
                }
                invoices.get(row.invoiceNumber).add(row);
            }
            g.writeFieldName('b2cl');
            g.writeStartArray();
            for (String pos : byPlace.keySet()) {
                g.writeStartObject();
                g.writeStringField('pos', pos);
                g.writeFieldName('inv');
                g.writeStartArray();
                for (List<GstReturnService.InvoiceRow> rows : byPlace.get(pos).values()) {
                    writeInvoice(g, ret, rows, false);
                }
                g.writeEndArray();
                g.writeEndObject();
            }
            g.writeEndArray();
        }

        if (!ret.b2cs.isEmpty()) {
            g.writeFieldName('b2cs');
            g.writeStartArray();
            for (GstReturnService.SummaryRow row : ret.b2cs) {
                String pos = row.placeOfSupply.left(2);
                Boolean inter = isInterState(ret, pos);
                g.writeStartObject();
                g.writeStringField('sply_ty', inter ? 'INTER' : 'INTRA');
                g.writeNumberField('rt', row.rate);
                g.writeStringField('typ', 'OE');
                g.writeStringField('pos', pos);
                g.writeNumberField('txval', row.taxableValue);
                writeTax(g, inter, row.igst, row.cgst, row.sgst);
                g.writeEndObject();
            }
            g.writeEndArray();
        }

        Map<String, String> nilTypes = new Map<String, String>{
            GstReturnService.NIL_INTER_REGISTERED => 'INTRB2B',
            GstReturnService.NIL_INTRA_REGISTERED => 'INTRAB2B',
            GstReturnService.NIL_INTER_UNREGISTERED => 'INTRB2C',
            GstReturnService.NIL_INTRA_UNREGISTERED => 'INTRAB2C'
        };
        g.writeFieldName('nil');
        g.writeStartObject();
        g.writeFieldName('inv');
        g.writeStartArray();
        for (GstReturnService.NilRow row : ret.nil) {
            g.writeStartObject();
            g.writeStringField('sply_ty', nilTypes.get(row.description));
            g.writeNumberField('expt_amt', 0);
            g.writeNumberField('nil_amt', row.nilRated);
            g.writeNumberField('ngsup_amt', 0);
            g.writeEndObject();
        }
        g.writeEndArray();
        g.writeEndObject();

        g.writeFieldName('hsn');
        g.writeStartObject();
        writeHsn(g, 'hsn_b2b', ret.hsnB2b);
        writeHsn(g, 'hsn_b2c', ret.hsnB2c);
        g.writeEndObject();

        if (!ret.documents.isEmpty()) {
            g.writeFieldName('doc_issue');
            g.writeStartObject();
            g.writeFieldName('doc_det');
            g.writeStartArray();
            g.writeStartObject();
            g.writeNumberField('doc_num', 1);
            g.writeStringField('doc_typ', GstReturnService.DOCUMENT_NATURE);
            g.writeFieldName('docs');
            g.writeStartArray();
            Integer num = 1;
            for (GstReturnService.DocumentRow row : ret.documents) {
                g.writeStartObject();
                g.writeNumberField('num', num++);
                g.writeStringField('from', row.fromNumber);
                g.writeStringField('to', row.toNumber);
                g.writeNumberField('totnum', row.totalNumber);
                g.writeNumberField('cancel', row.cancelled);
                g.writeNumberField('net_issue', row.netIssued);
                g.writeEndObject();
            }
            g.writeEndArray();
            g.writeEndObject();
            g.writeEndArray();
            g.writeEndObject();
        }
        g.writeEndObject();
        return g.getAsString();
    }

    // One invoice with its rates as items. B2B invoices carry the extra B2B fields.
    private static void writeInvoice(JSONGenerator g, GstReturnService.GstReturn ret, List<GstReturnService.InvoiceRow> rows, Boolean b2b) {
        GstReturnService.InvoiceRow first = rows[0];
        String pos = first.placeOfSupply.left(2);
        Boolean inter = isInterState(ret, pos);
        g.writeStartObject();
        g.writeStringField('inum', first.invoiceNumber);
        g.writeStringField('idt', jsonDate(first.invoiceDate));
        g.writeNumberField('val', first.invoiceValue);
        if (b2b) {
            g.writeStringField('pos', pos);
            g.writeStringField('rchrg', 'N');
            g.writeStringField('inv_typ', 'R');
        }
        g.writeFieldName('itms');
        g.writeStartArray();
        Integer num = 1;
        for (GstReturnService.InvoiceRow row : rows) {
            g.writeStartObject();
            g.writeNumberField('num', num++);
            g.writeFieldName('itm_det');
            g.writeStartObject();
            g.writeNumberField('txval', row.taxableValue);
            g.writeNumberField('rt', row.rate);
            writeTax(g, inter, row.igst, row.cgst, row.sgst);
            g.writeEndObject();
            g.writeEndObject();
        }
        g.writeEndArray();
        g.writeEndObject();
    }

    private static void writeHsn(JSONGenerator g, String field, List<GstReturnService.HsnRow> rows) {
        g.writeFieldName(field);
        g.writeStartArray();
        Integer num = 1;
        for (GstReturnService.HsnRow row : rows) {
            g.writeStartObject();
            g.writeNumberField('num', num++);
            g.writeStringField('hsn_sc', row.hsn);
            g.writeStringField('desc', row.description == null ? '' : row.description.left(30));
            // "NOS-NUMBERS" in the offline tool's lists is "NOS" here.
            g.writeStringField('uqc', row.uqc.substringBefore('-'));
            g.writeNumberField('qty', row.quantity);
            g.writeNumberField('rt', row.rate);
            g.writeNumberField('txval', row.taxableValue);
            g.writeNumberField('iamt', row.igst);
            g.writeNumberField('camt', row.cgst);
            g.writeNumberField('samt', row.sgst);
            g.writeNumberField('csamt', 0);
            g.writeEndObject();
        }
        g.writeEndArray();
    }

    // Inter-state: integrated tax; within the state: central and state tax.
    private static void writeTax(JSONGenerator g, Boolean inter, Decimal igst, Decimal cgst, Decimal sgst) {
        if (inter) {
            g.writeNumberField('iamt', igst);
        } else {
            g.writeNumberField('camt', cgst);
            g.writeNumberField('samt', sgst);
        }
        g.writeNumberField('csamt', 0);
    }

    private static Boolean isInterState(GstReturnService.GstReturn ret, String pos) {
        return ret.companyStateCode != null && pos != ret.companyStateCode;
    }

    /** "05-10-2026", the date form in the portal's JSON. */
    private static String jsonDate(Date day) {
        return String.valueOf(day.day()).leftPad(2, '0') + '-' + String.valueOf(day.month()).leftPad(2, '0') + '-' + day.year();
    }

    public static Blob zip(GstReturnService.GstReturn ret) {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        Map<String, String> files = csvFiles(ret);
        if (String.isBlank(ret.registrationType) || ret.registrationType == 'Regular') {
            files.put(jsonFileName(ret), portalJson(ret));
        }
        List<String> names = new List<String>(files.keySet());
        names.sort();
        for (String name : names) {
            writer.addEntry(name, Blob.valueOf(files.get(name)));
        }
        return writer.getArchive();
    }

    /** "GST_23AAACI7904G1ZV_2026-10.zip", or "..._2026-07_to_2026-09.zip" for a quarter. */
    public static String fileName(GstReturnService.GstReturn ret) {
        String who = GstRules.isValidGstin(ret.gstin) ? ret.gstin : ret.companyName.replaceAll('[^A-Za-z0-9]+', '_');
        String period = monthOf(ret.startDate);
        if (monthOf(ret.endDate) != period) {
            period += '_to_' + monthOf(ret.endDate);
        }
        return 'GST_' + who + '_' + period + '.zip';
    }

    private static String summary(GstReturnService.GstReturn ret) {
        List<String> lines = new List<String>{ 'Item,Value' };
        lines.add(join(new List<String>{ 'Company', ret.companyName }));
        lines.add(join(new List<String>{ 'GSTIN', ret.gstin }));
        lines.add(join(new List<String>{ 'Registration', ret.registrationType }));
        lines.add(join(new List<String>{ 'Period', gstDate(ret.startDate) + ' to ' + gstDate(ret.endDate) }));
        lines.add(join(new List<String>{ 'Bills', String.valueOf(ret.billCount) }));
        lines.add(join(new List<String>{ 'Total invoice value', amount(ret.invoiceValue) }));
        if (ret.compositionTurnover != null) {
            lines.add(join(new List<String>{ 'Turnover for CMP-08', amount(ret.compositionTurnover) }));
        }
        if (ret.gstr3b != null) {
            GstReturnService.Gstr3b g = ret.gstr3b;
            lines.add(join(new List<String>{ 'GSTR-3B 3.1(a) Taxable value', amount(g.taxableValue) }));
            lines.add(join(new List<String>{ 'GSTR-3B 3.1(a) Integrated tax', amount(g.igst) }));
            lines.add(join(new List<String>{ 'GSTR-3B 3.1(a) Central tax', amount(g.cgst) }));
            lines.add(join(new List<String>{ 'GSTR-3B 3.1(a) State/UT tax', amount(g.sgst) }));
            lines.add(join(new List<String>{ 'GSTR-3B 3.1(c) Nil rated', amount(g.nilRated) }));
            lines.add(join(new List<String>{ 'Portal upload file', jsonFileName(ret)
                + ': GST portal > Returns > GSTR-1 > Prepare offline > Upload. Check the first month you upload with your CA.' }));
            for (GstReturnService.SummaryRow row : g.unregisteredInterState) {
                lines.add(join(new List<String>{ 'GSTR-3B 3.2 Unregistered ' + row.placeOfSupply + ' taxable value', amount(row.taxableValue) }));
                lines.add(join(new List<String>{ 'GSTR-3B 3.2 Unregistered ' + row.placeOfSupply + ' integrated tax', amount(row.igst) }));
            }
        }
        for (GstReturnService.Issue issue : ret.issues) {
            lines.add(join(new List<String>{
                'Checkup ' + issue.severity + (issue.documentNumber == null ? '' : ' ' + issue.documentNumber), issue.message
            }));
        }
        return String.join(lines, '\n') + '\n';
    }

    private static String hsn(List<GstReturnService.HsnRow> rows) {
        List<String> lines = new List<String>{ HSN_HEADER };
        for (GstReturnService.HsnRow row : rows) {
            lines.add(join(new List<String>{
                row.hsn, row.description, row.uqc, GstRules.rateText(row.quantity), amount(row.totalValue), GstRules.rateText(row.rate),
                amount(row.taxableValue), amount(row.igst), amount(row.cgst), amount(row.sgst), '0.00'
            }));
        }
        return String.join(lines, '\n') + '\n';
    }

    // ---- cells ------------------------------------------------------------------

    private static String join(List<String> cells) {
        List<String> quoted = new List<String>();
        for (String cell : cells) {
            quoted.add(csv(cell));
        }
        return String.join(quoted, ',');
    }

    /** A cell, quoted when it holds a comma, quote or line break. */
    @TestVisible
    private static String csv(String value) {
        if (value == null) {
            return '';
        }
        if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
            return '"' + value.replace('"', '""') + '"';
        }
        return value;
    }

    private static String amount(Decimal value) {
        return value == null ? '0.00' : GstCalculatorService.round2(value).toPlainString();
    }

    /** "05-Oct-2026", the date form the offline tool's CSV takes. */
    @TestVisible
    private static String gstDate(Date day) {
        return day == null ? '' : Datetime.newInstance(day.year(), day.month(), day.day()).format('dd-MMM-yyyy');
    }

    private static String monthOf(Date day) {
        return day.year() + '-' + String.valueOf(day.month()).leftPad(2, '0');
    }
}
