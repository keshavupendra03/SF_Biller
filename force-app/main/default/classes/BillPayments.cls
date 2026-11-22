/**
 * The payments received against a bill, kept inside the bill (Payments__c,
 * as JSON, oldest first) instead of one Payment__c record each, for the same
 * storage reason as StoredLines (architecture.md, Forty-second).
 * Amount_Paid__c holds their sum so lists and customer totals can add it up
 * in SOQL, and Status__c follows from it: Unpaid, Partial or Paid.
 *
 * A payment on a saved bill locks the bill row first (SELECT ... FOR UPDATE),
 * the same lock-then-read-then-write as InvoiceNumberingService and
 * PartStockService, so two people taking money for the same bill at once
 * both count instead of one overwriting the other.
 */
public with sharing class BillPayments {

    public class BillPaymentsException extends Exception {}

    // The methods Payment__c.Method__c allowed.
    public static final List<String> METHODS = new List<String>{ 'Cash', 'Card', 'UPI', 'Bank Transfer' };

    public class Payment {
        public Decimal amount;
        public String method;
        public Datetime paidAt;
    }

    public static List<Payment> read(String stored) {
        if (String.isBlank(stored)) {
            return new List<Payment>();
        }
        return (List<Payment>) JSON.deserialize(stored, List<Payment>.class);
    }

    /** A first payment on a bill that's about to be saved, its totals already set. */
    public static void addFirst(Bill__c bill, Decimal amount, String method) {
        apply(bill, new List<Payment>{ newPayment(amount, method) }, bill.Total_Amount__c);
    }

    /** A payment on a saved bill, taken with the bill row locked. */
    public static void add(Id billId, Decimal amount, String method) {
        Payment payment = newPayment(amount, method);
        Bill__c bill = [SELECT Total_Amount__c, Payments__c FROM Bill__c WHERE Id = :billId FOR UPDATE];
        List<Payment> payments = read(bill.Payments__c);
        payments.add(payment);
        Bill__c changes = new Bill__c(Id = billId);
        apply(changes, payments, bill.Total_Amount__c);
        update changes;
    }

    public static Decimal sum(List<Payment> payments) {
        Decimal paid = 0;
        for (Payment payment : payments) {
            paid += payment.amount == null ? 0 : payment.amount;
        }
        return paid;
    }

    public static String statusFor(Decimal paid, Decimal total) {
        Decimal billTotal = total == null ? 0 : total;
        if (paid == null || paid <= 0) {
            return 'Unpaid';
        }
        return paid >= billTotal ? 'Paid' : 'Partial';
    }

    private static void apply(Bill__c bill, List<Payment> payments, Decimal total) {
        String body = JSON.serialize(payments, true);
        if (body.length() > StoredLines.MAX_LENGTH) {
            throw new BillPaymentsException('This bill has too many payments to record another.');
        }
        Decimal paid = sum(payments);
        bill.Payments__c = body;
        bill.Amount_Paid__c = paid;
        bill.Status__c = statusFor(paid, total);
    }

    private static Payment newPayment(Decimal amount, String method) {
        if (amount == null || amount <= 0) {
            throw new BillPaymentsException('A positive payment amount is required.');
        }
        String chosen = String.isBlank(method) ? 'Cash' : method;
        if (!METHODS.contains(chosen)) {
            throw new BillPaymentsException('"' + chosen + '" is not a payment method. Use ' + String.join(METHODS, ', ') + '.');
        }
        Payment payment = new Payment();
        payment.amount = amount.setScale(2, System.RoundingMode.HALF_UP);
        payment.method = chosen;
        payment.paidAt = Datetime.now();
        return payment;
    }
}
