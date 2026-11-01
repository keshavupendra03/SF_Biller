/**
 * Backs JobSlipPdf.page — a one-page A4 replica of the workshop's paper
 * job slip, headed with Workshop_Profile__c's name/address/phone. What
 * the ?id= param resolves to decides how much is filled in:
 *  - Job_Slip__c: the saved slip, everything filled — printed for the
 *    customer's signature after staff entered it on screen first.
 *  - Vehicle__c / Customer__c: a blank slip with only the customer (and
 *    vehicle) details prefilled, for staff to fill by hand and type into
 *    the Job Slip screen later.
 * The repairs table always pads out to the paper form's 15 rows so a
 * printed slip still has room for handwritten additions.
 */
public with sharing class JobSlipPdfController {

    @TestVisible
    private static final Integer TABLE_ROWS = 15;

    @TestVisible
    private static final String DEFAULT_TERMS =
        'Vehicles are stored, repaired and road-tested at the owner\'s risk. The workshop is not responsible for loss or damage caused by fire, theft, accident or other causes beyond its control.\n'
        + 'Please remove all valuables from the vehicle. The workshop is not responsible for articles left inside.\n'
        + 'Estimated cost and delivery time are approximate and may change once the vehicle is opened up; additional work is carried out only after your approval.\n'
        + 'Replaced parts can be collected at delivery unless they are claimed under warranty or insurance.\n'
        + 'Full payment is due at the time of delivery. Vehicles not collected within 7 days of completion may attract parking charges.';

    private static final List<String> SERVICE_TYPES = new List<String>{
        '1st Free Service', '2nd Free Service', '3rd Free Service', '4th Free Service',
        'Paid Service', 'Accidental Repair', 'Running Repair'
    };
    private static final Map<String, String> SERVICE_TYPE_SHORT = new Map<String, String>{
        '1st Free Service' => '1st FS', '2nd Free Service' => '2nd FS', '3rd Free Service' => '3rd FS',
        '4th Free Service' => '4th FS', 'Paid Service' => 'Paid Service',
        'Accidental Repair' => 'Acc. Rep.', 'Running Repair' => 'Running Rep.'
    };
    private static final List<String> FUEL_LEVELS = new List<String>{ 'E', '1/4', '1/2', '3/4', 'F' };
    private static final Map<String, String> FUEL_LABELS = new Map<String, String>{
        'E' => 'E', '1/4' => '¼', '1/2' => '½', '3/4' => '¾', 'F' => 'F'
    };
    private static final Map<String, String> ACCESSORY_LABELS = new Map<String, String>{
        'serviceBooklet' => 'Service Booklet', 'spareWheel' => 'Spare Wheel', 'jackAndHandle' => 'Jack & Handle',
        'toolKit' => 'Tool Kit', 'mats' => 'Mats', 'mudFlaps' => 'Mud Flaps', 'stereo' => 'Stereo',
        'clock' => 'Clock', 'cassetteCd' => 'Cassette / CD', 'sideBidding' => 'Side Bidding',
        'wheelCoverCap' => 'Wheel Cover / Cap', 'remote' => 'Remote', 'keyRing' => 'Key Ring'
    };

    public class Choice {
        public String label { get; set; }
        public Boolean selected { get; set; }
    }

    public class Accessory {
        public String label { get; set; }
        public String value { get; set; }
    }

    public class LineRow {
        public Integer rowNumber { get; set; }
        public String customerRequest { get; set; }
        public String observation { get; set; }
        public String labour { get; set; }
        public String spares { get; set; }
    }

    // ?format=html renders the same template as plain HTML for the in-app
    // preview; anything else renders the PDF.
    public String renderAs { get; private set; }
    public Boolean recordFound { get; private set; }
    public Boolean isBlank { get; private set; }

    public String workshopName { get; private set; }
    public String workshopAddress { get; private set; }
    public String workshopPhone { get; private set; }
    public String workshopEmail { get; private set; }
    public List<String> terms { get; private set; }

    public String slipNumber { get; private set; }
    public String slipDate { get; private set; }
    public String timeIn { get; private set; }

    public String customerName { get; private set; }
    public String customerAddress { get; private set; }
    public String customerPhone { get; private set; }
    public String customerEmail { get; private set; }

    public String registrationNumber { get; private set; }
    public String chassisNumber { get; private set; }
    public String makeModel { get; private set; }
    public String engineNumber { get; private set; }
    public String dateOfSale { get; private set; }
    public String currentKm { get; private set; }
    public String visitReason { get; private set; }

    public List<Choice> serviceTypes { get; private set; }
    public List<Choice> fuelLevels { get; private set; }
    public List<Accessory> accessories { get; private set; }
    public String dentsScratches { get; private set; }
    public String batteryMake { get; private set; }
    public String batteryNumber { get; private set; }
    public String tyreMake { get; private set; }
    public String tyreFrontRight { get; private set; }
    public String tyreFrontLeft { get; private set; }
    public String tyreRearRight { get; private set; }
    public String tyreRearLeft { get; private set; }

    public List<LineRow> lines { get; private set; }
    public String labourTotal { get; private set; }
    public String sparesTotal { get; private set; }

    public String serviceAdvisorName { get; private set; }
    public String serviceAdvisorMobile { get; private set; }
    public String promisedDelivery { get; private set; }
    public String totalCostEstimate { get; private set; }

    public JobSlipPdfController() {
        recordFound = false;
        isBlank = true;
        renderAs = ApexPages.currentPage().getParameters().get('format') == 'html' ? '' : 'pdf';
        lines = new List<LineRow>();
        accessories = new List<Accessory>();

        String rawId = ApexPages.currentPage().getParameters().get('id');
        Id recordId;
        try {
            recordId = String.isBlank(rawId) ? null : Id.valueOf(rawId);
        } catch (Exception e) {
            recordId = null;
        }
        if (recordId == null) {
            return;
        }

        loadWorkshopProfile();
        SObjectType type = recordId.getSObjectType();
        if (type == Job_Slip__c.SObjectType) {
            loadSlip(recordId);
        } else if (type == Vehicle__c.SObjectType) {
            Vehicle__c vehicle = [SELECT Customer__c FROM Vehicle__c WHERE Id = :recordId];
            loadCustomer(vehicle.Customer__c);
            loadVehicle(recordId);
            slipDate = formatDate(Date.today());
            recordFound = true;
        } else if (type == Customer__c.SObjectType) {
            loadCustomer(recordId);
            slipDate = formatDate(Date.today());
            recordFound = true;
        }
        if (serviceTypes == null) {
            buildChoices(null, null);
        }
        if (isBlank) {
            for (String key : JobSlipController.ACCESSORY_KEYS) {
                accessories.add(accessory(key, ''));
            }
            padLines();
        }
    }

    private void loadWorkshopProfile() {
        List<Workshop_Profile__c> profiles = [
            SELECT Name, Address__c, Phone__c, Email__c, Job_Slip_Terms__c FROM Workshop_Profile__c LIMIT 1
        ];
        String rawTerms = DEFAULT_TERMS;
        if (!profiles.isEmpty()) {
            workshopName = profiles[0].Name;
            workshopAddress = profiles[0].Address__c;
            workshopPhone = profiles[0].Phone__c;
            workshopEmail = profiles[0].Email__c;
            if (String.isNotBlank(profiles[0].Job_Slip_Terms__c)) {
                rawTerms = profiles[0].Job_Slip_Terms__c;
            }
        }
        terms = new List<String>();
        for (String line : rawTerms.split('\n')) {
            if (String.isNotBlank(line)) {
                terms.add(line.trim());
            }
        }
    }

    private void loadCustomer(Id customerId) {
        Customer__c customer = [SELECT Name, Address__c, Phone__c, Email__c FROM Customer__c WHERE Id = :customerId];
        customerName = customer.Name;
        customerAddress = customer.Address__c;
        customerPhone = customer.Phone__c;
        customerEmail = customer.Email__c;
    }

    private void loadVehicle(Id vehicleId) {
        Vehicle__c v = [
            SELECT Name, Make__c, Model__c, Chassis_Number__c, Engine_Number__c, Date_Of_Sale__c
            FROM Vehicle__c WHERE Id = :vehicleId
        ];
        registrationNumber = v.Name;
        chassisNumber = v.Chassis_Number__c;
        engineNumber = v.Engine_Number__c;
        dateOfSale = formatDate(v.Date_Of_Sale__c);
        List<String> parts = new List<String>();
        for (String part : new List<String>{ v.Make__c, v.Model__c }) {
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        makeModel = String.join(parts, ' ');
    }

    private void loadSlip(Id jobSlipId) {
        Job_Slip__c s = JobSlipController.loadSlip(jobSlipId);
        recordFound = true;
        isBlank = false;
        loadCustomer(s.Customer__c);
        if (s.Vehicle__c != null) {
            loadVehicle(s.Vehicle__c);
        }
        slipNumber = s.Name;
        slipDate = formatDate(s.Slip_Date__c);
        timeIn = formatTime(s.Time_In__c);
        currentKm = s.Current_Km__c == null ? null : s.Current_Km__c.format();
        visitReason = s.Visit_Reason__c;
        dentsScratches = s.Dents_Scratches__c;
        batteryMake = s.Battery_Make__c;
        batteryNumber = s.Battery_Number__c;
        tyreMake = s.Tyre_Make__c;
        tyreFrontRight = s.Tyre_Front_Right__c;
        tyreFrontLeft = s.Tyre_Front_Left__c;
        tyreRearRight = s.Tyre_Rear_Right__c;
        tyreRearLeft = s.Tyre_Rear_Left__c;
        serviceAdvisorName = s.Service_Advisor_Name__c;
        serviceAdvisorMobile = s.Service_Advisor_Mobile__c;
        promisedDelivery = s.Promised_Delivery__c;

        for (String key : JobSlipController.ACCESSORY_KEYS) {
            Boolean present = (Boolean) s.get(JobSlipController.ACCESSORY_FIELDS.get(key));
            accessories.add(accessory(key, present ? 'Yes' : 'No'));
        }

        Decimal labour = 0;
        Decimal spares = 0;
        Boolean anyAmount = false;
        for (Job_Slip_Line__c l : s.Lines__r) {
            LineRow row = new LineRow();
            row.rowNumber = lines.size() + 1;
            row.customerRequest = l.Customer_Request__c;
            row.observation = l.Observation__c;
            row.labour = formatAmount(l.Labour_Estimate__c);
            row.spares = formatAmount(l.Spares_Estimate__c);
            lines.add(row);
            if (l.Labour_Estimate__c != null) {
                labour += l.Labour_Estimate__c;
                anyAmount = true;
            }
            if (l.Spares_Estimate__c != null) {
                spares += l.Spares_Estimate__c;
                anyAmount = true;
            }
        }
        if (anyAmount) {
            labourTotal = formatAmount(labour);
            sparesTotal = formatAmount(spares);
        }
        totalCostEstimate = String.isNotBlank(s.Total_Cost_Estimate__c)
            ? s.Total_Cost_Estimate__c
            : (anyAmount ? 'Rs. ' + formatAmount(labour + spares) : null);
        padLines();
        buildChoices(s.Service_Type__c, s.Fuel_Level__c);
    }

    private void buildChoices(String serviceType, String fuelLevel) {
        serviceTypes = new List<Choice>();
        for (String value : SERVICE_TYPES) {
            serviceTypes.add(choice(SERVICE_TYPE_SHORT.get(value), value == serviceType));
        }
        fuelLevels = new List<Choice>();
        for (String value : FUEL_LEVELS) {
            fuelLevels.add(choice(FUEL_LABELS.get(value), value == fuelLevel));
        }
    }

    private void padLines() {
        while (lines.size() < TABLE_ROWS) {
            LineRow row = new LineRow();
            row.rowNumber = lines.size() + 1;
            lines.add(row);
        }
    }

    private static Choice choice(String label, Boolean selected) {
        Choice c = new Choice();
        c.label = label;
        c.selected = selected;
        return c;
    }

    private static Accessory accessory(String key, String value) {
        Accessory a = new Accessory();
        a.label = ACCESSORY_LABELS.get(key);
        a.value = value;
        return a;
    }

    @TestVisible
    private static String formatDate(Date d) {
        if (d == null) {
            return null;
        }
        return String.valueOf(d.day()).leftPad(2, '0') + '/' + String.valueOf(d.month()).leftPad(2, '0') + '/' + d.year();
    }

    @TestVisible
    private static String formatTime(Time t) {
        if (t == null) {
            return null;
        }
        Integer hour12 = Math.mod(t.hour(), 12) == 0 ? 12 : Math.mod(t.hour(), 12);
        return hour12 + ':' + String.valueOf(t.minute()).leftPad(2, '0') + (t.hour() < 12 ? ' AM' : ' PM');
    }

    private static String formatAmount(Decimal amount) {
        return amount == null ? null : amount.setScale(0, RoundingMode.HALF_UP).format();
    }
}
