import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchCustomers from '@salesforce/apex/BillController.searchCustomers';
import createCustomer from '@salesforce/apex/BillController.createCustomer';
import listVehiclesForCustomer from '@salesforce/apex/CustomerController.listVehiclesForCustomer';
import listBillToParties from '@salesforce/apex/DirectoryController.listBillToParties';
import createEstimate from '@salesforce/apex/EstimateController.createEstimate';
import createNewVersion from '@salesforce/apex/EstimateController.createNewVersion';
import getEstimateSummary from '@salesforce/apex/EstimateController.getEstimateSummary';
import { calculateLine, calculateBillTotals } from 'c/gstMath';
import { disablePullToRefresh } from 'c/disablePullToRefresh';

const EMPTY_BILL_TO_PARTY = { name: '', address: '', contactPhone: '', gstin: '', state: '' };
const EMPTY_NEW_CUSTOMER = { name: '', phone: '', address: '', email: '', gstin: '', state: '' };
const EMPTY_VEHICLE = { registrationNumber: '', make: '', model: '', year: '', color: '', chassisNumber: '' };
const EMPTY_LINE = { partId: null, description: '', quantity: 1, unitPrice: 0, taxRatePercent: 18, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' };

function todayIso() {
    return new Date().toISOString().slice(0, 10);
}

let nextLineKey = 1;

export default class EstimateCreate extends NavigationMixin(LightningElement) {
    @track customerResults = [];
    @track lines = [];

    customerSearchTerm = '';
    selectedCustomer;
    showNewCustomerFields = false;
    newCustomer = { ...EMPTY_NEW_CUSTOMER };
    isSavingCustomer = false;

    @track billToPartyResults = [];
    showBillToParty = false;
    billToPartySearchTerm = '';
    selectedBillToParty;
    showNewBillToPartyFields = false;
    newBillToParty = { ...EMPTY_BILL_TO_PARTY };
    carriedBillToPartyId;
    isSearchingBillToParties = false;

    @track vehicleOptions = [];
    selectedVehicleId;
    showNewVehicleFields = false;
    newVehicle = { ...EMPTY_VEHICLE };

    notes = '';
    estimateDate = todayIso();

    isSubmitting = false;
    isSearchingCustomers = false;

    // Line-item popup (lineItemEditor): set => that modal is open, editing this line.
    editingLine;

    versionBaseId; // set => the screen is in "edit an existing estimate" mode.
    jobId; // carried through to the created estimate when arriving from a job card.
    fromCustomerId; // the customer screen this estimate was opened from, if any — carried through to Estimate_Detail so its own Back works.
    _appliedPageRefKey;

    connectedCallback() {
        disablePullToRefresh(this);
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        const state = pageRef.state || {};
        const key = JSON.stringify(state);
        if (key === this._appliedPageRefKey) {
            return;
        }
        this._appliedPageRefKey = key;
        this.resetForm();
        this.fromCustomerId = state.c__fromCustomerId;
        if (state.c__recordId) {
            this.loadEstimateForVersioning(state.c__recordId);
        } else if (state.c__jobId) {
            this.jobId = state.c__jobId;
            if (state.c__customerId) {
                this.selectedCustomer = {
                    id: state.c__customerId,
                    name: state.c__customerName || '',
                    phone: ''
                };
                this.loadVehicleOptions(state.c__customerId);
            }
        } else if (state.c__customerId) {
            this.selectedCustomer = {
                id: state.c__customerId,
                name: state.c__customerName || '',
                phone: ''
            };
            this.loadVehicleOptions(state.c__customerId);
        }
    }

    get hasSelectedCustomer() {
        return !!this.selectedCustomer;
    }

    get hasCustomerResults() {
        return this.customerResults.length > 0;
    }

    get hasBillToPartyResults() {
        return this.billToPartyResults.length > 0;
    }

    get hasSelectedBillToParty() {
        return !!this.selectedBillToParty;
    }

    get hasVehicleOptions() {
        return this.vehicleOptions.length > 0;
    }

    get hasSelectedVehicle() {
        return !!this.selectedVehicleId && !this.showNewVehicleFields;
    }

    get selectedVehicle() {
        return this.vehicleOptions.find((v) => v.id === this.selectedVehicleId);
    }

    get decoratedVehicleOptions() {
        return this.vehicleOptions.map((v) => ({
            ...v,
            label: [v.registrationNumber, [v.make, v.model].filter((p) => p).join(' ')].filter((p) => p).join(' — ')
        }));
    }

    get selectedVehicleLabel() {
        const v = this.selectedVehicle;
        if (!v) {
            return '';
        }
        return [v.registrationNumber, [v.make, v.model].filter((p) => p).join(' ')].filter((p) => p).join(' — ');
    }

    get hasLines() {
        return this.lines.length > 0;
    }

    get isVersioning() {
        return !!this.versionBaseId;
    }

    get showLineEditor() {
        return !!this.editingLine;
    }

    get decoratedLines() {
        return this.lines.map((line) => ({
            ...line,
            lineTotal: calculateLine(line).total.toFixed(2)
        }));
    }

    get totals() {
        return calculateBillTotals(this.lines);
    }

    get formattedSubtotal() {
        return this.totals.subtotal.toFixed(2);
    }

    get formattedCgst() {
        return this.totals.cgst.toFixed(2);
    }

    get formattedSgst() {
        return this.totals.sgst.toFixed(2);
    }

    get formattedIgst() {
        return this.totals.igst.toFixed(2);
    }

    get formattedGrandTotal() {
        return this.totals.grandTotal.toFixed(2);
    }

    get hasIgstLines() {
        return this.totals.igst > 0;
    }

    get hasCgstSgstLines() {
        return this.totals.cgst > 0 || this.totals.sgst > 0;
    }

    get canSubmit() {
        return this.hasSelectedCustomer && this.hasLines && !this.isSubmitting;
    }

    get submitDisabled() {
        return !this.canSubmit;
    }

    get submitButtonLabel() {
        if (this.isSubmitting) {
            return 'Saving…';
        }
        return this.isVersioning ? 'Save Changes' : 'Create Estimate';
    }

    get cardTitle() {
        return this.isVersioning ? 'Edit Estimate' : 'New Estimate';
    }

    handleBack() {
        if (this.isVersioning) {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'Estimate_Detail' },
                state: { c__recordId: this.versionBaseId, c__fromCustomerId: this.fromCustomerId }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'Customer_List' }
            });
        }
    }

    handleCustomerSearchChange(event) {
        this.customerSearchTerm = event.target.value;
        if (this.customerSearchTerm.length < 2) {
            this.customerResults = [];
            return;
        }
        this.isSearchingCustomers = true;
        searchCustomers({ searchTerm: this.customerSearchTerm })
            .then((results) => {
                this.customerResults = results;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSearchingCustomers = false;
            });
    }

    handleSelectCustomer(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedCustomer = this.customerResults.find((c) => c.id === id);
        this.customerResults = [];
        this.customerSearchTerm = '';
        this.resetVehicleSelection();
        this.loadVehicleOptions(id);
    }

    handleClearCustomer() {
        this.selectedCustomer = undefined;
        this.resetVehicleSelection();
        this.vehicleOptions = [];
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
                this.resetVehicleSelection();
                this.vehicleOptions = [];
                this.showToast('Customer added', `${customer.name} created.`, 'success');
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSavingCustomer = false;
            });
    }

    handleToggleBillToParty(event) {
        this.showBillToParty = event.target.checked;
        if (!this.showBillToParty) {
            this.billToPartySearchTerm = '';
            this.billToPartyResults = [];
            this.selectedBillToParty = undefined;
            this.showNewBillToPartyFields = false;
            this.newBillToParty = { ...EMPTY_BILL_TO_PARTY };
        }
    }

    handleBillToPartySearchChange(event) {
        this.billToPartySearchTerm = event.target.value;
        if (this.billToPartySearchTerm.length < 2) {
            this.billToPartyResults = [];
            return;
        }
        this.isSearchingBillToParties = true;
        listBillToParties({ searchTerm: this.billToPartySearchTerm })
            .then((results) => {
                this.billToPartyResults = results;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSearchingBillToParties = false;
            });
    }

    handleSelectBillToParty(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedBillToParty = this.billToPartyResults.find((p) => p.id === id);
        this.billToPartyResults = [];
        this.billToPartySearchTerm = '';
    }

    handleClearBillToParty() {
        this.selectedBillToParty = undefined;
    }

    handleToggleNewBillToParty(event) {
        this.showNewBillToPartyFields = event.target.checked;
        if (!this.showNewBillToPartyFields) {
            this.newBillToParty = { ...EMPTY_BILL_TO_PARTY };
        } else {
            this.selectedBillToParty = undefined;
        }
    }

    handleBillToPartyFieldChange(event) {
        const field = event.target.dataset.field;
        this.newBillToParty = { ...this.newBillToParty, [field]: event.target.value };
    }

    loadVehicleOptions(customerId) {
        if (!customerId) {
            this.vehicleOptions = [];
            return Promise.resolve();
        }
        return listVehiclesForCustomer({ customerId })
            .then((results) => {
                this.vehicleOptions = results;
                if (!this.selectedVehicleId && !this.showNewVehicleFields && results.length > 0) {
                    this.selectedVehicleId = results[0].id;
                }
            })
            .catch((error) => this.showError(error));
    }

    resetVehicleSelection() {
        this.selectedVehicleId = undefined;
        this.showNewVehicleFields = false;
        this.newVehicle = { ...EMPTY_VEHICLE };
    }

    handleSelectVehicle(event) {
        this.selectedVehicleId = event.currentTarget.dataset.id;
        this.showNewVehicleFields = false;
    }

    handleClearVehicle() {
        this.selectedVehicleId = undefined;
    }

    handleToggleNewVehicle(event) {
        this.showNewVehicleFields = event.target.checked;
        if (this.showNewVehicleFields) {
            this.selectedVehicleId = undefined;
        } else {
            this.newVehicle = { ...EMPTY_VEHICLE };
        }
    }

    handleVehicleFieldChange(event) {
        const field = event.target.dataset.field;
        this.newVehicle = { ...this.newVehicle, [field]: event.target.value };
    }

    handleEstimateDateChange(event) {
        this.estimateDate = event.target.value;
    }

    handleAddLineItem() {
        this.editingLine = { ...EMPTY_LINE };
    }

    handleEditLine(event) {
        const key = Number(event.currentTarget.dataset.key);
        const line = this.lines.find((l) => l.key === key);
        if (line) {
            this.editingLine = { ...line };
        }
    }

    handleLineEditorSave(event) {
        const edited = event.detail;
        if (edited.key) {
            this.lines = this.lines.map((line) => (line.key === edited.key ? { ...line, ...edited } : line));
        } else {
            this.lines = [...this.lines, { ...edited, key: nextLineKey++ }];
        }
        this.editingLine = undefined;
    }

    handleLineEditorCancel() {
        this.editingLine = undefined;
    }

    handleRemoveLine(event) {
        const key = Number(event.currentTarget.dataset.key);
        this.lines = this.lines.filter((line) => line.key !== key);
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    handleSubmit() {
        if (!this.canSubmit) {
            return;
        }
        this.isSubmitting = true;

        const request = {
            customerId: this.selectedCustomer.id,
            jobId: this.jobId,
            notes: this.notes,
            estimateDate: this.estimateDate,
            billToPartyId: this.showBillToParty
                ? (this.selectedBillToParty ? this.selectedBillToParty.id : null)
                : this.carriedBillToPartyId,
            newBillToParty:
                this.showBillToParty && !this.selectedBillToParty && this.newBillToParty.name
                    ? { ...this.newBillToParty }
                    : null,
            vehicleId: this.showNewVehicleFields ? null : this.selectedVehicleId,
            newVehicle:
                this.showNewVehicleFields && this.newVehicle.registrationNumber
                    ? { ...this.newVehicle }
                    : null,
            lineItems: this.lines.map((line) => ({
                partId: line.partId,
                description: line.description,
                quantity: Number(line.quantity),
                unitPrice: Number(line.unitPrice),
                taxRatePercent: Number(line.taxRatePercent),
                gstType: line.gstType,
                hsnSacCode: line.hsnSacCode,
                unitLabel: line.unitLabel
            }))
        };

        const savePromise = this.isVersioning
            ? createNewVersion({ previousEstimateId: this.versionBaseId, request })
            : createEstimate({ request });

        savePromise
            .then((summary) => {
                this.showToast(
                    'Estimate saved',
                    `${summary.estimateNumber} — ₹${summary.totalAmount}`,
                    'success'
                );
                this[NavigationMixin.Navigate]({
                    type: 'standard__navItemPage',
                    attributes: { apiName: 'Estimate_Detail' },
                    state: { c__recordId: summary.estimateId, c__fromCustomerId: this.fromCustomerId }
                });
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    resetForm() {
        this.customerResults = [];
        this.lines = [];
        this.customerSearchTerm = '';
        this.selectedCustomer = undefined;
        this.showNewCustomerFields = false;
        this.newCustomer = { ...EMPTY_NEW_CUSTOMER };
        this.billToPartyResults = [];
        this.showBillToParty = false;
        this.billToPartySearchTerm = '';
        this.selectedBillToParty = undefined;
        this.showNewBillToPartyFields = false;
        this.newBillToParty = { ...EMPTY_BILL_TO_PARTY };
        this.carriedBillToPartyId = undefined;
        this.vehicleOptions = [];
        this.selectedVehicleId = undefined;
        this.showNewVehicleFields = false;
        this.newVehicle = { ...EMPTY_VEHICLE };
        this.notes = '';
        this.estimateDate = todayIso();
        this.editingLine = undefined;
        this.versionBaseId = undefined;
        this.jobId = undefined;
        this.fromCustomerId = undefined;
    }

    loadEstimateForVersioning(estimateId) {
        getEstimateSummary({ estimateId })
            .then((summary) => {
                this.applySummaryToForm(summary);
                this.versionBaseId = estimateId;
            })
            .catch((error) => this.showError(error));
    }

    applySummaryToForm(summary) {
        this.selectedCustomer = { id: summary.customerId, name: summary.customerName, phone: '' };
        this.notes = summary.notes || '';
        this.estimateDate = todayIso();
        this.carriedBillToPartyId = summary.billToPartyId;
        // The estimate already being for a party (not the customer
        // directly) must show up as such — otherwise the edit screen looks
        // like it has no bill-to party at all, even though one is still
        // carried forward correctly underneath until the toggle is touched.
        if (summary.billToPartyId) {
            this.showBillToParty = true;
            this.selectedBillToParty = { id: summary.billToPartyId, name: summary.billToPartyName };
        }
        this.jobId = summary.jobId;
        this.selectedVehicleId = summary.vehicleId;
        this.loadVehicleOptions(summary.customerId);
        this.lines = (summary.lineItems || []).map((li) => ({
            key: nextLineKey++,
            partId: li.partId,
            description: li.description,
            quantity: li.quantity,
            unitPrice: li.unitPrice,
            taxRatePercent: li.taxRatePercent,
            gstType: li.gstType || 'CGST_SGST',
            hsnSacCode: li.hsnSacCode,
            unitLabel: li.unitLabel
        }));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
