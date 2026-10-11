import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBillSummary from '@salesforce/apex/BillController.getBillSummary';
// Record Payment feature disabled (2026-10) — uncomment to restore. The
// Apex side (BillController.recordPayment, Bill__c.Status__c via
// PaymentTriggerHandler) was deliberately left untouched, so restoring
// this is a pure UI change — nothing to redo on the backend.
// import recordPayment from '@salesforce/apex/BillController.recordPayment';

// const PAYMENT_METHOD_OPTIONS = [
//     { label: 'Cash', value: 'Cash' },
//     { label: 'Card', value: 'Card' },
//     { label: 'UPI', value: 'UPI' },
//     { label: 'Bank Transfer', value: 'Bank Transfer' }
// ];

// const STATUS_BADGE_CLASS = {
//     Paid: 'slds-badge slds-theme_success',
//     Partial: 'slds-badge slds-theme_warning',
//     Unpaid: 'slds-badge slds-badge_inverse'
// };

export default class BillDetail extends NavigationMixin(LightningElement) {
    // paymentMethodOptions = PAYMENT_METHOD_OPTIONS;

    billId;
    summary;
    isLoading = true;

    showPreview = false;
    // showRecordPayment = false;
    // paymentAmount = 0;
    // paymentMethod = 'Cash';
    // isRecordingPayment = false;

    // The customer screen this bill was opened from, if any — Back returns
    // there instead of the generic Billing list when it's set.
    fromCustomerId;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        const state = pageRef.state || {};
        if (state.c__recordId && state.c__recordId !== this.billId) {
            this.billId = state.c__recordId;
            this.summary = undefined;
            this.showPreview = false;
            // this.showRecordPayment = false;
            this.fromCustomerId = state.c__fromCustomerId;
            this.loadSummary();
        }
    }

    loadSummary() {
        this.isLoading = true;
        return getBillSummary({ billId: this.billId })
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

    // get statusBadgeClass() {
    //     return STATUS_BADGE_CLASS[this.summary?.status] || 'slds-badge';
    // }

    get billToLabel() {
        return this.summary?.billToPartyName || this.summary?.customerName;
    }

    get hasLineItems() {
        return this.hasSummary && this.summary.lineItems.length > 0;
    }

    get decoratedLineItems() {
        return (this.summary?.lineItems || []).map((li, index) => ({
            ...li,
            key: index,
            gstLabel: li.gstType === 'IGST' ? 'IGST' : 'CGST+SGST'
        }));
    }

    get hasIgstLines() {
        return this.hasSummary && this.summary.igst > 0;
    }

    get hasCgstSgstLines() {
        return this.hasSummary && (this.summary.cgst > 0 || this.summary.sgst > 0);
    }

    // get hasPayments() {
    //     return this.hasSummary && this.summary.payments.length > 0;
    // }

    // get isFullyPaid() {
    //     return this.hasSummary && this.summary.amountDue <= 0;
    // }

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
            attributes: { apiName: 'Billing_List' }
        });
    }

    handleEdit() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'New_Bill' },
            state: { c__recordId: this.billId, c__fromCustomerId: this.fromCustomerId }
        });
    }

    // handleToggleRecordPayment() {
    //     this.showRecordPayment = !this.showRecordPayment;
    //     if (this.showRecordPayment) {
    //         this.paymentAmount = this.summary.amountDue > 0 ? this.summary.amountDue : 0;
    //     }
    // }

    // handlePaymentAmountChange(event) {
    //     this.paymentAmount = event.target.value;
    // }

    // handlePaymentMethodChange(event) {
    //     this.paymentMethod = event.detail.value;
    // }

    // get canSubmitPayment() {
    //     return Number(this.paymentAmount) > 0 && !this.isRecordingPayment;
    // }

    // get submitPaymentDisabled() {
    //     return !this.canSubmitPayment;
    // }

    // handleSubmitPayment() {
    //     if (!this.canSubmitPayment) {
    //         return;
    //     }
    //     this.isRecordingPayment = true;
    //     recordPayment({ billId: this.billId, amount: Number(this.paymentAmount), method: this.paymentMethod })
    //         .then((summary) => {
    //             this.summary = summary;
    //             this.showRecordPayment = false;
    //             this.showToast('Payment recorded', '', 'success');
    //         })
    //         .catch((error) => this.showError(error))
    //         .finally(() => {
    //             this.isRecordingPayment = false;
    //         });
    // }

    handlePrint() {
        this.showPreview = true;
    }

    handleClosePreview() {
        this.showPreview = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
