/**
 * Same single-threaded-Apex-test caveat as InvoiceNumberingServiceTest/
 * PaymentStatusService's own tests: a single Apex transaction can't
 * produce literal simultaneous execution, so "concurrent" here means
 * rapid sequential calls exercising the exact FOR UPDATE locking path a
 * real concurrent caller would hit, which proves the read-add-write logic
 * can't lose an update — the actual safety is the database-level
 * guarantee of FOR UPDATE, not something this test can force on its own.
 */
@isTest
private class PartStockServiceTest {

    @isTest
    static void adjustStock_singlePartPositiveDelta_addsToCurrentStock() {
        Part__c part = new Part__c(Name = 'Brake Pad', Price__c = 500, Current_Stock__c = 10);
        insert part;

        Test.startTest();
        PartStockService.adjustStock(new Map<Id, Decimal>{ part.Id => 5 });
        Test.stopTest();

        Part__c updated = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(15, updated.Current_Stock__c);
    }

    @isTest
    static void adjustStock_negativeDelta_subtractsFromCurrentStock() {
        Part__c part = new Part__c(Name = 'Brake Pad', Price__c = 500, Current_Stock__c = 10);
        insert part;

        Test.startTest();
        PartStockService.adjustStock(new Map<Id, Decimal>{ part.Id => -3 });
        Test.stopTest();

        Part__c updated = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(7, updated.Current_Stock__c);
    }

    @isTest
    static void adjustStock_bulkAcrossManyParts_eachDeltaIndependentlyCorrect() {
        List<Part__c> parts = new List<Part__c>();
        for (Integer i = 0; i < 20; i++) {
            parts.add(new Part__c(Name = 'Part ' + i, Price__c = 100, Current_Stock__c = 100));
        }
        insert parts;

        Map<Id, Decimal> deltaByPartId = new Map<Id, Decimal>();
        for (Integer i = 0; i < 20; i++) {
            // Each part gets a distinct delta (i+1) so a mixed-up mapping
            // between part and delta would be caught, not just "some
            // number changed".
            deltaByPartId.put(parts[i].Id, i + 1);
        }

        Test.startTest();
        PartStockService.adjustStock(deltaByPartId);
        Test.stopTest();

        Map<Id, Part__c> updatedById = new Map<Id, Part__c>(
            [SELECT Id, Current_Stock__c FROM Part__c]
        );
        for (Integer i = 0; i < 20; i++) {
            System.assertEquals(
                100 + i + 1,
                updatedById.get(parts[i].Id).Current_Stock__c,
                'Part ' + i + ' should have its own delta applied to its own starting stock.'
            );
        }
    }

    @isTest
    static void adjustStock_emptyMap_isNoOp() {
        Test.startTest();
        PartStockService.adjustStock(new Map<Id, Decimal>());
        Test.stopTest();
        // No exception is the assertion — nothing to query, nothing to update.
    }

    @isTest
    static void adjustStock_repeatedSequentialCallsAgainstSamePart_eachAddsOnTopOfTheLast() {
        // Simulates two bills created against the same part one after
        // another within the governing FOR UPDATE lock's serialization
        // guarantee — see class comment. A bug that read a stale
        // Current_Stock__c (e.g. caching it across calls) would lose one
        // of these deltas.
        Part__c part = new Part__c(Name = 'Brake Pad', Price__c = 500, Current_Stock__c = 20);
        insert part;

        Test.startTest();
        PartStockService.adjustStock(new Map<Id, Decimal>{ part.Id => -3 });
        PartStockService.adjustStock(new Map<Id, Decimal>{ part.Id => -2 });
        Test.stopTest();

        Part__c updated = [SELECT Current_Stock__c FROM Part__c WHERE Id = :part.Id];
        System.assertEquals(15, updated.Current_Stock__c);
    }

    @isTest
    static void adjustStock_negativeTotal_allowedNotBlocked() {
        Part__c part = new Part__c(Name = 'Brake Pad', Price__c = 500, Current_Stock__c = 0);
        insert part;

        Test.startTest();
        PartStockService.adjustStock(new Map<Id, Decimal>{ part.Id => -12 });
        Test.stopTest();

        Part__c updated = [
            SELECT Current_Stock__c, Is_Oversold__c FROM Part__c WHERE Id = :part.Id
        ];
        System.assertEquals(-12, updated.Current_Stock__c);
        System.assertEquals(true, updated.Is_Oversold__c);
    }
}
