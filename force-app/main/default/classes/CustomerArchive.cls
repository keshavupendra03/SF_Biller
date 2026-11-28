/**
 * Archives dormant customers, with their cars and Service Book, into Files
 * (ArchiveStore), and brings one back the moment staff look for it again
 * (architecture.md, Forty-sixth).
 *
 * What goes, as one "unit": a customer with all their cars, or a car filed
 * under the shared Walk-in Customer (the Walk-in Customer itself never goes).
 * A unit is dormant when nothing has happened to it for
 * Archive_Settings__c.Customers_Dormant_Months__c: the customer and every car
 * were added before then, no car has a Service Book day since, and no archived
 * bill is dated since. It's never archived while any bill, estimate, job or
 * job slip in Salesforce still points at the customer or one of the cars, or
 * while someone changed it in the last 30 days.
 *
 * Archiving is one transaction: the customers file and its index are written
 * and read back, then the cars and customers are deleted and emptied from the
 * Recycle Bin. It runs at most once every 28 days (Run now always), so the
 * archive stays a handful of files a year rather than one a night.
 *
 * Bringing back makes new records (Salesforce can't reuse an Id) and writes
 * the old-to-new Ids to a "moved" file, which also takes the unit out of
 * searches. A customer whose phone number has since been given to a live
 * customer is folded into that customer, and a car whose number is live again
 * has its Service Book days added to that car, so nothing is duplicated.
 */
public without sharing class CustomerArchive {
    // Without sharing: archiving runs for the whole org, and anyone looking a
    // customer up must be able to bring them back.

    public class CustomerArchiveException extends Exception {}

    public static final String KIND_CUSTOMER = 'customer';
    public static final String KIND_CAR = 'car';
    // Per run: stays well inside one transaction's DML and CPU limits.
    @TestVisible
    private static Integer maxUnits = 300;
    // Changed in the last this many days: someone's working on it, so it stays.
    @TestVisible
    private static Integer recentTouchDays = 30;
    // Old customers are looked at this many at a time, up to MAX_PAGES pages,
    // so thousands still coming back never hide a dormant one behind them.
    @TestVisible
    private static Integer pageSize = 2000;
    private static final Integer MAX_PAGES = 5;
    private static final List<String> DOCUMENT_OBJECTS = new List<String>{ 'Bill__c', 'Estimate__c', 'Job__c', 'Job_Slip__c' };

    /** One archived customer with their cars, or one Walk-in car (customer null). */
    public class Unit {
        public String id;
        public Customer__c customer;
        public List<Vehicle__c> vehicles;
        public Date lastSeen;
    }

    public class CustomerFile {
        public Integer format;
        public List<Unit> units;
    }

    public class Plan {
        @AuraEnabled public Integer customers { get; set; }
        @AuraEnabled public Integer cars { get; set; }
        @AuraEnabled public Date dormantBefore { get; set; }
        @AuraEnabled public Boolean isDue { get; set; }
    }

    public class Outcome {
        @AuraEnabled public Integer customers { get; set; }
        @AuraEnabled public Integer cars { get; set; }
    }

    // ---- which customers ------------------------------------------------

    public static Date dormantBefore(ArchiveSettings.Rules rules) {
        return Date.today().addMonths(-Math.max(rules.customersDormantMonths, 6));
    }

    /** Whether the nightly run archives customers tonight: not more than once every 28 days. */
    public static Boolean isDue() {
        return !ArchiveStore.wroteWithin(ArchiveStore.KIND_CUSTOMERS, ArchiveStore.DAYS_BETWEEN_RUNS);
    }

    /** Due, or more waiting than one run takes (a backlog clears a batch a night). */
    public static Boolean isDue(ArchiveSettings.Rules rules) {
        return isDue() || candidates(rules).size() > maxUnits;
    }

    // A ready customer or car, before its records are read in full.
    private class Candidate implements Comparable {
        Id id;
        Id customerId;
        List<Id> vehicleIds = new List<Id>();
        Date lastSeen;
        public Integer compareTo(Object other) {
            Candidate that = (Candidate) other;
            if (lastSeen == that.lastSeen) {
                return String.valueOf(id).compareTo(String.valueOf(that.id));
            }
            return lastSeen < that.lastSeen ? -1 : 1;
        }
    }

    public static Plan plan(ArchiveSettings.Rules rules) {
        Plan p = new Plan();
        p.dormantBefore = dormantBefore(rules);
        p.customers = 0;
        p.cars = 0;
        p.isDue = isDue();
        for (Candidate c : candidates(rules)) {
            if (c.customerId != null) {
                p.customers++;
            } else {
                p.cars++;
            }
        }
        return p;
    }

    // Dormant customers and Walk-in cars, the longest-quiet first: page after
    // page of old customers until a run's worth is found.
    private static List<Candidate> candidates(ArchiveSettings.Rules rules) {
        Date before = dormantBefore(rules);
        Datetime beforeTime = Datetime.newInstance(before, Time.newInstance(0, 0, 0, 0));
        Datetime touched = Datetime.now().addDays(-recentTouchDays);
        Id walkInId = QuickBillController.walkInCustomerIdIfExists();
        List<ArchiveStore.IndexEntry> archivedWork = ArchiveStore.index().clone();
        archivedWork.addAll(ArchiveStore.workIndex());

        List<Candidate> ready = new List<Candidate>();
        Datetime afterCreated;
        Id afterId;
        for (Integer page = 0; page < MAX_PAGES && ready.size() <= maxUnits; page++) {
            List<Customer__c> customers = afterId == null
                ? [
                    SELECT Id, CreatedDate FROM Customer__c
                    WHERE CreatedDate < :beforeTime AND LastModifiedDate < :touched AND Id != :walkInId
                    ORDER BY CreatedDate, Id LIMIT :pageSize
                ]
                : [
                    SELECT Id, CreatedDate FROM Customer__c
                    WHERE CreatedDate < :beforeTime AND LastModifiedDate < :touched AND Id != :walkInId
                      AND (CreatedDate > :afterCreated OR (CreatedDate = :afterCreated AND Id > :afterId))
                    ORDER BY CreatedDate, Id LIMIT :pageSize
                ];
            if (customers.isEmpty()) {
                break;
            }
            afterCreated = customers[customers.size() - 1].CreatedDate;
            afterId = customers[customers.size() - 1].Id;
            ready.addAll(readyAmong(customers, page == 0 ? walkInId : null, before, beforeTime, touched, archivedWork));
            if (customers.size() < pageSize) {
                break;
            }
        }
        if (afterId == null && walkInId != null) {
            // No old customers at all: Walk-in cars may still be ready.
            ready.addAll(readyAmong(new List<Customer__c>(), walkInId, before, beforeTime, touched, archivedWork));
        }
        ready.sort();
        return ready;
    }

    // Of these customers (and, given its Id, the Walk-in Customer's cars), those ready.
    private static List<Candidate> readyAmong(List<Customer__c> customers, Id walkInId, Date before, Datetime beforeTime,
                                              Datetime touched, List<ArchiveStore.IndexEntry> archivedWork) {
        Map<Id, Candidate> byCustomer = new Map<Id, Candidate>();
        for (Customer__c c : customers) {
            Candidate cand = new Candidate();
            cand.id = c.Id;
            cand.customerId = c.Id;
            cand.lastSeen = c.CreatedDate.date();
            byCustomer.put(c.Id, cand);
        }
        Set<Id> blocked = new Set<Id>();
        Map<Id, Candidate> byVehicle = new Map<Id, Candidate>();
        Set<Id> customerIds = byCustomer.keySet();
        for (Vehicle__c v : [
            SELECT Id, Customer__c, CreatedDate, LastModifiedDate, Last_Service_Date__c
            FROM Vehicle__c WHERE Customer__c IN :customerIds
        ]) {
            Candidate cand = byCustomer.get(v.Customer__c);
            cand.vehicleIds.add(v.Id);
            byVehicle.put(v.Id, cand);
            cand.lastSeen = latest(cand.lastSeen, latest(v.CreatedDate.date(), v.Last_Service_Date__c));
            if (v.LastModifiedDate >= touched) {
                blocked.add(cand.id);
            }
        }
        List<Candidate> walkInCars = new List<Candidate>();
        if (walkInId != null) {
            for (Vehicle__c v : [
                SELECT Id, CreatedDate, Last_Service_Date__c FROM Vehicle__c
                WHERE Customer__c = :walkInId AND CreatedDate < :beforeTime AND LastModifiedDate < :touched
                    AND (Last_Service_Date__c = null OR Last_Service_Date__c < :before)
                ORDER BY CreatedDate LIMIT 2000
            ]) {
                Candidate cand = new Candidate();
                cand.id = v.Id;
                cand.vehicleIds.add(v.Id);
                cand.lastSeen = latest(v.CreatedDate.date(), v.Last_Service_Date__c);
                byVehicle.put(v.Id, cand);
                walkInCars.add(cand);
            }
        }

        // Anything a live document points at stays.
        Set<Id> vehicleIds = byVehicle.keySet();
        for (String objectName : DOCUMENT_OBJECTS) {
            for (AggregateResult r : Database.query(
                'SELECT Customer__c c, Vehicle__c v FROM ' + objectName
                + ' WHERE Customer__c IN :customerIds OR Vehicle__c IN :vehicleIds GROUP BY Customer__c, Vehicle__c'
            )) {
                Id c = (Id) r.get('c');
                Id v = (Id) r.get('v');
                if (c != null && byCustomer.containsKey(c)) {
                    blocked.add(c);
                }
                if (v != null && byVehicle.containsKey(v)) {
                    blocked.add(byVehicle.get(v).id);
                }
            }
        }
        // An archived bill, job or job slip counts as being seen on its date.
        for (ArchiveStore.IndexEntry e : archivedWork) {
            for (String ref : new List<String>{ e.cu, e.ve }) {
                Candidate cand = ref == null ? null : (byCustomer.containsKey(ref) ? byCustomer.get(ref) : byVehicle.get(ref));
                if (cand != null) {
                    cand.lastSeen = latest(cand.lastSeen, e.d);
                }
            }
        }

        List<Candidate> ready = new List<Candidate>();
        List<Candidate> all = new List<Candidate>(byCustomer.values());
        all.addAll(walkInCars);
        for (Candidate cand : all) {
            if (!blocked.contains(cand.id) && cand.lastSeen < before) {
                ready.add(cand);
            }
        }
        return ready;
    }

    private static Date latest(Date a, Date b) {
        if (a == null) {
            return b;
        }
        return b == null || a >= b ? a : b;
    }

    // ---- archiving ------------------------------------------------------

    /** Archives up to maxUnits dormant customers and Walk-in cars, in one transaction. */
    public static Outcome archiveReady(ArchiveSettings.Rules rules) {
        Outcome outcome = new Outcome();
        outcome.customers = 0;
        outcome.cars = 0;
        List<Candidate> ready = candidates(rules);
        if (ready.isEmpty()) {
            return outcome;
        }
        List<Candidate> chosen = new List<Candidate>();
        Integer rows = 0;
        for (Candidate cand : ready) {
            rows += 1 + cand.vehicleIds.size();
            if (chosen.size() >= maxUnits || rows > 4000) {
                break;
            }
            chosen.add(cand);
        }

        Set<Id> customerIds = new Set<Id>();
        Set<Id> vehicleIds = new Set<Id>();
        for (Candidate cand : chosen) {
            if (cand.customerId != null) {
                customerIds.add(cand.customerId);
            }
            vehicleIds.addAll(cand.vehicleIds);
        }
        Map<Id, Customer__c> customers = new Map<Id, Customer__c>((List<Customer__c>) Database.query(
            'SELECT ' + String.join(fieldsOf(Customer__c.SObjectType), ', ') + ' FROM Customer__c WHERE Id IN :customerIds FOR UPDATE'
        ));
        Map<Id, Vehicle__c> vehicles = new Map<Id, Vehicle__c>((List<Vehicle__c>) Database.query(
            'SELECT ' + String.join(fieldsOf(Vehicle__c.SObjectType), ', ') + ' FROM Vehicle__c WHERE Id IN :vehicleIds FOR UPDATE'
        ));

        List<Unit> units = new List<Unit>();
        for (Candidate cand : chosen) {
            Unit u = new Unit();
            u.id = cand.id;
            u.customer = cand.customerId == null ? null : customers.get(cand.customerId);
            u.vehicles = new List<Vehicle__c>();
            for (Id vehicleId : cand.vehicleIds) {
                u.vehicles.add(vehicles.get(vehicleId));
            }
            u.lastSeen = cand.lastSeen;
            units.add(u);
            if (u.customer != null) {
                outcome.customers++;
            } else {
                outcome.cars++;
            }
        }

        CustomerFile file = new CustomerFile();
        file.format = 1;
        file.units = units;
        String month = Datetime.now().format('yyyy-MM');
        Id documentId = ArchiveStore.write(ArchiveStore.KIND_CUSTOMERS, null, month, 'Customers and cars ' + month, JSON.serialize(file));

        List<ArchiveStore.IndexEntry> entries = new List<ArchiveStore.IndexEntry>();
        for (Unit u : units) {
            ArchiveStore.IndexEntry e = new ArchiveStore.IndexEntry();
            e.id = u.id;
            e.k = u.customer != null ? KIND_CUSTOMER : KIND_CAR;
            e.c = u.customer == null ? null : u.customer.Name;
            e.p = u.customer == null ? null : u.customer.Phone__c;
            List<String> numbers = new List<String>();
            e.vs = new List<String>();
            for (Vehicle__c v : u.vehicles) {
                numbers.add(v.Name);
                e.vs.add(v.Id);
            }
            e.v = numbers.isEmpty() ? null : String.join(numbers, ' ');
            e.d = u.lastSeen;
            e.f = documentId;
            entries.add(e);
        }
        ArchiveStore.write(ArchiveStore.KIND_CUSTOMER_INDEX, null, null, 'Customer index ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss'),
            JSON.serialize(entries, true));

        // Read back before anything is deleted.
        CustomerFile back = (CustomerFile) JSON.deserialize(ArchiveStore.read(documentId), CustomerFile.class);
        if (back.units == null || back.units.size() != units.size()) {
            throw new CustomerArchiveException('The customers archive file did not read back as written. Nothing was archived.');
        }

        // Cars first: a customer can't be deleted while a car points at them.
        List<Vehicle__c> goingCars = vehicles.values();
        List<Customer__c> goingCustomers = customers.values();
        delete goingCars;
        delete goingCustomers;
        List<SObject> emptied = new List<SObject>();
        emptied.addAll((List<SObject>) goingCars);
        emptied.addAll((List<SObject>) goingCustomers);
        if (!emptied.isEmpty()) {
            Database.emptyRecycleBin(emptied);
        }
        entriesCache = null;
        return outcome;
    }

    // Every field a record is saved with: Name and the custom ones, less formulas.
    private static List<String> fieldsOf(Schema.SObjectType t) {
        List<String> names = new List<String>{ 'Id', 'CreatedDate' };
        for (Schema.SObjectField f : t.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if ((d.isCustom() || d.getName() == 'Name') && !d.isCalculated() && !d.isAutoNumber()) {
                names.add(d.getName());
            }
        }
        return names;
    }

    // ---- finding --------------------------------------------------------

    private static List<ArchiveStore.IndexEntry> entriesCache;

    /** Archived customers and Walk-in cars not brought back since. */
    public static List<ArchiveStore.IndexEntry> entries() {
        if (entriesCache == null) {
            entriesCache = ArchiveStore.customerIndex();
        }
        return entriesCache;
    }

    /** Archived customers and cars whose name, phone or car number matches every word typed. */
    public static List<ArchiveStore.IndexEntry> search(String term, Integer max) {
        List<ArchiveStore.IndexEntry> matches = new List<ArchiveStore.IndexEntry>();
        if (String.isBlank(term) || term.trim().length() < 2) {
            return matches;
        }
        List<String> words = term.trim().toLowerCase().split('\\s+');
        List<ArchiveStore.IndexEntry> all = entries();
        for (ArchiveStore.IndexEntry e : all) {
            String text = String.join(new List<String>{ e.c == null ? '' : e.c, e.p == null ? '' : e.p, e.v == null ? '' : e.v }, ' ').toLowerCase();
            String compact = text.replaceAll('[^a-z0-9]', '');
            Boolean every = true;
            for (String w : words) {
                every = every && (text.contains(w) || compact.contains(w.replaceAll('[^a-z0-9]', '')));
            }
            if (every) {
                matches.add(e);
                if (matches.size() >= max) {
                    break;
                }
            }
        }
        return matches;
    }

    /** Phone numbers match on their last 10 digits; a shorter number never matches. */
    public static String phoneKey(String phone) {
        String digits = phone == null ? '' : phone.replaceAll('[^0-9]', '');
        return digits.length() < 10 || digits.right(10) == QuickBillController.WALK_IN_PHONE ? null : digits.right(10);
    }

    /** Car numbers match whatever the spacing, dashes or case. */
    public static String carKey(String registration) {
        String key = registration == null ? '' : registration.toUpperCase().replaceAll('[^A-Z0-9]', '');
        return key.length() < 4 ? null : key;
    }

    public static ArchiveStore.IndexEntry findByPhone(String phone) {
        String key = phoneKey(phone);
        if (key == null) {
            return null;
        }
        for (ArchiveStore.IndexEntry e : entries()) {
            if (e.k == KIND_CUSTOMER && key == phoneKey(e.p)) {
                return e;
            }
        }
        return null;
    }

    public static ArchiveStore.IndexEntry findByCar(String registration) {
        String key = carKey(registration);
        if (key == null) {
            return null;
        }
        for (ArchiveStore.IndexEntry e : entries()) {
            for (String plate : e.v == null ? new List<String>() : e.v.split(' ')) {
                if (key == carKey(plate)) {
                    return e;
                }
            }
        }
        return null;
    }

    // ---- bringing back --------------------------------------------------

    /**
     * The customer with this phone back in Salesforce, if archived: their Id
     * now. Null when not archived, or when the archive can't be read or the
     * restore fails: looking a customer up for a bill must never fail because
     * of the archive (anything half done is undone).
     */
    public static Id bringBackByPhone(String phone) {
        Savepoint sp = Database.setSavepoint();
        try {
            ArchiveStore.IndexEntry e = findByPhone(phone);
            return e == null ? null : restore(e.id).customerId;
        } catch (Exception ex) {
            Database.rollback(sp);
            System.debug(LoggingLevel.WARN, 'Archive: could not bring back the customer with phone ' + phone + ': ' + ex.getMessage());
            return null;
        }
    }

    /** The car with this number back in Salesforce, if archived: its Id now. Null as bringBackByPhone. */
    public static Id bringBackByCar(String registration) {
        Savepoint sp = Database.setSavepoint();
        try {
            ArchiveStore.IndexEntry e = findByCar(registration);
            if (e == null) {
                return null;
            }
            Restored r = restore(e.id);
            String key = carKey(registration);
            for (Vehicle__c v : r.vehicles) {
                if (key == carKey(v.Name)) {
                    return r.vehicleIds.get(v.Id);
                }
            }
            return null;
        } catch (Exception ex) {
            Database.rollback(sp);
            System.debug(LoggingLevel.WARN, 'Archive: could not bring back car ' + registration + ': ' + ex.getMessage());
            return null;
        }
    }

    /** Archived matches for a search box; none (rather than an error) if the archive can't be read. */
    public static List<ArchiveStore.IndexEntry> searchQuietly(String term, Integer max) {
        try {
            return search(term, max);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Archive: search failed: ' + ex.getMessage());
            return new List<ArchiveStore.IndexEntry>();
        }
    }

    /** What a restore made: the customer's Id now, and each car's old Id to its Id now. */
    public class Restored {
        public Id customerId;
        public Map<Id, Id> vehicleIds = new Map<Id, Id>();
        public List<Vehicle__c> vehicles = new List<Vehicle__c>();
    }

    /** Brings one archived customer (with their cars) or Walk-in car back. */
    public static Restored restore(String unitId) {
        ArchiveStore.IndexEntry asked;
        for (ArchiveStore.IndexEntry e : entries()) {
            if (e.id == unitId) {
                asked = e;
            }
        }
        if (asked == null) {
            throw new CustomerArchiveException('That customer is not in the archive, or was already brought back.');
        }
        CustomerFile file = (CustomerFile) JSON.deserialize(ArchiveStore.read(asked.f), CustomerFile.class);
        Unit unit;
        for (Unit u : file.units) {
            if (u.id == unitId) {
                unit = u;
            }
        }
        if (unit == null) {
            throw new CustomerArchiveException('That customer is missing from its archive file.');
        }

        Restored result = new Restored();
        Map<String, String> moved = new Map<String, String>();
        if (unit.customer != null) {
            Customer__c samePhone = phoneKey(unit.customer.Phone__c) == null ? null : QuickBillController.findLiveByPhone(unit.customer.Phone__c);
            if (samePhone != null) {
                // The number was given to a customer since: one customer, not two.
                Customer__c live = [SELECT Id, Archived_Spend__c FROM Customer__c WHERE Id = :samePhone.Id FOR UPDATE];
                Decimal spend = unit.customer.Archived_Spend__c == null ? 0 : unit.customer.Archived_Spend__c;
                if (spend != 0) {
                    update new Customer__c(Id = live.Id, Archived_Spend__c = (live.Archived_Spend__c == null ? 0 : live.Archived_Spend__c) + spend);
                }
                result.customerId = live.Id;
            } else {
                Customer__c fresh = (Customer__c) copyOf(unit.customer, Customer__c.SObjectType);
                insert fresh;
                result.customerId = fresh.Id;
            }
            moved.put(unit.customer.Id, result.customerId);
        } else {
            result.customerId = QuickBillController.walkInCustomerId();
        }

        List<Vehicle__c> toInsert = new List<Vehicle__c>();
        Map<Id, Vehicle__c> insertedFrom = new Map<Id, Vehicle__c>();
        for (Vehicle__c saved : unit.vehicles) {
            Vehicle__c live = liveCar(saved.Name);
            if (live != null) {
                mergeInto(live, saved);
                result.vehicleIds.put(saved.Id, live.Id);
            } else {
                Vehicle__c fresh = (Vehicle__c) copyOf(saved, Vehicle__c.SObjectType);
                fresh.Customer__c = result.customerId;
                toInsert.add(fresh);
                insertedFrom.put(saved.Id, fresh);
            }
            result.vehicles.add(saved);
        }
        insert toInsert;
        for (Id oldId : insertedFrom.keySet()) {
            result.vehicleIds.put(oldId, insertedFrom.get(oldId).Id);
        }
        for (Id oldId : result.vehicleIds.keySet()) {
            moved.put(oldId, result.vehicleIds.get(oldId));
        }
        // The unit's own Id marks it brought back (for a Walk-in car, that's its car).
        if (!moved.containsKey(unit.id)) {
            moved.put(unit.id, result.customerId);
        }
        ArchiveStore.write(ArchiveStore.KIND_MOVED, null, null, 'Brought back ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss'),
            JSON.serialize(moved));
        entriesCache = null;
        movedCache = null;
        return result;
    }

    // A live car with this number, whoever it's filed under.
    private static Vehicle__c liveCar(String registration) {
        if (String.isBlank(registration)) {
            return null;
        }
        String typed = registration.trim();
        List<Vehicle__c> same = [
            SELECT Id, Service_Book__c, Make__c, Model__c, Chassis_Number__c, Engine_Number__c, Color__c, Year__c, Date_Of_Sale__c
            FROM Vehicle__c WHERE Name IN :new List<String>{ typed, carKey(typed) }
            ORDER BY CreatedDate LIMIT 1
        ];
        return same.isEmpty() ? null : same[0];
    }

    // The archived car's Service Book days and details go onto the live car,
    // which keeps its own where both have one.
    private static void mergeInto(Vehicle__c live, Vehicle__c saved) {
        List<ServiceBookController.Entry> days = ServiceBookController.readBook(live);
        Set<Date> have = new Set<Date>();
        for (ServiceBookController.Entry e : days) {
            have.add(e.entryDate);
        }
        Boolean added = false;
        for (ServiceBookController.Entry e : ServiceBookController.readBook(saved)) {
            if (!have.contains(e.entryDate)) {
                days.add(e);
                added = true;
            }
        }
        if (added) {
            ServiceBookController.writeBook(live, days);
        }
        Vehicle__c gaps = new Vehicle__c(Id = live.Id);
        Boolean changed = false;
        for (String field : new List<String>{ 'Make__c', 'Model__c', 'Chassis_Number__c', 'Engine_Number__c', 'Color__c', 'Year__c', 'Date_Of_Sale__c' }) {
            if (live.get(field) == null && saved.get(field) != null) {
                gaps.put(field, saved.get(field));
                changed = true;
            }
        }
        if (changed) {
            update gaps;
        }
    }

    // A new record with the saved one's details: no Id, no system fields.
    private static SObject copyOf(SObject saved, Schema.SObjectType t) {
        SObject fresh = t.newSObject();
        Map<String, Schema.SObjectField> fields = t.getDescribe().fields.getMap();
        for (String name : saved.getPopulatedFieldsAsMap().keySet()) {
            Schema.SObjectField f = fields.get(name.toLowerCase());
            if (f == null) {
                continue;
            }
            Schema.DescribeFieldResult d = f.getDescribe();
            if ((d.isCustom() || d.getName() == 'Name') && !d.isCalculated() && !d.isAutoNumber()) {
                fresh.put(name, saved.get(name));
            }
        }
        return fresh;
    }

    // ---- archived bills finding their customer --------------------------

    private static Map<String, String> movedCache;

    /**
     * For customer and car Ids no longer in Salesforce (an archived bill's):
     * their Id now, bringing them back from the archive if needed. An Id that
     * is nowhere is left out.
     */
    public static Map<Id, Id> liveIds(Set<Id> oldIds) {
        return liveIds(oldIds, 0);
    }

    private static Map<Id, Id> liveIds(Set<Id> oldIds, Integer depth) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (oldIds.isEmpty()) {
            return result;
        }
        if (movedCache == null) {
            movedCache = ArchiveStore.moved();
        }
        Set<Id> stillArchived = new Set<Id>();
        for (Id oldId : oldIds) {
            if (movedCache.containsKey(oldId)) {
                result.put(oldId, Id.valueOf(movedCache.get(oldId)));
            } else {
                stillArchived.add(oldId);
            }
        }
        for (Id oldId : stillArchived) {
            if (result.containsKey(oldId)) {
                continue;
            }
            for (ArchiveStore.IndexEntry e : entries()) {
                if (e.id == oldId || (e.vs != null && e.vs.contains(String.valueOf(oldId)))) {
                    Restored r = restore(e.id);
                    if (e.k == KIND_CUSTOMER) {
                        result.put(e.id, r.customerId);
                    }
                    for (Id vehicleId : r.vehicleIds.keySet()) {
                        result.put(vehicleId, r.vehicleIds.get(vehicleId));
                    }
                    break;
                }
            }
        }
        // Brought back once and archived again since: follow it (a few times at most).
        Set<Id> targets = new Set<Id>(result.values());
        Set<Id> gone = new Set<Id>(targets);
        gone.removeAll(stillThere(targets));
        if (!gone.isEmpty()) {
            Map<Id, Id> next = depth < 3 ? liveIds(gone, depth + 1) : new Map<Id, Id>();
            for (Id oldId : new List<Id>(result.keySet())) {
                Id now = result.get(oldId);
                if (next.containsKey(now)) {
                    result.put(oldId, next.get(now));
                } else if (gone.contains(now)) {
                    result.remove(oldId);
                }
            }
        }
        return result;
    }

    private static Set<Id> stillThere(Set<Id> ids) {
        Set<Id> found = new Set<Id>();
        for (Customer__c c : [SELECT Id FROM Customer__c WHERE Id IN :ids]) {
            found.add(c.Id);
        }
        for (Vehicle__c v : [SELECT Id FROM Vehicle__c WHERE Id IN :ids]) {
            found.add(v.Id);
        }
        return found;
    }
}
