/**
 * One archiving run (architecture.md, Forty-fifth and Forty-sixth): deletes old
 * estimates and archives dormant customers and Walk-in cars (at most once every
 * 28 days, or whenever run by hand), then archives bills one company-month per step, chaining itself for the next
 * month. Developer Edition allows a chain of 5, so a night does up to 5
 * months and the next night carries on. Started each night by
 * BillEstimateFileCleanupScheduler when archiving is on, or by "Run now".
 * The result, or the failure, is kept on Archive_Settings__c; a failure is
 * also emailed to whoever the job runs as.
 */
public without sharing class ArchiveJob implements Queueable {

    @TestVisible
    private static final Integer MAX_STEPS = 5;
    // Tests make a run fail after everything is archived, to prove it's all undone.
    @TestVisible
    private static Boolean failForTest = false;

    private Integer step;
    private Integer billsArchived;
    private Integer estimatesDeleted;
    private List<String> months;
    // Run now (by hand) archives customers whenever they're ready.
    private Boolean byHand = false;
    private Integer customersArchived = 0;
    private Integer carsArchived = 0;
    private Integer jobsArchived = 0;
    private Integer slipsArchived = 0;
    private Integer monthsArchived = 0;

    public ArchiveJob() {
        this(0, 0, 0, new List<String>());
    }

    public ArchiveJob(Boolean byHand) {
        this(0, 0, 0, new List<String>());
        this.byHand = byHand == true;
    }

    private ArchiveJob(Integer step, Integer billsArchived, Integer estimatesDeleted, List<String> months) {
        this.step = step;
        this.billsArchived = billsArchived;
        this.estimatesDeleted = estimatesDeleted;
        this.months = months;
    }

    public void execute(QueueableContext context) {
        ArchiveSettings.Rules rules = ArchiveSettings.current();
        Savepoint sp = Database.setSavepoint();
        try {
            if (step == 0) {
                estimatesDeleted += EstimatePurge.run(rules);
                // Jobs and slips first: a customer they kept can then go too.
                if (byHand || WorkArchive.isDue(rules)) {
                    WorkArchive.Outcome work = WorkArchive.archiveReady(rules);
                    jobsArchived += work.jobs;
                    slipsArchived += work.slips;
                }
                // A month's attendance is ready once a month, so this runs about monthly by itself.
                monthsArchived += AttendanceArchive.archiveReady(rules);
                if (byHand || CustomerArchive.isDue(rules)) {
                    CustomerArchive.Outcome people = CustomerArchive.archiveReady(rules);
                    customersArchived += people.customers;
                    carsArchived += people.cars;
                }
            }
            BillArchive.Outcome outcome = BillArchive.archiveNextMonth(rules);
            if (failForTest) {
                throw new ArchiveSettings.ArchiveSettingsException('Test failure after archiving');
            }
            billsArchived += outcome.billsArchived;
            if (outcome.month != null) {
                months.add(outcome.month);
            }
            if (outcome.moreToDo && step + 1 < MAX_STEPS && !Test.isRunningTest()) {
                ArchiveJob next = new ArchiveJob(step + 1, billsArchived, estimatesDeleted, months);
                next.customersArchived = customersArchived;
                next.carsArchived = carsArchived;
                next.jobsArchived = jobsArchived;
                next.slipsArchived = slipsArchived;
                next.monthsArchived = monthsArchived;
                System.enqueueJob(next);
                return;
            }
            ArchiveSettings.recordRun(summary(outcome.moreToDo));
        } catch (Exception e) {
            Database.rollback(sp);
            String message = 'Archiving stopped: ' + e.getMessage();
            ArchiveSettings.recordRun(message);
            tell(message);
        }
    }

    @TestVisible
    private String summary(Boolean moreToDo) {
        List<String> parts = new List<String>();
        parts.add(billsArchived == 0 ? 'No bills were ready to archive' : 'Archived ' + billsArchived + ' bill' + (billsArchived == 1 ? '' : 's') + ' (' + String.join(months, ', ') + ')');
        if (customersArchived > 0) {
            parts.add('archived ' + customersArchived + ' dormant customer' + (customersArchived == 1 ? '' : 's'));
        }
        if (carsArchived > 0) {
            parts.add('archived ' + carsArchived + ' Walk-in car' + (carsArchived == 1 ? '' : 's'));
        }
        if (jobsArchived > 0) {
            parts.add('archived ' + jobsArchived + ' finished job' + (jobsArchived == 1 ? '' : 's'));
        }
        if (slipsArchived > 0) {
            parts.add('archived ' + slipsArchived + ' job slip' + (slipsArchived == 1 ? '' : 's'));
        }
        if (monthsArchived > 0) {
            parts.add('archived ' + monthsArchived + ' attendance month' + (monthsArchived == 1 ? '' : 's'));
        }
        if (estimatesDeleted > 0) {
            parts.add('deleted ' + estimatesDeleted + ' old estimate' + (estimatesDeleted == 1 ? '' : 's'));
        }
        return String.join(parts, '; ') + (moreToDo ? '. More is ready; it carries on next night.' : '.');
    }

    private static void tell(String message) {
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(UserInfo.getUserId());
            mail.setSaveAsActivity(false);
            mail.setSubject('WS Biller: archiving stopped');
            mail.setPlainTextBody(message + '\n\nNothing from the failed step was changed. Open WS Biller > More > Settings > Archive to see the details.');
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception ignored) {
            // The failure is kept on the Archive screen either way.
        }
    }
}
