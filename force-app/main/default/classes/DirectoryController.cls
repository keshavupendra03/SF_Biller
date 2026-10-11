/**
 * The single Apex entry point for the Directory LWCs — Mechanics,
 * Surveyors, and Bill-To-Parties (architecture.md §B). Each of these was
 * previously only reachable via its standard object tab; this gives every
 * one of them the same search/create/toggle-active pattern the rest of the
 * app already uses.
 */
public with sharing class DirectoryController {

    public class DirectoryControllerException extends Exception {}

    public class PersonItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
    }

    public class BillToPartyItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String contactPhone { get; set; }
        @AuraEnabled public String gstin { get; set; }
        @AuraEnabled public String state { get; set; }
    }

    @AuraEnabled
    public static List<PersonItem> listMechanics(Boolean includeInactive) {
        List<Mechanic__c> records = includeInactive
            ? [SELECT Name, Phone__c, Is_Active__c FROM Mechanic__c ORDER BY Name]
            : [SELECT Name, Phone__c, Is_Active__c FROM Mechanic__c WHERE Is_Active__c = true ORDER BY Name];
        return toPersonItems(records);
    }

    @AuraEnabled
    public static PersonItem createMechanic(String name, String phone) {
        if (String.isBlank(name)) {
            throw new DirectoryControllerException('A name is required.');
        }
        Mechanic__c m = new Mechanic__c(Name = name, Phone__c = phone, Is_Active__c = true);
        insert m;
        return toPersonItem(m.Id, m.Name, m.Phone__c, true);
    }

    @AuraEnabled
    public static void setMechanicActive(Id mechanicId, Boolean active) {
        if (mechanicId == null) {
            throw new DirectoryControllerException('A mechanic is required.');
        }
        update new Mechanic__c(Id = mechanicId, Is_Active__c = active);
    }

    @AuraEnabled
    public static List<PersonItem> listSurveyors(Boolean includeInactive) {
        List<Surveyor__c> records = includeInactive
            ? [SELECT Name, Phone__c, Is_Active__c FROM Surveyor__c ORDER BY Name]
            : [SELECT Name, Phone__c, Is_Active__c FROM Surveyor__c WHERE Is_Active__c = true ORDER BY Name];
        return toPersonItems(records);
    }

    @AuraEnabled
    public static PersonItem createSurveyor(String name, String phone) {
        if (String.isBlank(name)) {
            throw new DirectoryControllerException('A name is required.');
        }
        Surveyor__c s = new Surveyor__c(Name = name, Phone__c = phone, Is_Active__c = true);
        insert s;
        return toPersonItem(s.Id, s.Name, s.Phone__c, true);
    }

    @AuraEnabled
    public static void setSurveyorActive(Id surveyorId, Boolean active) {
        if (surveyorId == null) {
            throw new DirectoryControllerException('A surveyor is required.');
        }
        update new Surveyor__c(Id = surveyorId, Is_Active__c = active);
    }

    @AuraEnabled
    public static List<BillToPartyItem> listBillToParties(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(String.isBlank(searchTerm) ? '' : searchTerm) + '%';
        List<Bill_To_Party__c> records = String.isBlank(searchTerm)
            ? [SELECT Name, Address__c, Contact_Phone__c, GSTIN__c, State__c FROM Bill_To_Party__c ORDER BY Name LIMIT 200]
            : [
                SELECT Name, Address__c, Contact_Phone__c, GSTIN__c, State__c
                FROM Bill_To_Party__c
                WHERE Name LIKE :term OR GSTIN__c LIKE :term
                ORDER BY Name
                LIMIT 200
            ];
        List<BillToPartyItem> results = new List<BillToPartyItem>();
        for (Bill_To_Party__c p : records) {
            results.add(toBillToPartyItem(p));
        }
        return results;
    }

    @AuraEnabled
    public static BillToPartyItem createBillToParty(BillController.NewBillToPartyInput input) {
        if (input == null || String.isBlank(input.name)) {
            throw new DirectoryControllerException('A party name is required.');
        }
        Bill_To_Party__c party = new Bill_To_Party__c(
            Name = input.name,
            Address__c = input.address,
            Contact_Phone__c = input.contactPhone,
            GSTIN__c = input.gstin,
            State__c = input.state
        );
        insert party;
        return toBillToPartyItem(party);
    }

    @AuraEnabled
    public static void updateBillToParty(Id billToPartyId, BillController.NewBillToPartyInput input) {
        if (billToPartyId == null || input == null || String.isBlank(input.name)) {
            throw new DirectoryControllerException('A party name is required.');
        }
        update new Bill_To_Party__c(
            Id = billToPartyId,
            Name = input.name,
            Address__c = input.address,
            Contact_Phone__c = input.contactPhone,
            GSTIN__c = input.gstin,
            State__c = input.state
        );
    }

    private static List<PersonItem> toPersonItems(List<SObject> records) {
        List<PersonItem> results = new List<PersonItem>();
        for (SObject r : records) {
            results.add(toPersonItem(
                (Id) r.get('Id'),
                (String) r.get('Name'),
                (String) r.get('Phone__c'),
                (Boolean) r.get('Is_Active__c')
            ));
        }
        return results;
    }

    private static PersonItem toPersonItem(Id id, String name, String phone, Boolean isActive) {
        PersonItem item = new PersonItem();
        item.id = id;
        item.name = name;
        item.phone = phone;
        item.isActive = isActive;
        return item;
    }

    private static BillToPartyItem toBillToPartyItem(Bill_To_Party__c p) {
        BillToPartyItem item = new BillToPartyItem();
        item.id = p.Id;
        item.name = p.Name;
        item.address = p.Address__c;
        item.contactPhone = p.Contact_Phone__c;
        item.gstin = p.GSTIN__c;
        item.state = p.State__c;
        return item;
    }
}
