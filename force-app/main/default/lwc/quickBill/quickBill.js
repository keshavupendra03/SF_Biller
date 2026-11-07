import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import findCustomerByPhone from '@salesforce/apex/QuickBillController.findCustomerByPhone';
import createQuickBill from '@salesforce/apex/QuickBillController.createQuickBill';
import createQuickEstimate from '@salesforce/apex/QuickBillController.createQuickEstimate';
import { calculateBillTotals } from 'c/gstMath';
import { disablePullToRefresh } from 'c/disablePullToRefresh';

const MODE_OPTIONS = [
    { label: 'Customer', value: 'customer' },
    { label: 'Walk-in', value: 'walkin' }
];

const EMPTY_CUSTOMER = { name: '', phone: '', address: '', gstin: '', state: '' };
const EMPTY_VEHICLE = { registrationNumber: '', make: '', model: '' };
const NEW_VEHICLE = '__new';
const LABELS = {
    bill: {
        noun: 'bill',
        title: 'Quick Bill',
        subtitle: 'Bill a parts sale or any customer in one step.',
        partyTitle: 'Bill To',
        created: 'Bill created',
        create: 'Create Bill',
        view: 'View Bill',
        startNew: 'New Quick Bill',
        date: 'Bill Date',
        moreOptions: 'Bill date & notes',
        hideMoreOptions: 'Hide bill date & notes'
    },
    estimate: {
        noun: 'estimate',
        title: 'Quick Estimate',
        subtitle: 'Quote a parts sale or any customer in one step.',
        partyTitle: 'Estimate For',
        created: 'Estimate created',
        create: 'Create Estimate',
        view: 'View Estimate',
        startNew: 'New Quick Estimate',
        date: 'Estimate Date',
        moreOptions: 'Estimate date & notes',
        hideMoreOptions: 'Hide estimate date & notes'
    }
};

const PHONE_LOOKUP_DELAY_MS = 400;

function todayIso() {
    const now = new Date();
    const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
    return local.toISOString().slice(0, 10);
}

function formatAmount(value) {
    return (Number(value) || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/**
 * Quick Bill / Quick Estimate (documentType) — one screen to bill or quote a
 * counter sale of spare parts, or any car customer, without setting up the
 * customer/vehicle first.
 * QuickBillController resolves the customer (shared Walk-in Customer, or
 * matched/created by phone) and the vehicle, then creates the bill
 * through BillController.createBill like every other bill (estimates through
 * EstimateController.createEstimate).
 */
export default class QuickBill extends NavigationMixin(LightningElement) {
    // 'bill' or 'estimate'. c/quickEstimate is this screen with 'estimate' set.
    @api documentType = 'bill';

    modeOptions = MODE_OPTIONS;

    workshopProfileId;
    mode = 'customer';
    customer = { ...EMPTY_CUSTOMER };
    showMoreCustomer = false;
    match;
    isLookingUp = false;

    selectedVehicleId = null;
    newVehicle = { ...EMPTY_VEHICLE };

    // The filled lines, as reported by c-line-item-grid.
    lines = [];
    includeGst = false;

    documentDate = todayIso();
    notes = '';
    showMoreOptions = false;

    isSubmitting = false;
    // { recordId, number, customerName, formattedTotal } once created.
    created;
    showPreview = false;

    _phoneTimer;
    _focusGridAfterRender = false;

    connectedCallback() {
        disablePullToRefresh(this);
    }

    renderedCallback() {
        if (this._focusGridAfterRender) {
            this._focusGridAfterRender = false;
            this.template.querySelector('c-line-item-grid').focusFirst();
        }
    }

    disconnectedCallback() {
        clearTimeout(this._phoneTimer);
    }

    get isEstimate() {
        return this.documentType === 'estimate';
    }

    get labels() {
        return this.isEstimate ? LABELS.estimate : LABELS.bill;
    }

    // ---- customer -------------------------------------------------------

    get isWalkIn() {
        return this.mode === 'walkin';
    }

    get isCustomerMode() {
        return !this.isWalkIn;
    }

    get hasMatch() {
        return !!this.match;
    }

    get nameDisabled() {
        return this.hasMatch;
    }

    get moreCustomerLabel() {
        return this.showMoreCustomer ? 'Hide address & GST details' : 'Add address & GST details';
    }

    handleCompanyChange(event) {
        this.workshopProfileId = event.detail.id;
    }

    handleModeChange(event) {
        this.mode = event.detail.value;
    }

    handleCustomerFieldChange(event) {
        const field = event.target.dataset.field;
        this.customer = { ...this.customer, [field]: event.target.value };
        if (field === 'phone') {
            this.schedulePhoneLookup();
        }
    }

    handleToggleMoreCustomer() {
        this.showMoreCustomer = !this.showMoreCustomer;
    }

    schedulePhoneLookup() {
        clearTimeout(this._phoneTimer);
        const phone = this.customer.phone;
        const hadMatch = this.hasMatch;
        this.match = undefined;
        this.selectedVehicleId = null;
        if (hadMatch) {
            this.customer = { ...this.customer, name: '' };
        }
        if ((phone || '').replace(/\D/g, '').length < 10) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._phoneTimer = setTimeout(() => this.lookUpPhone(phone), PHONE_LOOKUP_DELAY_MS);
    }

    lookUpPhone(phone) {
        this.isLookingUp = true;
        return findCustomerByPhone({ phone })
            .then((match) => {
                // Ignore a reply for a number that has since been edited.
                if (phone !== this.customer.phone) {
                    return;
                }
                this.match = match || undefined;
                if (match) {
                    this.customer = {
                        ...this.customer,
                        name: match.name,
                        address: this.customer.address || match.address || '',
                        gstin: this.customer.gstin || match.gstin || '',
                        state: this.customer.state || match.state || ''
                    };
                    this.selectedVehicleId = match.vehicles && match.vehicles.length === 1 ? match.vehicles[0].id : null;
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLookingUp = false;
            });
    }

    // ---- vehicle --------------------------------------------------------

    get matchVehicles() {
        return this.hasMatch && this.match.vehicles ? this.match.vehicles : [];
    }

    get hasMatchVehicles() {
        return this.matchVehicles.length > 0;
    }

    get vehicleChips() {
        const chips = this.matchVehicles.map((v) => ({
            value: v.id,
            label: v.registrationNumber,
            variant: v.id === this.selectedVehicleId ? 'brand' : 'neutral'
        }));
        chips.push({ value: NEW_VEHICLE, label: 'Other vehicle', variant: this.isNewVehicleSelected ? 'brand' : 'neutral' });
        chips.push({ value: '', label: 'No vehicle', variant: this.isNoVehicleSelected ? 'brand' : 'neutral' });
        return chips;
    }

    get isNewVehicleSelected() {
        return this.selectedVehicleId === NEW_VEHICLE;
    }

    get isNoVehicleSelected() {
        return !this.selectedVehicleId;
    }

    // With a matched customer the typed-vehicle fields appear only for
    // "Other vehicle"; for a new customer they're simply optional.
    get showVehicleFields() {
        return this.hasMatchVehicles ? this.isNewVehicleSelected : true;
    }

    handleVehicleChip(event) {
        this.selectedVehicleId = event.target.dataset.value || null;
    }

    handleVehicleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.newVehicle = { ...this.newVehicle, [field]: value };
    }

    // ---- items ----------------------------------------------------------

    get takesStock() {
        return !this.isEstimate;
    }

    get hasItems() {
        return this.lines.length > 0;
    }

    get itemCount() {
        return this.lines.reduce((sum, row) => sum + (Number(row.quantity) || 0), 0);
    }

    get itemCountLabel() {
        const count = this.itemCount;
        return `${count} ${count === 1 ? 'item' : 'items'}`;
    }

    get isGstExcluded() {
        return this.hasItems && !this.includeGst;
    }

    handleLinesChange(event) {
        this.lines = event.detail.lines;
    }

    handleToggleGst(event) {
        this.includeGst = event.target.checked;
    }

    handleGridFinish() {
        const create = this.template.querySelector('[data-id="create"]');
        if (create) {
            create.focus();
        }
    }

    // Ctrl+Enter from anywhere in the grid, so finishing doesn't mean tabbing
    // through the empty last line.
    handleGridKeydown(event) {
        if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
            event.preventDefault();
            this.handleCreate();
        }
    }

    // ---- totals ---------------------------------------------------------

    get totals() {
        return calculateBillTotals(this.includeGst ? this.lines : this.lines.map((row) => ({ ...row, taxRatePercent: 0 })));
    }

    get formattedSubtotal() {
        return formatAmount(this.totals.subtotal);
    }

    get formattedCgst() {
        return formatAmount(this.totals.cgst);
    }

    get formattedSgst() {
        return formatAmount(this.totals.sgst);
    }

    get formattedIgst() {
        return formatAmount(this.totals.igst);
    }

    get formattedTotal() {
        return formatAmount(this.totals.grandTotal);
    }

    get hasCgstSgst() {
        return this.totals.cgst > 0 || this.totals.sgst > 0;
    }

    get hasIgst() {
        return this.totals.igst > 0;
    }

    // ---- more options ---------------------------------------------------

    get moreOptionsLabel() {
        return this.showMoreOptions ? this.labels.hideMoreOptions : this.labels.moreOptions;
    }

    get moreOptionsIcon() {
        return this.showMoreOptions ? 'utility:chevronup' : 'utility:chevrondown';
    }

    handleToggleMoreOptions() {
        this.showMoreOptions = !this.showMoreOptions;
    }

    handleDocumentDateChange(event) {
        this.documentDate = event.target.value;
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    // ---- submit ---------------------------------------------------------

    // The first thing still missing, shown above the Create button.
    get missingReason() {
        if (this.isCustomerMode) {
            if ((this.customer.phone || '').replace(/\D/g, '').length < 10) {
                return 'Enter the customer’s 10-digit phone number, or switch to Walk-in.';
            }
            if (!this.hasMatch && !(this.customer.name || '').trim()) {
                return 'Enter the customer’s name.';
            }
        }
        if (!this.hasItems) {
            return 'Add at least one part or item.';
        }
        const rows = this.lines;
        if (rows.some((row) => !row.description.trim())) {
            return 'Give every item a name.';
        }
        if (rows.some((row) => String(row.unitPrice).trim() === '' || Number(row.unitPrice) < 0)) {
            return 'Enter a price for every item.';
        }
        if (rows.some((row) => !(Number(row.quantity) > 0))) {
            return 'Every item needs a quantity.';
        }
        return '';
    }

    get createDisabled() {
        return this.isSubmitting || this.isLookingUp || !!this.missingReason;
    }

    get createLabel() {
        return this.isSubmitting ? 'Creating…' : this.labels.create;
    }

    buildRequest() {
        const typedVehicle = this.showVehicleFields && this.newVehicle.registrationNumber.trim() ? { ...this.newVehicle } : null;
        return {
            workshopProfileId: this.workshopProfileId || undefined,
            isWalkIn: this.isWalkIn,
            customerName: this.isWalkIn ? null : this.customer.name,
            customerPhone: this.isWalkIn ? null : this.customer.phone,
            customerAddress: this.isWalkIn ? null : this.customer.address,
            customerGstin: this.isWalkIn ? null : this.customer.gstin,
            customerState: this.isWalkIn ? null : this.customer.state,
            vehicleId: this.isWalkIn || !this.selectedVehicleId || this.isNewVehicleSelected ? null : this.selectedVehicleId,
            newVehicle: this.isWalkIn ? null : typedVehicle,
            documentDate: this.documentDate || null,
            notes: this.notes,
            includeGst: this.includeGst,
            lineItems: this.lines.map((row) => ({
                partId: row.partId,
                description: row.description.trim(),
                quantity: Number(row.quantity),
                unitPrice: Number(row.unitPrice),
                taxRatePercent: Number(row.taxRatePercent) || 0,
                gstType: row.gstType || 'CGST_SGST',
                hsnSacCode: row.hsnSacCode,
                unitLabel: row.unitLabel
            }))
        };
    }

    handleCreate() {
        if (this.createDisabled) {
            return;
        }
        this.isSubmitting = true;
        const create = this.isEstimate ? createQuickEstimate : createQuickBill;
        create({ request: this.buildRequest() })
            .then((summary) => {
                this.created = {
                    recordId: this.isEstimate ? summary.estimateId : summary.billId,
                    number: this.isEstimate ? summary.estimateNumber : summary.invoiceNumber,
                    customerName: summary.customerName,
                    formattedTotal: formatAmount(summary.totalAmount)
                };
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    // ---- after creation -------------------------------------------------

    get isCreated() {
        return !!this.created;
    }

    get isEditing() {
        return !this.created;
    }

    handlePrint() {
        this.showPreview = true;
    }

    handleClosePreview() {
        this.showPreview = false;
    }

    handleViewDocument() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: this.isEstimate ? 'Estimate_Detail' : 'Bill_Detail' },
            state: { c__recordId: this.created.recordId }
        });
    }

    // Keeps the Walk-in/Customer choice — a counter usually handles the same
    // kind of sale several times in a row.
    handleNewDocument() {
        this.customer = { ...EMPTY_CUSTOMER };
        this.match = undefined;
        this.showMoreCustomer = false;
        this.selectedVehicleId = null;
        this.newVehicle = { ...EMPTY_VEHICLE };
        this.lines = [];
        this.includeGst = false;
        // Walk-in goes straight to the items; Customer starts at the phone box.
        this._focusGridAfterRender = this.isWalkIn;
        this.documentDate = todayIso();
        this.notes = '';
        this.showMoreOptions = false;
        this.created = undefined;
        this.showPreview = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
