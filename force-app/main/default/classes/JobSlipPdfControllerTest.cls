@isTest
private class JobSlipPdfControllerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Sanghi Motors', Address__c = 'AB Road, Indore', Phone__c = '0731-1234567');
    }

    private static Customer__c insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Deepak Sharma', Phone__c = '9425012345', Address__c = 'Vijay Nagar, Indore');
        insert customer;
        return customer;
    }

    private static JobSlipPdfController render(Id recordId) {
        PageReference page = Page.JobSlipPdf;
        page.getParameters().put('id', recordId);
        Test.setCurrentPage(page);
        return new JobSlipPdfController();
    }

    @isTest
    static void savedSlip_rendersEverythingAndPadsTableTo15Rows() {
        Customer__c customer = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(
            Name = 'MP70ZD3946', Customer__c = customer.Id, Make__c = 'Tata', Model__c = 'Punch',
            Chassis_Number__c = 'MAT867015SPJB9663', Date_Of_Sale__c = Date.newInstance(2025, 10, 22)
        );
        insert vehicle;
        Job_Slip__c slip = new Job_Slip__c(
            Customer__c = customer.Id, Vehicle__c = vehicle.Id, Slip_Date__c = Date.newInstance(2026, 10, 30),
            Time_In__c = Time.newInstance(14, 5, 0, 0), Current_Km__c = 17773, Visit_Reason__c = 'Accident',
            Service_Type__c = 'Accidental Repair', Fuel_Level__c = '3/4', Mats__c = true
        );
        insert slip;
        insert new List<Job_Slip_Line__c>{
            new Job_Slip_Line__c(Job_Slip__c = slip.Id, Customer_Request__c = 'Bumper damaged', Labour_Estimate__c = 1500, Spares_Estimate__c = 6500, Sort_Order__c = 1),
            new Job_Slip_Line__c(Job_Slip__c = slip.Id, Customer_Request__c = 'Headlamp', Labour_Estimate__c = 500, Sort_Order__c = 2)
        };

        Test.startTest();
        JobSlipPdfController controller = render(slip.Id);
        Test.stopTest();

        System.assertEquals(true, controller.recordFound);
        System.assertEquals(false, controller.isBlank);
        System.assertEquals('Sanghi Motors', controller.workshopName);
        System.assertEquals('Deepak Sharma', controller.customerName);
        System.assertEquals('MP70ZD3946', controller.registrationNumber);
        System.assertEquals('Tata Punch', controller.makeModel);
        System.assertEquals('22/10/2025', controller.dateOfSale);
        System.assertEquals('30/10/2026', controller.slipDate);
        System.assertEquals('2:05 PM', controller.timeIn);
        System.assertEquals(JobSlipPdfController.TABLE_ROWS, controller.lines.size());
        System.assertEquals('Bumper damaged', controller.lines[0].customerRequest);
        System.assertEquals(null, controller.lines[5].customerRequest);
        System.assertEquals(15, controller.lines[14].rowNumber);
        System.assertNotEquals(null, controller.labourTotal);
        System.assert(controller.totalCostEstimate.startsWith('Rs. '), 'With no typed total, the slip falls back to the sum of the line estimates.');

        Integer selectedServiceTypes = 0;
        for (JobSlipPdfController.Choice c : controller.serviceTypes) {
            if (c.selected) {
                selectedServiceTypes++;
                System.assertEquals('Acc. Rep.', c.label);
            }
        }
        System.assertEquals(1, selectedServiceTypes);
        System.assertEquals(true, controller.fuelLevels[3].selected);

        Map<String, String> accessoryValues = new Map<String, String>();
        for (JobSlipPdfController.Accessory a : controller.accessories) {
            accessoryValues.put(a.label, a.value);
        }
        System.assertEquals('Yes', accessoryValues.get('Mats'));
        System.assertEquals('No', accessoryValues.get('Tool Kit'));
        System.assert(!controller.terms.isEmpty(), 'With no Job Slip Terms set on the profile, the default terms print.');
    }

    @isTest
    static void typedTotalCostEstimate_winsOverTheLineSum() {
        Customer__c customer = insertCustomer();
        Job_Slip__c slip = new Job_Slip__c(Customer__c = customer.Id, Total_Cost_Estimate__c = '2000 - 8000');
        insert slip;
        insert new Job_Slip_Line__c(Job_Slip__c = slip.Id, Labour_Estimate__c = 100, Sort_Order__c = 1);

        Test.startTest();
        JobSlipPdfController controller = render(slip.Id);
        Test.stopTest();

        System.assertEquals('2000 - 8000', controller.totalCostEstimate);
    }

    @isTest
    static void blankSlipForVehicle_prefillsCustomerAndVehicleOnly() {
        Customer__c customer = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP70ZD3946', Customer__c = customer.Id, Engine_Number__c = 'ENG123');
        insert vehicle;
        update new Workshop_Profile__c(Id = [SELECT Id FROM Workshop_Profile__c].Id, Job_Slip_Terms__c = 'First term\n\nSecond term');

        Test.startTest();
        JobSlipPdfController controller = render(vehicle.Id);
        Test.stopTest();

        System.assertEquals(true, controller.recordFound);
        System.assertEquals(true, controller.isBlank);
        System.assertEquals('Deepak Sharma', controller.customerName);
        System.assertEquals('MP70ZD3946', controller.registrationNumber);
        System.assertEquals('ENG123', controller.engineNumber);
        System.assertEquals(null, controller.slipNumber);
        System.assertEquals(null, controller.timeIn);
        System.assertEquals(JobSlipPdfController.TABLE_ROWS, controller.lines.size());
        System.assertEquals(13, controller.accessories.size());
        System.assertEquals('', controller.accessories[0].value);
        for (JobSlipPdfController.Choice c : controller.serviceTypes) {
            System.assertEquals(false, c.selected);
        }
        System.assertEquals(new List<String>{ 'First term', 'Second term' }, controller.terms);
    }

    @isTest
    static void blankSlipForCustomer_leavesVehicleEmpty() {
        Customer__c customer = insertCustomer();

        Test.startTest();
        JobSlipPdfController controller = render(customer.Id);
        Test.stopTest();

        System.assertEquals(true, controller.recordFound);
        System.assertEquals('Deepak Sharma', controller.customerName);
        System.assertEquals(null, controller.registrationNumber);
    }

    @isTest
    static void missingOrUnsupportedId_rendersNotFound() {
        Test.startTest();
        JobSlipPdfController none = render(null);
        PageReference junk = Page.JobSlipPdf;
        junk.getParameters().put('id', 'not-an-id');
        Test.setCurrentPage(junk);
        JobSlipPdfController garbage = new JobSlipPdfController();
        JobSlipPdfController profile = render([SELECT Id FROM Workshop_Profile__c].Id);
        Test.stopTest();

        System.assertEquals(false, none.recordFound);
        System.assertEquals(false, garbage.recordFound);
        System.assertEquals(false, profile.recordFound);
    }

    @isTest
    static void htmlFormat_rendersForThePreviewIframe() {
        Customer__c customer = insertCustomer();
        PageReference page = Page.JobSlipPdf;
        page.getParameters().put('id', customer.Id);
        page.getParameters().put('format', 'html');
        Test.setCurrentPage(page);

        Test.startTest();
        JobSlipPdfController controller = new JobSlipPdfController();
        Test.stopTest();

        System.assertEquals('', controller.renderAs);
    }

    @isTest
    static void formatTime_handlesMidnightAndNoon() {
        System.assertEquals('12:00 AM', JobSlipPdfController.formatTime(Time.newInstance(0, 0, 0, 0)));
        System.assertEquals('12:30 PM', JobSlipPdfController.formatTime(Time.newInstance(12, 30, 0, 0)));
        System.assertEquals(null, JobSlipPdfController.formatDate(null));
    }
}
