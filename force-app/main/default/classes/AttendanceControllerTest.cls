@isTest
private class AttendanceControllerTest {

    @testSetup
    static void setup() {
        Date start = Date.today().toStartOfMonth();
        insert new List<Mechanic__c>{
            new Mechanic__c(Name = 'Anil', Is_Active__c = true, Pay_Type__c = 'Monthly', Pay_Amount__c = 15000, Weekly_Off__c = 'None', Pay_Start__c = start),
            new Mechanic__c(Name = 'Deepak', Is_Active__c = true, Pay_Type__c = 'Daily', Pay_Amount__c = 600, Weekly_Off__c = MechanicPay.weekdayOf(Date.today()), Pay_Start__c = start),
            new Mechanic__c(Name = 'Old Hand', Is_Active__c = false)
        };
    }

    private static Id idOf(String name) {
        return [SELECT Id FROM Mechanic__c WHERE Name = :name].Id;
    }

    @isTest
    static void today_listsActiveMechanics_andMarkAllPresentSkipsTheWeeklyOff() {
        Test.startTest();
        AttendanceController.DayView before = AttendanceController.getDay(Date.today());
        AttendanceController.DayView after = AttendanceController.markAllPresent(Date.today());
        Test.stopTest();

        System.assertEquals(2, before.rows.size(), 'Inactive mechanics are not on the day.');
        System.assertEquals('Anil', before.rows[0].name);
        System.assertEquals('-', before.rows[0].status);
        System.assertEquals(true, before.rows[1].isWeeklyOff, 'Deepak is off today.');
        System.assertEquals('P', after.rows[0].status);
        System.assertEquals('-', after.rows[1].status, 'A weekly off is left as it is.');
    }

    @isTest
    static void markingADay_showsOnTheMonth() {
        Id anil = idOf('Anil');

        Test.startTest();
        AttendanceController.DayRow row = AttendanceController.markDay(anil, Date.today(), 'A');
        AttendanceController.MechanicMonth month = AttendanceController.getMonth(anil, Date.today());
        Test.stopTest();

        System.assertEquals('A', row.status);
        System.assertEquals('A', month.days[Date.today().day() - 1].status);
        System.assertEquals(14500, month.earned);
        System.assertEquals(1, month.daysAbsent);
        System.assertEquals(MechanicPay.daysIn(Date.today()), month.days.size());
        System.assertEquals(MechanicPay.weekdayIndex(Date.today().toStartOfMonth()), month.firstWeekday);
    }

    @isTest
    static void payMonth_showsEachMechanicsBalance_andEntriesCanBeAddedAndRemoved() {
        Id anil = idOf('Anil');
        AttendanceController.EntryInput advance = new AttendanceController.EntryInput();
        advance.mechanicId = anil;
        advance.type = 'advance';
        advance.amount = 3000;
        advance.method = 'UPI';
        advance.note = 'For rent';

        Test.startTest();
        List<AttendanceController.MechanicMonth> before = AttendanceController.getPayMonth(Date.today());
        AttendanceController.MechanicMonth withAdvance = AttendanceController.addEntry(advance);
        AttendanceController.MechanicMonth removed = AttendanceController.removeEntry(anil, Date.today(), withAdvance.entries[0].id);
        Test.stopTest();

        System.assertEquals(2, before.size());
        System.assertEquals(15000, before[0].balance, 'Anil: the month\'s salary, before anything is paid.');
        System.assertEquals(12000, withAdvance.balance);
        System.assertEquals('For rent', withAdvance.entries[0].note);
        System.assertEquals('UPI', withAdvance.entries[0].method);
        System.assertEquals(15000, removed.balance);
    }

    @isTest
    static void anInactiveMechanicWithSomethingThatMonth_stillShowsOnPay() {
        Id old = idOf('Old Hand');
        AttendanceController.PayInput pay = new AttendanceController.PayInput();
        pay.mechanicId = old;
        pay.payType = 'Monthly';
        pay.payAmount = 9000;
        pay.weeklyOff = 'Sunday';
        AttendanceController.savePay(pay);
        update new Mechanic__c(Id = old, Is_Active__c = false);

        Test.startTest();
        List<AttendanceController.MechanicMonth> months = AttendanceController.getPayMonth(Date.today());
        Test.stopTest();

        System.assertEquals(3, months.size());
        System.assertEquals(false, months[2].isActive);
        System.assertEquals(true, months[2].hasPay);
    }

    @isTest
    static void savePay_returnsThisMonthWithTheNewPay() {
        AttendanceController.PayInput pay = new AttendanceController.PayInput();
        pay.mechanicId = idOf('Anil');
        pay.payType = 'Daily';
        pay.payAmount = 700;
        pay.weeklyOff = 'None';

        Test.startTest();
        AttendanceController.MechanicMonth month = AttendanceController.savePay(pay);
        Test.stopTest();

        System.assertEquals('Daily', month.payType);
        System.assertEquals(700, month.monthPayAmount);
        System.assertEquals(0, month.earned, 'Daily wage: nothing marked yet, nothing earned.');
    }

    @isTest
    static void mistakes_comeBackAsReadableErrors() {
        List<String> messages = new List<String>();
        AttendanceController.EntryInput noMechanic = new AttendanceController.EntryInput();

        Test.startTest();
        try { AttendanceController.markDay(idOf('Anil'), Date.today().addDays(1), 'P'); } catch (AttendanceController.AttendanceControllerException e) { messages.add(e.getMessage()); }
        try { AttendanceController.addEntry(noMechanic); } catch (AttendanceController.AttendanceControllerException e) { messages.add(e.getMessage()); }
        try { AttendanceController.savePay(null); } catch (AttendanceController.AttendanceControllerException e) { messages.add(e.getMessage()); }
        Test.stopTest();

        System.assertEquals(new List<String>{
            'Attendance can\'t be marked for a day that hasn\'t come yet.',
            'Choose the mechanic.',
            'Choose the mechanic.'
        }, messages);
    }
}
