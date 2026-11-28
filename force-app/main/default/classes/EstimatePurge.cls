/**
 * Deletes old estimates (architecture.md, Forty-fifth): every version of an
 * estimate whose latest version is dated more than Archive_Settings__c's
 * months ago. An estimate isn't a GST document, so nothing of it needs
 * keeping; a bill made from one keeps its own copy and only loses the link
 * (EstimateController.deleteEstimate does the same).
 */
public without sharing class EstimatePurge {

    public static Date deleteBefore(ArchiveSettings.Rules rules) {
        return Date.today().addMonths(-Math.max(rules.estimatesAfterMonths, 1));
    }

    /** How many estimates (counting every version) would go now. */
    public static Integer count(ArchiveSettings.Rules rules) {
        Set<Id> roots = oldRoots(rules, 2000);
        return roots.isEmpty() ? 0 : [SELECT COUNT() FROM Estimate__c WHERE Id IN :roots OR Root_Estimate__c IN :roots];
    }

    /** Deletes up to a few hundred old estimates; returns how many went. */
    public static Integer run(ArchiveSettings.Rules rules) {
        Set<Id> roots = oldRoots(rules, 400);
        if (roots.isEmpty()) {
            return 0;
        }
        List<Estimate__c> versions = [SELECT Id FROM Estimate__c WHERE Id IN :roots OR Root_Estimate__c IN :roots];
        delete versions;
        Database.emptyRecycleBin(versions);
        return versions.size();
    }

    private static Set<Id> oldRoots(ArchiveSettings.Rules rules, Integer max) {
        Date before = deleteBefore(rules);
        Set<Id> roots = new Set<Id>();
        for (Estimate__c e : [
            SELECT Id, Root_Estimate__c FROM Estimate__c
            WHERE Is_Latest_Version__c = true AND Estimate_Date__c < :before
            ORDER BY Estimate_Date__c LIMIT :max
        ]) {
            roots.add(e.Root_Estimate__c != null ? e.Root_Estimate__c : e.Id);
        }
        return roots;
    }
}
