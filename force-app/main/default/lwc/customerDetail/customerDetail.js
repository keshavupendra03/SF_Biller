import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import getCustomerDetail from '@salesforce/apex/CustomerController.getCustomerDetail';
import updateCustomer from '@salesforce/apex/CustomerController.updateCustomer';
import createVehicle from '@salesforce/apex/CustomerController.createVehicle';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';
import customerHistory from '@salesforce/apex/ArchiveController.customerHistory';
import getArchivedJob from '@salesforce/apex/ArchiveController.getArchivedJob';
import { STATE_OPTIONS, checkGstinBox, withStateFromGstin, tidyState, changedValue } from 'c/gst';

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

function shortDate(iso) {
    if (!iso) return '';
    const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
    return new Date(y, m - 1, d).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

export default class CustomerDetail extends NavigationMixin(LightningElement) {
    stateOptions = STATE_OPTIONS;
    customerId;
    @track detail;
    isLoading = true;

    isEditing = false;
    editValues = {};
    isSaving = false;

    showAddVehicle = false;
    newVehicle = { ...EMPTY_VEHICLE };
    isSavingVehicle = false;

    showBlankSlipChooser = false;
    // The Vehicle__c (or, with no vehicle picked, Customer__c) a blank job
    // slip is being previewed for — JobSlipPdf prefills just those details.
    blankSlipRecordId;
    blankSlipCompanyId;

    // Jobs and job slips archived into Files (WorkArchive): listed, a job
    // opened in place, a slip printed from its archive copy.
    archivedWork = [];
    openArchivedJobId;
    archivedJob;
    archivedSlip;

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
            this.showBlankSlipChooser = false;
            this.blankSlipRecordId = undefined;
            this.archivedWork = [];
            this.openArchivedJobId = undefined;
            this.archivedSlip = undefined;
            this.loadDetail();
            this.loadArchived();
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

    // Separate from the customer's own details, so a slow archive read never holds up the page.
    loadArchived() {
        const customerId = this.customerId;
        return customerHistory({ customerId })
            .then((rows) => {
                if (customerId === this.customerId) {
                    this.archivedWork = rows || [];
                }
            })
            .catch(() => {
                this.archivedWork = [];
            });
    }

    get hasArchivedWork() {
        return this.hasDetail && this.archivedWork.length > 0;
    }

    get decoratedArchivedWork() {
        return this.archivedWork.map((r) => {
            const isOpen = r.recordId === this.openArchivedJobId && !!this.archivedJob;
            const j = isOpen ? this.archivedJob : null;
            return {
                ...r,
                kindLabel: r.kind === 'slip' ? 'Job slip' : 'Job',
                sub: [r.vehicle, r.detail].filter((p) => p).join(' • '),
                dateText: shortDate(r.workDate),
                isOpen,
                jobLines: j
                    ? [
                          { label: 'Stage', value: j.stageName },
                          { label: 'Opened', value: shortDate(j.createdDate) },
                          { label: 'Last moved', value: shortDate(j.lastChanged) },
                          { label: 'Vehicle', value: j.vehicle },
                          { label: 'Mechanics', value: j.mechanicNames },
                          { label: 'Surveyor', value: j.surveyorName },
                          { label: 'Notes', value: j.notes }
                      ].filter((line) => line.value)
                    : []
            };
        });
    }

    handleOpenArchived(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const row = this.archivedWork.find((r) => r.recordId === recordId);
        if (!row) {
            return;
        }
        if (row.kind === 'slip') {
            this.archivedSlip = { recordId: row.recordId, documentId: row.documentId, heading: `Job Slip ${row.docNumber}` };
            return;
        }
        if (this.openArchivedJobId === recordId) {
            this.openArchivedJobId = undefined;
            this.archivedJob = undefined;
            return;
        }
        getArchivedJob({ documentId: row.documentId, jobId: row.recordId })
            .then((job) => {
                this.archivedJob = job;
                this.openArchivedJobId = recordId;
            })
            .catch((error) => this.showError(error));
    }

    handleCloseArchivedSlip() {
        this.archivedSlip = undefined;
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

    get hasJobSlips() {
        return this.hasDetail && (this.detail.jobSlips || []).length > 0;
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
            this.editValues = tidyState(this.editValues);
        }
    }

    handleEditFieldChange(event) {
        const field = event.target.dataset.field;
        this.editValues = { ...this.editValues, [field]: changedValue(event) };
        if (field === 'gstin') {
            checkGstinBox(event.target);
            this.editValues = withStateFromGstin(this.editValues);
        }
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
        this.newVehicle = { ...this.newVehicle, [field]: changedValue(event) };
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

    handleNewJobSlip() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Job_Slip' },
            state: { c__customerId: this.customerId }
        });
    }

    handleOpenJobSlip(event) {
        this.navigateToRecord('Job_Slip', event.currentTarget.dataset.id);
    }

    // With no vehicles and one company there's nothing to choose, so straight
    // to the preview.
    handlePrintBlankSlip() {
        listProfiles()
            .then((profiles) => {
                if (this.hasVehicles || (profiles || []).length > 1) {
                    this.showBlankSlipChooser = true;
                } else {
                    this.blankSlipRecordId = this.customerId;
                }
            })
            .catch((error) => this.showError(error));
    }

    handleBlankSlipCompany(event) {
        this.blankSlipCompanyId = event.detail.id;
    }

    get noVehicleLabel() {
        return this.hasVehicles ? 'Another vehicle' : 'Print job slip';
    }

    handleChooseBlankSlipVehicle(event) {
        this.showBlankSlipChooser = false;
        this.blankSlipRecordId = event.currentTarget.dataset.vehicleId || this.customerId;
    }

    handleCancelBlankSlip() {
        this.showBlankSlipChooser = false;
    }

    handleCloseBlankSlip() {
        this.blankSlipRecordId = undefined;
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
