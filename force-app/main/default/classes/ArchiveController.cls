/**
 * The Archive screen (archiveSettings), old bills in Billing (billingList) and
 * archived customers in Customers (customerList): the rules, storage, what
 * would be archived, running it, and finding, viewing, printing and bringing
 * back archived bills and customers (architecture.md, Forty-fifth and
 * Forty-sixth).
 */
public with sharing class ArchiveController {

    public class ArchiveControllerException extends Exception {}

    public class Status {
        @AuraEnabled public ArchiveSettings.Rules rules { get; set; }
        @AuraEnabled public Decimal dataUsedMb { get; set; }
        @AuraEnabled public Decimal dataLimitMb { get; set; }
        @AuraEnabled public Decimal fileUsedMb { get; set; }
        @AuraEnabled public Decimal fileLimitMb { get; set; }
        @AuraEnabled public Decimal archiveKb { get; set; }
        @AuraEnabled public Integer archiveFiles { get; set; }
        @AuraEnabled public Integer archivedBills { get; set; }
        @AuraEnabled public Integer billsReady { get; set; }
        @AuraEnabled public List<String> billMonthsReady { get; set; }
        @AuraEnabled public Date billsBefore { get; set; }
        @AuraEnabled public Integer estimatesToDelete { get; set; }
        @AuraEnabled public Date estimatesBefore { get; set; }
        @AuraEnabled public String downloadUrl { get; set; }
        @AuraEnabled public Integer archivedCustomers { get; set; }
        @AuraEnabled public Integer archivedCars { get; set; }
        @AuraEnabled public Integer customersReady { get; set; }
        @AuraEnabled public Integer carsReady { get; set; }
        @AuraEnabled public Date customersBefore { get; set; }
        // False when customers were archived in the last 28 days: the nightly
        // run leaves them until then (Run now doesn't).
        @AuraEnabled public Boolean customersDue { get; set; }
        @AuraEnabled public Integer archivedJobs { get; set; }
        @AuraEnabled public Integer archivedSlips { get; set; }
        @AuraEnabled public Integer archivedMonths { get; set; }
        @AuraEnabled public Integer jobsReady { get; set; }
        @AuraEnabled public Integer slipsReady { get; set; }
        @AuraEnabled public Date jobsBefore { get; set; }
        @AuraEnabled public Date slipsBefore { get; set; }
        @AuraEnabled public Boolean workDue { get; set; }
        @AuraEnabled public Integer monthsReady { get; set; }
        @AuraEnabled public Date monthsBefore { get; set; }
    }

    /** A customer's archived job or job slip (customerDetail). */
    public class ArchivedWorkRow {
        @AuraEnabled public String kind { get; set; }
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public Id documentId { get; set; }
        @AuraEnabled public String docNumber { get; set; }
        @AuraEnabled public Date workDate { get; set; }
        @AuraEnabled public String vehicle { get; set; }
        @AuraEnabled public String detail { get; set; }
    }

    public class ArchivedJob {
        @AuraEnabled public String jobNumber { get; set; }
        @AuraEnabled public Date createdDate { get; set; }
        @AuraEnabled public Date lastChanged { get; set; }
        @AuraEnabled public String stageName { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String customerPhone { get; set; }
        @AuraEnabled public String vehicle { get; set; }
        @AuraEnabled public String surveyorName { get; set; }
        @AuraEnabled public String mechanicNames { get; set; }
        @AuraEnabled public String notes { get; set; }
    }

    public class ArchivedCustomerRow {
        @AuraEnabled public String archivedId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String vehicles { get; set; }
        @AuraEnabled public Date lastSeen { get; set; }
    }

    public class ArchivedBillRow {
        @AuraEnabled public Id billId { get; set; }
        @AuraEnabled public Id documentId { get; set; }
        @AuraEnabled public String invoiceNumber { get; set; }
        @AuraEnabled public Date billDate { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String vehicle { get; set; }
        @AuraEnabled public String billToPartyName { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public Boolean isCancelled { get; set; }
        @AuraEnabled public Boolean isLatestVersion { get; set; }
        @AuraEnabled public Id workshopProfileId { get; set; }
    }

    public class ArchivedBill {
        @AuraEnabled public Id billId { get; set; }
        @AuraEnabled public Id documentId { get; set; }
        @AuraEnabled public Id workshopProfileId { get; set; }
        @AuraEnabled public String companyName { get; set; }
        @AuraEnabled public String invoiceNumber { get; set; }
        @AuraEnabled public Date billDate { get; set; }
        @AuraEnabled public Integer versionNumber { get; set; }
        @AuraEnabled public Boolean isLatestVersion { get; set; }
        @AuraEnabled public Boolean isCancelled { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String billToPartyName { get; set; }
        @AuraEnabled public String vehicle { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public String pairedInvoiceNumber { get; set; }
        @AuraEnabled public List<BillController.LineItemInput> lineItems { get; set; }
        @AuraEnabled public Decimal subtotal { get; set; }
        @AuraEnabled public Decimal cgst { get; set; }
        @AuraEnabled public Decimal sgst { get; set; }
        @AuraEnabled public Decimal igst { get; set; }
        @AuraEnabled public Decimal roundOff { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public Decimal amountPaid { get; set; }
    }

    // ---- the Archive screen ---------------------------------------------

    @AuraEnabled
    public static Status getStatus() {
        ArchiveSettings.Rules rules = ArchiveSettings.current();
        Status s = new Status();
        s.rules = rules;
        Map<String, System.OrgLimit> limits = OrgLimits.getMap();
        if (limits.containsKey('DataStorageMB')) {
            s.dataUsedMb = limits.get('DataStorageMB').getValue();
            s.dataLimitMb = limits.get('DataStorageMB').getLimit();
        }
        if (limits.containsKey('FileStorageMB')) {
            s.fileUsedMb = limits.get('FileStorageMB').getValue();
            s.fileLimitMb = limits.get('FileStorageMB').getLimit();
        }
        List<ArchiveStore.ArchiveFile> files = ArchiveStore.files();
        Decimal bytes = 0;
        List<String> ids = new List<String>();
        for (ArchiveStore.ArchiveFile f : files) {
            bytes += f.sizeBytes == null ? 0 : f.sizeBytes;
            ids.add(f.documentId);
        }
        s.archiveFiles = files.size();
        s.archiveKb = (bytes / 1024).setScale(1);
        s.archivedBills = ArchiveStore.index().size();
        // Several files in one link download as one zip.
        s.downloadUrl = ids.isEmpty() ? null : '/sfc/servlet.shepherd/document/download/' + String.join(ids, '/');
        BillArchive.Plan plan = BillArchive.plan(rules);
        s.billsReady = plan.billCount;
        s.billMonthsReady = plan.months;
        s.billsBefore = plan.archiveBefore;
        s.estimatesToDelete = EstimatePurge.count(rules);
        s.estimatesBefore = EstimatePurge.deleteBefore(rules);
        s.archivedCustomers = 0;
        s.archivedCars = 0;
        for (ArchiveStore.IndexEntry e : CustomerArchive.entries()) {
            if (e.k == CustomerArchive.KIND_CUSTOMER) {
                s.archivedCustomers++;
            } else {
                s.archivedCars++;
            }
        }
        CustomerArchive.Plan people = CustomerArchive.plan(rules);
        s.customersReady = people.customers;
        s.carsReady = people.cars;
        s.customersBefore = people.dormantBefore;
        s.customersDue = people.isDue;
        s.archivedJobs = 0;
        s.archivedSlips = 0;
        s.archivedMonths = 0;
        for (ArchiveStore.IndexEntry e : ArchiveStore.workIndex()) {
            if (e.k == WorkArchive.KIND_JOB) {
                s.archivedJobs++;
            } else if (e.k == WorkArchive.KIND_SLIP) {
                s.archivedSlips++;
            } else if (e.k == AttendanceArchive.KIND_MONTH) {
                s.archivedMonths++;
            }
        }
        WorkArchive.Plan work = WorkArchive.plan(rules);
        s.jobsReady = work.jobs;
        s.slipsReady = work.slips;
        s.jobsBefore = work.jobsBefore;
        s.slipsBefore = work.slipsBefore;
        s.workDue = work.isDue;
        AttendanceArchive.Plan attendance = AttendanceArchive.plan(rules);
        s.monthsReady = attendance.months;
        s.monthsBefore = attendance.before;
        return s;
    }

    // ---- archived jobs and job slips ------------------------------------

    /** A customer's archived jobs and job slips, newest first. */
    @AuraEnabled
    public static List<ArchivedWorkRow> customerHistory(Id customerId) {
        List<ArchivedWorkRow> rows = new List<ArchivedWorkRow>();
        if (customerId == null) {
            return rows;
        }
        for (ArchiveStore.IndexEntry e : WorkArchive.forCustomer(customerId)) {
            ArchivedWorkRow r = new ArchivedWorkRow();
            r.kind = e.k;
            r.recordId = e.id;
            r.documentId = e.f;
            r.docNumber = e.n;
            r.workDate = e.d;
            r.vehicle = e.v;
            r.detail = e.s;
            rows.add(r);
        }
        return rows;
    }

    @AuraEnabled
    public static ArchivedJob getArchivedJob(Id documentId, Id jobId) {
        try {
            WorkArchive.FoundJob found = WorkArchive.findJob(documentId, jobId);
            Job__c j = found.job;
            ArchivedJob v = new ArchivedJob();
            v.jobNumber = j.Name;
            v.createdDate = j.CreatedDate == null ? null : j.CreatedDate.date();
            v.lastChanged = j.LastModifiedDate == null ? null : j.LastModifiedDate.date();
            v.stageName = j.Job_Status_Stage__r == null ? null : j.Job_Status_Stage__r.Name;
            v.customerName = j.Customer__r == null ? null : j.Customer__r.Name;
            v.customerPhone = j.Customer__r == null ? null : j.Customer__r.Phone__c;
            if (j.Vehicle__r != null) {
                List<String> parts = new List<String>{ j.Vehicle__r.Name };
                for (String part : new List<String>{ j.Vehicle__r.Make__c, j.Vehicle__r.Model__c }) {
                    if (String.isNotBlank(part)) {
                        parts.add(part);
                    }
                }
                v.vehicle = String.join(parts, ' ');
            }
            v.surveyorName = j.Surveyor__r == null ? null : j.Surveyor__r.Name;
            v.mechanicNames = String.join(found.mechanics, ', ');
            v.notes = j.Notes__c;
            return v;
        } catch (Exception e) {
            throw new ArchiveControllerException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Status saveRules(ArchiveSettings.Rules rules) {
        try {
            ArchiveSettings.save(rules);
        } catch (ArchiveSettings.ArchiveSettingsException e) {
            throw new ArchiveControllerException(e.getMessage());
        }
        return getStatus();
    }

    /** Starts a run now, in the background, whether or not nightly archiving is on. */
    @AuraEnabled
    public static void runNow() {
        System.enqueueJob(new ArchiveJob(true));
    }

    // ---- archived customers ---------------------------------------------

    /** Archived customers whose name, phone or car number matches every word typed. */
    @AuraEnabled
    public static List<ArchivedCustomerRow> searchCustomers(String term) {
        List<ArchivedCustomerRow> rows = new List<ArchivedCustomerRow>();
        for (ArchiveStore.IndexEntry e : CustomerArchive.search(term, 200)) {
            if (e.k != CustomerArchive.KIND_CUSTOMER || rows.size() >= 20) {
                continue;
            }
            ArchivedCustomerRow r = new ArchivedCustomerRow();
            r.archivedId = e.id;
            r.name = e.c;
            r.phone = e.p == QuickBillController.WALK_IN_PHONE ? null : e.p;
            r.vehicles = e.v;
            r.lastSeen = e.d;
            rows.add(r);
        }
        return rows;
    }

    /** Brings an archived customer back with their cars and Service Book; returns their Id now. */
    @AuraEnabled
    public static Id restoreCustomer(String archivedId) {
        try {
            return CustomerArchive.restore(archivedId).customerId;
        } catch (DmlException e) {
            throw ReadableErrors.of(e);
        } catch (CustomerArchive.CustomerArchiveException e) {
            throw new ArchiveControllerException(e.getMessage());
        }
    }

    // ---- old bills ------------------------------------------------------

    /** Archived bills whose number, customer, phone, vehicle or party matches every word typed. Newest first. */
    @AuraEnabled
    public static List<ArchivedBillRow> searchBills(String term) {
        List<String> words = String.isBlank(term) ? new List<String>() : term.trim().toLowerCase().split('\\s+');
        List<ArchiveStore.IndexEntry> matches = new List<ArchiveStore.IndexEntry>();
        for (ArchiveStore.IndexEntry e : ArchiveStore.index()) {
            if (e.k != 'bill') {
                continue;
            }
            String text = String.join(new List<String>{ e.n, e.c, e.p, e.v, e.b }, ' ').toLowerCase().replaceAll('null', '');
            String compact = text.deleteWhitespace();
            Boolean all = true;
            for (String w : words) {
                all = all && (text.contains(w) || compact.contains(w));
            }
            if (all) {
                matches.add(e);
            }
        }
        // Newest first: dates as text sort the same way.
        Map<String, ArchiveStore.IndexEntry> byKey = new Map<String, ArchiveStore.IndexEntry>();
        for (ArchiveStore.IndexEntry e : matches) {
            byKey.put(String.valueOf(e.d) + '|' + e.n + '|' + e.id, e);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<ArchivedBillRow> rows = new List<ArchivedBillRow>();
        for (Integer i = keys.size() - 1; i >= 0 && rows.size() < 100; i--) {
            ArchiveStore.IndexEntry e = byKey.get(keys[i]);
            ArchivedBillRow r = new ArchivedBillRow();
            r.billId = e.id;
            r.documentId = e.f;
            r.invoiceNumber = e.n;
            r.billDate = e.d;
            r.customerName = e.c;
            r.phone = e.p;
            r.vehicle = e.v;
            r.billToPartyName = e.b;
            r.totalAmount = e.t;
            r.isCancelled = e.x == true;
            r.isLatestVersion = e.l != false;
            r.workshopProfileId = e.co;
            rows.add(r);
        }
        return rows;
    }

    @AuraEnabled
    public static ArchivedBill getArchivedBill(Id documentId, Id billId) {
        try {
            BillArchive.MonthFile file = BillArchive.findBill(documentId, billId);
            Bill__c b = file.bills[0];
            ArchivedBill v = new ArchivedBill();
            v.billId = b.Id;
            v.documentId = documentId;
            v.workshopProfileId = file.company == null ? null : file.company.Id;
            v.companyName = file.company == null ? null : file.company.Name;
            v.invoiceNumber = b.Invoice_Number__c;
            v.billDate = b.Bill_Date__c;
            v.versionNumber = b.Version_Number__c == null ? 1 : b.Version_Number__c.intValue();
            v.isLatestVersion = b.Is_Latest_Version__c;
            v.isCancelled = b.Is_Cancelled__c;
            v.customerName = b.Customer__r == null ? null : b.Customer__r.Name;
            v.billToPartyName = b.Bill_To_Party__r == null ? null : b.Bill_To_Party__r.Name;
            v.vehicle = b.Vehicle__r == null ? null : b.Vehicle__r.Name;
            v.notes = b.Notes__c;
            v.pairedInvoiceNumber = b.Paired_Bill__r == null ? null : b.Paired_Bill__r.Invoice_Number__c;
            v.lineItems = StoredLines.read(b.Line_Items__c);
            GstCalculatorService.GstBillResult t = GstCalculatorService.calculateBill(StoredLines.gstInputs(v.lineItems));
            v.subtotal = b.Subtotal__c;
            v.cgst = t.cgst;
            v.sgst = t.sgst;
            v.igst = t.igst;
            v.roundOff = b.Round_Off__c == null ? 0 : b.Round_Off__c;
            v.totalAmount = b.Total_Amount__c;
            v.amountPaid = b.Amount_Paid__c;
            return v;
        } catch (Exception e) {
            throw new ArchiveControllerException(e.getMessage());
        }
    }

    /** Brings an archived bill (and its versions and insurance pair) back; returns its new Id. */
    @AuraEnabled
    public static Id restoreBill(Id billId) {
        try {
            return BillArchive.restore(billId);
        } catch (DmlException e) {
            throw ReadableErrors.of(e);
        } catch (BillArchive.BillArchiveException e) {
            throw new ArchiveControllerException(e.getMessage());
        }
    }
}
