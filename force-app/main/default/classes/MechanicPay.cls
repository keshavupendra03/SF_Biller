/**
 * Mechanic attendance and pay (architecture.md, Forty-fourth). One
 * Mechanic_Month__c per mechanic per month holds the whole month:
 *   Days__c     one letter per day: P present, H half day, A absent,
 *               L paid leave, - not marked
 *   Entries__c  advances, salary payments, bonuses and deductions (JSON)
 * and the pay worked out from them, so a month costs one record however many
 * days are marked or payments made.
 *
 * Pay rules (agreed with the user, 2026-11-25):
 *   Monthly  salary, less salary / 30 for each absent day (half for a half
 *            day), plus a day's pay for each weekly off worked. Days not
 *            marked count as worked, so only absences need marking.
 *   Daily    wage x (present + half days / 2 + paid leave).
 *   Balance  brought forward + earned + bonuses - deductions - advances - paid.
 *            Positive: owed to the mechanic; negative: the mechanic owes.
 *
 * From the month pay was first set up (Mechanic__c.Pay_Start__c) every month
 * has a record, created as needed, so a balance always carries forward. A
 * change to one month works out it and every later month again. Every write
 * locks the month's row first (FOR UPDATE), so two people marking or paying at
 * once both count.
 *
 * Old months are archived into Files (AttendanceArchive): the mechanic keeps the
 * last archived month (Archived_To__c) and its closing balance
 * (Archived_Balance__c), which the first month still here brings forward.
 * Archived months can't be changed.
 */
public with sharing class MechanicPay {

    public class MechanicPayException extends Exception {}

    public static final String UNMARKED = '-';
    public static final Set<String> STATUSES = new Set<String>{ 'P', 'H', 'A', 'L', UNMARKED };
    public static final Set<String> ENTRY_TYPES = new Set<String>{ 'advance', 'payment', 'bonus', 'deduction' };
    public static final List<String> METHODS = new List<String>{ 'Cash', 'UPI', 'Bank Transfer' };
    // Index 0 is Monday, as weekdayIndex() counts.
    public static final List<String> WEEKDAYS = new List<String>{ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' };
    private static final Integer NOTE_LENGTH = 100;
    private static final Decimal DAYS_IN_SALARY_MONTH = 30;
    // How far back missing months are filled in, at most.
    private static final Integer MAX_FILL_MONTHS = 36;

    public class Entry {
        public String id;
        public String type;
        public Decimal amount;
        public Date entryDate;
        public String method;
        public String note;
    }

    // ---- dates ---------------------------------------------------------

    /** 0 = Monday ... 6 = Sunday. */
    public static Integer weekdayIndex(Date d) {
        Integer i = Math.mod(Date.newInstance(2024, 1, 1).daysBetween(d), 7);
        return i < 0 ? i + 7 : i;
    }

    public static String weekdayOf(Date d) {
        return WEEKDAYS[weekdayIndex(d)];
    }

    public static Integer daysIn(Date month) {
        return Date.daysInMonth(month.year(), month.month());
    }

    public static String keyFor(Id mechanicId, Date month) {
        return mechanicId + '|' + String.valueOf(month.toStartOfMonth()).left(7);
    }

    public static Boolean isWeeklyOff(String weeklyOff, Date d) {
        return String.isNotBlank(weeklyOff) && weeklyOff.equals(weekdayOf(d));
    }

    // ---- reading --------------------------------------------------------

    private static final String FIELDS = 'Id, Mechanic__c, Month__c, Unique_Key__c, Days__c, Entries__c, Pay_Type__c, Pay_Amount__c, Weekly_Off__c, '
        + 'Days_Present__c, Days_Absent__c, Earned__c, Extra__c, Advances__c, Paid__c, Opening_Balance__c, Closing_Balance__c';

    /** The saved months of these mechanics for one month, by mechanic. Nothing is created. */
    public static Map<Id, Mechanic_Month__c> monthsOf(Set<Id> mechanicIds, Date month) {
        Date start = month.toStartOfMonth();
        Map<Id, Mechanic_Month__c> byMechanic = new Map<Id, Mechanic_Month__c>();
        for (Mechanic_Month__c m : Database.query('SELECT ' + FIELDS + ' FROM Mechanic_Month__c WHERE Mechanic__c IN :mechanicIds AND Month__c = :start')) {
            byMechanic.put(m.Mechanic__c, m);
        }
        return byMechanic;
    }

    public static String statusOn(Mechanic_Month__c m, Date d) {
        if (m == null || String.isBlank(m.Days__c) || d.day() > m.Days__c.length()) {
            return UNMARKED;
        }
        return m.Days__c.substring(d.day() - 1, d.day());
    }

    public static List<Entry> entriesOf(Mechanic_Month__c m) {
        if (m == null || String.isBlank(m.Entries__c)) {
            return new List<Entry>();
        }
        return (List<Entry>) JSON.deserialize(m.Entries__c, List<Entry>.class);
    }

    /**
     * A month that has no record yet, as it would be: nothing marked, the
     * mechanic's current pay, and last month's balance brought forward.
     */
    public static Mechanic_Month__c unsaved(Mechanic__c mechanic, Date month) {
        Date start = month.toStartOfMonth();
        Mechanic_Month__c m = new Mechanic_Month__c(
            Mechanic__c = mechanic.Id,
            Month__c = start,
            Days__c = UNMARKED.repeat(daysIn(start)),
            Pay_Type__c = mechanic.Pay_Type__c,
            Pay_Amount__c = mechanic.Pay_Start__c != null && start >= mechanic.Pay_Start__c ? mechanic.Pay_Amount__c : null,
            Weekly_Off__c = mechanic.Weekly_Off__c
        );
        work(m, closingBefore(mechanic.Id, start));
        return m;
    }

    private static Decimal closingBefore(Id mechanicId, Date month) {
        List<Mechanic_Month__c> earlier = [
            SELECT Closing_Balance__c FROM Mechanic_Month__c
            WHERE Mechanic__c = :mechanicId AND Month__c < :month
            ORDER BY Month__c DESC LIMIT 1
        ];
        if (!earlier.isEmpty()) {
            return earlier[0].Closing_Balance__c == null ? 0 : earlier[0].Closing_Balance__c;
        }
        // Every month before this one archived: the last one's balance carries on.
        List<Mechanic__c> archived = [SELECT Archived_To__c, Archived_Balance__c FROM Mechanic__c WHERE Id = :mechanicId];
        if (!archived.isEmpty() && archived[0].Archived_To__c != null && archived[0].Archived_To__c < month) {
            return archived[0].Archived_Balance__c == null ? 0 : archived[0].Archived_Balance__c;
        }
        return 0;
    }

    /** The last archived month of this mechanic's attendance, or null. */
    public static Date archivedTo(Mechanic__c mechanic) {
        if (mechanic.isSet('Archived_To__c')) {
            return mechanic.Archived_To__c;
        }
        return [SELECT Archived_To__c FROM Mechanic__c WHERE Id = :mechanic.Id].Archived_To__c;
    }

    public static Boolean isArchived(Mechanic__c mechanic, Date month) {
        Date archivedTo = archivedTo(mechanic);
        return archivedTo != null && month.toStartOfMonth() <= archivedTo;
    }

    // ---- working it out -------------------------------------------------

    /** Fills a month's summary fields from its days, entries and pay. */
    public static void work(Mechanic_Month__c m, Decimal opening) {
        Date start = m.Month__c;
        String days = m.Days__c == null ? '' : m.Days__c;
        Decimal present = 0;
        Decimal half = 0;
        Decimal absent = 0;
        Decimal leave = 0;
        Decimal offWorked = 0;
        for (Integer i = 0; i < days.length(); i++) {
            String status = days.substring(i, i + 1);
            Boolean off = isWeeklyOff(m.Weekly_Off__c, start.addDays(i));
            if (status == 'P') {
                present++;
                if (off) {
                    offWorked++;
                }
            } else if (status == 'H') {
                half++;
            } else if (status == 'A') {
                absent++;
            } else if (status == 'L') {
                leave++;
            }
        }
        Decimal amount = m.Pay_Amount__c == null ? 0 : m.Pay_Amount__c;
        Decimal earned;
        if ('Daily'.equals(m.Pay_Type__c)) {
            earned = amount * (present + half / 2 + leave);
        } else {
            Decimal perDay = amount / DAYS_IN_SALARY_MONTH;
            earned = amount - (absent + half / 2) * perDay + offWorked * perDay;
        }
        earned = Math.max(earned, 0).setScale(0, System.RoundingMode.HALF_UP);

        Decimal advances = 0;
        Decimal paid = 0;
        Decimal extra = 0;
        for (Entry e : entriesOf(m)) {
            Decimal a = e.amount == null ? 0 : e.amount;
            if (e.type == 'advance') {
                advances += a;
            } else if (e.type == 'payment') {
                paid += a;
            } else if (e.type == 'bonus') {
                extra += a;
            } else if (e.type == 'deduction') {
                extra -= a;
            }
        }
        Decimal brought = opening == null ? 0 : opening;
        m.Days_Present__c = present + half / 2;
        m.Days_Absent__c = absent + half / 2;
        m.Earned__c = earned;
        m.Extra__c = extra;
        m.Advances__c = advances;
        m.Paid__c = paid;
        m.Opening_Balance__c = brought;
        m.Closing_Balance__c = brought + earned + extra - advances - paid;
    }

    // ---- writing --------------------------------------------------------

    public static Mechanic__c mechanic(Id mechanicId) {
        List<Mechanic__c> found = [
            SELECT Id, Name, Phone__c, Is_Active__c, Pay_Type__c, Pay_Amount__c, Weekly_Off__c, Pay_Start__c,
                   Archived_To__c, Archived_Balance__c
            FROM Mechanic__c WHERE Id = :mechanicId
        ];
        if (found.isEmpty()) {
            throw new MechanicPayException('That mechanic was not found.');
        }
        return found[0];
    }

    /** Marks one day. Not for a future day. */
    public static Mechanic_Month__c mark(Mechanic__c mechanic, Date day, String status) {
        if (!STATUSES.contains(status)) {
            throw new MechanicPayException('"' + status + '" is not an attendance mark.');
        }
        if (day > Date.today()) {
            throw new MechanicPayException('Attendance can\'t be marked for a day that hasn\'t come yet.');
        }
        Mechanic_Month__c m = lockMonth(mechanic, day);
        String days = m.Days__c.rightPad(daysIn(m.Month__c), UNMARKED);
        Integer i = day.day() - 1;
        m.Days__c = days.left(i) + status + days.substring(i + 1);
        settle(m);
        return m;
    }

    /** Adds an advance, payment, bonus or deduction, to the month of its date. */
    public static Mechanic_Month__c addEntry(Mechanic__c mechanic, Entry e) {
        if (e == null || !ENTRY_TYPES.contains(e.type)) {
            throw new MechanicPayException('Choose what this is: advance, salary paid, bonus or deduction.');
        }
        if (e.amount == null || e.amount <= 0) {
            throw new MechanicPayException('Type an amount more than zero.');
        }
        Date entryDate = e.entryDate == null ? Date.today() : e.entryDate;
        if (entryDate > Date.today()) {
            throw new MechanicPayException('The date can\'t be in the future.');
        }
        if (e.method != null && !METHODS.contains(e.method)) {
            throw new MechanicPayException('"' + e.method + '" is not a way of paying. Use ' + String.join(METHODS, ', ') + '.');
        }
        Entry saved = new Entry();
        saved.id = String.valueOf(Datetime.now().getTime()) + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(4);
        saved.type = e.type;
        saved.amount = e.amount.setScale(2, System.RoundingMode.HALF_UP);
        saved.entryDate = entryDate;
        saved.method = (e.type == 'advance' || e.type == 'payment') ? (e.method == null ? 'Cash' : e.method) : null;
        saved.note = String.isBlank(e.note) ? null : e.note.trim().abbreviate(NOTE_LENGTH);

        Mechanic_Month__c m = lockMonth(mechanic, entryDate);
        List<Entry> entries = entriesOf(m);
        entries.add(saved);
        m.Entries__c = writeEntries(entries);
        settle(m);
        return m;
    }

    /** Removes one entry (typed by mistake) from a month. */
    public static Mechanic_Month__c removeEntry(Mechanic__c mechanic, Date month, String entryId) {
        Mechanic_Month__c m = lockMonth(mechanic, month);
        List<Entry> kept = new List<Entry>();
        Boolean found = false;
        for (Entry e : entriesOf(m)) {
            if (e.id != null && e.id.equals(entryId)) {
                found = true;
            } else {
                kept.add(e);
            }
        }
        if (!found) {
            throw new MechanicPayException('That entry was already removed.');
        }
        m.Entries__c = kept.isEmpty() ? null : writeEntries(kept);
        settle(m);
        return m;
    }

    /**
     * Sets a mechanic's pay. It applies from this month on, and to months
     * since pay was set up that had none; months already worked out keep
     * theirs. The first time, pay is tracked from this month: attendance
     * kept before it earns nothing.
     */
    public static Mechanic__c setPay(Mechanic__c mechanic, String payType, Decimal amount, String weeklyOff) {
        if (!'Monthly'.equals(payType) && !'Daily'.equals(payType)) {
            throw new MechanicPayException('Choose Monthly salary or Daily wage.');
        }
        if (amount == null || amount <= 0) {
            throw new MechanicPayException('Type the ' + ('Daily'.equals(payType) ? 'daily wage' : 'monthly salary') + '.');
        }
        String off = String.isBlank(weeklyOff) ? 'None' : weeklyOff;
        if (!'None'.equals(off) && !WEEKDAYS.contains(off)) {
            throw new MechanicPayException('"' + weeklyOff + '" is not a day of the week.');
        }
        Date thisMonth = Date.today().toStartOfMonth();
        // Lock the mechanic: two pay changes at once would otherwise race.
        Mechanic__c locked = [SELECT Id, Pay_Start__c FROM Mechanic__c WHERE Id = :mechanic.Id FOR UPDATE];
        Mechanic__c changes = new Mechanic__c(
            Id = mechanic.Id,
            Pay_Type__c = payType,
            Pay_Amount__c = amount.setScale(2, System.RoundingMode.HALF_UP),
            Weekly_Off__c = off,
            Pay_Start__c = locked.Pay_Start__c != null ? locked.Pay_Start__c : thisMonth
        );
        update changes;

        Date payStart = changes.Pay_Start__c;
        Id mechanicId = mechanic.Id;
        List<Mechanic_Month__c> toChange = new List<Mechanic_Month__c>();
        // FOR UPDATE can't be combined with ORDER BY: sorted here instead.
        for (Mechanic_Month__c m : byMonth(Database.query(
            'SELECT ' + FIELDS + ' FROM Mechanic_Month__c WHERE Mechanic__c = :mechanicId'
            + ' AND (Month__c >= :thisMonth OR (Pay_Amount__c = null AND Month__c >= :payStart)) FOR UPDATE'
        ))) {
            m.Pay_Type__c = changes.Pay_Type__c;
            m.Pay_Amount__c = changes.Pay_Amount__c;
            m.Weekly_Off__c = off;
            toChange.add(m);
        }
        if (!toChange.isEmpty()) {
            update toChange;
            settleFrom(mechanic.Id, toChange[0].Month__c);
        }
        Mechanic__c result = mechanic(mechanic.Id);
        // Months from Pay_Start__c on are kept without gaps.
        lockMonth(result, Date.today());
        return result;
    }

    /**
     * The month's record, locked, made if it doesn't exist yet. Months missing
     * since pay was set up are made too, so balances carry forward.
     */
    public static Mechanic_Month__c lockMonth(Mechanic__c mechanic, Date day) {
        Date month = day.toStartOfMonth();
        if (isArchived(mechanic, month)) {
            throw new MechanicPayException(Datetime.newInstance(month, Time.newInstance(0, 0, 0, 0)).format('MMMM yyyy')
                + ' is archived: it can be seen but not changed.');
        }
        String key = keyFor(mechanic.Id, month);
        List<Mechanic_Month__c> rows = Database.query('SELECT ' + FIELDS + ' FROM Mechanic_Month__c WHERE Unique_Key__c = :key FOR UPDATE');
        if (!rows.isEmpty()) {
            return rows[0];
        }
        fillMonths(mechanic, month);
        rows = Database.query('SELECT ' + FIELDS + ' FROM Mechanic_Month__c WHERE Unique_Key__c = :key FOR UPDATE');
        return rows[0];
    }

    private static void fillMonths(Mechanic__c mechanic, Date month) {
        Date first = month;
        if (mechanic.Pay_Start__c != null && mechanic.Pay_Start__c < month) {
            List<Mechanic_Month__c> last = [
                SELECT Month__c FROM Mechanic_Month__c
                WHERE Mechanic__c = :mechanic.Id AND Month__c < :month AND Month__c >= :mechanic.Pay_Start__c
                ORDER BY Month__c DESC LIMIT 1
            ];
            first = last.isEmpty() ? mechanic.Pay_Start__c : last[0].Month__c.addMonths(1);
            if (first.monthsBetween(month) > MAX_FILL_MONTHS) {
                first = month.addMonths(-MAX_FILL_MONTHS);
            }
            // Archived months are not made again.
            Date archivedTo = archivedTo(mechanic);
            if (archivedTo != null && first <= archivedTo) {
                first = archivedTo.addMonths(1);
            }
        }
        List<Mechanic_Month__c> created = new List<Mechanic_Month__c>();
        for (Date m = first; m <= month; m = m.addMonths(1)) {
            created.add(new Mechanic_Month__c(
                Mechanic__c = mechanic.Id,
                Month__c = m,
                Unique_Key__c = keyFor(mechanic.Id, m),
                Days__c = UNMARKED.repeat(daysIn(m)),
                Pay_Type__c = mechanic.Pay_Type__c,
                Pay_Amount__c = mechanic.Pay_Start__c != null && m >= mechanic.Pay_Start__c ? mechanic.Pay_Amount__c : null,
                Weekly_Off__c = mechanic.Weekly_Off__c
            ));
        }
        // Someone else may have made one of them just now: that one stands.
        Database.insert(created, false);
        settleFrom(mechanic.Id, first);
    }

    // Saves a changed month and works out it and every later month again.
    private static void settle(Mechanic_Month__c m) {
        update new Mechanic_Month__c(Id = m.Id, Days__c = m.Days__c, Entries__c = m.Entries__c);
        settleFrom(m.Mechanic__c, m.Month__c);
        Mechanic_Month__c fresh = Database.query('SELECT ' + FIELDS + ' FROM Mechanic_Month__c WHERE Id = \'' + m.Id + '\'');
        m.Days_Present__c = fresh.Days_Present__c;
        m.Days_Absent__c = fresh.Days_Absent__c;
        m.Earned__c = fresh.Earned__c;
        m.Extra__c = fresh.Extra__c;
        m.Advances__c = fresh.Advances__c;
        m.Paid__c = fresh.Paid__c;
        m.Opening_Balance__c = fresh.Opening_Balance__c;
        m.Closing_Balance__c = fresh.Closing_Balance__c;
    }

    private static void settleFrom(Id mechanicId, Date month) {
        Decimal opening = closingBefore(mechanicId, month);
        // FOR UPDATE can't be combined with ORDER BY: sorted here instead.
        List<Mechanic_Month__c> later = byMonth(Database.query(
            'SELECT ' + FIELDS + ' FROM Mechanic_Month__c WHERE Mechanic__c = :mechanicId AND Month__c >= :month FOR UPDATE'
        ));
        for (Mechanic_Month__c m : later) {
            work(m, opening);
            opening = m.Closing_Balance__c;
        }
        update later;
    }

    // One mechanic's months, oldest first.
    private static List<Mechanic_Month__c> byMonth(List<Mechanic_Month__c> months) {
        Map<Date, Mechanic_Month__c> byDate = new Map<Date, Mechanic_Month__c>();
        for (Mechanic_Month__c m : months) {
            byDate.put(m.Month__c, m);
        }
        List<Date> dates = new List<Date>(byDate.keySet());
        dates.sort();
        List<Mechanic_Month__c> sorted = new List<Mechanic_Month__c>();
        for (Date d : dates) {
            sorted.add(byDate.get(d));
        }
        return sorted;
    }

    private static String writeEntries(List<Entry> entries) {
        String body = JSON.serialize(entries, true);
        if (body.length() > StoredLines.MAX_LENGTH) {
            throw new MechanicPayException('This month has too many entries to add another.');
        }
        return body;
    }
}
