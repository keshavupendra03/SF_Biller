import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import listCustomers from '@salesforce/apex/CustomerController.listCustomers';
import createCustomer from '@salesforce/apex/BillController.createCustomer';
import getProfile from '@salesforce/apex/WorkshopProfileController.getProfile';
const EMPTY_NEW_CUSTOMER = { name: '', phone: '', address: '', email: '', gstin: '', state: '' };

export default class CustomerList extends NavigationMixin(LightningElement) {
    @track customers = [];

    searchTerm = '';
    isLoading = true;

    showCreateForm = false;
    newCustomer = { ...EMPTY_NEW_CUSTOMER };
    isSaving = false;

    // Set => the blank job slip preview is open. A completely blank slip is
    // rendered from the Workshop Profile, since it belongs to no customer.
    blankSlipRecordId;
    isOpeningJobSlip = false;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadCustomers();
    }

    loadCustomers() {
        this.isLoading = true;
        return listCustomers({ searchTerm: this.searchTerm })
            .then((results) => {
                this.customers = results;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
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
        return !this.isLoading && this.customers.length === 0;
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
        this.newCustomer = { ...this.newCustomer, [field]: event.target.value };
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
        getProfile()
            .then((profile) => {
                if (profile) {
                    this.blankSlipRecordId = profile.id;
                } else {
                    this.showToast('Workshop profile needed', 'Add your workshop details under Settings first. They are printed at the top of the job slip.', 'warning');
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isOpeningJobSlip = false;
            });
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
