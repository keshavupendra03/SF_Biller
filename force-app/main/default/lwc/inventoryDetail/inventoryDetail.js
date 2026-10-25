import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import getPartDetail from '@salesforce/apex/PartController.getPartDetail';
import updatePart from '@salesforce/apex/PartController.updatePart';
import adjustStock from '@salesforce/apex/PartController.adjustStock';

const GST_TYPE_OPTIONS = [
    { label: 'CGST + SGST', value: 'CGST_SGST' },
    { label: 'IGST', value: 'IGST' }
];

export default class InventoryDetail extends NavigationMixin(LightningElement) {
    gstTypeOptions = GST_TYPE_OPTIONS;

    partId;
    @track detail;
    isLoading = true;

    isEditing = false;
    editValues = {};
    isSaving = false;

    showAdjustStock = false;
    adjustQuantity = '';
    isAdjusting = false;

    connectedCallback() {
        disablePullToRefresh(this);
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        const state = pageRef.state || {};
        if (state.c__partId && state.c__partId !== this.partId) {
            this.partId = state.c__partId;
            this.detail = undefined;
            this.isEditing = false;
            this.editValues = {};
            this.showAdjustStock = false;
            this.adjustQuantity = '';
            this.loadDetail();
        }
    }

    loadDetail() {
        this.isLoading = true;
        return getPartDetail({ partId: this.partId })
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

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Inventory_List' }
        });
    }

    handleToggleEdit() {
        this.isEditing = !this.isEditing;
        if (this.isEditing) {
            const p = this.detail.part;
            this.editValues = {
                name: p.name,
                sku: p.sku,
                barcode: p.barcode,
                price: p.price,
                lowStockThreshold: p.lowStockThreshold,
                gstType: p.gstType,
                taxRatePercent: p.taxRatePercent,
                hsnCode: p.hsnCode,
                unitLabel: p.unitLabel
            };
        }
    }

    handleEditFieldChange(event) {
        const field = event.target.dataset.field;
        this.editValues = { ...this.editValues, [field]: event.target.value };
    }

    handleGstTypeChange(event) {
        this.editValues = { ...this.editValues, gstType: event.detail.value };
    }

    get canSaveEdit() {
        return !!this.editValues.name && !this.isSaving;
    }

    get saveEditDisabled() {
        return !this.canSaveEdit;
    }

    handleSaveEdit() {
        if (!this.canSaveEdit) {
            return;
        }
        this.isSaving = true;
        updatePart({
            partId: this.partId,
            input: {
                name: this.editValues.name,
                sku: this.editValues.sku,
                barcode: this.editValues.barcode,
                price: this.editValues.price ? Number(this.editValues.price) : 0,
                lowStockThreshold: this.editValues.lowStockThreshold ? Number(this.editValues.lowStockThreshold) : null,
                gstType: this.editValues.gstType,
                taxRatePercent: this.editValues.taxRatePercent ? Number(this.editValues.taxRatePercent) : 0,
                hsnCode: this.editValues.hsnCode,
                unitLabel: this.editValues.unitLabel
            }
        })
            .then(() => {
                this.showToast('Part updated', '', 'success');
                this.isEditing = false;
                return this.loadDetail();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleToggleAdjustStock() {
        this.showAdjustStock = !this.showAdjustStock;
        if (!this.showAdjustStock) {
            this.adjustQuantity = '';
        }
    }

    handleAdjustQuantityChange(event) {
        this.adjustQuantity = event.target.value;
    }

    get canAdjust() {
        return !!this.adjustQuantity && Number(this.adjustQuantity) !== 0 && !this.isAdjusting;
    }

    get adjustDisabled() {
        return !this.canAdjust;
    }

    handleSubmitAdjustment() {
        if (!this.canAdjust) {
            return;
        }
        this.isAdjusting = true;
        adjustStock({
            partId: this.partId,
            quantityDelta: Number(this.adjustQuantity)
        })
            .then(() => {
                this.showToast('Stock adjusted', '', 'success');
                this.showAdjustStock = false;
                this.adjustQuantity = '';
                return this.loadDetail();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isAdjusting = false;
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
