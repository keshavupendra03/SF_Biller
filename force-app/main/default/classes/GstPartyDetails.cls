/**
 * Keeps GSTIN and state clean on customers, Bill-To-Parties and companies,
 * whichever screen, import or script saved them (CustomerTrigger,
 * BillToPartyTrigger, WorkshopProfileTrigger):
 *  - a GSTIN is stored upper case with no spaces, and must be a real one;
 *  - a state is stored as its name ("MP", "23" or "madhyapradesh" become
 *    "Madhya Pradesh"), and must be an Indian state or UT;
 *  - a blank state is filled from a valid GSTIN.
 * Only a GSTIN or state being entered or changed is checked. An older record
 * with a bad value isn't blocked from every other save: the invoice counter
 * updates the company row on every bill. GstBackfillBatch tidies old ones.
 */
public with sharing class GstPartyDetails {

    public static void apply(List<SObject> records, Map<Id, SObject> previous) {
        for (SObject record : records) {
            SObject old = previous == null ? null : previous.get(record.Id);
            String gstin = (String) record.get('GSTIN__c');
            Boolean gstinChanged = old == null || differs(gstin, (String) old.get('GSTIN__c'));
            if (gstinChanged) {
                gstin = GstRules.normalizeGstin(gstin);
                record.put('GSTIN__c', gstin);
                if (gstin != null && !GstRules.isValidGstin(gstin)) {
                    record.addError('GSTIN__c', gstin + ' is not a valid GSTIN. Check it on the GST certificate, or leave it blank.');
                    continue;
                }
            }

            String state = (String) record.get('State__c');
            Boolean stateChanged = old == null || differs(state, (String) old.get('State__c'));
            if (String.isBlank(state)) {
                if (gstinChanged && gstin != null) {
                    record.put('State__c', GstRules.stateNameForGstin(gstin));
                } else if (stateChanged) {
                    record.put('State__c', null);
                }
            } else if (stateChanged) {
                String name = GstRules.stateName(state);
                if (name == null) {
                    record.addError('State__c', '"' + state.trim() + '" is not an Indian state. Pick the state from the list.');
                } else {
                    record.put('State__c', name);
                }
            }
        }
    }

    // Apex's own != ignores case, and "mp" to "MP" is still a change to tidy.
    private static Boolean differs(String a, String b) {
        return a == null ? b != null : !a.equals(b);
    }
}
