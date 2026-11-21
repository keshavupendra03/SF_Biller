/**
 * The single Apex entry point for the Estimates LWC. No approval process
 * (confirmed 2026-10-03, architecture.md §C.4/§E): estimates are just
 * created and saved; "changing" one means creating a new version — a new
 * Estimate__c record (its own AutoNumber Name, e.g. EST-0008) that
 * supersedes the one it was based on. Converting an estimate to a bill
 * happens through BillController.createBill's sourceEstimateId — this
 * controller only prepares the data (getEstimateSummary returns the line
 * items a bill-creation screen needs to prefill from), it doesn't create
 * the bill itself.
 */
public with sharing class EstimateController {

    public class EstimateControllerException extends Exception {}

    public class CreateEstimateRequest {
        // The company this estimate is for. Blank means the primary company.
        @AuraEnabled public Id workshopProfileId { get; set; }
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public Id jobId { get; set; }
        @AuraEnabled public Id billToPartyId { get; set; }
        @AuraEnabled public BillController.NewBillToPartyInput newBillToParty { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public CustomerController.NewVehicleInput newVehicle { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Date estimateDate { get; set; }
        @AuraEnabled public List<BillController.LineItemInput> lineItems { get; set; }
    }

    public class EstimateSummary {
        @AuraEnabled public Id estimateId { get; set; }
        @AuraEnabled public String estimateNumber { get; set; }
        @AuraEnabled public Integer versionNumber { get; set; }
        @AuraEnabled public Boolean isLatestVersion { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date estimateDate { get; set; }
        @AuraEnabled public Id jobId { get; set; }
        @AuraEnabled public Id workshopProfileId { get; set; }
        // Only set when the workshop has two companies.
        @AuraEnabled public String companyName { get; set; }
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public Id billToPartyId { get; set; }
        @AuraEnabled public String billToPartyName { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public String vehicleLabel { get; set; }
        @AuraEnabled public String vehicleChassisNumber { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Decimal subtotal { get; set; }
        @AuraEnabled public Decimal cgst { get; set; }
        @AuraEnabled public Decimal sgst { get; set; }
        @AuraEnabled public Decimal igst { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public Decimal roundOff { get; set; }
        @AuraEnabled public List<BillController.LineItemInput> lineItems { get; set; }
    }

    @AuraEnabled
    public static EstimateSummary createEstimate(CreateEstimateRequest request) {
        // A save error (a bad GSTIN, a future date) is shown in its own words.
        try {
            validate(request);
            PartUpsertService.fillManualPartIds(request.lineItems);
            BillController.prepareLines(request.workshopProfileId, request.lineItems);
            Id billToPartyId = resolveBillToPartyId(request.billToPartyId, request.newBillToParty);
            Id vehicleId = resolveVehicleId(request.customerId, request.vehicleId, request.newVehicle);

            Estimate__c estimate = new Estimate__c(
                Workshop_Profile__c = request.workshopProfileId != null ? request.workshopProfileId : WorkshopProfileService.primaryId(),
                Customer__c = request.customerId,
                Job__c = request.jobId,
                Bill_To_Party__c = billToPartyId,
                Vehicle__c = vehicleId,
                Notes__c = request.notes,
                Estimate_Date__c = request.estimateDate != null ? request.estimateDate : Date.today()
            );
            insert estimate;

            insertLineItems(estimate.Id, request.lineItems);

            return buildSummary(estimate.Id);
        } catch (DmlException e) {
            throw ReadableErrors.of(e);
        }
    }

    /**
     * Creates a new version of previousEstimateId — a new Estimate__c
     * record (new AutoNumber Name) carrying Previous_Version__c/
     * Root_Estimate__c/Version_Number__c, marking the previous version
     * Is_Latest_Version__c = false. Estimates don't touch inventory, so
     * unlike bill versioning there's no stock to reverse.
     */
    @AuraEnabled
    public static EstimateSummary createNewVersion(Id previousEstimateId, CreateEstimateRequest request) {
        // A save error (a bad GSTIN, a future date) is shown in its own words.
        try {
            validate(request);
            PartUpsertService.fillManualPartIds(request.lineItems);

            Estimate__c previous = [
                SELECT Version_Number__c, Root_Estimate__c, Job__c, Vehicle__c, Workshop_Profile__c FROM Estimate__c WHERE Id = :previousEstimateId
            ];
            BillController.prepareLines(previous.Workshop_Profile__c, request.lineItems);
            Id rootId = previous.Root_Estimate__c != null ? previous.Root_Estimate__c : previousEstimateId;

            Id billToPartyId = resolveBillToPartyId(request.billToPartyId, request.newBillToParty);
            Id vehicleId = request.vehicleId != null || request.newVehicle != null
                ? resolveVehicleId(request.customerId, request.vehicleId, request.newVehicle)
                : previous.Vehicle__c;

            // A later version stays with its company, whatever the request says.
            Estimate__c newVersion = new Estimate__c(
                Workshop_Profile__c = previous.Workshop_Profile__c,
                Customer__c = request.customerId,
                Job__c = request.jobId != null ? request.jobId : previous.Job__c,
                Bill_To_Party__c = billToPartyId,
                Vehicle__c = vehicleId,
                Notes__c = request.notes,
                Estimate_Date__c = request.estimateDate != null ? request.estimateDate : Date.today(),
                Previous_Version__c = previousEstimateId,
                Root_Estimate__c = rootId,
                Version_Number__c = (previous.Version_Number__c == null ? 1 : previous.Version_Number__c) + 1
            );
            insert newVersion;

            insertLineItems(newVersion.Id, request.lineItems);

            update new Estimate__c(Id = previousEstimateId, Is_Latest_Version__c = false);

            return buildSummary(newVersion.Id);
        } catch (DmlException e) {
            throw ReadableErrors.of(e);
        }
    }

    /**
     * Deletes an estimate with all its versions and lines (architecture.md
     * §D.1, G2). An estimate isn't a GST document, so unlike a bill nothing of
     * it needs keeping. A bill made from it keeps its own copy of everything
     * and only loses the link.
     */
    @AuraEnabled
    public static void deleteEstimate(Id estimateId) {
        Estimate__c estimate = [SELECT Root_Estimate__c FROM Estimate__c WHERE Id = :estimateId];
        Id rootId = estimate.Root_Estimate__c != null ? estimate.Root_Estimate__c : estimateId;
        List<Estimate__c> versions = [SELECT Id FROM Estimate__c WHERE Id = :rootId OR Root_Estimate__c = :rootId];
        try {
            // Lines first: their link to the estimate doesn't allow deleting it under them.
            delete [SELECT Id FROM Estimate_Line_Item__c WHERE Estimate__c IN :versions];
            delete versions;
        } catch (DmlException e) {
            throw ReadableErrors.of(e);
        }
    }

    @AuraEnabled
    public static EstimateSummary getEstimateSummary(Id estimateId) {
        return buildSummary(estimateId);
    }

    @AuraEnabled
    public static List<EstimateSummary> getEstimateVersions(Id anyVersionEstimateId) {
        Estimate__c anyVersion = [SELECT Root_Estimate__c FROM Estimate__c WHERE Id = :anyVersionEstimateId];
        Id rootId = anyVersion.Root_Estimate__c != null ? anyVersion.Root_Estimate__c : anyVersionEstimateId;

        List<EstimateSummary> summaries = new List<EstimateSummary>();
        for (Estimate__c e : [
            SELECT Id FROM Estimate__c
            WHERE Id = :rootId OR Root_Estimate__c = :rootId
            ORDER BY Version_Number__c
        ]) {
            summaries.add(buildSummary(e.Id));
        }
        return summaries;
    }

    public class EstimateListItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String estimateNumber { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String billToPartyName { get; set; }
        @AuraEnabled public String companyName { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date estimateDate { get; set; }
    }

    /**
     * The Billing screen's Estimates list, the same shape as
     * BillController.listBills: latest versions only, newest first, optionally
     * searched by number, customer name or phone, or party name, and filtered
     * to one company.
     */
    @AuraEnabled
    public static List<EstimateListItem> listEstimates(String searchTerm, Id workshopProfileId) {
        String term = '%' + String.escapeSingleQuotes(String.isBlank(searchTerm) ? '' : searchTerm) + '%';
        String soql = 'SELECT Name, Customer__r.Name, Bill_To_Party__r.Name, Total_Amount__c, Status__c, Estimate_Date__c, Workshop_Profile__c'
            + ' FROM Estimate__c WHERE Is_Latest_Version__c = true';
        if (String.isNotBlank(searchTerm)) {
            soql += ' AND (Name LIKE :term OR Customer__r.Name LIKE :term OR Customer__r.Phone__c LIKE :term'
                + ' OR Bill_To_Party__r.Name LIKE :term)';
        }
        if (workshopProfileId != null) {
            // An estimate with no company recorded belongs to the primary company.
            Id orNoCompany = workshopProfileId == WorkshopProfileService.primaryId() ? null : workshopProfileId;
            soql += ' AND (Workshop_Profile__c = :workshopProfileId OR Workshop_Profile__c = :orNoCompany)';
        }
        List<Estimate__c> estimates = Database.query(soql + ' ORDER BY CreatedDate DESC LIMIT 200');
        Map<Id, String> companyNames = WorkshopProfileService.companyNames();

        List<EstimateListItem> results = new List<EstimateListItem>();
        for (Estimate__c e : estimates) {
            EstimateListItem item = new EstimateListItem();
            item.id = e.Id;
            item.estimateNumber = e.Name;
            item.customerName = e.Customer__r != null ? e.Customer__r.Name : null;
            item.billToPartyName = e.Bill_To_Party__r != null ? e.Bill_To_Party__r.Name : null;
            item.companyName = companyNames.get(e.Workshop_Profile__c);
            item.totalAmount = e.Total_Amount__c;
            item.status = e.Status__c;
            item.estimateDate = e.Estimate_Date__c;
            results.add(item);
        }
        return results;
    }

    private static void validate(CreateEstimateRequest request) {
        if (request == null || request.customerId == null) {
            throw new EstimateControllerException('A customer is required.');
        }
        GstRules.requireGstRates(request.lineItems);
        if (request.lineItems == null || request.lineItems.isEmpty()) {
            throw new EstimateControllerException('An estimate needs at least one line item.');
        }
        for (BillController.LineItemInput li : request.lineItems) {
            if (String.isBlank(li.description)) {
                throw new EstimateControllerException('Every line item needs a description.');
            }
            if (li.quantity == null || li.quantity <= 0) {
                throw new EstimateControllerException('Every line item needs a quantity greater than zero.');
            }
            if (li.unitPrice == null || li.unitPrice < 0) {
                throw new EstimateControllerException('Every line item needs a non-negative unit price.');
            }
        }
    }

    private static Id resolveBillToPartyId(Id billToPartyId, BillController.NewBillToPartyInput newBillToParty) {
        if (billToPartyId != null) {
            return billToPartyId;
        }
        if (newBillToParty != null && String.isNotBlank(newBillToParty.name)) {
            Bill_To_Party__c party = new Bill_To_Party__c(
                Name = newBillToParty.name,
                Address__c = newBillToParty.address,
                Contact_Phone__c = newBillToParty.contactPhone,
                GSTIN__c = newBillToParty.gstin,
                State__c = newBillToParty.state
            );
            insert party;
            return party.Id;
        }
        return null;
    }

    /**
     * Mirrors BillController.resolveVehicleId — a new vehicle created here
     * is saved under the estimate's customer, not just attached to this
     * one estimate.
     */
    private static Id resolveVehicleId(Id customerId, Id vehicleId, CustomerController.NewVehicleInput newVehicle) {
        if (vehicleId != null) {
            return vehicleId;
        }
        if (newVehicle != null && String.isNotBlank(newVehicle.registrationNumber)) {
            Vehicle__c vehicle = new Vehicle__c(
                Name = newVehicle.registrationNumber,
                Customer__c = customerId,
                Make__c = newVehicle.make,
                Model__c = newVehicle.model,
                Year__c = newVehicle.year,
                Color__c = newVehicle.color,
                Chassis_Number__c = newVehicle.chassisNumber
            );
            insert vehicle;
            VehicleMakeModelService.rememberIfNew(vehicle.Make__c, vehicle.Model__c);
            return vehicle.Id;
        }
        return null;
    }

    private static String vehicleLabel(Id vehicleId, Vehicle__c vehicle) {
        if (vehicleId == null || vehicle == null) {
            return null;
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(vehicle.Make__c)) {
            parts.add(vehicle.Make__c);
        }
        if (String.isNotBlank(vehicle.Model__c)) {
            parts.add(vehicle.Model__c);
        }
        String makeModel = String.join(parts, ' ');
        return String.isBlank(makeModel) ? vehicle.Name : vehicle.Name + ' — ' + makeModel;
    }

    private static void insertLineItems(Id estimateId, List<BillController.LineItemInput> lineItems) {
        List<Estimate_Line_Item__c> items = new List<Estimate_Line_Item__c>();
        for (BillController.LineItemInput li : lineItems) {
            items.add(new Estimate_Line_Item__c(
                Estimate__c = estimateId,
                Part__c = li.partId,
                Description__c = li.description,
                Quantity__c = li.quantity,
                Unit_Price__c = li.unitPrice,
                Tax_Rate_Percent__c = li.taxRatePercent == null ? 0 : li.taxRatePercent,
                Gst_Type__c = String.isBlank(li.gstType) ? 'CGST_SGST' : li.gstType,
                HSN_SAC_Code__c = li.hsnSacCode,
                Unit__c = li.unitLabel,
                Discount__c = li.discount == null ? 0 : li.discount
            ));
        }
        insert items;
    }

    private static EstimateSummary buildSummary(Id estimateId) {
        Estimate__c estimate = [
            SELECT Name, Version_Number__c, Is_Latest_Version__c, Status__c, Estimate_Date__c, Job__c,
                   Customer__c, Customer__r.Name, Bill_To_Party__c, Bill_To_Party__r.Name,
                   Vehicle__c, Vehicle__r.Name, Vehicle__r.Make__c, Vehicle__r.Model__c,
                   Vehicle__r.Chassis_Number__c, Notes__c,
                   Subtotal__c, Total_Amount__c, Workshop_Profile__c, Round_Off__c
            FROM Estimate__c
            WHERE Id = :estimateId
        ];

        List<BillController.LineItemInput> lineItemInputs = new List<BillController.LineItemInput>();
        List<GstCalculatorService.GstLineItemInput> gstInputs = new List<GstCalculatorService.GstLineItemInput>();
        for (Estimate_Line_Item__c item : [
            SELECT Part__c, Description__c, Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c, HSN_SAC_Code__c, Unit__c, Discount__c
            FROM Estimate_Line_Item__c
            WHERE Estimate__c = :estimateId
            ORDER BY CreatedDate, Id
        ]) {
            gstInputs.add(GstCalculatorService.inputFor(item));
            BillController.LineItemInput li = new BillController.LineItemInput();
            li.partId = item.Part__c;
            li.description = item.Description__c;
            li.quantity = item.Quantity__c;
            li.unitPrice = item.Unit_Price__c;
            li.taxRatePercent = item.Tax_Rate_Percent__c;
            li.gstType = item.Gst_Type__c;
            li.hsnSacCode = item.HSN_SAC_Code__c;
            li.unitLabel = item.Unit__c;
            li.discount = item.Discount__c;
            lineItemInputs.add(li);
        }
        GstCalculatorService.GstBillResult breakdown = GstCalculatorService.calculateBill(gstInputs);

        EstimateSummary summary = new EstimateSummary();
        summary.estimateId = estimateId;
        summary.estimateNumber = estimate.Name;
        summary.versionNumber = estimate.Version_Number__c == null ? 1 : estimate.Version_Number__c.intValue();
        summary.isLatestVersion = estimate.Is_Latest_Version__c;
        summary.status = estimate.Status__c;
        summary.estimateDate = estimate.Estimate_Date__c;
        summary.jobId = estimate.Job__c;
        summary.workshopProfileId = estimate.Workshop_Profile__c;
        summary.companyName = WorkshopProfileService.companyNames().get(estimate.Workshop_Profile__c);
        summary.customerId = estimate.Customer__c;
        summary.customerName = estimate.Customer__r != null ? estimate.Customer__r.Name : null;
        summary.billToPartyId = estimate.Bill_To_Party__c;
        summary.billToPartyName = estimate.Bill_To_Party__r != null ? estimate.Bill_To_Party__r.Name : null;
        summary.vehicleId = estimate.Vehicle__c;
        summary.vehicleLabel = vehicleLabel(estimate.Vehicle__c, estimate.Vehicle__r);
        summary.vehicleChassisNumber = estimate.Vehicle__c != null ? estimate.Vehicle__r.Chassis_Number__c : null;
        summary.notes = estimate.Notes__c;
        summary.subtotal = estimate.Subtotal__c;
        summary.cgst = breakdown.cgst;
        summary.sgst = breakdown.sgst;
        summary.igst = breakdown.igst;
        summary.totalAmount = estimate.Total_Amount__c;
        summary.roundOff = estimate.Round_Off__c == null ? 0 : estimate.Round_Off__c;
        summary.lineItems = lineItemInputs;
        return summary;
    }
}
