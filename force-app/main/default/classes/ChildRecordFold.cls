/**
 * Moves an org's old child records into their parent records, then deletes them
 * (architecture.md, Forty-second):
 *   Bill_Line_Item__c     -> Bill__c.Line_Items__c
 *   Payment__c            -> Bill__c.Payments__c and Amount_Paid__c
 *   Estimate_Line_Item__c -> Estimate__c.Line_Items__c
 *   Job_Slip_Line__c      -> Job_Slip__c.Repair_Lines__c
 *   Service_Entry__c      -> Vehicle__c.Service_Book__c, First/Last_Service_Date__c
 *
 * Run by scripts/apex/fold-child-records.apex (from Deploy-ToClientOrg.ps1).
 * Every query on the old objects is dynamic, so this compiles on an org that
 * never had them (or after Retire-OldChildObjects.ps1) and then does nothing.
 *
 * Field-level security applies to Apex here (API 67), and WS_Biller_Full_Access
 * no longer grants the old fields (it can't name objects a new org won't have).
 * So the first run gives the running user a temporary permission set for them
 * (ACCESS_SET, made in Apex, not metadata) and stops: a permission only applies
 * from the next transaction, and setup and record changes can't share one. The
 * last run, once nothing is left, removes it again.
 *
 * Each run is one transaction (all or nothing) handling a share of the records,
 * and reports FOLD-REMAINING: <n>, -1 meaning "run again"; the deploy script
 * runs it until that is 0.
 * Saved totals and statuses are kept as they were, not recalculated. Deleted
 * child records are emptied from the Recycle Bin straight away, so their storage
 * is freed now rather than in 15 days. Without sharing: it must see every record.
 */
public without sharing class ChildRecordFold {

    public class ChildRecordFoldException extends Exception {}

    private static final Map<String, Schema.SObjectType> TYPES = Schema.getGlobalDescribe();
    private static final Integer CHILD_CAP = 1500;
    private static final Integer ROW_BUDGET = 5000;
    public static final List<String> OLD_OBJECTS = new List<String>{
        'Bill_Line_Item__c', 'Payment__c', 'Estimate_Line_Item__c', 'Job_Slip_Line__c', 'Service_Entry__c'
    };
    public static final String ACCESS_SET = 'WS_Biller_Old_Records_Access';
    // The old fields a permission set can grant (required ones are always readable).
    private static final Map<String, List<String>> GRANTABLE_FIELDS = new Map<String, List<String>>{
        'Bill_Line_Item__c' => new List<String>{ 'Discount__c', 'Gst_Type__c', 'HSN_SAC_Code__c', 'Part__c', 'Tax_Rate_Percent__c', 'Unit__c' },
        'Payment__c' => new List<String>(),
        'Estimate_Line_Item__c' => new List<String>{ 'Discount__c', 'Gst_Type__c', 'HSN_SAC_Code__c', 'Part__c', 'Tax_Rate_Percent__c', 'Unit__c' },
        'Job_Slip_Line__c' => new List<String>{ 'Customer_Request__c', 'Labour_Estimate__c', 'Observation__c', 'Sort_Order__c', 'Spares_Estimate__c' },
        'Service_Entry__c' => new List<String>{ 'Unique_Key__c', 'Visit_Start__c', 'Work_Done__c' }
    };
    // A detail object's access needs Read on its master in the same permission set.
    private static final Map<String, String> MASTER_OF = new Map<String, String>{ 'Job_Slip_Line__c' => 'Job_Slip__c' };

    /**
     * One run. dryRun: work it all out, report it, then roll the records back
     * (the temporary access, if a first run grants it, stays).
     */
    public static List<String> run(Boolean dryRun) {
        List<String> report = new List<String>();
        if (presentObjects().isEmpty()) {
            report.add('FOLD-REMAINING: 0');
            return report;
        }
        if (grantAccess()) {
            report.add('Gave ' + UserInfo.getUserName() + ' temporary access to the old records (permission set '
                + ACCESS_SET + '). Run again to move them.');
            report.add('FOLD-REMAINING: -1');
            return report;
        }
        if (remaining(new List<String>()) == 0) {
            removeAccess();
            report.add('Nothing left to move; the temporary access is removed.');
            report.add('FOLD-REMAINING: 0');
            return report;
        }

        Savepoint sp = dryRun ? Database.setSavepoint() : null;
        foldBills(report, dryRun);
        foldEstimates(report, dryRun);
        foldJobSlips(report, dryRun);
        foldServiceBook(report, dryRun);
        Integer remaining = remaining(report);
        if (dryRun) {
            Database.rollback(sp);
            report.add('DRY RUN: everything above was rolled back; nothing changed.');
        }
        // Removing the access is a setup change, so it waits for a run of its own.
        if (remaining == 0) {
            report.add('Everything is moved. One more run removes the temporary access.');
        }
        report.add('FOLD-REMAINING: ' + (remaining == 0 ? -1 : remaining));
        return report;
    }

    private static List<String> presentObjects() {
        List<String> present = new List<String>();
        for (String objectName : OLD_OBJECTS) {
            if (hasObject(objectName)) {
                present.add(objectName);
            }
        }
        return present;
    }

    /**
     * Gives the running user read, create, edit and delete on the old objects
     * and their fields, through ACCESS_SET. True if anything had to be added,
     * which only applies from the next transaction.
     */
    public static Boolean grantAccess() {
        Boolean changed = false;
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = :ACCESS_SET];
        PermissionSet accessSet;
        if (sets.isEmpty()) {
            accessSet = new PermissionSet(
                Name = ACCESS_SET,
                Label = 'WS Biller old records (temporary)',
                Description = 'Lets ChildRecordFold move the old child records into their parents. It removes this set when done.'
            );
            insert accessSet;
            changed = true;
        } else {
            accessSet = sets[0];
        }

        Set<String> objectsGranted = new Set<String>();
        for (ObjectPermissions granted : [SELECT SobjectType FROM ObjectPermissions WHERE ParentId = :accessSet.Id]) {
            objectsGranted.add(granted.SobjectType);
        }
        Set<String> fieldsGranted = new Set<String>();
        for (FieldPermissions granted : [SELECT Field FROM FieldPermissions WHERE ParentId = :accessSet.Id]) {
            fieldsGranted.add(granted.Field);
        }
        List<ObjectPermissions> masterGrants = new List<ObjectPermissions>();
        List<ObjectPermissions> objectGrants = new List<ObjectPermissions>();
        List<FieldPermissions> fieldGrants = new List<FieldPermissions>();
        for (String objectName : presentObjects()) {
            String master = MASTER_OF.get(objectName);
            if (master != null && !objectsGranted.contains(master)) {
                masterGrants.add(new ObjectPermissions(ParentId = accessSet.Id, SobjectType = master, PermissionsRead = true));
                objectsGranted.add(master);
            }
            if (!objectsGranted.contains(objectName)) {
                objectGrants.add(new ObjectPermissions(
                    ParentId = accessSet.Id, SobjectType = objectName,
                    PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true
                ));
            }
            for (String field : GRANTABLE_FIELDS.get(objectName)) {
                String fullName = objectName + '.' + field;
                if (!fieldsGranted.contains(fullName)) {
                    fieldGrants.add(new FieldPermissions(
                        ParentId = accessSet.Id, SobjectType = objectName, Field = fullName, PermissionsRead = true, PermissionsEdit = true
                    ));
                }
            }
        }
        if (!masterGrants.isEmpty()) {
            insert masterGrants;
            changed = true;
        }
        if (!objectGrants.isEmpty()) {
            insert objectGrants;
            changed = true;
        }
        if (!fieldGrants.isEmpty()) {
            insert fieldGrants;
            changed = true;
        }
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId = :accessSet.Id AND AssigneeId = :UserInfo.getUserId()] == 0) {
            insert new PermissionSetAssignment(PermissionSetId = accessSet.Id, AssigneeId = UserInfo.getUserId());
            changed = true;
        }
        return changed;
    }

    /** Takes ACCESS_SET away from everyone and deletes it. */
    public static void removeAccess() {
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = :ACCESS_SET];
        if (sets.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM PermissionSetAssignment WHERE PermissionSetId = :sets[0].Id];
        delete sets;
    }

    /** Whether this org still has the old object (it has none on a new org). */
    public static Boolean hasObject(String objectName) {
        return TYPES.containsKey(objectName.toLowerCase());
    }

    private static Integer remaining(List<String> report) {
        Integer remaining = 0;
        for (String childObject : OLD_OBJECTS) {
            if (hasObject(childObject)) {
                Integer left = Database.countQuery('SELECT COUNT() FROM ' + childObject);
                report.add(childObject + ' records left: ' + left);
                remaining += left;
            }
        }
        return remaining;
    }

    // Parents with old children, whole parents only, up to about CHILD_CAP children.
    private static List<Id> parentsToFold(String childObject, String parentField, Integer childCap) {
        List<Id> parents = new List<Id>();
        Integer children = 0;
        for (AggregateResult row : Database.query(
            'SELECT ' + parentField + ' p, COUNT(Id) n FROM ' + childObject + ' GROUP BY ' + parentField + ' LIMIT 500'
        )) {
            Integer n = (Integer) row.get('n');
            if (!parents.isEmpty() && children + n > childCap) {
                break;
            }
            parents.add((Id) row.get('p'));
            children += n;
        }
        return parents;
    }

    private static void removeChildren(List<SObject> children, Boolean emptyBin) {
        if (!children.isEmpty()) {
            delete children;
            if (emptyBin) {
                Database.emptyRecycleBin(children);
            }
        }
    }

    // Bills: lines and payments
    private static void foldBills(List<String> report, Boolean dryRun) {
        Boolean hasBillLines = TYPES.containsKey('bill_line_item__c');
        Boolean hasPayments = TYPES.containsKey('payment__c');
        if ((hasBillLines || hasPayments) && Limits.getDmlRows() < ROW_BUDGET) {
            Set<Id> billIds = new Set<Id>();
            if (hasBillLines) {
                billIds.addAll(parentsToFold('Bill_Line_Item__c', 'Bill__c', CHILD_CAP));
            }
            if (hasPayments && billIds.size() < 300) {
                billIds.addAll(parentsToFold('Payment__c', 'Bill__c', CHILD_CAP));
            }
            if (!billIds.isEmpty()) {
                Map<Id, Bill__c> bills = new Map<Id, Bill__c>([
                    SELECT Id, Invoice_Number__c, Subtotal__c, GST_Amount__c, Line_Items__c, Payments__c FROM Bill__c WHERE Id IN :billIds
                ]);
                Map<Id, List<BillController.LineItemInput>> linesByBill = new Map<Id, List<BillController.LineItemInput>>();
                List<SObject> oldLines = new List<SObject>();
                if (hasBillLines) {
                    for (SObject line : Database.query(
                        'SELECT Id, Bill__c, Part__c, Description__c, Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c,'
                        + ' HSN_SAC_Code__c, Unit__c, Discount__c FROM Bill_Line_Item__c WHERE Bill__c IN :billIds ORDER BY CreatedDate, Id'
                    )) {
                        Id billId = (Id) line.get('Bill__c');
                        if (!linesByBill.containsKey(billId)) {
                            linesByBill.put(billId, new List<BillController.LineItemInput>());
                        }
                        BillController.LineItemInput li = new BillController.LineItemInput();
                        li.partId = (Id) line.get('Part__c');
                        li.description = (String) line.get('Description__c');
                        li.quantity = (Decimal) line.get('Quantity__c');
                        li.unitPrice = (Decimal) line.get('Unit_Price__c');
                        li.taxRatePercent = (Decimal) line.get('Tax_Rate_Percent__c');
                        li.gstType = (String) line.get('Gst_Type__c');
                        li.hsnSacCode = (String) line.get('HSN_SAC_Code__c');
                        li.unitLabel = (String) line.get('Unit__c');
                        li.discount = (Decimal) line.get('Discount__c');
                        linesByBill.get(billId).add(li);
                        oldLines.add(line);
                    }
                }
                Map<Id, List<BillPayments.Payment>> paymentsByBill = new Map<Id, List<BillPayments.Payment>>();
                List<SObject> oldPayments = new List<SObject>();
                if (hasPayments) {
                    for (SObject p : Database.query(
                        'SELECT Id, Bill__c, Amount__c, Method__c, Paid_At__c, CreatedDate FROM Payment__c WHERE Bill__c IN :billIds ORDER BY Paid_At__c, CreatedDate, Id'
                    )) {
                        Id billId = (Id) p.get('Bill__c');
                        if (!paymentsByBill.containsKey(billId)) {
                            paymentsByBill.put(billId, new List<BillPayments.Payment>());
                        }
                        BillPayments.Payment payment = new BillPayments.Payment();
                        payment.amount = (Decimal) p.get('Amount__c');
                        payment.method = (String) p.get('Method__c');
                        payment.paidAt = p.get('Paid_At__c') != null ? (Datetime) p.get('Paid_At__c') : (Datetime) p.get('CreatedDate');
                        paymentsByBill.get(billId).add(payment);
                        oldPayments.add(p);
                    }
                }
                List<Bill__c> changes = new List<Bill__c>();
                Integer mismatched = 0;
                for (Bill__c bill : bills.values()) {
                    Bill__c change = new Bill__c(Id = bill.Id);
                    if (linesByBill.containsKey(bill.Id)) {
                        if (String.isNotBlank(bill.Line_Items__c)) {
                            throw new ChildRecordFoldException(bill.Invoice_Number__c + ' already has stored lines and old line records. Nothing was changed; check it by hand.');
                        }
                        change.Line_Items__c = StoredLines.write(linesByBill.get(bill.Id));
                        GstCalculatorService.GstBillResult totals = GstCalculatorService.calculateBill(
                            StoredLines.gstInputs(StoredLines.read(change.Line_Items__c))
                        );
                        if (totals.subtotal != (bill.Subtotal__c == null ? 0 : bill.Subtotal__c) || totals.gst != (bill.GST_Amount__c == null ? 0 : bill.GST_Amount__c)) {
                            mismatched++;
                            report.add('NOTE: ' + bill.Invoice_Number__c + ' lines add up to ' + totals.subtotal + ' + GST ' + totals.gst
                                + ', but it was saved as ' + bill.Subtotal__c + ' + GST ' + bill.GST_Amount__c + ' (kept as saved).');
                        }
                    }
                    if (paymentsByBill.containsKey(bill.Id)) {
                        List<BillPayments.Payment> payments = BillPayments.read(bill.Payments__c);
                        payments.addAll(paymentsByBill.get(bill.Id));
                        change.Payments__c = JSON.serialize(payments, true);
                        change.Amount_Paid__c = BillPayments.sum(payments);
                    }
                    changes.add(change);
                }
                update changes;
                removeChildren(oldLines, !dryRun);
                removeChildren(oldPayments, !dryRun);
                report.add('Bills: ' + changes.size() + ' folded (' + oldLines.size() + ' lines, ' + oldPayments.size() + ' payments); '
                    + mismatched + ' with lines not matching their saved totals.');
            }
        }
    }

    // Estimates
    private static void foldEstimates(List<String> report, Boolean dryRun) {
        if (TYPES.containsKey('estimate_line_item__c') && Limits.getDmlRows() < ROW_BUDGET) {
            List<Id> estimateIds = parentsToFold('Estimate_Line_Item__c', 'Estimate__c', CHILD_CAP);
            if (!estimateIds.isEmpty()) {
                Map<Id, Estimate__c> estimates = new Map<Id, Estimate__c>([SELECT Id, Name, Line_Items__c FROM Estimate__c WHERE Id IN :estimateIds]);
                Map<Id, List<BillController.LineItemInput>> linesByEstimate = new Map<Id, List<BillController.LineItemInput>>();
                List<SObject> oldLines = Database.query(
                    'SELECT Id, Estimate__c, Part__c, Description__c, Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c,'
                    + ' HSN_SAC_Code__c, Unit__c, Discount__c FROM Estimate_Line_Item__c WHERE Estimate__c IN :estimateIds ORDER BY CreatedDate, Id'
                );
                for (SObject line : oldLines) {
                    Id estimateId = (Id) line.get('Estimate__c');
                    if (!linesByEstimate.containsKey(estimateId)) {
                        linesByEstimate.put(estimateId, new List<BillController.LineItemInput>());
                    }
                    BillController.LineItemInput li = new BillController.LineItemInput();
                    li.partId = (Id) line.get('Part__c');
                    li.description = (String) line.get('Description__c');
                    li.quantity = (Decimal) line.get('Quantity__c');
                    li.unitPrice = (Decimal) line.get('Unit_Price__c');
                    li.taxRatePercent = (Decimal) line.get('Tax_Rate_Percent__c');
                    li.gstType = (String) line.get('Gst_Type__c');
                    li.hsnSacCode = (String) line.get('HSN_SAC_Code__c');
                    li.unitLabel = (String) line.get('Unit__c');
                    li.discount = (Decimal) line.get('Discount__c');
                    linesByEstimate.get(estimateId).add(li);
                }
                List<Estimate__c> changes = new List<Estimate__c>();
                for (Id estimateId : linesByEstimate.keySet()) {
                    if (String.isNotBlank(estimates.get(estimateId).Line_Items__c)) {
                        throw new ChildRecordFoldException(estimates.get(estimateId).Name + ' already has stored lines and old line records. Nothing was changed; check it by hand.');
                    }
                    changes.add(new Estimate__c(Id = estimateId, Line_Items__c = StoredLines.write(linesByEstimate.get(estimateId))));
                }
                update changes;
                removeChildren(oldLines, !dryRun);
                report.add('Estimates: ' + changes.size() + ' folded (' + oldLines.size() + ' lines).');
            }
        }
    }

    // Job slips
    private static void foldJobSlips(List<String> report, Boolean dryRun) {
        if (TYPES.containsKey('job_slip_line__c') && Limits.getDmlRows() < ROW_BUDGET) {
            List<Id> slipIds = parentsToFold('Job_Slip_Line__c', 'Job_Slip__c', CHILD_CAP);
            if (!slipIds.isEmpty()) {
                Map<Id, Job_Slip__c> slips = new Map<Id, Job_Slip__c>([SELECT Id, Repair_Lines__c FROM Job_Slip__c WHERE Id IN :slipIds]);
                Map<Id, List<JobSlipController.JobSlipLine>> linesBySlip = new Map<Id, List<JobSlipController.JobSlipLine>>();
                List<SObject> oldLines = Database.query(
                    'SELECT Id, Job_Slip__c, Customer_Request__c, Observation__c, Labour_Estimate__c, Spares_Estimate__c'
                    + ' FROM Job_Slip_Line__c WHERE Job_Slip__c IN :slipIds ORDER BY Sort_Order__c, CreatedDate, Id'
                );
                for (SObject line : oldLines) {
                    Id slipId = (Id) line.get('Job_Slip__c');
                    if (!linesBySlip.containsKey(slipId)) {
                        linesBySlip.put(slipId, new List<JobSlipController.JobSlipLine>());
                    }
                    JobSlipController.JobSlipLine l = new JobSlipController.JobSlipLine();
                    l.customerRequest = (String) line.get('Customer_Request__c');
                    l.observation = (String) line.get('Observation__c');
                    l.labourEstimate = (Decimal) line.get('Labour_Estimate__c');
                    l.sparesEstimate = (Decimal) line.get('Spares_Estimate__c');
                    linesBySlip.get(slipId).add(l);
                }
                List<Job_Slip__c> changes = new List<Job_Slip__c>();
                for (Id slipId : linesBySlip.keySet()) {
                    if (String.isNotBlank(slips.get(slipId).Repair_Lines__c)) {
                        throw new ChildRecordFoldException('Job slip ' + slipId + ' already has stored lines and old line records. Nothing was changed; check it by hand.');
                    }
                    changes.add(new Job_Slip__c(Id = slipId, Repair_Lines__c = JSON.serialize(linesBySlip.get(slipId), true)));
                }
                update changes;
                removeChildren(oldLines, !dryRun);
                report.add('Job slips: ' + changes.size() + ' folded (' + oldLines.size() + ' lines).');
            }
        }
    }

    // Service Book
    private static void foldServiceBook(List<String> report, Boolean dryRun) {
        if (TYPES.containsKey('service_entry__c') && Limits.getDmlRows() < ROW_BUDGET) {
            List<Id> vehicleIds = parentsToFold('Service_Entry__c', 'Vehicle__c', CHILD_CAP);
            if (!vehicleIds.isEmpty()) {
                Map<Id, Vehicle__c> vehicles = new Map<Id, Vehicle__c>([SELECT Id, Name, Service_Book__c FROM Vehicle__c WHERE Id IN :vehicleIds]);
                Map<Id, List<ServiceBookController.Entry>> daysByVehicle = new Map<Id, List<ServiceBookController.Entry>>();
                List<SObject> oldEntries = Database.query(
                    'SELECT Id, Vehicle__c, Entry_Date__c, Visit_Start__c, Work_Done__c, CreatedDate'
                    + ' FROM Service_Entry__c WHERE Vehicle__c IN :vehicleIds ORDER BY Entry_Date__c, CreatedDate, Id'
                );
                for (SObject e : oldEntries) {
                    Id vehicleId = (Id) e.get('Vehicle__c');
                    if (!daysByVehicle.containsKey(vehicleId)) {
                        daysByVehicle.put(vehicleId, new List<ServiceBookController.Entry>());
                    }
                    ServiceBookController.Entry day = new ServiceBookController.Entry();
                    day.entryDate = (Date) e.get('Entry_Date__c');
                    day.visitStart = (Date) e.get('Visit_Start__c');
                    day.workDone = (String) e.get('Work_Done__c');
                    day.writtenAt = (Datetime) e.get('CreatedDate');
                    daysByVehicle.get(vehicleId).add(day);
                }
                List<Vehicle__c> changes = new List<Vehicle__c>();
                for (Id vehicleId : daysByVehicle.keySet()) {
                    if (String.isNotBlank(vehicles.get(vehicleId).Service_Book__c)) {
                        throw new ChildRecordFoldException(vehicles.get(vehicleId).Name + ' already has a stored Service Book and old entries. Nothing was changed; check it by hand.');
                    }
                    List<ServiceBookController.Entry> days = daysByVehicle.get(vehicleId);
                    String body = JSON.serialize(days, true);
                    if (body.length() > StoredLines.MAX_LENGTH) {
                        throw new ChildRecordFoldException(vehicles.get(vehicleId).Name + '\'s Service Book is too long to store on the car. Nothing was changed.');
                    }
                    changes.add(new Vehicle__c(
                        Id = vehicleId,
                        Service_Book__c = body,
                        First_Service_Date__c = days[0].entryDate,
                        Last_Service_Date__c = days[days.size() - 1].entryDate
                    ));
                }
                update changes;
                removeChildren(oldEntries, !dryRun);
                report.add('Service Book: ' + changes.size() + ' cars folded (' + oldEntries.size() + ' days).');
            }
        }
    }
}
