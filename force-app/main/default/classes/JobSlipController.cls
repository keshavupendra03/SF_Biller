/**
 * The single Apex entry point for the Job Slip LWC — the paper intake
 * sheet a workshop fills when a vehicle arrives (customer's complaints,
 * fuel level, accessories present, tyres/battery, promised delivery).
 * Works in either order: staff can print a blank slip from Customer
 * Detail, fill it by hand and type it in later, or fill it here first and
 * print it for the customer's signature (JobSlipPdf.page renders both).
 *
 * Engine number, date of sale and chassis number are facts about the
 * vehicle, not this visit, so they live on Vehicle__c and saveJobSlip
 * writes them back there — the next slip for the same vehicle (and the
 * blank one printed for it) starts with them already filled.
 */
public with sharing class JobSlipController {

    public class JobSlipControllerException extends Exception {}

    // Printed/rendered in this order on both the screen and the slip,
    // matching the paper form's checklist column.
    public static final List<String> ACCESSORY_KEYS = new List<String>{
        'serviceBooklet', 'spareWheel', 'jackAndHandle', 'toolKit', 'mats', 'mudFlaps', 'stereo',
        'clock', 'cassetteCd', 'sideBidding', 'wheelCoverCap', 'remote', 'keyRing'
    };

    public static final Map<String, SObjectField> ACCESSORY_FIELDS = new Map<String, SObjectField>{
        'serviceBooklet' => Job_Slip__c.Service_Booklet__c,
        'spareWheel' => Job_Slip__c.Spare_Wheel__c,
        'jackAndHandle' => Job_Slip__c.Jack_And_Handle__c,
        'toolKit' => Job_Slip__c.Tool_Kit__c,
        'mats' => Job_Slip__c.Mats__c,
        'mudFlaps' => Job_Slip__c.Mud_Flaps__c,
        'stereo' => Job_Slip__c.Stereo__c,
        'clock' => Job_Slip__c.Clock__c,
        'cassetteCd' => Job_Slip__c.Cassette_CD__c,
        'sideBidding' => Job_Slip__c.Side_Bidding__c,
        'wheelCoverCap' => Job_Slip__c.Wheel_Cover_Cap__c,
        'remote' => Job_Slip__c.Remote__c,
        'keyRing' => Job_Slip__c.Key_Ring__c
    };

    public class JobSlipLine {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String customerRequest { get; set; }
        @AuraEnabled public String observation { get; set; }
        @AuraEnabled public Decimal labourEstimate { get; set; }
        @AuraEnabled public Decimal sparesEstimate { get; set; }
    }

    public class JobSlipData {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String slipNumber { get; set; }
        @AuraEnabled public Id workshopProfileId { get; set; }
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public CustomerController.NewVehicleInput newVehicle { get; set; }
        @AuraEnabled public Date slipDate { get; set; }
        // "HH:mm" (or the "HH:mm:ss.SSS" lightning-input type="time" sends).
        @AuraEnabled public String timeIn { get; set; }
        @AuraEnabled public Integer currentKm { get; set; }
        @AuraEnabled public String visitReason { get; set; }
        @AuraEnabled public String fuelLevel { get; set; }
        // Keys from ACCESSORY_KEYS for every accessory present in the vehicle.
        @AuraEnabled public List<String> accessories { get; set; }
        @AuraEnabled public String dentsScratches { get; set; }
        @AuraEnabled public String batteryMake { get; set; }
        @AuraEnabled public String batteryNumber { get; set; }
        @AuraEnabled public String tyreMake { get; set; }
        @AuraEnabled public String tyreFrontRight { get; set; }
        @AuraEnabled public String tyreFrontLeft { get; set; }
        @AuraEnabled public String tyreRearRight { get; set; }
        @AuraEnabled public String tyreRearLeft { get; set; }
        @AuraEnabled public String serviceAdvisorName { get; set; }
        @AuraEnabled public String serviceAdvisorMobile { get; set; }
        @AuraEnabled public String promisedDelivery { get; set; }
        @AuraEnabled public String totalCostEstimate { get; set; }
        // Written back to the selected Vehicle__c on save.
        @AuraEnabled public String chassisNumber { get; set; }
        @AuraEnabled public String engineNumber { get; set; }
        @AuraEnabled public Date dateOfSale { get; set; }
        @AuraEnabled public List<JobSlipLine> lines { get; set; }
    }

    public class CustomerInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String address { get; set; }
    }

    public class VehicleOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String registrationNumber { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String chassisNumber { get; set; }
        @AuraEnabled public String engineNumber { get; set; }
        @AuraEnabled public Date dateOfSale { get; set; }
        // From this vehicle's most recent slip, so a new slip doesn't make
        // staff re-type a battery/tyre make that hasn't changed.
        @AuraEnabled public String lastBatteryMake { get; set; }
        @AuraEnabled public String lastBatteryNumber { get; set; }
        @AuraEnabled public String lastTyreMake { get; set; }
    }

    public class JobSlipForm {
        @AuraEnabled public JobSlipData slip { get; set; }
        @AuraEnabled public CustomerInfo customer { get; set; }
        @AuraEnabled public List<VehicleOption> vehicles { get; set; }
    }

    /**
     * Everything the Job Slip screen needs in one call: the existing slip
     * when jobSlipId is given, otherwise a new one for customerId
     * prefilled with today's date, the current time, the signed-in user as
     * service advisor, and vehicleId (or the customer's newest vehicle).
     */
    @AuraEnabled
    public static JobSlipForm getJobSlipForm(Id jobSlipId, Id customerId, Id vehicleId) {
        JobSlipForm form = new JobSlipForm();
        if (jobSlipId != null) {
            form.slip = toData(loadSlip(jobSlipId));
            customerId = form.slip.customerId;
        } else {
            if (customerId == null) {
                throw new JobSlipControllerException('A customer is required.');
            }
            form.slip = newSlipDefaults(customerId);
        }

        Customer__c customer = [
            SELECT Name, Phone__c, Email__c, Address__c FROM Customer__c WHERE Id = :customerId
        ];
        form.customer = new CustomerInfo();
        form.customer.id = customer.Id;
        form.customer.name = customer.Name;
        form.customer.phone = customer.Phone__c;
        form.customer.email = customer.Email__c;
        form.customer.address = customer.Address__c;

        form.vehicles = loadVehicleOptions(customerId);
        if (jobSlipId == null && !form.vehicles.isEmpty()) {
            VehicleOption selected = form.vehicles[0];
            for (VehicleOption option : form.vehicles) {
                if (option.id == vehicleId) {
                    selected = option;
                }
            }
            applyVehicleDefaults(form.slip, selected);
        }
        return form;
    }

    @AuraEnabled
    public static Id saveJobSlip(JobSlipData input) {
        if (input == null || input.customerId == null) {
            throw new JobSlipControllerException('A customer is required.');
        }
        Id vehicleId = resolveVehicle(input);

        update new Vehicle__c(
            Id = vehicleId,
            Chassis_Number__c = input.chassisNumber,
            Engine_Number__c = input.engineNumber,
            Date_Of_Sale__c = input.dateOfSale
        );

        Job_Slip__c slip = new Job_Slip__c(
            Id = input.id,
            Workshop_Profile__c = input.workshopProfileId != null ? input.workshopProfileId : WorkshopProfileService.primaryId(),
            Vehicle__c = vehicleId,
            Slip_Date__c = input.slipDate != null ? input.slipDate : Date.today(),
            Time_In__c = parseTime(input.timeIn),
            Current_Km__c = input.currentKm,
            Visit_Reason__c = input.visitReason,
            Fuel_Level__c = blankToNull(input.fuelLevel),
            Dents_Scratches__c = input.dentsScratches,
            Battery_Make__c = input.batteryMake,
            Battery_Number__c = input.batteryNumber,
            Tyre_Make__c = input.tyreMake,
            Tyre_Front_Right__c = input.tyreFrontRight,
            Tyre_Front_Left__c = input.tyreFrontLeft,
            Tyre_Rear_Right__c = input.tyreRearRight,
            Tyre_Rear_Left__c = input.tyreRearLeft,
            Service_Advisor_Name__c = input.serviceAdvisorName,
            Service_Advisor_Mobile__c = input.serviceAdvisorMobile,
            Promised_Delivery__c = input.promisedDelivery,
            Total_Cost_Estimate__c = input.totalCostEstimate
        );
        if (input.id == null) {
            slip.Customer__c = input.customerId;
        }
        Set<String> present = new Set<String>(input.accessories == null ? new List<String>() : input.accessories);
        for (String key : ACCESSORY_KEYS) {
            slip.put(ACCESSORY_FIELDS.get(key), present.contains(key));
        }
        upsert slip;

        saveLines(slip.Id, input.lines);
        return slip.Id;
    }

    private static Id resolveVehicle(JobSlipData input) {
        if (input.vehicleId != null) {
            Vehicle__c vehicle = [SELECT Customer__c FROM Vehicle__c WHERE Id = :input.vehicleId];
            if (vehicle.Customer__c != input.customerId) {
                throw new JobSlipControllerException('That vehicle belongs to a different customer.');
            }
            return vehicle.Id;
        }
        if (input.newVehicle != null && String.isNotBlank(input.newVehicle.registrationNumber)) {
            return CustomerController.createVehicle(input.customerId, input.newVehicle).id;
        }
        throw new JobSlipControllerException('Select the vehicle, or add a new one with its registration number.');
    }

    // Rows with nothing typed in are dropped rather than saved as empty
    // records; rows that came from the server but are no longer in the
    // list are deleted.
    private static void saveLines(Id slipId, List<JobSlipLine> lines) {
        Map<Id, Job_Slip_Line__c> existing = new Map<Id, Job_Slip_Line__c>(
            [SELECT Id FROM Job_Slip_Line__c WHERE Job_Slip__c = :slipId]
        );
        List<Job_Slip_Line__c> toUpsert = new List<Job_Slip_Line__c>();
        Integer sortOrder = 1;
        for (JobSlipLine line : lines == null ? new List<JobSlipLine>() : lines) {
            if (String.isBlank(line.customerRequest) && String.isBlank(line.observation)
                    && line.labourEstimate == null && line.sparesEstimate == null) {
                continue;
            }
            Job_Slip_Line__c record = new Job_Slip_Line__c(
                Customer_Request__c = line.customerRequest,
                Observation__c = line.observation,
                Labour_Estimate__c = line.labourEstimate,
                Spares_Estimate__c = line.sparesEstimate,
                Sort_Order__c = sortOrder++
            );
            if (line.id != null && existing.containsKey(line.id)) {
                record.Id = line.id;
                existing.remove(line.id);
            } else {
                record.Job_Slip__c = slipId;
            }
            toUpsert.add(record);
        }
        if (!existing.isEmpty()) {
            delete existing.values();
        }
        upsert toUpsert;
    }

    public static Job_Slip__c loadSlip(Id jobSlipId) {
        return [
            SELECT Id, Name, Workshop_Profile__c, Customer__c, Vehicle__c, Slip_Date__c, Time_In__c, Current_Km__c,
                   Visit_Reason__c, Fuel_Level__c,
                   Service_Booklet__c, Spare_Wheel__c, Jack_And_Handle__c, Tool_Kit__c, Mats__c,
                   Mud_Flaps__c, Stereo__c, Clock__c, Cassette_CD__c, Side_Bidding__c,
                   Wheel_Cover_Cap__c, Remote__c, Key_Ring__c,
                   Dents_Scratches__c, Battery_Make__c, Battery_Number__c, Tyre_Make__c,
                   Tyre_Front_Right__c, Tyre_Front_Left__c, Tyre_Rear_Right__c, Tyre_Rear_Left__c,
                   Service_Advisor_Name__c, Service_Advisor_Mobile__c, Promised_Delivery__c,
                   Total_Cost_Estimate__c,
                   Vehicle__r.Chassis_Number__c, Vehicle__r.Engine_Number__c, Vehicle__r.Date_Of_Sale__c,
                   (SELECT Id, Customer_Request__c, Observation__c, Labour_Estimate__c, Spares_Estimate__c
                    FROM Lines__r ORDER BY Sort_Order__c, CreatedDate)
            FROM Job_Slip__c
            WHERE Id = :jobSlipId
        ];
    }

    private static JobSlipData toData(Job_Slip__c s) {
        JobSlipData data = new JobSlipData();
        data.id = s.Id;
        data.slipNumber = s.Name;
        data.workshopProfileId = s.Workshop_Profile__c;
        data.customerId = s.Customer__c;
        data.vehicleId = s.Vehicle__c;
        data.slipDate = s.Slip_Date__c;
        data.timeIn = s.Time_In__c == null
            ? null
            : String.valueOf(s.Time_In__c.hour()).leftPad(2, '0') + ':' + String.valueOf(s.Time_In__c.minute()).leftPad(2, '0');
        data.currentKm = s.Current_Km__c == null ? null : s.Current_Km__c.intValue();
        data.visitReason = s.Visit_Reason__c;
        data.fuelLevel = s.Fuel_Level__c;
        data.accessories = new List<String>();
        for (String key : ACCESSORY_KEYS) {
            if ((Boolean) s.get(ACCESSORY_FIELDS.get(key))) {
                data.accessories.add(key);
            }
        }
        data.dentsScratches = s.Dents_Scratches__c;
        data.batteryMake = s.Battery_Make__c;
        data.batteryNumber = s.Battery_Number__c;
        data.tyreMake = s.Tyre_Make__c;
        data.tyreFrontRight = s.Tyre_Front_Right__c;
        data.tyreFrontLeft = s.Tyre_Front_Left__c;
        data.tyreRearRight = s.Tyre_Rear_Right__c;
        data.tyreRearLeft = s.Tyre_Rear_Left__c;
        data.serviceAdvisorName = s.Service_Advisor_Name__c;
        data.serviceAdvisorMobile = s.Service_Advisor_Mobile__c;
        data.promisedDelivery = s.Promised_Delivery__c;
        data.totalCostEstimate = s.Total_Cost_Estimate__c;
        if (s.Vehicle__c != null) {
            data.chassisNumber = s.Vehicle__r.Chassis_Number__c;
            data.engineNumber = s.Vehicle__r.Engine_Number__c;
            data.dateOfSale = s.Vehicle__r.Date_Of_Sale__c;
        }
        data.lines = new List<JobSlipLine>();
        for (Job_Slip_Line__c l : s.Lines__r) {
            JobSlipLine line = new JobSlipLine();
            line.id = l.Id;
            line.customerRequest = l.Customer_Request__c;
            line.observation = l.Observation__c;
            line.labourEstimate = l.Labour_Estimate__c;
            line.sparesEstimate = l.Spares_Estimate__c;
            data.lines.add(line);
        }
        return data;
    }

    private static JobSlipData newSlipDefaults(Id customerId) {
        JobSlipData data = new JobSlipData();
        data.customerId = customerId;
        data.slipDate = Date.today();
        // Datetime.format() renders in the running user's own time zone.
        data.timeIn = Datetime.now().format('HH:mm');
        data.accessories = new List<String>();
        data.lines = new List<JobSlipLine>();
        User me = [SELECT Name, MobilePhone FROM User WHERE Id = :UserInfo.getUserId()];
        data.serviceAdvisorName = me.Name;
        data.serviceAdvisorMobile = me.MobilePhone;
        return data;
    }

    private static void applyVehicleDefaults(JobSlipData data, VehicleOption vehicle) {
        data.vehicleId = vehicle.id;
        data.chassisNumber = vehicle.chassisNumber;
        data.engineNumber = vehicle.engineNumber;
        data.dateOfSale = vehicle.dateOfSale;
        data.batteryMake = vehicle.lastBatteryMake;
        data.batteryNumber = vehicle.lastBatteryNumber;
        data.tyreMake = vehicle.lastTyreMake;
    }

    private static List<VehicleOption> loadVehicleOptions(Id customerId) {
        List<VehicleOption> options = new List<VehicleOption>();
        for (Vehicle__c v : [
            SELECT Name, Make__c, Model__c, Chassis_Number__c, Engine_Number__c, Date_Of_Sale__c,
                   (SELECT Battery_Make__c, Battery_Number__c, Tyre_Make__c
                    FROM Job_Slips__r ORDER BY Slip_Date__c DESC, CreatedDate DESC LIMIT 1)
            FROM Vehicle__c
            WHERE Customer__c = :customerId
            ORDER BY CreatedDate DESC
        ]) {
            VehicleOption option = new VehicleOption();
            option.id = v.Id;
            option.registrationNumber = v.Name;
            option.make = v.Make__c;
            option.model = v.Model__c;
            option.chassisNumber = v.Chassis_Number__c;
            option.engineNumber = v.Engine_Number__c;
            option.dateOfSale = v.Date_Of_Sale__c;
            if (!v.Job_Slips__r.isEmpty()) {
                option.lastBatteryMake = v.Job_Slips__r[0].Battery_Make__c;
                option.lastBatteryNumber = v.Job_Slips__r[0].Battery_Number__c;
                option.lastTyreMake = v.Job_Slips__r[0].Tyre_Make__c;
            }
            options.add(option);
        }
        return options;
    }

    @TestVisible
    private static Time parseTime(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        List<String> parts = value.split(':');
        if (parts.size() < 2 || !parts[0].isNumeric() || !parts[1].left(2).isNumeric()) {
            throw new JobSlipControllerException('Time In must look like 10:15.');
        }
        return Time.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1].left(2)), 0, 0);
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value;
    }
}
