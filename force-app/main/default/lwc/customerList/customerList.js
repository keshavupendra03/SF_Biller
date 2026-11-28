import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import listCustomers from '@salesforce/apex/CustomerController.listCustomers';
import createCustomer from '@salesforce/apex/BillController.createCustomer';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';
import searchArchived from '@salesforce/apex/ArchiveController.searchCustomers';
import restoreCustomer from '@salesforce/apex/ArchiveController.restoreCustomer';
import { STATE_OPTIONS, checkGstinBox, withStateFromGstin, changedValue } from 'c/gst';
const EMPTY_NEW_CUSTOMER = { name: '', phone: '', address: '', email: '', gstin: '', state: '' };
// Archived customers are looked for once this much is typed.
const ARCHIVE_SEARCH_MIN = 3;

function lastSeenText(iso) {
    if (!iso) return '';
    const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
    return `Last seen ${new Date(y, m - 1, d).toLocaleDateString('en-IN', { month: 'short', year: 'numeric' })}`;
}

export default class CustomerList extends NavigationMixin(LightningElement) {
    stateOptions = STATE_OPTIONS;
    @track customers = [];

    searchTerm = '';
    isLoading = true;
    // Archived (dormant) customers matching the search, shown under the live ones.
    archived = [];
    bringingBackId;
    _searchSeq = 0;

    showCreateForm = false;
    newCustomer = { ...EMPTY_NEW_CUSTOMER };
    isSaving = false;

    // Set => the blank job slip preview is open. A completely blank slip is
    // rendered from the Workshop Profile, since it belongs to no customer.
    blankSlipRecordId;
    isOpeningJobSlip = false;
    // Set => asking which company's slip to print.
    slipCompanies;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadCustomers();
    }

    loadCustomers() {
        this.isLoading = true;
        const term = (this.searchTerm || '').trim();
        const seq = ++this._searchSeq;
        // The archive never stops the live list from showing.
        const archivedSearch = term.length >= ARCHIVE_SEARCH_MIN ? searchArchived({ term }).catch(() => []) : Promise.resolve([]);
        return Promise.all([listCustomers({ searchTerm: this.searchTerm }), archivedSearch])
            .then(([results, archived]) => {
                if (seq === this._searchSeq) {
                    this.customers = results;
                    this.archived = archived || [];
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                if (seq === this._searchSeq) {
                    this.isLoading = false;
                }
            });
    }

    get decoratedArchived() {
        return this.archived.map((c) => ({
            ...c,
            initial: c.name ? c.name.charAt(0).toUpperCase() : '?',
            details: [c.phone, c.vehicles, lastSeenText(c.lastSeen)].filter((p) => p).join(' · '),
            buttonLabel: this.bringingBackId === c.archivedId ? 'Bringing back…' : 'Bring back',
            disabled: !!this.bringingBackId
        }));
    }

    get hasArchived() {
        return this.archived.length > 0;
    }

    // Back into Salesforce with their cars and Service Book, then open them.
    handleBringBack(event) {
        const archivedId = event.currentTarget.dataset.id;
        const row = this.archived.find((c) => c.archivedId === archivedId);
        this.bringingBackId = archivedId;
        restoreCustomer({ archivedId })
            .then((customerId) => {
                this.showToast('Brought back', `${row ? row.name : 'The customer'} is back from the archive.`, 'success');
                this.archived = this.archived.filter((c) => c.archivedId !== archivedId);
                this[NavigationMixin.Navigate]({
                    type: 'standard__navItemPage',
                    attributes: { apiName: 'Customer_Detail' },
                    state: { c__customerId: customerId }
                });
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.bringingBackId = undefined;
            });
    }

    get decoratedCustomers() {
        return this.customers.map((c) => ({
            ...c,
            initial: c.name ? c.name.charAt(0).toUpperCase() : '?'
        }));
    }

    get hasCustomers() {
        return this.customers.length > 0;
    }

    get hasNoCustomers() {
        return !this.isLoading && this.customers.length === 0 && this.archived.length === 0;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.loadCustomers();
    }

    handleSelectCustomer(event) {
        const id = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_Detail' },
            state: { c__customerId: id }
        });
    }

    handleToggleCreateForm() {
        this.showCreateForm = !this.showCreateForm;
        if (!this.showCreateForm) {
            this.newCustomer = { ...EMPTY_NEW_CUSTOMER };
        }
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.newCustomer = { ...this.newCustomer, [field]: changedValue(event) };
        if (field === 'gstin') {
            checkGstinBox(event.target);
            this.newCustomer = withStateFromGstin(this.newCustomer);
        }
    }

    get canSave() {
        return !!this.newCustomer.name && !!this.newCustomer.phone && !this.isSaving;
    }

    get saveDisabled() {
        return !this.canSave;
    }

    handleSave() {
        if (!this.canSave) {
            return;
        }
        this.isSaving = true;
        createCustomer({ input: { ...this.newCustomer } })
            .then((customer) => {
                this.showToast('Customer added', `${customer.name} created.`, 'success');
                this.showCreateForm = false;
                this.newCustomer = { ...EMPTY_NEW_CUSTOMER };
                return this.loadCustomers();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSaving = false;
            });
    }

    handlePrintJobSlip() {
        this.isOpeningJobSlip = true;
        listProfiles()
            .then((profiles) => {
                if (profiles && profiles.length > 1) {
                    this.slipCompanies = profiles;
                } else if (profiles && profiles.length) {
                    this.blankSlipRecordId = profiles[0].id;
                } else {
                    this.showToast('Workshop profile needed', 'Add your workshop details under Settings first. They are printed at the top of the job slip.', 'warning');
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isOpeningJobSlip = false;
            });
    }

    handleChooseSlipCompany(event) {
        this.blankSlipRecordId = event.currentTarget.dataset.id;
        this.slipCompanies = undefined;
    }

    handleCancelSlipCompany() {
        this.slipCompanies = undefined;
    }

    handleCloseJobSlip() {
        this.blankSlipRecordId = undefined;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message =
            (error && error.body && error.body.message) ||
            (error && error.message) ||
            'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
