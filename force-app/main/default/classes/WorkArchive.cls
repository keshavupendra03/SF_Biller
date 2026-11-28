/**
 * Archives finished jobs and old job slips into Files (ArchiveStore,
 * architecture.md, Forty-seventh). Neither comes back: a job that's done and a
 * slip the customer signed are records to look at and print, which the
 * customer's screen still does from the archive.
 *
 * Jobs: not changed (moved, noted, given a mechanic) for
 * Archive_Settings__c.Jobs_After_Months__c, and no bill or estimate in
 * Salesforce points at the job (its lookup would be emptied; the job goes once
 * they're archived or deleted). Mechanics on the job are kept by name.
 * Job slips: dated more than Job_Slips_After_Months__c ago. Nothing points at
 * a slip.
 *
 * One run writes a jobs file, a slips file (with each company's header as it
 * was, so a slip prints the same) and one index file, reads them back, then
 * deletes and empties the Recycle Bin, in one transaction. Like customers, the
 * nightly run does this at most once every 28 days, or the next night when
 * more than one run's worth is waiting.
 */
public without sharing class WorkArchive {
    // Without sharing: archiving runs for the whole org, at night as well.

    public class WorkArchiveException extends Exception {}

    public static final String KIND_JOB = 'job';
    public static final String KIND_SLIP = 'slip';
    @TestVisible
    private static Integer maxJobs = 500;
    @TestVisible
    private static Integer maxSlips = 500;
    // Records made in a test were all changed just now: tests move the cut-off instead.
    @TestVisible
    private static Datetime jobsCutForTest;

    private static final String JOB_RELATED = 'Customer__r.Name, Customer__r.Phone__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c, '
        + 'Job_Status_Stage__r.Name, Surveyor__r.Name';
    private static final String SLIP_RELATED = 'Customer__r.Name, Customer__r.Address__c, Customer__r.Phone__c, Customer__r.Email__c, '
        + 'Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c, Vehicle__r.Chassis_Number__c, Vehicle__r.Engine_Number__c, Vehicle__r.Date_Of_Sale__c';
    private static final String COMPANY_FIELDS = 'Id, Name, Address__c, Phone__c, Email__c, Job_Slip_Terms__c';

    public class JobFile {
        public Integer format;
        public List<Job__c> jobs;
        // Job Id to its mechanics' names.
        public Map<String, List<String>> mechanics;
    }

    public class SlipFile {
        public Integer format;
        public List<Job_Slip__c> slips;
        // Company Id to the company as it was.
        public Map<String, Workshop_Profile__c> companies;
    }

    public class Plan {
        @AuraEnabled public Integer jobs { get; set; }
        @AuraEnabled public Integer slips { get; set; }
        @AuraEnabled public Date jobsBefore { get; set; }
        @AuraEnabled public Date slipsBefore { get; set; }
        @AuraEnabled public Boolean isDue { get; set; }
    }

    public class Outcome {
        @AuraEnabled public Integer jobs { get; set; }
        @AuraEnabled public Integer slips { get; set; }
    }

    // ---- which ----------------------------------------------------------

    public static Date jobsBefore(ArchiveSettings.Rules rules) {
        return Date.today().addMonths(-Math.max(rules.jobsAfterMonths, 1));
    }

    public static Date slipsBefore(ArchiveSettings.Rules rules) {
        return Date.today().addMonths(-Math.max(rules.jobSlipsAfterMonths, 1));
    }

    private static Datetime startOf(Date d) {
        return Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
    }

    // Jobs not changed since the cut-off that no live bill or estimate points at, longest-quiet first.
    private static List<Id> readyJobs(ArchiveSettings.Rules rules, Integer max) {
        Datetime cut = jobsCutForTest != null ? jobsCutForTest : startOf(jobsBefore(rules));
        Map<Id, Job__c> old = new Map<Id, Job__c>([
            SELECT Id FROM Job__c WHERE LastModifiedDate < :cut ORDER BY LastModifiedDate LIMIT 5000
        ]);
        Set<Id> ids = old.keySet();
        Set<Id> blocked = new Set<Id>();
        for (AggregateResult r : [SELECT Job__c j FROM Bill__c WHERE Job__c IN :ids GROUP BY Job__c]) {
            blocked.add((Id) r.get('j'));
        }
        for (AggregateResult r : [SELECT Job__c j FROM Estimate__c WHERE Job__c IN :ids GROUP BY Job__c]) {
            blocked.add((Id) r.get('j'));
        }
        List<Id> ready = new List<Id>();
        for (Id jobId : old.keySet()) {
            if (!blocked.contains(jobId) && ready.size() < max) {
                ready.add(jobId);
            }
        }
        return ready;
    }

    private static List<Id> readySlips(ArchiveSettings.Rules rules, Integer max) {
        Date cut = slipsBefore(rules);
        Datetime cutTime = startOf(cut);
        List<Id> ready = new List<Id>();
        for (Job_Slip__c s : [
            SELECT Id FROM Job_Slip__c
            WHERE Slip_Date__c < :cut OR (Slip_Date__c = null AND CreatedDate < :cutTime)
            ORDER BY Slip_Date__c LIMIT :max
        ]) {
            ready.add(s.Id);
        }
        return ready;
    }

    public static Plan plan(ArchiveSettings.Rules rules) {
        Plan p = new Plan();
        p.jobsBefore = jobsBefore(rules);
        p.slipsBefore = slipsBefore(rules);
        p.jobs = readyJobs(rules, 5000).size();
        p.slips = readySlips(rules, 5000).size();
        p.isDue = isDue();
        return p;
    }

    public static Boolean isDue() {
        return !ArchiveStore.wroteWithin(ArchiveStore.KIND_WORK_INDEX, ArchiveStore.DAYS_BETWEEN_RUNS);
    }

    /** Due, or more waiting than one run takes. */
    public static Boolean isDue(ArchiveSettings.Rules rules) {
        return isDue() || readyJobs(rules, maxJobs + 1).size() > maxJobs || readySlips(rules, maxSlips + 1).size() > maxSlips;
    }

    // ---- archiving ------------------------------------------------------

    /** Archives up to maxJobs jobs and maxSlips job slips, in one transaction. */
    public static Outcome archiveReady(ArchiveSettings.Rules rules) {
        Outcome outcome = new Outcome();
        outcome.jobs = 0;
        outcome.slips = 0;
        List<Id> jobIds = readyJobs(rules, maxJobs);
        List<Id> slipIds = readySlips(rules, maxSlips);
        if (jobIds.isEmpty() && slipIds.isEmpty()) {
            return outcome;
        }
        String month = Datetime.now().format('yyyy-MM');
        List<ArchiveStore.IndexEntry> entries = new List<ArchiveStore.IndexEntry>();
        Map<Id, Integer> expected = new Map<Id, Integer>();

        List<Job__c> jobs = new List<Job__c>();
        if (!jobIds.isEmpty()) {
            jobs = Database.query('SELECT ' + String.join(fieldsOf(Job__c.SObjectType), ', ') + ', ' + JOB_RELATED
                + ' FROM Job__c WHERE Id IN :jobIds ORDER BY CreatedDate');
            JobFile file = new JobFile();
            file.format = 1;
            file.jobs = jobs;
            file.mechanics = new Map<String, List<String>>();
            for (Job_Mechanic__c jm : [SELECT Job__c, Mechanic__r.Name FROM Job_Mechanic__c WHERE Job__c IN :jobIds ORDER BY Mechanic__r.Name]) {
                if (!file.mechanics.containsKey(jm.Job__c)) {
                    file.mechanics.put(jm.Job__c, new List<String>());
                }
                file.mechanics.get(jm.Job__c).add(jm.Mechanic__r.Name);
            }
            Id documentId = ArchiveStore.write(ArchiveStore.KIND_JOBS, null, month, 'Jobs ' + month, JSON.serialize(file));
            expected.put(documentId, jobs.size());
            for (Job__c j : jobs) {
                ArchiveStore.IndexEntry e = entryFor(j.Id, KIND_JOB, j.Name, j.CreatedDate.date(), j.Customer__r, j.Vehicle__r, documentId);
                e.cu = j.Customer__c;
                e.ve = j.Vehicle__c;
                e.s = j.Job_Status_Stage__r == null ? null : j.Job_Status_Stage__r.Name;
                entries.add(e);
            }
            outcome.jobs = jobs.size();
        }

        List<Job_Slip__c> slips = new List<Job_Slip__c>();
        if (!slipIds.isEmpty()) {
            slips = Database.query('SELECT ' + String.join(fieldsOf(Job_Slip__c.SObjectType), ', ') + ', ' + SLIP_RELATED
                + ' FROM Job_Slip__c WHERE Id IN :slipIds ORDER BY Slip_Date__c');
            Set<Id> companyIds = new Set<Id>{ WorkshopProfileService.primaryId() };
            for (Job_Slip__c s : slips) {
                companyIds.add(s.Workshop_Profile__c);
            }
            companyIds.remove(null);
            SlipFile file = new SlipFile();
            file.format = 1;
            file.slips = slips;
            file.companies = new Map<String, Workshop_Profile__c>();
            for (Workshop_Profile__c c : (List<Workshop_Profile__c>) Database.query('SELECT ' + COMPANY_FIELDS + ' FROM Workshop_Profile__c WHERE Id IN :companyIds')) {
                file.companies.put(c.Id, c);
            }
            Id documentId = ArchiveStore.write(ArchiveStore.KIND_SLIPS, null, month, 'Job slips ' + month, JSON.serialize(file));
            expected.put(documentId, slips.size());
            for (Job_Slip__c s : slips) {
                Date d = s.Slip_Date__c != null ? s.Slip_Date__c : s.CreatedDate.date();
                ArchiveStore.IndexEntry e = entryFor(s.Id, KIND_SLIP, s.Name, d, s.Customer__r, s.Vehicle__r, documentId);
                e.cu = s.Customer__c;
                e.ve = s.Vehicle__c;
                e.s = s.Visit_Reason__c;
                e.co = s.Workshop_Profile__c;
                entries.add(e);
            }
            outcome.slips = slips.size();
        }

        ArchiveStore.write(ArchiveStore.KIND_WORK_INDEX, null, null, 'Jobs and slips index ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss'),
            JSON.serialize(entries, true));

        // Read back before anything is deleted.
        Map<Id, String> back = ArchiveStore.readAll(filesFor(expected.keySet()));
        for (Id documentId : expected.keySet()) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(back.get(documentId));
            List<Object> records = (List<Object>) (body.containsKey('jobs') ? body.get('jobs') : body.get('slips'));
            if (records == null || records.size() != expected.get(documentId)) {
                throw new WorkArchiveException('An archive file did not read back as written. Nothing was archived.');
            }
        }

        // A job's mechanics (master-detail) go with it.
        List<SObject> going = new List<SObject>();
        going.addAll((List<SObject>) jobs);
        going.addAll((List<SObject>) slips);
        delete going;
        Database.emptyRecycleBin(going);
        return outcome;
    }

    private static ArchiveStore.IndexEntry entryFor(Id recordId, String kind, String name, Date d, Customer__c customer, Vehicle__c vehicle, Id documentId) {
        ArchiveStore.IndexEntry e = new ArchiveStore.IndexEntry();
        e.id = recordId;
        e.k = kind;
        e.n = name;
        e.d = d;
        e.c = customer == null ? null : customer.Name;
        e.p = customer == null ? null : customer.Phone__c;
        e.v = vehicle == null ? null : vehicle.Name;
        e.f = documentId;
        return e;
    }

    private static List<ArchiveStore.ArchiveFile> filesFor(Set<Id> documentIds) {
        List<ArchiveStore.ArchiveFile> files = new List<ArchiveStore.ArchiveFile>();
        for (Id documentId : documentIds) {
            ArchiveStore.ArchiveFile f = new ArchiveStore.ArchiveFile();
            f.documentId = documentId;
            files.add(f);
        }
        return files;
    }

    // Name, the custom fields less formulas, and the dates.
    private static List<String> fieldsOf(Schema.SObjectType t) {
        List<String> names = new List<String>{ 'Id', 'Name', 'CreatedDate', 'LastModifiedDate' };
        for (Schema.SObjectField f : t.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (d.isCustom() && !d.isCalculated()) {
                names.add(d.getName());
            }
        }
        return names;
    }

    // ---- finding --------------------------------------------------------

    /**
     * A customer's archived jobs and job slips, newest first. Also those
     * archived under the Id they had before being archived and brought back.
     */
    public static List<ArchiveStore.IndexEntry> forCustomer(Id customerId) {
        Set<String> ids = new Set<String>{ customerId };
        Map<String, String> moved = ArchiveStore.moved();
        for (String oldId : moved.keySet()) {
            if (String.valueOf(customerId).equals(moved.get(oldId))) {
                ids.add(oldId);
            }
        }
        Map<String, ArchiveStore.IndexEntry> byKey = new Map<String, ArchiveStore.IndexEntry>();
        for (ArchiveStore.IndexEntry e : ArchiveStore.workIndex()) {
            if ((e.k == KIND_JOB || e.k == KIND_SLIP) && e.cu != null && ids.contains(e.cu)) {
                byKey.put(String.valueOf(e.d) + '|' + e.n + '|' + e.id, e);
            }
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<ArchiveStore.IndexEntry> result = new List<ArchiveStore.IndexEntry>();
        for (Integer i = keys.size() - 1; i >= 0; i--) {
            result.add(byKey.get(keys[i]));
        }
        return result;
    }

    /** One archived job slip, with its company as it was (null if not kept). */
    public class FoundSlip {
        public Job_Slip__c slip;
        public Workshop_Profile__c company;
    }

    public static FoundSlip findSlip(Id documentId, Id slipId) {
        SlipFile file = (SlipFile) JSON.deserialize(ArchiveStore.read(documentId), SlipFile.class);
        for (Job_Slip__c s : file.slips) {
            if (s.Id == slipId) {
                FoundSlip found = new FoundSlip();
                found.slip = s;
                Id companyId = s.Workshop_Profile__c != null ? s.Workshop_Profile__c : WorkshopProfileService.primaryId();
                found.company = file.companies == null || companyId == null ? null : file.companies.get(companyId);
                return found;
            }
        }
        throw new WorkArchiveException('That job slip is not in this archive file.');
    }

    /** One archived job, with its mechanics' names. */
    public class FoundJob {
        public Job__c job;
        public List<String> mechanics;
    }

    public static FoundJob findJob(Id documentId, Id jobId) {
        JobFile file = (JobFile) JSON.deserialize(ArchiveStore.read(documentId), JobFile.class);
        for (Job__c j : file.jobs) {
            if (j.Id == jobId) {
                FoundJob found = new FoundJob();
                found.job = j;
                found.mechanics = file.mechanics == null || !file.mechanics.containsKey(j.Id) ? new List<String>() : file.mechanics.get(j.Id);
                return found;
            }
        }
        throw new WorkArchiveException('That job is not in this archive file.');
    }
}
