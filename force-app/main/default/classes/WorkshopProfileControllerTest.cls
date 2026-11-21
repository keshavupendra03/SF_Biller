@isTest
private class WorkshopProfileControllerTest {

    @isTest
    static void getProfile_noRecordExists_returnsNull() {
        Test.startTest();
        WorkshopProfileController.ProfileData data = WorkshopProfileController.getProfile();
        Test.stopTest();

        System.assertEquals(null, data);
    }

    @isTest
    static void saveProfile_noExistingRecord_insertsOne() {
        WorkshopProfileController.ProfileData input = new WorkshopProfileController.ProfileData();
        input.name = 'Keshav Car WS';
        input.phone = '6268471199';
        input.gstin = '23FDJSG2357H1ZH';
        input.bankName = 'Bank of Baroda';

        Test.startTest();
        WorkshopProfileController.ProfileData saved = WorkshopProfileController.saveProfile(input);
        Test.stopTest();

        System.assertEquals('Keshav Car WS', saved.name);
        System.assertEquals(1, [SELECT COUNT() FROM Workshop_Profile__c]);
    }

    @isTest
    static void saveProfile_existingRecord_updatesInPlaceRatherThanCreatingASecondOne() {
        Workshop_Profile__c existing = new Workshop_Profile__c(Name = 'Original Name');
        insert existing;

        WorkshopProfileController.ProfileData input = new WorkshopProfileController.ProfileData();
        input.name = 'Updated Name';
        input.phone = '9999999999';

        Test.startTest();
        WorkshopProfileController.saveProfile(input);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Workshop_Profile__c], 'Must never create a second singleton record.');
        Workshop_Profile__c updated = [SELECT Name, Phone__c FROM Workshop_Profile__c WHERE Id = :existing.Id];
        System.assertEquals('Updated Name', updated.Name);
    }

    @isTest
    static void saveProfile_missingName_throws() {
        WorkshopProfileController.ProfileData input = new WorkshopProfileController.ProfileData();

        Boolean threw = false;
        try {
            WorkshopProfileController.saveProfile(input);
        } catch (WorkshopProfileController.WorkshopProfileControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void saveProfile_roundTripsJobSlipTerms() {
        WorkshopProfileController.ProfileData input = new WorkshopProfileController.ProfileData();
        input.name = 'Keshav Car WS';
        input.jobSlipTerms = 'Vehicles are kept at owner risk.';

        Test.startTest();
        WorkshopProfileController.saveProfile(input);
        WorkshopProfileController.ProfileData loaded = WorkshopProfileController.getProfile();
        Test.stopTest();

        System.assertEquals('Vehicles are kept at owner risk.', loaded.jobSlipTerms);
    }

    @isTest
    static void gstSettings_defaultToRegularMonthly_saveWhenSent_andBlankKeepsThem() {
        WorkshopProfileController.ProfileData input = new WorkshopProfileController.ProfileData();
        input.name = 'Keshav Car WS';
        WorkshopProfileController.ProfileData saved = WorkshopProfileController.saveProfile(input);
        System.assertEquals('Regular', saved.gstRegistrationType);
        System.assertEquals('Monthly', saved.gstFilingFrequency);

        input.id = saved.id;
        input.gstRegistrationType = 'Composition';
        input.gstFilingFrequency = 'Quarterly';
        WorkshopProfileController.saveProfile(input);

        Test.startTest();
        input.gstRegistrationType = null;
        input.gstFilingFrequency = '';
        WorkshopProfileController.ProfileData after = WorkshopProfileController.saveProfile(input);
        Test.stopTest();

        System.assertEquals('Composition', after.gstRegistrationType, 'A screen that doesn\'t show it mustn\'t clear it.');
        System.assertEquals('Quarterly', after.gstFilingFrequency);
    }

    @isTest
    static void aWrongGstin_isRefused_withItsOwnMessage() {
        WorkshopProfileController.ProfileData input = new WorkshopProfileController.ProfileData();
        input.name = 'Keshav Car WS';
        input.gstin = 'kjhsdj090';

        Test.startTest();
        try {
            WorkshopProfileController.saveProfile(input);
            System.assert(false, 'Expected the GSTIN to be refused.');
        } catch (WorkshopProfileController.WorkshopProfileControllerException e) {
            System.assert(e.getMessage().contains('KJHSDJ090 is not a valid GSTIN'), e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void gstFiledUpTo_isAMonthEnd_onlyForAMonthThatIsOver_andOnlyChangedOnPurpose() {
        Workshop_Profile__c company = new Workshop_Profile__c(Name = 'Keshav Car WS');
        insert company;
        Date midLastMonth = Date.today().toStartOfMonth().addDays(-10);

        WorkshopProfileController.ProfileData filed = WorkshopProfileController.setGstFiledUpTo(company.Id, midLastMonth);
        System.assertEquals(Date.today().toStartOfMonth().addDays(-1), filed.gstFiledUpTo, 'Stored as the month\'s last day.');

        try {
            WorkshopProfileController.setGstFiledUpTo(company.Id, Date.today());
            System.assert(false, 'Expected this month to be refused.');
        } catch (WorkshopProfileController.WorkshopProfileControllerException e) {
            System.assert(e.getMessage().contains('until the month is over'), e.getMessage());
        }

        Test.startTest();
        WorkshopProfileController.ProfileData other = new WorkshopProfileController.ProfileData();
        other.id = company.Id;
        other.name = 'Keshav Car Workshop';
        WorkshopProfileController.ProfileData saved = WorkshopProfileController.saveProfile(other);
        Test.stopTest();

        System.assertEquals(filed.gstFiledUpTo, saved.gstFiledUpTo, 'Saving other details never moves it.');
        System.assertEquals(null, WorkshopProfileController.setGstFiledUpTo(company.Id, null).gstFiledUpTo, 'Blank unlocks.');
    }
}
