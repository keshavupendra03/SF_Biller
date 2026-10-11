/**
 * Autocomplete suggestions for the vehicle Make/Model fields (architecture.md
 * §F). Vehicle__c.Make__c/Model__c stay plain text with no lookup to
 * Vehicle_Make_Model__c — this table exists purely to drive suggestions as
 * the user types, not as a picklist constraint. Free-text entry is always
 * allowed; VehicleMakeModelService grows this table with anything new.
 */
public with sharing class VehicleMakeModelController {

    @AuraEnabled
    public static List<String> searchMakes(String term) {
        String likeTerm = '%' + String.escapeSingleQuotes(String.isBlank(term) ? '' : term) + '%';
        List<String> makes = new List<String>();
        for (AggregateResult result : [
            SELECT Make__c make
            FROM Vehicle_Make_Model__c
            WHERE Make__c LIKE :likeTerm
            GROUP BY Make__c
            ORDER BY Make__c
            LIMIT 10
        ]) {
            makes.add((String) result.get('make'));
        }
        return makes;
    }

    @AuraEnabled
    public static List<String> searchModels(String make, String term) {
        String likeTerm = '%' + String.escapeSingleQuotes(String.isBlank(term) ? '' : term) + '%';
        List<AggregateResult> results;
        if (String.isNotBlank(make)) {
            String likeMake = '%' + String.escapeSingleQuotes(make) + '%';
            results = [
                SELECT Model__c model
                FROM Vehicle_Make_Model__c
                WHERE Make__c LIKE :likeMake AND Model__c LIKE :likeTerm
                GROUP BY Model__c
                ORDER BY Model__c
                LIMIT 10
            ];
        } else {
            results = [
                SELECT Model__c model
                FROM Vehicle_Make_Model__c
                WHERE Model__c LIKE :likeTerm
                GROUP BY Model__c
                ORDER BY Model__c
                LIMIT 10
            ];
        }
        List<String> models = new List<String>();
        for (AggregateResult result : results) {
            models.add((String) result.get('model'));
        }
        return models;
    }
}
