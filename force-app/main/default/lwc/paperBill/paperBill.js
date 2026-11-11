import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';
import searchCustomers from '@salesforce/apex/BillController.searchCustomers';
import findCustomerByPhone from '@salesforce/apex/QuickBillController.findCustomerByPhone';
import searchMakes from '@salesforce/apex/VehicleMakeModelController.searchMakes';
import searchModels from '@salesforce/apex/VehicleMakeModelController.searchModels';
import getCustomer from '@salesforce/apex/PaperBillController.getCustomer';
import amountInWords from '@salesforce/apex/PaperBillController.amountInWords';
import saveDocument from '@salesforce/apex/PaperBillController.saveDocument';
import getVehicleCard from '@salesforce/apex/ServiceBookController.getVehicleCard';
import { calculateBillTotals } from 'c/gstMath';
import { disablePullToRefresh } from 'c/disablePullToRefresh';

const DOCUMENT_OPTIONS = [
    { label: 'Bill', value: 'bill' },
    { label: 'Estimate', value: 'estimate' }
];

// Same wording as InvoicePdfController, so the page reads like the print.
const LABELS = {
    bill: {
        noun: 'Bill',
        billTo: 'Bill To',
        details: 'Invoice Details',
        number: 'Invoice No.',
        words: 'Invoice Amount In Words'
    },
    estimate: {
        noun: 'Estimate',
        billTo: 'Estimated For',
        details: 'Estimate Details',
        number: 'Estimate No.',
        words: 'Estimate Amount In Words'
    }
};

const EMPTY_CUSTOMER = { id: null, name: '', phone: '', address: '', gstin: '', state: '' };
const EMPTY_VEHICLE = { id: null, registrationNumber: '', make: '', model: '', chassisNumber: '' };
const EMPTY_WORKSHOP = {
    name: '', address: '', phone: '', email: '', gstin: '', state: '',
    bankName: '', bankAccountNo: '', bankIfsc: '', bankAccountHolder: '', termsAndConditions: ''
};
const WALK_IN_PHONE = '0000000000';
const WORDS_DELAY_MS = 400;

// One typed box in the printed format, not a date input: Chrome's date input
// takes four Tab presses (day, month, year, calendar button) to get past.
function todayText() {
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    return `${pad(now.getDate())}-${pad(now.getMonth() + 1)}-${now.getFullYear()}`;
}

// "4-11-2026", "04/11/26" and "04.11.2026" all work. Null if it isn't a real date.
function toIsoDate(text) {
    const parts = (text || '').trim().match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})$/);
    if (!parts) {
        return null;
    }
    const day = Number(parts[1]);
    const month = Number(parts[2]);
    const year = Number(parts[3].length === 2 ? `20${parts[3]}` : parts[3]);
    const date = new Date(year, month - 1, day);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
        return null;
    }
    const pad = (n) => String(n).padStart(2, '0');
    return `${year}-${pad(month)}-${pad(day)}`;
}

function formatAmount(value) {
    return (Number(value) || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatVisitDate(iso) {
    const [year, month, day] = iso.split('-').map(Number);
    return new Date(year, month - 1, day).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

function digitsOf(value) {
    return (value || '').replace(/\D/g, '');
}

/**
 * Easy Bill: the screen looks like the printed bill and everything is typed
 * straight onto it, for staff who find forms hard. Saves a normal bill or
 * estimate through PaperBillController. The invoice number is the one thing
 * that can't be typed, because numbering is assigned atomically on save.
 *
 * Boxes on the page are plain inputs styled to match InvoicePdf.page rather
 * than lightning-input: looking like the print is the whole point here.
 */
export default class PaperBill extends NavigationMixin(LightningElement) {
    documentOptions = DOCUMENT_OPTIONS;
    documentType = 'bill';

    workshopProfileId;
    workshop = { ...EMPTY_WORKSHOP };
    isEditingWorkshop = false;
    _savedWorkshop;

    customer = { ...EMPTY_CUSTOMER };
    originalCustomerName;
    vehicle = { ...EMPTY_VEHICLE };
    customerVehicles = [];

    documentDate = todayText();
    lines = [];
    includeGst = false;
    notes = '';
    words = '';

    // Opened from a Service Book card: that visit's work, to bill from. Not printed.
    visitWork = [];

    isSaving = false;
    saved;
    showPreview = false;

    _openedFrom;
    _wordsTimer;
    _focusTimers = [];
    _focusAfterRender = false;

    connectedCallback() {
        disablePullToRefresh(this);
        this.scheduleFirstFocus();
    }

    // The Service Book opens this page for a customer and car it already knows.
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        const state = (pageRef && pageRef.state) || {};
        if (!state.c__customerId || state.c__opened === this._openedFrom) {
            return;
        }
        this._openedFrom = state.c__opened;
        if (state.c__documentType === 'estimate' || state.c__documentType === 'bill') {
            this.documentType = state.c__documentType;
        }
        getCustomer({ customerId: state.c__customerId })
            .then((match) => {
                this.applyCustomer(match);
                const vehicle = this.customerVehicles.find((v) => v.id === state.c__vehicleId);
                if (vehicle) {
                    this.applyVehicle(vehicle);
                }
                // The only thing left to type is the items.
                this.focusGrid();
            })
            .catch((error) => this.showError(error));
        this.visitWork = [];
        if (state.c__vehicleId && state.c__entryDate) {
            getVehicleCard({ vehicleId: state.c__vehicleId, entryDate: state.c__entryDate })
                .then((card) => {
                    const days = [...(card.visitDays || [])];
                    if (card.workDone) {
                        days.push({ entryDate: state.c__entryDate, workDone: card.workDone });
                    }
                    days.sort((a, b) => (a.entryDate < b.entryDate ? -1 : 1));
                    this.visitWork = days.map((day) => ({ ...day, dateLabel: formatVisitDate(day.entryDate) }));
                })
                .catch((error) => this.showError(error));
        }
    }

    get hasVisitWork() {
        return this.visitWork.length > 0;
    }

    // The page shows whichever company is chosen. With none on file yet there's
    // nothing to print at the top, so those boxes start open.
    handleCompanyChange(event) {
        const { id, profile } = event.detail;
        this.workshopProfileId = id;
        this._savedWorkshop = { ...EMPTY_WORKSHOP, ...(profile || {}) };
        this.workshop = { ...this._savedWorkshop };
        this.isEditingWorkshop = !profile;
    }

    // Lightning takes focus back while its page is still settling, so a single
    // focus() on first render is lost and the first keys typed go nowhere.
    // Not on a phone, where it would pop the keyboard over the page.
    scheduleFirstFocus() {
        if (FORM_FACTOR !== 'Large') {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._focusTimers = [0, 800, 2000, 4000].map((delay) => setTimeout(() => this.focusNameIfNowhereElse(), delay));
    }

    focusNameIfNowhereElse() {
        if (!this.template.activeElement) {
            this.focusCustomerName();
        }
    }

    renderedCallback() {
        if (this._focusAfterRender) {
            this._focusAfterRender = false;
            this.focusCustomerName();
        }
    }

    disconnectedCallback() {
        clearTimeout(this._wordsTimer);
        this._focusTimers.forEach((timer) => clearTimeout(timer));
    }

    focusCustomerName() {
        const name = this.template.querySelector('[data-id="customer-name"]');
        if (name) {
            name.focus();
        }
    }

    // ---- what the page shows --------------------------------------------

    get isEstimate() {
        return this.documentType === 'estimate';
    }

    get labels() {
        return this.isEstimate ? LABELS.estimate : LABELS.bill;
    }

    get billLines() {
        return this.includeGst ? this.lines : this.lines.map((line) => ({ ...line, taxRatePercent: 0 }));
    }

    get totals() {
        return calculateBillTotals(this.billLines);
    }

    // Same rule as InvoicePdfController: with no GST there's nothing to call a tax invoice.
    get documentTitle() {
        if (this.isEstimate) {
            return 'Estimate';
        }
        return this.hasGstAmount ? 'Tax Invoice' : 'Bill';
    }

    get hasGstAmount() {
        return this.totals.gst > 0;
    }

    get hasCgstSgst() {
        return this.totals.cgst > 0 || this.totals.sgst > 0;
    }

    get hasIgst() {
        return this.totals.igst > 0;
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

    get gstButtonLabel() {
        return this.includeGst ? 'Remove GST' : 'Add GST';
    }

    get gstButtonIcon() {
        return this.includeGst ? 'utility:dash' : 'utility:add';
    }

    get saveLabel() {
        return this.isSaving ? 'Saving…' : `Save ${this.labels.noun}`;
    }

    get savedLabel() {
        return `${this.labels.noun} saved`;
    }

    get viewLabel() {
        return `View ${this.labels.noun}`;
    }

    get newLabel() {
        return `New ${this.labels.noun}`;
    }

    get isExistingCustomer() {
        return !!this.customer.id;
    }

    get billTakesStock() {
        return !this.isEstimate;
    }

    get showExistingNote() {
        return this.isExistingCustomer && !this.isRenamingCustomer;
    }

    get isRenamingCustomer() {
        return this.isExistingCustomer && !!this.originalCustomerName && this.customer.name.trim() !== this.originalCustomerName;
    }

    get workshopToggleLabel() {
        return this.isEditingWorkshop ? 'Keep workshop details as they are' : 'Change workshop details';
    }

    get showBank() {
        const w = this.workshop;
        return this.isEditingWorkshop || !!(w.bankName || w.bankAccountNo || w.bankIfsc || w.bankAccountHolder);
    }

    // The first thing still missing, shown above the Save button.
    get missingReason() {
        const c = this.customer;
        const v = this.vehicle;
        if (this.isEditingWorkshop && !this.workshop.name.trim()) {
            return 'Type your workshop name at the top.';
        }
        if (!c.name.trim() && (c.phone.trim() || c.address.trim() || c.gstin.trim() || c.state.trim())) {
            return 'Type the customer name.';
        }
        if (!v.registrationNumber.trim() && (v.make.trim() || v.model.trim() || v.chassisNumber.trim())) {
            return 'Type the vehicle number, or clear the vehicle details.';
        }
        if (this.documentDate.trim() && !toIsoDate(this.documentDate)) {
            return 'Type the date like 04-11-2026.';
        }
        if (!this.lines.length) {
            return 'Type a product name and price in the table.';
        }
        if (this.lines.some((line) => !line.description.trim())) {
            return 'Type a product name on every line.';
        }
        if (this.lines.some((line) => String(line.unitPrice).trim() === '' || Number(line.unitPrice) < 0)) {
            return 'Type a price on every line.';
        }
        if (this.lines.some((line) => !(Number(line.quantity) > 0))) {
            return 'Type a quantity on every line.';
        }
        return '';
    }

    get saveDisabled() {
        return this.isSaving || !!this.missingReason;
    }

    get isEditing() {
        return !this.saved;
    }

    // ---- typing on the page ---------------------------------------------

    handleDocumentTypeChange(event) {
        this.documentType = event.detail.value;
    }

    handleDateChange(event) {
        this.documentDate = event.detail.value;
    }

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    handleWorkshopChange(event) {
        this.workshop = { ...this.workshop, [event.target.dataset.field]: event.detail.value };
    }

    handleToggleWorkshop() {
        // Going back to locked discards unsaved changes to these details.
        if (this.isEditingWorkshop) {
            this.workshop = { ...this._savedWorkshop };
        }
        this.isEditingWorkshop = !this.isEditingWorkshop;
    }

    handleCustomerChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this.customer = { ...this.customer, [field]: value };
        if (field === 'phone' && this.isExistingCustomer) {
            // A different number is a different person.
            this.customer = { ...this.customer, id: null };
            this.originalCustomerName = undefined;
            this.customerVehicles = [];
            this.vehicle = { ...this.vehicle, id: null };
        }
    }

    // A full mobile number typed by hand finds the customer without a pick.
    handlePhoneLeave() {
        const phone = this.customer.phone;
        if (this.isExistingCustomer || digitsOf(phone).length < 10) {
            return;
        }
        findCustomerByPhone({ phone })
            .then((match) => {
                if (match && !this.customer.id && this.customer.phone === phone) {
                    this.applyCustomer(match);
                }
            })
            .catch((error) => this.showError(error));
    }

    handleCustomerPick(event) {
        getCustomer({ customerId: event.detail.option.value })
            .then((match) => this.applyCustomer(match))
            .catch((error) => this.showError(error));
    }

    applyCustomer(match) {
        this.customer = {
            id: match.id,
            name: match.name || '',
            phone: match.phone === WALK_IN_PHONE ? '' : match.phone || '',
            address: match.address || '',
            gstin: match.gstin || '',
            state: match.state || ''
        };
        this.originalCustomerName = match.name;
        this.customerVehicles = match.vehicles || [];
        this.vehicle = { ...this.vehicle, id: null };
        if (this.customerVehicles.length === 1 && !this.vehicle.registrationNumber.trim()) {
            this.applyVehicle(this.customerVehicles[0]);
        }
    }

    searchCustomerOptions = (term) =>
        searchCustomers({ searchTerm: term }).then((results) =>
            results
                .filter((c) => !(c.phone === WALK_IN_PHONE && c.name === 'Walk-in Customer'))
                .map((c) => ({ value: c.id, label: c.name, sub: c.phone === WALK_IN_PHONE ? '' : c.phone }))
        );

    handleVehicleChange(event) {
        const field = event.target.dataset.field;
        this.vehicle = { ...this.vehicle, [field]: event.detail.value };
        if (field === 'registrationNumber') {
            // A different number is a different vehicle.
            this.vehicle = { ...this.vehicle, id: null };
        }
    }

    handleVehicleNumberLeave() {
        const typed = this.vehicle.registrationNumber.trim().toLowerCase();
        const known = this.customerVehicles.find((v) => (v.registrationNumber || '').toLowerCase() === typed);
        if (known && !this.vehicle.id) {
            this.applyVehicle(known);
        }
    }

    handleVehiclePick(event) {
        const picked = this.customerVehicles.find((v) => v.id === event.detail.option.value);
        if (picked) {
            this.applyVehicle(picked);
        }
    }

    applyVehicle(vehicle) {
        this.vehicle = {
            id: vehicle.id,
            registrationNumber: vehicle.registrationNumber || '',
            make: vehicle.make || '',
            model: vehicle.model || '',
            chassisNumber: vehicle.chassisNumber || ''
        };
    }

    searchVehicleOptions = (term) => {
        const typed = term.toLowerCase();
        return Promise.resolve(
            this.customerVehicles
                .filter((v) => (v.registrationNumber || '').toLowerCase().includes(typed))
                .map((v) => ({ value: v.id, label: v.registrationNumber, sub: [v.make, v.model].filter((p) => p).join(' ') }))
        );
    };

    searchMakeOptions = (term) =>
        searchMakes({ term }).then((results) => results.map((value) => ({ value, label: value, sub: '' })));

    searchModelOptions = (term) =>
        searchModels({ make: this.vehicle.make, term }).then((results) => results.map((value) => ({ value, label: value, sub: '' })));

    handleMakeModelPick(event) {
        this.vehicle = { ...this.vehicle, [event.target.dataset.field]: event.detail.option.value };
    }

    handleLinesChange(event) {
        this.lines = event.detail.lines;
        this.scheduleWords();
    }

    handleToggleGst() {
        this.includeGst = !this.includeGst;
        this.scheduleWords();
    }

    scheduleWords() {
        clearTimeout(this._wordsTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._wordsTimer = setTimeout(() => this.refreshWords(), WORDS_DELAY_MS);
    }

    refreshWords() {
        const amount = this.totals.grandTotal;
        if (!(amount > 0)) {
            this.words = '';
            return Promise.resolve();
        }
        return amountInWords({ amount })
            .then((words) => {
                if (amount === this.totals.grandTotal) {
                    this.words = words;
                }
            })
            .catch((error) => this.showError(error));
    }

    // ---- keyboard -------------------------------------------------------

    handleKeydown(event) {
        const key = (event.key || '').toLowerCase();
        if ((event.ctrlKey || event.metaKey) && (key === 's' || key === 'enter')) {
            event.preventDefault();
            this.handleSave();
        } else if (event.altKey && key === 'g') {
            event.preventDefault();
            this.handleToggleGst();
        }
    }

    // Enter goes to the next box on the page, in the order they print.
    handleAdvance(event) {
        const field = event.target;
        // Nobody to name, so jump straight to the items.
        if (field.dataset.id === 'customer-name' && !this.customer.name.trim()) {
            this.focusGrid();
            return;
        }
        if (field.dataset.next === 'grid') {
            this.focusGrid();
            return;
        }
        const boxes = [...this.template.querySelectorAll('c-paper-field')];
        const next = boxes[boxes.indexOf(field) + 1];
        if (next) {
            next.focus();
        } else {
            this.focusSave();
        }
    }

    focusGrid() {
        const grid = this.template.querySelector('c-line-item-grid');
        if (grid) {
            grid.focusFirst();
        }
    }

    focusSave() {
        const save = this.template.querySelector('[data-id="save"]');
        if (save) {
            save.focus();
        }
    }

    // ---- saving ---------------------------------------------------------

    buildRequest() {
        const c = this.customer;
        const v = this.vehicle;
        return {
            workshopProfileId: this.workshopProfileId || undefined,
            documentType: this.documentType,
            customerId: c.id,
            customerName: c.name,
            customerPhone: c.phone,
            customerAddress: c.address,
            customerGstin: c.gstin,
            customerState: c.state,
            vehicleId: v.id,
            registrationNumber: v.registrationNumber,
            make: v.make,
            model: v.model,
            chassisNumber: v.chassisNumber,
            documentDate: toIsoDate(this.documentDate),
            notes: this.notes,
            includeGst: this.includeGst,
            workshop: this.isEditingWorkshop ? { ...this.workshop } : null,
            lineItems: this.lines.map((line) => ({
                partId: line.partId,
                description: line.description.trim(),
                hsnSacCode: line.hsnSacCode,
                unitLabel: line.unitLabel,
                quantity: Number(line.quantity),
                unitPrice: Number(line.unitPrice),
                taxRatePercent: Number(line.taxRatePercent) || 0,
                gstType: line.gstType || 'CGST_SGST'
            }))
        };
    }

    handleSave() {
        if (this.isSaving) {
            return;
        }
        if (this.missingReason) {
            this.showToast(this.missingReason, '', 'warning');
            return;
        }
        this.isSaving = true;
        saveDocument({ request: this.buildRequest() })
            .then((saved) => {
                this.saved = { ...saved, formattedTotal: formatAmount(saved.totalAmount) };
                this.isEditingWorkshop = false;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSaving = false;
            });
    }

    handlePrint() {
        this.showPreview = true;
    }

    handleClosePreview() {
        this.showPreview = false;
    }

    handleView() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: this.isEstimate ? 'Estimate_Detail' : 'Bill_Detail' },
            state: { c__recordId: this.saved.recordId }
        });
    }

    handleNew() {
        this.customer = { ...EMPTY_CUSTOMER };
        this.originalCustomerName = undefined;
        this.vehicle = { ...EMPTY_VEHICLE };
        this.customerVehicles = [];
        this.documentDate = todayText();
        this.lines = [];
        this.includeGst = false;
        this.notes = '';
        this.words = '';
        this.visitWork = [];
        this.saved = undefined;
        this.showPreview = false;
        this._focusAfterRender = true;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
