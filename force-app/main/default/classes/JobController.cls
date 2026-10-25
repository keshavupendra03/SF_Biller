/**
 * The single Apex entry point for the Jobs Kanban LWC (architecture.md §B).
 * The board's columns are driven entirely by Job_Status_Stage__c records
 * (admin-editable, ordered by Sort_Order__c) rather than a fixed picklist —
 * adding/reordering/retiring a stage is a data change, not a deploy.
 */
public with sharing class JobController {

    public class JobControllerException extends Exception {}

    public class StageInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Integer sortOrder { get; set; }
    }

    public class JobCard {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String jobNumber { get; set; }
        @AuraEnabled public Id stageId { get; set; }
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String customerPhone { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public String vehicleLabel { get; set; }
        @AuraEnabled public Id surveyorId { get; set; }
        @AuraEnabled public String surveyorName { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public List<Id> mechanicIds { get; set; }
        @AuraEnabled public String mechanicNames { get; set; }
    }

    public class BoardData {
        @AuraEnabled public List<StageInfo> stages { get; set; }
        @AuraEnabled public List<JobCard> jobs { get; set; }
    }

    public class JobDetail {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String jobNumber { get; set; }
        @AuraEnabled public Date createdDate { get; set; }
        @AuraEnabled public Id stageId { get; set; }
        @AuraEnabled public String stageName { get; set; }
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String customerPhone { get; set; }
        @AuraEnabled public String customerAddress { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public String vehicleRegistrationNumber { get; set; }
        @AuraEnabled public String vehicleMakeModel { get; set; }
        @AuraEnabled public Integer vehicleYear { get; set; }
        @AuraEnabled public String vehicleColor { get; set; }
        @AuraEnabled public Id surveyorId { get; set; }
        @AuraEnabled public String surveyorName { get; set; }
        @AuraEnabled public String mechanicNames { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public List<CustomerController.DocumentItem> bills { get; set; }
        @AuraEnabled public List<CustomerController.DocumentItem> estimates { get; set; }
    }

    public class PersonOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
    }

    public class VehicleOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String registrationNumber { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public Integer year { get; set; }
    }

    public class NewVehicleInput {
        @AuraEnabled public String registrationNumber { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public Integer year { get; set; }
        @AuraEnabled public String color { get; set; }
        @AuraEnabled public String chassisNumber { get; set; }
    }

    public class CreateJobRequest {
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public NewVehicleInput newVehicle { get; set; }
        @AuraEnabled public Id surveyorId { get; set; }
        @AuraEnabled public Id stageId { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public List<Id> mechanicIds { get; set; }
    }

    @AuraEnabled
    public static BoardData getBoardData(String searchTerm) {
        BoardData data = new BoardData();
        data.stages = new List<StageInfo>();
        for (Job_Status_Stage__c stage : [
            SELECT Id, Name, Sort_Order__c
            FROM Job_Status_Stage__c
            WHERE Is_Active__c = true
            ORDER BY Sort_Order__c
        ]) {
            StageInfo info = new StageInfo();
            info.id = stage.Id;
            info.name = stage.Name;
            info.sortOrder = stage.Sort_Order__c == null ? 0 : stage.Sort_Order__c.intValue();
            data.stages.add(info);
        }

        Map<Id, List<String>> mechanicNamesByJob = new Map<Id, List<String>>();
        Map<Id, List<Id>> mechanicIdsByJob = new Map<Id, List<Id>>();
        for (Job_Mechanic__c jm : [
            SELECT Job__c, Mechanic__c, Mechanic__r.Name FROM Job_Mechanic__c
        ]) {
            if (!mechanicNamesByJob.containsKey(jm.Job__c)) {
                mechanicNamesByJob.put(jm.Job__c, new List<String>());
                mechanicIdsByJob.put(jm.Job__c, new List<Id>());
            }
            mechanicNamesByJob.get(jm.Job__c).add(jm.Mechanic__r.Name);
            mechanicIdsByJob.get(jm.Job__c).add(jm.Mechanic__c);
        }

        String term = '%' + String.escapeSingleQuotes(String.isBlank(searchTerm) ? '' : searchTerm) + '%';
        List<Job__c> jobs = String.isBlank(searchTerm)
            ? [
                SELECT Name, Job_Status_Stage__c, Customer__c, Customer__r.Name, Customer__r.Phone__c,
                       Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                       Surveyor__c, Surveyor__r.Name, Notes__c
                FROM Job__c
                ORDER BY CreatedDate DESC
            ]
            : [
                SELECT Name, Job_Status_Stage__c, Customer__c, Customer__r.Name, Customer__r.Phone__c,
                       Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                       Surveyor__c, Surveyor__r.Name, Notes__c
                FROM Job__c
                WHERE Customer__r.Name LIKE :term OR Customer__r.Phone__c LIKE :term OR Vehicle__r.Name LIKE :term
                ORDER BY CreatedDate DESC
            ];

        data.jobs = new List<JobCard>();
        for (Job__c job : jobs) {
            data.jobs.add(buildCard(
                job,
                mechanicIdsByJob.containsKey(job.Id) ? mechanicIdsByJob.get(job.Id) : new List<Id>(),
                mechanicNamesByJob.containsKey(job.Id) ? mechanicNamesByJob.get(job.Id) : new List<String>()
            ));
        }
        return data;
    }

    /**
     * Backs the Job Detail LWC (architecture.md §B) — reachable from both
     * the Jobs board and a customer's Jobs list. Bills/estimates reuse
     * CustomerController.DocumentItem so the detail screen's list rows
     * match the ones on Customer Detail exactly.
     */
    @AuraEnabled
    public static JobDetail getJobDetail(Id jobId) {
        if (jobId == null) {
            throw new JobControllerException('A job is required.');
        }
        Job__c job = [
            SELECT Name, CreatedDate, Job_Status_Stage__c, Job_Status_Stage__r.Name,
                   Customer__c, Customer__r.Name, Customer__r.Phone__c, Customer__r.Address__c,
                   Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                   Vehicle__r.Year__c, Vehicle__r.Color__c,
                   Surveyor__c, Surveyor__r.Name, Notes__c
            FROM Job__c
            WHERE Id = :jobId
        ];

        JobDetail detail = new JobDetail();
        detail.id = job.Id;
        detail.jobNumber = job.Name;
        detail.createdDate = job.CreatedDate.date();
        detail.stageId = job.Job_Status_Stage__c;
        detail.stageName = job.Job_Status_Stage__c != null ? job.Job_Status_Stage__r.Name : null;
        detail.customerId = job.Customer__c;
        detail.customerName = job.Customer__r.Name;
        detail.customerPhone = job.Customer__r.Phone__c;
        detail.customerAddress = job.Customer__r.Address__c;
        detail.vehicleId = job.Vehicle__c;
        if (job.Vehicle__c != null) {
            detail.vehicleRegistrationNumber = job.Vehicle__r.Name;
            detail.vehicleMakeModel = buildVehicleMakeModel(job.Vehicle__r.Make__c, job.Vehicle__r.Model__c);
            detail.vehicleYear = job.Vehicle__r.Year__c == null ? null : job.Vehicle__r.Year__c.intValue();
            detail.vehicleColor = job.Vehicle__r.Color__c;
        }
        detail.surveyorId = job.Surveyor__c;
        detail.surveyorName = job.Surveyor__c != null ? job.Surveyor__r.Name : null;
        detail.notes = job.Notes__c;

        List<String> mechanicNames = new List<String>();
        for (Job_Mechanic__c jm : [SELECT Mechanic__r.Name FROM Job_Mechanic__c WHERE Job__c = :jobId]) {
            mechanicNames.add(jm.Mechanic__r.Name);
        }
        detail.mechanicNames = mechanicNames.isEmpty() ? null : String.join(mechanicNames, ', ');

        detail.bills = new List<CustomerController.DocumentItem>();
        for (Bill__c b : [
            SELECT Invoice_Number__c, Status__c, Total_Amount__c, Bill_Date__c
            FROM Bill__c
            WHERE Job__c = :jobId AND Is_Latest_Version__c = true
            ORDER BY CreatedDate DESC
        ]) {
            CustomerController.DocumentItem item = new CustomerController.DocumentItem();
            item.id = b.Id;
            item.documentNumber = b.Invoice_Number__c;
            item.status = b.Status__c;
            item.totalAmount = b.Total_Amount__c;
            item.documentDate = b.Bill_Date__c;
            detail.bills.add(item);
        }

        detail.estimates = new List<CustomerController.DocumentItem>();
        for (Estimate__c e : [
            SELECT Name, Status__c, Total_Amount__c, Estimate_Date__c
            FROM Estimate__c
            WHERE Job__c = :jobId AND Is_Latest_Version__c = true
            ORDER BY CreatedDate DESC
        ]) {
            CustomerController.DocumentItem item = new CustomerController.DocumentItem();
            item.id = e.Id;
            item.documentNumber = e.Name;
            item.status = e.Status__c;
            item.totalAmount = e.Total_Amount__c;
            item.documentDate = e.Estimate_Date__c;
            detail.estimates.add(item);
        }

        return detail;
    }

    @AuraEnabled
    public static List<VehicleOption> searchVehicles(Id customerId, String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<VehicleOption> results = new List<VehicleOption>();
        List<Vehicle__c> vehicles = String.isBlank(searchTerm)
            ? [
                SELECT Name, Make__c, Model__c, Year__c FROM Vehicle__c
                WHERE Customer__c = :customerId
                ORDER BY Name
                LIMIT 25
            ]
            : [
                SELECT Name, Make__c, Model__c, Year__c FROM Vehicle__c
                WHERE Customer__c = :customerId AND Name LIKE :term
                ORDER BY Name
                LIMIT 25
            ];
        for (Vehicle__c v : vehicles) {
            VehicleOption option = new VehicleOption();
            option.id = v.Id;
            option.registrationNumber = v.Name;
            option.make = v.Make__c;
            option.model = v.Model__c;
            option.year = v.Year__c == null ? null : v.Year__c.intValue();
            results.add(option);
        }
        return results;
    }

    @AuraEnabled
    public static List<PersonOption> getActiveMechanics() {
        List<PersonOption> results = new List<PersonOption>();
        for (Mechanic__c m : [SELECT Name, Phone__c FROM Mechanic__c WHERE Is_Active__c = true ORDER BY Name]) {
            PersonOption option = new PersonOption();
            option.id = m.Id;
            option.name = m.Name;
            option.phone = m.Phone__c;
            results.add(option);
        }
        return results;
    }

    @AuraEnabled
    public static List<PersonOption> getActiveSurveyors() {
        List<PersonOption> results = new List<PersonOption>();
        for (Surveyor__c s : [SELECT Name, Phone__c FROM Surveyor__c WHERE Is_Active__c = true ORDER BY Name]) {
            PersonOption option = new PersonOption();
            option.id = s.Id;
            option.name = s.Name;
            option.phone = s.Phone__c;
            results.add(option);
        }
        return results;
    }

    @AuraEnabled
    public static JobCard createJob(CreateJobRequest request) {
        if (request == null || request.customerId == null) {
            throw new JobControllerException('A customer is required.');
        }
        if (request.vehicleId == null && (request.newVehicle == null || String.isBlank(request.newVehicle.registrationNumber))) {
            throw new JobControllerException('A vehicle (existing or new, with a registration number) is required.');
        }

        Id vehicleId = request.vehicleId;
        if (vehicleId == null) {
            Vehicle__c vehicle = new Vehicle__c(
                Name = request.newVehicle.registrationNumber,
                Customer__c = request.customerId,
                Make__c = request.newVehicle.make,
                Model__c = request.newVehicle.model,
                Year__c = request.newVehicle.year,
                Color__c = request.newVehicle.color,
                Chassis_Number__c = request.newVehicle.chassisNumber
            );
            insert vehicle;
            VehicleMakeModelService.rememberIfNew(vehicle.Make__c, vehicle.Model__c);
            vehicleId = vehicle.Id;
        }

        Id stageId = request.stageId != null ? request.stageId : firstActiveStageId();
        if (stageId == null) {
            throw new JobControllerException('No active Job_Status_Stage__c records exist — seed at least one before creating a job.');
        }

        Job__c job = new Job__c(
            Customer__c = request.customerId,
            Vehicle__c = vehicleId,
            Surveyor__c = request.surveyorId,
            Job_Status_Stage__c = stageId,
            Notes__c = request.notes
        );
        insert job;

        if (request.mechanicIds != null && !request.mechanicIds.isEmpty()) {
            List<Job_Mechanic__c> links = new List<Job_Mechanic__c>();
            for (Id mechanicId : request.mechanicIds) {
                links.add(new Job_Mechanic__c(Job__c = job.Id, Mechanic__c = mechanicId));
            }
            insert links;
        }

        return cardFor(job.Id);
    }

    @AuraEnabled
    public static void moveJob(Id jobId, Id newStageId) {
        if (jobId == null || newStageId == null) {
            throw new JobControllerException('Both a job and a target stage are required.');
        }
        update new Job__c(Id = jobId, Job_Status_Stage__c = newStageId);
    }

    /**
     * Replaces a job's mechanic assignments wholesale with mechanicIds —
     * simplest correct option for a small per-job team size; adds the
     * newly-checked ones and removes the unchecked ones in one call rather
     * than the caller tracking an add/remove diff itself.
     */
    @AuraEnabled
    public static void assignMechanics(Id jobId, List<Id> mechanicIds) {
        if (jobId == null) {
            throw new JobControllerException('A job is required.');
        }
        Set<Id> desired = new Set<Id>(mechanicIds == null ? new List<Id>() : mechanicIds);

        Map<Id, Job_Mechanic__c> existingByMechanic = new Map<Id, Job_Mechanic__c>();
        for (Job_Mechanic__c jm : [SELECT Id, Mechanic__c FROM Job_Mechanic__c WHERE Job__c = :jobId]) {
            existingByMechanic.put(jm.Mechanic__c, jm);
        }

        List<Job_Mechanic__c> toInsert = new List<Job_Mechanic__c>();
        for (Id mechanicId : desired) {
            if (!existingByMechanic.containsKey(mechanicId)) {
                toInsert.add(new Job_Mechanic__c(Job__c = jobId, Mechanic__c = mechanicId));
            }
        }

        List<Job_Mechanic__c> toDelete = new List<Job_Mechanic__c>();
        for (Id mechanicId : existingByMechanic.keySet()) {
            if (!desired.contains(mechanicId)) {
                toDelete.add(existingByMechanic.get(mechanicId));
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    private static Id firstActiveStageId() {
        List<Job_Status_Stage__c> stages = [
            SELECT Id FROM Job_Status_Stage__c WHERE Is_Active__c = true ORDER BY Sort_Order__c LIMIT 1
        ];
        return stages.isEmpty() ? null : stages[0].Id;
    }

    private static String buildVehicleMakeModel(String make, String model) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(make)) {
            parts.add(make);
        }
        if (String.isNotBlank(model)) {
            parts.add(model);
        }
        return parts.isEmpty() ? null : String.join(parts, ' ');
    }

    private static String buildVehicleLabel(Vehicle__c vehicle) {
        if (vehicle == null) {
            return null;
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(vehicle.Name)) {
            parts.add(vehicle.Name);
        }
        List<String> makeModel = new List<String>();
        if (String.isNotBlank(vehicle.Make__c)) {
            makeModel.add(vehicle.Make__c);
        }
        if (String.isNotBlank(vehicle.Model__c)) {
            makeModel.add(vehicle.Model__c);
        }
        if (!makeModel.isEmpty()) {
            parts.add(String.join(makeModel, ' '));
        }
        return parts.isEmpty() ? null : String.join(parts, ' — ');
    }

    private static JobCard cardFor(Id jobId) {
        Job__c job = [
            SELECT Name, Job_Status_Stage__c, Customer__c, Customer__r.Name, Customer__r.Phone__c,
                   Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                   Surveyor__c, Surveyor__r.Name, Notes__c
            FROM Job__c
            WHERE Id = :jobId
        ];

        List<String> mechanicNames = new List<String>();
        List<Id> mechanicIds = new List<Id>();
        for (Job_Mechanic__c jm : [
            SELECT Mechanic__c, Mechanic__r.Name FROM Job_Mechanic__c WHERE Job__c = :jobId
        ]) {
            mechanicIds.add(jm.Mechanic__c);
            mechanicNames.add(jm.Mechanic__r.Name);
        }

        return buildCard(job, mechanicIds, mechanicNames);
    }

    private static JobCard buildCard(Job__c job, List<Id> mechanicIds, List<String> mechanicNames) {
        JobCard card = new JobCard();
        card.id = job.Id;
        card.jobNumber = job.Name;
        card.stageId = job.Job_Status_Stage__c;
        card.customerId = job.Customer__c;
        card.customerName = job.Customer__r.Name;
        card.customerPhone = job.Customer__r.Phone__c;
        card.vehicleId = job.Vehicle__c;
        card.vehicleLabel = buildVehicleLabel(job.Vehicle__r);
        card.surveyorId = job.Surveyor__c;
        card.surveyorName = job.Surveyor__c != null ? job.Surveyor__r.Name : null;
        card.notes = job.Notes__c;
        card.mechanicIds = mechanicIds;
        card.mechanicNames = mechanicNames.isEmpty() ? null : String.join(mechanicNames, ', ');
        return card;
    }
}
