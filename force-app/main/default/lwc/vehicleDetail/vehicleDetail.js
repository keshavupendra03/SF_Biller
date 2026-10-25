import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import getVehicleDetail from '@salesforce/apex/VehicleController.getVehicleDetail';
import updateVehicle from '@salesforce/apex/VehicleController.updateVehicle';

export default class VehicleDetail extends NavigationMixin(LightningElement) {
    vehicleId;
    fromCustomerId;
    detail;
    isLoading = true;

    isEditing = false;
    editValues = {};
    isSaving = false;

    connectedCallback() {
        disablePullToRefresh(this);
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        const state = pageRef.state || {};
        if (state.c__recordId && state.c__recordId !== this.vehicleId) {
            this.vehicleId = state.c__recordId;
            this.fromCustomerId = state.c__fromCustomerId;
            this.detail = undefined;
            this.isEditing = false;
            this.editValues = {};
            this.loadDetail();
        }
    }

    loadDetail() {
        this.isLoading = true;
        return getVehicleDetail({ vehicleId: this.vehicleId })
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

    get hasYearOrColor() {
        return this.hasDetail && (!!this.detail.year || !!this.detail.color);
    }

    get hasChassisNumber() {
        return this.hasDetail && !!this.detail.chassisNumber;
    }

    handleBack() {
        if (this.fromCustomerId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'Customer_Detail' },
                state: { c__customerId: this.fromCustomerId }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'Customer_List' }
            });
        }
    }

    handleToggleEdit() {
        this.isEditing = !this.isEditing;
        if (this.isEditing) {
            this.editValues = {
                registrationNumber: this.detail.registrationNumber,
                make: this.detail.make,
                model: this.detail.model,
                year: this.detail.year,
                color: this.detail.color,
                chassisNumber: this.detail.chassisNumber
            };
        }
    }

    handleEditFieldChange(event) {
        const field = event.target.dataset.field;
        this.editValues = { ...this.editValues, [field]: event.target.value };
    }

    get canSaveEdit() {
        return !!this.editValues.registrationNumber && !this.isSaving;
    }

    get saveEditDisabled() {
        return !this.canSaveEdit;
    }

    handleSaveEdit() {
        if (!this.canSaveEdit) {
            return;
        }
        this.isSaving = true;
        updateVehicle({
            vehicleId: this.vehicleId,
            input: {
                registrationNumber: this.editValues.registrationNumber,
                make: this.editValues.make,
                model: this.editValues.model,
                year: this.editValues.year ? Number(this.editValues.year) : null,
                color: this.editValues.color,
                chassisNumber: this.editValues.chassisNumber
            }
        })
            .then(() => {
                this.showToast('Vehicle updated', '', 'success');
                this.isEditing = false;
                return this.loadDetail();
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
