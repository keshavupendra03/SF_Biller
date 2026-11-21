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
 *
 * For GST (architecture.md §D.1): the number follows the bill's own date; a
 * bill can't be dated in the future or in a month whose GST is filed
 * (GstFilingLock), and either is refused before a number is used; and the
 * buyer's GSTIN and place of supply are fixed on the bill as they are now, so
 * a later change to the customer can't change a bill that's been filed.
 */
public with sharing class BillTriggerHandler {

    public static void handleBeforeInsert(List<Bill__c> newBills) {
        Id primaryCompanyId = WorkshopProfileService.primaryId();
        Date today = Date.today();
        for (Bill__c bill : newBills) {
            if (bill.Workshop_Profile__c == null) {
                bill.Workshop_Profile__c = primaryCompanyId;
            }
            if (bill.Bill_Date__c == null) {
                bill.Bill_Date__c = today;
            }
        }
        Map<Id, Workshop_Profile__c> companies = companiesOf(newBills);

        for (Bill__c bill : newBills) {
            if (bill.Bill_Date__c > today) {
                bill.addError('Bill_Date__c', 'A bill can\'t be dated in the future. Use today\'s date or an earlier one.');
                continue;
            }
            Workshop_Profile__c company = companies.get(bill.Workshop_Profile__c);
            Date filedUpTo = company == null ? null : company.GST_Filed_Up_To__c;
            if (GstFilingLock.isLocked(filedUpTo, bill.Bill_Date__c)) {
                bill.addError('Bill_Date__c', GstFilingLock.lockedMessage(filedUpTo, bill.Bill_Date__c, 'added'));
                continue;
            }
            if (String.isBlank(bill.Invoice_Number__c)) {
                InvoiceNumberingService.InvoiceNumberResult result =
                    InvoiceNumberingService.assignNextInvoiceNumber(bill.Workshop_Profile__c, bill.Bill_Date__c);
                bill.Invoice_Number__c = result.invoiceNumber;
                bill.Financial_Year__c = result.financialYear;
                bill.Invoice_Sequence__c = result.sequence;
            }
        }
        fixRecipient(newBills, companies);
    }

    private static Map<Id, Workshop_Profile__c> companiesOf(List<Bill__c> bills) {
        Set<Id> companyIds = new Set<Id>();
        for (Bill__c bill : bills) {
            companyIds.add(bill.Workshop_Profile__c);
        }
        return new Map<Id, Workshop_Profile__c>(
            [SELECT State__c, GSTIN__c, GST_Filed_Up_To__c FROM Workshop_Profile__c WHERE Id IN :companyIds]
        );
    }

    /**
     * Who the bill is to, for GST: the Bill-To-Party if there is one, else the
     * customer. Place of supply is their state, else their GSTIN's state, else
     * the company's own (a counter sale is supplied where the workshop is).
     * A GSTIN is copied as saved, valid or not: the GST checkup lists bad ones.
     * Only fills what's blank. GstBackfillBatch uses it for older bills too.
     */
    public static void fixRecipient(List<Bill__c> bills) {
        fixRecipient(bills, companiesOf(bills));
    }

    private static void fixRecipient(List<Bill__c> bills, Map<Id, Workshop_Profile__c> companies) {
        Set<Id> customerIds = new Set<Id>();
        Set<Id> partyIds = new Set<Id>();
        for (Bill__c bill : bills) {
            if (bill.Bill_To_Party__c != null) {
                partyIds.add(bill.Bill_To_Party__c);
            } else if (bill.Customer__c != null) {
                customerIds.add(bill.Customer__c);
            }
        }
        Map<Id, SObject> recipients = new Map<Id, SObject>();
        if (!customerIds.isEmpty()) {
            recipients.putAll(new Map<Id, SObject>([SELECT GSTIN__c, State__c FROM Customer__c WHERE Id IN :customerIds]));
        }
        if (!partyIds.isEmpty()) {
            recipients.putAll(new Map<Id, SObject>([SELECT GSTIN__c, State__c FROM Bill_To_Party__c WHERE Id IN :partyIds]));
        }

        for (Bill__c bill : bills) {
            SObject recipient = recipients.get(bill.Bill_To_Party__c != null ? bill.Bill_To_Party__c : bill.Customer__c);
            if (bill.Recipient_GSTIN__c == null && recipient != null) {
                String gstin = GstRules.normalizeGstin((String) recipient.get('GSTIN__c'));
                bill.Recipient_GSTIN__c = gstin != null && gstin.length() <= 15 ? gstin : null;
            }
            if (bill.Place_Of_Supply__c != null) {
                continue;
            }
            String placeOfSupply = recipient == null ? null : GstRules.stateCode((String) recipient.get('State__c'));
            if (placeOfSupply == null && GstRules.isValidGstin(bill.Recipient_GSTIN__c)) {
                placeOfSupply = bill.Recipient_GSTIN__c.left(2);
            }
            Workshop_Profile__c company = companies.get(bill.Workshop_Profile__c);
            if (placeOfSupply == null && company != null) {
                placeOfSupply = GstRules.stateCode(company.State__c);
                if (placeOfSupply == null && GstRules.isValidGstin(company.GSTIN__c)) {
                    placeOfSupply = company.GSTIN__c.left(2);
                }
            }
            bill.Place_Of_Supply__c = placeOfSupply;
        }
    }
}
