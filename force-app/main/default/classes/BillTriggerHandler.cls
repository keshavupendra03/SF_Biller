/**
 * Wires InvoiceNumberingService into actual Bill__c creation — without
 * this, Invoice_Number__c/Financial_Year__c are required fields with no
 * way for a Salesforce user to know the next value, so a bill created
 * directly in the UI could never actually be saved.
 *
 * Only assigns when both fields are blank — a bill arriving with a number
 * already set must never be renumbered (invoice numbers are immutable
 * once assigned, architecture.md §C.1). Also records the primary company on a
 * bill that doesn't name one, since the company decides which series it joins.
 */
public with sharing class BillTriggerHandler {

    public static void handleBeforeInsert(List<Bill__c> newBills) {
        Id primaryCompanyId = WorkshopProfileService.primaryId();
        for (Bill__c bill : newBills) {
            if (bill.Workshop_Profile__c == null) {
                bill.Workshop_Profile__c = primaryCompanyId;
            }
            if (String.isBlank(bill.Invoice_Number__c)) {
                InvoiceNumberingService.InvoiceNumberResult result =
                    InvoiceNumberingService.assignNextInvoiceNumber(bill.Workshop_Profile__c);
                bill.Invoice_Number__c = result.invoiceNumber;
                bill.Financial_Year__c = result.financialYear;
            }
        }
    }
}
