// Read-only: lists GST details that need a person to fix them, after
// GstBackfillBatch (started by post-install.apex) has tidied what it could.
// Run: sf apex run --file scripts/apex/gst-data-report.apex --target-org <org>
// and read the USER_DEBUG lines.

Integer problems = 0;
for (String objectName : new List<String>{ 'Workshop_Profile__c', 'Customer__c', 'Bill_To_Party__c' }) {
    for (SObject record : Database.query('SELECT Name, GSTIN__c, State__c FROM ' + objectName + ' WHERE GSTIN__c != null OR State__c != null LIMIT 2000')) {
        String gstin = (String) record.get('GSTIN__c');
        String state = (String) record.get('State__c');
        List<String> issues = new List<String>();
        if (gstin != null && !GstRules.isValidGstin(gstin)) {
            issues.add('GSTIN "' + gstin + '" is not valid');
        }
        if (state != null && GstRules.stateName(state) == null) {
            issues.add('state "' + state + '" is not an Indian state');
        }
        if (!issues.isEmpty()) {
            problems++;
            System.debug(objectName + ' ' + record.get('Name') + ' (' + record.Id + '): ' + String.join(issues, '; '));
        }
    }
}
Integer noPlace = [SELECT COUNT() FROM Bill__c WHERE Place_Of_Supply__c = null];
if (noPlace > 0) {
    problems++;
    System.debug(noPlace + ' bills have no place of supply: give the company a state, then run post-install.apex again.');
}
System.debug(problems == 0 ? 'GST details: nothing to fix.' : 'GST details: ' + problems + ' to fix (above).');
