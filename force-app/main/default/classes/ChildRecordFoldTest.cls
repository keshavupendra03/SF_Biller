/**
 * ChildRecordFold. The old objects exist only on orgs set up before
 * architecture.md's Forty-second entry, until Retire-OldChildObjects.ps1 runs,
 * so the tests that need them build them dynamically and only where they exist.
 */
@isTest
private class ChildRecordFoldTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static Boolean hasOldObjects() {
        for (String objectName : ChildRecordFold.OLD_OBJECTS) {
            if (!ChildRecordFold.hasObject(objectName)) {
                return false;
            }
        }
        return true;
    }

    private static SObject old(String objectName, Map<String, Object> values) {
        SObject record = Schema.getGlobalDescribe().get(objectName.toLowerCase()).newSObject();
        for (String field : values.keySet()) {
            record.put(field, values.get(field));
        }
        return record;
    }

    private static Integer count(String objectName) {
        return Database.countQuery('SELECT COUNT() FROM ' + objectName);
    }

    @isTest
    static void withNothingToMove_itEndsAtNothingLeft_withoutTheTemporaryAccess() {
        List<String> last = new List<String>();

        Test.startTest();
        // Where the old objects exist the first run gives itself access; the next finds nothing and takes it back.
        for (Integer run = 0; run < 3 && !last.contains('FOLD-REMAINING: 0'); run++) {
            last = ChildRecordFold.run(false);
        }
        Test.stopTest();

        System.assertEquals('FOLD-REMAINING: 0', last[last.size() - 1], String.join(last, '\n'));
        System.assertEquals(0, [SELECT COUNT() FROM PermissionSet WHERE Name = :ChildRecordFold.ACCESS_SET]);
    }

    @isTest
    static void theFirstRun_givesTheUserAccessToTheOldRecords_andAsksToRunAgain() {
        if (!hasOldObjects()) {
            return;
        }

        Test.startTest();
        List<String> report = ChildRecordFold.run(false);
        Test.stopTest();

        System.assertEquals('FOLD-REMAINING: -1', report[report.size() - 1]);
        System.assert(report[0].startsWith('Gave '), report[0]);
        PermissionSet accessSet = [SELECT Id FROM PermissionSet WHERE Name = :ChildRecordFold.ACCESS_SET];
        System.assertEquals(1, [SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId = :accessSet.Id AND AssigneeId = :UserInfo.getUserId()]);
        System.assertEquals(6, [SELECT COUNT() FROM ObjectPermissions WHERE ParentId = :accessSet.Id], 'The five, and Read on the job slip that one of them hangs off.');
        System.assertEquals(false, ChildRecordFold.grantAccess(), 'Granted once is enough.');
    }

    @isTest
    static void oldRecords_moveIntoTheirParents_andAreDeleted() {
        if (!hasOldObjects()) {
            return;
        }
        ChildRecordFold.grantAccess();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
            insert customer;
            Vehicle__c car = new Vehicle__c(Name = 'MP09AB1234', Customer__c = customer.Id);
            insert car;
            // Saved as the old triggers left it: totals and status already worked out.
            Bill__c bill = new Bill__c(Customer__c = customer.Id, Subtotal__c = 1300, GST_Amount__c = 180, Total_Amount__c = 1480, Status__c = 'Partial');
            insert bill;
            Estimate__c estimate = new Estimate__c(Customer__c = customer.Id);
            insert estimate;
            Job_Slip__c slip = new Job_Slip__c(Customer__c = customer.Id, Vehicle__c = car.Id);
            insert slip;
            Date day1 = Date.newInstance(2026, 11, 1);
            insert new List<SObject>{
                old('Bill_Line_Item__c', new Map<String, Object>{ 'Bill__c' => bill.Id, 'Description__c' => 'Brake Pad', 'Quantity__c' => 2,
                    'Unit_Price__c' => 500, 'Tax_Rate_Percent__c' => 18, 'Gst_Type__c' => 'CGST_SGST', 'HSN_SAC_Code__c' => '8708', 'Unit__c' => 'Pcs' }),
                old('Bill_Line_Item__c', new Map<String, Object>{ 'Bill__c' => bill.Id, 'Description__c' => 'Labour', 'Quantity__c' => 1,
                    'Unit_Price__c' => 300, 'Tax_Rate_Percent__c' => 0 }),
                old('Payment__c', new Map<String, Object>{ 'Bill__c' => bill.Id, 'Amount__c' => 500, 'Method__c' => 'UPI', 'Paid_At__c' => Datetime.now() }),
                old('Estimate_Line_Item__c', new Map<String, Object>{ 'Estimate__c' => estimate.Id, 'Description__c' => 'Diagnostic', 'Quantity__c' => 1,
                    'Unit_Price__c' => 200, 'Tax_Rate_Percent__c' => 18 }),
                old('Job_Slip_Line__c', new Map<String, Object>{ 'Job_Slip__c' => slip.Id, 'Customer_Request__c' => 'Second', 'Sort_Order__c' => 2 }),
                old('Job_Slip_Line__c', new Map<String, Object>{ 'Job_Slip__c' => slip.Id, 'Customer_Request__c' => 'First', 'Labour_Estimate__c' => 400, 'Sort_Order__c' => 1 }),
                old('Service_Entry__c', new Map<String, Object>{ 'Vehicle__c' => car.Id, 'Entry_Date__c' => day1.addDays(4), 'Work_Done__c' => 'Brakes',
                    'Visit_Start__c' => day1, 'Unique_Key__c' => car.Id + '|5' }),
                old('Service_Entry__c', new Map<String, Object>{ 'Vehicle__c' => car.Id, 'Entry_Date__c' => day1, 'Work_Done__c' => 'Oil',
                    'Unique_Key__c' => car.Id + '|1' })
            };

            Test.startTest();
            List<String> dry = ChildRecordFold.run(true);
            Integer linesAfterDryRun = count('Bill_Line_Item__c');
            List<String> report = ChildRecordFold.run(false);
            Test.stopTest();

            System.assertEquals(2, linesAfterDryRun, 'A dry run changes nothing: ' + dry);
            System.assertEquals('FOLD-REMAINING: -1', report[report.size() - 1], 'All moved; one more run tidies up: ' + String.join(report, '\n'));
            for (String objectName : ChildRecordFold.OLD_OBJECTS) {
                System.assertEquals(0, count(objectName), objectName);
            }

            Bill__c folded = [SELECT Line_Items__c, Payments__c, Amount_Paid__c, Status__c, Total_Amount__c FROM Bill__c WHERE Id = :bill.Id];
            List<BillController.LineItemInput> lines = StoredLines.read(folded.Line_Items__c);
            System.assertEquals(2, lines.size());
            System.assertEquals('Brake Pad', lines[0].description);
            System.assertEquals('8708', lines[0].hsnSacCode);
            System.assertEquals('CGST_SGST', lines[1].gstType, 'A blank GST type is stored as the field default.');
            System.assertEquals(500, folded.Amount_Paid__c);
            System.assertEquals('UPI', BillPayments.read(folded.Payments__c)[0].method);
            System.assertEquals('Partial', folded.Status__c, 'Kept as saved.');
            System.assertEquals(1480, folded.Total_Amount__c, 'Kept as saved.');
            System.assertEquals(2, BillController.getBillSummary(bill.Id).lineItems.size());

            System.assertEquals('Diagnostic', TestLines.of(estimate.Id)[0].description);

            List<JobSlipController.JobSlipLine> slipLines = JobSlipController.repairLines([SELECT Repair_Lines__c FROM Job_Slip__c WHERE Id = :slip.Id]);
            System.assertEquals('First', slipLines[0].customerRequest, 'In their old order.');
            System.assertEquals(400, slipLines[0].labourEstimate);

            Vehicle__c folder = [SELECT Service_Book__c, First_Service_Date__c, Last_Service_Date__c FROM Vehicle__c WHERE Id = :car.Id];
            List<ServiceBookController.Entry> days = ServiceBookController.readBook(folder);
            System.assertEquals(2, days.size());
            System.assertEquals('Oil', days[0].workDone, 'Oldest first.');
            System.assertEquals(day1, days[1].visitStart);
            System.assertEquals(day1, folder.First_Service_Date__c);
            System.assertEquals(day1.addDays(4), folder.Last_Service_Date__c);
            System.assertEquals('Brakes', ServiceBookController.getDay(day1.addDays(4))[0].workDone);
        }
    }

    @isTest
    static void aBillWithBothStoredAndOldLines_stopsTheRun_changingNothing() {
        if (!hasOldObjects()) {
            return;
        }
        ChildRecordFold.grantAccess();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
            insert customer;
            Bill__c bill = new Bill__c(Customer__c = customer.Id);
            insert bill;
            TestLines.attach(bill.Id, TestLines.line('Already stored', 1, 100, 0));
            insert old('Bill_Line_Item__c', new Map<String, Object>{ 'Bill__c' => bill.Id, 'Description__c' => 'Old', 'Quantity__c' => 1, 'Unit_Price__c' => 5 });
            String message;

            Test.startTest();
            try {
                ChildRecordFold.run(false);
            } catch (ChildRecordFold.ChildRecordFoldException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            System.assert(message != null && message.contains('already has stored lines and old line records'), message);
            System.assertEquals(1, count('Bill_Line_Item__c'));
            System.assertEquals('Already stored', TestLines.of(bill.Id)[0].description);
        }
    }
}
