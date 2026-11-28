/**
 * A run that fails part way is undone completely (architecture.md, Forty-ninth):
 * records archived and emptied from the Recycle Bin come back, the archive
 * files written are gone, and the failure is kept for the Archive screen.
 */
@isTest
private class ArchiveJobFailureTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GST_Registration_Type__c = 'Unregistered', State__c = 'Madhya Pradesh');
        Customer__c c = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert c;
        Date old = Date.today().toStartOfMonth().addMonths(-24).addDays(3);
        insert new Job_Slip__c(Customer__c = c.Id, Slip_Date__c = old, Visit_Reason__c = 'Noise');
        Bill__c b = new Bill__c(Customer__c = c.Id, Bill_Date__c = old);
        insert b;
        TestLines.attach(b.Id, new List<BillController.LineItemInput>{ TestLines.line('Service', 1, 500, 0, 'CGST_SGST', '998714', null) });
    }

    @isTest
    static void aFailedRun_undoesEverything_andSaysWhy() {
        ArchiveJob.failForTest = true;

        Test.startTest();
        System.enqueueJob(new ArchiveJob(true));
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Job_Slip__c], 'The slip is back, though it was emptied from the bin.');
        System.assertEquals(1, [SELECT COUNT() FROM Bill__c], 'The bill is back.');
        System.assertEquals(0, ArchiveStore.files().size(), 'No archive file is left from the failed run.');
        System.assertEquals(null, [SELECT Invoice_Last_Numbers__c FROM Workshop_Profile__c].Invoice_Last_Numbers__c);
        String result = ArchiveSettings.current().lastResult;
        System.assert(result.startsWith('Archiving stopped: Test failure after archiving'), result);
    }

    @isTest
    static void aRunWithMoreToDo_carriesOnInTheNextStep() {
        // Two months of bills: the first step archives one and says more is ready.
        Customer__c c = [SELECT Id FROM Customer__c LIMIT 1];
        Bill__c later = new Bill__c(Customer__c = c.Id, Bill_Date__c = Date.today().toStartOfMonth().addMonths(-23).addDays(3));
        insert later;

        Test.startTest();
        System.enqueueJob(new ArchiveJob(true));
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Bill__c], 'One month a step; tests do not chain.');
        System.assert(ArchiveSettings.current().lastResult.contains('More is ready'), ArchiveSettings.current().lastResult);
    }
}
