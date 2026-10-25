import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import getProfile from '@salesforce/apex/WorkshopProfileController.getProfile';
import saveProfile from '@salesforce/apex/WorkshopProfileController.saveProfile';

const EMPTY_PROFILE = {
    name: '',
    address: '',
    phone: '',
    email: '',
    gstin: '',
    state: '',
    bankAccountHolder: '',
    bankName: '',
    bankAccountNo: '',
    bankIfsc: '',
    termsAndConditions: ''
};

export default class WorkshopProfile extends NavigationMixin(LightningElement) {
    values = { ...EMPTY_PROFILE };
    isLoading = true;
    isSaving = false;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadProfile();
    }

    loadProfile() {
        this.isLoading = true;
        return getProfile()
            .then((data) => {
                if (data) {
                    this.values = { ...EMPTY_PROFILE, ...data };
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
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
        saveProfile({ input: { ...this.values } })
            .then(() => {
                this.showToast('Workshop profile saved', '', 'success');
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
