/**
 * A workshop can run two companies (say repairs and car decoration), each with
 * its own name, GSTIN, bank details, terms and invoice series. "Primary" is the
 * first one created: it owns everything saved before a second company existed,
 * so a document with no Workshop_Profile__c always means the primary company.
 *
 * Never read a profile with a bare LIMIT 1 any more: with two rows that picks
 * either company.
 */
public with sharing class WorkshopProfileService {

    public static final Integer MAX_PROFILES = 2;
    public static final String DEFAULT_INVOICE_PREFIX = 'INV';

    private static Id primaryCompanyId;

    // Remembered for the transaction: numbering asks once per bill, and the
    // oldest row doesn't change.
    public static Id primaryId() {
        if (primaryCompanyId == null) {
            List<Workshop_Profile__c> profiles = [SELECT Id FROM Workshop_Profile__c ORDER BY CreatedDate, Id LIMIT 1];
            primaryCompanyId = profiles.isEmpty() ? null : profiles[0].Id;
        }
        return primaryCompanyId;
    }

    // The company named on screens. Empty when there's only one company, so
    // single-company workshops never see a company name anywhere. The null key
    // covers documents saved before a company was recorded on them.
    public static Map<Id, String> companyNames() {
        Map<Id, String> names = new Map<Id, String>();
        List<Workshop_Profile__c> profiles = [SELECT Id, Name FROM Workshop_Profile__c ORDER BY CreatedDate, Id];
        if (profiles.size() < MAX_PROFILES) {
            return names;
        }
        for (Workshop_Profile__c profile : profiles) {
            names.put(profile.Id, profile.Name);
        }
        names.put(null, profiles[0].Name);
        return names;
    }

    public static String invoicePrefix(Workshop_Profile__c profile) {
        return String.isBlank(profile.Invoice_Prefix__c) ? DEFAULT_INVOICE_PREFIX : profile.Invoice_Prefix__c;
    }
}
