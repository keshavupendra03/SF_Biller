import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listBillToParties from '@salesforce/apex/DirectoryController.listBillToParties';
import createBillToParty from '@salesforce/apex/DirectoryController.createBillToParty';

const EMPTY_PARTY = { name: '', address: '', contactPhone: '', gstin: '', state: '' };

export default class BillToPartyList extends LightningElement {
    @track parties = [];

    searchTerm = '';
    isLoading = true;

    showCreateForm = false;
    newParty = { ...EMPTY_PARTY };
    isSaving = false;

    connectedCallback() {
        this.loadParties();
    }

    loadParties() {
        this.isLoading = true;
        return listBillToParties({ searchTerm: this.searchTerm })
            .then((results) => {
                this.parties = results;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasParties() {
        return this.parties.length > 0;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.loadParties();
    }

    handleToggleCreateForm() {
        this.showCreateForm = !this.showCreateForm;
        if (!this.showCreateForm) {
            this.newParty = { ...EMPTY_PARTY };
        }
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.newParty = { ...this.newParty, [field]: event.target.value };
    }

    get canSave() {
        return !!this.newParty.name && !this.isSaving;
    }

    get saveDisabled() {
        return !this.canSave;
    }

    handleSave() {
        if (!this.canSave) {
            return;
        }
        this.isSaving = true;
        createBillToParty({ input: { ...this.newParty } })
            .then(() => {
                this.showToast('Bill-to party added', '', 'success');
                this.showCreateForm = false;
                this.newParty = { ...EMPTY_PARTY };
                return this.loadParties();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSaving = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
