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
import getDocument from '@salesforce/apex/PaperBillController.getDocument';
import cancelBill from '@salesforce/apex/BillController.cancelBill';
import deleteEstimate from '@salesforce/apex/EstimateController.deleteEstimate';
import getVehicleCard from '@salesforce/apex/ServiceBookController.getVehicleCard';
import listBillToParties from '@salesforce/apex/DirectoryController.listBillToParties';
import { calculateBillTotals, splitClaim, lineGross } from 'c/gstMath';
import {
    searchStates,
    stateName,
    gstinProblem,
    withStateFromGstin,
    todayIso,
    financialYearOf,
    isInFiledMonth,
    filedLockText,
    monthLabel
} from 'c/gst';
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
        toParty: 'Bill to a company or insurance',
        toCustomer: 'Bill the customer instead',
        details: 'Invoice Details',
        number: 'Invoice No.',
        words: 'Invoice Amount In Words'
    },
    estimate: {
        noun: 'Estimate',
        billTo: 'Estimated For',
        toParty: 'Estimate for a company or insurance',
        toCustomer: 'Estimate for the customer instead',
        details: 'Estimate Details',
        number: 'Estimate No.',
        words: 'Estimate Amount In Words'
    }
};

const EMPTY_CUSTOMER = { id: null, name: '', phone: '', address: '', gstin: '', state: '' };
const EMPTY_VEHICLE = { id: null, registrationNumber: '', make: '', model: '', chassisNumber: '' };
const EMPTY_PARTY = { id: null, name: '', address: '', contactPhone: '', gstin: '', state: '' };
const PARTY_DETAILS = ['address', 'contactPhone', 'gstin', 'state'];
const PARTIES_SHOWN = 8;
const GSTIN_LENGTH = 15;
const EMPTY_WORKSHOP = {
    name: '', address: '', phone: '', email: '', gstin: '', state: '',
    bankName: '', bankAccountNo: '', bankIfsc: '', bankAccountHolder: '', termsAndConditions: ''
};
const WALK_IN_PHONE = '0000000000';
const COMPOSITION_NOTE = 'Composition taxable person, not eligible to collect tax on supplies.';
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

// "2026-11-03" from Apex, shown as the page types it: "03-11-2026".
function isoToText(iso) {
    if (!iso) {
        return todayText();
    }
    const [year, month, day] = iso.split('-');
    return `${day}-${month}-${year}`;
}

// A wrong GSTIN or a state that isn't one, said for whose it is.
function detailsProblem(details, whose) {
    const gstinIssue = gstinProblem(details.gstin);
    if (gstinIssue) {
        return `The ${whose} GSTIN: ${gstinIssue}`;
    }
    const state = (details.state || '').trim();
    if (state && !stateName(state)) {
        return `Pick the ${whose} state from the list ("${state}" is not a state).`;
    }
    return '';
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

    // Billing a company (insurance, fleet, firm) instead of the customer.
    // The car owner then prints as the Buyer's Name, as on InvoicePdf.page.
    isBillToParty = false;
    party = { ...EMPTY_PARTY };
    _pickedParty;
    _partyResults = new Map();
    _focusPartyAfterRender = false;

    documentDate = todayText();
    lines = [];
    includeGst = false;
    notes = '';
    words = '';

    // The chosen company's settings (G5): whole-rupee totals, and whether it
    // charges GST at all (a composition or unregistered company doesn't).
    roundOffTotals = true;
    registrationType;
    showDiscount = false;

    // An insurance claim (G6): the party pays each line's percent, the
    // customer the rest plus the compulsory excess, on two bills saved together.
    insuranceSplit = false;
    compulsoryExcess = '';
    // Which saved bill the preview shows, when not the main one.
    previewTarget;

    // Opened from a Service Book card: that visit's work, to bill from. Not printed.
    visitWork = [];

    // A saved bill or estimate opened from the Billing list: { recordId,
    // documentNumber, versionNumber, isLatestVersion }. Saving makes its new
    // version (architecture.md §C.4); it is never changed in place.
    opened;
    isLoadingDocument = false;
    isDeleting = false;
    // The chosen company's "GST returns filed up to" ("yyyy-mm-dd"), if any.
    companyFiledUpTo;
    _pendingLines;

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

    // The Billing list opens a saved bill or estimate here (c__editId), and the
    // Service Book opens this page for a customer and car it already knows.
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        const state = (pageRef && pageRef.state) || {};
        if (state.c__editId && state.c__opened !== this._openedFrom) {
            this._openedFrom = state.c__opened;
            this.loadDocument(state.c__editId);
            return;
        }
        if (!state.c__customerId || state.c__opened === this._openedFrom) {
            return;
        }
        this._openedFrom = state.c__opened;
        // Not on top of an opened bill: its lines would go on this car's bill.
        if (this.opened) {
            this.resetPage();
        }
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
        this.companyFiledUpTo = profile ? profile.gstFiledUpTo : null;
        this.roundOffTotals = !profile || profile.roundOffTotals !== false;
        this.registrationType = profile ? profile.gstRegistrationType : null;
        this.workshop = { ...this._savedWorkshop };
        this.isEditingWorkshop = !profile;
        this.scheduleWords();
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
        // A saved document's lines wait for the grid, which isn't drawn while
        // the saved screen is showing.
        const grid = this._pendingLines && this.template.querySelector('c-line-item-grid');
        if (grid) {
            const lines = this._pendingLines;
            this._pendingLines = undefined;
            grid.setLines(lines);
        }
        if (this._focusAfterRender) {
            this._focusAfterRender = false;
            this.focusCustomerName();
        }
        if (this._focusPartyAfterRender) {
            this._focusPartyAfterRender = false;
            const name = this.template.querySelector('[data-id="party-name"]');
            if (name) {
                name.focus();
            }
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

    // Blank is a regular registration, as on the server (WorkshopProfileService.chargesGst).
    get chargesGst() {
        return !this.registrationType || this.registrationType === 'Regular';
    }

    get isComposition() {
        return this.registrationType === 'Composition';
    }

    get billIncludesGst() {
        return this.includeGst && this.chargesGst;
    }

    get billLines() {
        return this.billIncludesGst ? this.lines : this.lines.map((line) => ({ ...line, taxRatePercent: 0 }));
    }

    get totals() {
        return calculateBillTotals(this.billLines, { roundOff: this.roundOffTotals });
    }

    // Same rule as InvoicePdfController: with no GST there's nothing to call a
    // tax invoice, and a composition company issues a bill of supply.
    get documentTitle() {
        if (this.isEstimate) {
            return 'Estimate';
        }
        if (this.isComposition) {
            return 'Bill of Supply';
        }
        return this.hasGstAmount ? 'Tax Invoice' : 'Bill';
    }

    get compositionNote() {
        return !this.isEstimate && this.isComposition ? COMPOSITION_NOTE : '';
    }

    get hasRoundOff() {
        return this.totals.roundOff !== 0;
    }

    get showSubtotal() {
        return this.hasGstAmount || this.hasRoundOff;
    }

    get formattedRoundOff() {
        const value = this.totals.roundOff;
        return `${value > 0 ? '+' : '-'}${formatAmount(Math.abs(value))}`;
    }

    get discountButtonLabel() {
        return this.showDiscount ? 'Remove discount' : 'Add discount';
    }

    get discountButtonIcon() {
        return this.showDiscount ? 'utility:dash' : 'utility:add';
    }

    // ---- insurance claim split -------------------------------------------

    // A new bill to a party only: an estimate isn't split, and a saved bill's
    // halves are changed one at a time.
    get canSplit() {
        return this.isBillToParty && !this.isEstimate && this.isNewDocument;
    }

    get showSplit() {
        return this.canSplit && this.insuranceSplit;
    }

    get splitButtonLabel() {
        return this.insuranceSplit ? 'Bill the whole job to the party' : 'Split with the customer (insurance claim)';
    }

    get excessProblem() {
        const text = String(this.compulsoryExcess || '').trim();
        return text && !(Number(text) >= 0) ? 'Type the compulsory excess in rupees, like 1000.' : '';
    }

    get split() {
        if (!this.showSplit || !this.lines.length || this.excessProblem) {
            return null;
        }
        return splitClaim(this.billLines, this.compulsoryExcess);
    }

    get splitTotals() {
        const split = this.split;
        if (!split || split.error) {
            return null;
        }
        const options = { roundOff: this.roundOffTotals };
        const insurer = calculateBillTotals(split.insurerLines, options).grandTotal;
        const customer = calculateBillTotals(split.customerLines, options).grandTotal;
        // Each bill is rounded to the rupee on its own, so together they can be
        // a rupee off the job's rounded total.
        const apart = Math.round((insurer + customer - this.totals.grandTotal) * 100) / 100;
        return {
            insurer: formatAmount(insurer),
            customer: formatAmount(customer),
            note: apart !== 0 ? `Each bill is rounded on its own, so together they come to Rs. ${formatAmount(insurer + customer)}.` : ''
        };
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
        if (this.isSaving) {
            return 'Saving…';
        }
        return this.opened ? 'Save Changes' : `Save ${this.labels.noun}`;
    }

    get savedLabel() {
        if (this.saved && this.saved.pairedNumber) {
            return 'Claim bills saved';
        }
        return this.saved && this.saved.replacedNumber ? `${this.labels.noun} changes saved` : `${this.labels.noun} saved`;
    }

    // ---- a saved document opened here --------------------------------------

    get isNewDocument() {
        return !this.opened;
    }

    get isOpenedDocument() {
        return !!this.opened;
    }

    get openedText() {
        const o = this.opened;
        const version = o.versionNumber > 1 ? ` (version ${o.versionNumber})` : '';
        if (o.isCancelled) {
            return `${this.labels.noun} ${o.documentNumber} was deleted. Its number stays in your GST records as cancelled; it can be looked at and printed, not changed.`;
        }
        if (o.isGstFiled) {
            return `${this.labels.noun} ${o.documentNumber}${version}: ${filedLockText(o.gstFiledUpTo)}`;
        }
        if (!o.isLatestVersion) {
            return `${this.labels.noun} ${o.documentNumber}${version} is an older version. Open the latest one from the Billing list to change it.`;
        }
        return `Opened ${this.labels.noun} ${o.documentNumber}${version}. Change anything and save: this one is kept, and the changed ${this.labels.noun.toLowerCase()} is saved with a new number.`;
    }

    get openedPairText() {
        const o = this.opened;
        return o && o.pairedNumber ? `One of two bills for an insurance claim, with ${o.pairedNumber}. Changing this one doesn't change that one.` : '';
    }

    get autoNumberText() {
        if (this.opened) {
            return `New number when you save (now ${this.opened.documentNumber})`;
        }
        // An old date joins its own year's series: say so, so it's no surprise.
        const date = toIsoDate(this.documentDate);
        if (!this.isEstimate && date && financialYearOf(date) !== financialYearOf(todayIso())) {
            return `Given when you save (${financialYearOf(date)} series)`;
        }
        return 'Given when you save';
    }

    // Deleted, filed, or replaced since: shown, but not to be changed or deleted.
    get canChangeOpened() {
        const o = this.opened;
        return !!o && o.isLatestVersion && !o.isCancelled && !o.isGstFiled;
    }

    get deleteOpenedMessage() {
        const number = this.opened.documentNumber;
        return this.isEstimate
            ? `Delete ${number}, with all its earlier versions? This can't be undone.`
            : `Delete ${number}? For GST its number is kept and shown as cancelled, and its parts go back to stock. This can't be undone.`;
    }

    handleDeleteOpened() {
        const number = this.opened.documentNumber;
        const recordId = this.opened.recordId;
        this.isDeleting = true;
        const work = this.isEstimate ? deleteEstimate({ estimateId: recordId }) : cancelBill({ billId: recordId });
        work.then(() => {
            this.showToast(`${number} deleted`, this.isEstimate ? '' : 'Its number stays in your GST records as cancelled.', 'success');
            this.resetPage();
            this._focusAfterRender = true;
        })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isDeleting = false;
            });
    }

    get previewRecordId() {
        if (this.previewTarget) {
            return this.previewTarget.recordId;
        }
        return this.saved ? this.saved.recordId : this.opened && this.opened.recordId;
    }

    get previewHeading() {
        if (this.previewTarget) {
            return this.previewTarget.heading;
        }
        return this.saved ? this.saved.documentNumber : this.opened && this.opened.documentNumber;
    }

    loadDocument(recordId) {
        this.isLoadingDocument = true;
        return getDocument({ recordId })
            .then((doc) => this.applyDocument(doc))
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoadingDocument = false;
            });
    }

    applyDocument(doc) {
        this.resetPage();
        this.opened = {
            recordId: doc.recordId,
            documentNumber: doc.documentNumber,
            versionNumber: doc.versionNumber,
            isLatestVersion: doc.isLatestVersion,
            isCancelled: !!doc.isCancelled,
            isGstFiled: !!doc.isGstFiled,
            gstFiledUpTo: doc.gstFiledUpTo,
            pairedNumber: doc.pairedNumber
        };
        this.documentType = doc.documentType;
        this.workshopProfileId = doc.workshopProfileId;
        if (doc.customer) {
            this.applyCustomer(doc.customer);
        }
        // Exactly the document's vehicle: applyCustomer may have picked the
        // customer's only car for a document that had none.
        this.vehicle = { ...EMPTY_VEHICLE };
        if (doc.vehicle) {
            this.applyVehicle(doc.vehicle);
        }
        if (doc.billToParty) {
            this.isBillToParty = true;
            this.applyParty(doc.billToParty);
        }
        this.documentDate = isoToText(doc.documentDate);
        this.notes = doc.notes || '';
        this.includeGst = !!doc.includeGst;
        this._pendingLines = doc.lines || [];
        this.showDiscount = this._pendingLines.some((line) => Number(line.discount) > 0);
    }

    handleViewOpened() {
        this.showPreview = true;
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

    get partyToggleLabel() {
        return this.isBillToParty ? this.labels.toCustomer : this.labels.toParty;
    }

    get isExistingParty() {
        return !!this.party.id;
    }

    get isChangingParty() {
        const picked = this._pickedParty;
        return this.isExistingParty && !!picked && PARTY_DETAILS.some((field) => this.party[field].trim() !== (picked[field] || '').trim());
    }

    // InvoicePdf.page prints the party from its record, so changing a saved
    // party's details here changes them on every bill it's on.
    get partyNote() {
        if (this.isChangingParty) {
            return `This changes ${this.party.name}'s details on all its bills.`;
        }
        if (this.isExistingParty) {
            return 'Saved party. Details filled in for you.';
        }
        if (this.party.name.trim()) {
            return 'New party. It is saved for next time.';
        }
        return '';
    }

    get partyNoteClass() {
        return this.isChangingParty ? 'pb-note' : 'pb-note pb-note_ok';
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
        if (this.opened && this.opened.isCancelled) {
            return 'This bill was deleted, so it can\'t be changed.';
        }
        if (this.opened && this.opened.isGstFiled) {
            return `GST is filed up to ${monthLabel(this.opened.gstFiledUpTo)}, so this bill can't be changed.`;
        }
        if (this.opened && !this.opened.isLatestVersion) {
            return 'This is an older version. Open the latest one from the Billing list to change it.';
        }
        if (this.isEditingWorkshop && !this.workshop.name.trim()) {
            return 'Type your workshop name at the top.';
        }
        if (this.isEditingWorkshop) {
            const workshopProblem = detailsProblem(this.workshop, 'workshop');
            if (workshopProblem) {
                return workshopProblem;
            }
        }
        if (this.isBillToParty && !this.party.name.trim()) {
            return `Type the party name, or choose "${this.labels.toCustomer}".`;
        }
        if (this.isBillToParty && this.party.gstin.trim().length > GSTIN_LENGTH) {
            return 'The party GSTIN should be 15 characters.';
        }
        if (this.isBillToParty) {
            const partyProblem = detailsProblem(this.party, 'party');
            if (partyProblem) {
                return partyProblem;
            }
        } else {
            // Only when shown: on a party bill the customer's GSTIN isn't on the page.
            const customerProblem = detailsProblem(this.customer, 'customer');
            if (customerProblem) {
                return customerProblem;
            }
        }
        if (!c.name.trim() && (c.phone.trim() || c.address.trim() || c.gstin.trim() || c.state.trim())) {
            return this.isBillToParty ? 'Type the buyer’s name.' : 'Type the customer name.';
        }
        if (!v.registrationNumber.trim() && (v.make.trim() || v.model.trim() || v.chassisNumber.trim())) {
            return 'Type the vehicle number, or clear the vehicle details.';
        }
        if (this.documentDate.trim() && !toIsoDate(this.documentDate)) {
            return 'Type the date like 04-11-2026.';
        }
        const date = toIsoDate(this.documentDate);
        if (!this.isEstimate && date && date > todayIso()) {
            return 'A bill can\'t be dated in the future.';
        }
        if (!this.isEstimate && isInFiledMonth(this.companyFiledUpTo, date)) {
            return `GST is filed up to ${monthLabel(this.companyFiledUpTo)} for this company: date the bill after that.`;
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
        if (this.lines.some((line) => Number(line.discount) < 0 || Number(line.discount) > lineGross(line))) {
            return 'A discount is more than its line\'s price, or below zero.';
        }
        if (this.showSplit) {
            if (!this.customer.id && !this.customer.name.trim()) {
                return 'Type the car owner as Buyer\'s Name: they get a bill for their share.';
            }
            if (this.excessProblem) {
                return this.excessProblem;
            }
            if (this.split && this.split.error) {
                return this.split.error;
            }
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
        const field = event.target.dataset.field;
        this.workshop = { ...this.workshop, [field]: event.detail.value };
        if (field === 'gstin') {
            this.workshop = withStateFromGstin(this.workshop);
        }
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
        if (field === 'gstin') {
            this.customer = withStateFromGstin(this.customer);
        }
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

    // ---- bill to party ----------------------------------------------------

    handleToggleParty() {
        this.isBillToParty = !this.isBillToParty;
        if (this.isBillToParty) {
            this._focusPartyAfterRender = true;
        } else {
            this._focusAfterRender = true;
        }
    }

    handlePartyChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        if (field === 'name' && this.isExistingParty) {
            // A different name is a different party. Its old details go too, so a
            // saved party's GSTIN can't end up on someone else's tax invoice.
            this.party = { ...EMPTY_PARTY, name: value };
            this._pickedParty = undefined;
            return;
        }
        this.party = { ...this.party, [field]: value };
        if (field === 'gstin') {
            this.party = withStateFromGstin(this.party);
        }
    }

    // ---- states ------------------------------------------------------------
    // Each State box belongs to a group (data-group): customer, party or workshop.

    searchStateOptions = (term) => Promise.resolve(searchStates(term).map((name) => ({ value: name, label: name, sub: '' })));

    handleStatePick(event) {
        const group = event.target.dataset.group;
        this[group] = { ...this[group], state: event.detail.option.value };
    }

    // "MP" or "madhyapradesh" typed without picking becomes the state's name.
    handleStateLeave(event) {
        const group = event.target.dataset.group;
        const name = stateName(this[group].state);
        if (name && name !== this[group].state) {
            this[group] = { ...this[group], state: name };
        }
    }

    // Saved parties show as soon as the box is entered, so one can be picked
    // without typing anything.
    searchPartyOptions = (term) =>
        listBillToParties({ searchTerm: term }).then((results) => {
            this._partyResults = new Map(results.map((p) => [p.id, p]));
            return results
                .slice(0, PARTIES_SHOWN)
                .map((p) => ({ value: p.id, label: p.name, sub: p.gstin || p.contactPhone || p.state || '' }));
        });

    handlePartyPick(event) {
        const picked = this._partyResults.get(event.detail.option.value);
        if (picked) {
            this.applyParty(picked);
        }
    }

    // A saved party's name typed in full, without picking it, still finds it.
    handlePartyNameLeave() {
        const p = this.party;
        const typed = p.name.trim().toLowerCase();
        if (this.isExistingParty || !typed || PARTY_DETAILS.some((field) => p[field].trim())) {
            return;
        }
        const known = [...this._partyResults.values()].find((saved) => (saved.name || '').toLowerCase() === typed);
        if (known) {
            this.applyParty(known);
        }
    }

    applyParty(saved) {
        this.party = {
            id: saved.id,
            name: saved.name || '',
            address: saved.address || '',
            contactPhone: saved.contactPhone || '',
            gstin: saved.gstin || '',
            state: saved.state || ''
        };
        this._pickedParty = { ...this.party };
    }

    // ---- vehicle ----------------------------------------------------------

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
        if (!this.chargesGst) {
            return;
        }
        this.includeGst = !this.includeGst;
        this.scheduleWords();
    }

    // Turning it off clears the discounts (the grid does, and reports the lines).
    handleToggleDiscount() {
        this.showDiscount = !this.showDiscount;
    }

    handleToggleSplit() {
        this.insuranceSplit = !this.insuranceSplit;
    }

    handleExcessChange(event) {
        this.compulsoryExcess = event.detail.value;
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
        } else if (event.altKey && key === 'p') {
            event.preventDefault();
            this.handleToggleParty();
        } else if (event.altKey && key === 'd') {
            event.preventDefault();
            this.handleToggleDiscount();
        }
    }

    // Enter goes to the next box on the page, in the order they print.
    handleAdvance(event) {
        const field = event.target;
        // Nobody to name, so jump straight to the items. Not on a party bill,
        // where the buyer's name is optional and the vehicle comes next.
        if (field.dataset.id === 'customer-name' && !this.isBillToParty && !this.customer.name.trim()) {
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
        const p = this.party;
        return {
            workshopProfileId: this.workshopProfileId || undefined,
            documentType: this.documentType,
            previousVersionId: this.opened ? this.opened.recordId : null,
            customerId: c.id,
            customerName: c.name,
            customerPhone: c.phone,
            customerAddress: c.address,
            customerGstin: c.gstin,
            customerState: c.state,
            billToPartyId: this.isBillToParty ? p.id : null,
            billToParty: this.isBillToParty
                ? { name: p.name.trim(), address: p.address, contactPhone: p.contactPhone, gstin: p.gstin.trim(), state: p.state }
                : null,
            vehicleId: v.id,
            registrationNumber: v.registrationNumber,
            make: v.make,
            model: v.model,
            chassisNumber: v.chassisNumber,
            documentDate: toIsoDate(this.documentDate),
            notes: this.notes,
            includeGst: this.includeGst && this.chargesGst,
            workshop: this.isEditingWorkshop ? { ...this.workshop } : null,
            insuranceSplit: this.showSplit,
            insurerPercents: this.showSplit
                ? this.lines.map((line) => (String(line.insurerPercent || '').trim() === '' ? 100 : Number(line.insurerPercent)))
                : null,
            compulsoryExcess: this.showSplit ? Number(this.compulsoryExcess) || 0 : null,
            lineItems: this.lines.map((line) => ({
                partId: line.partId,
                description: line.description.trim(),
                hsnSacCode: line.hsnSacCode,
                unitLabel: line.unitLabel,
                quantity: Number(line.quantity),
                unitPrice: Number(line.unitPrice),
                taxRatePercent: Number(line.taxRatePercent) || 0,
                gstType: line.gstType || 'CGST_SGST',
                discount: Number(line.discount) || 0
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
                this.saved = {
                    ...saved,
                    formattedTotal: formatAmount(saved.totalAmount),
                    formattedPairedTotal: saved.pairedNumber ? formatAmount(saved.pairedTotal) : ''
                };
                this.opened = undefined;
                this.isEditingWorkshop = false;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSaving = false;
            });
    }

    handlePrint() {
        this.previewTarget = undefined;
        this.showPreview = true;
    }

    // The customer's bill of an insurance claim.
    handlePrintPaired() {
        this.previewTarget = { recordId: this.saved.pairedRecordId, heading: this.saved.pairedNumber };
        this.showPreview = true;
    }

    handleClosePreview() {
        this.showPreview = false;
        this.previewTarget = undefined;
    }

    handleView() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: this.isEstimate ? 'Estimate_Detail' : 'Bill_Detail' },
            state: { c__recordId: this.saved.recordId }
        });
    }

    handleNew() {
        this.resetPage();
        this._focusAfterRender = true;
    }

    // Everything typed on the page, back to a blank bill. The company stays.
    resetPage() {
        this.opened = undefined;
        this._pendingLines = undefined;
        this.customer = { ...EMPTY_CUSTOMER };
        this.originalCustomerName = undefined;
        this.vehicle = { ...EMPTY_VEHICLE };
        this.customerVehicles = [];
        this.isBillToParty = false;
        this.party = { ...EMPTY_PARTY };
        this._pickedParty = undefined;
        this.documentDate = todayText();
        this.lines = [];
        this.includeGst = false;
        this.notes = '';
        this.words = '';
        this.visitWork = [];
        this.saved = undefined;
        this.showPreview = false;
        this.previewTarget = undefined;
        this.showDiscount = false;
        this.insuranceSplit = false;
        this.compulsoryExcess = '';
        // A grid already on screen is cleared too (one left drawn while a
        // saved document is opened over a half-typed bill).
        const grid = this.template.querySelector('c-line-item-grid');
        if (grid) {
            grid.setLines([]);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
