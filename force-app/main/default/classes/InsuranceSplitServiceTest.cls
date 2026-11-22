/**
 * Insurance claim split (architecture.md §D.1, G6). The job, all at 18%:
 *
 *   Bumper     1 x 1000, insurer 100%
 *   Headlamp   1 x 1000, insurer  50% (depreciation)
 *   Labour     1 x  500, insurer 100%
 *
 * With no excess: insurer taxable 1000 + 500 + 500 = 2000 (2360 with GST);
 * customer 500 (590). With a Rs. 590 excess: 590 x share / 2360 comes off
 * each insurer line in taxable terms: 250, 125, 125. Insurer 750 + 375 + 375
 * = 1500 (1770 = 2360 - 590); customer 250 + 625 + 125 = 1000 (1180).
 */
@isTest
private class InsuranceSplitServiceTest {

    private static BillController.LineItemInput line(String description, Decimal qty, Decimal price) {
        BillController.LineItemInput li = new BillController.LineItemInput();
        li.description = description;
        li.quantity = qty;
        li.unitPrice = price;
        li.taxRatePercent = 18;
        li.gstType = 'CGST_SGST';
        li.hsnSacCode = '8708';
        li.unitLabel = 'Pcs';
        return li;
    }

    private static List<BillController.LineItemInput> job() {
        return new List<BillController.LineItemInput>{ line('Bumper', 1, 1000), line('Headlamp', 1, 1000), line('Labour', 1, 500) };
    }

    // As plain text: an Apex map tells 1000 from 1000.00.
    private static Map<String, String> taxableByLine(List<BillController.LineItemInput> lines) {
        Map<String, String> taxable = new Map<String, String>();
        for (BillController.LineItemInput li : lines) {
            taxable.put(li.description, GstRules.rateText(li.quantity * li.unitPrice - li.discount));
        }
        return taxable;
    }

    // How many of a bill's lines are linked to a part.
    private static Integer partLinks(Id billId) {
        Integer linked = 0;
        for (BillController.LineItemInput line : TestLines.of(billId)) {
            if (line.partId != null) {
                linked++;
            }
        }
        return linked;
    }

    @isTest
    static void eachLineSplitsByItsPercent_withTheOtherSharesAsTheDiscount() {
        InsuranceSplitService.Split split = InsuranceSplitService.split(job(), new List<Decimal>{ 100, 50, 100 }, 0);

        Map<String, String> insurer = taxableByLine(split.insurerLines);
        Map<String, String> customer = taxableByLine(split.customerLines);
        System.assertEquals(new Map<String, String>{ 'Bumper' => '1000', 'Headlamp' => '500', 'Labour' => '500' }, insurer);
        System.assertEquals(new Map<String, String>{ 'Headlamp' => '500' }, customer, 'Only what the insurer doesn\'t pay.');
        System.assertEquals(1000, split.customerLines[0].unitPrice, 'Both keep the full price.');
        System.assertEquals(500, split.customerLines[0].discount);
    }

    @isTest
    static void theExcess_movesFromTheInsurerToTheCustomer_keepingEachLinesRate() {
        InsuranceSplitService.Split split = InsuranceSplitService.split(job(), new List<Decimal>{ 100, 50, 100 }, 590);

        System.assertEquals(new Map<String, String>{ 'Bumper' => '750', 'Headlamp' => '375', 'Labour' => '375' }, taxableByLine(split.insurerLines));
        System.assertEquals(new Map<String, String>{ 'Bumper' => '250', 'Headlamp' => '625', 'Labour' => '125' }, taxableByLine(split.customerLines));
    }

    @isTest
    static void theCustomersLines_linkNoPart_soStockIsTakenOnce() {
        BillController.LineItemInput part = line('Bumper', 1, 1000);
        part.partId = Id.valueOf(Part__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

        InsuranceSplitService.Split split = InsuranceSplitService.split(new List<BillController.LineItemInput>{ part }, new List<Decimal>{ 60 }, 0);

        System.assertEquals(part.partId, split.insurerLines[0].partId);
        System.assertEquals(null, split.customerLines[0].partId);
    }

    @isTest
    static void whatCannotBeSplit_isRefused_saySo() {
        Map<String, List<Object>> cases = new Map<String, List<Object>>{
            'between 0 and 100%' => new List<Object>{ new List<Decimal>{ 120, 50, 100 }, 0 },
            'more than the insurance company\'s share' => new List<Object>{ new List<Decimal>{ 100, 50, 100 }, 3000 },
            'The customer pays nothing' => new List<Object>{ new List<Decimal>{ 100, 100, 100 }, 0 },
            'The insurance company pays nothing' => new List<Object>{ new List<Decimal>{ 0, 0, 0 }, 0 },
            'less than zero' => new List<Object>{ new List<Decimal>{ 100, 50, 100 }, -1 }
        };
        for (String expected : cases.keySet()) {
            List<Object> args = cases.get(expected);
            try {
                InsuranceSplitService.split(job(), (List<Decimal>) args[0], (Decimal) args[1]);
                System.assert(false, 'Expected: ' + expected);
            } catch (InsuranceSplitService.InsuranceSplitException e) {
                System.assert(e.getMessage().contains(expected), e.getMessage());
            }
        }
    }

    // ---- saved from Easy Bill --------------------------------------------------------

    private static PaperBillController.PaperRequest claim() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', State__c = 'Madhya Pradesh', Exact_Totals__c = true);
        Part__c bumper = new Part__c(Name = 'Bumper', Price__c = 1000, Tax_Rate_Percent__c = 18, Current_Stock__c = 5, HSN_Code__c = '8708');
        insert bumper;
        PaperBillController.PaperRequest r = new PaperBillController.PaperRequest();
        r.documentType = 'bill';
        r.includeGst = true;
        r.customerName = 'Ramesh Kumar';
        r.customerPhone = '9000011111';
        r.registrationNumber = 'MP09AB1234';
        r.billToParty = new BillController.NewBillToPartyInput();
        r.billToParty.name = 'ICICI Lombard';
        r.billToParty.gstin = '23AAACI7904G1ZV';
        r.lineItems = job();
        r.lineItems[0].partId = bumper.Id;
        r.insuranceSplit = true;
        r.insurerPercents = new List<Decimal>{ 100, 50, 100 };
        r.compulsoryExcess = 590;
        return r;
    }

    @isTest
    static void easyBill_savesTwoPairedBills_thatAddUpToTheJob_takingStockOnce() {
        PaperBillController.PaperRequest r = claim();

        Test.startTest();
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(r);
        Test.stopTest();

        Bill__c insurer = [SELECT Total_Amount__c, Bill_To_Party__r.Name, Customer__r.Name, Paired_Bill__c, Vehicle__r.Name FROM Bill__c WHERE Id = :saved.recordId];
        Bill__c customer = [SELECT Total_Amount__c, Bill_To_Party__c, Customer__r.Name, Paired_Bill__c, Vehicle__r.Name FROM Bill__c WHERE Id = :saved.pairedRecordId];
        System.assertEquals(1770, insurer.Total_Amount__c);
        System.assertEquals(1180, customer.Total_Amount__c);
        System.assertEquals(2950, insurer.Total_Amount__c + customer.Total_Amount__c, 'The two add up to the job: 2500 + 18% GST.');
        System.assertEquals('ICICI Lombard', insurer.Bill_To_Party__r.Name);
        System.assertEquals('Ramesh Kumar', insurer.Customer__r.Name, 'The car owner is the buyer on the insurer\'s bill.');
        System.assertEquals(null, customer.Bill_To_Party__c);
        System.assertEquals('Ramesh Kumar', customer.Customer__r.Name);
        System.assertEquals(customer.Id, insurer.Paired_Bill__c);
        System.assertEquals(insurer.Id, customer.Paired_Bill__c);
        System.assertEquals('MP09AB1234', customer.Vehicle__r.Name);
        System.assertEquals(saved.pairedNumber, [SELECT Invoice_Number__c FROM Bill__c WHERE Id = :customer.Id].Invoice_Number__c);
        System.assertEquals(4, [SELECT Current_Stock__c FROM Part__c WHERE Name = 'Bumper'].Current_Stock__c, 'One bumper went out, not two.');
        System.assertEquals(0, partLinks(customer.Id));
        System.assertEquals(saved.pairedNumber, PaperBillController.getDocument(saved.recordId).pairedNumber, 'Opened in Easy Bill, each names the other.');
    }

    @isTest
    static void eachBillPrintsWhoPaysTheRest_andNamesTheOther() {
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(claim());
        Test.setCurrentPageReference(Page.InvoicePdf);

        Test.startTest();
        ApexPages.currentPage().getParameters().put('id', saved.recordId);
        InvoicePdfController insurerPdf = new InvoicePdfController();
        ApexPages.currentPage().getParameters().put('id', saved.pairedRecordId);
        InvoicePdfController customerPdf = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals('Customer pays', insurerPdf.discountLabel);
        System.assert(insurerPdf.pairedNote.contains(saved.pairedNumber), insurerPdf.pairedNote);
        System.assertEquals('Insurance pays', customerPdf.discountLabel);
        System.assert(customerPdf.pairedNote.contains(saved.documentNumber), customerPdf.pairedNote);
    }

    @isTest
    static void theGstReturn_countsTheGoodsOnce_inTheHsnSummary() {
        PaperBillController.PaperRequest r = claim();
        r.documentDate = Date.today().toStartOfMonth().addMonths(-1).addDays(2);
        PaperBillController.saveDocument(r);
        Date start = Date.today().toStartOfMonth().addMonths(-1);

        Test.startTest();
        GstReturnService.GstReturn ret = GstReturnService.build(null, start, GstFilingLock.monthEnd(start));
        Test.stopTest();

        Decimal quantity = 0;
        Decimal taxable = 0;
        for (GstReturnService.HsnRow row : ret.hsnB2b) {
            quantity += row.quantity;
            taxable += row.taxableValue;
        }
        for (GstReturnService.HsnRow row : ret.hsnB2c) {
            quantity += row.quantity;
            taxable += row.taxableValue;
        }
        System.assertEquals(3, quantity, 'Bumper, headlamp and labour once each.');
        System.assertEquals(2500, taxable, 'Both bills together are the whole job.');
        System.assertEquals(1, ret.b2b.size() > 0 ? 1 : 0, 'The insurer, registered, is B2B.');
    }

    @isTest
    static void changingTheCustomersBill_takesNoStock_andKeepsThePair() {
        PaperBillController.SavedDocument saved = PaperBillController.saveDocument(claim());
        BillController.CreateBillRequest change = new BillController.CreateBillRequest();
        change.customerId = [SELECT Customer__c FROM Bill__c WHERE Id = :saved.pairedRecordId].Customer__c;
        // A typed "Bumper" would match the part by name on any other bill.
        BillController.LineItemInput bumper = line('Bumper', 1, 1000);
        bumper.discount = 800;
        change.lineItems = new List<BillController.LineItemInput>{ bumper };

        Test.startTest();
        BillController.BillSummary changed = BillController.createNewVersion(saved.pairedRecordId, change);
        Test.stopTest();

        System.assertEquals(4, [SELECT Current_Stock__c FROM Part__c WHERE Name = 'Bumper'].Current_Stock__c, 'Still one bumper out.');
        System.assertEquals(0, partLinks(changed.billId));
        System.assertEquals(saved.recordId, changed.pairedBillId);
        System.assertEquals(changed.billId, [SELECT Paired_Bill__c FROM Bill__c WHERE Id = :saved.recordId].Paired_Bill__c, 'The insurer\'s bill points at the new version.');
    }

    @isTest
    static void aSplitNeedsAnInsurerACustomerAndANewBill() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
        PaperBillController.PaperRequest noParty = new PaperBillController.PaperRequest();
        noParty.documentType = 'bill';
        noParty.customerName = 'Ramesh';
        noParty.lineItems = job();
        noParty.insuranceSplit = true;
        noParty.insurerPercents = new List<Decimal>{ 100, 50, 100 };
        PaperBillController.PaperRequest asEstimate = noParty.clone();
        asEstimate.documentType = 'estimate';

        for (PaperBillController.PaperRequest bad : new List<PaperBillController.PaperRequest>{ noParty, asEstimate }) {
            try {
                PaperBillController.saveDocument(bad);
                System.assert(false, 'Expected the split to be refused.');
            } catch (PaperBillController.PaperBillControllerException e) {
                System.assert(e.getMessage().contains('insurance company') || e.getMessage().contains('new bill only'), e.getMessage());
            }
        }
        System.assertEquals(0, [SELECT COUNT() FROM Bill__c]);
    }
}
