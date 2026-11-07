import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import BillCreate from 'c/billCreate';
import searchCustomers from '@salesforce/apex/BillController.searchCustomers';
import createBill from '@salesforce/apex/BillController.createBill';
import createNewVersion from '@salesforce/apex/BillController.createNewVersion';
import createCustomer from '@salesforce/apex/BillController.createCustomer';
import getBillSummary from '@salesforce/apex/BillController.getBillSummary';
import listBillToParties from '@salesforce/apex/DirectoryController.listBillToParties';
import listVehiclesForCustomer from '@salesforce/apex/CustomerController.listVehiclesForCustomer';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchCustomers', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.createBill', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.createNewVersion', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.createCustomer', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.getBillSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DirectoryController.listBillToParties', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/CustomerController.listVehiclesForCustomer', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/EstimateController.getEstimateSummary', () => ({ default: jest.fn() }), { virtual: true });
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

// Opens the "+ Add Line Item" popup and saves a manual line with the given fields.
function addLineViaModal(element, fields) {
    element.shadowRoot.querySelector('[data-id="add-line-item"]').click();
    return flushPromises().then(() => {
        const editor = element.shadowRoot.querySelector('c-line-item-editor');
        editor.dispatchEvent(new CustomEvent('save', { detail: { ...fields } }));
        return flushPromises();
    });
}

describe('c-bill-create', () => {
    beforeEach(() => {
        listVehiclesForCustomer.mockResolvedValue([]);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders with no customer selected and the submit button disabled', () => {
        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);

        const button = element.shadowRoot.querySelector('[data-id="submit-bill"]');
        expect(button.disabled).toBe(true);
    });

    it('opening an existing bill (c__recordId) locks the customer and loads its lines for editing', async () => {
        getBillSummary.mockResolvedValue({
            billId: 'a01xx0000000001',
            invoiceNumber: 'INV/2026-27/0005',
            status: 'Paid',
            totalAmount: 1180,
            customerId: '001xx0000000001',
            customerName: 'Ramesh Kumar',
            notes: '',
            lineItems: [
                { partId: null, description: 'Labour', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' }
            ]
        });

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: 'a01xx0000000001' } });
        await flushPromises();

        expect(getBillSummary).toHaveBeenCalledWith({ billId: 'a01xx0000000001' });
        expect(element.shadowRoot.textContent).toContain('Ramesh Kumar');
        expect(element.shadowRoot.textContent).toContain('Edit Bill');
        // Customer is locked (no search) once editing an existing bill.
        expect(element.shadowRoot.querySelector('[data-id="customer-search"]')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Labour');
        expect(element.shadowRoot.querySelector('[data-id="submit-bill"]').label).toBe('Save Changes');
    });

    it('opening an existing bill that is billed to a party pre-populates that party on the edit screen', async () => {
        getBillSummary.mockResolvedValue({
            billId: 'a01xx0000000001',
            invoiceNumber: 'INV/2026-27/0025',
            customerId: '001xx0000000001',
            customerName: 'Ramesh Kumar',
            notes: '',
            billToPartyId: 'a05xx0000000001',
            billToPartyName: 'IFFCO TOKIO GENERAL INSURANCE',
            lineItems: [
                { partId: null, description: 'Labour', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' }
            ]
        });

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: 'a01xx0000000001' } });
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('[data-id="bill-to-party-toggle"]');
        expect(toggle.checked).toBe(true);
        expect(element.shadowRoot.textContent).toContain('IFFCO TOKIO GENERAL INSURANCE');

        // Saving without touching the toggle must still carry the party forward.
        createNewVersion.mockResolvedValue({ billId: 'a01xx0000000002', invoiceNumber: 'INV/2026-27/0025', status: 'Unpaid', totalAmount: 590 });
        element.shadowRoot.querySelector('[data-id="submit-bill"]').click();
        await flushPromises();

        expect(createNewVersion.mock.calls[0][0].request.billToPartyId).toBe('a05xx0000000001');
    });

    it('searches customers as the user types and lets them pick one', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);

        const searchInput = element.shadowRoot.querySelector('[data-id="customer-search"]');
        searchInput.value = 'Ramesh';
        searchInput.dispatchEvent(new CustomEvent('change'));

        await flushPromises();

        expect(searchCustomers).toHaveBeenCalledWith({ searchTerm: 'Ramesh' });

        const resultButton = element.shadowRoot.querySelector('button[data-id="001xx0000000001"]');
        expect(resultButton).not.toBeNull();

        resultButton.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="customer-search"]')).toBeNull();
        const button = element.shadowRoot.querySelector('[data-id="submit-bill"]');
        expect(button.disabled).toBe(true);
    });

    it('does not call searchCustomers for a search term under 2 characters', () => {
        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);

        const searchInput = element.shadowRoot.querySelector('[data-id="customer-search"]');
        searchInput.value = 'R';
        searchInput.dispatchEvent(new CustomEvent('change'));

        expect(searchCustomers).not.toHaveBeenCalled();
    });

    it('selecting a customer preselects their most recently created vehicle', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        listVehiclesForCustomer.mockResolvedValue([
            { id: 'a06xx0000000002', registrationNumber: 'MH12CD5678', make: 'Maruti', model: 'Swift', year: null, color: null },
            { id: 'a06xx0000000001', registrationNumber: 'MH12AB1234', make: 'Honda', model: 'City', year: null, color: null }
        ]);

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        await selectCustomer(element);

        expect(listVehiclesForCustomer).toHaveBeenCalledWith({ customerId: '001xx0000000001' });
        // listVehiclesForCustomer returns newest-first — results[0] (the Swift) is the preselection.
        expect(element.shadowRoot.textContent).toContain('MH12CD5678');
        expect(element.shadowRoot.textContent).not.toContain('This customer has no vehicles yet.');
    });

    it('lets the user change to a different one of the customer\'s saved vehicles', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        listVehiclesForCustomer.mockResolvedValue([
            { id: 'a06xx0000000002', registrationNumber: 'MH12CD5678', make: 'Maruti', model: 'Swift', year: null, color: null },
            { id: 'a06xx0000000001', registrationNumber: 'MH12AB1234', make: 'Honda', model: 'City', year: null, color: null }
        ]);

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        await selectCustomer(element);

        element.shadowRoot.querySelector('[data-id="change-vehicle"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('button[data-id="a06xx0000000001"]').click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('MH12AB1234');
    });

    it('a customer with no saved vehicles shows the empty state and lets the user add a new one', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        listVehiclesForCustomer.mockResolvedValue([]);

        const element = createElement('c-bill-create', { is: BillCreate });
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

        await addLineViaModal(element, { description: 'Service', quantity: 1, unitPrice: 500, taxRatePercent: 0, gstType: 'CGST_SGST' });

        createBill.mockResolvedValue({ billId: 'a01xx0000000009', invoiceNumber: 'INV/2026-27/0009', status: 'Unpaid', totalAmount: 500 });
        element.shadowRoot.querySelector('[data-id="submit-bill"]').click();
        await flushPromises();

        const request = createBill.mock.calls[0][0].request;
        expect(request.vehicleId).toBeNull();
        expect(request.newVehicle).toEqual(
            expect.objectContaining({ registrationNumber: 'MH14EF9999' })
        );
    });

    it('"+ Add Line Item" opens the line editor popup, and saving it adds a compact row', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        await selectCustomer(element);

        expect(element.shadowRoot.querySelector('c-line-item-editor')).toBeNull();
        await addLineViaModal(element, { description: 'Labour', quantity: 1, unitPrice: 300, taxRatePercent: 0, gstType: 'CGST_SGST' });

        expect(element.shadowRoot.querySelector('c-line-item-editor')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Labour');
        expect(element.shadowRoot.querySelector('[data-id="submit-bill"]').disabled).toBe(false);
    });

    it('tapping an existing line row reopens the editor pre-filled, and saving it updates that line', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        await selectCustomer(element);
        await addLineViaModal(element, { description: 'Labour', quantity: 1, unitPrice: 300, taxRatePercent: 0, gstType: 'CGST_SGST' });

        element.shadowRoot.querySelector('.line-row-button').click();
        await flushPromises();

        const editor = element.shadowRoot.querySelector('c-line-item-editor');
        expect(editor.record.description).toBe('Labour');

        editor.dispatchEvent(new CustomEvent('save', { detail: { ...editor.record, description: 'Labour (revised)', unitPrice: 350 } }));
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Labour (revised)');
        expect(element.shadowRoot.textContent).not.toContain('₹300');
    });

    it('Cancel on the line editor discards the change without adding a line', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        await selectCustomer(element);

        element.shadowRoot.querySelector('[data-id="add-line-item"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('c-line-item-editor').dispatchEvent(new CustomEvent('cancel'));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-line-item-editor')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="submit-bill"]').disabled).toBe(true);
    });

    it('the trash icon removes a line', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        await selectCustomer(element);
        await addLineViaModal(element, { description: 'Labour', quantity: 1, unitPrice: 300, taxRatePercent: 0, gstType: 'CGST_SGST' });

        element.shadowRoot.querySelector('[data-id="remove-line"]').click();
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('Labour');
        expect(element.shadowRoot.querySelector('[data-id="submit-bill"]').disabled).toBe(true);
    });

    it('submits a well-formed CreateBillRequest (including the preselected vehicle) and navigates to Bill Details on success', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        listVehiclesForCustomer.mockResolvedValue([
            { id: 'a06xx0000000001', registrationNumber: 'MH12AB1234', make: 'Honda', model: 'City', year: null, color: null }
        ]);
        createBill.mockResolvedValue({
            billId: 'a01xx0000000001',
            invoiceNumber: 'INV/2026-27/0001',
            status: 'Unpaid',
            totalAmount: 1000
        });

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        await selectCustomer(element);
        await addLineViaModal(element, { description: 'Labour', quantity: 2, unitPrice: 500, taxRatePercent: 0, gstType: 'CGST_SGST' });

        element.shadowRoot.querySelector('[data-id="submit-bill"]').click();
        await flushPromises();

        expect(createBill).toHaveBeenCalledTimes(1);
        const request = createBill.mock.calls[0][0].request;
        expect(request.customerId).toBe('001xx0000000001');
        expect(request.vehicleId).toBe('a06xx0000000001');
        expect(request.lineItems).toHaveLength(1);
        expect(request.lineItems[0].quantity).toBe(2);
        expect(request.lineItems[0].unitPrice).toBe(500);

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: 'a01xx0000000001' }
        });
    });

    it('editing a bill opened from a customer carries that customer id through to the saved Bill Detail', async () => {
        getBillSummary.mockResolvedValue({
            billId: 'a01xx0000000001',
            invoiceNumber: 'INV/2026-27/0005',
            customerId: '001xx0000000001',
            customerName: 'Ramesh Kumar',
            notes: '',
            lineItems: [
                { partId: null, description: 'Labour', quantity: 1, unitPrice: 500, taxRatePercent: 0, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' }
            ]
        });
        createNewVersion.mockResolvedValue({
            billId: 'a01xx0000000002',
            invoiceNumber: 'INV/2026-27/0005',
            status: 'Unpaid',
            totalAmount: 500
        });

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        CurrentPageReference.emit({
            type: 'standard__navItemPage',
            attributes: {},
            state: { c__recordId: 'a01xx0000000001', c__fromCustomerId: 'cust1' }
        });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: 'a01xx0000000001', c__fromCustomerId: 'cust1' }
        });

        element.shadowRoot.querySelector('[data-id="submit-bill"]').click();
        await flushPromises();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: 'a01xx0000000002', c__fromCustomerId: 'cust1' }
        });
    });

    it('editing an existing bill calls createNewVersion, not createBill', async () => {
        getBillSummary.mockResolvedValue({
            billId: 'a01xx0000000001',
            invoiceNumber: 'INV/2026-27/0005',
            customerId: '001xx0000000001',
            customerName: 'Ramesh Kumar',
            notes: '',
            lineItems: [
                { partId: null, description: 'Labour', quantity: 1, unitPrice: 500, taxRatePercent: 0, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' }
            ]
        });
        createNewVersion.mockResolvedValue({
            billId: 'a01xx0000000002',
            invoiceNumber: 'INV/2026-27/0005',
            status: 'Unpaid',
            totalAmount: 500
        });

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: 'a01xx0000000001' } });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="submit-bill"]').click();
        await flushPromises();

        expect(createNewVersion).toHaveBeenCalledWith(
            expect.objectContaining({ previousBillId: 'a01xx0000000001' })
        );
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: 'a01xx0000000002' }
        });
    });

    it('includes a new Bill-To-Party in the request when the toggle is on and a name is entered', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        createBill.mockResolvedValue({
            billId: 'a01xx0000000001',
            invoiceNumber: 'INV/2026-27/0001',
            status: 'Unpaid',
            totalAmount: 1000
        });

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        await selectCustomer(element);
        await addLineViaModal(element, { description: 'Labour', quantity: 1, unitPrice: 1000, taxRatePercent: 0, gstType: 'CGST_SGST' });

        const toggle = element.shadowRoot.querySelector('[data-id="bill-to-party-toggle"]');
        toggle.checked = true;
        toggle.dispatchEvent(new CustomEvent('change', { detail: {} }));
        await flushPromises();

        const newPartyToggle = element.shadowRoot.querySelector('[data-id="new-bill-to-party-toggle"]');
        newPartyToggle.checked = true;
        newPartyToggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const nameInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'name'
        );
        nameInput.value = 'Acme Logistics Pvt Ltd';
        nameInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="submit-bill"]').click();
        await flushPromises();

        const request = createBill.mock.calls[0][0].request;
        expect(request.newBillToParty.name).toBe('Acme Logistics Pvt Ltd');
        expect(request.billToPartyId).toBeNull();
    });

    it('lets the user search for and select an existing bill-to party instead of creating a new one', async () => {
        searchCustomers.mockResolvedValue([{ id: '001xx0000000001', name: 'Ramesh Kumar', phone: '9000011111' }]);
        createBill.mockResolvedValue({
            billId: 'a01xx0000000001',
            invoiceNumber: 'INV/2026-27/0001',
            status: 'Unpaid',
            totalAmount: 1000
        });
        listBillToParties.mockResolvedValue([
            { id: 'a05xx0000000001', name: 'Acme Logistics Pvt Ltd', gstin: 'AAAAA0000A1Z5' }
        ]);

        const element = createElement('c-bill-create', { is: BillCreate });
        document.body.appendChild(element);
        await selectCustomer(element);
        await addLineViaModal(element, { description: 'Labour', quantity: 1, unitPrice: 1000, taxRatePercent: 0, gstType: 'CGST_SGST' });

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

        element.shadowRoot.querySelector('[data-id="submit-bill"]').click();
        await flushPromises();

        const request = createBill.mock.calls[0][0].request;
        expect(request.billToPartyId).toBe('a05xx0000000001');
        expect(request.newBillToParty).toBeNull();
    });

    it('creating a new customer inline selects it and enables line-item entry', async () => {
        createCustomer.mockResolvedValue({ id: '001xx0000000009', name: 'Brand New Co', phone: '9000000009' });

        const element = createElement('c-bill-create', { is: BillCreate });
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

        expect(createCustomer).toHaveBeenCalledWith({
            input: { name: 'Brand New Co', phone: '9000000009', address: '', email: '', gstin: '', state: '' }
        });
        expect(element.shadowRoot.querySelector('[data-id="customer-search"]')).toBeNull();

        await addLineViaModal(element, { description: 'Labour', quantity: 1, unitPrice: 300, taxRatePercent: 0, gstType: 'CGST_SGST' });

        expect(element.shadowRoot.querySelector('[data-id="submit-bill"]').disabled).toBe(false);
    });
});
