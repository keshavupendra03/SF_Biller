@isTest
private class CustomerArchiveTest {

    // Well past the default 24 months.
    private static Datetime longAgo() {
        return Datetime.now().addMonths(-30);
    }

    private static Date longAgoDay() {
        return longAgo().date();
    }

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors', GST_Registration_Type__c = 'Unregistered', State__c = 'Madhya Pradesh');
        Customer__c ramesh = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111', Address__c = 'Indore', Archived_Spend__c = 500);
        Customer__c sita = new Customer__c(Name = 'Sita Verma', Phone__c = '9000022222');
        insert new List<Customer__c>{ ramesh, sita };
        Vehicle__c swift = new Vehicle__c(Name = 'MP09AB1234', Customer__c = ramesh.Id, Make__c = 'Maruti', Model__c = 'Swift');
        Vehicle__c city = new Vehicle__c(Name = 'MP09CD5678', Customer__c = sita.Id);
        insert new List<Vehicle__c>{ swift, city };
        // Ramesh's Swift was last serviced long ago.
        ServiceBookController.Entry day = new ServiceBookController.Entry();
        day.entryDate = longAgoDay();
        day.visitStart = longAgoDay();
        day.workDone = 'Oil change';
        ServiceBookController.writeBook(swift, new List<ServiceBookController.Entry>{ day });
        for (Id recordId : new List<Id>{ ramesh.Id, sita.Id, swift.Id, city.Id }) {
            Test.setCreatedDate(recordId, longAgo());
        }
    }

    private static ArchiveSettings.Rules rules() {
        return ArchiveSettings.current();
    }

    private static Id customerNamed(String name) {
        List<Customer__c> found = [SELECT Id FROM Customer__c WHERE Name = :name];
        return found.isEmpty() ? null : found[0].Id;
    }

    // Records made in a test were all changed just now.
    private static void ignoreRecentChanges() {
        CustomerArchive.recentTouchDays = -1;
    }

    @isTest
    static void dormantCustomers_goWithTheirCarsAndBook_andLeaveSalesforce() {
        ignoreRecentChanges();
        Id ramesh = customerNamed('Ramesh Kumar');

        Test.startTest();
        CustomerArchive.Plan plan = CustomerArchive.plan(rules());
        CustomerArchive.Outcome outcome = CustomerArchive.archiveReady(rules());
        Test.stopTest();

        System.assertEquals(2, plan.customers);
        System.assertEquals(2, outcome.customers);
        System.assertEquals(0, [SELECT COUNT() FROM Customer__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Vehicle__c]);
        System.assertEquals(1, ArchiveStore.filesOfKind(ArchiveStore.KIND_CUSTOMERS).size());
        List<ArchiveStore.IndexEntry> entries = CustomerArchive.entries();
        System.assertEquals(2, entries.size());
        ArchiveStore.IndexEntry found = CustomerArchive.findByCar('mp 09 ab 1234');
        System.assertEquals(String.valueOf(ramesh), found.id);
        System.assertEquals('Ramesh Kumar', found.c);
        System.assertEquals(false, CustomerArchive.isDue(), 'The nightly run waits 28 days before archiving customers again.');
    }

    @isTest
    static void aCustomerWithADocumentInSalesforce_orChangedRecently_stays() {
        ignoreRecentChanges();
        Id sita = customerNamed('Sita Verma');
        insert new Estimate__c(Customer__c = sita, Estimate_Date__c = Date.today());

        Test.startTest();
        CustomerArchive.archiveReady(rules());
        Test.stopTest();

        System.assertNotEquals(null, customerNamed('Sita Verma'), 'Her estimate keeps her.');
        System.assertEquals(null, customerNamed('Ramesh Kumar'));

        CustomerArchive.recentTouchDays = 30;
        System.assertEquals(0, CustomerArchive.plan(rules()).customers, 'Everything here was changed today.');
    }

    @isTest
    static void aCarSeenRecently_keepsItsCustomer() {
        ignoreRecentChanges();
        Vehicle__c swift = [SELECT Id, Service_Book__c FROM Vehicle__c WHERE Name = 'MP09AB1234'];
        List<ServiceBookController.Entry> days = ServiceBookController.readBook(swift);
        ServiceBookController.Entry today = new ServiceBookController.Entry();
        today.entryDate = Date.today();
        today.visitStart = Date.today();
        today.workDone = 'Brakes';
        days.add(today);
        ServiceBookController.writeBook(swift, days);

        Test.startTest();
        CustomerArchive.archiveReady(rules());
        Test.stopTest();

        System.assertNotEquals(null, customerNamed('Ramesh Kumar'));
        System.assertEquals(null, customerNamed('Sita Verma'));
    }

    @isTest
    static void walkInCars_goOnTheirOwn_andWalkInStays() {
        ignoreRecentChanges();
        Id walkIn = QuickBillController.walkInCustomerId();
        Vehicle__c loose = new Vehicle__c(Name = 'MP04ZZ0001', Customer__c = walkIn);
        insert loose;
        Test.setCreatedDate(loose.Id, longAgo());
        Test.setCreatedDate(walkIn, longAgo());

        Test.startTest();
        CustomerArchive.Outcome outcome = CustomerArchive.archiveReady(rules());
        Test.stopTest();

        System.assertEquals(1, outcome.cars);
        System.assertEquals(walkIn, QuickBillController.walkInCustomerIdIfExists(), 'The Walk-in Customer is never archived.');
        System.assertEquals(0, [SELECT COUNT() FROM Vehicle__c WHERE Name = 'MP04ZZ0001']);

        // Typing its number on a new Service Book card brings it back, under Walk-in.
        ServiceBookController.SaveRequest r = new ServiceBookController.SaveRequest();
        r.registrationNumber = 'MP04 ZZ 0001';
        r.entryDate = Date.today();
        r.workDone = 'Wash';
        ServiceBookController.saveWork(r);
        Vehicle__c back = [SELECT Customer__c FROM Vehicle__c WHERE Name = 'MP04ZZ0001'];
        System.assertEquals(walkIn, back.Customer__c);
        System.assertEquals(1, [SELECT COUNT() FROM Vehicle__c WHERE Name = 'MP04ZZ0001'], 'Brought back, not made again.');
    }

    @isTest
    static void typingTheirPhone_bringsTheCustomerBack_withCarsAndBook() {
        ignoreRecentChanges();
        CustomerArchive.archiveReady(rules());

        Test.startTest();
        QuickBillController.CustomerMatch match = QuickBillController.findCustomerByPhone('+91 90000 11111');
        Test.stopTest();

        System.assertNotEquals(null, match, 'An archived customer is found by phone.');
        Customer__c back = [SELECT Name, Address__c, Archived_Spend__c FROM Customer__c WHERE Id = :match.id];
        System.assertEquals('Indore', back.Address__c);
        System.assertEquals(500, back.Archived_Spend__c, 'What they paid on archived bills still counts.');
        Vehicle__c swift = [SELECT Customer__c, Model__c, Service_Book__c, Last_Service_Date__c FROM Vehicle__c WHERE Name = 'MP09AB1234'];
        System.assertEquals(match.id, swift.Customer__c);
        System.assertEquals('Swift', swift.Model__c);
        System.assertEquals('Oil change', ServiceBookController.readBook(swift)[0].workDone);
        System.assertEquals(longAgoDay(), swift.Last_Service_Date__c);
        System.assertEquals(1, CustomerArchive.entries().size(), 'Only Sita is still archived.');
        System.assertEquals(null, CustomerArchive.findByPhone('9000011111'));
        System.assertEquals(null, CustomerArchive.findByPhone('90000'), 'Part of a number never matches.');
    }

    @isTest
    static void bringingBack_foldsIntoALiveCustomerAndCar_withTheSameNumbers() {
        ignoreRecentChanges();
        CustomerArchive.archiveReady(rules());
        Customer__c newRamesh = new Customer__c(Name = 'Ramesh K', Phone__c = '9000011111', Archived_Spend__c = 100);
        insert newRamesh;
        Vehicle__c swiftAgain = new Vehicle__c(Name = 'MP09AB1234', Customer__c = newRamesh.Id);
        insert swiftAgain;

        Test.startTest();
        CustomerArchive.Restored r = CustomerArchive.restore(CustomerArchive.findByCar('MP09AB1234').id);
        Test.stopTest();

        System.assertEquals(newRamesh.Id, r.customerId);
        System.assertEquals(1, [SELECT COUNT() FROM Customer__c WHERE Phone__c = '9000011111']);
        System.assertEquals(600, [SELECT Archived_Spend__c FROM Customer__c WHERE Id = :newRamesh.Id].Archived_Spend__c);
        Vehicle__c swift = [SELECT Model__c, Service_Book__c FROM Vehicle__c WHERE Id = :swiftAgain.Id];
        System.assertEquals(1, [SELECT COUNT() FROM Vehicle__c WHERE Name = 'MP09AB1234']);
        System.assertEquals('Swift', swift.Model__c, 'Gaps are filled from the archive.');
        System.assertEquals(1, ServiceBookController.readBook(swift).size(), 'The archived day is added.');
    }

    @isTest
    static void serviceBookSearch_showsArchivedCars_andOpeningOneBringsItBack() {
        ignoreRecentChanges();
        CustomerArchive.archiveReady(rules());

        Test.startTest();
        List<ServiceBookController.ServiceCard> cards = ServiceBookController.search('ramesh', Date.today());
        ServiceBookController.ServiceCard card = ServiceBookController.bringBack(cards[0].archivedId, cards[0].archivedVehicleId, Date.today());
        Test.stopTest();

        System.assertEquals(1, cards.size());
        System.assertEquals(null, cards[0].vehicleId);
        System.assertEquals('MP09AB1234', cards[0].registrationNumber);
        System.assertNotEquals(null, card.vehicleId);
        System.assertEquals('Ramesh Kumar', card.customerName);
        System.assert(card.otherVisits.size() + card.visitDays.size() >= 1, 'Its Service Book came back.');
        System.assertEquals(null, ServiceBookController.search('ramesh', Date.today())[0].archivedId, 'Found live now.');
    }

    @isTest
    static void anArchivedBill_bringsItsArchivedCustomerBackFirst() {
        ignoreRecentChanges();
        Id ramesh = customerNamed('Ramesh Kumar');
        Id swift = [SELECT Id FROM Vehicle__c WHERE Name = 'MP09AB1234'].Id;
        BillController.CreateBillRequest req = new BillController.CreateBillRequest();
        req.customerId = ramesh;
        req.vehicleId = swift;
        req.billDate = longAgoDay();
        req.lineItems = new List<BillController.LineItemInput>{ TestLines.line('Service', 1, 1000, 0, 'CGST_SGST', '998714', null) };
        BillController.BillSummary bill = BillController.createBill(req);
        BillPayments.add(bill.billId, 1000, 'Cash');
        BillArchive.archiveNextMonth(rules());
        System.assertEquals(0, [SELECT COUNT() FROM Bill__c]);

        Test.startTest();
        CustomerArchive.archiveReady(rules());
        System.assertEquals(null, customerNamed('Ramesh Kumar'), 'With the bill archived, nothing keeps him.');
        Id billBack = BillArchive.restore(bill.billId);
        Test.stopTest();

        Bill__c back = [SELECT Customer__c, Customer__r.Name, Vehicle__r.Name FROM Bill__c WHERE Id = :billBack];
        System.assertEquals('Ramesh Kumar', back.Customer__r.Name);
        System.assertEquals('MP09AB1234', back.Vehicle__r.Name);
        System.assertEquals(500, [SELECT Archived_Spend__c FROM Customer__c WHERE Id = :back.Customer__c].Archived_Spend__c,
            'The bill counts again in Salesforce, so it leaves the archived spend.');
    }

    @isTest
    static void anArchivedBillsDate_countsAsTheCustomerBeingSeen() {
        ignoreRecentChanges();
        Id sita = customerNamed('Sita Verma');
        BillController.CreateBillRequest req = new BillController.CreateBillRequest();
        req.customerId = sita;
        req.billDate = Date.today().addMonths(-4);
        req.lineItems = new List<BillController.LineItemInput>{ TestLines.line('Service', 1, 300, 0, 'CGST_SGST', '998714', null) };
        BillController.createBill(req);
        ArchiveSettings.Rules r = rules();
        r.billsAfterMonths = 3;
        BillArchive.archiveNextMonth(r);
        System.assertEquals(0, [SELECT COUNT() FROM Bill__c]);

        Test.startTest();
        CustomerArchive.archiveReady(rules());
        Test.stopTest();

        System.assertNotEquals(null, customerNamed('Sita Verma'), 'Billed four months ago, so not dormant.');
    }

    @isTest
    static void theArchiveScreen_andCustomersList() {
        ignoreRecentChanges();
        ArchiveController.Status before = ArchiveController.getStatus();
        CustomerArchive.archiveReady(rules());

        Test.startTest();
        ArchiveController.Status after = ArchiveController.getStatus();
        List<ArchiveController.ArchivedCustomerRow> rows = ArchiveController.searchCustomers('sita');
        Id back = ArchiveController.restoreCustomer(rows[0].archivedId);
        Test.stopTest();

        System.assertEquals(2, before.customersReady);
        System.assertEquals(2, after.archivedCustomers);
        System.assertEquals(0, after.archivedBills);
        System.assertEquals(false, after.customersDue);
        System.assertEquals(1, rows.size());
        System.assertEquals('MP09CD5678', rows[0].vehicles);
        System.assertEquals('Sita Verma', [SELECT Name FROM Customer__c WHERE Id = :back].Name);
        try {
            ArchiveController.restoreCustomer(rows[0].archivedId);
            System.assert(false, 'Brought back twice');
        } catch (ArchiveController.ArchiveControllerException e) {
            System.assert(e.getMessage().contains('already brought back'), e.getMessage());
        }
    }

    @isTest
    static void theJob_byHand_archivesCustomers_andSaysSo() {
        ignoreRecentChanges();
        Test.startTest();
        System.enqueueJob(new ArchiveJob(true));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Customer__c]);
        System.assert(ArchiveSettings.current().lastResult.contains('archived 2 dormant customers'), ArchiveSettings.current().lastResult);
    }

    @isTest
    static void archiveFiles_areLinkedToTheCompany_soEveryoneCanReadThem() {
        ignoreRecentChanges();
        CustomerArchive.archiveReady(rules());
        Id company = [SELECT Id FROM Workshop_Profile__c LIMIT 1].Id;
        Set<Id> documents = new Set<Id>();
        for (ArchiveStore.ArchiveFile f : ArchiveStore.files()) {
            documents.add(f.documentId);
        }
        System.assertEquals(2, documents.size());
        System.assertEquals(2, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :company AND ContentDocumentId IN :documents]);
    }
}
