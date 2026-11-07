/**
 * The workshop's companies: at most two (WorkshopProfileTrigger enforces it),
 * each with its own details, GSTIN, bank account, terms and invoice prefix.
 * Most workshops only ever have the one, so getProfile and saveProfile without
 * an id still mean the primary company.
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
        @AuraEnabled public String invoicePrefix { get; set; }
        @AuraEnabled public Boolean isPrimary { get; set; }
    }

    private static final List<String> FIELDS = new List<String>{
        'Name', 'Address__c', 'Phone__c', 'Email__c', 'GSTIN__c', 'State__c', 'Invoice_Prefix__c',
        'Bank_Account_Holder__c', 'Bank_Name__c', 'Bank_Account_No__c', 'Bank_IFSC__c',
        'Terms_And_Conditions__c', 'Job_Slip_Terms__c'
    };

    /** Primary company first. */
    @AuraEnabled
    public static List<ProfileData> listProfiles() {
        List<ProfileData> results = new List<ProfileData>();
        for (Workshop_Profile__c profile : Database.query(
            'SELECT ' + String.join(FIELDS, ', ') + ' FROM Workshop_Profile__c ORDER BY CreatedDate, Id'
        )) {
            ProfileData data = toProfileData(profile);
            data.isPrimary = results.isEmpty();
            results.add(data);
        }
        return results;
    }

    @AuraEnabled
    public static ProfileData getProfile() {
        List<ProfileData> profiles = listProfiles();
        return profiles.isEmpty() ? null : profiles[0];
    }

    /** Updates the company given by input.id, or the primary one (adding it if there's none). */
    @AuraEnabled
    public static ProfileData saveProfile(ProfileData input) {
        requireName(input);
        Id existingId = input.id != null ? input.id : WorkshopProfileService.primaryId();
        return write(applyTo(new Workshop_Profile__c(Id = existingId), input));
    }

    /** Adds a company. Refused by WorkshopProfileTrigger if there are already two. */
    @AuraEnabled
    public static ProfileData addProfile(ProfileData input) {
        requireName(input);
        return write(applyTo(new Workshop_Profile__c(), input));
    }

    private static void requireName(ProfileData input) {
        if (input == null || String.isBlank(input.name)) {
            throw new WorkshopProfileControllerException('A workshop name is required.');
        }
    }

    private static Workshop_Profile__c applyTo(Workshop_Profile__c profile, ProfileData input) {
        profile.Name = input.name;
        profile.Address__c = input.address;
        profile.Phone__c = input.phone;
        profile.Email__c = input.email;
        profile.GSTIN__c = input.gstin;
        profile.State__c = input.state;
        profile.Invoice_Prefix__c = input.invoicePrefix;
        profile.Bank_Account_Holder__c = input.bankAccountHolder;
        profile.Bank_Name__c = input.bankName;
        profile.Bank_Account_No__c = input.bankAccountNo;
        profile.Bank_IFSC__c = input.bankIfsc;
        profile.Terms_And_Conditions__c = input.termsAndConditions;
        profile.Job_Slip_Terms__c = input.jobSlipTerms;
        return profile;
    }

    // A DmlException reaches the screen with no readable message, so the
    // trigger's own wording is rethrown as one that does.
    private static ProfileData write(Workshop_Profile__c profile) {
        try {
            upsert profile;
        } catch (DmlException e) {
            throw new WorkshopProfileControllerException(e.getDmlMessage(0));
        }
        Id profileId = profile.Id;
        return toProfileData(Database.query(
            'SELECT ' + String.join(FIELDS, ', ') + ' FROM Workshop_Profile__c WHERE Id = :profileId'
        ));
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
        data.invoicePrefix = WorkshopProfileService.invoicePrefix(p);
        return data;
    }
}
