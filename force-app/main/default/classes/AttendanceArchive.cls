/**
 * Archives old attendance months (Mechanic_Month__c) into Files (ArchiveStore,
 * architecture.md, Forty-seventh): months that ended more than
 * Archive_Settings__c.Mechanic_Months_After_Months__c ago.
 *
 * Each month's opening balance is the month before's closing balance
 * (MechanicPay), so archiving a mechanic's months keeps the last one's closing
 * balance and month on the mechanic (Archived_Balance__c, Archived_To__c).
 * MechanicPay brings that balance forward into the first month still in
 * Salesforce, and refuses changes to archived months (they would otherwise be
 * made again, blank, and every later balance worked out without them). The
 * Attendance screen still shows an archived month, read-only, from its file.
 */
public without sharing class AttendanceArchive {
    // Without sharing: archiving runs for the whole org, at night as well.

    public class AttendanceArchiveException extends Exception {}

    public static final String KIND_MONTH = 'month';
    @TestVisible
    private static Integer maxMonths = 1000;

    public class MonthsFile {
        public Integer format;
        public List<Mechanic_Month__c> months;
    }

    public class Plan {
        @AuraEnabled public Integer months { get; set; }
        @AuraEnabled public Date before { get; set; }
    }

    /** Months starting before this are archived. */
    public static Date before(ArchiveSettings.Rules rules) {
        return Date.today().toStartOfMonth().addMonths(-Math.max(rules.mechanicMonthsAfterMonths, 3));
    }

    public static Plan plan(ArchiveSettings.Rules rules) {
        Plan p = new Plan();
        p.before = before(rules);
        Date cut = p.before;
        p.months = [SELECT COUNT() FROM Mechanic_Month__c WHERE Month__c < :cut];
        return p;
    }

    /** Archives up to maxMonths old months, oldest first, in one transaction. Returns how many. */
    public static Integer archiveReady(ArchiveSettings.Rules rules) {
        Date cut = before(rules);
        // Oldest first, so a mechanic's archived months are always the earliest ones.
        List<Id> ids = new List<Id>();
        for (Mechanic_Month__c m : [SELECT Id FROM Mechanic_Month__c WHERE Month__c < :cut ORDER BY Month__c, Mechanic__c LIMIT :maxMonths]) {
            ids.add(m.Id);
        }
        if (ids.isEmpty()) {
            return 0;
        }
        List<Mechanic_Month__c> months = Database.query('SELECT ' + String.join(fieldsOf(), ', ') + ', Mechanic__r.Name'
            + ' FROM Mechanic_Month__c WHERE Id IN :ids FOR UPDATE');

        // Each mechanic's last archived month and its closing balance.
        Map<Id, Mechanic_Month__c> lastOf = new Map<Id, Mechanic_Month__c>();
        for (Mechanic_Month__c m : months) {
            Mechanic_Month__c known = lastOf.get(m.Mechanic__c);
            if (known == null || m.Month__c > known.Month__c) {
                lastOf.put(m.Mechanic__c, m);
            }
        }
        Set<Id> mechanicIds = lastOf.keySet();
        List<Mechanic__c> changes = new List<Mechanic__c>();
        for (Mechanic__c mechanic : [SELECT Id, Archived_To__c FROM Mechanic__c WHERE Id IN :mechanicIds FOR UPDATE]) {
            Mechanic_Month__c last = lastOf.get(mechanic.Id);
            if (mechanic.Archived_To__c == null || last.Month__c > mechanic.Archived_To__c) {
                changes.add(new Mechanic__c(
                    Id = mechanic.Id,
                    Archived_To__c = last.Month__c,
                    Archived_Balance__c = last.Closing_Balance__c == null ? 0 : last.Closing_Balance__c
                ));
            }
        }

        MonthsFile file = new MonthsFile();
        file.format = 1;
        file.months = months;
        String runMonth = Datetime.now().format('yyyy-MM');
        Id documentId = ArchiveStore.write(ArchiveStore.KIND_ATTENDANCE, null, runMonth, 'Attendance ' + runMonth, JSON.serialize(file));
        List<ArchiveStore.IndexEntry> entries = new List<ArchiveStore.IndexEntry>();
        for (Mechanic_Month__c m : months) {
            ArchiveStore.IndexEntry e = new ArchiveStore.IndexEntry();
            e.id = m.Id;
            e.k = KIND_MONTH;
            e.n = m.Mechanic__r == null ? null : m.Mechanic__r.Name;
            e.d = m.Month__c;
            e.me = m.Mechanic__c;
            e.t = m.Closing_Balance__c;
            e.f = documentId;
            entries.add(e);
        }
        ArchiveStore.write(ArchiveStore.KIND_WORK_INDEX, null, null, 'Attendance index ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss'),
            JSON.serialize(entries, true));

        MonthsFile back = (MonthsFile) JSON.deserialize(ArchiveStore.read(documentId), MonthsFile.class);
        if (back.months == null || back.months.size() != months.size()) {
            throw new AttendanceArchiveException('The attendance archive file did not read back as written. Nothing was archived.');
        }

        update changes;
        delete months;
        Database.emptyRecycleBin(months);
        return months.size();
    }

    private static List<String> fieldsOf() {
        List<String> names = new List<String>{ 'Id', 'Name', 'CreatedDate' };
        for (Schema.SObjectField f : Mechanic_Month__c.SObjectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (d.isCustom() && !d.isCalculated()) {
                names.add(d.getName());
            }
        }
        return names;
    }

    // ---- reading --------------------------------------------------------

    /** Archived months for this month, by mechanic Id. */
    public static Map<Id, Mechanic_Month__c> monthsOf(Set<Id> mechanicIds, Date month) {
        Date start = month.toStartOfMonth();
        Map<Id, Set<String>> wantedByFile = new Map<Id, Set<String>>();
        for (ArchiveStore.IndexEntry e : ArchiveStore.workIndex()) {
            if (e.k == KIND_MONTH && e.d == start && e.me != null && (mechanicIds == null || mechanicIds.contains(Id.valueOf(e.me)))) {
                Id documentId = e.f;
                if (!wantedByFile.containsKey(documentId)) {
                    wantedByFile.put(documentId, new Set<String>());
                }
                wantedByFile.get(documentId).add(e.id);
            }
        }
        Map<Id, Mechanic_Month__c> found = new Map<Id, Mechanic_Month__c>();
        for (Id documentId : wantedByFile.keySet()) {
            MonthsFile file = (MonthsFile) JSON.deserialize(ArchiveStore.read(documentId), MonthsFile.class);
            for (Mechanic_Month__c m : file.months) {
                if (wantedByFile.get(documentId).contains(m.Id)) {
                    found.put(m.Mechanic__c, m);
                }
            }
        }
        return found;
    }
}
