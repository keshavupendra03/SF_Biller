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
        input.gstin = 'FDJSG23575HFH';
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
}
