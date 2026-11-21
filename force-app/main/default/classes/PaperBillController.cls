/**
 * Backs the Easy Bill screen: a screen laid out like the printed bill, for
 * staff who find forms hard, where every box is typed straight onto the page.
 * It saves a normal Bill__c or Estimate__c through BillController /
 * EstimateController, so numbering, stock and totals work as everywhere else.
 *
 * InvoicePdf.page prints the customer, vehicle and workshop live from their
 * records, so what's typed has to reach those records for the print to match
 * the screen. That's why, unlike Quick Bill, a customer or vehicle already
 * picked on screen is overwritten with what's on the page, blanks included.
 * Details typed without picking anyone only fill in or replace non-blank
 * values, because staff never saw what was already saved.
 *
 * A saved bill or estimate opens here too (getDocument), and saving it makes a
 * new version through createNewVersion (architecture.md §C.4): the old one is
 * kept, never edited, and the new one gets its own number.
 */
public with sharing class PaperBillController {

    public class PaperBillControllerException extends Exception {}

    // The grid's own default, for a line on a no-GST document whose rate was
    // never kept anywhere (no part behind it).
    private static final Decimal DEFAULT_GST_RATE = 18;

    public class PaperRequest {
        @AuraEnabled public String documentType { get; set; }
        // Set when a saved document was opened here: this saves its new version.
        @AuraEnabled public Id previousVersionId { get; set; }
        @AuraEnabled public Id workshopProfileId { get; set; }
        // Set when an existing customer/vehicle was picked or matched on screen.
        @AuraEnabled public Id customerId { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String customerPhone { get; set; }
        @AuraEnabled public String customerAddress { get; set; }
        @AuraEnabled public String customerGstin { get; set; }
        @AuraEnabled public String customerState { get; set; }
        // Billing a company (insurance, fleet, firm) instead of the customer:
        // a picked party's Id, and what the page shows for it.
        @AuraEnabled public Id billToPartyId { get; set; }
        @AuraEnabled public BillController.NewBillToPartyInput billToParty { get; set; }
        @AuraEnabled public Id vehicleId { get; set; }
        @AuraEnabled public String registrationNumber { get; set; }
        @AuraEnabled public String make { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String chassisNumber { get; set; }
        @AuraEnabled public Date documentDate { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Boolean includeGst { get; set; }
        @AuraEnabled public List<BillController.LineItemInput> lineItems { get; set; }
        // Only sent when the workshop details were unlocked and edited.
        @AuraEnabled public WorkshopProfileController.ProfileData workshop { get; set; }
        // An insurance claim: the party (the insurer) pays each line's percent,
        // the customer the rest plus the compulsory excess. Saves two bills.
        @AuraEnabled public Boolean insuranceSplit { get; set; }
        @AuraEnabled public List<Decimal> insurerPercents { get; set; }
        @AuraEnabled public Decimal compulsoryExcess { get; set; }
    }

    public class SavedDocument {
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public String documentNumber { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        // The number of the version this one replaces, when it is one.
        @AuraEnabled public String replacedNumber { get; set; }
        // An insurance claim's customer bill, saved with the insurer's.
        @AuraEnabled public Id pairedRecordId { get; set; }
        @AuraEnabled public String pairedNumber { get; set; }
        @AuraEnabled public Decimal pairedTotal { get; set; }
    }

    public class LoadedLine {
        @AuraEnabled public Id partId { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String hsnSacCode { get; set; }
        @AuraEnabled public String unitLabel { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public Decimal taxRatePercent { get; set; }
        @AuraEnabled public String gstType { get; set; }
        @AuraEnabled public Decimal discount { get; set; }
    }

    public class LoadedDocument {
        @AuraEnabled public String documentType { get; set; }
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public String documentNumber { get; set; }
        @AuraEnabled public Decimal versionNumber { get; set; }
        @AuraEnabled public Boolean isLatestVersion { get; set; }
        @AuraEnabled public Id workshopProfileId { get; set; }
        // Null for a document on the shared Walk-in Customer.
        @AuraEnabled public QuickBillController.CustomerMatch customer { get; set; }
        @AuraEnabled public CustomerController.VehicleItem vehicle { get; set; }
        @AuraEnabled public DirectoryController.BillToPartyItem billToParty { get; set; }
        @AuraEnabled public Date documentDate { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Boolean includeGst { get; set; }
        @AuraEnabled public List<LoadedLine> lines { get; set; }
        // Bills only: deleted, or dated in a month whose GST is filed. Either
        // can be looked at but not changed.
        @AuraEnabled public Boolean isCancelled { get; set; }
        @AuraEnabled public Boolean isGstFiled { get; set; }
        @AuraEnabled public Date gstFiledUpTo { get; set; }
        // One half of an insurance claim (G6): the other half's number.
        @AuraEnabled public String pairedNumber { get; set; }
    }

    @AuraEnabled
    public static QuickBillController.CustomerMatch getCustomer(Id customerId) {
        Customer__c customer = [
            SELECT Id, Name, Phone__c, Address__c, GSTIN__c, State__c FROM Customer__c WHERE Id = :customerId
        ];
        QuickBillController.CustomerMatch match = QuickBillController.toMatch(customer);
        // A placeholder, not a number to show or print.
        if (match.phone == QuickBillController.WALK_IN_PHONE) {
            match.phone = null;
        }
        return match;
    }

    /**
     * A saved bill or estimate, laid out for the Easy Bill page to show and edit.
     */
    @AuraEnabled
    public static LoadedDocument getDocument(Id recordId) {
        LoadedDocument doc = new LoadedDocument();
        doc.recordId = recordId;
        Id customerId;
        Id vehicleId;
        Id partyId;
        List<SObject> lineRecords;
        if (recordId.getSObjectType() == Estimate__c.SObjectType) {
            Estimate__c estimate = [
                SELECT Name, Version_Number__c, Is_Latest_Version__c, Workshop_Profile__c, Customer__c, Vehicle__c,
                       Bill_To_Party__c, Estimate_Date__c, Notes__c
                FROM Estimate__c WHERE Id = :recordId
            ];
            doc.documentType = 'estimate';
            doc.documentNumber = estimate.Name;
            doc.versionNumber = estimate.Version_Number__c;
            doc.isLatestVersion = estimate.Is_Latest_Version__c;
            doc.workshopProfileId = estimate.Workshop_Profile__c;
            doc.documentDate = estimate.Estimate_Date__c;
            doc.notes = estimate.Notes__c;
            customerId = estimate.Customer__c;
            vehicleId = estimate.Vehicle__c;
            partyId = estimate.Bill_To_Party__c;
            lineRecords = [
                SELECT Part__c, Part__r.Tax_Rate_Percent__c, Description__c, HSN_SAC_Code__c, Unit__c, Discount__c,
                       Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c
                FROM Estimate_Line_Item__c WHERE Estimate__c = :recordId ORDER BY CreatedDate, Id
            ];
        } else {
            Bill__c bill = [
                SELECT Invoice_Number__c, Version_Number__c, Is_Latest_Version__c, Workshop_Profile__c, Customer__c,
                       Vehicle__c, Bill_To_Party__c, Bill_Date__c, Notes__c, Is_Cancelled__c,
                       Paired_Bill__r.Invoice_Number__c
                FROM Bill__c WHERE Id = :recordId
            ];
            doc.documentType = 'bill';
            doc.pairedNumber = bill.Paired_Bill__r == null ? null : bill.Paired_Bill__r.Invoice_Number__c;
            doc.isCancelled = bill.Is_Cancelled__c;
            doc.gstFiledUpTo = GstFilingLock.filedUpTo(bill.Workshop_Profile__c);
            doc.isGstFiled = GstFilingLock.isLocked(doc.gstFiledUpTo, bill.Bill_Date__c);
            doc.documentNumber = bill.Invoice_Number__c;
            doc.versionNumber = bill.Version_Number__c;
            doc.isLatestVersion = bill.Is_Latest_Version__c;
            doc.workshopProfileId = bill.Workshop_Profile__c;
            doc.documentDate = bill.Bill_Date__c;
            doc.notes = bill.Notes__c;
            customerId = bill.Customer__c;
            vehicleId = bill.Vehicle__c;
            partyId = bill.Bill_To_Party__c;
            lineRecords = [
                SELECT Part__c, Part__r.Tax_Rate_Percent__c, Description__c, HSN_SAC_Code__c, Unit__c, Discount__c,
                       Quantity__c, Unit_Price__c, Tax_Rate_Percent__c, Gst_Type__c
                FROM Bill_Line_Item__c WHERE Bill__c = :recordId ORDER BY CreatedDate, Id
            ];
        }
        if (doc.workshopProfileId == null) {
            // A document with no company recorded belongs to the primary company.
            doc.workshopProfileId = WorkshopProfileService.primaryId();
        }

        if (customerId != null && customerId != QuickBillController.walkInCustomerIdIfExists()) {
            doc.customer = getCustomer(customerId);
        }
        if (vehicleId != null) {
            Vehicle__c vehicle = [SELECT Name, Make__c, Model__c, Chassis_Number__c FROM Vehicle__c WHERE Id = :vehicleId];
            doc.vehicle = new CustomerController.VehicleItem();
            doc.vehicle.id = vehicle.Id;
            doc.vehicle.registrationNumber = vehicle.Name;
            doc.vehicle.make = vehicle.Make__c;
            doc.vehicle.model = vehicle.Model__c;
            doc.vehicle.chassisNumber = vehicle.Chassis_Number__c;
        }
        if (partyId != null) {
            Bill_To_Party__c party = [
                SELECT Name, Address__c, Contact_Phone__c, GSTIN__c, State__c FROM Bill_To_Party__c WHERE Id = :partyId
            ];
            doc.billToParty = new DirectoryController.BillToPartyItem();
            doc.billToParty.id = party.Id;
            doc.billToParty.name = party.Name;
            doc.billToParty.address = party.Address__c;
            doc.billToParty.contactPhone = party.Contact_Phone__c;
            doc.billToParty.gstin = party.GSTIN__c;
            doc.billToParty.state = party.State__c;
        }

        doc.includeGst = false;
        for (SObject line : lineRecords) {
            if (((Decimal) line.get('Tax_Rate_Percent__c')) > 0) {
                doc.includeGst = true;
            }
        }
        doc.lines = new List<LoadedLine>();
        for (SObject record : lineRecords) {
            LoadedLine line = new LoadedLine();
            line.partId = (Id) record.get('Part__c');
            line.description = (String) record.get('Description__c');
            line.hsnSacCode = (String) record.get('HSN_SAC_Code__c');
            line.unitLabel = (String) record.get('Unit__c');
            line.discount = (Decimal) record.get('Discount__c');
            line.quantity = (Decimal) record.get('Quantity__c');
            line.unitPrice = (Decimal) record.get('Unit_Price__c');
            line.gstType = (String) record.get('Gst_Type__c');
            line.taxRatePercent = (Decimal) record.get('Tax_Rate_Percent__c');
            // A no-GST document saves every line at 0%, so Add GST would find
            // nothing to add. The part remembers the rate it was typed with.
            if (!doc.includeGst) {
                Part__c part = (Part__c) record.getSObject('Part__r');
                line.taxRatePercent = part != null && part.Tax_Rate_Percent__c != null ? part.Tax_Rate_Percent__c : DEFAULT_GST_RATE;
            }
            doc.lines.add(line);
        }
        return doc;
    }

    @AuraEnabled
    public static String amountInWords(Decimal amount) {
        return amount == null ? '' : AmountInWordsService.convert(amount);
    }

    @AuraEnabled
    public static SavedDocument saveDocument(PaperRequest request) {
        // A save error (a bad GSTIN, a future date) is shown in its own words.
        try {
            if (request == null || request.lineItems == null || request.lineItems.isEmpty()) {
                throw new PaperBillControllerException('Add at least one item.');
            }
            Id previousId = request.previousVersionId;
            Boolean isEstimate = previousId != null
                ? previousId.getSObjectType() == Estimate__c.SObjectType
                : request.documentType == 'estimate';
            String replacedNumber = previousId == null ? null : lockLatestVersion(previousId, isEstimate);
            Boolean split = request.insuranceSplit == true;
            if (split) {
                requireSplit(request, isEstimate, previousId);
            }

            Id companyId = request.workshopProfileId;
            if (request.workshop != null) {
                companyId = WorkshopProfileController.saveProfile(request.workshop).id;
            }
            Id customerId = resolveCustomer(request);
            Id vehicleId = resolveVehicle(customerId, request);
            Id billToPartyId = BillToPartyService.resolve(request.billToPartyId, request.billToParty, true);

            // Parts first: an item typed on a no-GST bill must still remember its
            // typed rate for later bills (same order as QuickBillController).
            PartUpsertService.fillManualPartIds(request.lineItems);
            if (request.includeGst != true) {
                for (BillController.LineItemInput line : request.lineItems) {
                    line.taxRatePercent = 0;
                }
            }

            SavedDocument saved = new SavedDocument();
            saved.replacedNumber = replacedNumber;
            if (isEstimate) {
                EstimateController.CreateEstimateRequest estimate = new EstimateController.CreateEstimateRequest();
                estimate.workshopProfileId = companyId;
                estimate.customerId = customerId;
                estimate.vehicleId = vehicleId;
                estimate.billToPartyId = billToPartyId;
                estimate.estimateDate = request.documentDate;
                estimate.notes = request.notes;
                estimate.lineItems = request.lineItems;
                EstimateController.EstimateSummary summary = previousId != null
                    ? EstimateController.createNewVersion(previousId, estimate)
                    : EstimateController.createEstimate(estimate);
                clearVehicleIfRemoved(summary.estimateId, summary.vehicleId, vehicleId);
                saved.recordId = summary.estimateId;
                saved.documentNumber = summary.estimateNumber;
                saved.customerName = summary.billToPartyName != null ? summary.billToPartyName : summary.customerName;
                saved.totalAmount = summary.totalAmount;
                return saved;
            }
            BillController.CreateBillRequest bill = new BillController.CreateBillRequest();
            bill.workshopProfileId = companyId;
            bill.customerId = customerId;
            bill.vehicleId = vehicleId;
            bill.billToPartyId = billToPartyId;
            bill.billDate = request.documentDate;
            bill.notes = request.notes;
            bill.lineItems = request.lineItems;
            if (split) {
                return saveInsuranceSplit(request, bill, saved);
            }
            BillController.BillSummary summary = previousId != null
                ? BillController.createNewVersion(previousId, bill)
                : BillController.createBill(bill);
            clearVehicleIfRemoved(summary.billId, summary.vehicleId, vehicleId);
            saved.recordId = summary.billId;
            saved.documentNumber = summary.invoiceNumber;
            saved.customerName = summary.billToPartyName != null ? summary.billToPartyName : summary.customerName;
            saved.totalAmount = summary.totalAmount;
            return saved;
        } catch (DmlException e) {
            throw ReadableErrors.of(e);
        }
    }

    private static void requireSplit(PaperRequest request, Boolean isEstimate, Id previousId) {
        if (isEstimate || previousId != null) {
            throw new PaperBillControllerException('An insurance split is for a new bill only.');
        }
        if (request.billToPartyId == null && (request.billToParty == null || String.isBlank(request.billToParty.name))) {
            throw new PaperBillControllerException('Pick the insurance company to bill.');
        }
        if (request.customerId == null && String.isBlank(request.customerName)) {
            throw new PaperBillControllerException('Type the customer\'s name: they get a bill for their share.');
        }
        if (request.insurerPercents == null || request.insurerPercents.size() != request.lineItems.size()) {
            throw new PaperBillControllerException('Give the insurance share for every line.');
        }
    }

    /**
     * Two bills for one claim job, saved together: the insurer's (to the party)
     * and the customer's. Each line keeps its full price on both, with the
     * other side's share as the reduction, so the two add up to the job.
     * Only the insurer's bill takes stock. They point at each other.
     */
    private static SavedDocument saveInsuranceSplit(PaperRequest request, BillController.CreateBillRequest insurerBill, SavedDocument saved) {
        InsuranceSplitService.Split split = InsuranceSplitService.split(request.lineItems, request.insurerPercents, request.compulsoryExcess);

        insurerBill.lineItems = split.insurerLines;
        BillController.BillSummary insurer = BillController.createBill(insurerBill);

        BillController.CreateBillRequest customerBill = new BillController.CreateBillRequest();
        customerBill.workshopProfileId = insurerBill.workshopProfileId;
        customerBill.customerId = insurerBill.customerId;
        customerBill.vehicleId = insurerBill.vehicleId;
        customerBill.billDate = insurerBill.billDate;
        customerBill.notes = insurerBill.notes;
        customerBill.lineItems = split.customerLines;
        customerBill.takesNoStock = true;
        BillController.BillSummary customer = BillController.createBill(customerBill);

        update new List<Bill__c>{
            new Bill__c(Id = insurer.billId, Paired_Bill__c = customer.billId),
            new Bill__c(Id = customer.billId, Paired_Bill__c = insurer.billId)
        };

        saved.recordId = insurer.billId;
        saved.documentNumber = insurer.invoiceNumber;
        saved.customerName = insurer.billToPartyName;
        saved.totalAmount = insurer.totalAmount;
        saved.pairedRecordId = customer.billId;
        saved.pairedNumber = customer.invoiceNumber;
        saved.pairedTotal = customer.totalAmount;
        return saved;
    }

    // Locks the version being replaced, so two people saving changes to the
    // same bill at once can't both make a "latest" version of it. Returns its
    // number for the saved screen.
    private static String lockLatestVersion(Id previousId, Boolean isEstimate) {
        Boolean isLatest;
        String documentNumber;
        if (isEstimate) {
            Estimate__c previous = [SELECT Name, Is_Latest_Version__c FROM Estimate__c WHERE Id = :previousId FOR UPDATE];
            isLatest = previous.Is_Latest_Version__c;
            documentNumber = previous.Name;
        } else {
            Bill__c previous = [SELECT Invoice_Number__c, Is_Latest_Version__c, Is_Cancelled__c FROM Bill__c WHERE Id = :previousId FOR UPDATE];
            isLatest = previous.Is_Latest_Version__c;
            documentNumber = previous.Invoice_Number__c;
            if (previous.Is_Cancelled__c) {
                throw new PaperBillControllerException(documentNumber + ' was deleted, so it can\'t be changed.');
            }
        }
        if (isLatest != true) {
            throw new PaperBillControllerException(
                documentNumber + ' has already been changed. Open its latest version from the Billing list.'
            );
        }
        return documentNumber;
    }

    // createNewVersion keeps the old version's vehicle when none is given. On
    // this page a vehicle cleared from the page is meant to be gone.
    private static void clearVehicleIfRemoved(Id recordId, Id savedVehicleId, Id pageVehicleId) {
        if (pageVehicleId != null || savedVehicleId == null) {
            return;
        }
        SObject record = recordId.getSObjectType().newSObject(recordId);
        record.put('Vehicle__c', null);
        update record;
    }

    private static Id resolveCustomer(PaperRequest request) {
        String name = String.isBlank(request.customerName) ? null : request.customerName.trim();
        String phone = String.isBlank(request.customerPhone) ? null : request.customerPhone.trim();

        if (request.customerId != null) {
            Customer__c picked = new Customer__c(
                Id = request.customerId,
                Address__c = request.customerAddress,
                GSTIN__c = request.customerGstin,
                State__c = request.customerState
            );
            if (name != null) {
                picked.Name = name;
            }
            if (phone != null) {
                picked.Phone__c = phone;
            }
            update picked;
            return picked.Id;
        }

        Customer__c existing;
        if (phone != null) {
            existing = QuickBillController.findByPhone(phone);
        } else if (name == null) {
            return QuickBillController.walkInCustomerId();
        } else {
            // A name with no number: reuse that name, so regular buyers who
            // never give a number don't become a new customer on every bill.
            List<Customer__c> sameName = [
                SELECT Id FROM Customer__c
                WHERE Name = :name AND Phone__c = :QuickBillController.WALK_IN_PHONE
                ORDER BY CreatedDate LIMIT 1
            ];
            existing = sameName.isEmpty() ? null : sameName[0];
        }

        if (existing == null) {
            if (name == null) {
                throw new PaperBillControllerException('Type the customer name.');
            }
            Customer__c created = new Customer__c(
                Name = name,
                Phone__c = phone != null ? phone : QuickBillController.WALK_IN_PHONE,
                Address__c = request.customerAddress,
                GSTIN__c = request.customerGstin,
                State__c = request.customerState
            );
            insert created;
            return created.Id;
        }

        Customer__c changes = new Customer__c(Id = existing.Id);
        if (name != null) {
            changes.Name = name;
        }
        if (String.isNotBlank(request.customerAddress)) {
            changes.Address__c = request.customerAddress;
        }
        if (String.isNotBlank(request.customerGstin)) {
            changes.GSTIN__c = request.customerGstin;
        }
        if (String.isNotBlank(request.customerState)) {
            changes.State__c = request.customerState;
        }
        update changes;
        return existing.Id;
    }

    private static Id resolveVehicle(Id customerId, PaperRequest request) {
        String registration = String.isBlank(request.registrationNumber) ? null : request.registrationNumber.trim();

        if (request.vehicleId != null) {
            Vehicle__c picked = [SELECT Customer__c FROM Vehicle__c WHERE Id = :request.vehicleId];
            if (picked.Customer__c != customerId) {
                throw new PaperBillControllerException('That vehicle belongs to a different customer.');
            }
            Vehicle__c changes = new Vehicle__c(
                Id = picked.Id,
                Make__c = request.make,
                Model__c = request.model,
                Chassis_Number__c = request.chassisNumber
            );
            if (registration != null) {
                changes.Name = registration;
            }
            update changes;
            VehicleMakeModelService.rememberIfNew(request.make, request.model);
            return picked.Id;
        }

        if (registration == null) {
            if (String.isNotBlank(request.make) || String.isNotBlank(request.model) || String.isNotBlank(request.chassisNumber)) {
                throw new PaperBillControllerException('Type the vehicle number, or clear the vehicle details.');
            }
            return null;
        }

        // SOQL "=" is case-insensitive, so "mp09ab1234" matches "MP09AB1234".
        List<Vehicle__c> sameNumber = [
            SELECT Id FROM Vehicle__c WHERE Customer__c = :customerId AND Name = :registration LIMIT 1
        ];
        if (sameNumber.isEmpty()) {
            CustomerController.NewVehicleInput vehicle = new CustomerController.NewVehicleInput();
            vehicle.registrationNumber = registration;
            vehicle.make = request.make;
            vehicle.model = request.model;
            vehicle.chassisNumber = request.chassisNumber;
            return CustomerController.createVehicle(customerId, vehicle).id;
        }

        Vehicle__c changes = new Vehicle__c(Id = sameNumber[0].Id);
        if (String.isNotBlank(request.make)) {
            changes.Make__c = request.make;
        }
        if (String.isNotBlank(request.model)) {
            changes.Model__c = request.model;
        }
        if (String.isNotBlank(request.chassisNumber)) {
            changes.Chassis_Number__c = request.chassisNumber;
        }
        update changes;
        VehicleMakeModelService.rememberIfNew(request.make, request.model);
        return changes.Id;
    }
}
