import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import listBills from '@salesforce/apex/BillController.listBills';

// Record Payment feature disabled (2026-10) — uncomment to restore the
// Paid/Partial/Unpaid status badge. Apex (Bill__c.Status__c) was left
// untouched, so this is a pure UI change.
// const STATUS_BADGE_CLASS = {
//     Paid: 'slds-badge slds-theme_success',
//     Partial: 'slds-badge slds-theme_warning',
//     Unpaid: 'slds-badge slds-badge_inverse'
// };

export default class BillingList extends NavigationMixin(LightningElement) {
    @track bills = [];

    // All/Dues Only filter disabled alongside the payment status feature
    // (2026-10) — listBills still accepts a filter param, so this just
    // always asks for 'All' now. Uncomment to restore the toggle.
    // filter = 'All';
    searchTerm = '';
    isLoading = true;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadBills();
    }

    loadBills() {
        this.isLoading = true;
        return listBills({ filter: 'All', searchTerm: this.searchTerm })
            .then((results) => {
                this.bills = results;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    get decoratedBills() {
        // return this.bills.map((b) => ({ ...b, badgeClass: STATUS_BADGE_CLASS[b.status] || 'slds-badge' }));
        return this.bills;
    }

    get hasBills() {
        return this.bills.length > 0;
    }

    get hasNoBills() {
        return !this.isLoading && this.bills.length === 0;
    }

    // get isAllActive() {
    //     return this.filter === 'All';
    // }

    // get isDuesOnlyActive() {
    //     return this.filter === 'DuesOnly';
    // }

    // get allButtonVariant() {
    //     return this.isAllActive ? 'brand' : 'neutral';
    // }

    // get duesOnlyButtonVariant() {
    //     return this.isDuesOnlyActive ? 'brand' : 'neutral';
    // }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.loadBills();
    }

    // handleShowAll() {
    //     this.filter = 'All';
    //     this.loadBills();
    // }

    // handleShowDuesOnly() {
    //     this.filter = 'DuesOnly';
    //     this.loadBills();
    // }

    handleSelectBill(event) {
        const id = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: id }
        });
    }

    handleNewBill() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'New_Bill' }
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
