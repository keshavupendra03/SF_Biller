import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchParts from '@salesforce/apex/BillController.searchParts';

const GST_TYPE_OPTIONS = [
    { label: 'CGST + SGST', value: 'CGST_SGST' },
    { label: 'IGST', value: 'IGST' }
];

/**
 * Focused popup for one line item — reused by billCreate and
 * estimateCreate's "tap a line to edit it" / "+ Add Line Item" actions,
 * instead of showing every line's fields inline all at once.
 */
export default class LineItemEditor extends LightningElement {
    gstTypeOptions = GST_TYPE_OPTIONS;

    @track line = {};
    @track partResults = [];

    isSearchingPart = false;
    partSearchTerm = '';

    @api
    get record() {
        return this.line;
    }
    set record(value) {
        this.line = { ...value };
        // A brand-new line (no description yet) starts straight in search
        // mode — there's nothing to show as "the current line" yet.
        this.isSearchingPart = !value.partId && !value.description;
    }

    get isNew() {
        return !this.line.description && !this.line.partId;
    }

    get heading() {
        return this.isNew ? 'Add Line Item' : 'Edit Line Item';
    }

    get isFromInventory() {
        return !!this.line.partId && !this.isSearchingPart;
    }

    get showManualHeader() {
        return !this.line.partId && !this.isSearchingPart && !this.isNew;
    }

    get showManualFields() {
        return !this.isSearchingPart;
    }

    get hasPartResults() {
        return this.partResults.length > 0;
    }

    get canSave() {
        return !!this.line.description && Number(this.line.quantity) > 0 && Number(this.line.unitPrice) >= 0;
    }

    get saveDisabled() {
        return !this.canSave;
    }

    handleStartPartSearch() {
        this.isSearchingPart = true;
        this.partSearchTerm = '';
        this.partResults = [];
    }

    handleCancelPartSearch() {
        if (this.isNew && !this.line.partId) {
            // Nothing was ever picked for a brand-new line — there's no
            // "manual fields" state to fall back to, so closing search
            // here is the same as cancelling the whole popup.
            this.handleCancel();
            return;
        }
        this.isSearchingPart = false;
    }

    handlePartSearchChange(event) {
        this.partSearchTerm = event.target.value;
        if (this.partSearchTerm.length < 2) {
            this.partResults = [];
            return;
        }
        this.isSearchingPart = true;
        searchParts({ searchTerm: this.partSearchTerm })
            .then((results) => {
                this.partResults = results;
            })
            .catch((error) => this.showError(error));
    }

    handleSelectPart(event) {
        const id = event.currentTarget.dataset.id;
        const part = this.partResults.find((p) => p.id === id);
        if (!part) {
            return;
        }
        this.line = {
            ...this.line,
            partId: part.id,
            description: part.name,
            unitPrice: part.price || 0,
            taxRatePercent: part.taxRatePercent || 0,
            gstType: part.gstType || 'CGST_SGST',
            hsnSacCode: part.hsnCode || '',
            unitLabel: part.unitLabel || '',
            quantity: this.line.quantity || 1
        };
        this.partResults = [];
        this.partSearchTerm = '';
        this.isSearchingPart = false;
    }

    handleUseManualLine() {
        // "Search inventory" turned out not to be what's needed — clear
        // any part link and let the fields below be typed in directly.
        // Tax rate defaults to 18% here the same way EMPTY_LINE already
        // does for a brand-new line — only when there isn't one already
        // (never overwrite a real rate carried over from a previously
        // selected part).
        this.line = { ...this.line, partId: null, taxRatePercent: this.line.taxRatePercent || 18 };
        this.partResults = [];
        this.partSearchTerm = '';
        this.isSearchingPart = false;
        if (!this.line.quantity) {
            this.line = { ...this.line, quantity: 1 };
        }
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.line = { ...this.line, [field]: event.target.value };
    }

    handleGstTypeChange(event) {
        this.line = { ...this.line, gstType: event.detail.value };
    }

    handleSave() {
        if (!this.canSave) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('save', {
                detail: {
                    ...this.line,
                    quantity: Number(this.line.quantity),
                    unitPrice: Number(this.line.unitPrice),
                    taxRatePercent: this.line.taxRatePercent ? Number(this.line.taxRatePercent) : 0
                }
            })
        );
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }
}
