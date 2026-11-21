/**
 * The month lock for GST (architecture.md §D.1, stage G2). Once a company's
 * GST returns are filed up to a month, a bill dated in or before it can't be
 * added, changed (a new version replaces its number) or deleted (cancelled),
 * because the filed return already reports it as it was. Estimates aren't
 * GST documents and are never locked.
 *
 * Workshop_Profile__c.GST_Filed_Up_To__c holds the last day of the last
 * filed month; blank means nothing is filed yet.
 */
public with sharing class GstFilingLock {

    public class GstFilingLockException extends Exception {}

    public static Boolean isLocked(Date filedUpTo, Date documentDate) {
        return filedUpTo != null && documentDate != null && documentDate <= filedUpTo;
    }

    /** action: what can't be done to the bill: 'added', 'changed' or 'deleted'. */
    public static String lockedMessage(Date filedUpTo, Date documentDate, String action) {
        return 'GST returns are filed up to ' + monthName(filedUpTo) + ' for this company, so a bill dated '
            + formatDate(documentDate) + ' can\'t be ' + action + '. If that return isn\'t really filed yet, '
            + 'change "GST returns filed up to" on the Workshop Profile.';
    }

    /** Refuses, in words a screen can show, a bill dated in a filed month. A blank company is the primary one. */
    public static void requireOpen(Id companyId, Date documentDate, String action) {
        Date filedUpTo = filedUpTo(companyId);
        if (isLocked(filedUpTo, documentDate)) {
            throw new GstFilingLockException(lockedMessage(filedUpTo, documentDate, action));
        }
    }

    public static Date filedUpTo(Id companyId) {
        Id profileId = companyId != null ? companyId : WorkshopProfileService.primaryId();
        if (profileId == null) {
            return null;
        }
        List<Workshop_Profile__c> profiles = [SELECT GST_Filed_Up_To__c FROM Workshop_Profile__c WHERE Id = :profileId];
        return profiles.isEmpty() ? null : profiles[0].GST_Filed_Up_To__c;
    }

    /** The last day of the month a date falls in. */
    public static Date monthEnd(Date day) {
        return day.toStartOfMonth().addMonths(1).addDays(-1);
    }

    /** "October 2026". */
    public static String monthName(Date day) {
        return Datetime.newInstance(day.year(), day.month(), 1).format('MMMM yyyy');
    }

    /** "05-10-2026", as bills are dated on screen and in print. */
    public static String formatDate(Date day) {
        return String.valueOf(day.day()).leftPad(2, '0') + '-' + String.valueOf(day.month()).leftPad(2, '0') + '-' + day.year();
    }
}
