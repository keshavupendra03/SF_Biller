import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import listParts from '@salesforce/apex/PartController.listParts';
import createPart from '@salesforce/apex/PartController.createPart';

const EMPTY_PART = {
    name: '',
    sku: '',
    barcode: '',
    price: '',
    lowStockThreshold: '',
    gstType: 'CGST_SGST',
    taxRatePercent: '',
    hsnCode: '',
    unitLabel: '',
    openingStock: ''
};

const GST_TYPE_OPTIONS = [
    { label: 'CGST + SGST', value: 'CGST_SGST' },
    { label: 'IGST', value: 'IGST' }
];

export default class InventoryList extends NavigationMixin(LightningElement) {
    gstTypeOptions = GST_TYPE_OPTIONS;

    @track parts = [];

    searchTerm = '';
    isLoading = true;

    showCreateForm = false;
    newPart = { ...EMPTY_PART };
    isSaving = false;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadParts();
    }

    loadParts() {
        this.isLoading = true;
        return listParts({ searchTerm: this.searchTerm })
            .then((results) => {
                this.parts = results;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    get decoratedParts() {
        return this.parts.map((p) => ({
            ...p,
            stockLineClass: p.isLowStock ? 'slds-text-body_small part-stock-warning' : 'slds-text-body_small slds-text-color_weak',
            iconContainerClass: p.isLowStock ? 'part-icon-box part-icon-box_warning' : 'part-icon-box'
        }));
    }

    get hasParts() {
        return this.parts.length > 0;
    }

    get hasNoParts() {
        return !this.isLoading && this.parts.length === 0;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.loadParts();
    }

    handleSelectPart(event) {
        const id = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Inventory_Detail' },
            state: { c__partId: id }
        });
    }

    handleToggleCreateForm() {
        this.showCreateForm = !this.showCreateForm;
        if (!this.showCreateForm) {
            this.newPart = { ...EMPTY_PART };
        }
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.newPart = { ...this.newPart, [field]: event.target.value };
    }

    handleGstTypeChange(event) {
        this.newPart = { ...this.newPart, gstType: event.detail.value };
    }

    get canSave() {
        return !!this.newPart.name && !this.isSaving;
    }

    get saveDisabled() {
        return !this.canSave;
    }

    handleSave() {
        if (!this.canSave) {
            return;
        }
        this.isSaving = true;
        createPart({
            input: {
                name: this.newPart.name,
                sku: this.newPart.sku,
                barcode: this.newPart.barcode,
                price: this.newPart.price ? Number(this.newPart.price) : 0,
                lowStockThreshold: this.newPart.lowStockThreshold ? Number(this.newPart.lowStockThreshold) : null,
                gstType: this.newPart.gstType,
                taxRatePercent: this.newPart.taxRatePercent ? Number(this.newPart.taxRatePercent) : 0,
                hsnCode: this.newPart.hsnCode,
                unitLabel: this.newPart.unitLabel,
                openingStock: this.newPart.openingStock ? Number(this.newPart.openingStock) : 0
            }
        })
            .then((part) => {
                this.showToast('Part added', `${part.name} created.`, 'success');
                this.showCreateForm = false;
                this.newPart = { ...EMPTY_PART };
                return this.loadParts();
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
