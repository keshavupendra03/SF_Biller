import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';
import saveProfile from '@salesforce/apex/WorkshopProfileController.saveProfile';
import addProfile from '@salesforce/apex/WorkshopProfileController.addProfile';
import setGstFiledUpTo from '@salesforce/apex/WorkshopProfileController.setGstFiledUpTo';
import { STATE_OPTIONS, checkGstinBox, withStateFromGstin, tidyState, changedValue, filedUpToOptions, filedLockText } from 'c/gst';

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
    jobSlipTerms: '',
    gstRegistrationType: 'Regular',
    gstFilingFrequency: 'Monthly',
    roundOffTotals: true
};

// How the company is registered for GST, and how often it files. Every client
// differs, and later the GST reports and invoice wording follow these.
const REGISTRATION_OPTIONS = [
    { label: 'Regular', value: 'Regular' },
    { label: 'Composition', value: 'Composition' },
    { label: 'Not registered', value: 'Unregistered' }
];
const FREQUENCY_OPTIONS = [
    { label: 'Monthly', value: 'Monthly' },
    { label: 'Quarterly (QRMP)', value: 'Quarterly' }
];

/**
 * Details of the workshop's companies (at most two), each with its own name,
 * GSTIN, bank details, terms and invoice prefix. WorkshopProfileTrigger is what
 * actually enforces the limit; this screen just doesn't offer a third.
 */
export default class WorkshopProfile extends NavigationMixin(LightningElement) {
    stateOptions = STATE_OPTIONS;
    registrationOptions = REGISTRATION_OPTIONS;
    frequencyOptions = FREQUENCY_OPTIONS;
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
                this.values = tidyState({ ...EMPTY_PROFILE, ...(selected || {}) });
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
        this.values = tidyState({ ...EMPTY_PROFILE, ...selected });
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
        this.values = tidyState({ ...EMPTY_PROFILE, ...selected });
    }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Settings_Menu' }
        });
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.values = { ...this.values, [field]: changedValue(event) };
        if (field === 'gstin') {
            checkGstinBox(event.target);
            this.values = withStateFromGstin(this.values);
        }
    }

    get isRegistered() {
        return this.values.gstRegistrationType !== 'Unregistered';
    }

    // Locking is its own action, saved at once: a company's filed months
    // shouldn't wait on, or be undone by, the rest of the form.
    get showFiledUpTo() {
        return this.isRegistered && !this.isAddingCompany && !!this.selectedId;
    }

    get filedUpToOptions() {
        return filedUpToOptions(this.values.gstFilingFrequency, new Date(), this.values.gstFiledUpTo || '');
    }

    get filedUpToValue() {
        return this.values.gstFiledUpTo || '';
    }

    get filedUpToHint() {
        return this.values.gstFiledUpTo
            ? filedLockText(this.values.gstFiledUpTo)
            : 'Once a month\'s GST returns are filed, pick it here: its bills are then locked against changes.';
    }

    handleFiledUpToChange(event) {
        const filedUpTo = event.detail.value || null;
        setGstFiledUpTo({ companyId: this.selectedId, filedUpTo })
            .then((saved) => {
                this.profiles = this.profiles.map((p) => (p.id === saved.id ? { ...p, gstFiledUpTo: saved.gstFiledUpTo } : p));
                this.values = { ...this.values, gstFiledUpTo: saved.gstFiledUpTo };
                this.showToast(saved.gstFiledUpTo ? 'Filed months locked' : 'All months unlocked', '', 'success');
            })
            .catch((error) => this.showError(error));
    }

    handleGstSettingChange(event) {
        this.values = { ...this.values, [event.target.dataset.field]: event.detail.value };
    }

    // Whole-rupee totals on its bills and estimates (G5).
    handleRoundOffChange(event) {
        this.values = { ...this.values, roundOffTotals: event.target.checked };
    }

    get roundOffHint() {
        return this.values.roundOffTotals
            ? 'Totals go to the nearest rupee, with the paise shown as "Round off" on the bill.'
            : 'Totals are shown to the paisa.';
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
