// Aborts this app's own scheduled job(s) before a (re)deploy. Salesforce
// blocks deploying ANY Apex class when a class in the deploy payload has
// an active/pending scheduled job tied to it ("This schedulable class has
// jobs pending or in progress") — this hits every deploy after the first
// one to a given org, once post-install.apex has registered the nightly
// job there. Run this immediately before every deploy; post-install.apex
// re-registers it immediately after, so the gap is a few seconds, not an
// overnight window.
//
// Matches by name on purpose, rather than aborting every CronTrigger in
// the org — a client org may have unrelated scheduled jobs (other
// installed packages, Salesforce's own internal jobs) that must not be
// touched.

Set<String> thisAppsJobNames = new Set<String>{
    'Bill/Estimate File Cleanup (Nightly)'
};

List<CronTrigger> jobs = [
    SELECT Id, CronJobDetail.Name
    FROM CronTrigger
    WHERE CronJobDetail.Name IN :thisAppsJobNames
];
for (CronTrigger job : jobs) {
    System.abortJob(job.Id);
    System.debug('Aborted: ' + job.CronJobDetail.Name);
}
if (jobs.isEmpty()) {
    System.debug('Nothing to abort — no matching scheduled jobs found (expected on a brand-new org).');
}
