/**
 * Lines stored on the bill or estimate (StoredLines), and the stock their parts
 * take (BillStockService). Covers what the old line-record trigger tests did:
 * totals worked out from the lines, mixed GST types, and stock out and back.
 */
@isTest
private class StoredLinesTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static Id insertBill() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Bill__c bill = new Bill__c(Customer__c = customer.Id);
        insert bill;
        return bill.Id;
    }

    @isTest
    static void storingLines_worksOutTheBillTotals() {
        Id billId = insertBill();

        Test.startTest();
        TestLines.attach(billId, new List<BillController.LineItemInput>{
            TestLines.line('Brake Pad', 2, 500, 18),
            TestLines.line('Labour', 1, 300, 0)
        });
        Test.stopTest();

        Bill__c bill = [SELECT Subtotal__c, GST_Amount__c, Total_Amount__c, Line_Items__c FROM Bill__c WHERE Id = :billId];
        System.assertEquals(1300, bill.Subtotal__c);
        System.assertEquals(180, bill.GST_Amount__c, '18% of 1000 only.');
        System.assertEquals(1480, bill.Total_Amount__c);
        System.assertEquals(2, StoredLines.read(bill.Line_Items__c).size());
        System.assertEquals('Brake Pad', StoredLines.read(bill.Line_Items__c)[0].description, 'Kept in the order given.');
    }

    @isTest
    static void mixedGstTypeLines_bothBucketsSummedCorrectly() {
        Id billId = insertBill();

        Test.startTest();
        TestLines.attach(billId, new List<BillController.LineItemInput>{
            TestLines.line('Local part', 2, 500, 18, 'CGST_SGST', null, null),
            TestLines.line('Out-of-state part', 5, 240, 28, 'IGST', null, null)
        });
        Test.stopTest();

        Bill__c bill = [SELECT Subtotal__c, GST_Amount__c, Total_Amount__c FROM Bill__c WHERE Id = :billId];
        // Line 1 (CGST+SGST): subtotal 1000, gst 180. Line 2 (IGST): subtotal 1200, gst 336.
        System.assertEquals(2200, bill.Subtotal__c);
        System.assertEquals(516, bill.GST_Amount__c);
        System.assertEquals(2716, bill.Total_Amount__c);
    }

    @isTest
    static void anEstimate_storesItsLinesTheSameWay() {
        Customer__c customer = new Customer__c(Name = 'Deepak', Phone__c = '9333344444');
        insert customer;
        Estimate__c estimate = new Estimate__c(Customer__c = customer.Id);
        insert estimate;

        Test.startTest();
        TestLines.attach(estimate.Id, TestLines.line('Diagnostic', 1, 500, 18));
        Test.stopTest();

        Estimate__c saved = [SELECT Total_Amount__c, GST_Amount__c FROM Estimate__c WHERE Id = :estimate.Id];
        System.assertEquals(590, saved.Total_Amount__c);
        System.assertEquals(90, saved.GST_Amount__c);
    }

    @isTest
    static void blanks_areStoredAsTheOldLineFieldsHeldThem() {
        BillController.LineItemInput typed = TestLines.line('Washer', 1.005, 99.999, null, null, '', ' ');
        typed.gstType = 'igst';

        Test.startTest();
        String stored = StoredLines.write(new List<BillController.LineItemInput>{ typed });
        Test.stopTest();

        BillController.LineItemInput line = StoredLines.read(stored)[0];
        System.assertEquals(1.01, line.quantity, 'Two places, as the old Quantity field.');
        System.assertEquals(100.00, line.unitPrice);
        System.assertEquals(0, line.taxRatePercent, 'A blank rate is 0.');
        System.assertEquals(0, line.discount, 'A blank discount is 0.');
        System.assertEquals('IGST', line.gstType);
        System.assertEquals(null, line.hsnSacCode, 'A blank code is stored as none.');
        System.assertEquals(null, line.unitLabel);
        System.assert(!stored.contains('partId'), 'Blanks take no room: ' + stored);
        System.assertEquals(0, StoredLines.read(null).size());
        System.assertEquals('CGST_SGST', StoredLines.read(StoredLines.write(new List<BillController.LineItemInput>{ TestLines.line('Pad', 1, 1, 0) }))[0].gstType);
    }

    @isTest
    static void aLineTheOldFieldsCouldNotHold_isRefusedInWords() {
        List<String> messages = new List<String>();
        List<BillController.LineItemInput> bad = new List<BillController.LineItemInput>{
            TestLines.line('x'.repeat(256), 1, 1, 0),
            TestLines.line('Pad', 1, 1, 0, null, '123456789012345678901', null),
            TestLines.line('Pad', 1, 1, 0, null, null, 'a very long unit name'),
            TestLines.line('Pad', 1, 1, 0, 'VAT', null, null)
        };

        Test.startTest();
        for (BillController.LineItemInput line : bad) {
            try {
                StoredLines.write(new List<BillController.LineItemInput>{ line });
                messages.add('saved');
            } catch (StoredLines.StoredLinesException e) {
                messages.add(e.getMessage());
            }
        }
        Test.stopTest();

        System.assert(messages[0].startsWith('An item name can be at most 255 characters'), messages[0]);
        System.assert(messages[1].startsWith('An HSN/SAC code can be at most 20 characters'), messages[1]);
        System.assert(messages[2].startsWith('A unit can be at most 20 characters'), messages[2]);
        System.assertEquals('"VAT" is not a GST type. Use CGST_SGST or IGST.', messages[3]);
    }

    @isTest
    static void moreLinesThanTheFieldHolds_isRefused() {
        List<BillController.LineItemInput> lines = new List<BillController.LineItemInput>();
        for (Integer i = 0; i < 450; i++) {
            lines.add(TestLines.line('x'.repeat(250), 1, 1, 0));
        }
        String message;

        Test.startTest();
        try {
            StoredLines.write(lines);
        } catch (StoredLines.StoredLinesException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals('There are too many items to save on one document. Split it into two.', message);
    }

    @isTest
    static void aBillsParts_goOutOfStock_andComeBack() {
        Part__c pad = new Part__c(Name = 'Brake Pad', Price__c = 500, Current_Stock__c = 5);
        Part__c gone = new Part__c(Name = 'Deleted part', Price__c = 10, Current_Stock__c = 1);
        insert new List<Part__c>{ pad, gone };
        List<BillController.LineItemInput> lines = new List<BillController.LineItemInput>{
            TestLines.line('Brake Pad', 2, 500, 18),
            TestLines.line('Brake Pad again', 1, 500, 18),
            TestLines.line('Labour', 1, 300, 0),
            TestLines.line('Deleted part', 1, 10, 0)
        };
        lines[0].partId = pad.Id;
        lines[1].partId = pad.Id;
        lines[3].partId = gone.Id;
        delete gone;

        Test.startTest();
        BillStockService.deduct(lines);
        Decimal afterDeduct = [SELECT Current_Stock__c FROM Part__c WHERE Id = :pad.Id].Current_Stock__c;
        BillStockService.restore(lines);
        Test.stopTest();

        System.assertEquals(2, afterDeduct, 'Both lines of the part come off; a deleted part is skipped.');
        System.assertEquals(5, [SELECT Current_Stock__c FROM Part__c WHERE Id = :pad.Id].Current_Stock__c);
    }
}
