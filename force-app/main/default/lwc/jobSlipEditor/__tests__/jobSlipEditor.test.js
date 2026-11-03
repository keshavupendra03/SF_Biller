import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import JobSlipEditor from 'c/jobSlipEditor';
import getJobSlipForm from '@salesforce/apex/JobSlipController.getJobSlipForm';
import saveJobSlip from '@salesforce/apex/JobSlipController.saveJobSlip';

jest.mock('@salesforce/apex/JobSlipController.getJobSlipForm', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobSlipController.saveJobSlip', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchMakes', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchModels', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });

const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    // eslint-disable-next-line global-require
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](pageRef, replace) {
                mockNavigate(pageRef, replace);
            }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: createTestWireAdapter(jest.fn()) };
});

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const VEHICLES = [
    {
        id: 'veh1', registrationNumber: 'MP70ZD3946', make: 'Tata', model: 'Punch', chassisNumber: 'MAT867015SPJB9663',
        engineNumber: 'ENG1', dateOfSale: '2025-10-22', lastBatteryMake: 'Amaron', lastBatteryNumber: 'AM1', lastTyreMake: 'CEAT'
    },
    { id: 'veh2', registrationNumber: 'MP09AB1234', make: 'Maruti', model: 'Swift', chassisNumber: 'CH2', engineNumber: null, dateOfSale: null }
];

const CUSTOMER = { id: 'cust1', name: 'Deepak Sharma', phone: '9425012345', email: 'deepak@example.com', address: 'Vijay Nagar, Indore' };

function newForm(overrides) {
    return {
        customer: CUSTOMER,
        vehicles: VEHICLES,
        slip: {
            id: null, slipNumber: null, customerId: 'cust1', vehicleId: 'veh1', slipDate: '2026-11-01', timeIn: '10:16',
            chassisNumber: 'MAT867015SPJB9663', engineNumber: 'ENG1', dateOfSale: '2025-10-22',
            serviceAdvisorName: 'Rahul', accessories: [], lines: [], ...overrides
        }
    };
}

const SAVED_FORM = {
    customer: CUSTOMER,
    vehicles: VEHICLES,
    slip: {
        id: 'slip1', slipNumber: 'JS-0007', customerId: 'cust1', vehicleId: 'veh1', slipDate: '2026-10-30', timeIn: '10:16',
        fuelLevel: '1/2', accessories: ['mats', 'toolKit'],
        lines: [{ id: 'line1', customerRequest: 'Bumper damaged', observation: 'Replace', labourEstimate: 1500, sparesEstimate: 6500 }]
    }
};

function createEditor(state) {
    const element = createElement('c-job-slip-editor', { is: JobSlipEditor });
    document.body.appendChild(element);
    CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state });
    return element;
}

function setValue(element, selector, value) {
    const input = element.shadowRoot.querySelector(selector);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-job-slip-editor', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('opens a new slip for the customer passed in, with their details and one empty complaint row', async () => {
        getJobSlipForm.mockResolvedValue(newForm());
        const element = createEditor({ c__customerId: 'cust1', c__vehicleId: 'veh1' });
        await flushPromises();

        expect(getJobSlipForm).toHaveBeenCalledWith({ jobSlipId: null, customerId: 'cust1', vehicleId: 'veh1' });
        expect(element.shadowRoot.textContent).toContain('New slip');
        expect(element.shadowRoot.textContent).toContain('9425012345');
        expect(element.shadowRoot.querySelector('[data-id="vehicle"]').value).toBe('veh1');
        expect(element.shadowRoot.querySelectorAll('[data-id="repair-line"]')).toHaveLength(1);
        // Print needs a saved slip; a new one only offers Save & Print.
        expect(element.shadowRoot.querySelector('[data-id="print"]')).toBeNull();
    });

    it('Save sends the slip with accessories in paper order and number-typed estimates', async () => {
        getJobSlipForm.mockResolvedValueOnce(newForm()).mockResolvedValueOnce(SAVED_FORM);
        saveJobSlip.mockResolvedValue('slip1');
        const element = createEditor({ c__customerId: 'cust1' });
        await flushPromises();

        setValue(element, '[data-field="visitReason"]', 'Accident');
        setValue(element, '[data-field="currentKm"]', '17773');
        element.shadowRoot.querySelector('[data-id="fuel"]').dispatchEvent(new CustomEvent('change', { detail: { value: '1/2' } }));
        for (const key of ['mats', 'spareWheel']) {
            const box = element.shadowRoot.querySelector(`lightning-input[data-key="${key}"]`);
            box.checked = true;
            box.dispatchEvent(new CustomEvent('change'));
        }
        setValue(element, '[data-field="customerRequest"]', 'Front bumper damaged');
        setValue(element, '[data-field="labourEstimate"]', '1500');
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        const { input } = saveJobSlip.mock.calls[0][0];
        expect(input).toEqual(expect.objectContaining({
            customerId: 'cust1',
            vehicleId: 'veh1',
            newVehicle: null,
            visitReason: 'Accident',
            currentKm: 17773,
            fuelLevel: '1/2',
            accessories: ['spareWheel', 'mats']
        }));
        expect(input.lines).toEqual([
            { id: null, customerRequest: 'Front bumper damaged', observation: '', labourEstimate: 1500, sparesEstimate: null }
        ]);
        // The URL is pointed at the saved slip (replace: true) and the form reloads from the server.
        expect(mockNavigate).toHaveBeenCalledWith(
            { type: 'standard__navItemPage', attributes: { apiName: 'Job_Slip' }, state: { c__recordId: 'slip1' } },
            true
        );
        expect(getJobSlipForm).toHaveBeenLastCalledWith({ jobSlipId: 'slip1', customerId: null, vehicleId: null });
        expect(element.shadowRoot.textContent).toContain('JS-0007');
        expect(element.shadowRoot.querySelector('c-document-preview')).toBeNull();
    });

    it('has no Type of Service section', async () => {
        getJobSlipForm.mockResolvedValue(newForm());
        const element = createEditor({ c__customerId: 'cust1' });
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('Type of Service');
        expect(element.shadowRoot.querySelector('[data-id="service-type"]')).toBeNull();
    });

    it('Mark all present ticks every accessory, then Clear all unticks them', async () => {
        getJobSlipForm.mockResolvedValue(newForm());
        const element = createEditor({ c__customerId: 'cust1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-all"]').click();
        await flushPromises();
        const boxes = element.shadowRoot.querySelectorAll('.accessory-grid lightning-input');
        expect(boxes).toHaveLength(13);
        expect([...boxes].every((b) => b.checked)).toBe(true);
        expect(element.shadowRoot.textContent).toContain('13/13');

        element.shadowRoot.querySelector('[data-id="toggle-all"]').click();
        await flushPromises();
        expect([...element.shadowRoot.querySelectorAll('.accessory-grid lightning-input')].some((b) => b.checked)).toBe(false);
    });

    it('switching vehicle fills its chassis/engine numbers and last battery/tyre make', async () => {
        getJobSlipForm.mockResolvedValue(newForm({ vehicleId: 'veh2', chassisNumber: 'CH2', engineNumber: null }));
        const element = createEditor({ c__customerId: 'cust1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="vehicle"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'veh1' } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-field="chassisNumber"]').value).toBe('MAT867015SPJB9663');
        expect(element.shadowRoot.querySelector('[data-field="engineNumber"]').value).toBe('ENG1');
        expect(element.shadowRoot.querySelector('[data-field="batteryMake"]').value).toBe('Amaron');
        expect(element.shadowRoot.querySelector('[data-field="tyreMake"]').value).toBe('CEAT');
    });

    it('"+ Add new vehicle" asks for a registration number and saves it as newVehicle', async () => {
        getJobSlipForm.mockResolvedValueOnce(newForm()).mockResolvedValueOnce(SAVED_FORM);
        saveJobSlip.mockResolvedValue('slip1');
        const element = createEditor({ c__customerId: 'cust1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="vehicle"]').dispatchEvent(new CustomEvent('change', { detail: { value: '__new' } }));
        await flushPromises();
        expect(element.shadowRoot.querySelector('[data-id="save"]').disabled).toBe(true);

        setValue(element, 'lightning-input[data-field="registrationNumber"]', 'MP09ZZ0001');
        await flushPromises();
        expect(element.shadowRoot.querySelector('[data-id="save"]').disabled).toBe(false);

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        const { input } = saveJobSlip.mock.calls[0][0];
        expect(input.vehicleId).toBeNull();
        expect(input.newVehicle).toEqual({ registrationNumber: 'MP09ZZ0001', make: '', model: '' });
        expect(input.chassisNumber).toBe('');
    });

    it('a customer with no vehicles starts straight on the new-vehicle fields', async () => {
        getJobSlipForm.mockResolvedValue({ ...newForm({ vehicleId: null }), vehicles: [] });
        const element = createEditor({ c__customerId: 'cust1' });
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="vehicle"]')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-input[data-field="registrationNumber"]')).not.toBeNull();
        expect(element.shadowRoot.textContent).toContain('Select the vehicle (or add one) to save this slip.');
    });

    it('opens a saved slip with its lines, estimate totals and a Print button', async () => {
        getJobSlipForm.mockResolvedValue(SAVED_FORM);
        const element = createEditor({ c__recordId: 'slip1', c__fromCustomerId: 'cust1' });
        await flushPromises();

        expect(getJobSlipForm).toHaveBeenCalledWith({ jobSlipId: 'slip1', customerId: null, vehicleId: null });
        expect(element.shadowRoot.textContent).toContain('JS-0007');
        expect(element.shadowRoot.querySelector('[data-field="customerRequest"]').value).toBe('Bumper damaged');
        expect(element.shadowRoot.querySelector('lightning-input[data-key="mats"]').checked).toBe(true);
        expect(element.shadowRoot.textContent).toContain('Estimated total');

        element.shadowRoot.querySelector('[data-id="print"]').click();
        await flushPromises();

        const preview = element.shadowRoot.querySelector('c-document-preview');
        expect(preview.recordId).toBe('slip1');
        expect(preview.pageName).toBe('JobSlipPdf');
    });

    it('Save & Print saves first, then opens the preview for the saved slip', async () => {
        getJobSlipForm.mockResolvedValue(SAVED_FORM);
        saveJobSlip.mockResolvedValue('slip1');
        const element = createEditor({ c__recordId: 'slip1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="save-print"]').click();
        await flushPromises();
        await flushPromises();

        expect(saveJobSlip).toHaveBeenCalledTimes(1);
        expect(saveJobSlip.mock.calls[0][0].input.lines[0].id).toBe('line1');
        expect(element.shadowRoot.querySelector('c-document-preview').recordId).toBe('slip1');
    });

    it('removing a complaint row drops it from the save', async () => {
        getJobSlipForm.mockResolvedValue({
            ...SAVED_FORM,
            slip: { ...SAVED_FORM.slip, lines: [...SAVED_FORM.slip.lines, { id: 'line2', customerRequest: 'Horn', observation: '' }] }
        });
        saveJobSlip.mockResolvedValue('slip1');
        const element = createEditor({ c__recordId: 'slip1' });
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('[data-id="repair-line"]')).toHaveLength(2);

        element.shadowRoot.querySelectorAll('[data-id="remove-line"]')[0].click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(saveJobSlip.mock.calls[0][0].input.lines.map((l) => l.id)).toEqual(['line2']);
    });

    it('Back returns to the slip’s customer', async () => {
        getJobSlipForm.mockResolvedValue(SAVED_FORM);
        const element = createEditor({ c__recordId: 'slip1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();

        expect(mockNavigate).toHaveBeenCalledWith(
            { type: 'standard__navItemPage', attributes: { apiName: 'Customer_Detail' }, state: { c__customerId: 'cust1' } },
            undefined
        );
    });
});
