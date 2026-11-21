// Run once against any org right after a metadata deploy (dev, sandbox, or
// a brand-new client org). Idempotent — safe to re-run after every future
// deploy to the same org, since it only acts if the scheduled job is
// missing. System.schedule() is not metadata, so it never comes over with
// `sf project deploy start` — this is the one piece of "config" that has
// to be run live, every time, in every org.

String jobName = 'Bill/Estimate File Cleanup (Nightly)';
List<CronTrigger> existing = [
    SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :jobName
];
if (existing.isEmpty()) {
    System.schedule(jobName, '0 0 2 * * ?', new BillEstimateFileCleanupScheduler());
    System.debug('Scheduled: ' + jobName);
} else {
    System.debug('Already scheduled, skipped: ' + jobName);
}

// Records saved before a workshop could have two companies have no company on
// them. They all belong to the first one; screens and PDFs already treat them
// so, and this makes reports agree. Idempotent, and run again it picks up any
// beyond the per-run limit.
List<Workshop_Profile__c> firstCompany = [SELECT Id FROM Workshop_Profile__c ORDER BY CreatedDate, Id LIMIT 1];
if (!firstCompany.isEmpty()) {
    Id companyId = firstCompany[0].Id;
    List<Bill__c> bills = [SELECT Id FROM Bill__c WHERE Workshop_Profile__c = null LIMIT 3000];
    List<Estimate__c> estimates = [SELECT Id FROM Estimate__c WHERE Workshop_Profile__c = null LIMIT 3000];
    List<Job_Slip__c> slips = [SELECT Id FROM Job_Slip__c WHERE Workshop_Profile__c = null LIMIT 3000];
    for (Bill__c record : bills) {
        record.Workshop_Profile__c = companyId;
    }
    for (Estimate__c record : estimates) {
        record.Workshop_Profile__c = companyId;
    }
    for (Job_Slip__c record : slips) {
        record.Workshop_Profile__c = companyId;
    }
    update bills;
    update estimates;
    update slips;
    System.debug('Company recorded on ' + bills.size() + ' bills, ' + estimates.size() + ' estimates, ' + slips.size() + ' job slips.');
}

// GST details saved before the GST checks existed: tidies states and GSTINs,
// and gives bills their place of supply and buyer's GSTIN. Runs in the
// background (one object after another); idempotent, so running it after every
// deploy is fine. scripts/apex/gst-data-report.apex lists what it couldn't fix.
Id gstJob = Database.executeBatch(new GstBackfillBatch(), 200);
System.debug('Started GST tidy-up job ' + gstJob);
