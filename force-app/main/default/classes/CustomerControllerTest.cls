@isTest
private class CustomerControllerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static Id insertCustomer() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        return customer.Id;
    }

    @isTest
    static void listCustomers_blankTerm_returnsAll() {
        insertCustomer();
        insert new Customer__c(Name = 'Suresh Singh', Phone__c = '9000022222');

        Test.startTest();
        List<CustomerController.CustomerListItem> results = CustomerController.listCustomers(null);
        Test.stopTest();

        System.assertEquals(2, results.size());
    }

    @isTest
    static void listCustomers_withTerm_filtersByNameOrPhone() {
        insertCustomer();
        insert new Customer__c(Name = 'Suresh Singh', Phone__c = '9000022222');

        Test.startTest();
        List<CustomerController.CustomerListItem> results = CustomerController.listCustomers('Ramesh');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Ramesh Kumar', results[0].name);
    }

    @isTest
    static void getCustomerDetail_includesVehiclesBillsEstimatesAndLifetimeSpend() {
        Id customerId = insertCustomer();
        Vehicle__c vehicle = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customerId, Make__c = 'Maruti', Model__c = 'Swift');
        insert vehicle;

        Job_Status_Stage__c stage = new Job_Status_Stage__c(Name = 'Received', Sort_Order__c = 1);
        insert stage;
        insert new Job__c(Customer__c = customerId, Vehicle__c = vehicle.Id, Job_Status_Stage__c = stage.Id);

        Bill__c bill = new Bill__c(Customer__c = customerId, Bill_Date__c = Date.today());
        insert bill;
        insert new Bill_Line_Item__c(
            Bill__c = bill.Id, Description__c = 'Service', Quantity__c = 1, Unit_Price__c = 500,
            Tax_Rate_Percent__c = 18, Gst_Type__c = 'CGST_SGST'
        );
        insert new Payment__c(Bill__c = bill.Id, Amount__c = 300, Method__c = 'Cash', Paid_At__c = Datetime.now());

        Estimate__c estimate = new Estimate__c(Customer__c = customerId, Estimate_Date__c = Date.today());
        insert estimate;
        insert new Estimate_Line_Item__c(
            Estimate__c = estimate.Id, Description__c = 'Diagnostic', Quantity__c = 1, Unit_Price__c = 200,
            Tax_Rate_Percent__c = 18, Gst_Type__c = 'CGST_SGST'
        );

        Test.startTest();
        CustomerController.CustomerDetail detail = CustomerController.getCustomerDetail(customerId);
        Test.stopTest();

        System.assertEquals('Ramesh Kumar', detail.name);
        System.assertEquals(300, detail.lifetimeSpend);
        System.assertEquals(1, detail.vehicles.size());
        System.assertEquals('MP09AB1234', detail.vehicles[0].registrationNumber);
        System.assertEquals(1, detail.jobs.size());
        System.assertEquals('Received', detail.jobs[0].stageName);
        System.assertEquals(1, detail.bills.size());
        System.assertEquals(1, detail.estimates.size());
    }

    @isTest
    static void updateCustomer_updatesFields() {
        Id customerId = insertCustomer();

        CustomerController.CustomerInput input = new CustomerController.CustomerInput();
        input.name = 'Ramesh Kumar Updated';
        input.phone = '9000099999';

        Test.startTest();
        CustomerController.updateCustomer(customerId, input);
        Test.stopTest();

        Customer__c updated = [SELECT Name, Phone__c FROM Customer__c WHERE Id = :customerId];
        System.assertEquals('Ramesh Kumar Updated', updated.Name);
        System.assertEquals('9000099999', updated.Phone__c);
    }

    @isTest
    static void updateCustomer_missingPhone_throws() {
        Id customerId = insertCustomer();
        CustomerController.CustomerInput input = new CustomerController.CustomerInput();
        input.name = 'No Phone';

        Boolean threw = false;
        try {
            CustomerController.updateCustomer(customerId, input);
        } catch (CustomerController.CustomerControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void createVehicle_insertsVehicleForCustomer() {
        Id customerId = insertCustomer();
        CustomerController.NewVehicleInput input = new CustomerController.NewVehicleInput();
        input.registrationNumber = 'MP09ZZ9999';
        input.make = 'Honda';
        input.model = 'City';
        input.chassisNumber = 'MA3ERLF1S00123456';

        Test.startTest();
        CustomerController.VehicleItem item = CustomerController.createVehicle(customerId, input);
        Test.stopTest();

        System.assertEquals('MP09ZZ9999', item.registrationNumber);
        System.assertEquals('MA3ERLF1S00123456', item.chassisNumber);
        System.assertEquals(1, [SELECT COUNT() FROM Vehicle__c WHERE Customer__c = :customerId]);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Vehicle_Make_Model__c WHERE Make__c = 'Honda' AND Model__c = 'City'],
            'A new make/model typed when adding a vehicle must be remembered for future autocomplete suggestions.'
        );
    }

    @isTest
    static void createVehicle_missingRegistrationNumber_throws() {
        Id customerId = insertCustomer();
        CustomerController.NewVehicleInput input = new CustomerController.NewVehicleInput();

        Boolean threw = false;
        try {
            CustomerController.createVehicle(customerId, input);
        } catch (CustomerController.CustomerControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void listVehiclesForCustomer_ordersNewestFirstForPreselection() {
        Id customerId = insertCustomer();
        Vehicle__c older = new Vehicle__c(Name = 'MP09AA1111', Customer__c = customerId);
        insert older;
        Vehicle__c newer = new Vehicle__c(Name = 'MP09BB2222', Customer__c = customerId);
        insert newer;
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-2));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));

        Test.startTest();
        List<CustomerController.VehicleItem> results = CustomerController.listVehiclesForCustomer(customerId);
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals('MP09BB2222', results[0].registrationNumber, 'The most recently created vehicle must come first so callers can preselect results[0].');
        System.assertEquals('MP09AA1111', results[1].registrationNumber);
    }

    @isTest
    static void listVehiclesForCustomer_noCustomer_returnsEmptyList() {
        Test.startTest();
        List<CustomerController.VehicleItem> results = CustomerController.listVehiclesForCustomer(null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }
}
