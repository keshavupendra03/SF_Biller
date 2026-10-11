/**
 * The nightly safety-net sweep for BillEstimateFileCleanupBatch —
 * scheduled once (see architecture.md §F for the exact
 * System.schedule call), not re-scheduled per bill/estimate the way
 * DocumentPdfService's five-minute cleanup is.
 */
public with sharing class BillEstimateFileCleanupScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        Database.executeBatch(new BillEstimateFileCleanupBatch(), 200);
    }
}
