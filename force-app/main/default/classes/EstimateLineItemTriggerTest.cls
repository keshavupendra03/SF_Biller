@isTest
private class EstimateLineItemTriggerTest {

    private static Id insertEstimate() {
        Customer__c customer = new Customer__c(Name = 'Ramesh Kumar', Phone__c = '9000011111');
        insert customer;
        Estimate__c estimate = new Estimate__c(Customer__c = customer.Id);
        insert estimate;
        return estimate.Id;
    }

    @isTest
    static void insertingLineItems_recomputesEstimateTotals() {
        Id estimateId = insertEstimate();

        Test.startTest();
        insert new List<Estimate_Line_Item__c>{
            new Estimate_Line_Item__c(
                Estimate__c = estimateId, Description__c = 'Brake Pad',
                Quantity__c = 2, Unit_Price__c = 500, Tax_Rate_Percent__c = 18
            ),
            new Estimate_Line_Item__c(
                Estimate__c = estimateId, Description__c = 'Labour',
                Quantity__c = 1, Unit_Price__c = 300, Tax_Rate_Percent__c = 0
            )
        };
        Test.stopTest();

        Estimate__c estimate = [
            SELECT Subtotal__c, GST_Amount__c, Total_Amount__c FROM Estimate__c WHERE Id = :estimateId
        ];
        System.assertEquals(1300, estimate.Subtotal__c);
        System.assertEquals(180, estimate.GST_Amount__c);
        System.assertEquals(1480, estimate.Total_Amount__c);
    }

    @isTest
    static void deletingALineItem_excludesItFromRecomputedTotals() {
        Id estimateId = insertEstimate();
        Estimate_Line_Item__c item = new Estimate_Line_Item__c(
            Estimate__c = estimateId, Description__c = 'Brake Pad',
            Quantity__c = 2, Unit_Price__c = 500, Tax_Rate_Percent__c = 18
        );
        insert item;

        Test.startTest();
        delete item;
        Test.stopTest();

        Estimate__c estimate = [SELECT Total_Amount__c FROM Estimate__c WHERE Id = :estimateId];
        System.assertEquals(0, estimate.Total_Amount__c);
    }

    @isTest
    static void mixedGstTypeLines_bothBucketsSummedCorrectly() {
        Id estimateId = insertEstimate();

        Test.startTest();
        insert new List<Estimate_Line_Item__c>{
            new Estimate_Line_Item__c(
                Estimate__c = estimateId, Description__c = 'Local part',
                Quantity__c = 2, Unit_Price__c = 500, Tax_Rate_Percent__c = 18, Gst_Type__c = 'CGST_SGST'
            ),
            new Estimate_Line_Item__c(
                Estimate__c = estimateId, Description__c = 'Out-of-state part',
                Quantity__c = 5, Unit_Price__c = 240, Tax_Rate_Percent__c = 28, Gst_Type__c = 'IGST'
            )
        };
        Test.stopTest();

        Estimate__c estimate = [
            SELECT Subtotal__c, GST_Amount__c, Total_Amount__c FROM Estimate__c WHERE Id = :estimateId
        ];
        System.assertEquals(2200, estimate.Subtotal__c);
        System.assertEquals(516, estimate.GST_Amount__c);
        System.assertEquals(2716, estimate.Total_Amount__c);
    }
}
