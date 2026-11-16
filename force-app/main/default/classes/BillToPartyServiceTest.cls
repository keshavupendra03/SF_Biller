@isTest
private class BillToPartyServiceTest {

    private static BillController.NewBillToPartyInput typed(String name) {
        BillController.NewBillToPartyInput input = new BillController.NewBillToPartyInput();
        input.name = name;
        return input;
    }

    private static Bill_To_Party__c insertIcici() {
        Bill_To_Party__c party = new Bill_To_Party__c(
            Name = 'ICICI Lombard', Address__c = 'MG Road, Indore', GSTIN__c = '23AAACI7904G1ZV', State__c = 'Madhya Pradesh'
        );
        insert party;
        return party;
    }

    @isTest
    static void nothingPickedOrTyped_meansNoParty() {
        Test.startTest();
        System.assertEquals(null, BillToPartyService.resolve(null, null, true));
        System.assertEquals(null, BillToPartyService.resolve(null, typed('   '), false));
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Bill_To_Party__c]);
    }

    @isTest
    static void aNewName_savesANewParty_forNextTime() {
        BillController.NewBillToPartyInput input = typed('  Sharma Transport  ');
        input.address = 'Nanakheda, Ujjain';
        input.contactPhone = '9827012345';
        input.gstin = '23ABCDE1234F1Z5';
        input.state = 'Madhya Pradesh';

        Test.startTest();
        Id partyId = BillToPartyService.resolve(null, input, false);
        Test.stopTest();

        Bill_To_Party__c saved = [SELECT Name, Address__c, Contact_Phone__c, GSTIN__c, State__c FROM Bill_To_Party__c WHERE Id = :partyId];
        System.assertEquals('Sharma Transport', saved.Name);
        System.assertEquals('Nanakheda, Ujjain', saved.Address__c);
        System.assertEquals('9827012345', saved.Contact_Phone__c);
        System.assertEquals('23ABCDE1234F1Z5', saved.GSTIN__c);
        System.assertEquals('Madhya Pradesh', saved.State__c);
    }

    @isTest
    static void aTypedSavedName_isThatParty_ignoringCase() {
        Bill_To_Party__c icici = insertIcici();

        Test.startTest();
        Id partyId = BillToPartyService.resolve(null, typed('icici lombard'), false);
        Test.stopTest();

        System.assertEquals(icici.Id, partyId);
        System.assertEquals(1, [SELECT COUNT() FROM Bill_To_Party__c], 'Typing a saved name again must not make a second copy.');
    }

    @isTest
    static void quickBill_typedSavedName_onlyFillsWhatThePartyIsMissing() {
        Bill_To_Party__c icici = insertIcici();
        BillController.NewBillToPartyInput input = typed('ICICI Lombard');
        input.address = 'Somewhere else';
        input.contactPhone = '9000000001';

        Test.startTest();
        BillToPartyService.resolve(null, input, false);
        Test.stopTest();

        Bill_To_Party__c saved = [SELECT Address__c, Contact_Phone__c, GSTIN__c FROM Bill_To_Party__c WHERE Id = :icici.Id];
        System.assertEquals('MG Road, Indore', saved.Address__c, 'A quick entry never overwrites saved details.');
        System.assertEquals('9000000001', saved.Contact_Phone__c, 'A missing detail is filled in.');
        System.assertEquals('23AAACI7904G1ZV', saved.GSTIN__c);
    }

    @isTest
    static void easyBill_typedSavedName_replacesWithTypedDetails_butBlanksKeepSaved() {
        Bill_To_Party__c icici = insertIcici();
        BillController.NewBillToPartyInput input = typed('ICICI Lombard');
        input.address = 'Vijay Nagar, Indore';

        Test.startTest();
        BillToPartyService.resolve(null, input, true);
        Test.stopTest();

        Bill_To_Party__c saved = [SELECT Address__c, GSTIN__c FROM Bill_To_Party__c WHERE Id = :icici.Id];
        System.assertEquals('Vijay Nagar, Indore', saved.Address__c);
        System.assertEquals('23AAACI7904G1ZV', saved.GSTIN__c, 'A box left blank keeps what was saved.');
    }

    @isTest
    static void easyBill_pickedParty_takesThePage_blanksIncluded() {
        Bill_To_Party__c icici = insertIcici();
        BillController.NewBillToPartyInput input = typed('ICICI Lombard GIC');
        input.address = 'Vijay Nagar, Indore';
        input.gstin = '23AAACI7904G1ZV';

        Test.startTest();
        Id partyId = BillToPartyService.resolve(icici.Id, input, true);
        Test.stopTest();

        System.assertEquals(icici.Id, partyId);
        Bill_To_Party__c saved = [SELECT Name, Address__c, State__c FROM Bill_To_Party__c WHERE Id = :icici.Id];
        System.assertEquals('ICICI Lombard GIC', saved.Name);
        System.assertEquals('Vijay Nagar, Indore', saved.Address__c);
        System.assertEquals(null, saved.State__c, 'The bill prints the record, so a box cleared on the page is cleared on it.');
    }

    @isTest
    static void quickBill_pickedParty_isLeftAsSaved() {
        Bill_To_Party__c icici = insertIcici();
        BillController.NewBillToPartyInput input = typed('Something else');

        Test.startTest();
        Id partyId = BillToPartyService.resolve(icici.Id, input, false);
        Test.stopTest();

        System.assertEquals(icici.Id, partyId);
        System.assertEquals('ICICI Lombard', [SELECT Name FROM Bill_To_Party__c WHERE Id = :icici.Id].Name);
    }

    @isTest
    static void aGstinLongerThan15_isRefusedWithAPlainMessage() {
        BillController.NewBillToPartyInput input = typed('Sharma Transport');
        input.gstin = '23ABCDE1234F1Z5X';

        Test.startTest();
        try {
            BillToPartyService.resolve(null, input, true);
            System.assert(false, 'Expected the long GSTIN to be refused.');
        } catch (BillToPartyService.BillToPartyServiceException e) {
            System.assert(e.getMessage().contains('15 characters'), e.getMessage());
        }
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Bill_To_Party__c]);
    }
}
