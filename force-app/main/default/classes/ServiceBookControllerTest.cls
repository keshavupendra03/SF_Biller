@isTest
private class ServiceBookControllerTest {

    private static final Date DAY_1 = Date.newInstance(2026, 11, 1);
    private static final Date DAY_5 = Date.newInstance(2026, 11, 5);

    private static Vehicle__c insertCar() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customer.Id, Make__c = 'Maruti', Model__c = 'Swift');
        insert vehicle;
        return vehicle;
    }

    private static ServiceBookController.SaveRequest work(Id vehicleId, Date entryDate, String text) {
        ServiceBookController.SaveRequest request = new ServiceBookController.SaveRequest();
        request.vehicleId = vehicleId;
        request.entryDate = entryDate;
        request.workDone = text;
        return request;
    }

    @isTest
    static void writingWork_putsTheCarOnThatDay_withItsDetails() {
        Vehicle__c car = insertCar();

        Test.startTest();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Oil changed\nAir filter cleaned'));
        List<ServiceBookController.ServiceCard> cards = ServiceBookController.getDay(DAY_1);
        Test.stopTest();

        System.assertEquals(1, cards.size());
        System.assertEquals('Ramesh Kumar', cards[0].customerName);
        System.assertEquals('9000011111', cards[0].phone);
        System.assertEquals('Maruti Swift', cards[0].carModel);
        System.assertEquals('MP09AB1234', cards[0].registrationNumber);
        System.assertEquals('Oil changed\nAir filter cleaned', cards[0].workDone);
        System.assertEquals(0, ServiceBookController.getDay(DAY_5).size());
    }

    @isTest
    static void workingOnTheCarAgain_showsOnBothDays_andEachShowsTheOther() {
        Vehicle__c car = insertCar();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Oil changed'));

        Test.startTest();
        ServiceBookController.saveWork(work(car.Id, DAY_5, 'Brake pads replaced'));
        ServiceBookController.ServiceCard first = ServiceBookController.getDay(DAY_1)[0];
        ServiceBookController.ServiceCard later = ServiceBookController.getDay(DAY_5)[0];
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Service_Entry__c]);
        System.assertEquals('Oil changed', first.workDone);
        System.assertEquals('Brake pads replaced', first.visitDays[0].workDone, 'Day 5 carried on the same visit.');
        System.assertEquals(DAY_5, first.visitDays[0].entryDate);
        System.assertEquals('Brake pads replaced', later.workDone);
        System.assertEquals('Oil changed', later.visitDays[0].workDone);
        System.assertEquals(DAY_1, later.visitStart);
    }

    @isTest
    static void savingAgainOnTheSameDay_updatesTheOneEntry() {
        Vehicle__c car = insertCar();

        Test.startTest();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Oil'));
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Oil changed\nWashed'));
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Service_Entry__c]);
        System.assertEquals('Oil changed\nWashed', [SELECT Work_Done__c FROM Service_Entry__c].Work_Done__c);
    }

    @isTest
    static void clearingTheText_removesTheEntry_andOnlyThatDays() {
        Vehicle__c car = insertCar();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Oil changed'));
        ServiceBookController.saveWork(work(car.Id, DAY_5, 'Washed'));

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveWork(work(car.Id, DAY_5, '   \n '));
        Test.stopTest();

        System.assertEquals(null, card.workDone);
        System.assertEquals(0, ServiceBookController.getDay(DAY_5).size());
        System.assertEquals(1, ServiceBookController.getDay(DAY_1).size());
    }

    @isTest
    static void nothingWrittenOnANewCard_createsNothing() {
        ServiceBookController.SaveRequest request = work(null, DAY_1, '');
        request.customerName = 'Suresh';
        request.registrationNumber = 'MP09ZZ0001';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveWork(request);
        Test.stopTest();

        System.assertEquals(null, card);
        System.assertEquals(0, [SELECT COUNT() FROM Customer__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Vehicle__c]);
    }

    @isTest
    static void newCard_createsCustomerAndCar_andRemembersMakeAndModel() {
        ServiceBookController.SaveRequest request = work(null, DAY_1, 'Oil changed');
        request.customerName = 'Suresh Patel';
        request.phone = '9826011111';
        request.make = 'Tata';
        request.model = 'Punch';
        request.registrationNumber = 'MP09ZZ0001';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveWork(request);
        Test.stopTest();

        System.assertEquals('Suresh Patel', card.customerName);
        System.assertEquals('9826011111', card.phone);
        System.assertEquals('Tata Punch', card.carModel);
        System.assertEquals('MP09ZZ0001', card.registrationNumber);
        System.assertEquals(1, [SELECT COUNT() FROM Vehicle_Make_Model__c WHERE Make__c = 'Tata' AND Model__c = 'Punch']);
    }

    @isTest
    static void newCard_withAKnownPhoneAndCarNumber_reusesThem() {
        Vehicle__c car = insertCar();
        ServiceBookController.SaveRequest request = work(null, DAY_1, 'Washed');
        request.customerName = 'Typed Differently';
        request.phone = '+91 90000 11111';
        request.registrationNumber = 'mp09ab1234';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveWork(request);
        Test.stopTest();

        System.assertEquals(car.Id, card.vehicleId);
        System.assertEquals(1, [SELECT COUNT() FROM Customer__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Vehicle__c]);
    }

    @isTest
    static void newCard_withNoPhone_hidesThePlaceholder_andReusesTheNameNextTime() {
        ServiceBookController.SaveRequest first = work(null, DAY_1, 'Washed');
        first.customerName = 'Ramesh';
        first.registrationNumber = 'MP09ZZ0001';
        ServiceBookController.SaveRequest second = work(null, DAY_1, 'Polished');
        second.customerName = 'Ramesh';
        second.registrationNumber = 'MP09ZZ0002';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveWork(first);
        ServiceBookController.saveWork(second);
        Test.stopTest();

        System.assertEquals(null, card.phone);
        System.assertEquals('Ramesh', card.customerName);
        System.assertEquals(1, [SELECT COUNT() FROM Customer__c WHERE Name = 'Ramesh']);
        System.assertEquals(2, [SELECT COUNT() FROM Vehicle__c]);
    }

    @isTest
    static void newCard_needsOnlyTheCarNumber_andHasNoCustomerUntilOneIsAdded() {
        ServiceBookController.SaveRequest request = work(null, DAY_1, 'Washed');
        request.registrationNumber = 'mp 09 zz-0001';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveWork(request);
        ServiceBookController.ServiceCard onThePage = ServiceBookController.getDay(DAY_1)[0];
        Test.stopTest();

        System.assertEquals('MP09ZZ0001', card.registrationNumber);
        System.assertEquals(null, card.customerId, 'No customer details means nothing to bill.');
        System.assertEquals(null, card.customerName);
        System.assertEquals(null, card.phone);
        System.assertEquals('Washed', onThePage.workDone);
        System.assertEquals(null, onThePage.customerName);
    }

    @isTest
    static void newCard_withoutACarNumber_isRefused() {
        ServiceBookController.SaveRequest request = work(null, DAY_1, 'Washed');
        request.customerName = 'Ramesh';

        String message;
        try {
            ServiceBookController.saveWork(request);
        } catch (ServiceBookController.ServiceBookControllerException e) {
            message = e.getMessage();
        }
        System.assertEquals('Type the car number.', message);
    }

    @isTest
    static void theSameCarNumberIsAlwaysTheSameCar_whoeverItIsFiledUnder() {
        Vehicle__c car = insertCar();
        ServiceBookController.SaveRequest request = work(null, DAY_1, 'Washed');
        request.registrationNumber = 'MP09AB1234';
        request.customerName = 'Someone Else';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveWork(request);
        Test.stopTest();

        System.assertEquals(car.Id, card.vehicleId);
        System.assertEquals('Ramesh Kumar', card.customerName, 'Details a car already has are not replaced from here.');
        System.assertEquals(1, [SELECT COUNT() FROM Vehicle__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Customer__c WHERE Name = 'Someone Else']);
    }

    private static Id carWithNoCustomer() {
        ServiceBookController.SaveRequest request = work(null, DAY_1, 'Washed');
        request.registrationNumber = 'MP09ZZ0001';
        return ServiceBookController.saveWork(request).vehicleId;
    }

    private static ServiceBookController.SaveRequest details(Id vehicleId) {
        ServiceBookController.SaveRequest request = new ServiceBookController.SaveRequest();
        request.vehicleId = vehicleId;
        request.entryDate = DAY_1;
        return request;
    }

    @isTest
    static void addingANameLater_givesTheCarACustomer_andKeepsItsWork() {
        Id vehicleId = carWithNoCustomer();
        ServiceBookController.SaveRequest request = details(vehicleId);
        request.customerName = 'Suresh Patel';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveCardDetails(request);
        Test.stopTest();

        System.assertNotEquals(null, card.customerId);
        System.assertEquals('Suresh Patel', card.customerName);
        System.assertEquals(null, card.phone);
        System.assertEquals('Washed', card.workDone);
        System.assertEquals(vehicleId, card.vehicleId);
    }

    @isTest
    static void addingANumberLater_withNoName_stillGivesACustomer() {
        Id vehicleId = carWithNoCustomer();
        ServiceBookController.SaveRequest request = details(vehicleId);
        request.phone = '9826011111';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveCardDetails(request);
        Test.stopTest();

        System.assertNotEquals(null, card.customerId);
        System.assertEquals('9826011111', card.customerName);
        System.assertEquals('9826011111', card.phone);
    }

    @isTest
    static void addingAKnownNumberLater_linksToThatCustomer() {
        Vehicle__c other = insertCar();
        Id vehicleId = carWithNoCustomer();
        ServiceBookController.SaveRequest request = details(vehicleId);
        request.customerName = 'Typed Differently';
        request.phone = '9000011111';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveCardDetails(request);
        Test.stopTest();

        System.assertEquals('Ramesh Kumar', card.customerName);
        System.assertEquals([SELECT Customer__c FROM Vehicle__c WHERE Id = :other.Id].Customer__c, card.customerId);
    }

    @isTest
    static void pickingACustomerLater_links_andCarNumberFoundLaterKeepsTheLink() {
        Vehicle__c other = insertCar();
        Id customerId = [SELECT Customer__c FROM Vehicle__c WHERE Id = :other.Id].Customer__c;
        Id vehicleId = carWithNoCustomer();
        ServiceBookController.SaveRequest request = details(vehicleId);
        request.customerId = customerId;

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveCardDetails(request);
        Test.stopTest();

        System.assertEquals(customerId, card.customerId);
    }

    @isTest
    static void addingANumberToACustomerWhoHadOnlyAName_updatesThem() {
        Id vehicleId = carWithNoCustomer();
        ServiceBookController.SaveRequest named = details(vehicleId);
        named.customerName = 'Suresh Patel';
        ServiceBookController.saveCardDetails(named);

        ServiceBookController.SaveRequest numbered = details(vehicleId);
        numbered.phone = '9826011111';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveCardDetails(numbered);
        Test.stopTest();

        System.assertEquals('Suresh Patel', card.customerName);
        System.assertEquals('9826011111', card.phone);
    }

    @isTest
    static void addingAModelLater_fillsItOnce_andDoesNotReplaceOne() {
        Id vehicleId = carWithNoCustomer();
        ServiceBookController.SaveRequest first = details(vehicleId);
        first.make = 'Tata';
        first.model = 'Punch';
        ServiceBookController.saveCardDetails(first);

        ServiceBookController.SaveRequest second = details(vehicleId);
        second.model = 'Nexon';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveCardDetails(second);
        Test.stopTest();

        System.assertEquals('Tata Punch', card.carModel);
    }

    @isTest
    static void aCarWithACustomerAlready_keepsThem() {
        Vehicle__c car = insertCar();
        ServiceBookController.SaveRequest request = details(car.Id);
        request.customerName = 'Someone Else';

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveCardDetails(request);
        Test.stopTest();

        System.assertEquals('Ramesh Kumar', card.customerName);
    }

    @isTest
    static void saveCardDetails_needsACar() {
        Boolean threw = false;
        try {
            ServiceBookController.saveCardDetails(details(null));
        } catch (ServiceBookController.ServiceBookControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void search_findsACarWithNoCustomer_andNotTheWalkInRecordItself() {
        carWithNoCustomer();
        insert new Vehicle__c(Name = 'MP09ZZ0002', Customer__c = QuickBillController.walkInCustomerId());

        Test.startTest();
        List<ServiceBookController.ServiceCard> byNumber = ServiceBookController.search('ZZ0001', DAY_1);
        List<ServiceBookController.ServiceCard> emptyWalkIn = ServiceBookController.search('Walk-in', DAY_1);
        Test.stopTest();

        System.assertEquals(1, byNumber.size());
        System.assertEquals(null, byNumber[0].customerName);
        for (ServiceBookController.ServiceCard card : emptyWalkIn) {
            System.assertNotEquals(null, card.vehicleId, 'The shared record is not a customer to pick.');
        }
    }

    @isTest
    static void search_findsACarByAnyDetail_withItsHistory() {
        Vehicle__c car = insertCar();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Oil changed'));

        Test.startTest();
        for (String term : new List<String>{ 'MP09AB', 'swift', 'maruti', 'ramesh', '90000', 'ramesh swift', 'MP 09 AB 1234' }) {
            List<ServiceBookController.ServiceCard> found = ServiceBookController.search(term, DAY_5);
            System.assertEquals(1, found.size(), term);
            System.assertEquals(car.Id, found[0].vehicleId, term);
            System.assertEquals('Oil changed', found[0].visitDays[0].workDone, term);
        }
        Test.stopTest();
    }

    @isTest
    static void search_needsEveryWordToMatch_andIgnoresTooShortTerms() {
        insertCar();

        Test.startTest();
        System.assertEquals(0, ServiceBookController.search('ramesh punch', DAY_1).size());
        System.assertEquals(0, ServiceBookController.search('m', DAY_1).size());
        System.assertEquals(0, ServiceBookController.search('', DAY_1).size());
        Test.stopTest();
    }

    @isTest
    static void search_isSafeWithAQuoteInTheTerm() {
        Customer__c customer = new Customer__c(Name = 'O\'Brien', Phone__c = '9000022222');
        insert customer;

        Test.startTest();
        List<ServiceBookController.ServiceCard> found = ServiceBookController.search('O\'Br', DAY_1);
        Test.stopTest();

        System.assertEquals(1, found.size());
    }

    @isTest
    static void search_findsACustomerWithNoCarYet() {
        Customer__c customer = new Customer__c(Name = 'Suresh Patel', Phone__c = '9826011111');
        insert customer;

        Test.startTest();
        List<ServiceBookController.ServiceCard> found = ServiceBookController.search('suresh', DAY_1);
        Test.stopTest();

        System.assertEquals(1, found.size());
        System.assertEquals(null, found[0].vehicleId);
        System.assertEquals(customer.Id, found[0].customerId);
    }

    @isTest
    static void search_includesWhatIsAlreadyWrittenForTheDate() {
        Vehicle__c car = insertCar();
        ServiceBookController.saveWork(work(car.Id, DAY_5, 'Washed'));

        Test.startTest();
        ServiceBookController.ServiceCard found = ServiceBookController.search('swift', DAY_5)[0];
        Test.stopTest();

        System.assertEquals('Washed', found.workDone);
        System.assertEquals(0, found.visitDays.size());
        System.assertEquals(0, found.otherVisits.size());
        System.assertEquals(true, found.hasEntryForDate);
    }

    @isTest
    static void searchCarModels_matchesModelOrMake() {
        insert new Vehicle_Make_Model__c(Name = 'Tata Punch', Make__c = 'Tata', Model__c = 'Punch');

        Test.startTest();
        List<ServiceBookController.CarModelOption> byModel = ServiceBookController.searchCarModels('pun');
        List<ServiceBookController.CarModelOption> byMake = ServiceBookController.searchCarModels('tat');
        Test.stopTest();

        System.assertEquals('Tata', byModel[0].make);
        System.assertEquals('Punch', byMake[0].model);
    }

    // ---- visits over several days ----------------------------------------

    private static final Date DAY_3 = Date.newInstance(2026, 11, 3);
    private static final Date DAY_30 = Date.newInstance(2026, 11, 30);

    private static ServiceBookController.SaveRequest newVisit(Id vehicleId, Date entryDate, String text) {
        ServiceBookController.SaveRequest request = work(vehicleId, entryDate, text);
        request.startNewVisit = true;
        return request;
    }

    @isTest
    static void laterDays_joinTheSameVisit_andEveryDayShowsTheWholeVisit() {
        Vehicle__c car = insertCar();

        Test.startTest();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Denting'));
        ServiceBookController.saveWork(work(car.Id, DAY_3, 'Painting'));
        ServiceBookController.ServiceCard day5 = ServiceBookController.saveWork(work(car.Id, DAY_5, 'Polish'));
        ServiceBookController.ServiceCard day1 = ServiceBookController.getDay(DAY_1)[0];
        Test.stopTest();

        System.assertEquals(DAY_1, day5.visitStart);
        System.assertEquals(2, day5.visitDays.size());
        System.assertEquals('Denting', day5.visitDays[0].workDone, 'Oldest first.');
        System.assertEquals('Painting', day5.visitDays[1].workDone);
        System.assertEquals(0, day5.otherVisits.size());
        System.assertEquals(null, day5.previousVisitStart);
        System.assertEquals(2, day1.visitDays.size(), 'Looking back at day 1 also shows the days after it.');
    }

    @isTest
    static void aNewVisit_keepsEarlierWorkAsAnotherVisit() {
        Vehicle__c car = insertCar();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Oil changed'));
        ServiceBookController.saveWork(work(car.Id, DAY_3, 'Filter'));

        Test.startTest();
        ServiceBookController.ServiceCard later = ServiceBookController.saveWork(newVisit(car.Id, DAY_30, 'Brake pads'));
        Test.stopTest();

        System.assertEquals(DAY_30, later.visitStart);
        System.assertEquals(0, later.visitDays.size());
        System.assertEquals(DAY_1, later.previousVisitStart);
        System.assertEquals(1, later.otherVisits.size());
        System.assertEquals(DAY_1, later.otherVisits[0].startDate);
        System.assertEquals(DAY_3, later.otherVisits[0].endDate);
        System.assertEquals(2, later.otherVisits[0].days.size());
    }

    @isTest
    static void aDayWithNothingWrittenYet_showsTheVisitItWouldJoin() {
        Vehicle__c car = insertCar();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Denting'));

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.getVehicleCard(car.Id, DAY_5);
        Test.stopTest();

        System.assertEquals(false, card.hasEntryForDate);
        System.assertEquals(DAY_1, card.visitStart);
        System.assertEquals('Denting', card.visitDays[0].workDone);
    }

    @isTest
    static void startNewVisit_isIgnoredOnceTheDayIsWritten() {
        Vehicle__c car = insertCar();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Denting'));
        ServiceBookController.saveWork(work(car.Id, DAY_5, 'Painting'));

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.saveWork(newVisit(car.Id, DAY_5, 'Painting and polish'));
        Test.stopTest();

        System.assertEquals(DAY_1, card.visitStart, 'Splitting a visit is changeVisit, not a side effect of typing.');
        System.assertEquals('Painting and polish', card.workDone);
    }

    @isTest
    static void changeVisit_splitsFromThatDayOn_andJoiningPutsItBack() {
        Vehicle__c car = insertCar();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Denting'));
        ServiceBookController.saveWork(work(car.Id, DAY_3, 'Painting'));
        ServiceBookController.saveWork(work(car.Id, DAY_5, 'Polish'));

        Test.startTest();
        ServiceBookController.ServiceCard split = ServiceBookController.changeVisit(car.Id, DAY_3, true);
        ServiceBookController.ServiceCard day5AfterSplit = ServiceBookController.getVehicleCard(car.Id, DAY_5);
        ServiceBookController.ServiceCard joined = ServiceBookController.changeVisit(car.Id, DAY_3, false);
        Test.stopTest();

        System.assertEquals(DAY_3, split.visitStart);
        System.assertEquals(1, split.visitDays.size(), 'Day 5 went with day 3.');
        System.assertEquals(DAY_5, split.visitDays[0].entryDate);
        System.assertEquals(DAY_1, split.previousVisitStart);
        System.assertEquals(DAY_3, day5AfterSplit.visitStart);
        System.assertEquals(DAY_1, joined.visitStart);
        System.assertEquals(2, joined.visitDays.size());
        System.assertEquals(0, joined.otherVisits.size());
    }

    @isTest
    static void changeVisit_onADayWithNothingWritten_changesNothing() {
        Vehicle__c car = insertCar();
        ServiceBookController.saveWork(work(car.Id, DAY_1, 'Denting'));

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.changeVisit(car.Id, DAY_5, true);
        Test.stopTest();

        System.assertEquals(DAY_1, card.visitStart);
        System.assertEquals(1, [SELECT COUNT() FROM Service_Entry__c]);
    }

    @isTest
    static void entriesFromBeforeVisits_countAsAVisitEach() {
        Vehicle__c car = insertCar();
        insert new List<Service_Entry__c>{
            new Service_Entry__c(Vehicle__c = car.Id, Entry_Date__c = DAY_1, Work_Done__c = 'Old one', Unique_Key__c = car.Id + '|1'),
            new Service_Entry__c(Vehicle__c = car.Id, Entry_Date__c = DAY_3, Work_Done__c = 'Old two', Unique_Key__c = car.Id + '|3')
        };

        Test.startTest();
        ServiceBookController.ServiceCard card = ServiceBookController.getVehicleCard(car.Id, DAY_3);
        Test.stopTest();

        System.assertEquals(DAY_3, card.visitStart);
        System.assertEquals(0, card.visitDays.size());
        System.assertEquals(1, card.otherVisits.size());
        System.assertEquals(DAY_1, card.previousVisitStart);
    }
}
