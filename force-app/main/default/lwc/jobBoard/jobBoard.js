import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBoardData from '@salesforce/apex/JobController.getBoardData';
import searchVehicles from '@salesforce/apex/JobController.searchVehicles';
import getActiveMechanics from '@salesforce/apex/JobController.getActiveMechanics';
import getActiveSurveyors from '@salesforce/apex/JobController.getActiveSurveyors';
import createJob from '@salesforce/apex/JobController.createJob';
import moveJob from '@salesforce/apex/JobController.moveJob';
import assignMechanics from '@salesforce/apex/JobController.assignMechanics';
import searchCustomers from '@salesforce/apex/BillController.searchCustomers';
import createCustomer from '@salesforce/apex/BillController.createCustomer';

const EMPTY_NEW_VEHICLE = { registrationNumber: '', make: '', model: '', year: '', color: '' };
const EMPTY_NEW_CUSTOMER = { name: '', phone: '', address: '', email: '', gstin: '', state: '' };

export default class JobBoard extends NavigationMixin(LightningElement) {
    // Raw data from Apex, kept separate from the decorated view the
    // template renders — columns/decorateJob are a GETTER computed from
    // these, so a job card's mechanic checkboxes are always correct
    // regardless of which of getBoardData()/getActiveMechanics() happens
    // to resolve first (they're independent promise chains in
    // connectedCallback; pre-computing "columns" once in loadBoard() and
    // caching it would silently render empty checkboxes if the mechanics
    // list arrived after the board already had).
    @track rawStages = [];
    @track rawJobs = [];
    @track allMechanics = [];
    @track surveyorOptions = [{ label: 'None', value: '' }];
    @track customerResults = [];
    @track vehicleResults = [];

    isLoading = true;
    isSubmittingJob = false;
    draggedJobId;
    searchTerm = '';

    // Create-job form state.
    showCreateForm = false;
    customerSearchTerm = '';
    selectedCustomer;
    showNewCustomerFields = false;
    newCustomer = { ...EMPTY_NEW_CUSTOMER };
    isSavingCustomer = false;
    vehicleSearchTerm = '';
    selectedVehicle;
    showNewVehicleFields = false;
    newVehicle = { ...EMPTY_NEW_VEHICLE };
    selectedSurveyorId = '';
    selectedMechanicIds = [];
    notes = '';

    // Which job card currently has its mechanic-assignment panel open.
    expandedMechanicsJobId;

    connectedCallback() {
        this.loadBoard();
        getActiveMechanics()
            .then((mechanics) => {
                this.allMechanics = mechanics;
            })
            .catch((error) => this.showError(error));
        getActiveSurveyors()
            .then((surveyors) => {
                this.surveyorOptions = [
                    { label: 'None', value: '' },
                    ...surveyors.map((s) => ({ label: s.name, value: s.id }))
                ];
            })
            .catch((error) => this.showError(error));
    }

    get columns() {
        return this.rawStages.map((stage) => ({
            id: stage.id,
            name: stage.name,
            jobs: this.rawJobs
                .filter((job) => job.stageId === stage.id)
                .map((job) => this.decorateJob(job))
        }));
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.loadBoard();
    }

    loadBoard() {
        this.isLoading = true;
        return getBoardData({ searchTerm: this.searchTerm })
            .then((data) => {
                this.rawStages = data.stages;
                this.rawJobs = data.jobs;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    decorateJob(job) {
        return {
            ...job,
            isMechanicsExpanded: job.id === this.expandedMechanicsJobId,
            mechanicCheckboxes: this.allMechanics.map((m) => ({
                id: m.id,
                name: m.name,
                checked: (job.mechanicIds || []).includes(m.id)
            })),
            otherStages: this.rawStages
                .filter((s) => s.id !== job.stageId)
                .map((s) => ({ label: s.name, value: s.id, jobId: job.id }))
        };
    }

    get hasCustomerResults() {
        return this.customerResults.length > 0;
    }

    get hasVehicleResults() {
        return this.vehicleResults.length > 0;
    }

    get hasSelectedCustomer() {
        return !!this.selectedCustomer;
    }

    get hasSelectedVehicle() {
        return !!this.selectedVehicle;
    }

    get canCreateJob() {
        const hasVehicle = this.hasSelectedVehicle
            || (this.showNewVehicleFields && !!this.newVehicle.registrationNumber);
        return this.hasSelectedCustomer && hasVehicle && !this.isSubmittingJob;
    }

    get createDisabled() {
        return !this.canCreateJob;
    }

    get createButtonLabel() {
        return this.isSubmittingJob ? 'Saving…' : 'Create Job';
    }

    get toggleFormLabel() {
        return this.showCreateForm ? 'Cancel' : 'New Job';
    }

    handleToggleCreateForm() {
        this.showCreateForm = !this.showCreateForm;
        if (!this.showCreateForm) {
            this.resetCreateForm();
        }
    }

    handleCustomerSearchChange(event) {
        this.customerSearchTerm = event.target.value;
        if (this.customerSearchTerm.length < 2) {
            this.customerResults = [];
            return;
        }
        searchCustomers({ searchTerm: this.customerSearchTerm })
            .then((results) => {
                this.customerResults = results;
            })
            .catch((error) => this.showError(error));
    }

    handleSelectCustomer(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedCustomer = this.customerResults.find((c) => c.id === id);
        this.customerResults = [];
        this.customerSearchTerm = '';
        this.selectedVehicle = undefined;
        this.vehicleResults = [];
    }

    handleClearCustomer() {
        this.selectedCustomer = undefined;
        this.selectedVehicle = undefined;
    }

    handleToggleNewCustomer(event) {
        this.showNewCustomerFields = event.target.checked;
        if (!this.showNewCustomerFields) {
            this.newCustomer = { ...EMPTY_NEW_CUSTOMER };
        }
    }

    handleNewCustomerFieldChange(event) {
        const field = event.target.dataset.field;
        this.newCustomer = { ...this.newCustomer, [field]: event.target.value };
    }

    get canSaveNewCustomer() {
        return !!this.newCustomer.name && !!this.newCustomer.phone && !this.isSavingCustomer;
    }

    get saveNewCustomerDisabled() {
        return !this.canSaveNewCustomer;
    }

    handleCreateCustomerInline() {
        if (!this.canSaveNewCustomer) {
            return;
        }
        this.isSavingCustomer = true;
        createCustomer({ input: { ...this.newCustomer } })
            .then((customer) => {
                this.selectedCustomer = customer;
                this.showNewCustomerFields = false;
                this.newCustomer = { ...EMPTY_NEW_CUSTOMER };
                this.showToast('Customer added', `${customer.name} created.`, 'success');
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSavingCustomer = false;
            });
    }

    handleVehicleSearchChange(event) {
        this.vehicleSearchTerm = event.target.value;
        if (!this.selectedCustomer) {
            return;
        }
        searchVehicles({ customerId: this.selectedCustomer.id, searchTerm: this.vehicleSearchTerm })
            .then((results) => {
                this.vehicleResults = results;
            })
            .catch((error) => this.showError(error));
    }

    handleSelectVehicle(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedVehicle = this.vehicleResults.find((v) => v.id === id);
        this.vehicleResults = [];
        this.vehicleSearchTerm = '';
    }

    handleClearVehicle() {
        this.selectedVehicle = undefined;
    }

    handleToggleNewVehicle(event) {
        this.showNewVehicleFields = event.target.checked;
        if (!this.showNewVehicleFields) {
            this.newVehicle = { ...EMPTY_NEW_VEHICLE };
        } else {
            this.selectedVehicle = undefined;
        }
    }

    handleNewVehicleFieldChange(event) {
        const field = event.target.dataset.field;
        this.newVehicle = { ...this.newVehicle, [field]: event.target.value };
    }

    handleSurveyorChange(event) {
        this.selectedSurveyorId = event.detail.value;
    }

    handleNewJobMechanicToggle(event) {
        const id = event.target.dataset.id;
        if (event.target.checked) {
            this.selectedMechanicIds = [...this.selectedMechanicIds, id];
        } else {
            this.selectedMechanicIds = this.selectedMechanicIds.filter((m) => m !== id);
        }
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    handleCreateJob() {
        if (!this.canCreateJob) {
            return;
        }
        this.isSubmittingJob = true;

        const request = {
            customerId: this.selectedCustomer.id,
            vehicleId: this.showNewVehicleFields ? null : this.selectedVehicle.id,
            newVehicle: this.showNewVehicleFields
                ? {
                      registrationNumber: this.newVehicle.registrationNumber,
                      make: this.newVehicle.make,
                      model: this.newVehicle.model,
                      year: this.newVehicle.year ? Number(this.newVehicle.year) : null,
                      color: this.newVehicle.color
                  }
                : null,
            surveyorId: this.selectedSurveyorId || null,
            notes: this.notes,
            mechanicIds: this.selectedMechanicIds
        };

        createJob({ request })
            .then(() => {
                this.showToast('Job created', 'The job was added to the board.', 'success');
                this.showCreateForm = false;
                this.resetCreateForm();
                return this.loadBoard();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSubmittingJob = false;
            });
    }

    resetCreateForm() {
        this.customerSearchTerm = '';
        this.selectedCustomer = undefined;
        this.customerResults = [];
        this.showNewCustomerFields = false;
        this.newCustomer = { ...EMPTY_NEW_CUSTOMER };
        this.vehicleSearchTerm = '';
        this.selectedVehicle = undefined;
        this.vehicleResults = [];
        this.showNewVehicleFields = false;
        this.newVehicle = { ...EMPTY_NEW_VEHICLE };
        this.selectedSurveyorId = '';
        this.selectedMechanicIds = [];
        this.notes = '';
    }

    // Desktop drag-and-drop.
    handleDragStart(event) {
        this.draggedJobId = event.currentTarget.dataset.jobId;
        event.dataTransfer.setData('text/plain', this.draggedJobId);
    }

    handleDragOver(event) {
        event.preventDefault();
    }

    handleDrop(event) {
        event.preventDefault();
        const targetStageId = event.currentTarget.dataset.stageId;
        const jobId = this.draggedJobId || event.dataTransfer.getData('text/plain');
        if (jobId && targetStageId) {
            this.moveJobToStage(jobId, targetStageId);
        }
        this.draggedJobId = undefined;
    }

    // Mobile/no-drag fallback: a combobox of "other stages" per card.
    handleMoveSelect(event) {
        const jobId = event.target.dataset.jobId;
        const targetStageId = event.detail.value;
        if (jobId && targetStageId) {
            this.moveJobToStage(jobId, targetStageId);
        }
    }

    moveJobToStage(jobId, targetStageId) {
        moveJob({ jobId, newStageId: targetStageId })
            .then(() => this.loadBoard())
            .catch((error) => this.showError(error));
    }

    handleToggleMechanicsPanel(event) {
        const jobId = event.currentTarget.dataset.jobId;
        // columns is a getter recomputed from rawJobs/rawStages/allMechanics —
        // setting this field alone is enough to re-render with the right
        // card's isMechanicsExpanded flipped.
        this.expandedMechanicsJobId = this.expandedMechanicsJobId === jobId ? undefined : jobId;
    }

    handleMechanicAssignmentToggle(event) {
        const jobId = event.target.dataset.jobId;
        const mechanicId = event.target.dataset.mechanicId;
        const checked = event.target.checked;

        let job;
        for (const col of this.columns) {
            const found = col.jobs.find((j) => j.id === jobId);
            if (found) {
                job = found;
                break;
            }
        }
        if (!job) {
            return;
        }
        const currentIds = job.mechanicIds || [];
        const newIds = checked ? [...currentIds, mechanicId] : currentIds.filter((id) => id !== mechanicId);

        assignMechanics({ jobId, mechanicIds: newIds })
            .then(() => this.loadBoard())
            .catch((error) => this.showError(error));
    }

    handleOpenJob(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Job_Detail' },
            state: { c__recordId: event.currentTarget.dataset.jobId }
        });
    }

    handleCreateEstimateForJob(event) {
        this.navigateToJobLinkedPage('New_Estimate', event.currentTarget.dataset.jobId);
    }

    handleCreateBillForJob(event) {
        this.navigateToJobLinkedPage('New_Bill', event.currentTarget.dataset.jobId);
    }

    navigateToJobLinkedPage(tabApiName, jobId) {
        const job = this.rawJobs.find((j) => j.id === jobId);
        if (!job) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: tabApiName
            },
            state: {
                c__jobId: job.id,
                c__customerId: job.customerId,
                c__customerName: job.customerName
            }
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
