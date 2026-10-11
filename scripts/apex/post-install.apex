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
