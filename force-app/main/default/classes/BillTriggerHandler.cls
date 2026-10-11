/**
 * Wires InvoiceNumberingService into actual Bill__c creation — without
 * this, Invoice_Number__c/Financial_Year__c are required fields with no
 * way for a Salesforce user to know the next value, so a bill created
 * directly in the UI could never actually be saved.
 *
 * Only assigns when both fields are blank — a bill arriving with a number
 * already set must never be renumbered (invoice numbers are immutable
 * once assigned, architecture.md §C.1).
 */
public with sharing class BillTriggerHandler {

    public static void handleBeforeInsert(List<Bill__c> newBills) {
        for (Bill__c bill : newBills) {
            if (String.isBlank(bill.Invoice_Number__c)) {
                InvoiceNumberingService.InvoiceNumberResult result =
                    InvoiceNumberingService.assignNextInvoiceNumber();
                bill.Invoice_Number__c = result.invoiceNumber;
                bill.Financial_Year__c = result.financialYear;
            }
        }
    }
}
