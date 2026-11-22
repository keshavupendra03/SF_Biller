/**
 * The Service Book screen: the workshop's daily notebook. Each page is a date,
 * and each card on it is one car and what was done to it that day. Working on a
 * car again another day makes a new entry for that day, so the car appears on
 * both days and either card can show its other visits.
 *
 * A visit can run over several days (work done today and more in two days), so
 * each day's entry records the first day of its visit in Visit_Start__c. A later
 * day joins the car's latest visit unless staff start a new one, and a card shows
 * every day of its visit at once, which is what they need in front of them when
 * billing. Older visits sit behind a "Show other visits" link.
 *
 * A car's days are stored on the car itself (Vehicle__c.Service_Book__c, JSON,
 * oldest first), not as one record per day, to save data storage
 * (architecture.md, Forty-second). First_Service_Date__c and
 * Last_Service_Date__c bracket them, so a page of the book only reads cars that
 * can have a day on it. One entry per car per day: writing locks the car's row
 * first, so two people writing about the same car on the same day share one
 * entry. An entry only exists once something is written, and clearing the text
 * removes it again, so looking a car up never leaves an empty card in the book.
 *
 * The car number is all this screen needs. Vehicle__c.Customer__c is required
 * though, so a car with no customer details yet sits under the shared Walk-in
 * Customer and is shown as having no customer. Details added later move it to a
 * real customer, which is what makes billing possible.
 */
public with sharing class ServiceBookController {

    public class ServiceBookControllerException extends Exception {}

    private static final Integer MAX_SEARCH_WORDS = 5;

    // One day of a car's book, as stored.
    public class Entry {
        public Date entryDate;
        // The first day of its visit. Blank for days written before visits
        // existed: each was its own visit.
        public Date visitStart;
        public String workDone;
        // When the day was first written: a page shows the newest first.
        public Datetime writtenAt;
    }

    // A car on a page of the book, ordered newest-written first.
    private class PageCar implements Comparable {
        Id vehicleId;
        Datetime writtenAt;
        PageCar(Id vehicleId, Datetime writtenAt) {
            this.vehicleId = vehicleId;
            this.writtenAt = writtenAt;
        }
        public Integer compareTo(Object other) {
            PageCar that = (PageCar) other;
            if (writtenAt == that.writtenAt) {
                return String.valueOf(that.vehicleId).compareTo(String.valueOf(vehicleId));
            }
            if (writtenAt == null) {
                return 1;
            }
            if (that.writtenAt == null) {
                return -1;
            }
            return writtenAt > that.writtenAt ? -1 : 1;
        }
    }

    public class Visit {
        @AuraEnabled public Date entryDate { get; set; }
        @AuraEnabled public String workDone { get; set; }
    }

    public class VisitGroup {
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public List<Visit> days { get; set; }
    }

    public class ServiceCard {
        @AuraEnabled public Id vehicleId { get; set; }
        // Blank while the car has no customer details, which rules out billing.
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String carModel { get; set; }
        @AuraEnabled public String registrationNumber { get; set; }
        // What was written for the date asked about. Blank if nothing yet.
        @AuraEnabled public String workDone { get; set; }
        @AuraEnabled public Boolean hasEntryForDate { get; set; }
        // The visit that date belongs to, or would join if something is written.
        @AuraEnabled public Date visitStart { get; set; }
        // That visit's other days, oldest first.
        @AuraEnabled public List<Visit> visitDays { get; set; }
        // Set when that date starts a visit but an earlier one could be joined.
        @AuraEnabled public Date previousVisitStart { get; set; }
        // Every other visit of this car, newest first.
        @AuraEnabled public List<VisitGroup> otherVisits { get; set; }
    }

    public class CarModelOption {
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
    }

    public class SaveRequest {
        @AuraEnabled public Date entryDate { get; set; }
        @AuraEnabled public String workDone { get; set; }
        // Only read when this day's entry is first written. Otherwise the day
        // joins the car's latest visit.
        @AuraEnabled public Boolean startNewVisit { get; set; }
        // Set for a car already known...
        @AuraEnabled public Id vehicleId { get; set; }
        // ...otherwise the car number typed on a new card. All optional but that.
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String registrationNumber { get; set; }
    }

    /** One page of the book, the most recently started card first. */
    @AuraEnabled
    public static List<ServiceCard> getDay(Date entryDate) {
        List<PageCar> onThePage = new List<PageCar>();
        // In chunks: an old date can match many cars, and only their days on it are kept.
        for (List<Vehicle__c> chunk : [
            SELECT Id, Service_Book__c FROM Vehicle__c
            WHERE First_Service_Date__c <= :entryDate AND Last_Service_Date__c >= :entryDate
        ]) {
            for (Vehicle__c vehicle : chunk) {
                for (Entry entry : readBook(vehicle)) {
                    if (entry.entryDate == entryDate) {
                        onThePage.add(new PageCar(vehicle.Id, entry.writtenAt));
                    }
                }
            }
        }
        onThePage.sort();
        List<Id> vehicleIds = new List<Id>();
        for (PageCar car : onThePage) {
            vehicleIds.add(car.vehicleId);
        }
        Map<Id, Vehicle__c> vehicles = new Map<Id, Vehicle__c>(queryVehicles(vehicleIds));
        List<Vehicle__c> inOrder = new List<Vehicle__c>();
        for (Id vehicleId : vehicleIds) {
            inOrder.add(vehicles.get(vehicleId));
        }
        return buildCards(inOrder, entryDate);
    }

    @AuraEnabled
    public static ServiceCard getVehicleCard(Id vehicleId, Date entryDate) {
        return buildCards(queryVehicles(new List<Id>{ vehicleId }), entryDate)[0];
    }

    /**
     * Any mix of car number, model, make, customer name or phone. Every word
     * typed has to match something, so "ramesh swift" narrows down, and
     * "MP 09 AB 1234" still finds MP09AB1234.
     */
    @AuraEnabled
    public static List<ServiceCard> search(String term, Date entryDate) {
        if (String.isBlank(term) || term.trim().length() < 2) {
            return new List<ServiceCard>();
        }
        List<String> vehicleConditions = new List<String>();
        List<String> customerConditions = new List<String>();
        List<String> words = term.trim().split('\\s+');
        for (Integer i = 0; i < Math.min(words.size(), MAX_SEARCH_WORDS); i++) {
            String word = '\'%' + String.escapeSingleQuotes(words[i]) + '%\'';
            vehicleConditions.add('(Name LIKE ' + word + ' OR Make__c LIKE ' + word + ' OR Model__c LIKE ' + word
                + ' OR Customer__r.Name LIKE ' + word + ' OR Customer__r.Phone__c LIKE ' + word + ')');
            customerConditions.add('(Name LIKE ' + word + ' OR Phone__c LIKE ' + word + ')');
        }

        List<ServiceCard> cards = buildCards(
            Database.query(
                'SELECT Id, Name, Make__c, Model__c, Customer__c, Customer__r.Name, Customer__r.Phone__c, Service_Book__c FROM Vehicle__c WHERE '
                + String.join(vehicleConditions, ' AND ') + ' ORDER BY Name LIMIT 20'
            ),
            entryDate
        );

        // A customer who has no car on file yet can still be picked.
        for (Customer__c customer : Database.query(
            'SELECT Id, Name, Phone__c FROM Customer__c WHERE Id NOT IN (SELECT Customer__c FROM Vehicle__c) AND '
            + String.join(customerConditions, ' AND ')
            + ' AND Name != \'' + QuickBillController.WALK_IN_NAME + '\' ORDER BY Name LIMIT 10'
        )) {
            ServiceCard card = new ServiceCard();
            card.customerId = customer.Id;
            card.customerName = customer.Name;
            card.phone = shownPhone(customer.Phone__c);
            card.visitDays = new List<Visit>();
            card.otherVisits = new List<VisitGroup>();
            card.hasEntryForDate = false;
            cards.add(card);
        }
        return cards;
    }

    @AuraEnabled
    public static List<CarModelOption> searchCarModels(String term) {
        String likeTerm = '%' + (String.isBlank(term) ? '' : term.trim()) + '%';
        List<CarModelOption> options = new List<CarModelOption>();
        for (Vehicle_Make_Model__c row : [
            SELECT Make__c, Model__c FROM Vehicle_Make_Model__c
            WHERE Model__c LIKE :likeTerm OR Make__c LIKE :likeTerm
            ORDER BY Make__c, Model__c
            LIMIT 10
        ]) {
            CarModelOption option = new CarModelOption();
            option.make = row.Make__c;
            option.model = row.Model__c;
            options.add(option);
        }
        return options;
    }

    /**
     * Called as staff type. Returns the card as it now stands, or null if
     * nothing was written on a car that isn't on file yet.
     */
    @AuraEnabled
    public static ServiceCard saveWork(SaveRequest request) {
        Date entryDate = request.entryDate != null ? request.entryDate : Date.today();
        Boolean isBlank = String.isBlank(request.workDone);
        if (isBlank && request.vehicleId == null) {
            return null;
        }
        Id vehicleId = request.vehicleId != null ? request.vehicleId : resolveNewVehicle(request);

        Vehicle__c locked = lockBook(vehicleId);
        List<Entry> entries = readBook(locked);
        Entry existing = dayOf(entries, entryDate);
        if (isBlank) {
            if (existing != null) {
                List<Entry> kept = new List<Entry>();
                for (Entry entry : entries) {
                    if (entry.entryDate != entryDate) {
                        kept.add(entry);
                    }
                }
                writeBook(locked, kept);
            }
        } else if (existing != null) {
            existing.workDone = request.workDone.trim();
            writeBook(locked, entries);
        } else {
            Entry day = new Entry();
            day.entryDate = entryDate;
            day.workDone = request.workDone.trim();
            day.writtenAt = Datetime.now();
            day.visitStart = entryDate;
            if (request.startNewVisit != true) {
                Entry previous = latestBefore(entries, entryDate);
                if (previous != null) {
                    day.visitStart = visitKey(previous);
                }
            }
            entries.add(day);
            writeBook(locked, entries);
        }
        return getVehicleCard(vehicleId, entryDate);
    }

    /**
     * Moves a day, and the later days of its visit with it, into a visit of its
     * own (startNew), or back into the visit before it. Does nothing for a day
     * with nothing written yet: the screen sends that choice with the first save.
     */
    @AuraEnabled
    public static ServiceCard changeVisit(Id vehicleId, Date entryDate, Boolean startNew) {
        Vehicle__c locked = lockBook(vehicleId);
        List<Entry> entries = readBook(locked);
        Entry day = dayOf(entries, entryDate);
        if (day != null) {
            Date currentVisit = visitKey(day);
            Date newVisit = entryDate;
            if (startNew != true) {
                Entry previous = latestBefore(entries, entryDate);
                newVisit = previous == null ? entryDate : visitKey(previous);
            }
            for (Entry entry : entries) {
                if (visitKey(entry) == currentVisit && entry.entryDate >= entryDate) {
                    entry.visitStart = newVisit;
                }
            }
            writeBook(locked, entries);
        }
        return getVehicleCard(vehicleId, entryDate);
    }

    // The car's row, locked so two people writing about it at once both count.
    private static Vehicle__c lockBook(Id vehicleId) {
        return [SELECT Id, Service_Book__c FROM Vehicle__c WHERE Id = :vehicleId FOR UPDATE];
    }

    /** A car's days, oldest first (the vehicle must be queried with Service_Book__c). */
    public static List<Entry> readBook(Vehicle__c vehicle) {
        if (String.isBlank(vehicle.Service_Book__c)) {
            return new List<Entry>();
        }
        return (List<Entry>) JSON.deserialize(vehicle.Service_Book__c, List<Entry>.class);
    }

    private static void writeBook(Vehicle__c vehicle, List<Entry> entries) {
        List<Entry> ordered = sortedByDate(entries);
        String body = ordered.isEmpty() ? null : JSON.serialize(ordered, true);
        if (body != null && body.length() > StoredLines.MAX_LENGTH) {
            throw new ServiceBookControllerException('This car\'s Service Book has no room left. Shorten an earlier day\'s note.');
        }
        update new Vehicle__c(
            Id = vehicle.Id,
            Service_Book__c = body,
            First_Service_Date__c = ordered.isEmpty() ? null : ordered[0].entryDate,
            Last_Service_Date__c = ordered.isEmpty() ? null : ordered[ordered.size() - 1].entryDate
        );
    }

    private static List<Entry> sortedByDate(List<Entry> entries) {
        Map<Date, Entry> byDate = new Map<Date, Entry>();
        for (Entry entry : entries) {
            byDate.put(entry.entryDate, entry);
        }
        List<Date> dates = new List<Date>(byDate.keySet());
        dates.sort();
        List<Entry> ordered = new List<Entry>();
        for (Date d : dates) {
            ordered.add(byDate.get(d));
        }
        return ordered;
    }

    private static Entry dayOf(List<Entry> entries, Date entryDate) {
        for (Entry entry : entries) {
            if (entry.entryDate == entryDate) {
                return entry;
            }
        }
        return null;
    }

    private static Entry latestBefore(List<Entry> entries, Date entryDate) {
        Entry latest;
        for (Entry entry : entries) {
            if (entry.entryDate < entryDate && (latest == null || entry.entryDate > latest.entryDate)) {
                latest = entry;
            }
        }
        return latest;
    }

    // Entries written before visits existed have no start: each was its own visit.
    private static Date visitKey(Entry entry) {
        return entry.visitStart != null ? entry.visitStart : entry.entryDate;
    }

    /** Fills in what a card was missing: its customer, mobile number or model. */
    @AuraEnabled
    public static ServiceCard saveCardDetails(SaveRequest request) {
        if (request == null || request.vehicleId == null) {
            throw new ServiceBookControllerException('Choose a car first.');
        }
        fillDetails(request.vehicleId, request);
        return getVehicleCard(request.vehicleId, request.entryDate != null ? request.entryDate : Date.today());
    }

    private static Id resolveNewVehicle(SaveRequest request) {
        if (String.isBlank(request.registrationNumber)) {
            throw new ServiceBookControllerException('Type the car number.');
        }
        // On this screen the car number is the car, whoever it was filed under.
        // SOQL "=" and IN are case-insensitive, so case doesn't matter here.
        String typed = request.registrationNumber.trim();
        String registration = typed.replaceAll('[\\s-]', '').toUpperCase();
        List<Vehicle__c> sameNumber = [
            SELECT Id, Customer__c FROM Vehicle__c
            WHERE Name IN :new List<String>{ typed, registration }
            ORDER BY CreatedDate
        ];
        if (!sameNumber.isEmpty()) {
            Id vehicleId = sameNumber[0].Id;
            for (Vehicle__c vehicle : sameNumber) {
                if (vehicle.Customer__c == request.customerId) {
                    vehicleId = vehicle.Id;
                }
            }
            fillDetails(vehicleId, request);
            return vehicleId;
        }

        CustomerController.NewVehicleInput vehicle = new CustomerController.NewVehicleInput();
        vehicle.registrationNumber = registration;
        vehicle.make = request.make;
        vehicle.model = request.model;
        return CustomerController.createVehicle(resolveCustomer(request), vehicle).id;
    }

    // Only fills gaps: details a car already has are changed on their own screens.
    private static void fillDetails(Id vehicleId, SaveRequest request) {
        Vehicle__c vehicle = [
            SELECT Make__c, Model__c, Customer__c, Customer__r.Name, Customer__r.Phone__c
            FROM Vehicle__c
            WHERE Id = :vehicleId
        ];
        Vehicle__c changes = new Vehicle__c(Id = vehicleId);
        Boolean phoneTyped = String.isNotBlank(request.phone);

        if (hasNoCustomer(vehicle.Customer__r)) {
            if (request.customerId != null || String.isNotBlank(request.customerName) || phoneTyped) {
                changes.Customer__c = resolveCustomer(request);
            }
        } else if (phoneTyped && vehicle.Customer__r.Phone__c == QuickBillController.WALK_IN_PHONE) {
            Customer__c samePhone = QuickBillController.findByPhone(request.phone);
            if (samePhone != null) {
                changes.Customer__c = samePhone.Id;
            } else {
                update new Customer__c(Id = vehicle.Customer__c, Phone__c = request.phone.trim());
            }
        }
        if (String.isBlank(vehicle.Model__c) && String.isBlank(vehicle.Make__c) && String.isNotBlank(request.model)) {
            changes.Make__c = request.make;
            changes.Model__c = request.model;
            VehicleMakeModelService.rememberIfNew(request.make, request.model);
        }
        update changes;
    }

    // Nothing typed means the shared Walk-in Customer. A mobile number identifies
    // a customer. A name with no number is reused by name, so regulars who never
    // give a number don't pile up as new customers. Customer__c needs a name, so a
    // number with no name uses the number until someone types one.
    private static Id resolveCustomer(SaveRequest request) {
        if (request.customerId != null) {
            return request.customerId;
        }
        String name = String.isBlank(request.customerName) ? null : request.customerName.trim();
        String phone = String.isBlank(request.phone) ? null : request.phone.trim();
        if (name == null && phone == null) {
            return QuickBillController.walkInCustomerId();
        }

        if (phone != null) {
            Customer__c samePhone = QuickBillController.findByPhone(phone);
            if (samePhone != null) {
                return samePhone.Id;
            }
        } else {
            List<Customer__c> sameName = [
                SELECT Id FROM Customer__c
                WHERE Name = :name AND Phone__c = :QuickBillController.WALK_IN_PHONE
                ORDER BY CreatedDate LIMIT 1
            ];
            if (!sameName.isEmpty()) {
                return sameName[0].Id;
            }
        }
        Customer__c created = new Customer__c(
            Name = name != null ? name : phone,
            Phone__c = phone != null ? phone : QuickBillController.WALK_IN_PHONE
        );
        insert created;
        return created.Id;
    }

    private static Boolean hasNoCustomer(Customer__c customer) {
        return customer.Name == QuickBillController.WALK_IN_NAME && customer.Phone__c == QuickBillController.WALK_IN_PHONE;
    }

    private static List<Vehicle__c> queryVehicles(List<Id> vehicleIds) {
        return [
            SELECT Id, Name, Make__c, Model__c, Customer__c, Customer__r.Name, Customer__r.Phone__c, Service_Book__c
            FROM Vehicle__c
            WHERE Id IN :vehicleIds
        ];
    }

    private static List<ServiceCard> buildCards(List<Vehicle__c> vehicles, Date entryDate) {
        List<ServiceCard> cards = new List<ServiceCard>();
        for (Vehicle__c vehicle : vehicles) {
            ServiceCard card = new ServiceCard();
            card.vehicleId = vehicle.Id;
            if (!hasNoCustomer(vehicle.Customer__r)) {
                card.customerId = vehicle.Customer__c;
                card.customerName = vehicle.Customer__r.Name;
                card.phone = shownPhone(vehicle.Customer__r.Phone__c);
            }
            card.registrationNumber = vehicle.Name;
            card.carModel = String.join(nonBlank(vehicle.Make__c, vehicle.Model__c), ' ');
            fillVisits(card, sortedByDate(readBook(vehicle)), entryDate);
            cards.add(card);
        }
        return cards;
    }

    // entries are oldest first.
    private static void fillVisits(ServiceCard card, List<Entry> entries, Date entryDate) {
        Entry onTheDay;
        Entry latestBefore;
        for (Entry entry : entries) {
            if (entry.entryDate == entryDate) {
                onTheDay = entry;
            } else if (entry.entryDate < entryDate) {
                latestBefore = entry;
            }
        }
        card.hasEntryForDate = onTheDay != null;
        card.workDone = onTheDay != null ? onTheDay.workDone : null;

        // A day with nothing written yet would join the latest visit before it.
        Date currentVisit = onTheDay != null ? visitKey(onTheDay) : (latestBefore != null ? visitKey(latestBefore) : null);
        card.visitStart = currentVisit != null ? currentVisit : entryDate;
        if (card.visitStart == entryDate && latestBefore != null && visitKey(latestBefore) != entryDate) {
            card.previousVisitStart = visitKey(latestBefore);
        }

        card.visitDays = new List<Visit>();
        Map<Date, VisitGroup> others = new Map<Date, VisitGroup>();
        List<Date> otherOrder = new List<Date>();
        for (Entry entry : entries) {
            if (entry.entryDate == entryDate) {
                continue;
            }
            Visit day = new Visit();
            day.entryDate = entry.entryDate;
            day.workDone = entry.workDone;
            Date key = visitKey(entry);
            if (key == currentVisit) {
                card.visitDays.add(day);
                continue;
            }
            if (!others.containsKey(key)) {
                VisitGroup visit = new VisitGroup();
                visit.startDate = key;
                visit.days = new List<Visit>();
                others.put(key, visit);
                otherOrder.add(key);
            }
            others.get(key).days.add(day);
            others.get(key).endDate = entry.entryDate;
        }
        card.otherVisits = new List<VisitGroup>();
        for (Integer i = otherOrder.size() - 1; i >= 0; i--) {
            card.otherVisits.add(others.get(otherOrder[i]));
        }
    }

    private static List<String> nonBlank(String first, String second) {
        List<String> parts = new List<String>();
        for (String part : new List<String>{ first, second }) {
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        return parts;
    }

    // The walk-in placeholder isn't a number anyone should see.
    private static String shownPhone(String phone) {
        return phone == QuickBillController.WALK_IN_PHONE ? null : phone;
    }
}
