import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import getJobSlipForm from '@salesforce/apex/JobSlipController.getJobSlipForm';
import saveJobSlip from '@salesforce/apex/JobSlipController.saveJobSlip';

// Same keys as JobSlipController.ACCESSORY_KEYS, in the paper slip's order.
const ACCESSORIES = [
    { key: 'serviceBooklet', label: 'Service Booklet' },
    { key: 'spareWheel', label: 'Spare Wheel' },
    { key: 'jackAndHandle', label: 'Jack & Handle' },
    { key: 'toolKit', label: 'Tool Kit' },
    { key: 'mats', label: 'Mats' },
    { key: 'mudFlaps', label: 'Mud Flaps' },
    { key: 'stereo', label: 'Stereo' },
    { key: 'clock', label: 'Clock' },
    { key: 'cassetteCd', label: 'Cassette / CD' },
    { key: 'sideBidding', label: 'Side Bidding' },
    { key: 'wheelCoverCap', label: 'Wheel Cover / Cap' },
    { key: 'remote', label: 'Remote' },
    { key: 'keyRing', label: 'Key Ring' }
];

const SERVICE_TYPES = [
    { value: '1st Free Service', label: '1st Free' },
    { value: '2nd Free Service', label: '2nd Free' },
    { value: '3rd Free Service', label: '3rd Free' },
    { value: '4th Free Service', label: '4th Free' },
    { value: 'Paid Service', label: 'Paid Service' },
    { value: 'Accidental Repair', label: 'Accident Repair' },
    { value: 'Running Repair', label: 'Running Repair' }
];

const FUEL_OPTIONS = [
    { label: 'E', value: 'E' },
    { label: '¼', value: '1/4' },
    { label: '½', value: '1/2' },
    { label: '¾', value: '3/4' },
    { label: 'F', value: 'F' }
];

const NEW_VEHICLE = '__new';
const EMPTY_NEW_VEHICLE = { registrationNumber: '', make: '', model: '' };

let lineKeySeed = 0;
function toLine(line) {
    lineKeySeed += 1;
    return {
        key: `line-${lineKeySeed}`,
        id: line ? line.id : null,
        customerRequest: line ? line.customerRequest || '' : '',
        observation: line ? line.observation || '' : '',
        labourEstimate: line ? line.labourEstimate : null,
        sparesEstimate: line ? line.sparesEstimate : null
    };
}

function toNumberOrNull(value) {
    return value === '' || value === null || value === undefined ? null : Number(value);
}

/**
 * Job Slip screen — the on-screen version of the workshop's paper intake
 * slip. Opened from Customer Detail either as a new slip (c__customerId,
 * optionally c__vehicleId) or an existing one (c__recordId). Either way
 * Save & Print hands the saved slip to documentPreview/JobSlipPdf for the
 * customer's signature; Customer Detail's "Print Blank" covers the other
 * order (paper first, typed in here later).
 */
export default class JobSlipEditor extends NavigationMixin(LightningElement) {
    pageKey;
    jobSlipId;
    customer;
    vehicles = [];
    slip = {};
    lines = [];
    accessories = new Set();
    isNewVehicle = false;
    newVehicle = { ...EMPTY_NEW_VEHICLE };

    isLoading = true;
    isSaving = false;
    showPreview = false;

    connectedCallback() {
        disablePullToRefresh(this);
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        const state = pageRef.state || {};
        const key = state.c__recordId || (state.c__customerId ? `new:${state.c__customerId}:${state.c__vehicleId || ''}` : null);
        if (!key || key === this.pageKey) {
            return;
        }
        this.pageKey = key;
        this.jobSlipId = state.c__recordId || null;
        this.customer = undefined;
        this.showPreview = false;
        this.loadForm(state.c__customerId, state.c__vehicleId);
    }

    loadForm(customerId, vehicleId) {
        this.isLoading = true;
        return getJobSlipForm({ jobSlipId: this.jobSlipId, customerId: customerId || null, vehicleId: vehicleId || null })
            .then((form) => {
                this.customer = form.customer;
                this.vehicles = form.vehicles || [];
                const { lines, accessories, ...slip } = form.slip;
                this.slip = slip;
                this.accessories = new Set(accessories || []);
                this.lines = lines && lines.length ? lines.map(toLine) : [toLine()];
                this.isNewVehicle = this.vehicles.length === 0;
                this.newVehicle = { ...EMPTY_NEW_VEHICLE };
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ---- derived view state -------------------------------------------

    get hasForm() {
        return !!this.customer;
    }

    get isSaved() {
        return !!this.jobSlipId;
    }

    get headerSubtitle() {
        return this.slip.slipNumber || 'New slip';
    }

    get vehicleOptions() {
        const options = this.vehicles.map((v) => ({
            label: [v.registrationNumber, [v.make, v.model].filter((p) => p).join(' ')].filter((p) => p).join(' — '),
            value: v.id
        }));
        options.push({ label: '+ Add new vehicle', value: NEW_VEHICLE });
        return options;
    }

    get selectedVehicleValue() {
        return this.isNewVehicle ? NEW_VEHICLE : this.slip.vehicleId;
    }

    get hasVehicles() {
        return this.vehicles.length > 0;
    }

    get selectedVehicleModel() {
        const vehicle = this.vehicles.find((v) => v.id === this.slip.vehicleId);
        return vehicle && !this.isNewVehicle ? [vehicle.make, vehicle.model].filter((p) => p).join(' ') : '';
    }

    get serviceTypeChips() {
        return SERVICE_TYPES.map((type) => ({
            ...type,
            variant: type.value === this.slip.serviceType ? 'brand' : 'neutral'
        }));
    }

    get fuelOptions() {
        return FUEL_OPTIONS;
    }

    get accessoryItems() {
        return ACCESSORIES.map((a) => ({ ...a, checked: this.accessories.has(a.key) }));
    }

    get presentCount() {
        return this.accessories.size;
    }

    get allPresent() {
        return this.accessories.size === ACCESSORIES.length;
    }

    get toggleAllLabel() {
        return this.allPresent ? 'Clear all' : 'Mark all present';
    }

    get numberedLines() {
        return this.lines.map((line, index) => ({ ...line, number: index + 1, canRemove: this.lines.length > 1 }));
    }

    get labourTotal() {
        return this.lines.reduce((sum, l) => sum + (Number(l.labourEstimate) || 0), 0);
    }

    get sparesTotal() {
        return this.lines.reduce((sum, l) => sum + (Number(l.sparesEstimate) || 0), 0);
    }

    get estimateTotal() {
        return this.labourTotal + this.sparesTotal;
    }

    get hasEstimateTotal() {
        return this.estimateTotal > 0;
    }

    get totalCostPlaceholder() {
        return this.hasEstimateTotal ? `Leave blank to print ₹${this.estimateTotal}` : 'e.g. ₹2,000 – ₹8,000';
    }

    get hasVehicleChoice() {
        return this.isNewVehicle ? !!this.newVehicle.registrationNumber : !!this.slip.vehicleId;
    }

    get saveDisabled() {
        return this.isSaving || this.isLoading || !this.hasVehicleChoice;
    }

    get saveHint() {
        return this.hasVehicleChoice ? '' : 'Select the vehicle (or add one) to save this slip.';
    }

    // ---- field handlers -------------------------------------------------

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.slip = { ...this.slip, [field]: event.detail.value !== undefined ? event.detail.value : event.target.value };
    }

    handleVehicleChange(event) {
        const value = event.detail.value;
        if (value === NEW_VEHICLE) {
            this.isNewVehicle = true;
            this.slip = { ...this.slip, vehicleId: null, chassisNumber: '', engineNumber: '', dateOfSale: null };
            return;
        }
        const vehicle = this.vehicles.find((v) => v.id === value);
        this.isNewVehicle = false;
        const next = {
            ...this.slip,
            vehicleId: value,
            chassisNumber: vehicle.chassisNumber,
            engineNumber: vehicle.engineNumber,
            dateOfSale: vehicle.dateOfSale
        };
        if (!this.isSaved) {
            next.batteryMake = vehicle.lastBatteryMake || '';
            next.batteryNumber = vehicle.lastBatteryNumber || '';
            next.tyreMake = vehicle.lastTyreMake || '';
        }
        this.slip = next;
    }

    handleNewVehicleChange(event) {
        const field = event.target.dataset.field;
        this.newVehicle = { ...this.newVehicle, [field]: event.detail.value !== undefined ? event.detail.value : event.target.value };
    }

    handleServiceType(event) {
        const value = event.target.dataset.value;
        this.slip = { ...this.slip, serviceType: this.slip.serviceType === value ? null : value };
    }

    handleFuelChange(event) {
        this.slip = { ...this.slip, fuelLevel: event.detail.value };
    }

    handleAccessoryChange(event) {
        const next = new Set(this.accessories);
        if (event.target.checked) {
            next.add(event.target.dataset.key);
        } else {
            next.delete(event.target.dataset.key);
        }
        this.accessories = next;
    }

    handleToggleAll() {
        this.accessories = this.allPresent ? new Set() : new Set(ACCESSORIES.map((a) => a.key));
    }

    handleLineChange(event) {
        const { key, field } = event.target.dataset;
        const value = event.target.value;
        this.lines = this.lines.map((line) => (line.key === key ? { ...line, [field]: value } : line));
    }

    handleAddLine() {
        this.lines = [...this.lines, toLine()];
    }

    handleRemoveLine(event) {
        const key = event.currentTarget.dataset.key;
        this.lines = this.lines.filter((line) => line.key !== key);
    }

    // ---- actions ---------------------------------------------------------

    handleSave() {
        this.save(false);
    }

    handleSaveAndPrint() {
        this.save(true);
    }

    handlePrint() {
        this.showPreview = true;
    }

    handleClosePreview() {
        this.showPreview = false;
    }

    save(thenPrint) {
        if (this.saveDisabled) {
            return;
        }
        this.isSaving = true;
        const input = {
            ...this.slip,
            vehicleId: this.isNewVehicle ? null : this.slip.vehicleId,
            newVehicle: this.isNewVehicle ? { ...this.newVehicle } : null,
            currentKm: toNumberOrNull(this.slip.currentKm),
            dateOfSale: this.slip.dateOfSale || null,
            accessories: ACCESSORIES.map((a) => a.key).filter((key) => this.accessories.has(key)),
            lines: this.lines.map((line) => ({
                id: line.id,
                customerRequest: line.customerRequest,
                observation: line.observation,
                labourEstimate: toNumberOrNull(line.labourEstimate),
                sparesEstimate: toNumberOrNull(line.sparesEstimate)
            }))
        };
        saveJobSlip({ input })
            .then((savedId) => {
                this.showToast(this.isSaved ? 'Job slip updated' : 'Job slip saved', '', 'success');
                this.jobSlipId = savedId;
                // Keeps the URL pointing at the saved slip (so a refresh
                // reopens it) without the page-reference wire reloading it.
                this.pageKey = savedId;
                this[NavigationMixin.Navigate](
                    {
                        type: 'standard__navItemPage',
                        attributes: { apiName: 'Job_Slip' },
                        state: { c__recordId: savedId }
                    },
                    true
                );
                return this.loadForm();
            })
            .then(() => {
                if (thenPrint && this.jobSlipId) {
                    this.showPreview = true;
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_Detail' },
            state: { c__customerId: this.customer ? this.customer.id : this.slip.customerId }
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
