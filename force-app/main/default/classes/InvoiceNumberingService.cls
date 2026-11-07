/**
 * Sequential, FY-based invoice numbers that never collide or skip under
 * concurrent bill creation (architecture.md §C.1). Salesforce is the sole
 * writer in this project, so there is no placeholder/reconciliation state —
 * each company's Workshop_Profile__c row holds its own counter and prefix (a
 * GSTIN keeps its own series), and assignNextInvoiceNumber locks that row with
 * FOR UPDATE for the duration of the transaction so concurrent callers
 * serialize instead of racing each other.
 */
public with sharing class InvoiceNumberingService {

    public class InvoiceNumberingException extends Exception {}

    public class InvoiceNumberResult {
        public String invoiceNumber;
        public String financialYear;
    }

    /**
     * Indian financial year (1 April - 31 March), e.g. "2026-27".
     */
    public static String financialYearFor(Date asOf) {
        Integer startYear = asOf.month() >= 4 ? asOf.year() : asOf.year() - 1;
        Integer endYearSuffix = Math.mod(startYear + 1, 100);
        String suffix = endYearSuffix < 10
            ? '0' + String.valueOf(endYearSuffix)
            : String.valueOf(endYearSuffix);
        return String.valueOf(startYear) + '-' + suffix;
    }

    /**
     * Assigns the next sequential invoice number for the current financial
     * year, for the primary company. Precondition: a Workshop_Profile__c row
     * already exists in the org (seeded once, not lazily created here — a lazy
     * get-or-create here would itself race under concurrent callers with
     * no row yet, which SOQL's FOR UPDATE can't protect against since it
     * locks rows that exist, not the absence of one).
     */
    public static InvoiceNumberResult assignNextInvoiceNumber() {
        return assignNextInvoiceNumber(null);
    }

    public static InvoiceNumberResult assignNextInvoiceNumber(Id workshopProfileId) {
        String fy = financialYearFor(Date.today());

        // FOR UPDATE can't be combined with ORDER BY, so find the row first.
        Id profileId = workshopProfileId != null ? workshopProfileId : WorkshopProfileService.primaryId();
        List<Workshop_Profile__c> profiles = [
            SELECT Id, Invoice_Prefix__c, Invoice_Sequence_Financial_Year__c, Invoice_Sequence_Last_Number__c
            FROM Workshop_Profile__c
            WHERE Id = :profileId
            FOR UPDATE
        ];
        if (profiles.isEmpty()) {
            throw new InvoiceNumberingException(
                'No Workshop_Profile__c row exists to hold the invoice sequence ' +
                'counter. One must be seeded before bills can be numbered.'
            );
        }
        Workshop_Profile__c profile = profiles[0];

        Boolean continuingFy = fy.equals(profile.Invoice_Sequence_Financial_Year__c);
        Integer currentLast = profile.Invoice_Sequence_Last_Number__c == null
            ? 0
            : profile.Invoice_Sequence_Last_Number__c.intValue();
        Integer nextSequence = continuingFy ? currentLast + 1 : 1;

        profile.Invoice_Sequence_Financial_Year__c = fy;
        profile.Invoice_Sequence_Last_Number__c = nextSequence;
        update profile;

        InvoiceNumberResult result = new InvoiceNumberResult();
        result.invoiceNumber = WorkshopProfileService.invoicePrefix(profile) + '/' + fy + '/' + String.valueOf(nextSequence).leftPad(4, '0');
        result.financialYear = fy;
        return result;
    }
}
