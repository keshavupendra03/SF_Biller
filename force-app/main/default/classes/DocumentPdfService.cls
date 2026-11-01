/**
 * Backs the documentPreview LWC. The preview itself is InvoicePdf.page (or
 * JobSlipPdf.page for job slips) in ?format=html mode inside an iframe;
 * this class produces the PDF.
 *
 * Two ways out, because the Salesforce Mobile App has no supported way for
 * an LWC to save a file to the phone (blob/data downloads silently do
 * nothing there):
 *  - getPdfDownload: base64 PDF for the LWC to download itself — desktop.
 *    Never persists a File — nothing to clean up here.
 *  - getPublicLink: stores the PDF as a File on the record and returns a
 *    link (ContentDistribution) that the phone's own browser/native share
 *    sheet can open without a Salesforce login — this is purely a
 *    mechanical step on the way to a one-tap mobile download now (no
 *    WhatsApp/customer sharing happens anymore, architecture.md §F), so
 *    the File it creates is scratch: scheduleCleanup below deletes it five
 *    minutes after this call, with BillEstimateFileCleanupScheduler's
 *    nightly sweep as a safety net for anything that slips past that.
 * One File per record while it's alive: regenerating within that five-
 * minute window adds a new file version rather than a second File.
 */
public with sharing class DocumentPdfService {

    @TestVisible
    private static final Integer LINK_VALID_DAYS = 30;

    public class DocumentPdfServiceException extends Exception {}

    public class PdfDownload {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String base64Data { get; set; }
    }

    public class PublicLink {
        @AuraEnabled public String documentNumber { get; set; }
        @AuraEnabled public String downloadUrl { get; set; }
    }

    private class DocumentInfo {
        String title;
        String documentNumber;
    }

    @AuraEnabled
    public static PdfDownload getPdfDownload(Id recordId) {
        DocumentInfo info = loadInfo(recordId);
        PdfDownload download = new PdfDownload();
        download.fileName = info.title + '.pdf';
        download.base64Data = EncodingUtil.base64Encode(renderPdf(recordId));
        return download;
    }

    @AuraEnabled
    public static PublicLink getPublicLink(Id recordId) {
        DocumentInfo info = loadInfo(recordId);
        Id documentId = saveFileVersion(recordId, info.title, renderPdf(recordId));
        Datetime expiresAt = Datetime.now().addDays(LINK_VALID_DAYS);

        List<ContentDistribution> existing = [
            SELECT Id FROM ContentDistribution
            WHERE ContentDocumentId = :documentId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Id distributionId;
        if (existing.isEmpty()) {
            ContentVersion latest = [
                SELECT Id FROM ContentVersion WHERE ContentDocumentId = :documentId AND IsLatest = true
            ];
            ContentDistribution distribution = new ContentDistribution(
                Name = info.title,
                ContentVersionId = latest.Id,
                PreferencesAllowViewInBrowser = true,
                PreferencesAllowOriginalDownload = true,
                PreferencesAllowPDFDownload = true,
                PreferencesLinkLatestVersion = true,
                PreferencesNotifyOnVisit = false,
                PreferencesPasswordRequired = false,
                PreferencesExpires = true,
                ExpiryDate = expiresAt
            );
            insert distribution;
            distributionId = distribution.Id;
        } else {
            distributionId = existing[0].Id;
            update new ContentDistribution(Id = distributionId, PreferencesExpires = true, ExpiryDate = expiresAt);
        }

        ContentDistribution saved = [
            SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :distributionId
        ];

        scheduleCleanup(documentId);

        PublicLink link = new PublicLink();
        link.documentNumber = info.documentNumber;
        link.downloadUrl = saved.ContentDownloadUrl;
        return link;
    }

    /**
     * This File only ever exists to hand the Mobile App's native share
     * sheet a real URL (it can't share raw bytes) on the way to an
     * immediate download — nothing downstream keeps the link alive past
     * that, so there's no reason to keep the File either. Skipped in
     * tests: scheduling here would leave a CronTrigger behind for every
     * test run that calls getPublicLink, and the batch's own deletion
     * logic is already covered directly by BillEstimateFileCleanupBatchTest.
     */
    private static void scheduleCleanup(Id contentDocumentId) {
        if (Test.isRunningTest()) {
            return;
        }
        String jobName = 'Bill/Estimate File Cleanup ' + contentDocumentId + ' ' + System.currentTimeMillis();
        System.scheduleBatch(new BillEstimateFileCleanupBatch(new Set<Id>{ contentDocumentId }), jobName, 5);
    }

    private static Blob renderPdf(Id recordId) {
        PageReference page = isJobSlip(recordId) ? Page.JobSlipPdf : Page.InvoicePdf;
        page.getParameters().put('id', recordId);
        // getContentAsPDF() isn't allowed in test context.
        return Test.isRunningTest() ? Blob.valueOf('test-pdf') : page.getContentAsPDF();
    }

    private static Id saveFileVersion(Id recordId, String title, Blob body) {
        List<ContentDocumentLink> existing = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
              AND ContentDocument.Title = :title
            LIMIT 1
        ];
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = body
        );
        if (existing.isEmpty()) {
            version.FirstPublishLocationId = recordId;
        } else {
            version.ContentDocumentId = existing[0].ContentDocumentId;
        }
        insert version;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    // A job slip PDF is rendered from the saved Job_Slip__c, or — for a
    // blank slip to fill by hand — from the Vehicle__c/Customer__c it's
    // printed for (JobSlipPdfController prefills only those details).
    private static Boolean isJobSlip(Id recordId) {
        SObjectType type = recordId.getSObjectType();
        return type == Job_Slip__c.SObjectType || type == Vehicle__c.SObjectType || type == Customer__c.SObjectType;
    }

    private static DocumentInfo loadInfo(Id recordId) {
        if (recordId == null) {
            throw new DocumentPdfServiceException('A bill or estimate is required.');
        }
        DocumentInfo info = new DocumentInfo();
        if (recordId.getSObjectType() == Job_Slip__c.SObjectType) {
            Job_Slip__c slip = [SELECT Name FROM Job_Slip__c WHERE Id = :recordId];
            info.documentNumber = slip.Name;
            info.title = 'Job Slip ' + slip.Name;
            return info;
        }
        if (recordId.getSObjectType() == Vehicle__c.SObjectType) {
            Vehicle__c vehicle = [SELECT Name FROM Vehicle__c WHERE Id = :recordId];
            info.documentNumber = 'Job Slip ' + vehicle.Name;
            info.title = 'Blank Job Slip ' + sanitize(vehicle.Name);
            return info;
        }
        if (recordId.getSObjectType() == Customer__c.SObjectType) {
            Customer__c customer = [SELECT Name FROM Customer__c WHERE Id = :recordId];
            info.documentNumber = 'Job Slip ' + customer.Name;
            info.title = 'Blank Job Slip ' + sanitize(customer.Name);
            return info;
        }
        if (recordId.getSObjectType() == Bill__c.SObjectType) {
            Bill__c bill = [SELECT Invoice_Number__c, Version_Number__c FROM Bill__c WHERE Id = :recordId];
            info.documentNumber = bill.Invoice_Number__c;
            info.title = sanitize(bill.Invoice_Number__c) + versionSuffix(bill.Version_Number__c);
            return info;
        }
        if (recordId.getSObjectType() == Estimate__c.SObjectType) {
            Estimate__c estimate = [SELECT Name, Version_Number__c FROM Estimate__c WHERE Id = :recordId];
            info.documentNumber = estimate.Name;
            info.title = sanitize(estimate.Name) + versionSuffix(estimate.Version_Number__c);
            return info;
        }
        throw new DocumentPdfServiceException('PDFs are only available for bills, estimates and job slips.');
    }

    private static String versionSuffix(Decimal versionNumber) {
        return versionNumber == null || versionNumber <= 1 ? '' : ' v' + versionNumber.intValue();
    }

    // Invoice numbers contain slashes (INV/2026-27/0001), which aren't valid in a file name.
    private static String sanitize(String value) {
        return String.isBlank(value) ? 'Document' : value.replace('/', '-');
    }
}
