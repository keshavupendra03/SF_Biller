@isTest
private class GstFilingLockTest {

    @isTest
    static void isLocked_onOrBeforeTheFiledMonthEnd() {
        Date filed = Date.newInstance(2026, 10, 31);
        System.assert(GstFilingLock.isLocked(filed, Date.newInstance(2026, 10, 31)));
        System.assert(GstFilingLock.isLocked(filed, Date.newInstance(2026, 4, 1)));
        System.assert(!GstFilingLock.isLocked(filed, Date.newInstance(2026, 11, 1)));
        System.assert(!GstFilingLock.isLocked(null, Date.newInstance(2026, 4, 1)), 'Nothing filed: nothing locked.');
        System.assert(!GstFilingLock.isLocked(filed, null));
    }

    @isTest
    static void datesAreShownAsOnBills() {
        System.assertEquals(Date.newInstance(2026, 2, 28), GstFilingLock.monthEnd(Date.newInstance(2026, 2, 10)));
        System.assertEquals(Date.newInstance(2028, 2, 29), GstFilingLock.monthEnd(Date.newInstance(2028, 2, 1)));
        System.assertEquals(Date.newInstance(2026, 12, 31), GstFilingLock.monthEnd(Date.newInstance(2026, 12, 31)));
        System.assertEquals('October 2026', GstFilingLock.monthName(Date.newInstance(2026, 10, 31)));
        System.assertEquals('05-03-2026', GstFilingLock.formatDate(Date.newInstance(2026, 3, 5)));
    }

    @isTest
    static void lockedMessage_saysWhyAndWhatToDo() {
        String message = GstFilingLock.lockedMessage(Date.newInstance(2026, 10, 31), Date.newInstance(2026, 10, 5), 'deleted');
        System.assert(message.contains('filed up to October 2026'), message);
        System.assert(message.contains('dated 05-10-2026 can\'t be deleted'), message);
        System.assert(message.contains('Workshop Profile'), message);
    }

    @isTest
    static void requireOpen_usesTheCompanysDate_andThePrimaryWhenNoneIsNamed() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GST_Filed_Up_To__c = Date.newInstance(2026, 10, 31));

        GstFilingLock.requireOpen(null, Date.newInstance(2026, 11, 1), 'added');
        try {
            GstFilingLock.requireOpen(null, Date.newInstance(2026, 10, 1), 'added');
            System.assert(false, 'Expected October to be locked.');
        } catch (GstFilingLock.GstFilingLockException e) {
            System.assert(e.getMessage().contains('can\'t be added'), e.getMessage());
        }
        System.assertEquals(Date.newInstance(2026, 10, 31), GstFilingLock.filedUpTo(null));
    }
}
