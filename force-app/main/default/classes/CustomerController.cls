/**
 * The single Apex entry point for the Customers LWC (architecture.md §B).
 * Customer onboarding, their vehicles, and their bills/estimates are all
 * reachable from here without ever dropping into a standard related list —
 * createVehicle lets the Customer Detail screen add a vehicle inline, the
 * same way BillController.createCustomer lets every other screen onboard a
 * customer inline.
 */
public with sharing class CustomerController {

    public class CustomerControllerException extends Exception {}

    public class CustomerListItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
    }

    public class VehicleItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String registrationNumber { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public Integer year { get; set; }
        @AuraEnabled public String color { get; set; }
        @AuraEnabled public String chassisNumber { get; set; }
    }

    public class DocumentItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String documentNumber { get; set; }
        // Only set when the workshop has two companies.
        @AuraEnabled public String companyName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public Date documentDate { get; set; }
    }

    public class JobItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String jobNumber { get; set; }
        @AuraEnabled public String stageName { get; set; }
        @AuraEnabled public String vehicleLabel { get; set; }
        @AuraEnabled public Date createdDate { get; set; }
    }

    public class JobSlipItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String slipNumber { get; set; }
        @AuraEnabled public Date slipDate { get; set; }
        @AuraEnabled public String vehicleLabel { get; set; }
        @AuraEnabled public String visitReason { get; set; }
    }

    public class CustomerDetail {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String gstin { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public Decimal lifetimeSpend { get; set; }
        @AuraEnabled public List<VehicleItem> vehicles { get; set; }
        @AuraEnabled public List<JobItem> jobs { get; set; }
        @AuraEnabled public List<JobSlipItem> jobSlips { get; set; }
        @AuraEnabled public List<DocumentItem> bills { get; set; }
        @AuraEnabled public List<DocumentItem> estimates { get; set; }
    }

    public class CustomerInput {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String gstin { get; set; }
        @AuraEnabled public String state { get; set; }
    }

    public class NewVehicleInput {
        @AuraEnabled public String registrationNumber { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public Integer year { get; set; }
        @AuraEnabled public String color { get; set; }
        @AuraEnabled public String chassisNumber { get; set; }
    }

    @AuraEnabled
    public static List<CustomerListItem> listCustomers(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(String.isBlank(searchTerm) ? '' : searchTerm) + '%';
        List<Customer__c> customers = String.isBlank(searchTerm)
            ? [SELECT Name, Phone__c, Email__c FROM Customer__c ORDER BY Name LIMIT 200]
            : [
                SELECT Name, Phone__c, Email__c FROM Customer__c
                WHERE Name LIKE :term OR Phone__c LIKE :term
                ORDER BY Name
                LIMIT 200
            ];

        List<CustomerListItem> results = new List<CustomerListItem>();
        for (Customer__c c : customers) {
            CustomerListItem item = new CustomerListItem();
            item.id = c.Id;
            item.name = c.Name;
            item.phone = c.Phone__c;
            item.email = c.Email__c;
            results.add(item);
        }
        return results;
    }

    @AuraEnabled
    public static CustomerDetail getCustomerDetail(Id customerId) {
        if (customerId == null) {
            throw new CustomerControllerException('A customer is required.');
        }
        Customer__c customer = [
            SELECT Name, Phone__c, Email__c, Address__c, GSTIN__c, State__c
            FROM Customer__c
            WHERE Id = :customerId
        ];

        CustomerDetail detail = new CustomerDetail();
        detail.id = customer.Id;
        detail.name = customer.Name;
        detail.phone = customer.Phone__c;
        detail.email = customer.Email__c;
        detail.address = customer.Address__c;
        detail.gstin = customer.GSTIN__c;
        detail.state = customer.State__c;

        Decimal spend = 0;
        for (AggregateResult result : [
            SELECT SUM(Amount__c) total
            FROM Payment__c
            WHERE Bill__r.Customer__c = :customerId
        ]) {
            Object total = result.get('total');
            spend = total == null ? 0 : (Decimal) total;
        }
        detail.lifetimeSpend = spend;

        detail.vehicles = new List<VehicleItem>();
        for (Vehicle__c v : [
            SELECT Name, Make__c, Model__c, Year__c, Color__c, Chassis_Number__c
            FROM Vehicle__c
            WHERE Customer__c = :customerId
            ORDER BY Name
        ]) {
            VehicleItem item = new VehicleItem();
            item.id = v.Id;
            item.registrationNumber = v.Name;
            item.make = v.Make__c;
            item.model = v.Model__c;
            item.year = v.Year__c == null ? null : v.Year__c.intValue();
            item.color = v.Color__c;
            item.chassisNumber = v.Chassis_Number__c;
            detail.vehicles.add(item);
        }

        detail.jobs = new List<JobItem>();
        for (Job__c job : [
            SELECT Name, Job_Status_Stage__r.Name, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c, CreatedDate
            FROM Job__c
            WHERE Customer__c = :customerId
            ORDER BY CreatedDate DESC
        ]) {
            JobItem item = new JobItem();
            item.id = job.Id;
            item.jobNumber = job.Name;
            item.stageName = job.Job_Status_Stage__c != null ? job.Job_Status_Stage__r.Name : null;
            item.vehicleLabel = job.Vehicle__c != null ? job.Vehicle__r.Name : null;
            item.createdDate = job.CreatedDate.date();
            detail.jobs.add(item);
        }

        detail.jobSlips = new List<JobSlipItem>();
        for (Job_Slip__c slip : [
            SELECT Name, Slip_Date__c, Visit_Reason__c, Vehicle__r.Name
            FROM Job_Slip__c
            WHERE Customer__c = :customerId
            ORDER BY Slip_Date__c DESC, CreatedDate DESC
        ]) {
            JobSlipItem item = new JobSlipItem();
            item.id = slip.Id;
            item.slipNumber = slip.Name;
            item.slipDate = slip.Slip_Date__c;
            item.vehicleLabel = slip.Vehicle__c != null ? slip.Vehicle__r.Name : null;
            item.visitReason = slip.Visit_Reason__c;
            detail.jobSlips.add(item);
        }

        Map<Id, String> companyNames = WorkshopProfileService.companyNames();

        detail.bills = new List<DocumentItem>();
        for (Bill__c b : [
            SELECT Invoice_Number__c, Status__c, Total_Amount__c, Bill_Date__c, Workshop_Profile__c
            FROM Bill__c
            WHERE Customer__c = :customerId AND Is_Latest_Version__c = true
            ORDER BY CreatedDate DESC
        ]) {
            DocumentItem item = new DocumentItem();
            item.id = b.Id;
            item.documentNumber = b.Invoice_Number__c;
            item.companyName = companyNames.get(b.Workshop_Profile__c);
            item.status = b.Status__c;
            item.totalAmount = b.Total_Amount__c;
            item.documentDate = b.Bill_Date__c;
            detail.bills.add(item);
        }

        detail.estimates = new List<DocumentItem>();
        for (Estimate__c e : [
            SELECT Name, Status__c, Total_Amount__c, Estimate_Date__c, Workshop_Profile__c
            FROM Estimate__c
            WHERE Customer__c = :customerId AND Is_Latest_Version__c = true
            ORDER BY CreatedDate DESC
        ]) {
            DocumentItem item = new DocumentItem();
            item.id = e.Id;
            item.documentNumber = e.Name;
            item.companyName = companyNames.get(e.Workshop_Profile__c);
            item.status = e.Status__c;
            item.totalAmount = e.Total_Amount__c;
            item.documentDate = e.Estimate_Date__c;
            detail.estimates.add(item);
        }

        return detail;
    }

    /**
     * Backs the vehicle picker on the Bill/Estimate create screens — ordered
     * newest-first so the caller can preselect results[0] as "this
     * customer's last created vehicle" without a second query.
     */
    @AuraEnabled
    public static List<VehicleItem> listVehiclesForCustomer(Id customerId) {
        List<VehicleItem> results = new List<VehicleItem>();
        if (customerId == null) {
            return results;
        }
        for (Vehicle__c v : [
            SELECT Name, Make__c, Model__c, Year__c, Color__c, Chassis_Number__c
            FROM Vehicle__c
            WHERE Customer__c = :customerId
            ORDER BY CreatedDate DESC
        ]) {
            VehicleItem item = new VehicleItem();
            item.id = v.Id;
            item.registrationNumber = v.Name;
            item.make = v.Make__c;
            item.model = v.Model__c;
            item.year = v.Year__c == null ? null : v.Year__c.intValue();
            item.color = v.Color__c;
            item.chassisNumber = v.Chassis_Number__c;
            results.add(item);
        }
        return results;
    }

    @AuraEnabled
    public static void updateCustomer(Id customerId, CustomerInput input) {
        if (customerId == null || input == null || String.isBlank(input.name) || String.isBlank(input.phone)) {
            throw new CustomerControllerException('Customer name and phone are required.');
        }
        update new Customer__c(
            Id = customerId,
            Name = input.name,
            Phone__c = input.phone,
            Address__c = input.address,
            Email__c = input.email,
            GSTIN__c = input.gstin,
            State__c = input.state
        );
    }

    @AuraEnabled
    public static VehicleItem createVehicle(Id customerId, NewVehicleInput input) {
        if (customerId == null || input == null || String.isBlank(input.registrationNumber)) {
            throw new CustomerControllerException('A registration number is required.');
        }
        Vehicle__c vehicle = new Vehicle__c(
            Name = input.registrationNumber,
            Customer__c = customerId,
            Make__c = input.make,
            Model__c = input.model,
            Year__c = input.year,
            Color__c = input.color,
            Chassis_Number__c = input.chassisNumber
        );
        insert vehicle;
        VehicleMakeModelService.rememberIfNew(vehicle.Make__c, vehicle.Model__c);

        VehicleItem item = new VehicleItem();
        item.id = vehicle.Id;
        item.registrationNumber = vehicle.Name;
        item.make = vehicle.Make__c;
        item.model = vehicle.Model__c;
        item.year = input.year;
        item.color = vehicle.Color__c;
        item.chassisNumber = vehicle.Chassis_Number__c;
        return item;
    }
}
