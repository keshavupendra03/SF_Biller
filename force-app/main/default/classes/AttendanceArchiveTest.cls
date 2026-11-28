@isTest
private class AttendanceArchiveTest {

    // Pay set up 30 months ago: older than the default 24.
    private static Date payStart() {
        return Date.today().toStartOfMonth().addMonths(-30);
    }

    @testSetup
    static void setup() {
        insert new Mechanic__c(Name = 'Anil', Is_Active__c = true, Pay_Type__c = 'Monthly', Pay_Amount__c = 15000,
            Weekly_Off__c = 'None', Pay_Start__c = payStart());
        Mechanic__c anil = MechanicPay.mechanic([SELECT Id FROM Mechanic__c].Id);
        // An advance long ago, never paid back: it carries through every month.
        MechanicPay.Entry advance = new MechanicPay.Entry();
        advance.type = 'advance';
        advance.amount = 5000;
        advance.entryDate = payStart().addDays(3);
        MechanicPay.addEntry(anil, advance);
        // Every month since gets a record (and its pay) when today is marked.
        MechanicPay.mark(anil, Date.today(), 'P');
    }

    private static Mechanic__c anil() {
        return MechanicPay.mechanic([SELECT Id FROM Mechanic__c].Id);
    }

    private static Date lastArchived() {
        return AttendanceArchive.before(ArchiveSettings.current()).addMonths(-1);
    }

    @isTest
    static void oldMonths_go_andTheBalanceCarriesOn() {
        Date firstKept = AttendanceArchive.before(ArchiveSettings.current());
        Mechanic_Month__c keptBefore = [SELECT Opening_Balance__c, Closing_Balance__c FROM Mechanic_Month__c WHERE Month__c = :firstKept];
        Decimal lastClosing = [SELECT Closing_Balance__c FROM Mechanic_Month__c WHERE Month__c = :lastArchived()].Closing_Balance__c;
        Integer total = [SELECT COUNT() FROM Mechanic_Month__c];

        Test.startTest();
        Integer archived = AttendanceArchive.archiveReady(ArchiveSettings.current());
        Test.stopTest();

        System.assertEquals(6, archived, 'Six months from pay start to the cut-off.');
        System.assertEquals(total - 6, [SELECT COUNT() FROM Mechanic_Month__c]);
        Mechanic__c m = anil();
        System.assertEquals(lastArchived(), m.Archived_To__c);
        System.assertEquals(lastClosing, m.Archived_Balance__c);

        // Working out the first kept month again brings the archived balance forward.
        MechanicPay.Entry bonus = new MechanicPay.Entry();
        bonus.type = 'bonus';
        bonus.amount = 100;
        bonus.entryDate = firstKept.addDays(1);
        MechanicPay.addEntry(m, bonus);
        Mechanic_Month__c keptAfter = [SELECT Opening_Balance__c, Closing_Balance__c FROM Mechanic_Month__c WHERE Month__c = :firstKept];
        System.assertEquals(keptBefore.Opening_Balance__c, keptAfter.Opening_Balance__c);
        System.assertEquals(keptBefore.Closing_Balance__c + 100, keptAfter.Closing_Balance__c);
    }

    @isTest
    static void anArchivedMonth_canBeSeen_butNotChanged_orMadeAgain() {
        AttendanceArchive.archiveReady(ArchiveSettings.current());
        Integer left = [SELECT COUNT() FROM Mechanic_Month__c];

        Test.startTest();
        AttendanceController.MechanicMonth shown = AttendanceController.getMonth(anil().Id, payStart());
        List<AttendanceController.MechanicMonth> pay = AttendanceController.getPayMonth(payStart());
        Test.stopTest();

        System.assertEquals(true, shown.isArchived);
        System.assertEquals(1, shown.entries.size(), 'The advance is in the archived month.');
        System.assertEquals(5000, shown.advances);
        System.assertEquals(1, pay.size());
        System.assertEquals(true, pay[0].isArchived);
        System.assertEquals(false, AttendanceController.getMonth(anil().Id, Date.today()).isArchived);
        try {
            AttendanceController.markDay(anil().Id, payStart().addDays(5), 'A');
            System.assert(false, 'Changed an archived month');
        } catch (AttendanceController.AttendanceControllerException e) {
            System.assert(e.getMessage().contains('is archived'), e.getMessage());
        }
        System.assertEquals(left, [SELECT COUNT() FROM Mechanic_Month__c], 'No month was made again.');
    }

    @isTest
    static void theArchiveScreen_andTheJob() {
        ArchiveController.Status before = ArchiveController.getStatus();

        Test.startTest();
        System.enqueueJob(new ArchiveJob());
        Test.stopTest();

        System.assertEquals(6, before.monthsReady);
        System.assertEquals(6, ArchiveController.getStatus().archivedMonths);
        System.assert(ArchiveSettings.current().lastResult.contains('archived 6 attendance months'), ArchiveSettings.current().lastResult);
    }
}
