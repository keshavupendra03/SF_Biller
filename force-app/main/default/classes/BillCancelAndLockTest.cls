/**
 * GST stage G2 (architecture.md §D.1): deleting a bill cancels it, and a
 * company's filed months can't be added to, changed or deleted from.
 */
@isTest
private class BillCancelAndLockTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', State__c = 'Madhya Pradesh');
        insert new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert new Part__c(Name = 'Engine Oil 1L', Price__c = 500, Tax_Rate_Percent__c = 18, Current_Stock__c = 10);
    }

    private static Date lastMonth() {
        return Date.today().toStartOfMonth().addDays(-10);
    }

    private static Date endOfLastMonth() {
        return Date.today().toStartOfMonth().addDays(-1);
    }

    private static BillController.CreateBillRequest request(Date billDate) {
        BillController.CreateBillRequest request = new BillController.CreateBillRequest();
        request.customerId = [SELECT Id FROM Customer__c LIMIT 1].Id;
        request.billDate = billDate;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.partId = [SELECT Id FROM Part__c LIMIT 1].Id;
        line.description = 'Engine Oil 1L';
        line.quantity = 2;
        line.unitPrice = 500;
        line.taxRatePercent = 18;
        request.lineItems = new List<BillController.LineItemInput>{ line };
        return request;
    }

    private static Decimal stock() {
        return [SELECT Current_Stock__c FROM Part__c LIMIT 1].Current_Stock__c;
    }

    private static void fileUpToLastMonth() {
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id, GST_Filed_Up_To__c = endOfLastMonth());
    }

    // ---- delete = cancel ---------------------------------------------------

    @isTest
    static void deletingABill_keepsItsNumber_returnsTheStock_andHidesIt() {
        BillController.BillSummary bill = BillController.createBill(request(Date.today()));
        System.assertEquals(8, stock());

        Test.startTest();
        BillController.BillSummary cancelled = BillController.cancelBill(bill.billId);
        Test.stopTest();

        System.assertEquals(true, cancelled.isCancelled);
        System.assertEquals(Date.today(), cancelled.cancelledOn);
        System.assertEquals(bill.invoiceNumber, [SELECT Invoice_Number__c FROM Bill__c WHERE Id = :bill.billId].Invoice_Number__c,
            'The number stays, to be reported as cancelled.');
        System.assertEquals(10, stock(), 'The parts go back to stock.');
        System.assertEquals(0, BillController.listBills('All', null, null).size());
        System.assertEquals(1, BillController.listBills('Cancelled', null, null).size());
        System.assertEquals(0, CustomerController.getCustomerDetail(cancelled.customerId).bills.size());
    }

    @isTest
    static void aDeletedBill_cannotBeDeletedAgain_orChanged() {
        BillController.BillSummary bill = BillController.createBill(request(Date.today()));
        BillController.cancelBill(bill.billId);

        Test.startTest();
        try {
            BillController.cancelBill(bill.billId);
            System.assert(false, 'Expected a second delete to be refused.');
        } catch (BillController.BillControllerException e) {
            System.assert(e.getMessage().contains('already deleted'), e.getMessage());
        }
        try {
            BillController.createNewVersion(bill.billId, request(Date.today()));
            System.assert(false, 'Expected a deleted bill not to take a new version.');
        } catch (BillController.BillControllerException e) {
            System.assert(e.getMessage().contains('was deleted'), e.getMessage());
        }
        Test.stopTest();
        System.assertEquals(10, stock(), 'Stock went back once only.');
    }

    @isTest
    static void onlyTheLatestVersion_canBeDeleted() {
        BillController.BillSummary first = BillController.createBill(request(Date.today()));
        BillController.BillSummary second = BillController.createNewVersion(first.billId, request(Date.today()));

        Test.startTest();
        try {
            BillController.cancelBill(first.billId);
            System.assert(false, 'Expected the replaced version to be refused.');
        } catch (BillController.BillControllerException e) {
            System.assert(e.getMessage().contains('changed since'), e.getMessage());
        }
        BillController.cancelBill(second.billId);
        Test.stopTest();

        System.assertEquals(10, stock(), 'Version 2 had taken the stock; deleting it puts it back.');
    }

    @isTest
    static void theDeletedBillPrintsAsCancelled() {
        BillController.BillSummary bill = BillController.createBill(request(Date.today()));
        BillController.cancelBill(bill.billId);
        Test.setCurrentPageReference(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', bill.billId);

        Test.startTest();
        InvoicePdfController controller = new InvoicePdfController();
        Test.stopTest();

        System.assertEquals(true, controller.isCancelled);
    }

    // ---- the month lock ----------------------------------------------------

    @isTest
    static void aFiledMonth_takesNoNewBill_butLaterDatesDo() {
        fileUpToLastMonth();

        Test.startTest();
        try {
            BillController.createBill(request(lastMonth()));
            System.assert(false, 'Expected a bill in a filed month to be refused.');
        } catch (ReadableErrors.ReadableException e) {
            System.assert(e.getMessage().contains('can\'t be added'), e.getMessage());
        }
        BillController.BillSummary today = BillController.createBill(request(Date.today()));
        Test.stopTest();

        System.assertNotEquals(null, today.invoiceNumber);
        System.assertEquals(1, [SELECT COUNT() FROM Bill__c]);
    }

    @isTest
    static void aBillInAFiledMonth_cannotBeDeletedOrChanged() {
        BillController.BillSummary bill = BillController.createBill(request(lastMonth()));
        fileUpToLastMonth();
        System.assertEquals(true, BillController.getBillSummary(bill.billId).isGstFiled);

        Test.startTest();
        try {
            BillController.cancelBill(bill.billId);
            System.assert(false, 'Expected deleting to be refused.');
        } catch (GstFilingLock.GstFilingLockException e) {
            System.assert(e.getMessage().contains('can\'t be deleted'), e.getMessage());
        }
        try {
            BillController.createNewVersion(bill.billId, request(Date.today()));
            System.assert(false, 'Expected changing to be refused.');
        } catch (GstFilingLock.GstFilingLockException e) {
            System.assert(e.getMessage().contains('can\'t be changed'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(false, [SELECT Is_Cancelled__c FROM Bill__c WHERE Id = :bill.billId].Is_Cancelled__c);
        System.assertEquals(8, stock(), 'Nothing moved.');
        System.assertEquals(1, [SELECT COUNT() FROM Bill__c]);
    }

    @isTest
    static void easyBill_seesAFiledOrDeletedBill_andWillNotChangeIt() {
        BillController.BillSummary filed = BillController.createBill(request(lastMonth()));
        BillController.BillSummary deleted = BillController.createBill(request(Date.today()));
        BillController.cancelBill(deleted.billId);
        fileUpToLastMonth();

        Test.startTest();
        PaperBillController.LoadedDocument filedDoc = PaperBillController.getDocument(filed.billId);
        PaperBillController.LoadedDocument deletedDoc = PaperBillController.getDocument(deleted.billId);
        PaperBillController.PaperRequest change = new PaperBillController.PaperRequest();
        change.previousVersionId = deleted.billId;
        change.lineItems = request(Date.today()).lineItems;
        try {
            PaperBillController.saveDocument(change);
            System.assert(false, 'Expected the deleted bill to be refused.');
        } catch (PaperBillController.PaperBillControllerException e) {
            System.assert(e.getMessage().contains('was deleted'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, filedDoc.isGstFiled);
        System.assertEquals(endOfLastMonth(), filedDoc.gstFiledUpTo);
        System.assertEquals(false, filedDoc.isCancelled);
        System.assertEquals(true, deletedDoc.isCancelled);
        System.assertEquals(false, deletedDoc.isGstFiled);
    }

    @isTest
    static void estimatesAreNeverLocked() {
        fileUpToLastMonth();
        EstimateController.CreateEstimateRequest estimate = new EstimateController.CreateEstimateRequest();
        estimate.customerId = [SELECT Id FROM Customer__c LIMIT 1].Id;
        estimate.estimateDate = lastMonth();
        estimate.lineItems = request(lastMonth()).lineItems;

        Test.startTest();
        EstimateController.EstimateSummary saved = EstimateController.createEstimate(estimate);
        Test.stopTest();

        System.assertNotEquals(null, saved.estimateId);
    }
}
