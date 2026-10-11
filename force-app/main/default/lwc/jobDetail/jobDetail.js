import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getJobDetail from '@salesforce/apex/JobController.getJobDetail';

/**
 * Read-only Job Details screen — reachable from both the Jobs board and a
 * customer's Jobs list (architecture.md §B). Mirrors billDetail/
 * estimateDetail's page-reference/back-navigation pattern exactly.
 */
export default class JobDetail extends NavigationMixin(LightningElement) {
    jobId;
    summary;
    isLoading = true;

    // The customer screen this job was opened from, if any — Back returns
    // there instead of the Jobs board when it's set.
    fromCustomerId;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        const state = pageRef.state || {};
        if (state.c__recordId && state.c__recordId !== this.jobId) {
            this.jobId = state.c__recordId;
            this.summary = undefined;
            this.fromCustomerId = state.c__fromCustomerId;
            this.loadSummary();
        }
    }

    loadSummary() {
        this.isLoading = true;
        return getJobDetail({ jobId: this.jobId })
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

    get hasVehicle() {
        return this.hasSummary && !!this.summary.vehicleRegistrationNumber;
    }

    get hasSurveyor() {
        return this.hasSummary && !!this.summary.surveyorName;
    }

    get hasMechanics() {
        return this.hasSummary && !!this.summary.mechanicNames;
    }

    get hasNotes() {
        return this.hasSummary && !!this.summary.notes;
    }

    get hasBills() {
        return this.hasSummary && this.summary.bills.length > 0;
    }

    get hasEstimates() {
        return this.hasSummary && this.summary.estimates.length > 0;
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
            attributes: { apiName: 'Jobs_Board' }
        });
    }

    handleOpenBill(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: event.currentTarget.dataset.id }
        });
    }

    handleOpenEstimate(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Estimate_Detail' },
            state: { c__recordId: event.currentTarget.dataset.id }
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
