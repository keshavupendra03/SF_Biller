/**
 * WS Biller's archive in Salesforce Files (architecture.md, Forty-fifth). Files
 * use the org's file storage (20 MB on Developer Edition), not its data storage.
 *
 * Every file is a zip holding one data.json, linked to its company's
 * Workshop_Profile__c, and never changed once written (a changed Salesforce
 * File keeps its old version too, doubling the storage):
 *   kind "bills"     one company's bills for one month (more archived later
 *                    for that month go into a new part)
 *   kind "index"     one line per archived item, for searching without opening
 *                    every month
 *   kind "restored"  ids brought back into Salesforce, left out of searches
 *   kind "customers" dormant customers with their cars and Service Book, and
 *                    cars filed under the Walk-in Customer (CustomerArchive)
 *   kind "customer-index"  one line per archived customer or car
 *   kind "moved"     brought back customers and cars: old Id to new Id, so an
 *                    archived bill brought back later finds them
 *   kind "jobs", "slips", "attendance"  finished jobs, old job slips and old
 *                    attendance months (WorkArchive, AttendanceArchive)
 *   kind "work-index"  one line per archived job, job slip or attendance month
 * The kind, company, month and part are kept in the file's Description; the
 * Title is for people. Every file is linked to a company (files that belong to
 * no company, to the first one), so whoever can see the company can read the
 * archive: a file linked to no record is private to whoever made it.
 */
public without sharing class ArchiveStore {
    // Without sharing: the archive is the org's, whoever runs or reads it.

    public class ArchiveStoreException extends Exception {}

    public static final String TITLE_PREFIX = 'WS Biller archive';
    public static final String KIND_BILLS = 'bills';
    public static final String KIND_INDEX = 'index';
    public static final String KIND_RESTORED = 'restored';
    public static final String KIND_CUSTOMERS = 'customers';
    public static final String KIND_CUSTOMER_INDEX = 'customer-index';
    public static final String KIND_MOVED = 'moved';
    public static final String KIND_JOBS = 'jobs';
    public static final String KIND_SLIPS = 'slips';
    public static final String KIND_ATTENDANCE = 'attendance';
    public static final String KIND_WORK_INDEX = 'work-index';
    // How often the nightly run archives customers, jobs, slips and attendance
    // (a full batch waiting is archived the next night anyway).
    public static final Integer DAYS_BETWEEN_RUNS = 28;

    public class FileMeta {
        public String kind;
        public String company;
        public String month;
        public Integer part;
    }

    public class ArchiveFile {
        @AuraEnabled public Id documentId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public Integer sizeBytes { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        public FileMeta meta;
    }

    /** One archived item, as searched. Short keys: the index holds thousands. */
    public class IndexEntry {
        public String id; // the record's Id when it was archived
        public String k; // kind: bill, customer, car (one filed under Walk-in), job, slip or month
        public String g; // its group (versions and an insurance pair go together)
        public String n; // number
        public Date d; // date (a customer's or car's: when last seen)
        public String c; // customer
        public String p; // phone
        public String v; // vehicle number (a customer's: all of them, space separated)
        public String b; // bill-to party
        public Decimal t; // total
        public Boolean x; // deleted (cancelled)
        public Boolean l; // latest version
        public String co; // company Id
        public String f; // the ContentDocument holding it
        public String cu; // a bill's customer Id
        public String ve; // a bill's vehicle Id
        public List<String> vs; // a customer's vehicle Ids, in the order of v
        public String s; // a job's stage, a job slip's visit reason
        public String me; // an attendance month's mechanic Id
    }

    // ---- writing --------------------------------------------------------

    /** Saves a new archive file; returns its ContentDocument Id. */
    public static Id write(String kind, Id companyId, String month, String title, String body) {
        FileMeta meta = new FileMeta();
        meta.kind = kind;
        meta.company = companyId;
        meta.month = month;
        meta.part = month == null ? 1 : partsOf(kind, companyId, month) + 1;
        Compression.ZipWriter zip = new Compression.ZipWriter();
        zip.addEntry('data.json', Blob.valueOf(body));
        ContentVersion version = new ContentVersion(
            Title = TITLE_PREFIX + ' · ' + title + (meta.part > 1 ? ' (part ' + meta.part + ')' : ''),
            PathOnClient = 'ws-biller-archive-' + kind + (month == null ? '' : '-' + month) + '-' + meta.part + '.zip',
            VersionData = zip.getArchive(),
            Description = JSON.serialize(meta)
        );
        Id linkTo = companyId != null ? companyId : WorkshopProfileService.primaryId();
        if (linkTo != null) {
            version.FirstPublishLocationId = linkTo;
        }
        insert version;
        cache = null;
        parsed.clear();
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    // ---- reading --------------------------------------------------------

    public static String read(Id documentId) {
        List<ContentVersion> versions = [
            SELECT VersionData FROM ContentVersion WHERE ContentDocumentId = :documentId AND IsLatest = true
        ];
        if (versions.isEmpty()) {
            throw new ArchiveStoreException('That archive file is missing.');
        }
        return unzip(versions[0].VersionData);
    }

    /** Several files in one query: ContentDocument Id to its data.json. */
    public static Map<Id, String> readAll(List<ArchiveFile> archiveFiles) {
        Set<Id> ids = new Set<Id>();
        for (ArchiveFile f : archiveFiles) {
            ids.add(f.documentId);
        }
        Map<Id, String> bodies = new Map<Id, String>();
        if (ids.isEmpty()) {
            return bodies;
        }
        for (ContentVersion v : [
            SELECT ContentDocumentId, VersionData FROM ContentVersion WHERE ContentDocumentId IN :ids AND IsLatest = true
        ]) {
            bodies.put(v.ContentDocumentId, unzip(v.VersionData));
        }
        return bodies;
    }

    private static String unzip(Blob data) {
        Compression.ZipReader zip = new Compression.ZipReader(data);
        return zip.extract(zip.getEntry('data.json')).toString();
    }

    // The file list, kept for the transaction: searches ask for it more than once.
    private static List<ArchiveFile> cache;

    /** Every archive file, newest first. */
    public static List<ArchiveFile> files() {
        if (cache != null) {
            return cache;
        }
        List<ArchiveFile> result = new List<ArchiveFile>();
        String prefix = TITLE_PREFIX + '%';
        // Found through their links to the companies: a query for files with no
        // other filter returns only files the user owns, or in a shared library,
        // even without sharing, so staff would see none of the admin's archive
        // (architecture.md, Forty-ninth). By Id, any file they can see is read.
        Set<Id> companyIds = new Map<Id, Workshop_Profile__c>([SELECT Id FROM Workshop_Profile__c]).keySet();
        Set<Id> documentIds = new Set<Id>();
        if (!companyIds.isEmpty()) {
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId FROM ContentDocumentLink
                WHERE LinkedEntityId IN :companyIds AND ContentDocument.Title LIKE :prefix
            ]) {
                documentIds.add(link.ContentDocumentId);
            }
        }
        // Files made before every file was linked to a company are their maker's
        // own. (One query with "Id IN ... OR owner" is no longer "by Id": it then
        // returns only the user's own files.)
        for (ContentVersion v : [SELECT ContentDocumentId FROM ContentVersion WHERE IsLatest = true AND Title LIKE :prefix]) {
            documentIds.add(v.ContentDocumentId);
        }
        for (ContentVersion v : [
            SELECT ContentDocumentId, Title, ContentSize, Description, CreatedDate
            FROM ContentVersion
            WHERE IsLatest = true AND ContentDocumentId IN :documentIds
            ORDER BY CreatedDate DESC
        ]) {
            ArchiveFile f = new ArchiveFile();
            f.documentId = v.ContentDocumentId;
            f.title = v.Title;
            f.sizeBytes = v.ContentSize;
            f.createdDate = v.CreatedDate;
            try {
                f.meta = (FileMeta) JSON.deserialize(v.Description, FileMeta.class);
            } catch (Exception e) {
                continue;
            }
            result.add(f);
        }
        cache = result;
        return result;
    }

    public static List<ArchiveFile> filesOfKind(String kind) {
        List<ArchiveFile> result = new List<ArchiveFile>();
        for (ArchiveFile f : files()) {
            if (f.meta != null && kind.equals(f.meta.kind)) {
                result.add(f);
            }
        }
        return result;
    }

    private static Integer partsOf(String kind, Id companyId, String month) {
        Integer parts = 0;
        for (ArchiveFile f : filesOfKind(kind)) {
            if (String.valueOf(companyId).equals(String.valueOf(f.meta.company)) && month.equals(f.meta.month)) {
                parts++;
            }
        }
        return parts;
    }

    /** Every archived bill, less those brought back since. */
    public static List<IndexEntry> index() {
        return entriesOf(KIND_INDEX, restoredIds());
    }

    /** Every archived customer and Walk-in car, less those brought back since. */
    public static List<IndexEntry> customerIndex() {
        return entriesOf(KIND_CUSTOMER_INDEX, moved().keySet());
    }

    // Each index read and parsed once per transaction (cleared when a file is written).
    private static Map<String, List<IndexEntry>> parsed = new Map<String, List<IndexEntry>>();

    private static List<IndexEntry> entriesOf(String kind, Set<String> leaveOut) {
        String key = kind + '|' + leaveOut.size();
        if (parsed.containsKey(key)) {
            return parsed.get(key);
        }
        List<IndexEntry> entries = new List<IndexEntry>();
        for (String body : readAll(filesOfKind(kind)).values()) {
            for (IndexEntry e : (List<IndexEntry>) JSON.deserialize(body, List<IndexEntry>.class)) {
                if (!leaveOut.contains(e.id)) {
                    entries.add(e);
                }
            }
        }
        parsed.put(key, entries);
        return entries;
    }

    public static Set<String> restoredIds() {
        Set<String> ids = new Set<String>();
        for (String body : readAll(filesOfKind(KIND_RESTORED)).values()) {
            ids.addAll((List<String>) JSON.deserialize(body, List<String>.class));
        }
        return ids;
    }

    /** Every archived job, job slip and attendance month (none of them come back). */
    public static List<IndexEntry> workIndex() {
        return entriesOf(KIND_WORK_INDEX, new Set<String>());
    }

    /** Whether a file of this kind was written in the last few days. */
    public static Boolean wroteWithin(String kind, Integer days) {
        Datetime since = Datetime.now().addDays(-days);
        for (ArchiveFile f : filesOfKind(kind)) {
            if (f.createdDate > since) {
                return true;
            }
        }
        return false;
    }

    /** Customers and cars brought back: their Id when archived, to their Id now. */
    public static Map<String, String> moved() {
        Map<String, String> ids = new Map<String, String>();
        for (String body : readAll(filesOfKind(KIND_MOVED)).values()) {
            ids.putAll((Map<String, String>) JSON.deserialize(body, Map<String, String>.class));
        }
        return ids;
    }

    public static Integer totalBytes() {
        Integer total = 0;
        for (ArchiveFile f : files()) {
            total += f.sizeBytes == null ? 0 : f.sizeBytes;
        }
        return total;
    }
}
