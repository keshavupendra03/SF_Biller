import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import getCustomerDetail from '@salesforce/apex/CustomerController.getCustomerDetail';
import updateCustomer from '@salesforce/apex/CustomerController.updateCustomer';
import createVehicle from '@salesforce/apex/CustomerController.createVehicle';

const EMPTY_VEHICLE = { registrationNumber: '', make: '', model: '', year: '', color: '', chassisNumber: '' };

const STATUS_BADGE_CLASS = {
    Paid: 'slds-badge slds-theme_success',
    Converted: 'slds-badge slds-theme_success',
    Partial: 'slds-badge slds-theme_warning',
    Approved: 'slds-badge slds-theme_warning',
    Unpaid: 'slds-badge slds-badge_inverse',
    Draft: 'slds-badge',
    Rejected: 'slds-badge slds-theme_error'
};

function badgeClassForStatus(status) {
    return STATUS_BADGE_CLASS[status] || 'slds-badge';
}

export default class CustomerDetail extends NavigationMixin(LightningElement) {
    customerId;
    @track detail;
    isLoading = true;

    isEditing = false;
    editValues = {};
    isSaving = false;

    showAddVehicle = false;
    newVehicle = { ...EMPTY_VEHICLE };
    isSavingVehicle = false;

    connectedCallback() {
        disablePullToRefresh(this);
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        const state = pageRef.state || {};
        if (state.c__customerId && state.c__customerId !== this.customerId) {
            this.customerId = state.c__customerId;
            this.detail = undefined;
            this.isEditing = false;
            this.editValues = {};
            this.showAddVehicle = false;
            this.newVehicle = { ...EMPTY_VEHICLE };
            this.loadDetail();
        }
    }

    loadDetail() {
        this.isLoading = true;
        return getCustomerDetail({ customerId: this.customerId })
            .then((data) => {
                this.detail = data;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasDetail() {
        return !!this.detail;
    }

    get hasVehicles() {
        return this.hasDetail && this.detail.vehicles.length > 0;
    }

    get hasJobs() {
        return this.hasDetail && this.detail.jobs.length > 0;
    }

    get hasBills() {
        return this.hasDetail && this.detail.bills.length > 0;
    }

    get hasEstimates() {
        return this.hasDetail && this.detail.estimates.length > 0;
    }

    get decoratedVehicles() {
        return (this.detail?.vehicles || []).map((v) => ({
            ...v,
            label: [v.make, v.model].filter((p) => p).join(' ')
        }));
    }

    get decoratedBills() {
        return (this.detail?.bills || []).map((b) => ({ ...b, badgeClass: badgeClassForStatus(b.status) }));
    }

    get decoratedEstimates() {
        return (this.detail?.estimates || []).map((e) => ({ ...e, badgeClass: badgeClassForStatus(e.status) }));
    }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_List' }
        });
    }

    handleToggleEdit() {
        this.isEditing = !this.isEditing;
        if (this.isEditing) {
            this.editValues = {
                name: this.detail.name,
                phone: this.detail.phone,
                address: this.detail.address,
                email: this.detail.email,
                gstin: this.detail.gstin,
                state: this.detail.state
            };
        }
    }

    handleEditFieldChange(event) {
        const field = event.target.dataset.field;
        this.editValues = { ...this.editValues, [field]: event.target.value };
    }

    get canSaveEdit() {
        return !!this.editValues.name && !!this.editValues.phone && !this.isSaving;
    }

    get saveEditDisabled() {
        return !this.canSaveEdit;
    }

    handleSaveEdit() {
        if (!this.canSaveEdit) {
            return;
        }
        this.isSaving = true;
        updateCustomer({ customerId: this.customerId, input: { ...this.editValues } })
            .then(() => {
                this.showToast('Customer updated', '', 'success');
                this.isEditing = false;
                return this.loadDetail();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleToggleAddVehicle() {
        this.showAddVehicle = !this.showAddVehicle;
        if (!this.showAddVehicle) {
            this.newVehicle = { ...EMPTY_VEHICLE };
        }
    }

    handleVehicleFieldChange(event) {
        const field = event.target.dataset.field;
        this.newVehicle = { ...this.newVehicle, [field]: event.target.value };
    }

    get canSaveVehicle() {
        return !!this.newVehicle.registrationNumber && !this.isSavingVehicle;
    }

    get saveVehicleDisabled() {
        return !this.canSaveVehicle;
    }

    handleSaveVehicle() {
        if (!this.canSaveVehicle) {
            return;
        }
        this.isSavingVehicle = true;
        createVehicle({
            customerId: this.customerId,
            input: {
                registrationNumber: this.newVehicle.registrationNumber,
                make: this.newVehicle.make,
                model: this.newVehicle.model,
                year: this.newVehicle.year ? Number(this.newVehicle.year) : null,
                color: this.newVehicle.color,
                chassisNumber: this.newVehicle.chassisNumber
            }
        })
            .then(() => {
                this.showToast('Vehicle added', '', 'success');
                this.showAddVehicle = false;
                this.newVehicle = { ...EMPTY_VEHICLE };
                return this.loadDetail();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSavingVehicle = false;
            });
    }

    handleNewBill() {
        this.navigateWithCustomer('New_Bill');
    }

    handleNewEstimate() {
        this.navigateWithCustomer('New_Estimate');
    }

    handleOpenJob(event) {
        this.navigateToRecord('Job_Detail', event.currentTarget.dataset.id);
    }

    handleOpenVehicle(event) {
        this.navigateToRecord('Vehicle_Detail', event.currentTarget.dataset.id);
    }

    handleOpenBill(event) {
        this.navigateToRecord('Bill_Detail', event.currentTarget.dataset.id);
    }

    handleOpenEstimate(event) {
        this.navigateToRecord('Estimate_Detail', event.currentTarget.dataset.id);
    }

    navigateWithCustomer(tabApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: tabApiName },
            state: { c__customerId: this.customerId, c__customerName: this.detail.name }
        });
    }

    navigateToRecord(tabApiName, recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: tabApiName },
            state: { c__recordId: recordId, c__fromCustomerId: this.customerId }
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
