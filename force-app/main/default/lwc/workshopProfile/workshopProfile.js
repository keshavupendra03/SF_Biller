import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';
import saveProfile from '@salesforce/apex/WorkshopProfileController.saveProfile';
import addProfile from '@salesforce/apex/WorkshopProfileController.addProfile';

const MAX_COMPANIES = 2;

const EMPTY_PROFILE = {
    name: '',
    address: '',
    phone: '',
    email: '',
    gstin: '',
    state: '',
    invoicePrefix: '',
    bankAccountHolder: '',
    bankName: '',
    bankAccountNo: '',
    bankIfsc: '',
    termsAndConditions: '',
    jobSlipTerms: ''
};

/**
 * Details of the workshop's companies (at most two), each with its own name,
 * GSTIN, bank details, terms and invoice prefix. WorkshopProfileTrigger is what
 * actually enforces the limit; this screen just doesn't offer a third.
 */
export default class WorkshopProfile extends NavigationMixin(LightningElement) {
    profiles = [];
    values = { ...EMPTY_PROFILE };
    selectedId;
    isAddingCompany = false;
    isLoading = true;
    isSaving = false;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadProfiles();
    }

    loadProfiles(selectId) {
        this.isLoading = true;
        return listProfiles()
            .then((profiles) => {
                this.profiles = profiles || [];
                const selected = this.profiles.find((p) => p.id === selectId) || this.profiles[0];
                this.isAddingCompany = false;
                this.selectedId = selected ? selected.id : undefined;
                this.values = { ...EMPTY_PROFILE, ...(selected || {}) };
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasTwoCompanies() {
        return this.profiles.length > 1;
    }

    get showCompanyChoices() {
        return this.hasTwoCompanies || this.isAddingCompany;
    }

    get companyChoices() {
        const choices = this.profiles.map((p) => ({
            id: p.id,
            label: p.name,
            variant: !this.isAddingCompany && p.id === this.selectedId ? 'brand' : 'neutral'
        }));
        if (this.isAddingCompany) {
            choices.push({ id: 'new', label: 'New company', variant: 'brand' });
        }
        return choices;
    }

    // The first company can be saved before any other exists, so there's
    // nothing to add until it's on file.
    get canAddCompany() {
        return this.profiles.length > 0 && this.profiles.length < MAX_COMPANIES && !this.isAddingCompany;
    }

    get nameLabel() {
        return this.showCompanyChoices ? 'Company Name' : 'Workshop Name';
    }

    get invoiceExample() {
        const prefix = (this.values.invoicePrefix || '').trim().toUpperCase() || 'INV';
        return `Invoice numbers will look like ${prefix}/2026-27/0001. Each company has its own series.`;
    }

    get saveLabel() {
        return this.isAddingCompany ? 'Add Company' : 'Save Profile';
    }

    handleChooseCompany(event) {
        const id = event.currentTarget.dataset.value;
        if (id === 'new') {
            return;
        }
        const selected = this.profiles.find((p) => p.id === id);
        this.isAddingCompany = false;
        this.selectedId = id;
        this.values = { ...EMPTY_PROFILE, ...selected };
    }

    handleAddCompany() {
        this.isAddingCompany = true;
        this.selectedId = undefined;
        this.values = { ...EMPTY_PROFILE };
    }

    handleCancelAdd() {
        const selected = this.profiles[0];
        this.isAddingCompany = false;
        this.selectedId = selected.id;
        this.values = { ...EMPTY_PROFILE, ...selected };
    }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Settings_Menu' }
        });
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.values = { ...this.values, [field]: event.target.value };
    }

    get canSave() {
        return !!this.values.name && !this.isSaving;
    }

    get saveDisabled() {
        return !this.canSave;
    }

    handleSave() {
        if (!this.canSave) {
            return;
        }
        this.isSaving = true;
        const save = this.isAddingCompany ? addProfile : saveProfile;
        save({ input: { ...this.values } })
            .then((saved) => {
                this.showToast(this.isAddingCompany ? 'Company added' : 'Workshop profile saved', '', 'success');
                return this.loadProfiles(saved ? saved.id : this.selectedId);
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
