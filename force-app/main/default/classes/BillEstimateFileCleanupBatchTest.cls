@isTest
private class BillEstimateFileCleanupBatchTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        return customer.Id;
    }

    private static Id insertFileFor(Id recordId, String title) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('test-pdf'),
            FirstPublishLocationId = recordId
        );
        insert version;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    @isTest
    static void execute_specificContentDocumentIds_deletesOnlyThoseDocuments() {
        Id customerId = insertCustomer();
        Bill__c bill = new Bill__c(Customer__c = customerId);
        insert bill;

        Id toDelete = insertFileFor(bill.Id, 'INV-0001');
        Id toKeep = insertFileFor(bill.Id, 'INV-0002');

        Test.startTest();
        Database.executeBatch(new BillEstimateFileCleanupBatch(new Set<Id>{ toDelete }));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :toDelete]);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :toKeep]);
    }

    @isTest
    static void noArgSweep_deletesOnlyYesterdaysBillAndEstimateFiles() {
        Id customerId = insertCustomer();
        Bill__c bill = new Bill__c(Customer__c = customerId);
        insert bill;
        Estimate__c estimate = new Estimate__c(Customer__c = customerId);
        insert estimate;

        Id oldBillFile = insertFileFor(bill.Id, 'Old Bill File');
        Id todayBillFile = insertFileFor(bill.Id, 'Today Bill File');
        Id oldEstimateFile = insertFileFor(estimate.Id, 'Old Estimate File');
        Id oldUnrelatedFile = insertFileFor(customerId, 'Old Customer File');

        Datetime yesterday = Datetime.now().addDays(-1);
        Test.setCreatedDate(oldBillFile, yesterday);
        Test.setCreatedDate(oldEstimateFile, yesterday);
        Test.setCreatedDate(oldUnrelatedFile, yesterday);
        // todayBillFile is left at its real (today) CreatedDate.

        Test.startTest();
        Database.executeBatch(new BillEstimateFileCleanupBatch());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :oldBillFile], 'Yesterday\'s bill file must be deleted.');
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :oldEstimateFile], 'Yesterday\'s estimate file must be deleted.');
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :todayBillFile], 'A file created today must survive the yesterday-only sweep.');
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :oldUnrelatedFile], 'A file not linked to a Bill/Estimate must never be touched by this batch.');
    }
}
