@isTest
private class BillLineItemTriggerTest {

    @testSetup
    static void setup() {
        insert new Workshop_Profile__c(Name = 'Speedy Motors');
    }

    private static Id insertBill() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Bill__c bill = new Bill__c(Customer__c = customer.Id);
        insert bill;
        return bill.Id;
    }

    @isTest
    static void insertingLineItems_recomputesBillTotals() {
        Id billId = insertBill();

        Test.startTest();
        insert new List<Bill_Line_Item__c>{
            new Bill_Line_Item__c(
                Bill__c = billId,
                Description__c = 'Brake Pad',
                Quantity__c = 2,
                Unit_Price__c = 500,
                Tax_Rate_Percent__c = 18
            ),
            new Bill_Line_Item__c(
                Bill__c = billId,
                Description__c = 'Labour',
                Quantity__c = 1,
                Unit_Price__c = 300,
                Tax_Rate_Percent__c = 0
            )
        };
        Test.stopTest();

        Bill__c bill = [
            SELECT Subtotal__c, GST_Amount__c, Total_Amount__c FROM Bill__c WHERE Id = :billId
        ];
        System.assertEquals(1300, bill.Subtotal__c); // 1000 + 300
        System.assertEquals(180, bill.GST_Amount__c); // 18% of 1000 only
        System.assertEquals(1480, bill.Total_Amount__c);
    }

    @isTest
    static void deletingALineItem_excludesItFromRecomputedTotalsAndRestoresStock() {
        Id billId = insertBill();
        Part__c part = new Part__c(Name = 'Brake Pad', Price__c = 500);
        insert part;
        Bill_Line_Item__c item = new Bill_Line_Item__c(
            Bill__c = billId,
            Part__c = part.Id,
            Description__c = 'Brake Pad',
            Quantity__c = 2,
            Unit_Price__c = 500,
            Tax_Rate_Percent__c = 18
        );
        insert item;

        Part__c afterInsert = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(-2, afterInsert.Current_Stock__c, 'Inserting the line should deduct stock.');

        Test.startTest();
        delete item;
        Test.stopTest();

        Bill__c bill = [SELECT Total_Amount__c FROM Bill__c WHERE Id = :billId];
        System.assertEquals(0, bill.Total_Amount__c, 'Deleting the only line should zero the bill total.');

        Part__c afterDelete = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(0, afterDelete.Current_Stock__c, 'Deleting the line should restore the stock it deducted.');
    }

    @isTest
    static void bulkLineItemsAcrossMultipleBills_eachBillTotalIndependentlyCorrect() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        List<Bill__c> bills = new List<Bill__c>{
            new Bill__c(Customer__c = customer.Id),
            new Bill__c(Customer__c = customer.Id)
        };
        insert bills;

        Test.startTest();
        insert new List<Bill_Line_Item__c>{
            new Bill_Line_Item__c(
                Bill__c = bills[0].Id, Description__c = 'A',
                Quantity__c = 1, Unit_Price__c = 100, Tax_Rate_Percent__c = 0
            ),
            new Bill_Line_Item__c(
                Bill__c = bills[1].Id, Description__c = 'B',
                Quantity__c = 1, Unit_Price__c = 500, Tax_Rate_Percent__c = 0
            )
        };
        Test.stopTest();

        Map<Id, Bill__c> billsById = new Map<Id, Bill__c>(
            [SELECT Id, Total_Amount__c FROM Bill__c WHERE Id IN :bills]
        );
        System.assertEquals(100, billsById.get(bills[0].Id).Total_Amount__c);
        System.assertEquals(500, billsById.get(bills[1].Id).Total_Amount__c);
    }

    @isTest
    static void mixedGstTypeLines_bothBucketsSummedCorrectly() {
        Id billId = insertBill();

        Test.startTest();
        insert new List<Bill_Line_Item__c>{
            new Bill_Line_Item__c(
                Bill__c = billId, Description__c = 'Local part',
                Quantity__c = 2, Unit_Price__c = 500, Tax_Rate_Percent__c = 18,
                Gst_Type__c = 'CGST_SGST'
            ),
            new Bill_Line_Item__c(
                Bill__c = billId, Description__c = 'Out-of-state part',
                Quantity__c = 5, Unit_Price__c = 240, Tax_Rate_Percent__c = 28,
                Gst_Type__c = 'IGST'
            )
        };
        Test.stopTest();

        Bill__c bill = [
            SELECT Subtotal__c, GST_Amount__c, Total_Amount__c FROM Bill__c WHERE Id = :billId
        ];
        // Line 1 (CGST+SGST): subtotal 1000, gst 180. Line 2 (IGST): subtotal 1200, gst 336.
        System.assertEquals(2200, bill.Subtotal__c);
        System.assertEquals(516, bill.GST_Amount__c);
        System.assertEquals(2716, bill.Total_Amount__c);
    }

    @isTest
    static void insertingLineItemWithPart_deductsStockDirectlyFromThePart() {
        Id billId = insertBill();
        Part__c part = new Part__c(Name = 'Oil Filter', Price__c = 150);
        insert part;

        Test.startTest();
        insert new Bill_Line_Item__c(
            Bill__c = billId,
            Part__c = part.Id,
            Description__c = 'Oil Filter',
            Quantity__c = 3,
            Unit_Price__c = 150,
            Tax_Rate_Percent__c = 18
        );
        Test.stopTest();

        Part__c updated = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(-3, updated.Current_Stock__c);
    }

    @isTest
    static void insertingLineItemWithoutPart_doesNotTouchStock() {
        Id billId = insertBill();
        Part__c part = new Part__c(Name = 'Unrelated Part', Price__c = 100, Current_Stock__c = 7);
        insert part;

        Test.startTest();
        insert new Bill_Line_Item__c(
            Bill__c = billId,
            Description__c = 'Labour charge',
            Quantity__c = 1,
            Unit_Price__c = 300,
            Tax_Rate_Percent__c = 0
        );
        Test.stopTest();

        Part__c unchanged = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(7, unchanged.Current_Stock__c, 'A line with no Part__c must never touch any part\'s stock.');
    }
}
