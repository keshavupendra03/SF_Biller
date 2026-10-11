// Run ONCE per new client org, after editing the values below for that
// specific client. Idempotent — each block only inserts if the org has
// none of that record yet, so re-running after editing (e.g. to add more
// stages) is safe and won't create duplicates.
//
// These two objects are DATA, not metadata — `sf project deploy start`
// never creates these rows. Skipping this step leaves an app that deploys
// clean but is actually broken:
//   - No Workshop_Profile__c row  -> every bill creation throws
//     InvoiceNumberingService.InvoiceNumberingException immediately.
//   - No active Job_Status_Stage__c rows -> the Jobs board renders with
//     zero columns and JobController.createJob throws.

// --- EDIT THESE BEFORE RUNNING ---
String workshopName    = 'REPLACE_ME Motors';
String workshopGstin   = 'REPLACE_ME';
String workshopPhone   = 'REPLACE_ME';
String workshopEmail   = 'REPLACE_ME';
String workshopState   = 'REPLACE_ME';
String workshopAddress = 'REPLACE_ME';
// ----------------------------------

if ([SELECT COUNT() FROM Workshop_Profile__c] == 0) {
    insert new Workshop_Profile__c(
        Name = workshopName,
        GSTIN__c = workshopGstin,
        Phone__c = workshopPhone,
        Email__c = workshopEmail,
        State__c = workshopState,
        Address__c = workshopAddress
        // Invoice_Sequence_Financial_Year__c / Invoice_Sequence_Last_Number__c
        // intentionally left null — InvoiceNumberingService starts a fresh
        // financial year and sequence the first time a bill is created.
    );
    System.debug('Workshop_Profile__c seeded for ' + workshopName + '.');
} else {
    System.debug('Workshop_Profile__c already exists — skipped. ' +
        'Edit the existing record by hand if client details changed.');
}

if ([SELECT COUNT() FROM Job_Status_Stage__c WHERE Is_Active__c = true] == 0) {
    insert new List<Job_Status_Stage__c>{
        new Job_Status_Stage__c(Name = 'Received',    Sort_Order__c = 1, Is_Active__c = true),
        new Job_Status_Stage__c(Name = 'In Progress',  Sort_Order__c = 2, Is_Active__c = true),
        new Job_Status_Stage__c(Name = 'Ready',        Sort_Order__c = 3, Is_Active__c = true),
        new Job_Status_Stage__c(Name = 'Delivered',    Sort_Order__c = 4, Is_Active__c = true)
    };
    System.debug('Default Job_Status_Stage__c pipeline seeded (4 stages) — ' +
        'rename/reorder/add to these later via the Job Stages screen in-app, no redeploy needed.');
} else {
    System.debug('Active Job_Status_Stage__c rows already exist — skipped.');
}
