/**
 * Enforced here rather than on a screen, so no screen, data import or admin
 * action can get past it:
 *  - at most two companies;
 *  - each company's invoice prefix is 1-3 letters/digits and differs from the
 *    other company's. Three characters keeps PRE/2026-27/0001 within the GST
 *    limit of 16 characters for an invoice number.
 */
public with sharing class WorkshopProfileTriggerHandler {

    public static void handleBeforeInsert(List<Workshop_Profile__c> incoming) {
        // Locking the existing rows makes a second simultaneous insert wait and
        // then count the first one.
        List<Workshop_Profile__c> existing = [SELECT Id, Invoice_Prefix__c FROM Workshop_Profile__c FOR UPDATE];
        if (existing.size() + incoming.size() > WorkshopProfileService.MAX_PROFILES) {
            for (Workshop_Profile__c profile : incoming) {
                profile.addError('You can only have ' + WorkshopProfileService.MAX_PROFILES + ' companies.');
            }
            return;
        }
        checkPrefixes(incoming, existing);
    }

    // Only when a prefix changes: the invoice counter updates this row on every
    // bill, and that must not cost an extra query each time.
    public static void handleBeforeUpdate(List<Workshop_Profile__c> updated, Map<Id, Workshop_Profile__c> previous) {
        List<Workshop_Profile__c> changed = new List<Workshop_Profile__c>();
        for (Workshop_Profile__c profile : updated) {
            if (profile.Invoice_Prefix__c != previous.get(profile.Id).Invoice_Prefix__c) {
                changed.add(profile);
            }
        }
        if (!changed.isEmpty()) {
            checkPrefixes(changed, [SELECT Id, Invoice_Prefix__c FROM Workshop_Profile__c WHERE Id NOT IN :changed]);
        }
    }

    private static void checkPrefixes(List<Workshop_Profile__c> profiles, List<Workshop_Profile__c> others) {
        Set<String> taken = new Set<String>();
        for (Workshop_Profile__c other : others) {
            taken.add(WorkshopProfileService.invoicePrefix(other).toUpperCase());
        }
        for (Workshop_Profile__c profile : profiles) {
            if (String.isNotBlank(profile.Invoice_Prefix__c)) {
                profile.Invoice_Prefix__c = profile.Invoice_Prefix__c.trim().toUpperCase();
                if (!Pattern.matches('[A-Z0-9]{1,3}', profile.Invoice_Prefix__c)) {
                    profile.addError('The invoice prefix must be 1 to 3 letters or numbers, like DEC.');
                    continue;
                }
            }
            String prefix = WorkshopProfileService.invoicePrefix(profile);
            if (taken.contains(prefix)) {
                profile.addError('Each company needs its own invoice prefix. ' + prefix + ' is already used.');
                continue;
            }
            taken.add(prefix);
        }
    }
}
