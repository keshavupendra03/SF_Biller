@isTest
private class MechanicPayTest {

    // Last month: every day of it is in the past, so any day can be marked.
    private static Date lastMonth() {
        return Date.today().toStartOfMonth().addMonths(-1);
    }

    private static Mechanic__c mechanic(String payType, Decimal amount, String weeklyOff, Date payStart) {
        Mechanic__c m = new Mechanic__c(Name = 'Raju', Is_Active__c = true, Pay_Type__c = payType, Pay_Amount__c = amount,
            Weekly_Off__c = weeklyOff, Pay_Start__c = payStart);
        insert m;
        return MechanicPay.mechanic(m.Id);
    }

    // The first day of the month that is (or isn't) the given weekday.
    private static Date firstDay(Date month, String weekday, Boolean isIt) {
        for (Integer i = 0; i < 7; i++) {
            Date d = month.addDays(i);
            if (MechanicPay.weekdayOf(d).equals(weekday) == isIt) {
                return d;
            }
        }
        return null;
    }

    private static MechanicPay.Entry entry(String type, Decimal amount, Date d) {
        MechanicPay.Entry e = new MechanicPay.Entry();
        e.type = type;
        e.amount = amount;
        e.entryDate = d;
        return e;
    }

    @isTest
    static void weekdays_areWorkedOutFromTheDate() {
        System.assertEquals('Monday', MechanicPay.weekdayOf(Date.newInstance(2024, 1, 1)));
        System.assertEquals('Sunday', MechanicPay.weekdayOf(Date.newInstance(2026, 11, 22)));
        System.assertEquals('Wednesday', MechanicPay.weekdayOf(Date.newInstance(2023, 12, 27)), 'Before the reference date too.');
        System.assertEquals(6, MechanicPay.weekdayIndex(Date.newInstance(2026, 11, 1)), '1 Nov 2026 is a Sunday.');
    }

    @isTest
    static void monthlySalary_absencesAndHalfDaysAreCut_unmarkedDaysCountAsWorked() {
        Mechanic__c raju = mechanic('Monthly', 15000, 'None', lastMonth());
        Date m = lastMonth();

        Test.startTest();
        MechanicPay.mark(raju, m.addDays(1), 'A');
        MechanicPay.mark(raju, m.addDays(2), 'A');
        MechanicPay.mark(raju, m.addDays(3), 'H');
        Mechanic_Month__c month = MechanicPay.mark(raju, m.addDays(4), 'P');
        Test.stopTest();

        // 15000 - 2.5 days x 500
        System.assertEquals(13750, month.Earned__c);
        System.assertEquals(2.5, month.Days_Absent__c);
        System.assertEquals(1.5, month.Days_Present__c);
        System.assertEquals(13750, month.Closing_Balance__c, 'Nothing paid yet: all of it is due.');
        System.assertEquals('-AAHP', month.Days__c.left(5));
    }

    @isTest
    static void monthlySalary_aWeeklyOffWorked_earnsAnExtraDay() {
        Mechanic__c raju = mechanic('Monthly', 15000, 'Sunday', lastMonth());
        Date sunday = firstDay(lastMonth(), 'Sunday', true);

        Test.startTest();
        Mechanic_Month__c month = MechanicPay.mark(raju, sunday, 'P');
        Test.stopTest();

        System.assertEquals(15500, month.Earned__c);
    }

    @isTest
    static void dailyWage_paysPresentHalfDaysAndPaidLeave() {
        Mechanic__c raju = mechanic('Daily', 600, 'Sunday', lastMonth());
        Date m = lastMonth();

        Test.startTest();
        MechanicPay.mark(raju, m.addDays(7), 'P');
        MechanicPay.mark(raju, m.addDays(8), 'P');
        MechanicPay.mark(raju, m.addDays(9), 'P');
        MechanicPay.mark(raju, m.addDays(10), 'H');
        MechanicPay.mark(raju, m.addDays(11), 'L');
        Mechanic_Month__c month = MechanicPay.mark(raju, m.addDays(12), 'A');
        Test.stopTest();

        System.assertEquals(2700, month.Earned__c, '600 x (3 + 0.5 + 1)');
    }

    @isTest
    static void advancesAndPayments_comeOffTheBalance_whichCarriesIntoNextMonth() {
        Mechanic__c raju = mechanic('Monthly', 10000, 'None', lastMonth());
        Date m = lastMonth();

        Test.startTest();
        MechanicPay.addEntry(raju, entry('advance', 2000, m.addDays(4)));
        MechanicPay.addEntry(raju, entry('bonus', 500, m.addDays(5)));
        MechanicPay.addEntry(raju, entry('deduction', 300, m.addDays(6)));
        Mechanic_Month__c last = MechanicPay.addEntry(raju, entry('payment', 7000, m.addDays(20)));
        Mechanic_Month__c now = MechanicPay.addEntry(raju, entry('advance', 1000, Date.today()));
        Test.stopTest();

        // 10000 + 500 - 300 - 2000 - 7000
        System.assertEquals(1200, last.Closing_Balance__c);
        System.assertEquals(2000, last.Advances__c);
        System.assertEquals(7000, last.Paid__c);
        System.assertEquals(200, last.Extra__c);
        System.assertEquals(1200, now.Opening_Balance__c, 'What was still due is brought forward.');
        System.assertEquals(1200 + 10000 - 1000, now.Closing_Balance__c);
        System.assertEquals('Cash', MechanicPay.entriesOf(now)[0].method, 'No way of paying given means cash.');
    }

    @isTest
    static void changingAnEarlierMonth_reworksTheLaterOnes() {
        Mechanic__c raju = mechanic('Monthly', 9000, 'None', lastMonth());
        MechanicPay.addEntry(raju, entry('payment', 9000, lastMonth().addDays(27)));
        Mechanic_Month__c now = MechanicPay.lockMonth(raju, Date.today());
        System.assertEquals(0, now.Opening_Balance__c);

        Test.startTest();
        MechanicPay.mark(raju, lastMonth().addDays(2), 'A');
        Test.stopTest();

        Mechanic_Month__c reworked = [SELECT Opening_Balance__c FROM Mechanic_Month__c WHERE Id = :now.Id];
        System.assertEquals(-300, reworked.Opening_Balance__c, 'Paid a full month but was absent a day: owes 300.');
    }

    @isTest
    static void removingAnEntry_putsTheBalanceBack() {
        Mechanic__c raju = mechanic('Monthly', 10000, 'None', lastMonth());
        Mechanic_Month__c month = MechanicPay.addEntry(raju, entry('advance', 2500, lastMonth().addDays(3)));
        String entryId = MechanicPay.entriesOf(month)[0].id;

        Test.startTest();
        Mechanic_Month__c after = MechanicPay.removeEntry(raju, lastMonth(), entryId);
        Test.stopTest();

        System.assertEquals(0, after.Advances__c);
        System.assertEquals(10000, after.Closing_Balance__c);
        System.assertEquals(null, after.Entries__c);
    }

    @isTest
    static void missingMonths_sincePayWasSetUp_areFilledIn() {
        Date start = Date.today().toStartOfMonth().addMonths(-3);
        Mechanic__c raju = mechanic('Monthly', 8000, 'None', start);

        Test.startTest();
        Mechanic_Month__c now = MechanicPay.mark(raju, Date.today(), 'P');
        Test.stopTest();

        System.assertEquals(4, [SELECT COUNT() FROM Mechanic_Month__c WHERE Mechanic__c = :raju.Id], 'Three earlier months and this one.');
        System.assertEquals(24000, now.Opening_Balance__c, 'Three unpaid months brought forward.');
        System.assertEquals(1, [SELECT COUNT() FROM Mechanic_Month__c WHERE Unique_Key__c = :MechanicPay.keyFor(raju.Id, Date.today())]);
    }

    @isTest
    static void setPay_startsTrackingThisMonth_andKeepsEarlierMonthsAsTheyWere() {
        Mechanic__c raju = mechanic(null, null, null, null);
        // Attendance kept before pay was set up: no pay for it.
        MechanicPay.mark(raju, lastMonth().addDays(5), 'P');

        Test.startTest();
        Mechanic__c withPay = MechanicPay.setPay(raju, 'Monthly', 12000, 'Tuesday');
        Test.stopTest();

        System.assertEquals(Date.today().toStartOfMonth(), withPay.Pay_Start__c);
        System.assertEquals('Tuesday', withPay.Weekly_Off__c);
        Mechanic_Month__c now = [SELECT Pay_Amount__c, Earned__c, Opening_Balance__c FROM Mechanic_Month__c
                                 WHERE Unique_Key__c = :MechanicPay.keyFor(raju.Id, Date.today())];
        System.assertEquals(12000, now.Earned__c);
        System.assertEquals(0, now.Opening_Balance__c);
    }

    @isTest
    static void aPayChange_appliesFromThisMonth_notToMonthsAlreadyWorkedOut() {
        Mechanic__c raju = mechanic('Monthly', 10000, 'None', lastMonth());
        MechanicPay.lockMonth(raju, Date.today());

        Test.startTest();
        MechanicPay.setPay(raju, 'Monthly', 11000, 'Sunday');
        Test.stopTest();

        Map<Date, Decimal> earned = new Map<Date, Decimal>();
        for (Mechanic_Month__c m : [SELECT Month__c, Earned__c FROM Mechanic_Month__c WHERE Mechanic__c = :raju.Id]) {
            earned.put(m.Month__c, m.Earned__c);
        }
        System.assertEquals(10000, earned.get(lastMonth()));
        System.assertEquals(11000, earned.get(Date.today().toStartOfMonth()));
    }

    @isTest
    static void wrongInput_isRefusedInWords() {
        Mechanic__c raju = mechanic('Monthly', 10000, 'None', lastMonth());
        List<String> messages = new List<String>();
        List<MechanicPay.Entry> bad = new List<MechanicPay.Entry>{ entry('tip', 10, null), entry('advance', 0, null), entry('advance', 10, Date.today().addDays(1)) };
        MechanicPay.Entry badMethod = entry('payment', 10, null);
        badMethod.method = 'Cheque';
        bad.add(badMethod);

        Test.startTest();
        for (MechanicPay.Entry e : bad) {
            try { MechanicPay.addEntry(raju, e); messages.add('saved'); } catch (MechanicPay.MechanicPayException ex) { messages.add(ex.getMessage()); }
        }
        try { MechanicPay.mark(raju, Date.today().addDays(1), 'P'); } catch (MechanicPay.MechanicPayException ex) { messages.add(ex.getMessage()); }
        try { MechanicPay.mark(raju, Date.today(), 'X'); } catch (MechanicPay.MechanicPayException ex) { messages.add(ex.getMessage()); }
        try { MechanicPay.setPay(raju, 'Weekly', 100, 'Sunday'); } catch (MechanicPay.MechanicPayException ex) { messages.add(ex.getMessage()); }
        try { MechanicPay.setPay(raju, 'Daily', null, 'Sunday'); } catch (MechanicPay.MechanicPayException ex) { messages.add(ex.getMessage()); }
        try { MechanicPay.setPay(raju, 'Daily', 500, 'Funday'); } catch (MechanicPay.MechanicPayException ex) { messages.add(ex.getMessage()); }
        try { MechanicPay.removeEntry(raju, lastMonth(), 'nope'); } catch (MechanicPay.MechanicPayException ex) { messages.add(ex.getMessage()); }
        Test.stopTest();

        System.assertEquals(new List<String>{
            'Choose what this is: advance, salary paid, bonus or deduction.',
            'Type an amount more than zero.',
            'The date can\'t be in the future.',
            '"Cheque" is not a way of paying. Use Cash, UPI, Bank Transfer.',
            'Attendance can\'t be marked for a day that hasn\'t come yet.',
            '"X" is not an attendance mark.',
            'Choose Monthly salary or Daily wage.',
            'Type the daily wage.',
            '"Funday" is not a day of the week.',
            'That entry was already removed.'
        }, messages);
    }
}
