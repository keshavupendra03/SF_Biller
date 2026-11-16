/**
 * Finds or saves the party a bill or estimate is billed to (an insurance
 * company, a fleet owner, a firm buying parts) for Easy Bill and Quick
 * Bill / Quick Estimate, where staff either pick a saved party or just type
 * one in.
 *
 * A typed name that matches a saved party, ignoring case, is that party, so
 * typing a regular party's name again doesn't make a second copy of it.
 */
public with sharing class BillToPartyService {

    public class BillToPartyServiceException extends Exception {}

    // Bill_To_Party__c.GSTIN__c is 15 characters, like every GSTIN.
    private static final Integer GSTIN_LENGTH = 15;

    /**
     * Returns the party to bill, or null when none was picked or typed.
     *
     * pageIsTheRecord: Easy Bill shows a picked party's details as editable
     * boxes, and InvoicePdf.page prints the party live from its record, so a
     * picked party takes what's on the page, blanks included. Quick Bill only
     * shows a picked party, so it's left as saved. For a typed name that
     * matches a saved party, Easy Bill replaces details with any typed ones;
     * Quick Bill only fills in details the party doesn't have yet.
     */
    public static Id resolve(Id partyId, BillController.NewBillToPartyInput typed, Boolean pageIsTheRecord) {
        String name = typed == null || String.isBlank(typed.name) ? null : typed.name.trim();
        if (typed != null && String.isNotBlank(typed.gstin) && typed.gstin.trim().length() > GSTIN_LENGTH) {
            throw new BillToPartyServiceException('The party GSTIN should be 15 characters.');
        }

        if (partyId != null) {
            if (pageIsTheRecord == true && typed != null) {
                Bill_To_Party__c picked = new Bill_To_Party__c(
                    Id = partyId,
                    Address__c = trimmed(typed.address),
                    Contact_Phone__c = trimmed(typed.contactPhone),
                    GSTIN__c = trimmed(typed.gstin),
                    State__c = trimmed(typed.state)
                );
                if (name != null) {
                    picked.Name = name;
                }
                update picked;
            }
            return partyId;
        }
        if (name == null) {
            return null;
        }

        // SOQL "=" is case-insensitive, so "icici lombard" finds "ICICI Lombard".
        List<Bill_To_Party__c> sameName = [
            SELECT Id, Address__c, Contact_Phone__c, GSTIN__c, State__c
            FROM Bill_To_Party__c
            WHERE Name = :name
            ORDER BY CreatedDate
            LIMIT 1
        ];
        if (sameName.isEmpty()) {
            Bill_To_Party__c created = new Bill_To_Party__c(
                Name = name,
                Address__c = trimmed(typed.address),
                Contact_Phone__c = trimmed(typed.contactPhone),
                GSTIN__c = trimmed(typed.gstin),
                State__c = trimmed(typed.state)
            );
            insert created;
            return created.Id;
        }

        Bill_To_Party__c existing = sameName[0];
        Bill_To_Party__c changes = new Bill_To_Party__c(Id = existing.Id);
        Boolean replace = pageIsTheRecord == true;
        Boolean changed = false;
        changed = applyTyped(changes, existing, 'Address__c', typed.address, replace) || changed;
        changed = applyTyped(changes, existing, 'Contact_Phone__c', typed.contactPhone, replace) || changed;
        changed = applyTyped(changes, existing, 'GSTIN__c', typed.gstin, replace) || changed;
        changed = applyTyped(changes, existing, 'State__c', typed.state, replace) || changed;
        if (changed) {
            update changes;
        }
        return existing.Id;
    }

    // A blank typed value never clears what's saved.
    private static Boolean applyTyped(Bill_To_Party__c changes, Bill_To_Party__c existing, String field, String value, Boolean replace) {
        String typedValue = trimmed(value);
        String saved = (String) existing.get(field);
        if (typedValue == null || typedValue == saved || (!replace && String.isNotBlank(saved))) {
            return false;
        }
        changes.put(field, typedValue);
        return true;
    }

    private static String trimmed(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}
