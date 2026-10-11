@isTest
private class DirectoryControllerTest {

    @isTest
    static void listMechanics_defaultExcludesInactive() {
        insert new Mechanic__c(Name = 'Active Mechanic', Is_Active__c = true);
        insert new Mechanic__c(Name = 'Inactive Mechanic', Is_Active__c = false);

        Test.startTest();
        List<DirectoryController.PersonItem> activeOnly = DirectoryController.listMechanics(false);
        List<DirectoryController.PersonItem> all = DirectoryController.listMechanics(true);
        Test.stopTest();

        System.assertEquals(1, activeOnly.size());
        System.assertEquals(2, all.size());
    }

    @isTest
    static void createMechanic_insertsActiveRecord() {
        Test.startTest();
        DirectoryController.PersonItem item = DirectoryController.createMechanic('Suresh', '9000011111');
        Test.stopTest();

        System.assertEquals('Suresh', item.name);
        System.assertEquals(true, item.isActive);
    }

    @isTest
    static void setMechanicActive_togglesFlag() {
        Mechanic__c m = new Mechanic__c(Name = 'Suresh', Is_Active__c = true);
        insert m;

        Test.startTest();
        DirectoryController.setMechanicActive(m.Id, false);
        Test.stopTest();

        System.assertEquals(false, [SELECT Is_Active__c FROM Mechanic__c WHERE Id = :m.Id].Is_Active__c);
    }

    @isTest
    static void listSurveyors_defaultExcludesInactive() {
        insert new Surveyor__c(Name = 'Active Surveyor', Is_Active__c = true);
        insert new Surveyor__c(Name = 'Inactive Surveyor', Is_Active__c = false);

        Test.startTest();
        List<DirectoryController.PersonItem> activeOnly = DirectoryController.listSurveyors(false);
        Test.stopTest();

        System.assertEquals(1, activeOnly.size());
    }

    @isTest
    static void createSurveyor_insertsActiveRecord() {
        Test.startTest();
        DirectoryController.PersonItem item = DirectoryController.createSurveyor('Bhaiyo Jio', '9131360083');
        Test.stopTest();

        System.assertEquals('Bhaiyo Jio', item.name);
    }

    @isTest
    static void setSurveyorActive_togglesFlag() {
        Surveyor__c s = new Surveyor__c(Name = 'Bhaiyo Jio', Is_Active__c = true);
        insert s;

        Test.startTest();
        DirectoryController.setSurveyorActive(s.Id, false);
        Test.stopTest();

        System.assertEquals(false, [SELECT Is_Active__c FROM Surveyor__c WHERE Id = :s.Id].Is_Active__c);
    }

    @isTest
    static void listBillToParties_filtersByNameOrGstin() {
        insert new Bill_To_Party__c(Name = 'Aakash Siroliya', GSTIN__c = 'BZJGZ1234F1Z5');
        insert new Bill_To_Party__c(Name = 'Other Party', GSTIN__c = 'AAAAA0000A1Z5');

        Test.startTest();
        List<DirectoryController.BillToPartyItem> results = DirectoryController.listBillToParties('Aakash');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Aakash Siroliya', results[0].name);
    }

    @isTest
    static void createBillToParty_insertsRecord() {
        BillController.NewBillToPartyInput input = new BillController.NewBillToPartyInput();
        input.name = 'Acme Logistics';
        input.gstin = 'AAAAA0000A1Z5';

        Test.startTest();
        DirectoryController.BillToPartyItem item = DirectoryController.createBillToParty(input);
        Test.stopTest();

        System.assertEquals('Acme Logistics', item.name);
        System.assertEquals(1, [SELECT COUNT() FROM Bill_To_Party__c]);
    }

    @isTest
    static void createBillToParty_missingName_throws() {
        BillController.NewBillToPartyInput input = new BillController.NewBillToPartyInput();

        Boolean threw = false;
        try {
            DirectoryController.createBillToParty(input);
        } catch (DirectoryController.DirectoryControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void updateBillToParty_updatesFields() {
        Bill_To_Party__c party = new Bill_To_Party__c(Name = 'Acme Logistics');
        insert party;

        BillController.NewBillToPartyInput input = new BillController.NewBillToPartyInput();
        input.name = 'Acme Logistics Pvt Ltd';
        input.gstin = 'AAAAA0000A1Z5';

        Test.startTest();
        DirectoryController.updateBillToParty(party.Id, input);
        Test.stopTest();

        Bill_To_Party__c updated = [SELECT Name, GSTIN__c FROM Bill_To_Party__c WHERE Id = :party.Id];
        System.assertEquals('Acme Logistics Pvt Ltd', updated.Name);
        System.assertEquals('AAAAA0000A1Z5', updated.GSTIN__c);
    }
}
