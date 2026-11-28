@isTest
private class ArchiveControllerTest {

    private static Date oldDay() {
        return Date.today().toStartOfMonth().addMonths(-24).addDays(9);
    }

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GST_Registration_Type__c = 'Unregistered');
        Customer__c c = new Customer__c(Name = 'Sharma Traders', Phone__c = '9876501234');
        insert c;
        insert new Vehicle__c(Name = 'MP09AB1234', Customer__c = c.Id);
    }

    private static BillController.BillSummary oldBill() {
        Customer__c c = [SELECT Id FROM Customer__c LIMIT 1];
        BillController.CreateBillRequest r = new BillController.CreateBillRequest();
        r.customerId = c.Id;
        r.vehicleId = [SELECT Id FROM Vehicle__c LIMIT 1].Id;
        r.billDate = oldDay();
        r.lineItems = new List<BillController.LineItemInput>{ TestLines.line('Clutch plate', 2, 1500, 18, 'CGST_SGST', '8708', 'Pcs') };
        return BillController.createBill(r);
    }

    @isTest
    static void status_showsWhatIsReady_andSavingRulesChangesIt() {
        oldBill();

        Test.startTest();
        ArchiveController.Status before = ArchiveController.getStatus();
        ArchiveSettings.Rules r = before.rules;
        r.billsAfterMonths = 36;
        ArchiveController.Status after = ArchiveController.saveRules(r);
        Test.stopTest();

        System.assertEquals(1, before.billsReady);
        System.assertEquals(1, before.billMonthsReady.size());
        System.assertEquals(0, before.archiveFiles);
        System.assertEquals(null, before.downloadUrl);
        System.assertEquals(0, after.billsReady, 'Not old enough for 36 months.');
    }

    @isTest
    static void runNow_archives_andOldBillsCanBeFoundOpenedAndBroughtBack() {
        BillController.BillSummary b = oldBill();
        Test.startTest();
        ArchiveController.runNow();
        Test.stopTest();

        List<ArchiveController.ArchivedBillRow> byPhone = ArchiveController.searchBills('98765');
        List<ArchiveController.ArchivedBillRow> byVehicle = ArchiveController.searchBills('mp09 ab');
        List<ArchiveController.ArchivedBillRow> none = ArchiveController.searchBills('nobody');
        System.assertEquals(1, byPhone.size());
        System.assertEquals(1, byVehicle.size(), 'Spaces in a car number don\'t matter.');
        System.assertEquals(0, none.size());
        System.assertEquals(b.invoiceNumber, byPhone[0].invoiceNumber);

        ArchiveController.ArchivedBill view = ArchiveController.getArchivedBill(byPhone[0].documentId, byPhone[0].billId);
        System.assertEquals('Sharma Traders', view.customerName);
        System.assertEquals('MP09AB1234', view.vehicle);
        System.assertEquals(1, view.lineItems.size());
        System.assertEquals(3000, view.totalAmount, 'A company without GST charges none.');
        System.assertEquals(0, view.cgst);

        ArchiveController.Status status = ArchiveController.getStatus();
        System.assertEquals(1, status.archivedBills);
        System.assert(status.downloadUrl.startsWith('/sfc/servlet.shepherd/document/download/'), status.downloadUrl);

        Id back = ArchiveController.restoreBill(byPhone[0].billId);
        System.assertEquals(b.invoiceNumber, [SELECT Invoice_Number__c FROM Bill__c WHERE Id = :back].Invoice_Number__c);
        System.assertEquals(0, ArchiveController.searchBills('').size());
    }

    @isTest
    static void mistakes_comeBackInWords() {
        List<String> messages = new List<String>();
        ArchiveSettings.Rules r = ArchiveSettings.current();
        r.storageAlertPercent = 5;
        try { ArchiveController.saveRules(r); } catch (ArchiveController.ArchiveControllerException e) { messages.add(e.getMessage()); }
        try { ArchiveController.restoreBill(oldBill().billId); } catch (ArchiveController.ArchiveControllerException e) { messages.add(e.getMessage()); }
        System.assertEquals(new List<String>{
            'The storage warning must be between 10% and 100%.',
            'That bill is not in the archive, or was already brought back.'
        }, messages);
    }
}
