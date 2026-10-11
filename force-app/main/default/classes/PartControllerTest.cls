@isTest
private class PartControllerTest {

    @isTest
    static void listParts_blankTerm_returnsAll() {
        insert new Part__c(Name = 'Brake Pad', SKU__c = 'BP-1', Price__c = 500);
        insert new Part__c(Name = 'Clutch Plate', SKU__c = 'CP-1', Price__c = 800);

        Test.startTest();
        List<PartController.PartListItem> results = PartController.listParts(null);
        Test.stopTest();

        System.assertEquals(2, results.size());
    }

    @isTest
    static void listParts_withTerm_filtersByNameSkuOrBarcode() {
        insert new Part__c(Name = 'Brake Pad', SKU__c = 'BP-1', Price__c = 500);
        insert new Part__c(Name = 'Clutch Plate', SKU__c = 'CP-1', Price__c = 800);

        Test.startTest();
        List<PartController.PartListItem> results = PartController.listParts('Brake');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Brake Pad', results[0].name);
    }

    @isTest
    static void createPart_withOpeningStock_setsCurrentStockDirectly() {
        PartController.PartInput input = new PartController.PartInput();
        input.name = 'Brake Pad';
        input.sku = 'BP-1';
        input.price = 500;
        input.taxRatePercent = 18;
        input.gstType = 'CGST_SGST';
        input.openingStock = 10;

        Test.startTest();
        PartController.PartListItem item = PartController.createPart(input);
        Test.stopTest();

        System.assertEquals(10, item.currentStock);
    }

    @isTest
    static void createPart_missingName_throws() {
        PartController.PartInput input = new PartController.PartInput();
        input.price = 500;

        Boolean threw = false;
        try {
            PartController.createPart(input);
        } catch (PartController.PartControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void updatePart_neverTouchesCurrentStock() {
        Part__c part = new Part__c(Name = 'Brake Pad', SKU__c = 'BP-1', Price__c = 500, Current_Stock__c = 5);
        insert part;

        PartController.PartInput input = new PartController.PartInput();
        input.name = 'Brake Pad Updated';
        input.sku = 'BP-1';
        input.price = 600;

        Test.startTest();
        PartController.updatePart(part.Id, input);
        Test.stopTest();

        Part__c updated = [SELECT Name, Price__c, Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals('Brake Pad Updated', updated.Name);
        System.assertEquals(600, updated.Price__c);
        System.assertEquals(5, updated.Current_Stock__c, 'Updating part fields must never change derived stock.');
    }

    @isTest
    static void adjustStock_addsDeltaDirectlyToCurrentStock() {
        Part__c part = new Part__c(Name = 'Brake Pad', SKU__c = 'BP-1', Price__c = 500);
        insert part;

        Test.startTest();
        PartController.adjustStock(part.Id, 20);
        Test.stopTest();

        Part__c updated = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(20, updated.Current_Stock__c);
    }

    @isTest
    static void adjustStock_zeroQuantity_throws() {
        Part__c part = new Part__c(Name = 'Brake Pad', SKU__c = 'BP-1', Price__c = 500);
        insert part;

        Boolean threw = false;
        try {
            PartController.adjustStock(part.Id, 0);
        } catch (PartController.PartControllerException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void getPartDetail_returnsPartWithoutAnyMovementHistory() {
        Part__c part = new Part__c(Name = 'Brake Pad', SKU__c = 'BP-1', Price__c = 500, Current_Stock__c = 10);
        insert part;

        Test.startTest();
        PartController.PartDetail detail = PartController.getPartDetail(part.Id);
        Test.stopTest();

        System.assertEquals('Brake Pad', detail.part.name);
        System.assertEquals(10, detail.part.currentStock);
    }
}
