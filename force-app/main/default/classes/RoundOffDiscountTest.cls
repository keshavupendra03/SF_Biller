/**
 * GST stages G5/G6 (architecture.md §D.1): rupee line discounts, whole-rupee
 * round-off by company setting, and no GST from a composition company.
 *
 *   1 x 333 @18%           = 333 + 59.94      = 392.94 -> rounds to 393.00 (+0.06)
 *   2 x 500 - 100 discount = 900 + 162 (18%)  = 1062.00
 */
@isTest
private class RoundOffDiscountTest {

    @testSetup
    static void setup() {
        // Left as it comes: a company rounds off unless it chooses exact totals.
        insert new Workshop_Profile__c(Name = 'Speedy Motors', State__c = 'Madhya Pradesh');
        insert new Customer__c(Name = 'Ramesh', Phone__c = '9000011111');
    }

    private static BillController.LineItemInput line(String description, Decimal qty, Decimal price, Decimal rate, Decimal discount) {
        BillController.LineItemInput li = new BillController.LineItemInput();
        li.description = description;
        li.quantity = qty;
        li.unitPrice = price;
        li.taxRatePercent = rate;
        li.gstType = 'CGST_SGST';
        li.hsnSacCode = '8708';
        li.discount = discount;
        return li;
    }

    private static BillController.CreateBillRequest request(List<BillController.LineItemInput> lines) {
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = [SELECT Id FROM Customer__c LIMIT 1].Id;
        request.lineItems = lines;
        return request;
    }

    private static void roundOff(Boolean rounds) {
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, Exact_Totals__c = !rounds);
    }

    @isTest
    static void roundOff_takesTheTotalToWholeRupees_whenTheCompanyChoosesIt() {
        Test.startTest();
        BillController.BillSummary rounded = BillController.createBill(request(new List<BillController.LineItemInput>{ line('Pad', 1, 333, 18, null) }));
        roundOff(false);
        BillController.BillSummary exact = BillController.createBill(request(new List<BillController.LineItemInput>{ line('Pad', 1, 333, 18, null) }));
        Test.stopTest();

        System.assertEquals(393.00, rounded.totalAmount);
        System.assertEquals(0.06, rounded.roundOff);
        System.assertEquals(333, rounded.subtotal);
        System.assertEquals(392.94, exact.totalAmount);
        System.assertEquals(0, exact.roundOff);
    }

    @isTest
    static void roundOff_canGoDown() {
        Test.startTest();
        // 1 x 340 @18% = 401.20 -> 401.00 (-0.20)
        BillController.BillSummary down = BillController.createBill(request(new List<BillController.LineItemInput>{ line('Pad', 1, 340, 18, null) }));
        Test.stopTest();

        System.assertEquals(401.00, down.totalAmount);
        System.assertEquals(-0.20, down.roundOff);
    }

    @isTest
    static void aDiscount_comesOffBeforeGst() {
        roundOff(false);

        Test.startTest();
        BillController.BillSummary bill = BillController.createBill(request(new List<BillController.LineItemInput>{ line('Pad', 2, 500, 18, 100) }));
        Test.stopTest();

        System.assertEquals(900, bill.subtotal);
        System.assertEquals(81, bill.cgst);
        System.assertEquals(81, bill.sgst);
        System.assertEquals(1062, bill.totalAmount);
        System.assertEquals(100, bill.lineItems[0].discount);
        System.assertEquals(100, [SELECT Discount__c FROM Bill_Line_Item__c LIMIT 1].Discount__c);
    }

    @isTest
    static void aDiscountMoreThanTheLine_orBelowZero_isRefused() {
        for (Decimal discount : new List<Decimal>{ 1001, -1 }) {
            try {
                BillController.createBill(request(new List<BillController.LineItemInput>{ line('Pad', 2, 500, 18, discount) }));
                System.assert(false, 'Expected ' + discount + ' to be refused.');
            } catch (BillController.BillControllerException e) {
                System.assert(e.getMessage().contains('discount on "Pad" must be between 0 and its price (Rs. 1000.00)'), e.getMessage());
            }
        }
        System.assertEquals(0, [SELECT COUNT() FROM Bill__c]);
    }

    @isTest
    static void estimates_takeDiscountsAndRoundOffToo() {
        EstimateController.CreateEstimateRequest estimate = new EstimateController.CreateEstimateRequest();
        estimate.customerId = [SELECT Id FROM Customer__c LIMIT 1].Id;
        estimate.lineItems = new List<BillController.LineItemInput>{ line('Pad', 1, 333, 18, 0), line('Paint', 2, 500, 18, 100) };

        Test.startTest();
        EstimateController.EstimateSummary saved = EstimateController.createEstimate(estimate);
        Test.stopTest();

        // 392.94 + 1062.00 = 1454.94 -> 1455.00
        System.assertEquals(1233, saved.subtotal);
        System.assertEquals(1455.00, saved.totalAmount);
        System.assertEquals(0.06, saved.roundOff);
    }

    @isTest
    static void theBillPrints_theDiscountColumn_roundOff_andWordsForTheRoundedTotal() {
        BillController.BillSummary bill = BillController.createBill(request(new List<BillController.LineItemInput>{
            line('Pad', 1, 333, 18, 0), line('Paint', 2, 500, 18, 100) }));
        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', bill.billId);

        Test.startTest();
        InvoicePdfController pdf = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals(true, pdf.showDiscount);
        System.assertEquals('Discount', pdf.discountLabel);
        System.assertEquals(100, pdf.lines[1].discount);
        System.assertEquals(900, pdf.lines[1].taxableAmount);
        System.assertEquals(0.06, pdf.roundOff);
        System.assertEquals(1455.00, pdf.grandTotal);
        System.assertEquals(AmountInWordsService.convert(1455.00), pdf.amountInWords);
    }

    @isTest
    static void aCompositionCompany_chargesNoGst_andIssuesABillOfSupply() {
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, GST_Registration_Type__c = 'Composition', Exact_Totals__c = true);

        Test.startTest();
        BillController.BillSummary bill = BillController.createBill(request(new List<BillController.LineItemInput>{ line('Pad', 1, 1000, 18, null) }));
        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', bill.billId);
        InvoicePdfController pdf = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals(1000, bill.totalAmount, 'No GST, whatever the screen sent.');
        System.assertEquals(0, [SELECT Tax_Rate_Percent__c FROM Bill_Line_Item__c LIMIT 1].Tax_Rate_Percent__c);
        System.assertEquals('Bill of Supply', pdf.documentTitle);
        System.assert(pdf.compositionNote.contains('not eligible to collect tax'), pdf.compositionNote);
    }

    @isTest
    static void anUnregisteredCompany_chargesNoGst_andPrintsABill() {
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, GST_Registration_Type__c = 'Unregistered', Exact_Totals__c = true);

        Test.startTest();
        BillController.BillSummary bill = BillController.createBill(request(new List<BillController.LineItemInput>{ line('Pad', 1, 1000, 18, null) }));
        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', bill.billId);
        InvoicePdfController pdf = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals(1000, bill.totalAmount);
        System.assertEquals('Bill', pdf.documentTitle);
        System.assertEquals(null, pdf.compositionNote);
    }

    @isTest
    static void theGstReturn_usesTheDiscountedValue() {
        roundOff(false);
        BillController.CreateBillRequest r = request(new List<BillController.LineItemInput>{ line('Pad', 2, 500, 18, 100) });
        r.billDate = Date.today().toStartOfMonth().addMonths(-1).addDays(3);
        BillController.createBill(r);
        Date start = Date.today().toStartOfMonth().addMonths(-1);

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, start, GstFilingLock.monthEnd(start));
        Test.stopTest();

        System.assertEquals(900, ret.b2cs[0].taxableValue);
        System.assertEquals(900, ret.gstr3b.taxableValue);
        System.assertEquals(1062, ret.hsnB2c[0].totalValue);
    }

    @isTest
    static void theCompanySetting_isReadAndSaved_andBlankKeepsIt() {
        Id companyId = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id;
        WorkshopProfileController.ProfileData data = WorkshopProfileController.listProfiles()[0];
        System.assertEquals(true, data.roundOffTotals);

        data.roundOffTotals = false;
        WorkshopProfileController.saveProfile(data);
        data.roundOffTotals = null;
        Test.startTest();
        WorkshopProfileController.ProfileData saved = WorkshopProfileController.saveProfile(data);
        Test.stopTest();

        System.assertEquals(false, saved.roundOffTotals, 'A screen that doesn\'t show it mustn\'t change it.');
        System.assertEquals(true, [SELECT Exact_Totals__c FROM Workshop_Profile__c WHERE Id = :companyId].Exact_Totals__c);
    }
}
