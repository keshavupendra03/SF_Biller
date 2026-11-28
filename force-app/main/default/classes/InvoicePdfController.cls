/**
 * Backs InvoicePdf.page — same header/Bill-To/details/line-items/totals/
 * footer structure for both document types, driven by which SObject type
 * the ?id= param resolves to, with the same label swaps ("Tax Invoice"/
 * "Estimate", "Bill To"/"Estimated For", etc.) and Received/Balance/
 * Payment Mode rows omitted for estimates.
 *
 * Unlike the reference project, CGST/SGST/IGST is never a flat half-split
 * of one GST_Amount__c — architecture.md §C.3 means a document's lines can
 * independently be CGST+SGST or IGST, so the breakdown is always
 * recomputed live from the line items via GstCalculatorService, the same
 * way BillController/EstimateController's summaries are. Document dates
 * come from the editable Bill_Date__c/Estimate_Date__c fields, never
 * CreatedDate (architecture.md §C.4 — staff can correct/backdate these).
 */
public with sharing class InvoicePdfController {

    public Boolean isEstimate { get; private set; }
    public String documentTitle { get; private set; }
    public String billToLabel { get; private set; }
    public String detailsLabel { get; private set; }
    public String numberLabel { get; private set; }
    public String amountInWordsLabel { get; private set; }
    public Boolean showPayment { get; private set; }
    public Boolean showIgst { get; private set; }
    // A document with no GST prints no GST columns or rows, and a bill then
    // isn't a tax invoice. c/paperBill mirrors this so its screen matches.
    public Boolean hasGst { get; private set; }
    public Boolean showUnit { get; private set; }
    public Boolean recordFound { get; private set; }
    // ?format=html renders the same template as plain HTML for the in-app
    // preview; anything else renders the PDF.
    public String renderAs { get; private set; }

    public String workshopName { get; private set; }
    public String workshopAddress { get; private set; }
    public String workshopPhone { get; private set; }
    public String workshopEmail { get; private set; }
    public String workshopGstin { get; private set; }
    public String workshopState { get; private set; }
    public String bankName { get; private set; }
    public String bankAccountNo { get; private set; }
    public String bankIfsc { get; private set; }
    public String bankAccountHolder { get; private set; }
    public String termsAndConditions { get; private set; }

    public String billToName { get; private set; }
    public String billToAddress { get; private set; }
    public String billToContact { get; private set; }
    public String billToGstin { get; private set; }
    public String billToState { get; private set; }
    public String buyersName { get; private set; }
    // "23-Madhya Pradesh": required on a tax invoice. Bills only.
    public String placeOfSupply { get; private set; }
    // A deleted bill still prints, marked so it can't pass for a live one.
    public Boolean isCancelled { get; private set; }
    // Whole-rupee rounding, when the company rounds off.
    public Decimal roundOff { get; private set; }
    public Boolean showDiscount { get; private set; }
    // "Discount", or on an insurance claim pair who pays the rest of the line.
    public String discountLabel { get; private set; }
    // A composition company's bill of supply must say so.
    public String compositionNote { get; private set; }
    // An insurance claim pair names the other bill.
    public String pairedNote { get; private set; }
    private String registrationType;

    public String documentNumber { get; private set; }
    public String documentDate { get; private set; }
    public String vehicleRegNumber { get; private set; }
    public String vehicleMakeModel { get; private set; }
    public String vehicleChassisNumber { get; private set; }
    public String notes { get; private set; }

    public List<LineRow> lines { get; private set; }
    public Decimal subtotal { get; private set; }
    public Decimal cgst { get; private set; }
    public Decimal sgst { get; private set; }
    public Decimal igst { get; private set; }
    public Decimal grandTotal { get; private set; }
    public Decimal amountPaid { get; private set; }
    public Decimal amountDue { get; private set; }
    public String paymentMode { get; private set; }
    public String amountInWords { get; private set; }

    public class LineRow {
        public Integer rowNumber { get; set; }
        public String description { get; set; }
        public String hsnSacCode { get; set; }
        public Decimal quantity { get; set; }
        public Decimal unitPrice { get; set; }
        public String unit { get; set; }
        public Decimal taxableAmount { get; set; }
        public Decimal gstAmount { get; set; }
        public Decimal taxRatePercent { get; set; }
        public String gstType { get; set; }
        public Decimal lineTotal { get; set; }
        public Decimal discount { get; set; }
    }

    public InvoicePdfController() {
        lines = new List<LineRow>();
        subtotal = 0;
        cgst = 0;
        sgst = 0;
        igst = 0;
        grandTotal = 0;
        amountPaid = 0;
        amountDue = 0;
        recordFound = false;
        roundOff = 0;
        showDiscount = false;
        discountLabel = 'Discount';
        renderAs = ApexPages.currentPage().getParameters().get('format') == 'html' ? '' : 'pdf';

        String rawId = ApexPages.currentPage().getParameters().get('id');
        if (String.isBlank(rawId)) {
            return;
        }

        Id recordId;
        try {
            recordId = Id.valueOf(rawId);
        } catch (Exception e) {
            return;
        }

        String sobjectName = recordId.getSObjectType().getDescribe().getName();
        String archive = ApexPages.currentPage().getParameters().get('archive');
        if (sobjectName == 'Bill__c' && String.isNotBlank(archive)) {
            loadArchivedBill(Id.valueOf(archive), recordId);
        } else if (sobjectName == 'Bill__c') {
            loadBill(recordId);
        } else if (sobjectName == 'Estimate__c') {
            loadEstimate(recordId);
        }
    }

    // A bill archived into Files (BillArchive), with the company as it was then.
    private void loadArchivedBill(Id documentId, Id billId) {
        BillArchive.MonthFile file = BillArchive.findBill(documentId, billId);
        applyWorkshopProfile(file.company);
        applyBill(file.bills[0]);
    }

    // The company on the document. None recorded means it predates a second
    // company, so it belongs to the primary one.
    private void loadWorkshopProfile(Id workshopProfileId) {
        Id profileId = workshopProfileId != null ? workshopProfileId : WorkshopProfileService.primaryId();
        List<Workshop_Profile__c> profiles = [
            SELECT Name, Address__c, Phone__c, Email__c, GSTIN__c, State__c, GST_Registration_Type__c,
                   Bank_Name__c, Bank_Account_No__c, Bank_IFSC__c,
                   Bank_Account_Holder__c, Terms_And_Conditions__c
            FROM Workshop_Profile__c
            WHERE Id = :profileId
        ];
        if (profiles.isEmpty()) {
            return;
        }
        applyWorkshopProfile(profiles[0]);
    }

    private void applyWorkshopProfile(Workshop_Profile__c profile) {
        if (profile == null) {
            return;
        }
        workshopName = profile.Name;
        workshopAddress = profile.Address__c;
        workshopPhone = profile.Phone__c;
        workshopEmail = profile.Email__c;
        workshopGstin = profile.GSTIN__c;
        workshopState = profile.State__c;
        registrationType = profile.GST_Registration_Type__c;
        bankName = profile.Bank_Name__c;
        bankAccountNo = profile.Bank_Account_No__c;
        bankIfsc = profile.Bank_IFSC__c;
        bankAccountHolder = profile.Bank_Account_Holder__c;
        termsAndConditions = profile.Terms_And_Conditions__c;
    }

    private void loadBill(Id billId) {
        List<Bill__c> bills = [
            SELECT Workshop_Profile__c, Invoice_Number__c, Bill_Date__c, Notes__c, Place_Of_Supply__c, Is_Cancelled__c,
                   Subtotal__c, Total_Amount__c, Round_Off__c, Paired_Bill__c, Paired_Bill__r.Invoice_Number__c,
                   Customer__c, Customer__r.Name, Customer__r.Phone__c,
                   Customer__r.Address__c, Customer__r.GSTIN__c, Customer__r.State__c,
                   Bill_To_Party__c, Bill_To_Party__r.Name, Bill_To_Party__r.Address__c,
                   Bill_To_Party__r.Contact_Phone__c, Bill_To_Party__r.GSTIN__c,
                   Bill_To_Party__r.State__c,
                   Job__c, Job__r.Vehicle__r.Name, Job__r.Vehicle__r.Make__c,
                   Job__r.Vehicle__r.Model__c, Job__r.Vehicle__r.Chassis_Number__c,
                   Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                   Vehicle__r.Chassis_Number__c, Line_Items__c, Payments__c
            FROM Bill__c
            WHERE Id = :billId
            LIMIT 1
        ];
        if (bills.isEmpty()) {
            return;
        }
        loadWorkshopProfile(bills[0].Workshop_Profile__c);
        applyBill(bills[0]);
    }

    private void applyBill(Bill__c bill) {
        recordFound = true;
        isEstimate = false;
        applyLabels();

        documentNumber = bill.Invoice_Number__c;
        documentDate = formatDate(bill.Bill_Date__c);
        isCancelled = bill.Is_Cancelled__c;
        if (bill.Paired_Bill__c != null) {
            // The insurer's bill is the one to a party; each shows the other's share as the reduction.
            Boolean insurers = bill.Bill_To_Party__c != null;
            discountLabel = insurers ? 'Customer pays' : 'Insurance pays';
            pairedNote = (insurers ? 'Insurance claim: the customer\'s share is billed on ' : 'Insurance claim: the insurer\'s share is billed on ')
                + bill.Paired_Bill__r.Invoice_Number__c + '.';
        }
        String stateName = GstRules.stateNameForCode(bill.Place_Of_Supply__c);
        placeOfSupply = stateName == null ? null : bill.Place_Of_Supply__c + '-' + stateName;
        notes = bill.Notes__c;

        applyBillTo(bill.Customer__r, bill.Bill_To_Party__c, bill.Bill_To_Party__r);
        // The bill's own Vehicle__c (picked on the create/edit screen) is the
        // primary source — Job__r.Vehicle__c is only a fallback for bills
        // created before that field existed, or ones linked to a job but
        // never given their own vehicle selection.
        if (bill.Vehicle__c != null) {
            vehicleRegNumber = bill.Vehicle__r.Name;
            vehicleMakeModel = trimJoin(new List<String>{ bill.Vehicle__r.Make__c, bill.Vehicle__r.Model__c });
            vehicleChassisNumber = bill.Vehicle__r.Chassis_Number__c;
        } else if (bill.Job__c != null && bill.Job__r.Vehicle__c != null) {
            vehicleRegNumber = bill.Job__r.Vehicle__r.Name;
            vehicleMakeModel = trimJoin(
                new List<String>{ bill.Job__r.Vehicle__r.Make__c, bill.Job__r.Vehicle__r.Model__c }
            );
            vehicleChassisNumber = bill.Job__r.Vehicle__r.Chassis_Number__c;
        }

        List<BillPayments.Payment> payments = BillPayments.read(bill.Payments__c);
        Decimal totalPaid = BillPayments.sum(payments);
        Set<String> methods = new Set<String>();
        for (BillPayments.Payment p : payments) {
            methods.add(p.method);
        }
        amountPaid = totalPaid;
        if (!methods.isEmpty()) {
            paymentMode = String.join(new List<String>(methods), ', ');
        }

        loadLines(StoredLines.read(bill.Line_Items__c));
        addRoundOff(bill.Round_Off__c);
        amountDue = grandTotal - totalPaid;
        amountInWords = AmountInWordsService.convert(grandTotal);
    }

    private void loadEstimate(Id estimateId) {
        List<Estimate__c> estimates = [
            SELECT Workshop_Profile__c, Name, Estimate_Date__c, Notes__c,
                   Subtotal__c, Total_Amount__c, Round_Off__c,
                   Customer__c, Customer__r.Name, Customer__r.Phone__c,
                   Customer__r.Address__c, Customer__r.GSTIN__c, Customer__r.State__c,
                   Bill_To_Party__c, Bill_To_Party__r.Name, Bill_To_Party__r.Address__c,
                   Bill_To_Party__r.Contact_Phone__c, Bill_To_Party__r.GSTIN__c,
                   Bill_To_Party__r.State__c,
                   Job__c, Job__r.Vehicle__r.Name, Job__r.Vehicle__r.Make__c,
                   Job__r.Vehicle__r.Model__c, Job__r.Vehicle__r.Chassis_Number__c,
                   Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                   Vehicle__r.Chassis_Number__c, Line_Items__c
            FROM Estimate__c
            WHERE Id = :estimateId
            LIMIT 1
        ];
        if (estimates.isEmpty()) {
            return;
        }
        Estimate__c estimate = estimates[0];
        loadWorkshopProfile(estimate.Workshop_Profile__c);
        recordFound = true;
        isEstimate = true;
        applyLabels();

        documentNumber = estimate.Name;
        documentDate = formatDate(estimate.Estimate_Date__c);
        notes = estimate.Notes__c;

        applyBillTo(estimate.Customer__r, estimate.Bill_To_Party__c, estimate.Bill_To_Party__r);
        if (estimate.Vehicle__c != null) {
            vehicleRegNumber = estimate.Vehicle__r.Name;
            vehicleMakeModel = trimJoin(new List<String>{ estimate.Vehicle__r.Make__c, estimate.Vehicle__r.Model__c });
            vehicleChassisNumber = estimate.Vehicle__r.Chassis_Number__c;
        } else if (estimate.Job__c != null && estimate.Job__r.Vehicle__c != null) {
            vehicleRegNumber = estimate.Job__r.Vehicle__r.Name;
            vehicleChassisNumber = estimate.Job__r.Vehicle__r.Chassis_Number__c;
            vehicleMakeModel = trimJoin(
                new List<String>{ estimate.Job__r.Vehicle__r.Make__c, estimate.Job__r.Vehicle__r.Model__c }
            );
        }

        loadLines(StoredLines.read(estimate.Line_Items__c));
        addRoundOff(estimate.Round_Off__c);
        amountInWords = AmountInWordsService.convert(grandTotal);
    }

    private void applyLabels() {
        documentTitle = isEstimate ? 'Estimate' : 'Tax Invoice';
        billToLabel = isEstimate ? 'Estimated For' : 'Bill To';
        detailsLabel = isEstimate ? 'Estimate Details' : 'Invoice Details';
        numberLabel = isEstimate ? 'Estimate No.' : 'Invoice No.';
        amountInWordsLabel = isEstimate ? 'Estimate Amount In Words' : 'Invoice Amount In Words';
        showPayment = !isEstimate;
    }

    private void applyBillTo(Customer__c customer, Id billToPartyId, Bill_To_Party__c party) {
        if (billToPartyId != null && party != null) {
            billToName = party.Name;
            billToAddress = party.Address__c;
            billToContact = party.Contact_Phone__c;
            billToGstin = party.GSTIN__c;
            billToState = party.State__c;
            // A party bill with nobody named goes to the shared walk-in
            // customer, which isn't a buyer's name worth printing.
            buyersName = customer == null || isWalkIn(customer) ? null : customer.Name;
        } else if (customer != null) {
            billToName = customer.Name;
            billToAddress = customer.Address__c;
            // Quick Bill's shared walk-in customer carries a placeholder
            // phone only because Phone__c is required — don't print it.
            billToContact = customer.Phone__c == QuickBillController.WALK_IN_PHONE ? null : customer.Phone__c;
            billToGstin = customer.GSTIN__c;
            billToState = customer.State__c;
            buyersName = null;
        }
    }

    private static Boolean isWalkIn(Customer__c customer) {
        return customer.Name == QuickBillController.WALK_IN_NAME && customer.Phone__c == QuickBillController.WALK_IN_PHONE;
    }

    private void loadLines(List<BillController.LineItemInput> items) {
        Integer i = 1;
        List<GstCalculatorService.GstLineItemInput> gstInputs = new List<GstCalculatorService.GstLineItemInput>();
        for (BillController.LineItemInput item : items) {
            GstCalculatorService.GstLineItemInput input = GstCalculatorService.inputFor(item);
            GstCalculatorService.GstLineResult result = GstCalculatorService.calculateLine(input);
            Decimal quantity = input.quantity;
            Decimal unitPrice = input.unitPrice;
            Decimal taxRate = input.taxRatePercent;
            String gstType = item.gstType;
            Decimal taxable = result.subtotal;
            Decimal gstAmt = result.gst;

            LineRow row = new LineRow();
            row.rowNumber = i;
            row.description = item.description;
            row.hsnSacCode = item.hsnSacCode;
            row.quantity = quantity;
            row.unitPrice = unitPrice;
            row.unit = item.unitLabel;
            row.taxableAmount = taxable;
            row.gstAmount = gstAmt;
            row.taxRatePercent = taxRate;
            row.gstType = gstType;
            row.lineTotal = taxable + gstAmt;
            row.discount = input.discount;
            showDiscount = showDiscount || input.discount > 0;
            lines.add(row);
            i++;

            gstInputs.add(input);
        }

        GstCalculatorService.GstBillResult totals = GstCalculatorService.calculateBill(gstInputs);
        subtotal = totals.subtotal;
        cgst = totals.cgst;
        sgst = totals.sgst;
        igst = totals.igst;
        grandTotal = totals.grandTotal;
        showIgst = totals.igst > 0;
        hasGst = totals.cgst + totals.sgst + totals.igst > 0;
        showUnit = false;
        for (LineRow row : lines) {
            showUnit = showUnit || String.isNotBlank(row.unit);
        }
        if (!isEstimate && registrationType == 'Composition') {
            documentTitle = 'Bill of Supply';
            compositionNote = 'Composition taxable person, not eligible to collect tax on supplies.';
        } else if (!isEstimate && !hasGst) {
            documentTitle = 'Bill';
        }
    }

    // After the lines: the saved whole-rupee rounding joins the total, and so
    // the amount in words.
    private void addRoundOff(Decimal saved) {
        roundOff = saved == null ? 0 : saved;
        grandTotal += roundOff;
    }

    // What's left of the table once the optional columns are accounted for.
    public Integer productColumnWidth {
        get {
            return 54 - (showUnit == true ? 6 : 0) - (hasGst == true ? 26 : 0) - (showDiscount == true ? 10 : 0);
        }
    }

    private static String trimJoin(List<String> parts) {
        List<String> nonEmpty = new List<String>();
        for (String p : parts) {
            if (String.isNotBlank(p)) {
                nonEmpty.add(p);
            }
        }
        return nonEmpty.isEmpty() ? null : String.join(nonEmpty, ' ');
    }

    private static String formatDate(Date d) {
        if (d == null) {
            return null;
        }
        return String.valueOf(d.day()).leftPad(2, '0') + '-' +
               String.valueOf(d.month()).leftPad(2, '0') + '-' +
               String.valueOf(d.year());
    }
}
