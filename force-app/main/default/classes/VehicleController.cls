/**
 * The single Apex entry point for the Vehicle Detail LWC (architecture.md §B).
 * Mirrors PartController/CustomerController's view+edit shape — one method
 * to load everything the detail screen needs, one to save it.
 */
public with sharing class VehicleController {

    public class VehicleControllerException extends Exception {}

    public class VehicleDetail {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String registrationNumber { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public Integer year { get; set; }
        @AuraEnabled public String color { get; set; }
        @AuraEnabled public String chassisNumber { get; set; }
        @AuraEnabled public String engineNumber { get; set; }
        @AuraEnabled public Date dateOfSale { get; set; }
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
    }

    public class VehicleInput {
        @AuraEnabled public String registrationNumber { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public Integer year { get; set; }
        @AuraEnabled public String color { get; set; }
        @AuraEnabled public String chassisNumber { get; set; }
        @AuraEnabled public String engineNumber { get; set; }
        @AuraEnabled public Date dateOfSale { get; set; }
    }

    @AuraEnabled
    public static VehicleDetail getVehicleDetail(Id vehicleId) {
        if (vehicleId == null) {
            throw new VehicleControllerException('A vehicle is required.');
        }
        Vehicle__c v = [
            SELECT Name, Make__c, Model__c, Year__c, Color__c, Chassis_Number__c,
                   Engine_Number__c, Date_Of_Sale__c, Customer__c, Customer__r.Name
            FROM Vehicle__c
            WHERE Id = :vehicleId
        ];

        VehicleDetail detail = new VehicleDetail();
        detail.id = v.Id;
        detail.registrationNumber = v.Name;
        detail.make = v.Make__c;
        detail.model = v.Model__c;
        detail.year = v.Year__c == null ? null : v.Year__c.intValue();
        detail.color = v.Color__c;
        detail.chassisNumber = v.Chassis_Number__c;
        detail.engineNumber = v.Engine_Number__c;
        detail.dateOfSale = v.Date_Of_Sale__c;
        detail.customerId = v.Customer__c;
        detail.customerName = v.Customer__r.Name;
        return detail;
    }

    @AuraEnabled
    public static void updateVehicle(Id vehicleId, VehicleInput input) {
        if (vehicleId == null || input == null || String.isBlank(input.registrationNumber)) {
            throw new VehicleControllerException('A registration number is required.');
        }
        update new Vehicle__c(
            Id = vehicleId,
            Name = input.registrationNumber,
            Make__c = input.make,
            Model__c = input.model,
            Year__c = input.year,
            Color__c = input.color,
            Chassis_Number__c = input.chassisNumber,
            Engine_Number__c = input.engineNumber,
            Date_Of_Sale__c = input.dateOfSale
        );
        VehicleMakeModelService.rememberIfNew(input.make, input.model);
    }
}
