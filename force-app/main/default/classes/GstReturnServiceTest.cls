/**
 * GST stage G3 (architecture.md §D.1). One month of sample bills, every kind
 * of sale, with the GSTR-1 and GSTR-3B figures worked out by hand:
 *
 *   B1  B2B, same state      1 x 1000 @18 CGST+SGST (8708, Pcs) and 2 x 100 @5 (2710, Ltr)
 *   B2  B2B, Maharashtra     1 x 2000 @18 IGST (8708, Pcs), to a Bill-To-Party
 *   B3  B2C Large            1 x 100000 @18 IGST (8703, Nos), unregistered, Maharashtra: 118000
 *   B4  B2C Small, inter     1 x 1000 @18 IGST (8708, Set), unregistered, Maharashtra
 *   B5  B2C Small, intra     1 x 500 @18 (998714, a service) and 1 x 300 @0 (8708, Pcs)
 *   B6  no GST               1 x 700 @0 (8708, Pcs)
 *   B7  deleted              1 x 999 @18, not counted
 *   B8  replaced by an edit  1 x 888 @18, not counted
 *   B9  B2C Small            1 x 100 @5 (2710, Ltr)
 *   B10 B2C Small            1 x 100 @18 charged IGST on a same-state sale: an error
 *   B11 B2C Small            1 x 50 @18 with no HSN: an error
 */
@isTest
private class GstReturnServiceTest {

    private static final String MP_GSTIN = '23ABCDE1234F1Z8';
    private static final String MH_GSTIN = '27AAPFU0939F1ZV';

    private static Date periodStart() {
        return Date.today().toStartOfMonth().addMonths(-2);
    }

    private static Date periodEnd() {
        return GstFilingLock.monthEnd(periodStart());
    }

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GSTIN__c = '23AAACI7904G1ZV', State__c = 'Madhya Pradesh');
    }

    private static Customer__c customer(String name, String gstin, String state) {
        Customer__c customer = new Customer__c(Name = name, Phone__c = '90000' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(5), GSTIN__c = gstin, State__c = state);
        insert customer;
        return customer;
    }

    private static Bill__c bill(Id customerId, Id partyId, Integer day, List<BillController.LineItemInput> lines) {
        Bill__c bill = new Bill__c(Customer__c = customerId, Bill_To_Party__c = partyId, Bill_Date__c = periodStart().addDays(day));
        insert bill;
        TestLines.attach(bill.Id, lines);
        return [SELECT Id, Invoice_Number__c, Total_Amount__c FROM Bill__c WHERE Id = :bill.Id];
    }

    private static BillController.LineItemInput line(String description, Decimal qty, Decimal price, Decimal rate, String type, String hsn, String unit) {
        return TestLines.line(description, qty, price, rate, type, hsn, unit);
    }

    private static Map<String, Bill__c> sampleMonth() {
        Customer__c registeredMp = customer('Sharma Traders', MP_GSTIN, null);
        Customer__c unregisteredMh = customer('Patil', null, 'Maharashtra');
        Customer__c walkIn = customer('Ramesh', null, null);
        Bill_To_Party__c fleetMh = new Bill_To_Party__c(Name = 'Mumbai Fleet', GSTIN__c = MH_GSTIN);
        insert fleetMh;

        Map<String, Bill__c> bills = new Map<String, Bill__c>();
        bills.put('B1', bill(registeredMp.Id, null, 1, new List<BillController.LineItemInput>{
            line('Brake Pad', 1, 1000, 18, 'CGST_SGST', '8708', 'Pcs'), line('Engine Oil', 2, 100, 5, 'CGST_SGST', '2710', 'Ltr') }));
        bills.put('B2', bill(walkIn.Id, fleetMh.Id, 2, new List<BillController.LineItemInput>{ line('Clutch', 1, 2000, 18, 'IGST', '8708', 'Pcs') }));
        bills.put('B3', bill(unregisteredMh.Id, null, 3, new List<BillController.LineItemInput>{ line('Engine', 1, 100000, 18, 'IGST', '8703', 'Nos') }));
        bills.put('B4', bill(unregisteredMh.Id, null, 4, new List<BillController.LineItemInput>{ line('Seat Covers', 1, 1000, 18, 'IGST', '8708', 'Set') }));
        bills.put('B5', bill(walkIn.Id, null, 5, new List<BillController.LineItemInput>{
            line('Labour', 1, 500, 18, 'CGST_SGST', '998714', null), line('Free Washer', 1, 300, 0, 'CGST_SGST', '8708', 'Pcs') }));
        bills.put('B6', bill(walkIn.Id, null, 6, new List<BillController.LineItemInput>{ line('Wiper', 1, 700, 0, 'CGST_SGST', '8708', 'Pcs') }));
        bills.put('B7', bill(walkIn.Id, null, 7, new List<BillController.LineItemInput>{ line('Horn', 1, 999, 18, 'CGST_SGST', '8512', 'Pcs') }));
        update new Bill__c(Id = bills.get('B7').Id, Is_Cancelled__c = true, Cancelled_On__c = Date.today());
        bills.put('B8', bill(walkIn.Id, null, 8, new List<BillController.LineItemInput>{ line('Mirror', 1, 888, 18, 'CGST_SGST', '7009', 'Pcs') }));
        update new Bill__c(Id = bills.get('B8').Id, Is_Latest_Version__c = false);
        bills.put('B9', bill(walkIn.Id, null, 9, new List<BillController.LineItemInput>{ line('Coolant', 1, 100, 5, 'CGST_SGST', '2710', 'Ltr') }));
        bills.put('B10', bill(walkIn.Id, null, 10, new List<BillController.LineItemInput>{ line('Bulb', 1, 100, 18, 'IGST', '8539', 'Pcs') }));
        bills.put('B11', bill(walkIn.Id, null, 11, new List<BillController.LineItemInput>{ line('Clip', 1, 50, 18, 'CGST_SGST', null, 'Pcs') }));

        // Not this return: last month, and the other company.
        bill(walkIn.Id, null, -5, new List<BillController.LineItemInput>{ line('Earlier', 1, 5000, 18, 'CGST_SGST', '8708', 'Pcs') });
        Workshop_Profile__c decor = new Workshop_Profile__c(Name = 'Speedy Decor', Invoice_Prefix__c = 'DEC', State__c = 'Madhya Pradesh');
        insert decor;
        Bill__c other = new Bill__c(Customer__c = walkIn.Id, Workshop_Profile__c = decor.Id, Bill_Date__c = periodStart().addDays(3));
        insert other;
        TestLines.attach(other.Id, line('Other company', 1, 7000, 18, 'CGST_SGST', '8708', 'Pcs'));
        return bills;
    }

    private static GstReturnService.InvoiceRow invoiceRow(List<GstReturnService.InvoiceRow> rows, String invoiceNumber, Decimal rate) {
        for (GstReturnService.InvoiceRow row : rows) {
            if (row.invoiceNumber == invoiceNumber && row.rate == rate) {
                return row;
            }
        }
        return null;
    }

    private static GstReturnService.SummaryRow summaryRow(List<GstReturnService.SummaryRow> rows, String placeOfSupply, Decimal rate) {
        for (GstReturnService.SummaryRow row : rows) {
            if (row.placeOfSupply == placeOfSupply && (rate == null || row.rate == rate)) {
                return row;
            }
        }
        return null;
    }

    private static GstReturnService.HsnRow hsnRow(List<GstReturnService.HsnRow> rows, String hsn, Decimal rate) {
        for (GstReturnService.HsnRow row : rows) {
            if (row.hsn == hsn && row.rate == rate) {
                return row;
            }
        }
        return null;
    }

    @isTest
    static void aMonthOfBills_landsInTheRightGstr1Tables() {
        Map<String, Bill__c> bills = sampleMonth();

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Test.stopTest();

        System.assertEquals(9, ret.billCount, 'Deleted and replaced bills carry no amounts.');

        // Table 4, B2B: per invoice and rate.
        System.assertEquals(3, ret.b2b.size());
        GstReturnService.InvoiceRow b1At18 = invoiceRow(ret.b2b, bills.get('B1').Invoice_Number__c, 18);
        System.assertEquals(MP_GSTIN, b1At18.gstin);
        System.assertEquals('Sharma Traders', b1At18.receiverName);
        System.assertEquals('23-Madhya Pradesh', b1At18.placeOfSupply);
        System.assertEquals(1000, b1At18.taxableValue);
        System.assertEquals(90, b1At18.cgst);
        System.assertEquals(90, b1At18.sgst);
        System.assertEquals(1390, b1At18.invoiceValue);
        GstReturnService.InvoiceRow b1At5 = invoiceRow(ret.b2b, bills.get('B1').Invoice_Number__c, 5);
        System.assertEquals(200, b1At5.taxableValue);
        System.assertEquals(5, b1At5.cgst);
        GstReturnService.InvoiceRow b2 = invoiceRow(ret.b2b, bills.get('B2').Invoice_Number__c, 18);
        System.assertEquals(MH_GSTIN, b2.gstin);
        System.assertEquals('Mumbai Fleet', b2.receiverName, 'Billed to the party, not the car owner.');
        System.assertEquals('27-Maharashtra', b2.placeOfSupply);
        System.assertEquals(360, b2.igst);

        // Table 5, B2C Large: inter-state, unregistered, over one lakh.
        System.assertEquals(1, ret.b2cl.size());
        System.assertEquals(bills.get('B3').Invoice_Number__c, ret.b2cl[0].invoiceNumber);
        System.assertEquals(118000, ret.b2cl[0].invoiceValue);
        System.assertEquals(100000, ret.b2cl[0].taxableValue);
        System.assertEquals(18000, ret.b2cl[0].igst);

        // Table 7, B2C Small: by place of supply and rate.
        System.assertEquals(3, ret.b2cs.size());
        GstReturnService.SummaryRow mp18 = summaryRow(ret.b2cs, '23-Madhya Pradesh', 18);
        System.assertEquals(650, mp18.taxableValue, 'B5 500 + B10 100 + B11 50.');
        System.assertEquals(49.5, mp18.cgst);
        System.assertEquals(49.5, mp18.sgst);
        System.assertEquals(18, mp18.igst, 'Reported as charged; the checkup flags it.');
        System.assertEquals(100, summaryRow(ret.b2cs, '23-Madhya Pradesh', 5).taxableValue);
        System.assertEquals(180, summaryRow(ret.b2cs, '27-Maharashtra', 18).igst);

        // Table 8, nil rated.
        for (GstReturnService.NilRow row : ret.nil) {
            System.assertEquals(row.description == GstReturnService.NIL_INTRA_UNREGISTERED ? 1000 : 0, row.nilRated, row.description);
        }
    }

    @isTest
    static void hsnSummary_isSplitB2bAndB2c_withGstUnits() {
        sampleMonth();

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Test.stopTest();

        System.assertEquals(2, ret.hsnB2b.size());
        GstReturnService.HsnRow brakes = hsnRow(ret.hsnB2b, '8708', 18);
        System.assertEquals('PCS-PIECES', brakes.uqc);
        System.assertEquals(2, brakes.quantity, 'B1 and B2 together.');
        System.assertEquals(3000, brakes.taxableValue);
        System.assertEquals(360, brakes.igst);
        System.assertEquals(90, brakes.cgst);
        System.assertEquals(3540, brakes.totalValue);
        System.assertEquals('LTR-LITRES', hsnRow(ret.hsnB2b, '2710', 5).uqc);

        GstReturnService.HsnRow labour = hsnRow(ret.hsnB2c, '998714', 18);
        System.assertEquals('NA', labour.uqc, 'A service has no unit.');
        System.assertEquals(0, labour.quantity);
        System.assertEquals(1000, hsnRow(ret.hsnB2c, '8708', 0).taxableValue, 'B5\'s 300 and B6\'s 700 at nil.');
        System.assertEquals('SET-SETS', hsnRow(ret.hsnB2c, '8708', 18).uqc);
        System.assertEquals('NOS-NUMBERS', hsnRow(ret.hsnB2c, '8703', 18).uqc);
        System.assertEquals(50, hsnRow(ret.hsnB2c, '', 18).taxableValue, 'A line with no HSN is still counted, and flagged.');
    }

    @isTest
    static void gstr3b_salesFigures() {
        sampleMonth();

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Test.stopTest();

        GstReturnService.Gstr3b g = ret.gstr3b;
        System.assertEquals(104950, g.taxableValue);
        System.assertEquals(18558, g.igst);
        System.assertEquals(147, g.cgst);
        System.assertEquals(147, g.sgst);
        System.assertEquals(1000, g.nilRated);
        System.assertEquals(1, g.unregisteredInterState.size());
        System.assertEquals('27-Maharashtra', g.unregisteredInterState[0].placeOfSupply);
        System.assertEquals(101000, g.unregisteredInterState[0].taxableValue);
        System.assertEquals(18180, g.unregisteredInterState[0].igst);
    }

    @isTest
    static void documentsIssued_countsDeletedAndReplacedAsCancelled() {
        Map<String, Bill__c> bills = sampleMonth();

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Test.stopTest();

        System.assertEquals(1, ret.documents.size());
        GstReturnService.DocumentRow docs = ret.documents[0];
        System.assertEquals('Invoices for outward supply', docs.nature);
        System.assertEquals(bills.get('B1').Invoice_Number__c, docs.fromNumber);
        System.assertEquals(bills.get('B11').Invoice_Number__c, docs.toNumber);
        System.assertEquals(11, docs.totalNumber);
        System.assertEquals(2, docs.cancelled);
        System.assertEquals(9, docs.netIssued);
    }

    @isTest
    static void checkup_namesWhatToPutRight() {
        Map<String, Bill__c> bills = sampleMonth();

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Test.stopTest();

        Map<String, List<GstReturnService.Issue>> byNumber = new Map<String, List<GstReturnService.Issue>>();
        String all = '';
        for (GstReturnService.Issue issue : ret.issues) {
            all += issue.severity + ': ' + issue.message + '\n';
            String key = issue.documentNumber == null ? '' : issue.documentNumber;
            if (!byNumber.containsKey(key)) {
                byNumber.put(key, new List<GstReturnService.Issue>());
            }
            byNumber.get(key).add(issue);
        }
        System.assertEquals(2, ret.errorCount, all);
        System.assertEquals('error', ret.issues[0].severity, 'Errors first.');
        System.assert(byNumber.get(bills.get('B10').Invoice_Number__c)[0].message.contains('should be CGST+SGST'), all);
        System.assert(byNumber.get(bills.get('B11').Invoice_Number__c)[0].message.contains('No HSN/SAC'), all);
        System.assert(all.contains('1 bill(s) worth Rs. 700.00 have no GST (' + bills.get('B6').Invoice_Number__c + ')'), all);
        System.assert(!byNumber.containsKey(bills.get('B7').Invoice_Number__c), 'A deleted bill isn\'t checked.');
    }

    @isTest
    static void anInvalidBuyerGstin_isAnError_andTheBillCountsAsB2c() {
        Customer__c buyer = customer('Bad GSTIN Traders', null, null);
        Bill__c b = bill(buyer.Id, null, 2, new List<BillController.LineItemInput>{ line('Pad', 1, 100, 18, 'CGST_SGST', '8708', 'Pcs') });
        update new Bill__c(Id = b.Id, Recipient_GSTIN__c = '23ABCDE1234F1Z5');

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Test.stopTest();

        System.assertEquals(0, ret.b2b.size());
        System.assertEquals(100, ret.b2cs[0].taxableValue);
        System.assertEquals(1, ret.errorCount);
        System.assert(ret.issues[0].message.contains('"23ABCDE1234F1Z5" is not valid'), ret.issues[0].message);
        System.assertEquals(b.Id, ret.issues[0].billId);
    }

    @isTest
    static void inter_stateCgstSgst_isAnError() {
        Customer__c buyer = customer('Patil', null, 'Maharashtra');
        bill(buyer.Id, null, 2, new List<BillController.LineItemInput>{ line('Pad', 1, 100, 18, 'CGST_SGST', '8708', 'Pcs') });

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Test.stopTest();

        System.assert(ret.issues[0].message.contains('another state (27-Maharashtra): it should be IGST'), ret.issues[0].message);
    }

    @isTest
    static void documentsIssued_splitAroundAnOldDateBill_andCountsAMissingNumber() {
        Customer__c buyer = customer('Ramesh', null, null);
        String fy = InvoiceNumberingService.financialYearFor(periodStart());
        Id companyId = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id;
        List<Bill__c> bills = new List<Bill__c>{
            new Bill__c(Customer__c = buyer.Id, Workshop_Profile__c = companyId, Bill_Date__c = periodStart(), Invoice_Number__c = 'TST/' + fy + '/0001', Financial_Year__c = fy),
            new Bill__c(Customer__c = buyer.Id, Workshop_Profile__c = companyId, Bill_Date__c = periodStart(), Invoice_Number__c = 'TST/' + fy + '/0002', Financial_Year__c = fy),
            new Bill__c(Customer__c = buyer.Id, Workshop_Profile__c = companyId, Bill_Date__c = periodEnd().addDays(1), Invoice_Number__c = 'TST/' + fy + '/0003', Financial_Year__c = fy),
            new Bill__c(Customer__c = buyer.Id, Workshop_Profile__c = companyId, Bill_Date__c = periodEnd(), Invoice_Number__c = 'TST/' + fy + '/0004', Financial_Year__c = fy, Is_Cancelled__c = true),
            new Bill__c(Customer__c = buyer.Id, Workshop_Profile__c = companyId, Bill_Date__c = periodEnd(), Invoice_Number__c = 'TST/' + fy + '/0006', Financial_Year__c = fy)
        };
        insert bills;

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(companyId, periodStart(), periodEnd());
        Test.stopTest();

        System.assertEquals(2, ret.documents.size());
        System.assertEquals('TST/' + fy + '/0001', ret.documents[0].fromNumber);
        System.assertEquals('TST/' + fy + '/0002', ret.documents[0].toNumber);
        System.assertEquals(0, ret.documents[0].cancelled);
        System.assertEquals('TST/' + fy + '/0004', ret.documents[1].fromNumber);
        System.assertEquals('TST/' + fy + '/0006', ret.documents[1].toNumber);
        System.assertEquals(3, ret.documents[1].totalNumber);
        System.assertEquals(2, ret.documents[1].cancelled, 'The deleted 0004 and the missing 0005.');
        Boolean warned = false;
        for (GstReturnService.Issue issue : ret.issues) {
            warned = warned || issue.message.contains('TST/' + fy + '/0005');
        }
        System.assert(warned, 'The missing number is named.');
    }

    @isTest
    static void theCompanyItself_mustHaveAValidGstinAndState() {
        Workshop_Profile__c company = [SELECT Id FROM Workshop_Profile__c LIMIT 1];
        update new Workshop_Profile__c(Id = company.Id, GSTIN__c = null, State__c = null);

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(company.Id, periodStart(), periodEnd());
        Test.stopTest();

        System.assertEquals(2, ret.errorCount);
        System.assert(ret.issues[0].message.contains('GSTIN'), ret.issues[0].message);
        System.assert(ret.issues[1].message.contains('no state'), ret.issues[1].message);
    }

    @isTest
    static void aCompositionCompany_getsItsTurnover_notGstr1() {
        Workshop_Profile__c company = [SELECT Id FROM Workshop_Profile__c LIMIT 1];
        update new Workshop_Profile__c(Id = company.Id, GST_Registration_Type__c = 'Composition');
        Customer__c buyer = customer('Ramesh', null, null);
        bill(buyer.Id, null, 2, new List<BillController.LineItemInput>{ line('Pad', 1, 1000, 0, 'CGST_SGST', '8708', 'Pcs') });

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(company.Id, periodStart(), periodEnd());
        Map<String, String> files = GstReturnFiles.csvFiles(ret);
        Test.stopTest();

        System.assertEquals(1000, ret.compositionTurnover);
        System.assertEquals(0, ret.b2cs.size());
        System.assertEquals(null, ret.gstr3b);
        System.assertEquals(new Set<String>{ GstReturnFiles.SUMMARY }, files.keySet());
        System.assert(files.get(GstReturnFiles.SUMMARY).contains('Turnover for CMP-08,1000.00'));
    }

    @isTest
    static void aFiledPeriod_saysSo() {
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, GST_Filed_Up_To__c = periodEnd());

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Test.stopTest();

        System.assertEquals(true, ret.isFiled);
        System.assertEquals(periodEnd(), ret.filedUpTo);
    }

    @isTest
    static void aBillsItemProblems_areOneLineEach_namingEveryItem() {
        Customer__c buyer = customer('Ramesh', null, null);
        Bill__c b = bill(buyer.Id, null, 2, new List<BillController.LineItemInput>{
            line('Bulb', 1, 100, 18, 'CGST_SGST', null, 'Pcs'),
            line('Pad', 1, 100, 18, 'CGST_SGST', '', 'Pcs'),
            line('Clip', 1, 100, 18, 'CGST_SGST', '87', 'bundle')
        });

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Test.stopTest();

        System.assertEquals(1, ret.errorCount);
        System.assertEquals(2, ret.warningCount);
        System.assertEquals('No HSN/SAC on "Bulb", "Pad". Every item needs one for the HSN summary: add it to the part and change the bill.', ret.issues[0].message);
        System.assertEquals(b.Id, ret.issues[0].billId);
        System.assertEquals('HSN/SAC should be at least 4 digits: "87" on "Clip".', ret.issues[1].message);
        System.assert(ret.issues[2].message.contains('"bundle" on "Clip"'), ret.issues[2].message);
    }

    // ---- the portal's JSON (G5) ------------------------------------------------------

    private static Map<String, Object> obj(Object o) {
        return (Map<String, Object>) o;
    }

    private static List<Object> arr(Object o) {
        return (List<Object>) o;
    }

    @isTest
    static void thePortalJson_holdsTheSameReturn_inThePortalsLayout() {
        Map<String, Bill__c> bills = sampleMonth();

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), periodEnd());
        Map<String, Object> root = obj(JSON.deserializeUntyped(GstReturnFiles.portalJson(ret)));
        Test.stopTest();

        System.assertEquals('23AAACI7904G1ZV', root.get('gstin'));
        System.assertEquals(String.valueOf(periodStart().month()).leftPad(2, '0') + periodStart().year(), root.get('fp'));
        System.assertEquals('GSTR1_' + root.get('fp') + '.json', GstReturnFiles.jsonFileName(ret));

        // B2B: one entry per buyer, the invoice with one item per rate.
        Map<String, Map<String, Object>> buyers = new Map<String, Map<String, Object>>();
        for (Object o : arr(root.get('b2b'))) {
            buyers.put((String) obj(o).get('ctin'), obj(o));
        }
        System.assertEquals(new Set<String>{ MP_GSTIN, MH_GSTIN }, buyers.keySet());
        Map<String, Object> b1 = obj(arr(buyers.get(MP_GSTIN).get('inv'))[0]);
        System.assertEquals(bills.get('B1').Invoice_Number__c, b1.get('inum'));
        Date b1Date = periodStart().addDays(1);
        System.assertEquals('02-' + String.valueOf(b1Date.month()).leftPad(2, '0') + '-' + b1Date.year(), b1.get('idt'));
        System.assertEquals('23', b1.get('pos'));
        System.assertEquals(1390, (Decimal) b1.get('val'));
        List<Object> items = arr(b1.get('itms'));
        System.assertEquals(2, items.size());
        Map<String, Decimal> cgstByRate = new Map<String, Decimal>();
        for (Object item : items) {
            Map<String, Object> det = obj(obj(item).get('itm_det'));
            cgstByRate.put(GstRules.rateText((Decimal) det.get('rt')), (Decimal) det.get('camt'));
            System.assertEquals(false, det.containsKey('iamt'), 'Within the state: central and state tax only.');
        }
        System.assertEquals(90, cgstByRate.get('18'));
        System.assertEquals(5, cgstByRate.get('5'));
        Map<String, Object> b2Item = obj(obj(arr(obj(arr(buyers.get(MH_GSTIN).get('inv'))[0]).get('itms'))[0]).get('itm_det'));
        System.assertEquals(360, (Decimal) b2Item.get('iamt'));
        System.assertEquals(false, b2Item.containsKey('camt'));

        // B2C Large by state, B2C Small by state and rate.
        Map<String, Object> b2cl = obj(arr(root.get('b2cl'))[0]);
        System.assertEquals('27', b2cl.get('pos'));
        System.assertEquals(118000, (Decimal) obj(arr(b2cl.get('inv'))[0]).get('val'));
        Integer interRows = 0;
        for (Object o : arr(root.get('b2cs'))) {
            Map<String, Object> row = obj(o);
            System.assertEquals('OE', row.get('typ'));
            if (row.get('pos') == '27') {
                interRows++;
                System.assertEquals('INTER', row.get('sply_ty'));
                System.assertEquals(180, (Decimal) row.get('iamt'));
            } else {
                System.assertEquals('INTRA', row.get('sply_ty'));
            }
        }
        System.assertEquals(1, interRows);

        // Nil rated, HSN in two lists, documents issued.
        Decimal nil = 0;
        for (Object o : arr(obj(root.get('nil')).get('inv'))) {
            nil += (Decimal) obj(o).get('nil_amt');
        }
        System.assertEquals(1000, nil);
        Map<String, Object> hsn = obj(root.get('hsn'));
        System.assertEquals(ret.hsnB2b.size(), arr(hsn.get('hsn_b2b')).size());
        System.assertEquals(ret.hsnB2c.size(), arr(hsn.get('hsn_b2c')).size());
        for (Object o : arr(hsn.get('hsn_b2b'))) {
            System.assert(!((String) obj(o).get('uqc')).contains('-'), 'The portal takes the short unit code: ' + obj(o).get('uqc'));
        }
        Map<String, Object> docs = obj(arr(obj(root.get('doc_issue')).get('doc_det'))[0]);
        System.assertEquals(GstReturnService.DOCUMENT_NATURE, docs.get('doc_typ'));
        System.assertEquals(ret.documents[0].cancelled, (Integer) obj(arr(docs.get('docs'))[0]).get('cancel'));
    }

    @isTest
    static void theZip_carriesTheJson_onlyForARegularCompany() {
        Workshop_Profile__c company = [SELECT Id FROM Workshop_Profile__c LIMIT 1];
        Customer__c buyer = customer('Ramesh', null, null);
        bill(buyer.Id, null, 2, new List<BillController.LineItemInput>{ line('Pad', 1, 1000, 18, 'CGST_SGST', '8708', 'Pcs') });

        Test.startTest();
        GstReturnService.GstReturn regular = GstReturnService.build(company.Id, periodStart(), periodEnd());
        Compression.ZipReader regularZip = new Compression.ZipReader(GstReturnFiles.zip(regular));
        update new Workshop_Profile__c(Id = company.Id, GST_Registration_Type__c = 'Composition');
        GstReturnService.GstReturn composition = GstReturnService.build(company.Id, periodStart(), periodEnd());
        Compression.ZipReader compositionZip = new Compression.ZipReader(GstReturnFiles.zip(composition));
        Test.stopTest();

        System.assert(entryNames(regularZip).contains(GstReturnFiles.jsonFileName(regular)), String.valueOf(entryNames(regularZip)));
        System.assert(!entryNames(compositionZip).contains(GstReturnFiles.jsonFileName(composition)), 'A composition company files CMP-08, not GSTR-1.');
    }

    private static Set<String> entryNames(Compression.ZipReader reader) {
        Set<String> names = new Set<String>();
        for (Compression.ZipEntry entry : reader.getEntries()) {
            names.add(entry.getName());
        }
        return names;
    }
}
