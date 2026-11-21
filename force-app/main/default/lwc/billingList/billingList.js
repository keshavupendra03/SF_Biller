import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import listBills from '@salesforce/apex/BillController.listBills';
import listEstimates from '@salesforce/apex/EstimateController.listEstimates';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';
import { gstDueDates } from 'c/gst';

// Record Payment feature disabled (2026-10) — uncomment to restore the
// Paid/Partial/Unpaid status badge. Apex (Bill__c.Status__c) was left
// untouched, so this is a pure UI change.
// const STATUS_BADGE_CLASS = {
//     Paid: 'slds-badge slds-theme_success',
//     Partial: 'slds-badge slds-theme_warning',
//     Unpaid: 'slds-badge slds-badge_inverse'
// };

const LIST_OPTIONS = [
    { label: 'Bills', value: 'bills' },
    { label: 'Estimates', value: 'estimates' }
];

const WALK_IN_NAME = 'Walk-in Customer';
// One search when typing pauses, not one per key: they queue up on the server.
const SEARCH_DELAY_MS = 300;

// What differs between the two lists: where a row opens, and the buttons.
const KINDS = {
    bills: {
        detailPage: 'Bill_Detail',
        newPage: 'New_Bill',
        quickPage: 'Quick_Bill',
        quickLabel: 'Quick Bill',
        newLabel: 'New Bill',
        searchPlaceholder: 'Search by invoice number, customer, phone or party',
        empty: 'No bills found.'
    },
    estimates: {
        detailPage: 'Estimate_Detail',
        newPage: 'New_Estimate',
        quickPage: 'Quick_Estimate',
        quickLabel: 'Quick Estimate',
        newLabel: 'New Estimate',
        searchPlaceholder: 'Search by estimate number, customer, phone or party',
        empty: 'No estimates found.'
    }
};

function formatAmount(value) {
    return (Number(value) || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/**
 * The Billing tab: saved bills or estimates (latest versions), searchable and
 * filterable by company. A row opens its details; its Easy Bill button opens
 * it on the Easy Bill page, to see it as printed and change it (saving there
 * makes a new version, architecture.md §C.4).
 */
export default class BillingList extends NavigationMixin(LightningElement) {
    @track bills = [];

    listOptions = LIST_OPTIONS;
    listType = 'bills';
    // Deleted bills are kept for GST; they're listed only when asked for.
    showDeleted = false;

    // All/Dues Only filter disabled alongside the payment status feature
    // (2026-10) — listBills still accepts a filter param, so this just
    // always asks for 'All' now. Uncomment to restore the toggle.
    // filter = 'All';
    searchTerm = '';
    isLoading = true;

    companyFilter = null;

    _loadSeq = 0;
    _searchTimer;

    // Every company, for the GST due-date reminder (G5).
    profiles = [];

    connectedCallback() {
        this.loadReminders();
        disablePullToRefresh(this);
        this.loadBills();
    }

    disconnectedCallback() {
        clearTimeout(this._searchTimer);
    }

    get kind() {
        return KINDS[this.listType];
    }

    get isEstimates() {
        return this.listType === 'estimates';
    }

    loadReminders() {
        return listProfiles()
            .then((profiles) => {
                this.profiles = profiles || [];
            })
            .catch(() => {
                // Only a reminder: the list works without it.
                this.profiles = [];
            });
    }

    // Returns due within a week or late, for the company shown (all, if none
    // is picked), soonest first, named by company when there are several.
    get gstReminders() {
        const shown = this.companyFilter ? this.profiles.filter((p) => p.id === this.companyFilter) : this.profiles;
        const named = this.profiles.length > 1;
        return shown
            .flatMap((profile) =>
                gstDueDates(profile)
                    .filter((d) => d.isSoon)
                    .map((d) => ({ ...d, key: `${profile.id}-${d.key}`, text: named ? `${profile.name}: ${d.text}` : d.text }))
            )
            .sort((a, b) => (a.due < b.due ? -1 : a.due > b.due ? 1 : 0))
            .slice(0, 3);
    }

    get hasGstReminders() {
        return this.gstReminders.length > 0;
    }

    get gstReminderClass() {
        return this.gstReminders.some((d) => d.isLate)
            ? 'slds-scoped-notification slds-theme_error slds-m-bottom_small gst-reminder'
            : 'slds-scoped-notification slds-theme_warning slds-m-bottom_small gst-reminder';
    }

    handleOpenGstReturns() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GST_Returns' }
        });
    }

    loadBills() {
        this.isLoading = true;
        const seq = ++this._loadSeq;
        const workshopProfileId = this.companyFilter || undefined;
        const request = this.isEstimates
            ? listEstimates({ searchTerm: this.searchTerm, workshopProfileId })
            : listBills({ filter: this.showDeleted ? 'Cancelled' : 'All', searchTerm: this.searchTerm, workshopProfileId });
        return request
            .then((results) => {
                // A reply for the other list, or an older search, is dropped.
                if (seq === this._loadSeq) {
                    this.bills = results;
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                if (seq === this._loadSeq) {
                    this.isLoading = false;
                }
            });
    }

    // One row shape for both lists. A party bill is shown under the party's
    // name, with the car owner as the buyer.
    get decoratedBills() {
        // return this.bills.map((b) => ({ ...b, badgeClass: STATUS_BADGE_CLASS[b.status] || 'slds-badge' }));
        return this.bills.map((b) => {
            const party = b.billToPartyName;
            const buyer = b.customerName && b.customerName !== WALK_IN_NAME ? b.customerName : '';
            return {
                id: b.id,
                number: this.isEstimates ? b.estimateNumber : b.invoiceNumber,
                name: party || b.customerName,
                buyer: party && buyer ? `Buyer: ${buyer}` : '',
                companyName: b.companyName,
                totalAmount: formatAmount(b.totalAmount),
                isDeleted: !this.isEstimates && this.showDeleted,
                easyBillLabel: `Open ${this.isEstimates ? 'estimate' : 'bill'} ${this.isEstimates ? b.estimateNumber : b.invoiceNumber} in Easy Bill`
            };
        });
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

    get deletedToggleLabel() {
        return this.showDeleted ? 'Back to bills' : 'Show deleted bills';
    }

    handleToggleDeleted() {
        this.showDeleted = !this.showDeleted;
        this.bills = [];
        this.loadBills();
    }

    handleListTypeChange(event) {
        this.listType = event.detail.value;
        this.showDeleted = false;
        this.bills = [];
        this.loadBills();
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this._searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = setTimeout(() => this.loadBills(), SEARCH_DELAY_MS);
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
            attributes: { apiName: this.kind.detailPage },
            state: { c__recordId: id }
        });
    }

    // c__opened makes opening the same bill twice in a row still reload it.
    handleOpenInEasyBill(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Easy_Bill' },
            state: { c__editId: event.currentTarget.dataset.record, c__opened: String(Date.now()) }
        });
    }

    handleNewBill() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: this.kind.newPage }
        });
    }

    // Only reloads on a real change: the picker also reports in when it loads.
    handleCompanyFilter(event) {
        const id = event.detail.id || null;
        if (id !== this.companyFilter) {
            this.companyFilter = id;
            this.loadBills();
        }
    }

    handleQuickBill() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: this.kind.quickPage }
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
