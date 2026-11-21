@isTest
private class GstReturnControllerTest {

    private static Date periodStart() {
        return Date.today().toStartOfMonth().addMonths(-2);
    }

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GSTIN__c = '23AAACI7904G1ZV', State__c = 'Madhya Pradesh');
        Customer__c buyer = new Customer__c(Name = 'Sharma, Traders', Phone__c = '9000011111', GSTIN__c = '27AAPFU0939F1ZV');
        insert buyer;
        Bill__c bill = new Bill__c(Customer__c = buyer.Id, Bill_Date__c = periodStart().addDays(4));
        insert bill;
        insert new Bill_Line_Item__c(
            Bill__c = bill.Id, Description__c = 'Brake Pad', Quantity__c = 2, Unit_Price__c = 500, Tax_Rate_Percent__c = 18,
            Gst_Type__c = 'IGST', HSN_SAC_Code__c = '8708', Unit__c = 'Pcs'
        );
    }

    @isTest
    static void getReturn_forAMonth() {
        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnController.getReturn(null, periodStart(), GstFilingLock.monthEnd(periodStart()));
        Test.stopTest();

        System.assertEquals(1, ret.b2b.size());
        System.assertEquals(1000, ret.b2b[0].taxableValue);
    }

    @isTest
    static void onlyWholeMonthsOrQuarters() {
        Date start = periodStart();
        GstReturnController.getReturn(null, start.addMonths(-2), GstFilingLock.monthEnd(start));
        for (List<Date> bad : new List<List<Date>>{
            new List<Date>{ start.addDays(1), GstFilingLock.monthEnd(start) },
            new List<Date>{ start, start.addDays(10) },
            new List<Date>{ start.addMonths(-3), GstFilingLock.monthEnd(start) },
            new List<Date>{ null, null }
        }) {
            try {
                GstReturnController.getReturn(null, bad[0], bad[1]);
                System.assert(false, 'Expected ' + bad + ' to be refused.');
            } catch (GstReturnController.GstReturnControllerException e) {
                System.assertEquals('Pick a month or quarter.', e.getMessage());
            }
        }
    }

    @isTest
    static void theFiles_areInTheOfflineToolsLayouts() {
        GstReturnService.GstReturn ret = GstReturnService.build(null, periodStart(), GstFilingLock.monthEnd(periodStart()));

        Test.startTest();
        Map<String, String> files = GstReturnFiles.csvFiles(ret);
        Test.stopTest();

        System.assertEquals(new Set<String>{ 'b2b.csv', 'b2cl.csv', 'b2cs.csv', 'exemp.csv', 'hsn(b2b).csv', 'hsn(b2c).csv', 'docs.csv', 'summary.csv' }, files.keySet());
        List<String> b2b = files.get('b2b.csv').split('\n');
        System.assertEquals('GSTIN/UIN of Recipient,Receiver Name,Invoice Number,Invoice date,Invoice Value,Place Of Supply,Reverse Charge,'
            + 'Applicable % of Tax Rate,Invoice Type,E-Commerce GSTIN,Rate,Taxable Value,Cess Amount', b2b[0]);
        String expectedDate = Datetime.newInstance(periodStart().addDays(4), Time.newInstance(0, 0, 0, 0)).format('dd-MMM-yyyy');
        System.assertEquals('27AAPFU0939F1ZV,"Sharma, Traders",' + ret.b2b[0].invoiceNumber + ',' + expectedDate
            + ',1180.00,27-Maharashtra,N,,Regular B2B,,18,1000.00,0.00', b2b[1], 'A comma in a name is quoted.');

        List<String> hsn = files.get('hsn(b2b).csv').split('\n');
        System.assertEquals('8708,Brake Pad,PCS-PIECES,2,1180.00,18,1000.00,180.00,0.00,0.00,0.00', hsn[1]);
        System.assert(files.get('docs.csv').contains('Invoices for outward supply,' + ret.b2b[0].invoiceNumber + ',' + ret.b2b[0].invoiceNumber + ',1,0'));
        System.assert(files.get('summary.csv').contains('GSTR-3B 3.1(a) Integrated tax,180.00'));
        System.assert(files.get('exemp.csv').startsWith('Description,Nil Rated Supplies,'));
    }

    @isTest
    static void download_isOneZipNamedByGstinAndPeriod() {
        Date start = periodStart();

        Test.startTest();
        GstReturnController.Download download = GstReturnController.downloadReturn(null, start, GstFilingLock.monthEnd(start));
        Test.stopTest();

        String month = start.year() + '-' + String.valueOf(start.month()).leftPad(2, '0');
        System.assertEquals('GST_23AAACI7904G1ZV_' + month + '.zip', download.fileName);
        Compression.ZipReader reader = new Compression.ZipReader(EncodingUtil.base64Decode(download.base64Data));
        Set<String> names = new Set<String>();
        for (Compression.ZipEntry entry : reader.getEntries()) {
            names.add(entry.getName());
        }
        System.assert(names.contains('b2b.csv') && names.contains('summary.csv'), String.valueOf(names));
    }

    @isTest
    static void csvCells_andDates() {
        System.assertEquals('', GstReturnFiles.csv(null));
        System.assertEquals('plain', GstReturnFiles.csv('plain'));
        System.assertEquals('"say ""hi"""', GstReturnFiles.csv('say "hi"'));
        System.assertEquals('"two\nlines"', GstReturnFiles.csv('two\nlines'));
        System.assertEquals('05-Oct-2026', GstReturnFiles.gstDate(Date.newInstance(2026, 10, 5)));
    }
}
