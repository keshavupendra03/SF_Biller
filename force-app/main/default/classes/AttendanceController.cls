/**
 * The Attendance screen (attendanceBook): marking a day for every mechanic, a
 * mechanic's month as a calendar, and pay (advances, salary paid, bonuses and
 * deductions, and the balance). The rules and storage are in MechanicPay
 * (architecture.md, Forty-fourth).
 */
public with sharing class AttendanceController {

    public class AttendanceControllerException extends Exception {}

    public class DayRow {
        @AuraEnabled public Id mechanicId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean isWeeklyOff { get; set; }
    }

    public class DayView {
        @AuraEnabled public Date day { get; set; }
        @AuraEnabled public List<DayRow> rows { get; set; }
    }

    public class DayCell {
        @AuraEnabled public Date day { get; set; }
        @AuraEnabled public Integer dayNumber { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean isWeeklyOff { get; set; }
        @AuraEnabled public Boolean isFuture { get; set; }
    }

    public class EntryItem {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Date entryDate { get; set; }
        @AuraEnabled public String method { get; set; }
        @AuraEnabled public String note { get; set; }
    }

    public class MechanicMonth {
        @AuraEnabled public Id mechanicId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Date month { get; set; }
        // The mechanic's pay now (for the pay form) and this month's (for the sums).
        @AuraEnabled public String payType { get; set; }
        @AuraEnabled public Decimal payAmount { get; set; }
        @AuraEnabled public String weeklyOff { get; set; }
        @AuraEnabled public Boolean hasPay { get; set; }
        @AuraEnabled public String monthPayType { get; set; }
        @AuraEnabled public Decimal monthPayAmount { get; set; }
        // 0 = Monday: blank cells before day 1 on a calendar that starts on Monday.
        @AuraEnabled public Integer firstWeekday { get; set; }
        @AuraEnabled public List<DayCell> days { get; set; }
        @AuraEnabled public Decimal daysPresent { get; set; }
        @AuraEnabled public Decimal daysAbsent { get; set; }
        @AuraEnabled public Integer halfDays { get; set; }
        @AuraEnabled public Integer leaveDays { get; set; }
        @AuraEnabled public Integer offDays { get; set; }
        @AuraEnabled public Integer offDaysWorked { get; set; }
        @AuraEnabled public Decimal earned { get; set; }
        @AuraEnabled public Decimal extra { get; set; }
        @AuraEnabled public Decimal advances { get; set; }
        @AuraEnabled public Decimal paid { get; set; }
        @AuraEnabled public Decimal broughtForward { get; set; }
        @AuraEnabled public Decimal balance { get; set; }
        @AuraEnabled public List<EntryItem> entries { get; set; }
        // Archived into Files (AttendanceArchive): shown, not changed.
        @AuraEnabled public Boolean isArchived { get; set; }
    }

    public class EntryInput {
        @AuraEnabled public Id mechanicId { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Date entryDate { get; set; }
        @AuraEnabled public String method { get; set; }
        @AuraEnabled public String note { get; set; }
    }

    public class PayInput {
        @AuraEnabled public Id mechanicId { get; set; }
        @AuraEnabled public String payType { get; set; }
        @AuraEnabled public Decimal payAmount { get; set; }
        @AuraEnabled public String weeklyOff { get; set; }
    }

    // ---- a day ----------------------------------------------------------

    @AuraEnabled
    public static DayView getDay(Date day) {
        Date d = day == null ? Date.today() : day;
        List<Mechanic__c> mechanics = activeMechanics();
        Map<Id, Mechanic_Month__c> months = MechanicPay.monthsOf(new Map<Id, Mechanic__c>(mechanics).keySet(), d);
        putArchived(months, mechanics, d);
        DayView view = new DayView();
        view.day = d;
        view.rows = new List<DayRow>();
        for (Mechanic__c mechanic : mechanics) {
            Mechanic_Month__c m = months.get(mechanic.Id);
            String weeklyOff = m != null ? m.Weekly_Off__c : mechanic.Weekly_Off__c;
            DayRow row = new DayRow();
            row.mechanicId = mechanic.Id;
            row.name = mechanic.Name;
            row.status = MechanicPay.statusOn(m, d);
            row.isWeeklyOff = MechanicPay.isWeeklyOff(weeklyOff, d);
            view.rows.add(row);
        }
        return view;
    }

    @AuraEnabled
    public static DayRow markDay(Id mechanicId, Date day, String status) {
        try {
            Mechanic__c mechanic = MechanicPay.mechanic(mechanicId);
            Mechanic_Month__c m = MechanicPay.mark(mechanic, day, status);
            DayRow row = new DayRow();
            row.mechanicId = mechanic.Id;
            row.name = mechanic.Name;
            row.status = MechanicPay.statusOn(m, day);
            row.isWeeklyOff = MechanicPay.isWeeklyOff(m.Weekly_Off__c, day);
            return row;
        } catch (MechanicPay.MechanicPayException e) {
            throw new AttendanceControllerException(e.getMessage());
        }
    }

    /** Marks everyone not marked yet as present; a weekly off is left as it is. */
    @AuraEnabled
    public static DayView markAllPresent(Date day) {
        try {
            for (DayRow row : getDay(day).rows) {
                if (row.status == MechanicPay.UNMARKED && row.isWeeklyOff != true) {
                    MechanicPay.mark(MechanicPay.mechanic(row.mechanicId), day, 'P');
                }
            }
            return getDay(day);
        } catch (MechanicPay.MechanicPayException e) {
            throw new AttendanceControllerException(e.getMessage());
        }
    }

    // ---- a month --------------------------------------------------------

    @AuraEnabled
    public static MechanicMonth getMonth(Id mechanicId, Date month) {
        Mechanic__c mechanic = MechanicPay.mechanic(mechanicId);
        Date start = (month == null ? Date.today() : month).toStartOfMonth();
        Map<Id, Mechanic_Month__c> months = MechanicPay.monthsOf(new Set<Id>{ mechanicId }, start);
        putArchived(months, new List<Mechanic__c>{ mechanic }, start);
        Mechanic_Month__c m = months.get(mechanicId);
        return toView(mechanic, m != null ? m : MechanicPay.unsaved(mechanic, start));
    }

    // Months archived into Files, read from the archive (only when some are).
    private static void putArchived(Map<Id, Mechanic_Month__c> months, List<Mechanic__c> mechanics, Date day) {
        Set<Id> archived = new Set<Id>();
        for (Mechanic__c mechanic : mechanics) {
            if (MechanicPay.isArchived(mechanic, day) && !months.containsKey(mechanic.Id)) {
                archived.add(mechanic.Id);
            }
        }
        if (!archived.isEmpty()) {
            months.putAll(AttendanceArchive.monthsOf(archived, day));
        }
    }

    /** Every mechanic's pay for a month: the active ones, and any other with something that month. */
    @AuraEnabled
    public static List<MechanicMonth> getPayMonth(Date month) {
        Date start = (month == null ? Date.today() : month).toStartOfMonth();
        Map<Id, Mechanic__c> mechanics = new Map<Id, Mechanic__c>(activeMechanics());
        Set<Id> withMonth = new Set<Id>();
        for (Mechanic_Month__c m : [SELECT Mechanic__c FROM Mechanic_Month__c WHERE Month__c = :start]) {
            withMonth.add(m.Mechanic__c);
        }
        // A month archived for anyone: those who had it (a mechanic since let go too).
        Map<Id, Mechanic_Month__c> archivedMonths = new Map<Id, Mechanic_Month__c>();
        if ([SELECT COUNT() FROM Mechanic__c WHERE Archived_To__c >= :start] > 0) {
            archivedMonths = AttendanceArchive.monthsOf(null, start);
            withMonth.addAll(archivedMonths.keySet());
        }
        withMonth.removeAll(mechanics.keySet());
        if (!withMonth.isEmpty()) {
            mechanics.putAll(new Map<Id, Mechanic__c>([
                SELECT Id, Name, Phone__c, Is_Active__c, Pay_Type__c, Pay_Amount__c, Weekly_Off__c, Pay_Start__c,
                       Archived_To__c, Archived_Balance__c
                FROM Mechanic__c WHERE Id IN :withMonth
            ]));
        }
        Map<Id, Mechanic_Month__c> months = MechanicPay.monthsOf(mechanics.keySet(), start);
        for (Id mechanicId : archivedMonths.keySet()) {
            if (!months.containsKey(mechanicId)) {
                months.put(mechanicId, archivedMonths.get(mechanicId));
            }
        }
        List<MechanicMonth> result = new List<MechanicMonth>();
        for (Mechanic__c mechanic : sortedByName(mechanics.values())) {
            Mechanic_Month__c m = months.get(mechanic.Id);
            result.add(toView(mechanic, m != null ? m : MechanicPay.unsaved(mechanic, start)));
        }
        return result;
    }

    @AuraEnabled
    public static MechanicMonth addEntry(EntryInput input) {
        if (input == null || input.mechanicId == null) {
            throw new AttendanceControllerException('Choose the mechanic.');
        }
        try {
            MechanicPay.Entry e = new MechanicPay.Entry();
            e.type = input.type;
            e.amount = input.amount;
            e.entryDate = input.entryDate;
            e.method = String.isBlank(input.method) ? null : input.method;
            e.note = input.note;
            Mechanic__c mechanic = MechanicPay.mechanic(input.mechanicId);
            return toView(mechanic, MechanicPay.addEntry(mechanic, e));
        } catch (MechanicPay.MechanicPayException e) {
            throw new AttendanceControllerException(e.getMessage());
        }
    }

    @AuraEnabled
    public static MechanicMonth removeEntry(Id mechanicId, Date month, String entryId) {
        try {
            Mechanic__c mechanic = MechanicPay.mechanic(mechanicId);
            return toView(mechanic, MechanicPay.removeEntry(mechanic, month, entryId));
        } catch (MechanicPay.MechanicPayException e) {
            throw new AttendanceControllerException(e.getMessage());
        }
    }

    /** Sets a mechanic's pay; returns this month as it now stands. */
    @AuraEnabled
    public static MechanicMonth savePay(PayInput input) {
        if (input == null || input.mechanicId == null) {
            throw new AttendanceControllerException('Choose the mechanic.');
        }
        try {
            Mechanic__c mechanic = MechanicPay.setPay(MechanicPay.mechanic(input.mechanicId), input.payType, input.payAmount, input.weeklyOff);
            return getMonth(mechanic.Id, Date.today());
        } catch (MechanicPay.MechanicPayException e) {
            throw new AttendanceControllerException(e.getMessage());
        }
    }

    // ---- helpers --------------------------------------------------------

    private static List<Mechanic__c> activeMechanics() {
        return [
            SELECT Id, Name, Phone__c, Is_Active__c, Pay_Type__c, Pay_Amount__c, Weekly_Off__c, Pay_Start__c,
                   Archived_To__c, Archived_Balance__c
            FROM Mechanic__c WHERE Is_Active__c = true ORDER BY Name
        ];
    }

    private static List<Mechanic__c> sortedByName(List<Mechanic__c> mechanics) {
        Map<String, Mechanic__c> byKey = new Map<String, Mechanic__c>();
        for (Mechanic__c m : mechanics) {
            byKey.put(m.Name.toLowerCase() + '|' + m.Id, m);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<Mechanic__c> sorted = new List<Mechanic__c>();
        for (String k : keys) {
            sorted.add(byKey.get(k));
        }
        return sorted;
    }

    private static MechanicMonth toView(Mechanic__c mechanic, Mechanic_Month__c m) {
        MechanicMonth v = new MechanicMonth();
        v.mechanicId = mechanic.Id;
        v.name = mechanic.Name;
        v.phone = mechanic.Phone__c;
        v.isActive = mechanic.Is_Active__c;
        v.month = m.Month__c;
        v.isArchived = MechanicPay.isArchived(mechanic, m.Month__c);
        v.payType = mechanic.Pay_Type__c;
        v.payAmount = mechanic.Pay_Amount__c;
        v.weeklyOff = mechanic.Weekly_Off__c;
        v.hasPay = mechanic.Pay_Amount__c != null && mechanic.Pay_Start__c != null;
        v.monthPayType = m.Pay_Type__c;
        v.monthPayAmount = m.Pay_Amount__c;
        v.firstWeekday = MechanicPay.weekdayIndex(m.Month__c);

        v.days = new List<DayCell>();
        v.halfDays = 0;
        v.leaveDays = 0;
        v.offDays = 0;
        v.offDaysWorked = 0;
        Date today = Date.today();
        for (Integer i = 0; i < MechanicPay.daysIn(m.Month__c); i++) {
            Date d = m.Month__c.addDays(i);
            DayCell cell = new DayCell();
            cell.day = d;
            cell.dayNumber = i + 1;
            cell.status = MechanicPay.statusOn(m, d);
            cell.isWeeklyOff = MechanicPay.isWeeklyOff(m.Weekly_Off__c, d);
            cell.isFuture = d > today;
            v.days.add(cell);
            if (cell.status == 'H') {
                v.halfDays++;
            } else if (cell.status == 'L') {
                v.leaveDays++;
            }
            if (cell.isWeeklyOff) {
                if (cell.status == 'P') {
                    v.offDaysWorked++;
                } else if (cell.status == MechanicPay.UNMARKED && !cell.isFuture) {
                    v.offDays++;
                }
            }
        }
        v.daysPresent = m.Days_Present__c;
        v.daysAbsent = m.Days_Absent__c;
        v.earned = m.Earned__c;
        v.extra = m.Extra__c;
        v.advances = m.Advances__c;
        v.paid = m.Paid__c;
        v.broughtForward = m.Opening_Balance__c;
        v.balance = m.Closing_Balance__c;
        v.entries = new List<EntryItem>();
        for (MechanicPay.Entry e : MechanicPay.entriesOf(m)) {
            EntryItem item = new EntryItem();
            item.id = e.id;
            item.type = e.type;
            item.amount = e.amount;
            item.entryDate = e.entryDate;
            item.method = e.method;
            item.note = e.note;
            v.entries.add(item);
        }
        return v;
    }
}
