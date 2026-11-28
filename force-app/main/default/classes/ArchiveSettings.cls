/**
 * The org's archive rules (Archive_Settings__c, architecture.md, Forty-fifth):
 * how old each kind of data must be before it's archived, or for estimates
 * deleted. Blank values use the defaults agreed with the user (2026-11-26).
 * Archiving is off until the workshop switches it on.
 */
public with sharing class ArchiveSettings {

    public class ArchiveSettingsException extends Exception {}

    public static final Integer DEFAULT_BILLS = 18;
    public static final Integer DEFAULT_ESTIMATES = 6;
    public static final Integer DEFAULT_JOBS = 6;
    public static final Integer DEFAULT_JOB_SLIPS = 6;
    public static final Integer DEFAULT_CUSTOMERS = 24;
    public static final Integer DEFAULT_MECHANIC_MONTHS = 24;
    public static final Integer DEFAULT_STORAGE_ALERT = 70;
    // Bills younger than this are never archived, whatever is typed:
    // recent months are still being billed, changed and filed.
    public static final Integer MIN_BILL_MONTHS = 3;

    public class Rules {
        @AuraEnabled public Boolean isOn { get; set; }
        @AuraEnabled public Integer billsAfterMonths { get; set; }
        @AuraEnabled public Integer estimatesAfterMonths { get; set; }
        @AuraEnabled public Integer jobsAfterMonths { get; set; }
        @AuraEnabled public Integer jobSlipsAfterMonths { get; set; }
        @AuraEnabled public Integer customersDormantMonths { get; set; }
        @AuraEnabled public Integer mechanicMonthsAfterMonths { get; set; }
        @AuraEnabled public Integer storageAlertPercent { get; set; }
        @AuraEnabled public Datetime lastRun { get; set; }
        @AuraEnabled public String lastResult { get; set; }
    }

    public static Rules current() {
        Archive_Settings__c s = Archive_Settings__c.getOrgDefaults();
        Rules r = new Rules();
        r.isOn = s != null && s.Archiving_On__c == true;
        r.billsAfterMonths = orDefault(s == null ? null : s.Bills_After_Months__c, DEFAULT_BILLS);
        r.estimatesAfterMonths = orDefault(s == null ? null : s.Estimates_After_Months__c, DEFAULT_ESTIMATES);
        r.jobsAfterMonths = orDefault(s == null ? null : s.Jobs_After_Months__c, DEFAULT_JOBS);
        r.jobSlipsAfterMonths = orDefault(s == null ? null : s.Job_Slips_After_Months__c, DEFAULT_JOB_SLIPS);
        r.customersDormantMonths = orDefault(s == null ? null : s.Customers_Dormant_Months__c, DEFAULT_CUSTOMERS);
        r.mechanicMonthsAfterMonths = orDefault(s == null ? null : s.Mechanic_Months_After_Months__c, DEFAULT_MECHANIC_MONTHS);
        r.storageAlertPercent = orDefault(s == null ? null : s.Storage_Alert_Percent__c, DEFAULT_STORAGE_ALERT);
        r.lastRun = s == null ? null : s.Last_Run__c;
        r.lastResult = s == null ? null : s.Last_Result__c;
        return r;
    }

    public static Rules save(Rules r) {
        if (r == null) {
            throw new ArchiveSettingsException('Nothing to save.');
        }
        requireMonths(r.billsAfterMonths, MIN_BILL_MONTHS, 'Bills');
        requireMonths(r.estimatesAfterMonths, 1, 'Estimates');
        requireMonths(r.jobsAfterMonths, 1, 'Jobs');
        requireMonths(r.jobSlipsAfterMonths, 1, 'Job slips');
        requireMonths(r.customersDormantMonths, 6, 'Customers');
        requireMonths(r.mechanicMonthsAfterMonths, 3, 'Attendance');
        if (r.storageAlertPercent == null || r.storageAlertPercent < 10 || r.storageAlertPercent > 100) {
            throw new ArchiveSettingsException('The storage warning must be between 10% and 100%.');
        }
        Archive_Settings__c s = orgRecord();
        s.Archiving_On__c = r.isOn == true;
        s.Bills_After_Months__c = r.billsAfterMonths;
        s.Estimates_After_Months__c = r.estimatesAfterMonths;
        s.Jobs_After_Months__c = r.jobsAfterMonths;
        s.Job_Slips_After_Months__c = r.jobSlipsAfterMonths;
        s.Customers_Dormant_Months__c = r.customersDormantMonths;
        s.Mechanic_Months_After_Months__c = r.mechanicMonthsAfterMonths;
        s.Storage_Alert_Percent__c = r.storageAlertPercent;
        upsert s;
        return current();
    }

    public static void recordRun(String result) {
        Archive_Settings__c s = orgRecord();
        s.Last_Run__c = Datetime.now();
        s.Last_Result__c = result == null ? null : result.abbreviate(255);
        upsert s;
    }

    private static Archive_Settings__c orgRecord() {
        Archive_Settings__c s = Archive_Settings__c.getOrgDefaults();
        if (s == null || s.Id == null) {
            s = new Archive_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        return s;
    }

    private static Integer orDefault(Decimal value, Integer fallback) {
        return value == null ? fallback : value.intValue();
    }

    private static void requireMonths(Integer months, Integer minimum, String what) {
        if (months == null || months < minimum || months > 240) {
            throw new ArchiveSettingsException(what + ': type a number of months from ' + minimum + ' to 240.');
        }
    }
}
