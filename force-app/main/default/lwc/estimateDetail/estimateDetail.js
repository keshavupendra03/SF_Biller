import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEstimateSummary from '@salesforce/apex/EstimateController.getEstimateSummary';

const STATUS_BADGE_CLASS = {
    Converted: 'slds-badge slds-theme_success',
    Approved: 'slds-badge slds-theme_warning',
    Draft: 'slds-badge',
    Rejected: 'slds-badge slds-theme_error'
};

export default class EstimateDetail extends NavigationMixin(LightningElement) {
    estimateId;
    summary;
    isLoading = true;

    showPreview = false;

    // The customer screen this estimate was opened from, if any — Back
    // returns there instead of the generic Customer list when it's set.
    fromCustomerId;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        const state = pageRef.state || {};
        if (state.c__recordId && state.c__recordId !== this.estimateId) {
            this.estimateId = state.c__recordId;
            this.summary = undefined;
            this.showPreview = false;
            this.fromCustomerId = state.c__fromCustomerId;
            this.loadSummary();
        }
    }

    loadSummary() {
        this.isLoading = true;
        return getEstimateSummary({ estimateId: this.estimateId })
            .then((summary) => {
                this.summary = summary;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasSummary() {
        return !!this.summary;
    }

    get statusBadgeClass() {
        return STATUS_BADGE_CLASS[this.summary?.status] || 'slds-badge';
    }

    get billToLabel() {
        return this.summary?.billToPartyName || this.summary?.customerName;
    }

    get hasLineItems() {
        return this.hasSummary && this.summary.lineItems.length > 0;
    }

    get decoratedLineItems() {
        return (this.summary?.lineItems || []).map((li, index) => ({ ...li, key: index }));
    }

    get hasIgstLines() {
        return this.hasSummary && this.summary.igst > 0;
    }

    get hasCgstSgstLines() {
        return this.hasSummary && (this.summary.cgst > 0 || this.summary.sgst > 0);
    }

    get canConvertToBill() {
        return this.hasSummary && this.summary.status !== 'Converted';
    }

    handleBack() {
        if (this.fromCustomerId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'Customer_Detail' },
                state: { c__customerId: this.fromCustomerId }
            });
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_List' }
        });
    }

    handleEdit() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'New_Estimate' },
            state: { c__recordId: this.estimateId, c__fromCustomerId: this.fromCustomerId }
        });
    }

    handlePrint() {
        this.showPreview = true;
    }

    handleClosePreview() {
        this.showPreview = false;
    }

    handleCreateBill() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'New_Bill' },
            state: { c__sourceEstimateId: this.estimateId, c__fromCustomerId: this.fromCustomerId }
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
