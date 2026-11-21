/**
 * Tidies GST details saved before GstPartyDetails and Bill__c's GST fields
 * existed, and is safe to run again (post-install.apex starts it after every
 * deploy):
 *  - customers, Bill-To-Parties and companies: a state typed any old way
 *    ("MP", "Madhyapradesh") becomes its name, a GSTIN goes upper case, and a
 *    blank state is filled from a valid GSTIN;
 *  - bills: the invoice sequence, buyer's GSTIN and place of supply, worked
 *    out as BillTriggerHandler does for a new bill.
 * Anything it can't work out (an unknown state, a bad GSTIN) is left exactly
 * as it is; scripts/apex/gst-data-report.apex lists those to fix by hand.
 *
 * One object per run, chained: customers, parties, companies, then bills, so
 * bills get their place of supply from states already tidied.
 */
public with sharing class GstBackfillBatch implements Database.Batchable<SObject> {

    private static final List<String> STEPS = new List<String>{ 'Customer__c', 'Bill_To_Party__c', 'Workshop_Profile__c', 'Bill__c' };

    private final Integer step;

    public GstBackfillBatch() {
        this(0);
    }

    @TestVisible
    private GstBackfillBatch(Integer step) {
        this.step = step;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (STEPS[step] == 'Bill__c') {
            return Database.getQueryLocator(
                'SELECT Invoice_Number__c, Invoice_Sequence__c, Customer__c, Bill_To_Party__c, Workshop_Profile__c,'
                + ' Recipient_GSTIN__c, Place_Of_Supply__c FROM Bill__c'
                + ' WHERE Place_Of_Supply__c = null OR Invoice_Sequence__c = null'
            );
        }
        return Database.getQueryLocator('SELECT GSTIN__c, State__c FROM ' + STEPS[step] + ' WHERE GSTIN__c != null OR State__c != null');
    }

    public void execute(Database.BatchableContext context, List<SObject> records) {
        List<SObject> changed = STEPS[step] == 'Bill__c' ? tidyBills((List<Bill__c>) records) : tidyDetails(records);
        // One record that won't save mustn't stop the rest.
        Database.update(changed, false);
    }

    public void finish(Database.BatchableContext context) {
        if (step + 1 < STEPS.size() && !Test.isRunningTest()) {
            Database.executeBatch(new GstBackfillBatch(step + 1), 200);
        }
    }

    /** The changes to make, as new records holding only what changes. */
    @TestVisible
    private static List<SObject> tidyDetails(List<SObject> records) {
        List<SObject> changed = new List<SObject>();
        for (SObject record : records) {
            String gstin = (String) record.get('GSTIN__c');
            String state = (String) record.get('State__c');
            String cleanGstin = GstRules.normalizeGstin(gstin);
            Boolean gstinValid = GstRules.isValidGstin(cleanGstin);
            String cleanState = String.isBlank(state)
                ? (gstinValid ? GstRules.stateNameForGstin(cleanGstin) : null)
                : GstRules.stateName(state);

            SObject change = record.getSObjectType().newSObject(record.Id);
            Boolean differs = false;
            // An invalid GSTIN is left alone: tidying it would only make the
            // save refuse it, and it needs a person to correct it anyway.
            if (gstinValid && !cleanGstin.equals(gstin)) {
                change.put('GSTIN__c', cleanGstin);
                differs = true;
            }
            if (cleanState != null && !cleanState.equals(state)) {
                change.put('State__c', cleanState);
                differs = true;
            }
            if (differs) {
                changed.add(change);
            }
        }
        return changed;
    }

    @TestVisible
    private static List<Bill__c> tidyBills(List<Bill__c> bills) {
        for (Bill__c bill : bills) {
            if (bill.Invoice_Sequence__c == null) {
                bill.Invoice_Sequence__c = InvoiceNumberingService.sequenceOf(bill.Invoice_Number__c);
            }
        }
        BillTriggerHandler.fixRecipient(bills);
        return bills;
    }
}
