/**
 * Grows the Vehicle_Make_Model__c suggestion table whenever a vehicle is
 * created with a make/model combination it doesn't already have, so the
 * next staff member who types that same make/model gets it offered as a
 * suggestion instead of typing it out again. Called once per new vehicle
 * (not bulk — vehicles are created one at a time from the UI), so a single
 * SELECT + single insert per call is the right shape here, not a bulk-safe
 * batch pattern.
 */
public with sharing class VehicleMakeModelService {

    public static void rememberIfNew(String make, String model) {
        if (String.isBlank(make) || String.isBlank(model)) {
            return;
        }
        List<Vehicle_Make_Model__c> existing = [
            SELECT Id
            FROM Vehicle_Make_Model__c
            WHERE Make__c = :make AND Model__c = :model
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new Vehicle_Make_Model__c(
                Name = make + ' ' + model,
                Make__c = make,
                Model__c = model
            );
        }
    }
}
