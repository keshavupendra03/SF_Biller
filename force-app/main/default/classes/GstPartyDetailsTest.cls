@isTest
private class GstPartyDetailsTest {

    private static Id fakeId(Schema.SObjectType type) {
        return Id.valueOf(type.getDescribe().getKeyPrefix() + '000000000001');
    }

    @isTest
    static void aCustomerState_isStoredAsItsName() {
        Customer__c customer = new Customer__c(Name = 'Ramesh', Phone__c = '9000011111', State__c = 'mp');

        Test.startTest();
        insert customer;
        Test.stopTest();

        System.assertEquals('Madhya Pradesh', [SELECT State__c FROM Customer__c WHERE Id = :customer.Id].State__c);
    }

    @isTest
    static void aGstin_isTidied_andFillsABlankState() {
        Customer__c customer = new Customer__c(Name = 'Sharma Traders', Phone__c = '9000011111', GSTIN__c = ' 27aapfu0939f1zv ');

        Test.startTest();
        insert customer;
        Test.stopTest();

        Customer__c saved = [SELECT GSTIN__c, State__c FROM Customer__c WHERE Id = :customer.Id];
        System.assertEquals('27AAPFU0939F1ZV', saved.GSTIN__c);
        System.assertEquals('Maharashtra', saved.State__c);
    }

    @isTest
    static void aStateTypedAlongsideAGstin_isKept() {
        Customer__c customer = new Customer__c(
            Name = 'Sharma Traders', Phone__c = '9000011111', GSTIN__c = '27AAPFU0939F1ZV', State__c = 'Goa'
        );

        Test.startTest();
        insert customer;
        Test.stopTest();

        System.assertEquals('Goa', [SELECT State__c FROM Customer__c WHERE Id = :customer.Id].State__c,
            'The buyer said where; a mismatch is for the GST checkup to show, not to overwrite.');
    }

    @isTest
    static void aWrongGstin_isRefused_withItsOwnMessage() {
        Customer__c customer = new Customer__c(Name = 'Sharma Traders', Phone__c = '9000011111', GSTIN__c = '27AAPFU0939F1ZW');

        Test.startTest();
        Database.SaveResult result = Database.insert(customer, false);
        Test.stopTest();

        System.assert(!result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('27AAPFU0939F1ZW is not a valid GSTIN'), result.getErrors()[0].getMessage());
    }

    @isTest
    static void aStateThatIsNotAState_isRefused() {
        Customer__c customer = new Customer__c(Name = 'Ramesh', Phone__c = '9000011111', State__c = 'Ujjain');

        Test.startTest();
        Database.SaveResult result = Database.insert(customer, false);
        Test.stopTest();

        System.assert(!result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('"Ujjain" is not an Indian state'), result.getErrors()[0].getMessage());
    }

    @isTest
    static void anOldBadValue_doesNotBlockOtherChanges() {
        Id id = fakeId(Workshop_Profile__c.SObjectType);
        Workshop_Profile__c before = new Workshop_Profile__c(Id = id, GSTIN__c = 'kjhsdj090', State__c = 'Ujjain');
        Workshop_Profile__c after = new Workshop_Profile__c(Id = id, GSTIN__c = 'kjhsdj090', State__c = 'Ujjain', Phone__c = '9000000000');

        GstPartyDetails.apply(new List<SObject>{ after }, new Map<Id, SObject>{ id => before });

        System.assert(!after.hasErrors(), 'The invoice counter updates this row on every bill: it must not be blocked.');
        System.assertEquals('kjhsdj090', after.GSTIN__c);
    }

    @isTest
    static void changingAnOldBadGstin_isChecked() {
        Id id = fakeId(Workshop_Profile__c.SObjectType);
        Workshop_Profile__c before = new Workshop_Profile__c(Id = id, GSTIN__c = 'kjhsdj090');
        Workshop_Profile__c fixedTypo = new Workshop_Profile__c(Id = id, GSTIN__c = 'kjhsdj091');
        Workshop_Profile__c fixedProperly = new Workshop_Profile__c(Id = id, GSTIN__c = '23aaaci7904g1zv');

        GstPartyDetails.apply(new List<SObject>{ fixedTypo }, new Map<Id, SObject>{ id => before });
        GstPartyDetails.apply(new List<SObject>{ fixedProperly }, new Map<Id, SObject>{ id => before });

        System.assert(fixedTypo.hasErrors());
        System.assert(!fixedProperly.hasErrors());
        System.assertEquals('23AAACI7904G1ZV', fixedProperly.GSTIN__c);
        System.assertEquals('Madhya Pradesh', fixedProperly.State__c);
    }

    @isTest
    static void clearingAState_orGstin_isAllowed() {
        Id id = fakeId(Customer__c.SObjectType);
        Customer__c before = new Customer__c(Id = id, GSTIN__c = '23AAACI7904G1ZV', State__c = 'Madhya Pradesh');
        Customer__c after = new Customer__c(Id = id, GSTIN__c = '', State__c = ' ');

        GstPartyDetails.apply(new List<SObject>{ after }, new Map<Id, SObject>{ id => before });

        System.assert(!after.hasErrors());
        System.assertEquals(null, after.GSTIN__c);
        System.assertEquals(null, after.State__c);
    }

    @isTest
    static void partiesAndCompanies_areCheckedToo() {
        Bill_To_Party__c party = new Bill_To_Party__c(Name = 'ICICI Lombard', GSTIN__c = '23aaaci7904g1zv');
        Workshop_Profile__c company = new Workshop_Profile__c(Name = 'Speedy Motors', State__c = '23-MP');

        Test.startTest();
        insert party;
        insert company;
        Database.SaveResult badParty = Database.insert(new Bill_To_Party__c(Name = 'Bad', GSTIN__c = 'ABC'), false);
        Test.stopTest();

        System.assertEquals('Madhya Pradesh', [SELECT State__c FROM Bill_To_Party__c WHERE Id = :party.Id].State__c);
        System.assertEquals('Madhya Pradesh', [SELECT State__c FROM Workshop_Profile__c WHERE Id = :company.Id].State__c);
        System.assert(!badParty.isSuccess());
    }

    @isTest
    static void screens_showTheMessage_notAnUnreadableSaveError() {
        BillController.NewBillToPartyInput input = new BillController.NewBillToPartyInput();
        input.name = 'Sharma Transport';
        input.gstin = '23AAACI7904G1ZX';

        Test.startTest();
        try {
            DirectoryController.createBillToParty(input);
            System.assert(false, 'Expected the GSTIN to be refused.');
        } catch (ReadableErrors.ReadableException e) {
            System.assert(e.getMessage().contains('23AAACI7904G1ZX is not a valid GSTIN'), e.getMessage());
        }
        Test.stopTest();
    }
}
