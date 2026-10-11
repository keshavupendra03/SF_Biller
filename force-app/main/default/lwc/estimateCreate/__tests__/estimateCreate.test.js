import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import EstimateCreate from 'c/estimateCreate';
import searchCustomers from '@salesforce/apex/BillController.searchCustomers';
import createCustomer from '@salesforce/apex/BillController.createCustomer';
import createEstimate from '@salesforce/apex/EstimateController.createEstimate';
import createNewVersion from '@salesforce/apex/EstimateController.createNewVersion';
import getEstimateSummary from '@salesforce/apex/EstimateController.getEstimateSummary';
import listBillToParties from '@salesforce/apex/DirectoryController.listBillToParties';
import listVehiclesForCustomer from '@salesforce/apex/CustomerController.listVehiclesForCustomer';

jest.mock('@salesforce/apex/BillController.searchCustomers', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.createCustomer', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/EstimateController.createEstimate', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/EstimateController.createNewVersion', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/EstimateController.getEstimateSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DirectoryController.listBillToParties', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/CustomerController.listVehiclesForCustomer', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchParts', () => ({ default: jest.fn() }), { virtual: true });

const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    // eslint-disable-next-line global-require
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](pageRef) {
                mockNavigate(pageRef);
            }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: createTestWireAdapter(jest.fn()) };
});

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function selectCustomer(element) {
    const searchInput = element.shadowRoot.querySelector('[data-id="customer-search"]');
    searchInput.value = 'Ramesh';
    searchInput.dispatchEvent(new CustomEvent('change'));
    return flushPromises().then(() => {
        element.shadowRoot.querySelector('button[data-id="001xx0000000001"]').click();
        return flushPromises();
    });
}

function addLineViaModal(element, fields) {
    element.shadowRoot.querySelector('[data-id="add-line-item"]').click();
    return flushPromises().then(() => {
        const editor = element.shadowRoot.querySelector('c-line-item-editor');
        editor.dispatchEvent(new CustomEvent('save', { detail: { ...fields } }));
        return flushPromises();
    });
}

describe('c-estimate-create', () => {
    beforeEach(() => {
        listVehiclesForCustomer.mockResolvedValue([]);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('opening an existing estimate (c__recordId) locks the customer and loads its lines for editing', async () => {
        getEstimateSummary.mockResolvedValue({
            estimateId: 'a02xx0000000001',
            estimateNumber: 'EST-0005',
            status: 'Draft',
            totalAmount: 590,
            customerId: '001xx0000000001',
            customerName: 'Ramesh Kumar',
            notes: '',
            lineItems: [
                { partId: null, description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' }
            ]
        });

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: 'a02xx0000000001' } });
        await flushPromises();

        expect(getEstimateSummary).toHaveBeenCalledWith({ estimateId: 'a02xx0000000001' });
        expect(element.shadowRoot.textContent).toContain('Ramesh Kumar');
        expect(element.shadowRoot.textContent).toContain('Edit Estimate');
        expect(element.shadowRoot.querySelector('[data-id="customer-search"]')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Diagnostic Fee');
        expect(element.shadowRoot.querySelector('[data-id="submit-estimate"]').label).toBe('Save Changes');
    });

    it('opening an existing estimate that is for a party pre-populates that party on the edit screen', async () => {
        getEstimateSummary.mockResolvedValue({
            estimateId: 'a02xx0000000001',
            estimateNumber: 'EST-0005',
            customerId: '001xx0000000001',
            customerName: 'Ramesh Kumar',
            notes: '',
            billToPartyId: 'a05xx0000000001',
            billToPartyName: 'IFFCO TOKIO GENERAL INSURANCE',
            lineItems: [
                { partId: null, description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' }
            ]
        });

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: 'a02xx0000000001' } });
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('[data-id="bill-to-party-toggle"]');
        expect(toggle.checked).toBe(true);
        expect(element.shadowRoot.textContent).toContain('IFFCO TOKIO GENERAL INSURANCE');

        createNewVersion.mockResolvedValue({ estimateId: 'a02xx0000000002', estimateNumber: 'EST-0005', versionNumber: 2, totalAmount: 590 });
        element.shadowRoot.querySelector('[data-id="submit-estimate"]').click();
        await flushPromises();

        expect(createNewVersion.mock.calls[0][0].request.billToPartyId).toBe('a05xx0000000001');
    });

    it('renders with the submit button disabled until a customer and a line exist', () => {
        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);

        const button = element.shadowRoot.querySelector('[data-id="submit-estimate"]');
        expect(button.disabled).toBe(true);
    });

    it('enables submit once a customer is selected and a line is added via the popup', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);

        await selectCustomer(element);
        await addLineViaModal(element, { description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST' });

        const button = element.shadowRoot.querySelector('[data-id="submit-estimate"]');
        expect(button.disabled).toBe(false);
    });

    it('selecting a customer preselects their most recently created vehicle', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        listVehiclesForCustomer.mockResolvedValue([
            { id: 'a06xx0000000002', registrationNumber: 'MH12CD5678', make: 'Maruti', model: 'Swift', year: null, color: null },
            { id: 'a06xx0000000001', registrationNumber: 'MH12AB1234', make: 'Honda', model: 'City', year: null, color: null }
        ]);

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);
        await selectCustomer(element);

        expect(listVehiclesForCustomer).toHaveBeenCalledWith({ customerId: '001xx0000000001' });
        expect(element.shadowRoot.textContent).toContain('MH12CD5678');
    });

    it('a customer with no saved vehicles shows the empty state and lets the user add a new one', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        listVehiclesForCustomer.mockResolvedValue([]);

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);
        await selectCustomer(element);

        expect(element.shadowRoot.textContent).toContain('This customer has no vehicles yet.');

        const vehicleToggle = element.shadowRoot.querySelector('[data-id="new-vehicle-toggle"]');
        vehicleToggle.checked = true;
        vehicleToggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const regField = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'registrationNumber'
        );
        regField.value = 'MH14EF9999';
        regField.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        await addLineViaModal(element, { description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST' });

        createEstimate.mockResolvedValue({ estimateId: 'a02xx0000000009', estimateNumber: 'EST-0009', totalAmount: 590 });
        element.shadowRoot.querySelector('[data-id="submit-estimate"]').click();
        await flushPromises();

        const request = createEstimate.mock.calls[0][0].request;
        expect(request.vehicleId).toBeNull();
        expect(request.newVehicle).toEqual(
            expect.objectContaining({ registrationNumber: 'MH14EF9999' })
        );
    });

    it('submits a well-formed CreateEstimateRequest (including the preselected vehicle) and navigates to Estimate Details on success', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        listVehiclesForCustomer.mockResolvedValue([
            { id: 'a06xx0000000001', registrationNumber: 'MH12AB1234', make: 'Honda', model: 'City', year: null, color: null }
        ]);
        createEstimate.mockResolvedValue({
            estimateId: 'a02xx0000000001',
            estimateNumber: 'EST-0001',
            versionNumber: 1,
            totalAmount: 590
        });

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);

        await selectCustomer(element);
        await addLineViaModal(element, { description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST' });

        element.shadowRoot.querySelector('[data-id="submit-estimate"]').click();
        await flushPromises();

        expect(createEstimate).toHaveBeenCalledTimes(1);
        const request = createEstimate.mock.calls[0][0].request;
        expect(request.customerId).toBe('001xx0000000001');
        expect(request.vehicleId).toBe('a06xx0000000001');
        expect(request.lineItems).toHaveLength(1);
        expect(request.lineItems[0].description).toBe('Diagnostic Fee');

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Estimate_Detail' },
            state: { c__recordId: 'a02xx0000000001' }
        });
    });

    it('does not call Apex search for a term under 2 characters', () => {
        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);

        const searchInput = element.shadowRoot.querySelector('[data-id="customer-search"]');
        searchInput.value = 'R';
        searchInput.dispatchEvent(new CustomEvent('change'));

        expect(searchCustomers).not.toHaveBeenCalled();
    });

    it('the trash icon removes a line', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);
        await selectCustomer(element);
        await addLineViaModal(element, { description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST' });

        element.shadowRoot.querySelector('[data-id="remove-line"]').click();
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('Diagnostic Fee');
        expect(element.shadowRoot.querySelector('[data-id="submit-estimate"]').disabled).toBe(true);
    });

    it('editing an estimate opened from a customer carries that customer id through to the saved Estimate Detail', async () => {
        getEstimateSummary.mockResolvedValue({
            estimateId: 'a02xx0000000001',
            estimateNumber: 'EST-0005',
            customerId: '001xx0000000001',
            customerName: 'Ramesh Kumar',
            notes: '',
            lineItems: [
                { partId: null, description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' }
            ]
        });
        createNewVersion.mockResolvedValue({
            estimateId: 'a02xx0000000002',
            estimateNumber: 'EST-0006',
            totalAmount: 590
        });

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            type: 'standard__navItemPage',
            attributes: {},
            state: { c__recordId: 'a02xx0000000001', c__fromCustomerId: 'cust1' }
        });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Estimate_Detail' },
            state: { c__recordId: 'a02xx0000000001', c__fromCustomerId: 'cust1' }
        });

        element.shadowRoot.querySelector('[data-id="submit-estimate"]').click();
        await flushPromises();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Estimate_Detail' },
            state: { c__recordId: 'a02xx0000000002', c__fromCustomerId: 'cust1' }
        });
    });

    it('editing an existing estimate calls createNewVersion, not createEstimate', async () => {
        getEstimateSummary.mockResolvedValue({
            estimateId: 'a02xx0000000001',
            estimateNumber: 'EST-0001',
            customerId: '001xx0000000001',
            customerName: 'Ramesh Kumar',
            notes: '',
            lineItems: [
                { partId: null, description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' }
            ]
        });
        createNewVersion.mockResolvedValue({
            estimateId: 'a02xx0000000002',
            estimateNumber: 'EST-0002',
            versionNumber: 2,
            totalAmount: 700
        });

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: 'a02xx0000000001' } });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="submit-estimate"]').click();
        await flushPromises();

        expect(createNewVersion).toHaveBeenCalledWith(
            expect.objectContaining({ previousEstimateId: 'a02xx0000000001' })
        );
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Estimate_Detail' },
            state: { c__recordId: 'a02xx0000000002' }
        });
    });

    it('creating a new customer inline selects it without requiring a search', async () => {
        createCustomer.mockResolvedValue({ id: '001xx0000000009', name: 'Brand New Co', phone: '9000000009' });

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);

        const toggle = element.shadowRoot.querySelector('[data-id="new-customer-toggle"]');
        toggle.checked = true;
        toggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const nameInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'name'
        );
        nameInput.value = 'Brand New Co';
        nameInput.dispatchEvent(new CustomEvent('change'));
        const phoneInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'phone'
        );
        phoneInput.value = '9000000009';
        phoneInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save-new-customer"]').click();
        await flushPromises();

        expect(createCustomer).toHaveBeenCalledTimes(1);
        expect(element.shadowRoot.querySelector('[data-id="customer-search"]')).toBeNull();
    });

    it('lets the user search for and select an existing bill-to party instead of creating a new one', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        createEstimate.mockResolvedValue({
            estimateId: 'a02xx0000000001',
            estimateNumber: 'EST-0001',
            versionNumber: 1,
            totalAmount: 590
        });
        listBillToParties.mockResolvedValue([
            { id: 'a05xx0000000001', name: 'Acme Logistics Pvt Ltd', gstin: 'AAAAA0000A1Z5' }
        ]);

        const element = createElement('c-estimate-create', { is: EstimateCreate });
        document.body.appendChild(element);

        await selectCustomer(element);
        await addLineViaModal(element, { description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST' });

        const toggle = element.shadowRoot.querySelector('[data-id="bill-to-party-toggle"]');
        toggle.checked = true;
        toggle.dispatchEvent(new CustomEvent('change', { detail: {} }));
        await flushPromises();

        const search = element.shadowRoot.querySelector('[data-id="bill-to-party-search"]');
        search.value = 'Acme';
        search.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(listBillToParties).toHaveBeenCalledWith({ searchTerm: 'Acme' });
        element.shadowRoot.querySelector('button[data-id="a05xx0000000001"]').click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Acme Logistics Pvt Ltd');
        expect(element.shadowRoot.querySelector('[data-id="bill-to-party-search"]')).toBeNull();

        element.shadowRoot.querySelector('[data-id="submit-estimate"]').click();
        await flushPromises();

        const request = createEstimate.mock.calls[0][0].request;
        expect(request.billToPartyId).toBe('a05xx0000000001');
        expect(request.newBillToParty).toBeNull();
    });
});
