/**
 * Deletes the PDF Files (ContentDocument, and with it its ContentVersion
 * and any ContentDistribution) generated for Bill__c/Estimate__c/
 * Job_Slip__c records. (Blank job slips are saved on the Customer__c/
 * Vehicle__c/Workshop_Profile__c they're printed for; those rely on the
 * five-minute cleanup alone, since sweeping every file on recently created
 * customers isn't something this batch should do.)
 * These are disposable scratch artifacts now — downloading happens
 * immediately client-side and nothing is shared via a stored link
 * anymore (architecture.md §F), so there's no reason to keep them.
 *
 * Two ways this runs:
 *  - with a specific set of ContentDocument Ids: the near-immediate
 *    cleanup DocumentPdfService.getPublicLink schedules five minutes
 *    after generating each file — the primary mechanism.
 *  - no-arg: the nightly "yesterday" sweep (via
 *    BillEstimateFileCleanupScheduler), a safety net for anything that
 *    slipped past the five-minute cleanup above.
 */
public with sharing class BillEstimateFileCleanupBatch implements Database.Batchable<SObject> {

    private Set<Id> specificContentDocumentIds;

    public BillEstimateFileCleanupBatch() {
    }

    public BillEstimateFileCleanupBatch(Set<Id> specificContentDocumentIds) {
        this.specificContentDocumentIds = specificContentDocumentIds;
    }

    // How far back to look for candidate Bill/Estimate records when
    // scoping the nightly sweep below — wide enough to comfortably cover
    // "a file created yesterday", never meant to reach arbitrarily far
    // into the past (see the start() comment for why).
    @TestVisible
    private static final Integer CANDIDATE_RECORD_LOOKBACK_DAYS = 2;

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (specificContentDocumentIds != null) {
            return Database.getQueryLocator([
                SELECT Id FROM ContentDocument WHERE Id IN :specificContentDocumentIds
            ]);
        }

        // ContentDocumentLink's own implementation restriction requires
        // filtering by a specific ContentDocumentId or LinkedEntityId (via
        // "=" or "IN"), so this can't start from "every file linked to a
        // Bill/Estimate" directly — it has to start from a bounded set of
        // candidate Bill/Estimate record Ids instead. This is the nightly
        // safety net, not the primary cleanup mechanism (that's the
        // five-minute cleanup DocumentPdfService schedules per file), so
        // scoping it to recently-created records rather than every
        // Bill__c/Estimate__c ever is an acceptable, documented limit: a
        // file regenerated for a bill/estimate older than
        // CANDIDATE_RECORD_LOOKBACK_DAYS would be missed by this sweep.
        Date startOfYesterday = Date.today().addDays(-1);
        Date lookback = Date.today().addDays(-CANDIDATE_RECORD_LOOKBACK_DAYS);

        Set<Id> candidateRecordIds = new Set<Id>();
        for (Bill__c b : [SELECT Id FROM Bill__c WHERE CreatedDate >= :lookback]) {
            candidateRecordIds.add(b.Id);
        }
        for (Estimate__c e : [SELECT Id FROM Estimate__c WHERE CreatedDate >= :lookback]) {
            candidateRecordIds.add(e.Id);
        }
        for (Job_Slip__c j : [SELECT Id FROM Job_Slip__c WHERE CreatedDate >= :lookback]) {
            candidateRecordIds.add(j.Id);
        }

        Set<Id> documentIds = new Set<Id>();
        if (!candidateRecordIds.isEmpty()) {
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :candidateRecordIds
            ]) {
                documentIds.add(link.ContentDocumentId);
            }
        }

        return Database.getQueryLocator([
            SELECT Id FROM ContentDocument
            WHERE Id IN :documentIds
              AND CreatedDate >= :startOfYesterday AND CreatedDate < :Date.today()
        ]);
    }

    public void execute(Database.BatchableContext context, List<ContentDocument> scope) {
        delete scope;
    }

    public void finish(Database.BatchableContext context) {
    }
}
