@isTest
private class PartUpsertServiceTest {

    private static BillController.LineItemInput manualLine(String description, Decimal unitPrice, Decimal taxRatePercent, String gstType, String hsnSacCode, String unitLabel) {
        BillController.LineItemInput li = new BillController.LineItemInput();
        li.description = description;
        li.quantity = 1;
        li.unitPrice = unitPrice;
        li.taxRatePercent = taxRatePercent;
        li.gstType = gstType;
        li.hsnSacCode = hsnSacCode;
        li.unitLabel = unitLabel;
        return li;
    }

    @isTest
    static void fillManualPartIds_createsNewPartAndSetsItOnTheLine() {
        BillController.LineItemInput line = manualLine('Clutch Plate', 850, 18, 'CGST_SGST', '8708', 'pcs');

        Test.startTest();
        PartUpsertService.fillManualPartIds(new List<BillController.LineItemInput>{ line });
        Test.stopTest();

        System.assertNotEquals(null, line.partId, 'A manual line must end up with a real Part__c Id, just like one picked from search.');
        Part__c created = [SELECT Name, Price__c, Tax_Rate_Percent__c, Gst_Type__c, HSN_Code__c, Unit__c FROM Part__c WHERE Id = :line.partId];
        System.assertEquals('Clutch Plate', created.Name);
        System.assertEquals(850, created.Price__c);
        System.assertEquals(18, created.Tax_Rate_Percent__c);
        System.assertEquals('CGST_SGST', created.Gst_Type__c);
        System.assertEquals('8708', created.HSN_Code__c);
        System.assertEquals('pcs', created.Unit__c);
    }

    @isTest
    static void fillManualPartIds_reusesAnExistingPartWithTheSameName() {
        Part__c existing = new Part__c(Name = 'Oil Filter', Price__c = 150, Tax_Rate_Percent__c = 18, Gst_Type__c = 'CGST_SGST');
        insert existing;
        BillController.LineItemInput line = manualLine('Oil Filter', 150, 18, 'CGST_SGST', null, null);

        Test.startTest();
        PartUpsertService.fillManualPartIds(new List<BillController.LineItemInput>{ line });
        Test.stopTest();

        System.assertEquals(existing.Id, line.partId, 'A second manual line with the same name must reuse the part created the first time, not duplicate it.');
        System.assertEquals(1, [SELECT COUNT() FROM Part__c WHERE Name = 'Oil Filter']);
    }

    @isTest
    static void fillManualPartIds_doesNotTouchALineThatAlreadyHasAPart() {
        Part__c part = new Part__c(Name = 'Brake Pad', Price__c = 500);
        insert part;
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.partId = part.Id;
        line.description = 'Brake Pad';
        line.quantity = 1;
        line.unitPrice = 500;

        Test.startTest();
        PartUpsertService.fillManualPartIds(new List<BillController.LineItemInput>{ line });
        Test.stopTest();

        System.assertEquals(part.Id, line.partId);
        System.assertEquals(1, [SELECT COUNT() FROM Part__c], 'An already-linked line must never trigger a part lookup/creation.');
    }

    @isTest
    static void fillManualPartIds_multipleLinesWithTheSameDescriptionResolveToOneNewPart() {
        BillController.LineItemInput first = manualLine('Labour', 300, 0, null, null, null);
        BillController.LineItemInput second = manualLine('Labour', 300, 0, null, null, null);

        Test.startTest();
        PartUpsertService.fillManualPartIds(new List<BillController.LineItemInput>{ first, second });
        Test.stopTest();

        System.assertNotEquals(null, first.partId);
        System.assertEquals(first.partId, second.partId, 'Two manual lines with the same description in one request must resolve to the same new Part__c, not create two.');
        System.assertEquals(1, [SELECT COUNT() FROM Part__c WHERE Name = 'Labour']);
    }

    @isTest
    static void fillManualPartIds_blankDescriptionLineIsLeftAlone() {
        BillController.LineItemInput line = new BillController.LineItemInput();
        line.description = '';
        line.quantity = 1;
        line.unitPrice = 0;

        Test.startTest();
        PartUpsertService.fillManualPartIds(new List<BillController.LineItemInput>{ line });
        Test.stopTest();

        System.assertEquals(null, line.partId);
        System.assertEquals(0, [SELECT COUNT() FROM Part__c]);
    }
}
