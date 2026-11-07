import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveWork from '@salesforce/apex/ServiceBookController.saveWork';
import saveCardDetails from '@salesforce/apex/ServiceBookController.saveCardDetails';
import getVehicleCard from '@salesforce/apex/ServiceBookController.getVehicleCard';
import searchCarModels from '@salesforce/apex/ServiceBookController.searchCarModels';
import search from '@salesforce/apex/ServiceBookController.search';
import searchCustomers from '@salesforce/apex/BillController.searchCustomers';
import findCustomerByPhone from '@salesforce/apex/QuickBillController.findCustomerByPhone';
import getCustomer from '@salesforce/apex/PaperBillController.getCustomer';

const WALK_IN_PHONE = '0000000000';
const SAVE_DELAY_MS = 800;
const LEAVE_CHECK_MS = 150;
const MIN_WORK_ROWS = 3;

function digitsOf(value) {
    return (value || '').replace(/\D/g, '');
}

function formatDate(iso) {
    const [year, month, day] = iso.split('-').map(Number);
    return new Date(year, month - 1, day).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

/**
 * One car's card on a page of the Service Book. Saves itself as staff type, so
 * there's no Save button to forget, including when they move to another date.
 * The car number is all a card needs. Customer and model boxes stay on the card
 * until they're filled, and a bill needs a customer.
 */
export default class ServiceCard extends NavigationMixin(LightningElement) {
    @api entryDate;

    // Only read once: from then on this component owns the card, so a parent
    // re-render can't overwrite what's being typed.
    _card;
    workDone = '';
    showVisits = false;
    draft = { customerId: null, customerName: '', phone: '', make: '', model: '', registrationNumber: '' };
    customerVehicles = [];

    saveState = '';
    _isDirty = false;
    _isSaving = false;
    _saveTimer;
    _detailsTimer;
    _focusWorkIfLost = false;
    _isSavingDetails = false;

    @api
    get card() {
        return this._card;
    }
    set card(value) {
        if (this._card) {
            return;
        }
        this._card = value;
        this.workDone = value.workDone || '';
        this.showVisits = !!value.openVisits;
        this.draft = { ...this.draft, ...(value.draft || {}) };
    }

    // LWC templates can't bind a <textarea> value (it becomes an attribute, which
    // a textarea ignores), so it's set here. Only when different, so the cursor
    // stays put while typing.
    renderedCallback() {
        const box = this.template.querySelector('[data-id="work"]');
        if (box && box.value !== this.workDone) {
            box.value = this.workDone;
        }
        // The box being typed in can vanish when a car turns out to be known.
        if (this._focusWorkIfLost) {
            this._focusWorkIfLost = false;
            if (!this.template.activeElement) {
                this.focusWork();
            }
        }
    }

    disconnectedCallback() {
        clearTimeout(this._saveTimer);
        clearTimeout(this._detailsTimer);
        if (this.hasTypedDetails) {
            this.saveDetails();
        }
        // Moving to another date mustn't lose the last few keys typed.
        if (this._isDirty) {
            this.save();
        }
    }

    @api
    focusWork() {
        const box = this.template.querySelector('[data-id="work"]');
        if (box) {
            box.focus();
            const end = box.value.length;
            box.setSelectionRange(end, end);
        }
    }

    @api
    focusFirstBox() {
        const box = this.template.querySelector('c-paper-field');
        if (box) {
            box.focus();
        } else {
            this.focusWork();
        }
    }

    // ---- what the card shows --------------------------------------------

    get isNewCar() {
        return !this._card.vehicleId;
    }

    get visits() {
        return (this._card.visits || []).map((visit) => ({ ...visit, dateLabel: formatDate(visit.entryDate) }));
    }

    get hasVisits() {
        return this.visits.length > 0;
    }

    get visitsLabel() {
        const count = this.visits.length;
        return `${this.showVisits ? 'Hide' : 'Show'} ${count} other ${count === 1 ? 'visit' : 'visits'}`;
    }

    get workRows() {
        return Math.max(MIN_WORK_ROWS, this.workDone.split('\n').length + 1);
    }

    get missingDetails() {
        if (this.isNewCar && this.workDone.trim() && !this.draft.registrationNumber.trim()) {
            return 'Type the car number to save this.';
        }
        return '';
    }

    get showHeader() {
        return !this.isNewCar;
    }

    get showCustomerBox() {
        return this.isNewCar || !this._card.customerName;
    }

    get showMobileBox() {
        return this.isNewCar || !this._card.phone;
    }

    get showModelBox() {
        return this.isNewCar || !this._card.carModel;
    }

    get showBoxes() {
        return this.showCustomerBox || this.showMobileBox || this.showModelBox;
    }

    get hasTypedDetails() {
        const d = this.draft;
        return !this.isNewCar && !!(d.customerId || d.customerName.trim() || d.phone.trim() || d.model.trim());
    }

    get noCustomerHint() {
        return !this.isNewCar && !this._card.customerId ? 'Add a customer name or mobile to make a bill.' : '';
    }

    get saveStateLabel() {
        return { saving: 'Saving…', saved: 'Saved', failed: 'Not saved' }[this.saveState] || '';
    }

    get saveStateClass() {
        return this.saveState === 'failed' ? 'sc-status sc-status_failed' : 'sc-status';
    }

    get carModelValue() {
        return [this.draft.make, this.draft.model].filter((p) => p).join(' ');
    }

    get phoneLink() {
        return `tel:${this._card.phone}`;
    }

    // A bill needs someone to bill.
    get noBillYet() {
        return !this._card.customerId;
    }

    // ---- writing --------------------------------------------------------

    handleWorkInput(event) {
        this.workDone = event.target.value;
        this.markDirty();
    }

    markDirty() {
        this._isDirty = true;
        clearTimeout(this._saveTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._saveTimer = setTimeout(() => this.save(), SAVE_DELAY_MS);
    }

    saveNow() {
        clearTimeout(this._saveTimer);
        if (this._isDirty) {
            this.save();
        }
    }

    // Enter is left alone: in this box it makes the new line. Esc or Ctrl+Enter
    // means "done with this car".
    handleWorkKeydown(event) {
        if (event.key === 'Escape' || (event.key === 'Enter' && event.ctrlKey)) {
            event.preventDefault();
            this.saveNow();
            this.dispatchEvent(new CustomEvent('done', { bubbles: true, composed: true }));
        }
    }

    save() {
        if (this._isSaving || this.missingDetails || (this.isNewCar && !this.workDone.trim())) {
            return;
        }
        this._isDirty = false;
        this._isSaving = true;
        this.saveState = 'saving';
        saveWork({ request: this.buildRequest() })
            .then((card) => {
                this.saveState = 'saved';
                if (card && this.isNewCar) {
                    this.becomeCard(card);
                }
            })
            .catch((error) => {
                this._isDirty = true;
                this.saveState = 'failed';
                this.showError(error);
            })
            .finally(() => {
                this._isSaving = false;
                // More was typed while that was on its way.
                if (this._isDirty && this.saveState !== 'failed') {
                    this.save();
                }
            });
    }

    buildRequest() {
        const request = { entryDate: this.entryDate, workDone: this.workDone };
        if (this.isNewCar) {
            return { ...request, ...this.draft };
        }
        return { ...request, vehicleId: this._card.vehicleId };
    }

    becomeCard(card) {
        this._card = card;
        this.clearDraft();
        this.dispatchEvent(new CustomEvent('carknown', { detail: { vehicleId: card.vehicleId } }));
    }

    clearDraft() {
        this.draft = { customerId: null, customerName: '', phone: '', make: '', model: '', registrationNumber: '' };
    }

    // ---- the customer and car boxes -------------------------------------

    handleDraftChange(event) {
        this.draft = { ...this.draft, [event.target.dataset.field]: event.detail.value };
        if (event.target.dataset.field === 'phone') {
            this.draft = { ...this.draft, customerId: null };
            this.customerVehicles = [];
        }
    }

    handleModelChange(event) {
        // Typed by hand it's just a model; picking one from the list fills both.
        this.draft = { ...this.draft, make: '', model: event.detail.value };
    }

    handleModelPick(event) {
        const { make, model } = event.detail.option.data;
        this.draft = { ...this.draft, make, model };
    }

    searchCustomerOptions = (term) =>
        searchCustomers({ searchTerm: term }).then((results) =>
            results
                .filter((c) => !(c.phone === WALK_IN_PHONE && c.name === 'Walk-in Customer'))
                .map((c) => ({ value: c.id, label: c.name, sub: c.phone === WALK_IN_PHONE ? '' : c.phone }))
        );

    searchModelOptions = (term) =>
        searchCarModels({ term }).then((results) =>
            results.map((r) => ({ value: `${r.make}|${r.model}`, label: `${r.make} ${r.model}`, sub: '', data: r }))
        );

    searchCarOptions = (term) => {
        if (this.customerVehicles.length) {
            const typed = term.toLowerCase();
            return Promise.resolve(
                this.customerVehicles
                    .filter((v) => (v.registrationNumber || '').toLowerCase().includes(typed))
                    .map((v) => ({ value: v.id, label: v.registrationNumber, sub: [v.make, v.model].filter((p) => p).join(' ') }))
            );
        }
        if (term.length < 2) {
            return Promise.resolve([]);
        }
        return search({ term, entryDate: this.entryDate }).then((cards) =>
            cards
                .filter((c) => c.vehicleId)
                .map((c) => ({ value: c.vehicleId, label: c.registrationNumber, sub: [c.carModel, c.customerName].filter((p) => p).join(' · ') }))
        );
    };

    handleCustomerPick(event) {
        getCustomer({ customerId: event.detail.option.value })
            .then((match) => this.applyCustomer(match))
            .catch((error) => this.showError(error));
    }

    // A full mobile number typed by hand finds the customer without a pick.
    handlePhoneLeave() {
        if (!this.isNewCar) {
            this.handleDetailsLeave();
            return;
        }
        const phone = this.draft.phone;
        if (this.draft.customerId || digitsOf(phone).length < 10) {
            return;
        }
        findCustomerByPhone({ phone })
            .then((match) => {
                if (match && this.isNewCar && this.draft.phone === phone) {
                    this.applyCustomer(match);
                }
            })
            .catch((error) => this.showError(error));
    }

    applyCustomer(match) {
        this.draft = {
            ...this.draft,
            customerId: match.id,
            customerName: match.name || '',
            phone: match.phone === WALK_IN_PHONE ? '' : match.phone || ''
        };
        this.customerVehicles = match.vehicles || [];
        if (!this.isNewCar) {
            this.saveDetails();
        } else if (this.customerVehicles.length === 1 && !this.draft.registrationNumber.trim()) {
            this.openCar(this.customerVehicles[0].id);
        }
    }

    // Waits to see where the cursor went: tabbing from name to mobile shouldn't
    // save half a customer. Saves once it has left the boxes.
    handleDetailsLeave() {
        if (this.isNewCar) {
            return;
        }
        clearTimeout(this._detailsTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._detailsTimer = setTimeout(() => {
            const active = this.template.activeElement;
            if (!active || active.tagName !== 'C-PAPER-FIELD') {
                this.saveDetails();
            }
        }, LEAVE_CHECK_MS);
    }

    // What was typed stays in the boxes until the save is confirmed, so a failed
    // or slow one can't lose it.
    saveDetails() {
        if (this._isSavingDetails || !this.hasTypedDetails) {
            return;
        }
        this._isSavingDetails = true;
        this.saveState = 'saving';
        const sent = this.draft;
        saveCardDetails({ request: { ...sent, vehicleId: this._card.vehicleId, entryDate: this.entryDate } })
            .then((card) => {
                this._card = { ...card, visits: this._card.visits };
                this.saveState = 'saved';
                // Only clears if nothing more was typed while it was saving.
                if (this.draft === sent) {
                    this.clearDraft();
                }
            })
            .catch((error) => {
                this.saveState = 'failed';
                this.showError(error);
            })
            .finally(() => {
                this._isSavingDetails = false;
            });
    }

    handleCarPick(event) {
        this.openCar(event.detail.option.value);
    }

    // A car number typed in full that's already on file is that car.
    handleCarNumberLeave() {
        const typed = this.draft.registrationNumber.trim();
        if (typed.length < 2 || !this.isNewCar) {
            return;
        }
        search({ term: typed, entryDate: this.entryDate })
            .then((cards) => {
                const simple = (text) => (text || '').replace(/[\s-]/g, '').toLowerCase();
                const same = (cards || []).find((c) => simple(c.registrationNumber) === simple(typed));
                if (same && this.isNewCar && this.draft.registrationNumber.trim() === typed) {
                    this.becomeKnownCar(same);
                }
            })
            .catch((error) => this.showError(error));
    }

    openCar(vehicleId) {
        getVehicleCard({ vehicleId, entryDate: this.entryDate })
            .then((card) => this.becomeKnownCar(card))
            .catch((error) => this.showError(error));
    }

    // Keeps both anything already written for this car today and anything just
    // typed here, rather than one overwriting the other.
    becomeKnownCar(card) {
        const typed = this.workDone.trim();
        const onFile = (card.workDone || '').trim();
        this.workDone = [onFile, typed].filter((p) => p).join('\n');
        this.becomeCard(card);
        this._focusWorkIfLost = true;
        this.showVisits = card.visits.length > 0;
        if (typed) {
            this.markDirty();
        }
    }

    handleAdvance(event) {
        this.handleDetailsLeave();
        const boxes = [...this.template.querySelectorAll('c-paper-field')];
        const next = boxes[boxes.indexOf(event.target) + 1];
        if (next) {
            next.focus();
        } else {
            this.focusWork();
        }
    }

    // ---- other visits, and making a bill --------------------------------

    handleToggleVisits() {
        this.showVisits = !this.showVisits;
    }

    handleOpenVisit(event) {
        this.dispatchEvent(new CustomEvent('opendate', { detail: { date: event.currentTarget.dataset.date }, bubbles: true, composed: true }));
    }

    handleMakeBill() {
        this.openEasyBill('bill');
    }

    handleMakeEstimate() {
        this.openEasyBill('estimate');
    }

    openEasyBill(documentType) {
        this.saveNow();
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Easy_Bill' },
            state: {
                c__documentType: documentType,
                c__customerId: this._card.customerId,
                c__vehicleId: this._card.vehicleId,
                // Makes each visit a new page reference, so Easy Bill fills in
                // again even for the same car twice in a row.
                c__opened: String(Date.now())
            }
        });
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }
}
