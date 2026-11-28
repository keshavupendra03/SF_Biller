/**
 * One nightly run with a lot to do at once (architecture.md, Forty-ninth):
 * dormant customers with cars and Service Books, Walk-in cars, old job slips,
 * attendance months and a month of bills, in the one Queueable step that does
 * them, inside the platform's limits.
 */
@isTest
private class ArchiveBulkTest {

    private static final Integer CUSTOMER_COUNT = 30;
    private static final Integer SLIP_COUNT = 200;
    private static final Integer BILL_COUNT = 40;
    private static final Integer MECHANIC_COUNT = 3;

    private static Date oldDay() {
        return Date.today().toStartOfMonth().addMonths(-24).addDays(2);
    }

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GST_Registration_Type__c = 'Unregistered', State__c = 'Madhya Pradesh');
        Datetime longAgo = Datetime.now().addMonths(-30);
        List<Customer__c> customers = new List<Customer__c>();
        for (Integer i = 0; i < CUSTOMER_COUNT; i++) {
            customers.add(new Customer__c(Name = 'Dormant ' + i, Phone__c = '90000' + String.valueOf(10000 + i)));
        }
        insert customers;
        List<Vehicle__c> cars = new List<Vehicle__c>();
        String book = '[{"entryDate":"' + String.valueOf(oldDay()) + '","visitStart":"' + String.valueOf(oldDay()) + '","workDone":"Oil change, filters, brake check and a long note to give the book some size"}]';
        for (Integer i = 0; i < CUSTOMER_COUNT; i++) {
            cars.add(new Vehicle__c(Name = 'MP09A' + String.valueOf(1000 + i), Customer__c = customers[i].Id, Service_Book__c = book,
                First_Service_Date__c = oldDay(), Last_Service_Date__c = oldDay()));
            cars.add(new Vehicle__c(Name = 'MP09B' + String.valueOf(1000 + i), Customer__c = customers[i].Id));
        }
        insert cars;
        for (Customer__c c : customers) {
            Test.setCreatedDate(c.Id, longAgo);
        }
        for (Vehicle__c v : cars) {
            Test.setCreatedDate(v.Id, longAgo);
        }

        // Bills for one more customer, all in one old month.
        Customer__c billed = new Customer__c(Name = 'Billed', Phone__c = '9111100000');
        insert billed;
        List<Bill__c> bills = new List<Bill__c>();
        for (Integer i = 0; i < BILL_COUNT; i++) {
            bills.add(new Bill__c(Customer__c = billed.Id, Bill_Date__c = oldDay().addDays(Math.mod(i, 20))));
        }
        insert bills;
        List<Bill__c> withLines = new List<Bill__c>();
        for (Bill__c b : bills) {
            withLines.add(new Bill__c(Id = b.Id, Line_Items__c = JSON.serialize(new List<BillController.LineItemInput>{
                TestLines.line('Service', 1, 500, 0, 'CGST_SGST', '998714', null) })));
        }
        update withLines;

        List<Job_Slip__c> slips = new List<Job_Slip__c>();
        for (Integer i = 0; i < SLIP_COUNT; i++) {
            slips.add(new Job_Slip__c(Customer__c = billed.Id, Slip_Date__c = oldDay(), Visit_Reason__c = 'Service ' + i,
                Repair_Lines__c = '[{"customerRequest":"General service","labourEstimate":500}]'));
        }
        insert slips;

        List<Mechanic__c> mechanics = new List<Mechanic__c>();
        for (Integer i = 0; i < MECHANIC_COUNT; i++) {
            mechanics.add(new Mechanic__c(Name = 'Mechanic ' + i, Is_Active__c = true));
        }
        insert mechanics;
        List<Mechanic_Month__c> months = new List<Mechanic_Month__c>();
        for (Mechanic__c m : mechanics) {
            for (Integer back = 30; back >= 0; back--) {
                Date month = Date.today().toStartOfMonth().addMonths(-back);
                months.add(new Mechanic_Month__c(Mechanic__c = m.Id, Month__c = month, Unique_Key__c = MechanicPay.keyFor(m.Id, month),
                    Days__c = 'P'.repeat(MechanicPay.daysIn(month)), Closing_Balance__c = 100 * back));
            }
        }
        insert months;
    }

    @isTest
    static void oneNightsRun_archivesEverythingReady_withinTheLimits() {
        CustomerArchive.recentTouchDays = -1;

        Test.startTest();
        System.enqueueJob(new ArchiveJob(true));
        Test.stopTest();

        String result = ArchiveSettings.current().lastResult;
        System.assert(!result.startsWith('Archiving stopped'), result);
        System.assertEquals(0, [SELECT COUNT() FROM Customer__c WHERE Name LIKE 'Dormant %'], result);
        System.assertEquals(0, [SELECT COUNT() FROM Vehicle__c WHERE Name LIKE 'MP09%'], result);
        System.assertEquals(0, [SELECT COUNT() FROM Job_Slip__c], result);
        System.assertEquals(0, [SELECT COUNT() FROM Bill__c], result);
        System.assertEquals(MECHANIC_COUNT * 25, [SELECT COUNT() FROM Mechanic_Month__c], 'The last 25 months stay: ' + result);
        System.assertEquals(CUSTOMER_COUNT, CustomerArchive.entries().size());
        System.assertEquals(BILL_COUNT, ArchiveStore.index().size());
        // The archive screen still works out its status with all of that in Files.
        ArchiveController.Status s = ArchiveController.getStatus();
        System.assertEquals(SLIP_COUNT, s.archivedSlips);
        System.assertEquals(MECHANIC_COUNT * 6, s.archivedMonths);
        for (Mechanic__c m : [SELECT Archived_To__c, Archived_Balance__c FROM Mechanic__c]) {
            System.assertEquals(Date.today().toStartOfMonth().addMonths(-25), m.Archived_To__c);
            System.assertEquals(2500, m.Archived_Balance__c);
        }
    }
}
