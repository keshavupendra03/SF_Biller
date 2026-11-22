/**
 * Test data for bills and estimates, now that their lines are stored on the
 * record itself (StoredLines): attach() adds lines to a saved bill or
 * estimate and works its totals out again, as inserting line records used to.
 */
@isTest
public class TestLines {

    public static BillController.LineItemInput line(String description, Decimal quantity, Decimal unitPrice,
                                                    Decimal taxRatePercent, String gstType, String hsnSacCode, String unitLabel) {
        BillController.LineItemInput li = new BillController.LineItemInput();
        li.description = description;
        li.quantity = quantity;
        li.unitPrice = unitPrice;
        li.taxRatePercent = taxRatePercent;
        li.gstType = gstType;
        li.hsnSacCode = hsnSacCode;
        li.unitLabel = unitLabel;
        return li;
    }

    public static BillController.LineItemInput line(String description, Decimal quantity, Decimal unitPrice, Decimal taxRatePercent) {
        return line(description, quantity, unitPrice, taxRatePercent, null, null, null);
    }

    public static void attach(Id recordId, BillController.LineItemInput line) {
        attach(recordId, new List<BillController.LineItemInput>{ line });
    }

    public static void attach(Id recordId, List<BillController.LineItemInput> lines) {
        Schema.SObjectType recordType = recordId.getSObjectType();
        SObject record = Database.query('SELECT Workshop_Profile__c, Line_Items__c FROM ' + recordType + ' WHERE Id = :recordId');
        List<BillController.LineItemInput> all = StoredLines.read((String) record.get('Line_Items__c'));
        all.addAll(lines);
        SObject changes = recordType.newSObject(recordId);
        StoredLines.store(changes, (Id) record.get('Workshop_Profile__c'), all);
        update changes;
    }

    /** A bill's or estimate's stored lines. */
    public static List<BillController.LineItemInput> of(Id recordId) {
        SObject record = Database.query('SELECT Line_Items__c FROM ' + recordId.getSObjectType() + ' WHERE Id = :recordId');
        return StoredLines.read((String) record.get('Line_Items__c'));
    }

    /** A bill's stored payments. */
    public static List<BillPayments.Payment> paymentsOf(Id billId) {
        return BillPayments.read([SELECT Payments__c FROM Bill__c WHERE Id = :billId].Payments__c);
    }
}
