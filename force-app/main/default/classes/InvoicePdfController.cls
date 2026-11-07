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
        if (sobjectName == 'Bill__c') {
            loadBill(recordId);
        } else if (sobjectName == 'Estimate__c') {
            loadEstimate(recordId);
        }
    }

    // The company on the document. None recorded means it predates a second
    // company, so it belongs to the primary one.
    private void loadWorkshopProfile(Id workshopProfileId) {
        Id profileId = workshopProfileId != null ? workshopProfileId : WorkshopProfileService.primaryId();
        List<Workshop_Profile__c> profiles = [
            SELECT Name, Address__c, Phone__c, Email__c, GSTIN__c, State__c,
                   Bank_Name__c, Bank_Account_No__c, Bank_IFSC__c,
                   Bank_Account_Holder__c, Terms_And_Conditions__c
            FROM Workshop_Profile__c
            WHERE Id = :profileId
        ];
        if (profiles.isEmpty()) {
            return;
        }
        Workshop_Profile__c profile = profiles[0];
        workshopName = profile.Name;
        workshopAddress = profile.Address__c;
        workshopPhone = profile.Phone__c;
        workshopEmail = profile.Email__c;
        workshopGstin = profile.GSTIN__c;
        workshopState = profile.State__c;
        bankName = profile.Bank_Name__c;
        bankAccountNo = profile.Bank_Account_No__c;
        bankIfsc = profile.Bank_IFSC__c;
        bankAccountHolder = profile.Bank_Account_Holder__c;
        termsAndConditions = profile.Terms_And_Conditions__c;
    }

    private void loadBill(Id billId) {
        List<Bill__c> bills = [
            SELECT Workshop_Profile__c, Invoice_Number__c, Bill_Date__c, Notes__c,
                   Subtotal__c, Total_Amount__c,
                   Customer__c, Customer__r.Name, Customer__r.Phone__c,
                   Customer__r.Address__c, Customer__r.GSTIN__c, Customer__r.State__c,
                   Bill_To_Party__c, Bill_To_Party__r.Name, Bill_To_Party__r.Address__c,
                   Bill_To_Party__r.Contact_Phone__c, Bill_To_Party__r.GSTIN__c,
                   Bill_To_Party__r.State__c,
                   Job__c, Job__r.Vehicle__r.Name, Job__r.Vehicle__r.Make__c,
                   Job__r.Vehicle__r.Model__c, Job__r.Vehicle__r.Chassis_Number__c,
                   Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                   Vehicle__r.Chassis_Number__c
            FROM Bill__c
            WHERE Id = :billId
            LIMIT 1
        ];
        if (bills.isEmpty()) {
            return;
        }
        Bill__c bill = bills[0];
        loadWorkshopProfile(bill.Workshop_Profile__c);
        recordFound = true;
        isEstimate = false;
        applyLabels();

        documentNumber = bill.Invoice_Number__c;
        documentDate = formatDate(bill.Bill_Date__c);
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

        List<Payment__c> payments = [SELECT Amount__c, Method__c FROM Payment__c WHERE Bill__c = :billId];
        Decimal totalPaid = 0;
        Set<String> methods = new Set<String>();
        for (Payment__c p : payments) {
            totalPaid += p.Amount__c;
            methods.add(p.Method__c);
        }
        amountPaid = totalPaid;
        if (!methods.isEmpty()) {
            paymentMode = String.join(new List<String>(methods), ', ');
        }

        loadLines([
            SELECT Description__c, HSN_SAC_Code__c, Quantity__c, Unit__c,
                   Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c
            FROM Bill_Line_Item__c
            WHERE Bill__c = :billId
            ORDER BY CreatedDate
        ]);
        amountDue = grandTotal - totalPaid;
        amountInWords = AmountInWordsService.convert(grandTotal);
    }

    private void loadEstimate(Id estimateId) {
        List<Estimate__c> estimates = [
            SELECT Workshop_Profile__c, Name, Estimate_Date__c, Notes__c,
                   Subtotal__c, Total_Amount__c,
                   Customer__c, Customer__r.Name, Customer__r.Phone__c,
                   Customer__r.Address__c, Customer__r.GSTIN__c, Customer__r.State__c,
                   Bill_To_Party__c, Bill_To_Party__r.Name, Bill_To_Party__r.Address__c,
                   Bill_To_Party__r.Contact_Phone__c, Bill_To_Party__r.GSTIN__c,
                   Bill_To_Party__r.State__c,
                   Job__c, Job__r.Vehicle__r.Name, Job__r.Vehicle__r.Make__c,
                   Job__r.Vehicle__r.Model__c, Job__r.Vehicle__r.Chassis_Number__c,
                   Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                   Vehicle__r.Chassis_Number__c
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

        loadLines([
            SELECT Description__c, HSN_SAC_Code__c, Quantity__c, Unit__c,
                   Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c
            FROM Estimate_Line_Item__c
            WHERE Estimate__c = :estimateId
            ORDER BY CreatedDate
        ]);
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
            buyersName = customer != null ? customer.Name : null;
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

    private void loadLines(List<SObject> items) {
        Integer i = 1;
        List<GstCalculatorService.GstLineItemInput> gstInputs = new List<GstCalculatorService.GstLineItemInput>();
        for (SObject item : items) {
            Decimal quantity = (Decimal) item.get('Quantity__c');
            Decimal unitPrice = (Decimal) item.get('Unit_Price__c');
            Decimal taxRate = (Decimal) item.get('Tax_Rate_Percent__c');
            String gstType = (String) item.get('Gst_Type__c');
            Decimal taxable = quantity * unitPrice;
            Decimal gstAmt = taxable * taxRate / 100;

            LineRow row = new LineRow();
            row.rowNumber = i;
            row.description = (String) item.get('Description__c');
            row.hsnSacCode = (String) item.get('HSN_SAC_Code__c');
            row.quantity = quantity;
            row.unitPrice = unitPrice;
            row.unit = (String) item.get('Unit__c');
            row.taxableAmount = taxable;
            row.gstAmount = gstAmt;
            row.taxRatePercent = taxRate;
            row.gstType = gstType;
            row.lineTotal = taxable + gstAmt;
            lines.add(row);
            i++;

            gstInputs.add(new GstCalculatorService.GstLineItemInput(
                row.description, quantity, unitPrice, taxRate,
                GstCalculatorService.supplyTypeFromGstType(gstType)
            ));
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
        if (!isEstimate && !hasGst) {
            documentTitle = 'Bill';
        }
    }

    // What's left of the table once the optional columns are accounted for.
    public Integer productColumnWidth {
        get {
            return 54 - (showUnit == true ? 6 : 0) - (hasGst == true ? 26 : 0);
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
