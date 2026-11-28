/**
 * The archive as the workshop's own staff meet it (architecture.md,
 * Forty-ninth): an end user with the WS Biller end user profile, a damaged
 * archive, and a big customer list.
 */
@isTest
private class ArchiveHardeningTest {

    private static Datetime longAgo() {
        return Datetime.now().addMonths(-30);
    }

    private static Date oldDay() {
        return Date.today().toStartOfMonth().addMonths(-25).addDays(4);
    }

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GST_Registration_Type__c = 'Unregistered', State__c = 'Madhya Pradesh');
        Customer__c ramesh = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        Customer__c sita = new Customer__c(Name = 'Sita Verma', Phone__c = '9000022222');
        insert new List<Customer__c>{ ramesh, sita };
        Vehicle__c swift = new Vehicle__c(Name = 'MP09AB1234', Customer__c = ramesh.Id);
        Vehicle__c city = new Vehicle__c(Name = 'MP09CD5678', Customer__c = sita.Id);
        insert new List<Vehicle__c>{ swift, city };
        for (Id recordId : new List<Id>{ ramesh.Id, sita.Id, swift.Id, city.Id }) {
            Test.setCreatedDate(recordId, longAgo());
        }
        insert new Mechanic__c(Name = 'Anil', Is_Active__c = true, Pay_Type__c = 'Monthly', Pay_Amount__c = 15000,
            Weekly_Off__c = 'None', Pay_Start__c = Date.today().toStartOfMonth().addMonths(-30));
    }

    private static ArchiveSettings.Rules rules() {
        return ArchiveSettings.current();
    }

    // Everything archivable here, archived (as the nightly run would, as the admin).
    private static void archiveEverything() {
        CustomerArchive.recentTouchDays = -1;
        Id sita = [SELECT Id FROM Customer__c WHERE Name = 'Sita Verma'].Id;
        // A bill and a job slip of Sita's, two years old.
        Bill__c b = new Bill__c(Customer__c = sita, Bill_Date__c = oldDay());
        insert b;
        TestLines.attach(b.Id, new List<BillController.LineItemInput>{ TestLines.line('Service', 1, 800, 0, 'CGST_SGST', '998714', null) });
        insert new Job_Slip__c(Customer__c = sita, Slip_Date__c = oldDay(), Visit_Reason__c = 'Noise');
        Mechanic__c anil = MechanicPay.mechanic([SELECT Id FROM Mechanic__c].Id);
        MechanicPay.mark(anil, Date.today(), 'P');

        BillArchive.archiveNextMonth(rules());
        WorkArchive.archiveReady(rules());
        AttendanceArchive.archiveReady(rules());
        CustomerArchive.archiveReady(rules());
    }

    private static User endUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Ws biller enduser profile'];
        String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User u = new User(
            LastName = 'Counter', Alias = 'cntr', Email = 'counter' + unique + '@example.com',
            Username = 'counter' + unique + '@wsbiller.test', ProfileId = p.Id,
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_IN', TimeZoneSidKey = 'Asia/Kolkata'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert new PermissionSetAssignment(AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'WS_Biller_Full_Access'].Id);
        }
        return u;
    }

    @isTest
    static void staffWithTheEndUserProfile_canFindViewPrintAndBringBackEverything() {
        archiveEverything();
        System.assertEquals(0, [SELECT COUNT() FROM Customer__c WHERE Name IN ('Ramesh Kumar', 'Sita Verma')], 'Both archived');
        User staff = endUser();

        Test.startTest();
        System.runAs(staff) {
            // Old bills in Billing: found, opened.
            List<ArchiveController.ArchivedBillRow> bills = ArchiveController.searchBills('sita');
            System.assertEquals(1, bills.size(), 'Staff see archive files linked to the company.');
            ArchiveController.ArchivedBill shown = ArchiveController.getArchivedBill(bills[0].documentId, bills[0].billId);
            System.assertEquals(800, shown.totalAmount);

            // Service Book: an archived car shows up, and opening it brings it back.
            List<ServiceBookController.ServiceCard> cards = ServiceBookController.search('MP09AB1234', Date.today());
            System.assertEquals(1, cards.size());
            System.assertNotEquals(null, cards[0].archivedId);
            ServiceBookController.ServiceCard back = ServiceBookController.bringBack(cards[0].archivedId, cards[0].archivedVehicleId, Date.today());
            System.assertNotEquals(null, back.vehicleId);

            // Quick Bill: typing Sita's number brings her back.
            QuickBillController.CustomerMatch sita = QuickBillController.findCustomerByPhone('9000022222');
            System.assertNotEquals(null, sita);
            System.assertEquals(1, sita.vehicles.size());

            // Her customer page lists the archived slip, and it prints.
            List<ArchiveController.ArchivedWorkRow> work = ArchiveController.customerHistory(sita.id);
            System.assertEquals(1, work.size(), 'Found under her new Id too.');
            System.assertNotEquals(null, DocumentPdfService.getArchivedPdfDownload(work[0].recordId, work[0].documentId));

            // Bringing her archived bill back links it to her as she is now.
            Id billBack = ArchiveController.restoreBill(bills[0].billId);
            System.assertEquals(sita.id, [SELECT Customer__c FROM Bill__c WHERE Id = :billBack].Customer__c);

            // Attendance: an archived month shows, read-only.
            Id anil = [SELECT Id FROM Mechanic__c].Id;
            AttendanceController.MechanicMonth old = AttendanceController.getMonth(anil, Date.today().toStartOfMonth().addMonths(-29));
            System.assertEquals(true, old.isArchived);

            // GST return for the archived month.
            System.assertNotEquals(null, GstReturnService.build(null, oldDay().toStartOfMonth(), GstFilingLock.monthEnd(oldDay())));
        }
        Test.stopTest();

        // What staff brought back is known to the admin's nightly run too.
        Map<String, String> moved = ArchiveStore.moved();
        System.assertEquals(4, moved.size(), 'Both customers and both cars, written by staff, read by the admin.');
        System.assertEquals(0, CustomerArchive.entries().size());
        System.assertEquals(0, ArchiveStore.index().size(), 'The bill brought back is out of the index.');
    }

    @isTest
    static void aDamagedArchive_neverStopsBillingOrTheServiceBook() {
        archiveEverything();
        // The customers file goes missing (deleted by hand, say).
        List<ArchiveStore.ArchiveFile> customerFiles = ArchiveStore.filesOfKind(ArchiveStore.KIND_CUSTOMERS);
        delete [SELECT Id FROM ContentDocument WHERE Id = :customerFiles[0].documentId];

        Test.startTest();
        QuickBillController.CustomerMatch match = QuickBillController.findCustomerByPhone('9000011111');
        List<ServiceBookController.ServiceCard> cards = ServiceBookController.search('ramesh', Date.today());
        QuickBillController.QuickBillRequest r = new QuickBillController.QuickBillRequest();
        r.customerPhone = '9000011111';
        r.customerName = 'Ramesh Kumar';
        r.documentDate = Date.today();
        r.lineItems = new List<BillController.LineItemInput>{ TestLines.line('Service', 1, 500, 0, 'CGST_SGST', '998714', null) };
        BillController.BillSummary bill = QuickBillController.createQuickBill(r);
        Test.stopTest();

        System.assertEquals(null, match, 'Not found, but no error.');
        System.assertEquals(1, cards.size(), 'Still listed from the index; opening it would say what is wrong.');
        System.assertNotEquals(null, bill.billId, 'The bill is made, for a new customer record.');
        System.assertEquals(1, [SELECT COUNT() FROM Customer__c WHERE Phone__c = '9000011111']);
        System.assertEquals(0, [SELECT COUNT() FROM Vehicle__c WHERE Name = 'MP09AB1234'], 'Nothing half brought back.');
    }

    @isTest
    static void dormantCustomers_areFound_behindAPageOfActiveOnes() {
        CustomerArchive.recentTouchDays = -1;
        CustomerArchive.pageSize = 1;
        // The oldest (Ramesh) has an open estimate; Sita, next, is dormant.
        Id ramesh = [SELECT Id FROM Customer__c WHERE Name = 'Ramesh Kumar'].Id;
        insert new Estimate__c(Customer__c = ramesh, Estimate_Date__c = Date.today());

        Test.startTest();
        CustomerArchive.Outcome outcome = CustomerArchive.archiveReady(rules());
        Test.stopTest();

        System.assertEquals(1, outcome.customers);
        System.assertNotEquals(null, [SELECT Id FROM Customer__c WHERE Name = 'Ramesh Kumar'].Id);
        System.assertEquals(0, [SELECT COUNT() FROM Customer__c WHERE Name = 'Sita Verma']);
    }
}
