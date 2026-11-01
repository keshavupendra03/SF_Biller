/**
 * Workshop_Profile__c is a singleton — exactly one record holds the
 * workshop's own details (name, GSTIN, bank account) shown as the "Pay To"
 * block on every invoice PDF (InvoicePdfController already reads it the
 * same way). saveProfile finds-or-creates that one record rather than
 * exposing a generic CRUD surface, since there is never a second one.
 */
public with sharing class WorkshopProfileController {

    public class WorkshopProfileControllerException extends Exception {}

    public class ProfileData {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String gstin { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String bankAccountHolder { get; set; }
        @AuraEnabled public String bankName { get; set; }
        @AuraEnabled public String bankAccountNo { get; set; }
        @AuraEnabled public String bankIfsc { get; set; }
        @AuraEnabled public String termsAndConditions { get; set; }
        @AuraEnabled public String jobSlipTerms { get; set; }
    }

    @AuraEnabled
    public static ProfileData getProfile() {
        List<Workshop_Profile__c> records = [
            SELECT Name, Address__c, Phone__c, Email__c, GSTIN__c, State__c,
                   Bank_Account_Holder__c, Bank_Name__c, Bank_Account_No__c, Bank_IFSC__c,
                   Terms_And_Conditions__c, Job_Slip_Terms__c
            FROM Workshop_Profile__c
            LIMIT 1
        ];
        if (records.isEmpty()) {
            return null;
        }
        return toProfileData(records[0]);
    }

    @AuraEnabled
    public static ProfileData saveProfile(ProfileData input) {
        if (input == null || String.isBlank(input.name)) {
            throw new WorkshopProfileControllerException('A workshop name is required.');
        }

        List<Workshop_Profile__c> existing = [SELECT Id FROM Workshop_Profile__c LIMIT 1];
        Workshop_Profile__c profile = existing.isEmpty()
            ? new Workshop_Profile__c()
            : new Workshop_Profile__c(Id = existing[0].Id);

        profile.Name = input.name;
        profile.Address__c = input.address;
        profile.Phone__c = input.phone;
        profile.Email__c = input.email;
        profile.GSTIN__c = input.gstin;
        profile.State__c = input.state;
        profile.Bank_Account_Holder__c = input.bankAccountHolder;
        profile.Bank_Name__c = input.bankName;
        profile.Bank_Account_No__c = input.bankAccountNo;
        profile.Bank_IFSC__c = input.bankIfsc;
        profile.Terms_And_Conditions__c = input.termsAndConditions;
        profile.Job_Slip_Terms__c = input.jobSlipTerms;

        upsert profile;

        return toProfileData([
            SELECT Name, Address__c, Phone__c, Email__c, GSTIN__c, State__c,
                   Bank_Account_Holder__c, Bank_Name__c, Bank_Account_No__c, Bank_IFSC__c,
                   Terms_And_Conditions__c, Job_Slip_Terms__c
            FROM Workshop_Profile__c
            WHERE Id = :profile.Id
        ]);
    }

    private static ProfileData toProfileData(Workshop_Profile__c p) {
        ProfileData data = new ProfileData();
        data.id = p.Id;
        data.name = p.Name;
        data.address = p.Address__c;
        data.phone = p.Phone__c;
        data.email = p.Email__c;
        data.gstin = p.GSTIN__c;
        data.state = p.State__c;
        data.bankAccountHolder = p.Bank_Account_Holder__c;
        data.bankName = p.Bank_Name__c;
        data.bankAccountNo = p.Bank_Account_No__c;
        data.bankIfsc = p.Bank_IFSC__c;
        data.termsAndConditions = p.Terms_And_Conditions__c;
        data.jobSlipTerms = p.Job_Slip_Terms__c;
        return data;
    }
}
