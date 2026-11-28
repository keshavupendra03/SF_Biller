/**
 * Archives old bills into Files (ArchiveStore), one company-month at a time,
 * and brings one back if it's needed again (architecture.md, Forty-fifth).
 *
 * Which bills: dated more than Archive_Settings__c's months ago, and, for a
 * company that files GST returns, in a month already marked filed (so no
 * return still to be made is missing them, and no new bill can be dated into
 * that month). A bill goes with its whole group (every version, and both
 * halves of an insurance claim with their versions) or not at all.
 *
 * Archiving one month is one transaction: the month file and its index are
 * written, read back and checked, the company's last invoice number for each
 * financial year is kept (so a number is never reused), what customers paid
 * is added to Customer__c.Archived_Spend__c, and only then are the bills
 * deleted and emptied from the Recycle Bin. Any failure undoes all of it.
 *
 * A bill is archived as the Bill__c record itself, with the customer, party,
 * vehicle and paired-bill details it prints with, so InvoicePdfController can
 * print it exactly as before.
 */
public without sharing class BillArchive {
    // Without sharing: archiving runs for the whole org, at night as well.

    public class BillArchiveException extends Exception {}

    public static final String SNAPSHOT_FIELDS =
        'Id, Name, Workshop_Profile__c, Invoice_Number__c, Invoice_Sequence__c, Financial_Year__c, Bill_Date__c, Status__c, Notes__c, '
        + 'Place_Of_Supply__c, Recipient_GSTIN__c, Is_Cancelled__c, Cancelled_On__c, Is_Latest_Version__c, Version_Number__c, '
        + 'Previous_Version__c, Root_Bill__c, Paired_Bill__c, Paired_Bill__r.Invoice_Number__c, Source_Estimate__c, Job__c, '
        + 'Subtotal__c, GST_Amount__c, Round_Off__c, Total_Amount__c, Amount_Paid__c, Line_Items__c, Payments__c, '
        + 'Customer__c, Customer__r.Name, Customer__r.Phone__c, Customer__r.Address__c, Customer__r.GSTIN__c, Customer__r.State__c, '
        + 'Bill_To_Party__c, Bill_To_Party__r.Name, Bill_To_Party__r.Address__c, Bill_To_Party__r.Contact_Phone__c, '
        + 'Bill_To_Party__r.GSTIN__c, Bill_To_Party__r.State__c, '
        + 'Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c, Vehicle__r.Chassis_Number__c, '
        + 'Job__r.Vehicle__c, Job__r.Vehicle__r.Name, Job__r.Vehicle__r.Make__c, Job__r.Vehicle__r.Model__c, Job__r.Vehicle__r.Chassis_Number__c, '
        + 'CreatedDate';
    private static final String COMPANY_FIELDS =
        'Id, Name, Address__c, Phone__c, Email__c, GSTIN__c, State__c, GST_Registration_Type__c, Bank_Name__c, Bank_Account_No__c, '
        + 'Bank_IFSC__c, Bank_Account_Holder__c, Terms_And_Conditions__c, Invoice_Last_Numbers__c, GST_Filed_Up_To__c';

    /** What one month file holds. */
    public class MonthFile {
        public Integer format;
        public String month;
        public Workshop_Profile__c company;
        public List<Bill__c> bills;
    }

    public class Plan {
        @AuraEnabled public Integer billCount { get; set; }
        @AuraEnabled public List<String> months { get; set; }
        @AuraEnabled public Date archiveBefore { get; set; }
    }

    public class Outcome {
        @AuraEnabled public Integer billsArchived { get; set; }
        @AuraEnabled public String month { get; set; }
        @AuraEnabled public Boolean moreToDo { get; set; }
    }

    // Set while a bill is brought back: it keeps its number, and its filed
    // month doesn't stop it (BillTriggerHandler).
    public static Boolean restoring = false;

    // ---- which bills ----------------------------------------------------

    /** Bills dated before this are old enough. */
    public static Date archiveBefore(ArchiveSettings.Rules rules) {
        Integer months = Math.max(rules.billsAfterMonths, ArchiveSettings.MIN_BILL_MONTHS);
        return Date.today().toStartOfMonth().addMonths(-months);
    }

    // Per company: bills dated before this may go. A company that files GST
    // returns only up to its filed month.
    private static Map<Id, Date> limitsByCompany(ArchiveSettings.Rules rules) {
        Date before = archiveBefore(rules);
        Map<Id, Date> limits = new Map<Id, Date>();
        for (Workshop_Profile__c company : [SELECT Id, GST_Registration_Type__c, GST_Filed_Up_To__c FROM Workshop_Profile__c]) {
            Date limitDate = before;
            if (!'Unregistered'.equals(company.GST_Registration_Type__c)) {
                Date filedUpTo = company.GST_Filed_Up_To__c;
                Date afterFiled = filedUpTo == null ? null : filedUpTo.addDays(1);
                limitDate = afterFiled == null || afterFiled < before ? afterFiled : before;
            }
            if (limitDate != null) {
                limits.put(company.Id, limitDate);
            }
        }
        return limits;
    }

    private static Id companyOf(Bill__c bill) {
        return bill.Workshop_Profile__c != null ? bill.Workshop_Profile__c : WorkshopProfileService.primaryId();
    }

    private static Boolean isReady(Bill__c bill, Map<Id, Date> limits) {
        Date limitDate = limits.get(companyOf(bill));
        return limitDate != null && bill.Bill_Date__c != null && bill.Bill_Date__c < limitDate;
    }

    /** What archiving would do now: bills ready and their months. */
    public static Plan plan(ArchiveSettings.Rules rules) {
        Map<Id, Date> limits = limitsByCompany(rules);
        Plan p = new Plan();
        p.archiveBefore = archiveBefore(rules);
        p.billCount = 0;
        Set<String> months = new Set<String>();
        Date latest = latestLimit(limits);
        if (latest != null) {
            for (Bill__c b : [
                SELECT Id, Bill_Date__c, Workshop_Profile__c FROM Bill__c WHERE Bill_Date__c < :latest ORDER BY Bill_Date__c LIMIT 10000
            ]) {
                if (isReady(b, limits)) {
                    p.billCount++;
                    months.add(String.valueOf(b.Bill_Date__c).left(7));
                }
            }
        }
        p.months = new List<String>(months);
        p.months.sort();
        return p;
    }

    private static Date latestLimit(Map<Id, Date> limits) {
        Date latest;
        for (Date d : limits.values()) {
            if (latest == null || d > latest) {
                latest = d;
            }
        }
        return latest;
    }

    // ---- archiving ------------------------------------------------------

    /**
     * Archives the oldest company-month that has a bill ready (with the whole
     * groups of its bills). Months whose groups all reach into newer bills are
     * passed over.
     */
    public static Outcome archiveNextMonth(ArchiveSettings.Rules rules) {
        Outcome outcome = new Outcome();
        outcome.billsArchived = 0;
        outcome.moreToDo = false;
        Map<Id, Date> limits = limitsByCompany(rules);
        Date latest = latestLimit(limits);
        if (latest == null) {
            return outcome;
        }
        List<Bill__c> candidates = new List<Bill__c>();
        for (Bill__c b : [
            SELECT Id, Bill_Date__c, Workshop_Profile__c, Root_Bill__c, Paired_Bill__c
            FROM Bill__c WHERE Bill_Date__c < :latest ORDER BY Bill_Date__c, Id LIMIT 2000
        ]) {
            if (isReady(b, limits)) {
                candidates.add(b);
            }
        }
        Set<String> triedMonths = new Set<String>();
        for (Bill__c first : candidates) {
            String key = companyOf(first) + '|' + String.valueOf(first.Bill_Date__c).left(7);
            if (triedMonths.contains(key)) {
                continue;
            }
            triedMonths.add(key);
            List<Bill__c> monthBills = new List<Bill__c>();
            for (Bill__c b : candidates) {
                if ((companyOf(b) + '|' + String.valueOf(b.Bill_Date__c).left(7)).equals(key)) {
                    monthBills.add(b);
                }
            }
            List<Bill__c> members = readyGroups(monthBills, limits);
            if (!members.isEmpty()) {
                archive(members);
                outcome.billsArchived = members.size();
                outcome.month = String.valueOf(first.Bill_Date__c).left(7);
                outcome.moreToDo = candidates.size() > members.size();
                return outcome;
            }
        }
        return outcome;
    }

    // The bills of these bills' groups, if every bill in a group is ready.
    private static List<Bill__c> readyGroups(List<Bill__c> seeds, Map<Id, Date> limits) {
        Set<Id> ids = new Set<Id>();
        for (Bill__c b : seeds) {
            ids.add(b.Id);
        }
        Map<Id, Bill__c> members = new Map<Id, Bill__c>();
        // Widen until nothing new is found: roots, their versions, and paired bills' versions.
        for (Integer round = 0; round < 5; round++) {
            Set<Id> roots = new Set<Id>();
            for (Bill__c b : [SELECT Id, Root_Bill__c, Paired_Bill__c FROM Bill__c WHERE Id IN :ids]) {
                roots.add(b.Root_Bill__c != null ? b.Root_Bill__c : b.Id);
                if (b.Paired_Bill__c != null) {
                    roots.add(b.Paired_Bill__c);
                }
            }
            Set<Id> found = new Set<Id>();
            for (Bill__c b : [
                SELECT Id, Bill_Date__c, Workshop_Profile__c, Root_Bill__c, Paired_Bill__c
                FROM Bill__c WHERE Id IN :roots OR Root_Bill__c IN :roots
            ]) {
                members.put(b.Id, b);
                found.add(b.Id);
                if (b.Paired_Bill__c != null) {
                    found.add(b.Paired_Bill__c);
                }
            }
            if (ids.containsAll(found)) {
                break;
            }
            ids.addAll(found);
        }
        // Split into groups (connected by root and pair) and keep the ready ones.
        Map<Id, Id> groupOf = groupsOf(members.values());
        Set<Id> blocked = new Set<Id>();
        for (Bill__c b : members.values()) {
            if (!isReady(b, limits)) {
                blocked.add(groupOf.get(b.Id));
            }
        }
        List<Bill__c> ready = new List<Bill__c>();
        for (Bill__c b : members.values()) {
            if (!blocked.contains(groupOf.get(b.Id))) {
                ready.add(b);
            }
        }
        return ready;
    }

    // Each bill's group: the smallest root Id reachable through versions and pairs.
    private static Map<Id, Id> groupsOf(List<Bill__c> bills) {
        Map<Id, Id> parent = new Map<Id, Id>();
        for (Bill__c b : bills) {
            parent.put(b.Id, b.Id);
        }
        for (Bill__c b : bills) {
            for (Id other : new List<Id>{ b.Root_Bill__c, b.Paired_Bill__c }) {
                if (other != null && parent.containsKey(other)) {
                    unite(parent, b.Id, other);
                }
            }
        }
        Map<Id, Id> result = new Map<Id, Id>();
        for (Bill__c b : bills) {
            result.put(b.Id, find(parent, b.Id));
        }
        return result;
    }

    private static Id find(Map<Id, Id> parent, Id x) {
        Id root = x;
        while (parent.get(root) != root) {
            root = parent.get(root);
        }
        return root;
    }

    private static void unite(Map<Id, Id> parent, Id a, Id b) {
        Id ra = find(parent, a);
        Id rb = find(parent, b);
        if (ra != rb) {
            if (String.valueOf(ra).compareTo(String.valueOf(rb)) < 0) {
                parent.put(rb, ra);
            } else {
                parent.put(ra, rb);
            }
        }
    }

    /** Archives exactly these bills (whole groups), in one transaction. */
    public static void archive(List<Bill__c> members) {
        Set<Id> ids = new Map<Id, Bill__c>(members).keySet();
        List<Bill__c> bills = Database.query('SELECT ' + SNAPSHOT_FIELDS + ' FROM Bill__c WHERE Id IN :ids ORDER BY Bill_Date__c, Invoice_Number__c');
        Map<Id, Id> groupOf = groupsOf(bills);

        Set<Id> companyIds = new Set<Id>();
        for (Bill__c b : bills) {
            companyIds.add(companyOf(b));
        }
        Map<Id, Workshop_Profile__c> companies = new Map<Id, Workshop_Profile__c>(
            (List<Workshop_Profile__c>) Database.query('SELECT ' + COMPANY_FIELDS + ' FROM Workshop_Profile__c WHERE Id IN :companyIds FOR UPDATE')
        );

        // One file per company-month.
        Map<String, List<Bill__c>> byMonth = new Map<String, List<Bill__c>>();
        for (Bill__c b : bills) {
            String key = companyOf(b) + '|' + String.valueOf(b.Bill_Date__c).left(7);
            if (!byMonth.containsKey(key)) {
                byMonth.put(key, new List<Bill__c>());
            }
            byMonth.get(key).add(b);
        }
        Map<Id, Id> documentOf = new Map<Id, Id>();
        Map<Id, Integer> expected = new Map<Id, Integer>();
        for (String key : byMonth.keySet()) {
            Id companyId = Id.valueOf(key.substringBefore('|'));
            String month = key.substringAfter('|');
            Workshop_Profile__c company = companies.get(companyId);
            MonthFile file = new MonthFile();
            file.format = 1;
            file.month = month;
            file.company = company;
            file.bills = byMonth.get(key);
            Id documentId = ArchiveStore.write(ArchiveStore.KIND_BILLS, companyId, month,
                'Bills ' + month + ' · ' + (company == null ? '' : company.Name), JSON.serialize(file));
            expected.put(documentId, file.bills.size());
            for (Bill__c b : file.bills) {
                documentOf.put(b.Id, documentId);
            }
        }

        List<ArchiveStore.IndexEntry> entries = new List<ArchiveStore.IndexEntry>();
        for (Bill__c b : bills) {
            ArchiveStore.IndexEntry e = new ArchiveStore.IndexEntry();
            e.id = b.Id;
            e.k = 'bill';
            e.g = groupOf.get(b.Id);
            e.n = b.Invoice_Number__c;
            e.d = b.Bill_Date__c;
            e.c = b.Customer__r == null ? null : b.Customer__r.Name;
            e.p = b.Customer__r == null ? null : b.Customer__r.Phone__c;
            e.v = b.Vehicle__r != null ? b.Vehicle__r.Name : (b.Job__r != null && b.Job__r.Vehicle__r != null ? b.Job__r.Vehicle__r.Name : null);
            e.b = b.Bill_To_Party__r == null ? null : b.Bill_To_Party__r.Name;
            e.t = b.Total_Amount__c;
            e.x = b.Is_Cancelled__c;
            e.l = b.Is_Latest_Version__c;
            e.co = companyOf(b);
            e.f = documentOf.get(b.Id);
            e.cu = b.Customer__c;
            e.ve = b.Vehicle__c != null ? b.Vehicle__c : (b.Job__r == null ? null : b.Job__r.Vehicle__c);
            entries.add(e);
        }
        ArchiveStore.write(ArchiveStore.KIND_INDEX, null, null, 'Index ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss'), JSON.serialize(entries, true));

        // Read back before anything is deleted.
        for (Id documentId : expected.keySet()) {
            MonthFile back = (MonthFile) JSON.deserialize(ArchiveStore.read(documentId), MonthFile.class);
            if (back.bills == null || back.bills.size() != expected.get(documentId)) {
                throw new BillArchiveException('An archive file did not read back as written. Nothing was archived.');
            }
        }

        rememberLastNumbers(bills, companies);
        addArchivedSpend(bills);
        delete bills;
        Database.emptyRecycleBin(bills);
    }

    // The highest number of each financial year, kept on the company.
    private static void rememberLastNumbers(List<Bill__c> bills, Map<Id, Workshop_Profile__c> companies) {
        Map<Id, Map<String, Integer>> byCompany = new Map<Id, Map<String, Integer>>();
        for (Bill__c b : bills) {
            if (b.Financial_Year__c == null) {
                continue;
            }
            Integer sequence = b.Invoice_Sequence__c != null ? b.Invoice_Sequence__c.intValue() : InvoiceNumberingService.sequenceOf(b.Invoice_Number__c);
            if (sequence == null) {
                continue;
            }
            Id companyId = companyOf(b);
            if (!byCompany.containsKey(companyId)) {
                byCompany.put(companyId, lastNumbers(companies.get(companyId)));
            }
            Map<String, Integer> numbers = byCompany.get(companyId);
            Integer known = numbers.get(b.Financial_Year__c);
            if (known == null || sequence > known) {
                numbers.put(b.Financial_Year__c, sequence);
            }
        }
        List<Workshop_Profile__c> changes = new List<Workshop_Profile__c>();
        for (Id companyId : byCompany.keySet()) {
            changes.add(new Workshop_Profile__c(Id = companyId, Invoice_Last_Numbers__c = JSON.serialize(byCompany.get(companyId))));
        }
        update changes;
    }

    public static Map<String, Integer> lastNumbers(Workshop_Profile__c company) {
        if (company == null || String.isBlank(company.Invoice_Last_Numbers__c)) {
            return new Map<String, Integer>();
        }
        return (Map<String, Integer>) JSON.deserialize(company.Invoice_Last_Numbers__c, Map<String, Integer>.class);
    }

    private static void addArchivedSpend(List<Bill__c> bills) {
        Map<Id, Decimal> paid = new Map<Id, Decimal>();
        for (Bill__c b : bills) {
            Decimal amount = b.Amount_Paid__c == null ? 0 : b.Amount_Paid__c;
            if (b.Customer__c != null && amount != 0) {
                paid.put(b.Customer__c, (paid.containsKey(b.Customer__c) ? paid.get(b.Customer__c) : 0) + amount);
            }
        }
        adjustSpend(paid, 1);
    }

    private static void adjustSpend(Map<Id, Decimal> amounts, Integer sign) {
        if (amounts.isEmpty()) {
            return;
        }
        Set<Id> customerIds = amounts.keySet();
        List<Customer__c> customers = [SELECT Id, Archived_Spend__c FROM Customer__c WHERE Id IN :customerIds FOR UPDATE];
        for (Customer__c c : customers) {
            Decimal now = c.Archived_Spend__c == null ? 0 : c.Archived_Spend__c;
            c.Archived_Spend__c = Math.max(now + sign * amounts.get(c.Id), 0);
        }
        update customers;
    }

    // ---- reading and bringing back --------------------------------------

    // Read back from JSON, 1770.00 comes back as 1770.0: amounts get their two
    // places again, so an archived bill reads (and files) exactly as it was saved.
    private static final List<String> AMOUNT_FIELDS = new List<String>{
        'Subtotal__c', 'GST_Amount__c', 'Round_Off__c', 'Total_Amount__c', 'Amount_Paid__c'
    };

    private static Bill__c asSaved(Bill__c b) {
        Map<String, Object> populated = b.getPopulatedFieldsAsMap();
        for (String field : AMOUNT_FIELDS) {
            if (populated.containsKey(field) && populated.get(field) != null) {
                b.put(field, ((Decimal) populated.get(field)).setScale(2));
            }
        }
        return b;
    }

    /** A company's archived bills dated in a period, and the file each is in. */
    public class PeriodBills {
        public List<Bill__c> bills = new List<Bill__c>();
        public Map<Id, Id> documentOf = new Map<Id, Id>();
    }

    /**
     * The archived bills of a company dated from start to end (every version,
     * cancelled ones too), less any brought back since: those are in Salesforce
     * again. The GST return reads these with the live ones (Forty-eighth).
     */
    public static PeriodBills billsFor(Id companyId, Date startDate, Date endDate) {
        PeriodBills result = new PeriodBills();
        String fromMonth = String.valueOf(startDate).left(7);
        String toMonth = String.valueOf(endDate).left(7);
        List<ArchiveStore.ArchiveFile> wanted = new List<ArchiveStore.ArchiveFile>();
        for (ArchiveStore.ArchiveFile f : ArchiveStore.filesOfKind(ArchiveStore.KIND_BILLS)) {
            String month = f.meta.month;
            if (String.valueOf(companyId).equals(f.meta.company) && month != null && month >= fromMonth && month <= toMonth) {
                wanted.add(f);
            }
        }
        if (wanted.isEmpty()) {
            return result;
        }
        Set<String> restored = ArchiveStore.restoredIds();
        Map<Id, String> bodies = ArchiveStore.readAll(wanted);
        for (Id documentId : bodies.keySet()) {
            MonthFile file = (MonthFile) JSON.deserialize(bodies.get(documentId), MonthFile.class);
            for (Bill__c b : file.bills) {
                if (b.Bill_Date__c >= startDate && b.Bill_Date__c <= endDate && !restored.contains(b.Id)) {
                    result.bills.add(asSaved(b));
                    result.documentOf.put(b.Id, documentId);
                }
            }
        }
        return result;
    }

    /** One archived bill, as it was saved, with its company. */
    public static MonthFile findBill(Id documentId, Id billId) {
        MonthFile file = (MonthFile) JSON.deserialize(ArchiveStore.read(documentId), MonthFile.class);
        for (Bill__c b : file.bills) {
            if (b.Id == billId) {
                MonthFile one = new MonthFile();
                one.format = file.format;
                one.month = file.month;
                one.company = file.company;
                one.bills = new List<Bill__c>{ asSaved(b) };
                return one;
            }
        }
        throw new BillArchiveException('That bill is not in this archive file.');
    }

    /**
     * Brings a bill back into Salesforce with its whole group, keeping their
     * numbers. Returns the new Id of the bill asked for.
     */
    public static Id restore(Id billId) {
        ArchiveStore.IndexEntry asked;
        List<ArchiveStore.IndexEntry> index = ArchiveStore.index();
        for (ArchiveStore.IndexEntry e : index) {
            if (e.id == billId) {
                asked = e;
            }
        }
        if (asked == null) {
            throw new BillArchiveException('That bill is not in the archive, or was already brought back.');
        }
        Set<String> groupIds = new Set<String>();
        Set<Id> documentIds = new Set<Id>();
        for (ArchiveStore.IndexEntry e : index) {
            if (e.g == asked.g) {
                groupIds.add(e.id);
                documentIds.add(e.f);
            }
        }
        List<Bill__c> saved = new List<Bill__c>();
        for (Id documentId : documentIds) {
            MonthFile file = (MonthFile) JSON.deserialize(ArchiveStore.read(documentId), MonthFile.class);
            for (Bill__c b : file.bills) {
                if (groupIds.contains(b.Id)) {
                    saved.add(b);
                }
            }
        }

        // Lookups only to records that still exist.
        Set<Id> refs = new Set<Id>();
        for (Bill__c b : saved) {
            refs.addAll(new List<Id>{ b.Customer__c, b.Vehicle__c, b.Bill_To_Party__c, b.Job__c, b.Source_Estimate__c, b.Workshop_Profile__c });
        }
        refs.remove(null);
        Set<Id> existing = existingIds(refs);

        // A customer or car archived since (CustomerArchive) comes back first.
        Set<Id> archivedPeople = new Set<Id>();
        for (Bill__c b : saved) {
            for (Id ref : new List<Id>{ b.Customer__c, b.Vehicle__c }) {
                if (ref != null && !existing.contains(ref)) {
                    archivedPeople.add(ref);
                }
            }
        }
        Map<Id, Id> nowIds = CustomerArchive.liveIds(archivedPeople);
        Map<Id, Id> customerOf = new Map<Id, Id>();

        Map<Id, Bill__c> fresh = new Map<Id, Bill__c>();
        for (Bill__c b : saved) {
            Id customerId = b.Customer__c != null && existing.contains(b.Customer__c) ? b.Customer__c : nowIds.get(b.Customer__c);
            if (customerId == null) {
                throw new BillArchiveException(b.Invoice_Number__c + '\'s customer is no longer in Salesforce, so the bill can\'t be brought back.');
            }
            customerOf.put(b.Id, customerId);
            Id vehicleId = b.Vehicle__c != null && existing.contains(b.Vehicle__c) ? b.Vehicle__c : nowIds.get(b.Vehicle__c);
            fresh.put(b.Id, new Bill__c(
                Workshop_Profile__c = keep(b.Workshop_Profile__c, existing),
                Customer__c = customerId,
                Vehicle__c = vehicleId,
                Bill_To_Party__c = keep(b.Bill_To_Party__c, existing),
                Job__c = keep(b.Job__c, existing),
                Source_Estimate__c = keep(b.Source_Estimate__c, existing),
                Invoice_Number__c = b.Invoice_Number__c,
                Invoice_Sequence__c = b.Invoice_Sequence__c,
                Financial_Year__c = b.Financial_Year__c,
                Bill_Date__c = b.Bill_Date__c,
                Status__c = b.Status__c,
                Notes__c = b.Notes__c,
                Place_Of_Supply__c = b.Place_Of_Supply__c,
                Recipient_GSTIN__c = b.Recipient_GSTIN__c,
                Is_Cancelled__c = b.Is_Cancelled__c,
                Cancelled_On__c = b.Cancelled_On__c,
                Is_Latest_Version__c = b.Is_Latest_Version__c,
                Version_Number__c = b.Version_Number__c,
                Subtotal__c = b.Subtotal__c,
                GST_Amount__c = b.GST_Amount__c,
                Round_Off__c = b.Round_Off__c,
                Total_Amount__c = b.Total_Amount__c,
                Amount_Paid__c = b.Amount_Paid__c,
                Line_Items__c = b.Line_Items__c,
                Payments__c = b.Payments__c
            ));
        }
        restoring = true;
        try {
            insert fresh.values();
        } finally {
            restoring = false;
        }
        // Versions and pairs point at each other's new Ids.
        List<Bill__c> links = new List<Bill__c>();
        for (Bill__c b : saved) {
            links.add(new Bill__c(
                Id = fresh.get(b.Id).Id,
                Root_Bill__c = b.Root_Bill__c == null || !fresh.containsKey(b.Root_Bill__c) ? null : fresh.get(b.Root_Bill__c).Id,
                Previous_Version__c = b.Previous_Version__c == null || !fresh.containsKey(b.Previous_Version__c) ? null : fresh.get(b.Previous_Version__c).Id,
                Paired_Bill__c = b.Paired_Bill__c == null || !fresh.containsKey(b.Paired_Bill__c) ? null : fresh.get(b.Paired_Bill__c).Id
            ));
        }
        update links;

        Map<Id, Decimal> paid = new Map<Id, Decimal>();
        for (Bill__c b : saved) {
            Decimal amount = b.Amount_Paid__c == null ? 0 : b.Amount_Paid__c;
            Id customerId = customerOf.get(b.Id);
            if (amount != 0) {
                paid.put(customerId, (paid.containsKey(customerId) ? paid.get(customerId) : 0) + amount);
            }
        }
        adjustSpend(paid, -1);
        ArchiveStore.write(ArchiveStore.KIND_RESTORED, null, null, 'Brought back ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss'),
            JSON.serialize(new List<String>(groupIds)));
        return fresh.get(billId).Id;
    }

    private static Id keep(Id ref, Set<Id> existing) {
        return ref != null && existing.contains(ref) ? ref : null;
    }

    private static Set<Id> existingIds(Set<Id> ids) {
        Set<Id> found = new Set<Id>();
        Map<Schema.SObjectType, Set<Id>> byType = new Map<Schema.SObjectType, Set<Id>>();
        for (Id i : ids) {
            if (!byType.containsKey(i.getSObjectType())) {
                byType.put(i.getSObjectType(), new Set<Id>());
            }
            byType.get(i.getSObjectType()).add(i);
        }
        for (Schema.SObjectType t : byType.keySet()) {
            Set<Id> some = byType.get(t);
            for (SObject r : Database.query('SELECT Id FROM ' + t + ' WHERE Id IN :some')) {
                found.add(r.Id);
            }
        }
        return found;
    }
}
