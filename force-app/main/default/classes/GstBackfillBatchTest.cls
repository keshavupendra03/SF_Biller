@isTest
private class GstBackfillBatchTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', State__c = 'Madhya Pradesh');
    }

    private static Id fakeId(Schema.SObjectType type, Integer n) {
        return Id.valueOf(type.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0'));
    }

    @isTest
    static void tidyDetails_namesStates_tidiesGstins_andLeavesWhatItCannotFix() {
        List<SObject> records = new List<SObject>{
            new Customer__c(Id = fakeId(Customer__c.SObjectType, 1), State__c = 'Madhyapradesh'),
            new Customer__c(Id = fakeId(Customer__c.SObjectType, 2), State__c = 'MP', GSTIN__c = '27aapfu0939f1zv'),
            new Customer__c(Id = fakeId(Customer__c.SObjectType, 3), GSTIN__c = '23AAACI7904G1ZV'),
            new Customer__c(Id = fakeId(Customer__c.SObjectType, 4), State__c = 'Ujjain', GSTIN__c = 'kjhsdj090'),
            new Customer__c(Id = fakeId(Customer__c.SObjectType, 5), State__c = 'Madhya Pradesh', GSTIN__c = '23AAACI7904G1ZV')
        };

        Map<Id, SObject> changes = new Map<Id, SObject>(GstBackfillBatch.tidyDetails(records));

        System.assertEquals(3, changes.size(), 'An unknown state, a bad GSTIN and a tidy record are left alone.');
        System.assertEquals('Madhya Pradesh', changes.get(records[0].Id).get('State__c'));
        System.assertEquals('Madhya Pradesh', changes.get(records[1].Id).get('State__c'), 'A typed state is kept, not replaced by the GSTIN\'s.');
        System.assertEquals('27AAPFU0939F1ZV', changes.get(records[1].Id).get('GSTIN__c'));
        System.assertEquals('Madhya Pradesh', changes.get(records[2].Id).get('State__c'), 'A blank state comes from the GSTIN.');
        System.assert(!changes.containsKey(records[3].Id));
        System.assert(!changes.containsKey(records[4].Id));
    }

    @isTest
    static void billsStep_givesOlderBillsTheirSequence_buyerGstin_andPlaceOfSupply() {
        Customer__c customer = new Customer__c(Name = 'Sharma Traders', Phone__c = '9000011111', GSTIN__c = '27AAPFU0939F1ZV');
        insert customer;
        Bill__c bill = new Bill__c(Customer__c = customer.Id);
        insert bill;
        // As a bill saved before these fields existed.
        update new Bill__c(Id = bill.Id, Invoice_Sequence__c = null, Recipient_GSTIN__c = null, Place_Of_Supply__c = null);

        Test.startTest();
        Database.executeBatch(new GstBackfillBatch(3), 200);
        Test.stopTest();

        Bill__c tidied = [SELECT Invoice_Number__c, Invoice_Sequence__c, Recipient_GSTIN__c, Place_Of_Supply__c FROM Bill__c WHERE Id = :bill.Id];
        System.assertEquals(InvoiceNumberingService.sequenceOf(tidied.Invoice_Number__c), tidied.Invoice_Sequence__c);
        System.assertEquals('27AAPFU0939F1ZV', tidied.Recipient_GSTIN__c);
        System.assertEquals('27', tidied.Place_Of_Supply__c);
    }

    @isTest
    static void detailsStep_savesWhatItTidied() {
        Customer__c customer = new Customer__c(Name = 'Ramesh', Phone__c = '9000011111', State__c = 'Madhya Pradesh');
        insert customer;

        Test.startTest();
        Database.executeBatch(new GstBackfillBatch(), 200);
        Test.stopTest();

        System.assertEquals('Madhya Pradesh', [SELECT State__c FROM Customer__c WHERE Id = :customer.Id].State__c);
    }
}
