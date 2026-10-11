@isTest
private class BillEstimateFileCleanupSchedulerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    @isTest
    static void execute_runsTheCleanupBatch() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Bill__c bill = new Bill__c(Customer__c = customer.Id);
        insert bill;
        ContentVersion version = new ContentVersion(
            Title = 'Old Bill File',
            PathOnClient = 'Old Bill File.pdf',
            VersionData = Blob.valueOf('test-pdf'),
            FirstPublishLocationId = bill.Id
        );
        insert version;
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
        Test.setCreatedDate(contentDocumentId, Datetime.now().addDays(-1));

        // System.schedule's own cron firing isn't simulated by
        // Test.stopTest() the way future/queueable/batch jobs are, so the
        // scheduler's execute() is called directly here — the standard
        // way to test a Schedulable's actual logic. canBeScheduled below
        // separately proves System.schedule itself accepts this class.
        Test.startTest();
        new BillEstimateFileCleanupScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :contentDocumentId]);
    }

    @isTest
    static void canBeScheduled_registersACronJob() {
        Test.startTest();
        String jobId = System.schedule(
            'Bill/Estimate File Cleanup Test',
            '0 0 2 * * ?',
            new BillEstimateFileCleanupScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId]);
    }
}
