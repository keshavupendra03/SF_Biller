import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import PaperBill from 'c/paperBill';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';
import searchCustomers from '@salesforce/apex/BillController.searchCustomers';
import findCustomerByPhone from '@salesforce/apex/QuickBillController.findCustomerByPhone';
import getCustomer from '@salesforce/apex/PaperBillController.getCustomer';
import amountInWords from '@salesforce/apex/PaperBillController.amountInWords';
import saveDocument from '@salesforce/apex/PaperBillController.saveDocument';
import searchParts from '@salesforce/apex/BillController.searchParts';
import getVehicleCard from '@salesforce/apex/ServiceBookController.getVehicleCard';
import listBillToParties from '@salesforce/apex/DirectoryController.listBillToParties';
import getDocument from '@salesforce/apex/PaperBillController.getDocument';
import cancelBill from '@salesforce/apex/BillController.cancelBill';
import deleteEstimate from '@salesforce/apex/EstimateController.deleteEstimate';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchCustomers', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchParts', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.findCustomerByPhone', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchMakes', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchModels', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/PaperBillController.getCustomer', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PaperBillController.amountInWords', () => ({ default: jest.fn(() => Promise.resolve('')) }), { virtual: true });
jest.mock('@salesforce/apex/PaperBillController.saveDocument', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ServiceBookController.getVehicleCard', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DirectoryController.listBillToParties', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PaperBillController.getDocument', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.cancelBill', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/EstimateController.deleteEstimate', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/client/formFactor', () => ({ default: 'Large' }), { virtual: true });
jest.mock(
    'lightning/mobileCapabilities',
    () => ({ getBarcodeScanner: jest.fn(() => ({ isAvailable: () => false })) }),
    { virtual: true }
);

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

const PROFILE = {
    id: 'wp1', name: 'Keshav Motors', address: 'Dewas Road, Ujjain', phone: '9039472001', email: '', gstin: '23AAACI7904G1ZV', state: 'MP',
    bankName: 'Bank of Baroda', bankAccountNo: '123', bankIfsc: '', bankAccountHolder: '', termsAndConditions: 'Goods once sold are not returned.'
};
const RAMESH = {
    id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111', address: 'Vijay Nagar', gstin: '', state: 'MP',
    vehicles: [{ id: 'veh1', registrationNumber: 'MP09AB1234', make: 'Tata', model: 'Punch', chassisNumber: 'CH1' }]
};
const SAVED = { recordId: 'bill1', documentNumber: 'INV/2026-27/0042', customerName: 'Walk-in Customer', totalAmount: 1000 };

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function createScreen() {
    const element = createElement('c-paper-bill', { is: PaperBill });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

function $(element, selector) {
    return element.shadowRoot.querySelector(selector);
}

function grid(element) {
    return $(element, 'c-line-item-grid').shadowRoot;
}

function field(element, selector) {
    return $(element, `c-paper-field${selector}`);
}

async function typeField(element, selector, value) {
    const target = field(element, selector);
    const box = target.shadowRoot.querySelector('input, textarea');
    box.value = value;
    box.dispatchEvent(new CustomEvent('input', { bubbles: true }));
    await flushPromises();
}

function press(target, key, options) {
    target.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, composed: true, cancelable: true, ...options }));
}

function cell(element, rowIndex, name) {
    return grid(element).querySelectorAll('[data-id="item-row"]')[rowIndex].querySelector(`input[data-field="${name}"]`);
}

async function typeCell(element, rowIndex, name, value) {
    const input = cell(element, rowIndex, name);
    input.value = value;
    input.dispatchEvent(new CustomEvent('input', { bubbles: true }));
    await flushPromises();
}

async function addItem(element, rowIndex, name, price) {
    await typeCell(element, rowIndex, 'description', name);
    await typeCell(element, rowIndex, 'unitPrice', price);
}

describe('c-paper-bill', () => {
    beforeEach(() => {
        listProfiles.mockResolvedValue([PROFILE]);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('opens looking like the printed bill, with the workshop at the top and the cursor on the customer name', async () => {
        const element = await createScreen();

        expect($(element, '[data-id="workshop-name"]').textContent).toBe('Keshav Motors');
        expect($(element, '[data-id="sheet"]').textContent).toContain('Phone no.: 9039472001');
        expect($(element, '[data-id="sheet"]').textContent).toContain('Bank Name: Bank of Baroda');
        expect($(element, '[data-id="terms"]').textContent).toContain('Goods once sold');
        expect($(element, '[data-id="title"]').textContent).toBe('Bill');
        expect($(element, '[data-id="sheet"]').textContent).toContain('Bill To');
        expect($(element, '[data-id="sheet"]').textContent).toContain('Authorized Signatory');
        expect($(element, '[data-id="auto-number"]').textContent).toBe('Given when you save');
        expect(element.shadowRoot.activeElement).toBe(field(element, '[data-id="customer-name"]'));
    });

    it('has the Product Name, HSN, Qty, Price and Total columns, with Total worked out as you type', async () => {
        const element = await createScreen();

        const header = grid(element).querySelector('.item-header').textContent;
        ['Sr', 'Product Name', 'HSN', 'Qty', 'Price', 'Total'].forEach((name) => expect(header).toContain(name));
        expect(header).not.toContain('GST');

        await typeCell(element, 0, 'description', 'Engine Oil');
        await typeCell(element, 0, 'hsnSacCode', '2710');
        await typeCell(element, 0, 'quantity', '2');
        await typeCell(element, 0, 'unitPrice', '500');

        expect(grid(element).querySelector('[data-id="line-amount"]').textContent).toBe('₹1,000.00');
        expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 1,000.00');
        expect(grid(element).querySelector('[data-id="line-number"]').textContent).toBe('1');
        // The next line is ready to type into.
        expect(grid(element).querySelectorAll('[data-id="item-row"]')).toHaveLength(2);
    });

    it('Add GST adds the GST column and rows, and Remove GST takes them away', async () => {
        const element = await createScreen();
        await addItem(element, 0, 'Engine Oil', '1000');

        expect($(element, '[data-id="title"]').textContent).toBe('Bill');
        expect($(element, '[data-id="sheet"]').textContent).not.toContain('CGST');
        expect(cell(element, 0, 'taxRatePercent')).toBeNull();
        expect($(element, '[data-id="gst-toggle"]').label).toBe('Add GST');

        $(element, '[data-id="gst-toggle"]').click();
        await flushPromises();

        expect($(element, '[data-id="title"]').textContent).toBe('Tax Invoice');
        expect(cell(element, 0, 'taxRatePercent').value).toBe('18');
        expect($(element, '[data-id="sheet"]').textContent).toContain('CGST');
        expect($(element, '[data-id="sheet"]').textContent).toContain('Sub Total');
        expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 1,180.00');
        expect($(element, '[data-id="gst-toggle"]').label).toBe('Remove GST');

        $(element, '[data-id="gst-toggle"]').click();
        await flushPromises();
        expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 1,000.00');
    });

    it('Alt+G adds or removes GST from the keyboard', async () => {
        const element = await createScreen();
        await addItem(element, 0, 'Engine Oil', '1000');

        press(cell(element, 0, 'unitPrice'), 'g', { altKey: true });
        await flushPromises();

        expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 1,180.00');
    });

    it('Enter moves through every box on the line, and on to the next line', async () => {
        const element = await createScreen();
        $(element, 'c-line-item-grid').focusFirst();
        await addItem(element, 0, 'Engine Oil', '500');

        const order = ['description', 'hsnSacCode', 'quantity', 'unitPrice'];
        for (let i = 0; i < order.length - 1; i++) {
            press(cell(element, 0, order[i]), 'Enter');
            // eslint-disable-next-line no-await-in-loop
            await flushPromises();
            expect(grid(element).activeElement).toBe(cell(element, 0, order[i + 1]));
        }
        press(cell(element, 0, 'unitPrice'), 'Enter');
        await flushPromises();
        expect(grid(element).activeElement).toBe(cell(element, 1, 'description'));
    });

    it('Enter on a product name moves at once, without waiting for the part lookup', async () => {
        searchParts.mockReturnValue(new Promise(() => {}));
        const element = await createScreen();
        await typeCell(element, 0, 'description', 'Engine Oil');

        press(cell(element, 0, 'description'), 'Enter');

        expect(grid(element).activeElement).toBe(cell(element, 0, 'hsnSacCode'));
        searchParts.mockReset();
        searchParts.mockResolvedValue([]);
    });

    it('a part linked after the cursor moved on keeps the HSN and price already typed', async () => {
        searchParts.mockResolvedValue([{ id: 'part1', name: 'Engine Oil', price: 450, hsnCode: '2710', taxRatePercent: 18, currentStock: 5 }]);
        const element = await createScreen();
        await typeCell(element, 0, 'description', 'engine oil');
        await typeCell(element, 0, 'hsnSacCode', '9999');
        await typeCell(element, 0, 'unitPrice', '500');

        cell(element, 0, 'description').dispatchEvent(new CustomEvent('blur'));
        await flushPromises();

        expect(cell(element, 0, 'description').value).toBe('Engine Oil');
        expect(cell(element, 0, 'hsnSacCode').value).toBe('9999');
        expect(cell(element, 0, 'unitPrice').value).toBe('500');
        searchParts.mockResolvedValue([]);
    });

    it('up and down move between lines instead of changing a number', async () => {
        const element = await createScreen();
        await addItem(element, 0, 'Engine Oil', '500');

        const event = new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, composed: true, cancelable: true });
        cell(element, 0, 'quantity').dispatchEvent(event);
        await flushPromises();

        expect(event.defaultPrevented).toBe(true);
        expect(grid(element).activeElement).toBe(cell(element, 1, 'quantity'));
    });

    it('Ctrl+Delete removes the line', async () => {
        const element = await createScreen();
        await addItem(element, 0, 'Engine Oil', '500');
        await addItem(element, 1, 'Car Wash', '200');

        press(cell(element, 0, 'quantity'), 'Delete', { ctrlKey: true });
        await flushPromises();

        expect(cell(element, 0, 'description').value).toBe('Car Wash');
        expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 200.00');
    });

    it('Enter on a blank customer name jumps straight to the items, for a quick walk-in sale', async () => {
        const element = await createScreen();

        press(field(element, '[data-id="customer-name"]').shadowRoot.querySelector('input'), 'Enter');
        await flushPromises();

        expect(grid(element).activeElement).toBe(cell(element, 0, 'description'));
    });

    it('Enter walks the bill boxes in printed order, then from Chassis No. into the table', async () => {
        const element = await createScreen();
        await typeField(element, '[data-id="customer-name"]', 'Ramesh');

        press(field(element, '[data-id="customer-name"]').shadowRoot.querySelector('input'), 'Enter');
        await flushPromises();
        expect(element.shadowRoot.activeElement).toBe(field(element, '[data-field="address"]'));

        press(field(element, '[data-field="chassisNumber"]').shadowRoot.querySelector('input'), 'Enter');
        await flushPromises();
        expect(grid(element).activeElement).toBe(cell(element, 0, 'description'));
    });

    it('typing a name offers existing customers; picking one fills their details and only vehicle', async () => {
        searchCustomers.mockResolvedValue([
            { id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111' },
            { id: 'walk', name: 'Walk-in Customer', phone: '0000000000' }
        ]);
        getCustomer.mockResolvedValue(RAMESH);
        const element = await createScreen();

        await typeField(element, '[data-id="customer-name"]', 'Ram');
        await wait(350);
        const options = field(element, '[data-id="customer-name"]').shadowRoot.querySelectorAll('[data-id="option"]');
        expect(options).toHaveLength(1);

        options[0].dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
        await flushPromises();

        expect(getCustomer).toHaveBeenCalledWith({ customerId: 'cust1' });
        expect(field(element, '[data-field="address"]').value).toBe('Vijay Nagar');
        expect(field(element, '[data-field="phone"]').value).toBe('9000011111');
        expect(field(element, '[data-field="registrationNumber"]').value).toBe('MP09AB1234');
        expect(field(element, '[data-field="make"]').value).toBe('Tata');
        expect($(element, '[data-id="existing-note"]')).not.toBeNull();
    });

    it('a full mobile number typed by hand finds the customer', async () => {
        findCustomerByPhone.mockResolvedValue(RAMESH);
        searchCustomers.mockResolvedValue([]);
        const element = await createScreen();

        await typeField(element, '[data-id="customer-phone"]', '9000011111');
        field(element, '[data-id="customer-phone"]').shadowRoot.querySelector('input').dispatchEvent(new CustomEvent('blur'));
        await flushPromises();

        expect(field(element, '[data-id="customer-name"]').value).toBe('Ramesh Kumar');
    });

    it('warns when an existing customer is being renamed', async () => {
        searchCustomers.mockResolvedValue([{ id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111' }]);
        getCustomer.mockResolvedValue(RAMESH);
        const element = await createScreen();
        await typeField(element, '[data-id="customer-name"]', 'Ram');
        await wait(350);
        field(element, '[data-id="customer-name"]').shadowRoot.querySelector('[data-id="option"]').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
        await flushPromises();

        await typeField(element, '[data-id="customer-name"]', 'Ramesh K');
        await flushPromises();

        expect($(element, '[data-id="rename-note"]').textContent).toContain('Ramesh Kumar');
    });

    it('saves a bill for a walk-in with one line and ignores the empty last line', async () => {
        saveDocument.mockResolvedValue(SAVED);
        const element = await createScreen();
        expect($(element, '[data-id="save"]').disabled).toBe(true);
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('product name');

        await typeCell(element, 0, 'description', 'Engine Oil');
        await typeCell(element, 0, 'hsnSacCode', '2710');
        await typeCell(element, 0, 'quantity', '2');
        await typeCell(element, 0, 'unitPrice', '500');
        await typeField(element, '[data-id="notes"]', 'Thank you');

        $(element, '[data-id="save"]').click();
        await flushPromises();

        const { request } = saveDocument.mock.calls[0][0];
        expect(request).toEqual(expect.objectContaining({
            documentType: 'bill', customerId: null, customerName: '', includeGst: false, notes: 'Thank you', workshop: null
        }));
        expect(request.lineItems).toEqual([
            expect.objectContaining({ description: 'Engine Oil', hsnSacCode: '2710', quantity: 2, unitPrice: 500, taxRatePercent: 18 })
        ]);
        expect($(element, '[data-id="saved-number"]').textContent).toBe('INV/2026-27/0042');
        expect($(element, '[data-id="print"]')).not.toBeNull();
    });

    it('Ctrl+S saves, and tells the user what is missing when it cannot', async () => {
        saveDocument.mockResolvedValue(SAVED);
        const element = await createScreen();
        const toast = jest.fn();
        element.addEventListener('lightning__showtoast', toast);

        press(field(element, '[data-id="customer-name"]').shadowRoot.querySelector('input'), 's', { ctrlKey: true });
        await flushPromises();
        expect(saveDocument).not.toHaveBeenCalled();
        expect(toast.mock.calls[0][0].detail.title).toContain('product name');

        await addItem(element, 0, 'Engine Oil', '500');
        press(cell(element, 0, 'unitPrice'), 's', { ctrlKey: true });
        await flushPromises();
        expect(saveDocument).toHaveBeenCalledTimes(1);
    });

    it('needs a customer name when other customer details are typed, and a vehicle number for vehicle details', async () => {
        const element = await createScreen();
        await addItem(element, 0, 'Engine Oil', '500');
        expect($(element, '[data-id="missing-reason"]')).toBeNull();

        await typeField(element, '[data-field="address"]', 'Ujjain');
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('customer name');
        await typeField(element, '[data-id="customer-name"]', 'Ramesh');
        expect($(element, '[data-id="missing-reason"]')).toBeNull();

        await typeField(element, '[data-field="make"]', 'Tata');
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('vehicle number');
    });

    it('the same page makes an estimate, with the printed estimate wording', async () => {
        saveDocument.mockResolvedValue({ recordId: 'est1', documentNumber: 'EST-0042', customerName: 'Walk-in Customer', totalAmount: 500 });
        const element = await createScreen();

        $(element, '[data-id="document-type"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'estimate' } }));
        await flushPromises();

        expect($(element, '[data-id="title"]').textContent).toBe('Estimate');
        const sheet = $(element, '[data-id="sheet"]').textContent;
        expect(sheet).toContain('Estimated For');
        expect(sheet).toContain('Estimate No.');
        expect($(element, '[data-id="save"]').label).toBe('Save Estimate');

        await addItem(element, 0, 'Engine Oil', '500');
        $(element, '[data-id="save"]').click();
        await flushPromises();

        expect(saveDocument.mock.calls[0][0].request.documentType).toBe('estimate');
        expect(element.shadowRoot.textContent).toContain('Estimate saved');

        $(element, '[data-id="view"]').click();
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage', attributes: { apiName: 'Estimate_Detail' }, state: { c__recordId: 'est1' }
        });
    });

    it('keeps what was typed when switching between bill and estimate', async () => {
        const element = await createScreen();
        await addItem(element, 0, 'Engine Oil', '500');
        await typeField(element, '[data-id="customer-name"]', 'Ramesh');

        $(element, '[data-id="document-type"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'estimate' } }));
        await flushPromises();

        expect(field(element, '[data-id="customer-name"]').value).toBe('Ramesh');
        expect(cell(element, 0, 'description').value).toBe('Engine Oil');
    });

    it('workshop details stay locked until asked for, warn before editing, and save with the bill', async () => {
        saveDocument.mockResolvedValue(SAVED);
        const element = await createScreen();
        expect(field(element, '.pb-workshop-name')).toBeNull();

        $(element, '[data-id="toggle-workshop"]').click();
        await flushPromises();
        expect($(element, '[data-id="workshop-warning"]').textContent).toContain('every bill');

        await typeField(element, '.pb-workshop-name', 'Keshav Motors & Sons');
        await addItem(element, 0, 'Engine Oil', '500');
        $(element, '[data-id="save"]').click();
        await flushPromises();

        const { workshop } = saveDocument.mock.calls[0][0].request;
        expect(workshop.name).toBe('Keshav Motors & Sons');
        expect(workshop.bankName).toBe('Bank of Baroda');
    });

    it('starts with the workshop boxes open when no profile exists yet, and needs a name', async () => {
        listProfiles.mockResolvedValue([]);
        const element = await createScreen();
        await addItem(element, 0, 'Engine Oil', '500');

        expect(field(element, '.pb-workshop-name')).not.toBeNull();
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('workshop name');
    });

    it('shows the amount in words from the server', async () => {
        amountInWords.mockResolvedValue('One Thousand Rupees Only');
        const element = await createScreen();

        await addItem(element, 0, 'Engine Oil', '1000');
        await wait(450);
        await flushPromises();

        expect(amountInWords).toHaveBeenCalledWith({ amount: 1000 });
        expect($(element, '[data-id="amount-words"]').textContent).toBe('One Thousand Rupees Only');
    });

    it('picks a part in the table and warns about stock on a bill', async () => {
        searchParts.mockResolvedValue([{ id: 'part1', name: 'Brake Pad', price: 1200, hsnCode: '8708', taxRatePercent: 28, currentStock: 1 }]);
        const element = await createScreen();

        await typeCell(element, 0, 'description', 'bra');
        await wait(350);
        grid(element).querySelector('[data-id="suggestion"]').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
        await flushPromises();

        expect(cell(element, 0, 'hsnSacCode').value).toBe('8708');
        expect(cell(element, 0, 'unitPrice').value).toBe('1200');
        expect(grid(element).activeElement).toBe(cell(element, 0, 'quantity'));

        await typeCell(element, 0, 'quantity', '3');
        expect(grid(element).querySelector('[data-id="stock-note"]').textContent).toBe('Only 1 in stock');
    });

    it('after saving: Print previews the real PDF, and New starts a clean page', async () => {
        saveDocument.mockResolvedValue(SAVED);
        const element = await createScreen();
        await addItem(element, 0, 'Engine Oil', '500');
        await typeField(element, '[data-id="customer-name"]', 'Ramesh');
        $(element, '[data-id="gst-toggle"]').click();
        await flushPromises();
        $(element, '[data-id="save"]').click();
        await flushPromises();

        $(element, '[data-id="print"]').click();
        await flushPromises();
        expect($(element, 'c-document-preview').recordId).toBe('bill1');

        $(element, '[data-id="new"]').click();
        await flushPromises();

        expect($(element, '[data-id="saved-number"]')).toBeNull();
        expect(field(element, '[data-id="customer-name"]').value).toBe('');
        expect(cell(element, 0, 'description').value).toBe('');
        expect($(element, '[data-id="gst-toggle"]').label).toBe('Add GST');
        expect(element.shadowRoot.activeElement).toBe(field(element, '[data-id="customer-name"]'));
    });

    it('takes the date as one typed box, today by default, and saves it in any common format', async () => {
        saveDocument.mockResolvedValue(SAVED);
        const element = await createScreen();
        expect(field(element, '[data-id="document-date"]').value).toMatch(/^\d{2}-\d{2}-\d{4}$/);
        expect(field(element, '[data-id="document-date"]').shadowRoot.querySelector('input').type).toBe('text');

        await addItem(element, 0, 'Engine Oil', '500');
        await typeField(element, '[data-id="document-date"]', '31-02-2026');
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('date');

        await typeField(element, '[data-id="document-date"]', '5/11/26');
        expect($(element, '[data-id="missing-reason"]')).toBeNull();
        $(element, '[data-id="save"]').click();
        await flushPromises();

        expect(saveDocument.mock.calls[0][0].request.documentDate).toBe('2026-11-05');
    });

    it('with two companies: choosing one changes the page, and the choice is saved', async () => {
        const decor = { ...PROFILE, id: 'wp2', name: 'Keshav Decor', gstin: '23DEC', address: 'Freeganj' };
        listProfiles.mockResolvedValue([PROFILE, decor]);
        saveDocument.mockResolvedValue(SAVED);
        window.localStorage.clear();
        const element = await createScreen();
        expect($(element, '[data-id="workshop-name"]').textContent).toBe('Keshav Motors');

        const picker = $(element, 'c-company-picker');
        picker.shadowRoot.querySelectorAll('[data-id="company-choice"]')[1].click();
        await flushPromises();

        expect($(element, '[data-id="workshop-name"]').textContent).toBe('Keshav Decor');
        expect($(element, '[data-id="sheet"]').textContent).toContain('GSTIN: 23DEC');
        expect($(element, '[data-id="sheet"]').textContent).toContain('For: Keshav Decor');

        await addItem(element, 0, 'Seat Covers', '500');
        $(element, '[data-id="save"]').click();
        await flushPromises();

        expect(saveDocument.mock.calls[0][0].request.workshopProfileId).toBe('wp2');
        window.localStorage.clear();
    });

    it('changing workshop details edits the chosen company, and Keep restores it', async () => {
        const decor = { ...PROFILE, id: 'wp2', name: 'Keshav Decor', invoicePrefix: 'DEC' };
        listProfiles.mockResolvedValue([PROFILE, decor]);
        saveDocument.mockResolvedValue(SAVED);
        window.localStorage.clear();
        const element = await createScreen();
        $(element, 'c-company-picker').shadowRoot.querySelectorAll('[data-id="company-choice"]')[1].click();
        await flushPromises();

        $(element, '[data-id="toggle-workshop"]').click();
        await flushPromises();
        await typeField(element, '.pb-workshop-name', 'Typo');
        $(element, '[data-id="toggle-workshop"]').click();
        await flushPromises();
        expect($(element, '[data-id="workshop-name"]').textContent).toBe('Keshav Decor');

        $(element, '[data-id="toggle-workshop"]').click();
        await flushPromises();
        await typeField(element, '.pb-workshop-name', 'Keshav Car Decor');
        await addItem(element, 0, 'Seat Covers', '500');
        $(element, '[data-id="save"]').click();
        await flushPromises();

        expect(saveDocument.mock.calls[0][0].request.workshop).toEqual(
            expect.objectContaining({ id: 'wp2', name: 'Keshav Car Decor', invoicePrefix: 'DEC' })
        );
        window.localStorage.clear();
    });

    it('opened from the Service Book: customer and car are filled in, ready for the items', async () => {
        getCustomer.mockResolvedValue(RAMESH);
        const element = await createScreen();

        CurrentPageReference.emit({
            type: 'standard__navItemPage',
            attributes: {},
            state: { c__documentType: 'estimate', c__customerId: 'cust1', c__vehicleId: 'veh1', c__opened: '1' }
        });
        await flushPromises();

        expect($(element, '[data-id="title"]').textContent).toBe('Estimate');
        expect(field(element, '[data-id="customer-name"]').value).toBe('Ramesh Kumar');
        expect(field(element, '[data-field="registrationNumber"]').value).toBe('MP09AB1234');
        expect(grid(element).activeElement).toBe(cell(element, 0, 'description'));
    });

    it('a customer with several cars gets the one the card was for', async () => {
        getCustomer.mockResolvedValue({
            ...RAMESH,
            vehicles: [...RAMESH.vehicles, { id: 'veh2', registrationNumber: 'MP09CD5678', make: 'Honda', model: 'City' }]
        });
        const element = await createScreen();

        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__customerId: 'cust1', c__vehicleId: 'veh2', c__opened: '2' } });
        await flushPromises();

        expect(field(element, '[data-field="registrationNumber"]').value).toBe('MP09CD5678');
    });

    it('the terms box shows the saved terms when workshop details are opened', async () => {
        const element = await createScreen();

        $(element, '[data-id="toggle-workshop"]').click();
        await flushPromises();

        const terms = field(element, '[data-field="termsAndConditions"]').shadowRoot.querySelector('textarea');
        expect(terms.value).toBe('Goods once sold are not returned.');
    });

    it('opened from a Service Book card, it shows that visit work beside the bill, not printed', async () => {
        getCustomer.mockResolvedValue(RAMESH);
        getVehicleCard.mockResolvedValue({
            workDone: 'Polish',
            visitDays: [{ entryDate: '2026-11-07', workDone: 'Painting' }, { entryDate: '2026-11-05', workDone: 'Denting' }]
        });
        const element = await createScreen();
        expect($(element, '[data-id="visit-work"]')).toBeNull();

        CurrentPageReference.emit({
            type: 'standard__navItemPage',
            attributes: {},
            state: { c__customerId: 'cust1', c__vehicleId: 'veh1', c__entryDate: '2026-11-09', c__opened: '9' }
        });
        await flushPromises();

        expect(getVehicleCard).toHaveBeenCalledWith({ vehicleId: 'veh1', entryDate: '2026-11-09' });
        const panel = $(element, '[data-id="visit-work"]').textContent;
        expect(panel).toContain('not printed');
        expect(panel.indexOf('Denting')).toBeLessThan(panel.indexOf('Painting'));
        expect(panel.indexOf('Painting')).toBeLessThan(panel.indexOf('Polish'));
    });

    describe('billing a company or insurance', () => {
        const ICICI = { id: 'p1', name: 'ICICI Lombard', address: 'MG Road, Indore', contactPhone: '0731400000', gstin: '23AAACI7904G1ZV', state: 'Madhya Pradesh' };
        const SHARMA = { id: 'p2', name: 'Sharma Transport', address: '', contactPhone: '9827012345', gstin: '', state: '' };

        beforeEach(() => {
            listBillToParties.mockResolvedValue([ICICI, SHARMA]);
        });

        async function turnOnParty(element) {
            $(element, '[data-id="toggle-party"]').click();
            await flushPromises();
        }

        async function pickParty(element, index) {
            const name = field(element, '[data-id="party-name"]');
            name.shadowRoot.querySelector('input').dispatchEvent(new CustomEvent('focus'));
            await flushPromises();
            name.shadowRoot.querySelectorAll('[data-id="option"]')[index].dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
            await flushPromises();
        }

        it('keeps the printed layout: the party under Bill To, and the car owner as Buyer\'s Name', async () => {
            const element = await createScreen();
            expect($(element, '[data-id="toggle-party"]').textContent).toBe('Bill to a company or insurance');
            expect(field(element, '[data-id="party-name"]')).toBeNull();

            await turnOnParty(element);

            const sheet = $(element, '[data-id="sheet"]').textContent;
            expect(sheet).toContain('Bill To');
            expect(sheet).toContain('GSTIN Number:');
            expect(sheet).toContain('Buyer\'s Name:');
            expect(sheet.indexOf('Date:')).toBeLessThan(sheet.indexOf('Buyer\'s Name:'));
            expect(sheet.indexOf('Buyer\'s Name:')).toBeLessThan(sheet.indexOf('Vehicle No.:'));
            expect(field(element, '[data-id="customer-name"]').label).toBe('Buyer\'s name');
            expect($(element, '[data-id="toggle-party"]').textContent).toBe('Bill the customer instead');
            expect(element.shadowRoot.activeElement).toBe(field(element, '[data-id="party-name"]'));
        });

        it('lists saved parties as soon as the party box is entered, and picking one fills its details', async () => {
            const element = await createScreen();
            await turnOnParty(element);

            await pickParty(element, 0);

            expect(listBillToParties).toHaveBeenCalledWith({ searchTerm: '' });
            expect(field(element, '[data-id="party-name"]').value).toBe('ICICI Lombard');
            expect(field(element, '[data-id="party-address"]').value).toBe('MG Road, Indore');
            expect(field(element, '[data-id="party-gstin"]').value).toBe('23AAACI7904G1ZV');
            expect(field(element, '[data-id="party-state"]').value).toBe('Madhya Pradesh');
            expect($(element, '[data-id="party-note"]').textContent).toContain('Saved party');
        });

        it('warns when a saved party\'s details are being changed', async () => {
            const element = await createScreen();
            await turnOnParty(element);
            await pickParty(element, 0);

            await typeField(element, '[data-id="party-address"]', 'Vijay Nagar, Indore');

            expect($(element, '[data-id="party-note"]').textContent).toContain('changes ICICI Lombard');
            expect($(element, '[data-id="party-note"]').className).not.toContain('pb-note_ok');
        });

        it('a different name after a pick is a new party, and drops the old GSTIN', async () => {
            const element = await createScreen();
            await turnOnParty(element);
            await pickParty(element, 0);

            await typeField(element, '[data-id="party-name"]', 'Verma Fleet');

            expect(field(element, '[data-id="party-gstin"]').value).toBe('');
            expect(field(element, '[data-id="party-address"]').value).toBe('');
            expect($(element, '[data-id="party-note"]').textContent).toContain('New party');
        });

        it('a saved name typed in full finds that party when the cursor leaves', async () => {
            listBillToParties.mockResolvedValue([SHARMA]);
            const element = await createScreen();
            await turnOnParty(element);
            await typeField(element, '[data-id="party-name"]', 'sharma transport');
            await wait(350);

            field(element, '[data-id="party-name"]').shadowRoot.querySelector('input').dispatchEvent(new CustomEvent('blur'));
            await flushPromises();

            expect(field(element, '[data-id="party-phone"]').value).toBe('9827012345');
            expect($(element, '[data-id="party-note"]').textContent).toContain('Saved party');
        });

        it('saves the picked party with the page\'s details and the car owner as buyer', async () => {
            saveDocument.mockResolvedValue({ ...SAVED, customerName: 'ICICI Lombard' });
            const element = await createScreen();
            await turnOnParty(element);
            await pickParty(element, 0);
            await typeField(element, '[data-id="customer-name"]', 'Ramesh Kumar');
            await typeField(element, '[data-id="customer-phone"]', '9000011111');
            await addItem(element, 0, 'Bumper repair', '3500');

            $(element, '[data-id="save"]').click();
            await flushPromises();

            const { request } = saveDocument.mock.calls[0][0];
            expect(request).toEqual(expect.objectContaining({
                customerName: 'Ramesh Kumar',
                customerPhone: '9000011111',
                billToPartyId: 'p1',
                billToParty: { name: 'ICICI Lombard', address: 'MG Road, Indore', contactPhone: '0731400000', gstin: '23AAACI7904G1ZV', state: 'Madhya Pradesh' }
            }));
            expect($(element, '.pb-saved-card').textContent).toContain('ICICI Lombard');
        });

        it('needs a party name, checks the GSTIN length, and the buyer is optional', async () => {
            const element = await createScreen();
            await turnOnParty(element);
            await addItem(element, 0, 'Bumper repair', '3500');
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('party name');

            await typeField(element, '[data-id="party-name"]', 'Verma Fleet');
            await typeField(element, '[data-id="party-gstin"]', '23ABCDE1234F1Z5X');
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('15 characters');

            await typeField(element, '[data-id="party-gstin"]', '23ABCDE1234F1Z8');
            expect($(element, '[data-id="missing-reason"]')).toBeNull();
            expect($(element, '[data-id="save"]').disabled).toBe(false);
        });

        it('Enter on an empty buyer name goes on to the vehicle, not the items', async () => {
            const element = await createScreen();
            await turnOnParty(element);

            press(field(element, '[data-id="customer-name"]').shadowRoot.querySelector('input'), 'Enter');
            await flushPromises();

            expect(element.shadowRoot.activeElement).toBe(field(element, '[data-id="customer-phone"]'));
        });

        it('Alt+P switches it on and off; switching off sends no party', async () => {
            saveDocument.mockResolvedValue(SAVED);
            const element = await createScreen();
            const screen = $(element, '.pb-screen');

            press(screen, 'p', { altKey: true });
            await flushPromises();
            expect(field(element, '[data-id="party-name"]')).not.toBeNull();
            await typeField(element, '[data-id="party-name"]', 'Verma Fleet');

            press(screen, 'p', { altKey: true });
            await flushPromises();
            expect(field(element, '[data-id="party-name"]')).toBeNull();
            await addItem(element, 0, 'Bumper repair', '3500');
            $(element, '[data-id="save"]').click();
            await flushPromises();

            const { request } = saveDocument.mock.calls[0][0];
            expect(request.billToPartyId).toBeNull();
            expect(request.billToParty).toBeNull();
        });

        it('the estimate uses estimate wording, and New starts without a party', async () => {
            saveDocument.mockResolvedValue(SAVED);
            const element = await createScreen();
            $(element, '[data-id="document-type"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'estimate' } }));
            await flushPromises();
            expect($(element, '[data-id="toggle-party"]').textContent).toBe('Estimate for a company or insurance');

            await turnOnParty(element);
            await typeField(element, '[data-id="party-name"]', 'Verma Fleet');
            await addItem(element, 0, 'Bumper repair', '3500');
            $(element, '[data-id="save"]').click();
            await flushPromises();
            expect(saveDocument.mock.calls[0][0].request.billToParty.name).toBe('Verma Fleet');

            $(element, '[data-id="new"]').click();
            await flushPromises();
            expect(field(element, '[data-id="party-name"]')).toBeNull();
        });
    });

    describe('a saved bill opened from the Billing list', () => {
        const SAVED_BILL = {
            documentType: 'bill',
            recordId: 'bill9',
            documentNumber: 'INV/2026-27/0009',
            versionNumber: 1,
            isLatestVersion: true,
            workshopProfileId: 'wp1',
            customer: { ...RAMESH, vehicles: [...RAMESH.vehicles, { id: 'veh2', registrationNumber: 'MP09CD5678', make: 'Maruti', model: 'Swift' }] },
            vehicle: { id: 'veh2', registrationNumber: 'MP09CD5678', make: 'Maruti', model: 'Swift', chassisNumber: '' },
            billToParty: null,
            documentDate: '2026-11-03',
            notes: 'First visit',
            includeGst: true,
            lines: [
                { partId: 'part1', description: 'Engine Oil 1L', hsnSacCode: '2710', quantity: 2, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST' },
                { partId: 'part2', description: 'Washing', hsnSacCode: '', quantity: 1, unitPrice: 200, taxRatePercent: 5, gstType: 'CGST_SGST' }
            ]
        };

        async function openSaved(element, doc, opened = '1') {
            getDocument.mockResolvedValue(doc);
            CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__editId: doc.recordId, c__opened: opened } });
            await flushPromises();
            await flushPromises();
        }

        it('shows the saved bill on the page, as it was saved', async () => {
            const element = await createScreen();
            await openSaved(element, SAVED_BILL);

            expect(getDocument).toHaveBeenCalledWith({ recordId: 'bill9' });
            expect(field(element, '[data-id="customer-name"]').value).toBe('Ramesh Kumar');
            expect(field(element, '[data-field="registrationNumber"]').value).toBe('MP09CD5678');
            expect(field(element, '[data-id="document-date"]').value).toBe('03-11-2026');
            // What shows in the box, not just the property: an unbound textarea
            // already on screen once stayed blank here.
            expect(field(element, '[data-id="notes"]').shadowRoot.querySelector('textarea').value).toBe('First visit');
            expect(cell(element, 0, 'description').value).toBe('Engine Oil 1L');
            expect(cell(element, 0, 'quantity').value).toBe('2');
            expect(cell(element, 1, 'description').value).toBe('Washing');
            expect($(element, '[data-id="gst-toggle"]').label).toBe('Remove GST');
            expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 1,390.00');
            expect($(element, '[data-id="auto-number"]').textContent).toContain('INV/2026-27/0009');
        });

        it('says what saving will do, locks the company and the bill/estimate choice', async () => {
            const element = await createScreen();
            await openSaved(element, SAVED_BILL);

            expect($(element, '[data-id="opened-text"]').textContent).toContain('INV/2026-27/0009');
            expect($(element, '[data-id="opened-text"]').textContent).toContain('new number');
            expect($(element, '[data-id="document-type"]')).toBeNull();
            expect($(element, 'c-company-picker').locked).toBe(true);
            expect($(element, 'c-company-picker').value).toBe('wp1');
            expect($(element, '[data-id="save"]').label).toBe('Save Changes');
        });

        it('saving sends it as a new version of the opened bill, and says which one it replaces', async () => {
            saveDocument.mockResolvedValue({ ...SAVED, replacedNumber: 'INV/2026-27/0009' });
            const element = await createScreen();
            await openSaved(element, SAVED_BILL);
            await typeCell(element, 0, 'quantity', '3');

            $(element, '[data-id="save"]').click();
            await flushPromises();

            const { request } = saveDocument.mock.calls[0][0];
            expect(request).toEqual(expect.objectContaining({
                previousVersionId: 'bill9', documentType: 'bill', customerId: 'cust1', vehicleId: 'veh2', includeGst: true, notes: 'First visit'
            }));
            expect(request.lineItems.map((l) => [l.description, l.quantity])).toEqual([['Engine Oil 1L', 3], ['Washing', 1]]);
            expect(request.documentDate).toBe('2026-11-03');
            expect($(element, '[data-id="replaced-note"]').textContent).toContain('INV/2026-27/0009');
            expect($(element, '.pb-saved-card').textContent).toContain('Bill changes saved');
        });

        it('View PDF shows the saved bill as it is now', async () => {
            const element = await createScreen();
            await openSaved(element, SAVED_BILL);

            $(element, '[data-id="view-opened"]').click();
            await flushPromises();

            expect($(element, 'c-document-preview').recordId).toBe('bill9');
            expect($(element, 'c-document-preview').heading).toBe('INV/2026-27/0009');
        });

        it('an estimate with a party opens as an estimate, billed to the party', async () => {
            const element = await createScreen();
            await openSaved(element, {
                ...SAVED_BILL,
                documentType: 'estimate',
                recordId: 'est9',
                documentNumber: 'EST-0009',
                customer: null,
                vehicle: null,
                billToParty: { id: 'p1', name: 'ICICI Lombard', address: 'MG Road', contactPhone: '', gstin: '23AAACI7904G1ZV', state: '' },
                includeGst: false
            });

            expect($(element, '[data-id="title"]').textContent).toBe('Estimate');
            expect(field(element, '[data-id="party-name"]').value).toBe('ICICI Lombard');
            expect(field(element, '[data-id="party-gstin"]').value).toBe('23AAACI7904G1ZV');
            expect(field(element, '[data-id="customer-name"]').value).toBe('');
            expect($(element, '[data-id="gst-toggle"]').label).toBe('Add GST');
            expect($(element, '[data-id="opened-text"]').textContent).toContain('Estimate EST-0009');
        });

        it('an older version can be seen but not saved', async () => {
            const element = await createScreen();
            await openSaved(element, { ...SAVED_BILL, isLatestVersion: false, versionNumber: 2 });

            expect($(element, '[data-id="opened-text"]').textContent).toContain('older version');
            expect($(element, '[data-id="save"]').disabled).toBe(true);
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('latest one');
        });

        it('opening replaces a half-typed bill, and New Bill starts clean again', async () => {
            const element = await createScreen();
            await addItem(element, 0, 'Half typed', '99');
            await openSaved(element, SAVED_BILL);
            expect(cell(element, 0, 'description').value).toBe('Engine Oil 1L');
            expect(cell(element, 2, 'description').value).toBe('');

            $(element, '[data-id="start-new"]').click();
            await flushPromises();

            expect($(element, '[data-id="opened-banner"]')).toBeNull();
            expect($(element, '[data-id="document-type"]')).not.toBeNull();
            expect(cell(element, 0, 'description').value).toBe('');
            expect(field(element, '[data-id="customer-name"]').value).toBe('');
            expect($(element, '[data-id="auto-number"]').textContent).toBe('Given when you save');
        });

        it('a bill opened by mistake does not stay behind when the Service Book opens a car', async () => {
            getCustomer.mockResolvedValue(RAMESH);
            const element = await createScreen();
            await openSaved(element, SAVED_BILL);

            CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__customerId: 'cust1', c__vehicleId: 'veh1', c__opened: '2' } });
            await flushPromises();
            await flushPromises();

            expect($(element, '[data-id="opened-banner"]')).toBeNull();
            expect(cell(element, 0, 'description').value).toBe('');
            expect(field(element, '[data-field="registrationNumber"]').value).toBe('MP09AB1234');
        });
    });

    describe('GST details on the page', () => {
        it('the customer state suggests states as it is typed, and a pick fills it', async () => {
            const element = await createScreen();
            await typeField(element, '[data-id="customer-state"]', 'ma');
            await wait(350);
            const options = [...field(element, '[data-id="customer-state"]').shadowRoot.querySelectorAll('[data-id="option"]')];
            expect(options.map((o) => o.dataset.value)).toEqual(expect.arrayContaining(['Madhya Pradesh', 'Maharashtra']));

            options.find((o) => o.dataset.value === 'Maharashtra').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
            await flushPromises();

            expect(field(element, '[data-id="customer-state"]').value).toBe('Maharashtra');
        });

        it('"mp" typed without picking becomes Madhya Pradesh', async () => {
            const element = await createScreen();
            await typeField(element, '[data-id="customer-state"]', 'mp');
            field(element, '[data-id="customer-state"]').shadowRoot.querySelector('input').dispatchEvent(new CustomEvent('blur'));
            await flushPromises();

            expect(field(element, '[data-id="customer-state"]').value).toBe('Madhya Pradesh');
        });

        it('a state that is not a state, or a wrong GSTIN, is named before saving', async () => {
            const element = await createScreen();
            await addItem(element, 0, 'Engine Oil', '500');
            await typeField(element, '[data-id="customer-name"]', 'Ramesh');
            await typeField(element, '[data-id="customer-state"]', 'Ujjain');
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('Pick the customer state from the list');

            await typeField(element, '[data-id="customer-state"]', '');
            await typeField(element, '[data-field="gstin"]', '27AAPFU0939F1ZW');
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('The customer GSTIN');
            expect($(element, '[data-id="save"]').disabled).toBe(true);

            await typeField(element, '[data-field="gstin"]', '27AAPFU0939F1ZV');
            expect($(element, '[data-id="missing-reason"]')).toBeNull();
            expect(field(element, '[data-id="customer-state"]').value).toBe('Maharashtra');
        });

        it('a wrong workshop GSTIN stops saving while the workshop details are being changed', async () => {
            const element = await createScreen();
            await addItem(element, 0, 'Engine Oil', '500');
            $(element, '[data-id="toggle-workshop"]').click();
            await flushPromises();

            const workshopGstin = [...element.shadowRoot.querySelectorAll('c-paper-field[data-field="gstin"]')].find((f) => f.label === 'Workshop GSTIN');
            const box = workshopGstin.shadowRoot.querySelector('input');
            box.value = 'kjhsdj090';
            box.dispatchEvent(new CustomEvent('input', { bubbles: true }));
            await flushPromises();

            expect($(element, '[data-id="missing-reason"]').textContent).toContain('The workshop GSTIN');
        });
    });

    describe('deleting, old dates and filed months', () => {
        const OPENED = {
            documentType: 'bill', recordId: 'bill9', documentNumber: 'INV/2026-27/0009', versionNumber: 1, isLatestVersion: true,
            workshopProfileId: 'wp1', customer: null, vehicle: null, billToParty: null, documentDate: '2026-11-03', notes: '',
            includeGst: false, lines: [{ description: 'Engine Oil', quantity: 1, unitPrice: 500, taxRatePercent: 18 }],
            isCancelled: false, isGstFiled: false
        };

        async function open(element, doc) {
            getDocument.mockResolvedValue(doc);
            CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__editId: doc.recordId, c__opened: String(Math.random()) } });
            await flushPromises();
            await flushPromises();
        }

        function isoDaysFromToday(days) {
            const d = new Date();
            d.setDate(d.getDate() + days);
            const pad = (n) => String(n).padStart(2, '0');
            return `${pad(d.getDate())}-${pad(d.getMonth() + 1)}-${d.getFullYear()}`;
        }

        it('an opened bill can be deleted from the page, which then starts a new bill', async () => {
            cancelBill.mockResolvedValue({});
            const element = await createScreen();
            await open(element, OPENED);
            const confirm = $(element, 'c-delete-confirm');
            expect(confirm.message).toContain('number is kept and shown as cancelled');

            confirm.dispatchEvent(new CustomEvent('confirm'));
            await flushPromises();

            expect(cancelBill).toHaveBeenCalledWith({ billId: 'bill9' });
            expect($(element, '[data-id="opened-banner"]')).toBeNull();
            expect(cell(element, 0, 'description').value).toBe('');
        });

        it('an opened estimate is deleted outright', async () => {
            deleteEstimate.mockResolvedValue();
            const element = await createScreen();
            await open(element, { ...OPENED, documentType: 'estimate', recordId: 'est9', documentNumber: 'EST-0009' });

            $(element, 'c-delete-confirm').dispatchEvent(new CustomEvent('confirm'));
            await flushPromises();

            expect(deleteEstimate).toHaveBeenCalledWith({ estimateId: 'est9' });
            expect(cancelBill).not.toHaveBeenCalled();
        });

        it('a deleted bill can be looked at, not changed or deleted again', async () => {
            const element = await createScreen();
            await open(element, { ...OPENED, isCancelled: true });

            expect($(element, '[data-id="opened-text"]').textContent).toContain('was deleted');
            expect($(element, 'c-delete-confirm')).toBeNull();
            expect($(element, '[data-id="save"]').disabled).toBe(true);
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('was deleted');
        });

        it('a bill in a filed month can be looked at, not changed or deleted', async () => {
            const element = await createScreen();
            await open(element, { ...OPENED, isGstFiled: true, gstFiledUpTo: '2026-11-30' });

            expect($(element, '[data-id="opened-text"]').textContent).toContain('filed up to November 2026');
            expect($(element, 'c-delete-confirm')).toBeNull();
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('can\'t be changed');
        });

        it('a new bill can\'t be dated in the future', async () => {
            const element = await createScreen();
            await addItem(element, 0, 'Engine Oil', '500');
            await typeField(element, '[data-id="document-date"]', isoDaysFromToday(2));

            expect($(element, '[data-id="missing-reason"]').textContent).toContain('future');
        });

        it('a date in an earlier financial year says which series the number joins', async () => {
            const element = await createScreen();
            await typeField(element, '[data-id="document-date"]', isoDaysFromToday(-400));
            const [day, month, year] = isoDaysFromToday(-400).split('-').map(Number);
            const start = month >= 4 ? year : year - 1;

            expect($(element, '[data-id="auto-number"]').textContent).toContain(`${start}-${String((start + 1) % 100).padStart(2, '0')} series`);
        });

        it('a date in a month the company has filed is refused before saving', async () => {
            listProfiles.mockResolvedValue([{ ...PROFILE, gstFiledUpTo: '2099-12-31' }]);
            const element = await createScreen();
            await addItem(element, 0, 'Engine Oil', '500');

            expect($(element, '[data-id="missing-reason"]').textContent).toContain('GST is filed up to December 2099');
            expect($(element, '[data-id="save"]').disabled).toBe(true);
        });
    });

    describe('discount, round-off and no-GST companies (G5)', () => {
        it('Add discount shows a Discount column; the discount comes off before GST and the total is rounded', async () => {
            saveDocument.mockResolvedValue(SAVED);
            const element = await createScreen();
            $(element, '[data-id="gst-toggle"]').click();
            await flushPromises();
            expect(cell(element, 0, 'discount')).toBeNull();

            $(element, '[data-id="discount-toggle"]').click();
            await flushPromises();
            expect($(element, '[data-id="discount-toggle"]').label).toBe('Remove discount');
            await typeCell(element, 0, 'description', 'Pad');
            await typeCell(element, 0, 'quantity', '2');
            await typeCell(element, 0, 'unitPrice', '500');
            await typeCell(element, 0, 'discount', '100');
            await typeCell(element, 1, 'description', 'Clip');
            await typeCell(element, 1, 'unitPrice', '333');

            // 900 + 162 + 333 + 59.94 = 1454.94, rounded to 1455.00
            expect($(element, '[data-id="round-off"]').textContent).toBe('Rs. +0.06');
            expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 1,455.00');
            $(element, '[data-id="save"]').click();
            await flushPromises();
            const { request } = saveDocument.mock.calls[0][0];
            expect(request.lineItems.map((line) => line.discount)).toEqual([100, 0]);
            expect(request.insuranceSplit).toBe(false);
        });

        it('Alt+D turns discounts off again, clearing them', async () => {
            const element = await createScreen();
            press($(element, '.pb-screen'), 'd', { altKey: true });
            await flushPromises();
            await addItem(element, 0, 'Pad', '500');
            await typeCell(element, 0, 'discount', '50');
            expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 450.00');

            press($(element, '.pb-screen'), 'd', { altKey: true });
            await flushPromises();
            expect(cell(element, 0, 'discount')).toBeNull();
            expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 500.00');
        });

        it('a discount above the line\'s price can\'t be saved', async () => {
            const element = await createScreen();
            $(element, '[data-id="discount-toggle"]').click();
            await flushPromises();
            await addItem(element, 0, 'Pad', '500');
            await typeCell(element, 0, 'discount', '600');

            expect(grid(element).querySelector('[data-id="discount-note"]').textContent).toContain('between 0 and ₹500.00');
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('discount is more than');
            expect($(element, '[data-id="save"]').disabled).toBe(true);
        });

        it('a company that doesn\'t round off shows the exact total', async () => {
            listProfiles.mockResolvedValue([{ ...PROFILE, roundOffTotals: false }]);
            const element = await createScreen();
            $(element, '[data-id="gst-toggle"]').click();
            await flushPromises();
            await addItem(element, 0, 'Clip', '333');

            expect($(element, '[data-id="round-off"]')).toBeNull();
            expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 392.94');
        });

        it('a composition company issues a Bill of Supply, with no GST button', async () => {
            listProfiles.mockResolvedValue([{ ...PROFILE, gstRegistrationType: 'Composition' }]);
            const element = await createScreen();

            expect($(element, '[data-id="title"]').textContent).toBe('Bill of Supply');
            expect($(element, '[data-id="composition-note"]').textContent).toContain('not eligible to collect tax');
            expect($(element, '[data-id="gst-toggle"]')).toBeNull();
            press($(element, '.pb-screen'), 'g', { altKey: true });
            await flushPromises();
            expect(cell(element, 0, 'taxRatePercent')).toBeNull();
        });
    });

    describe('an insurance claim split (G6)', () => {
        const ICICI = { id: 'p1', name: 'ICICI Lombard', address: 'MG Road, Indore', contactPhone: '0731400000', gstin: '23AAACI7904G1ZV', state: 'Madhya Pradesh' };

        beforeEach(() => {
            listBillToParties.mockResolvedValue([ICICI]);
        });

        async function claimPage() {
            const element = await createScreen();
            $(element, '[data-id="toggle-party"]').click();
            await flushPromises();
            const name = field(element, '[data-id="party-name"]');
            name.shadowRoot.querySelector('input').dispatchEvent(new CustomEvent('focus'));
            await flushPromises();
            name.shadowRoot.querySelectorAll('[data-id="option"]')[0].dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
            await flushPromises();
            $(element, '[data-id="gst-toggle"]').click();
            await flushPromises();
            return element;
        }

        it('is offered only on a new bill to a party', async () => {
            const element = await createScreen();
            expect($(element, '[data-id="split-toggle"]')).toBeNull();
            $(element, '[data-id="toggle-party"]').click();
            await flushPromises();
            expect($(element, '[data-id="split-toggle"]')).not.toBeNull();
            $(element, '[data-id="document-type"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'estimate' } }));
            await flushPromises();
            expect($(element, '[data-id="split-toggle"]')).toBeNull();
        });

        it('shows what each side pays, and saves both bills in one go', async () => {
            saveDocument.mockResolvedValue({
                ...SAVED, customerName: 'ICICI Lombard', totalAmount: 1770,
                pairedRecordId: 'bill2', pairedNumber: 'INV/2026-27/0043', pairedTotal: 1180
            });
            const element = await claimPage();
            $(element, '[data-id="split-toggle"]').click();
            await flushPromises();
            await typeField(element, '[data-id="customer-name"]', 'Ramesh Kumar');
            await addItem(element, 0, 'Bumper', '1000');
            await addItem(element, 1, 'Headlamp', '1000');
            await typeCell(element, 1, 'insurerPercent', '50');
            await addItem(element, 2, 'Labour', '500');
            await typeField(element, '[data-id="excess"]', '590');

            expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 2,950.00');
            expect($(element, '[data-id="insurer-total"]').textContent).toBe('Rs. 1,770.00');
            expect($(element, '[data-id="customer-total"]').textContent).toBe('Rs. 1,180.00');
            expect($(element, '[data-id="split-rounding-note"]')).toBeNull();

            $(element, '[data-id="save"]').click();
            await flushPromises();
            const { request } = saveDocument.mock.calls[0][0];
            expect(request.insuranceSplit).toBe(true);
            expect(request.insurerPercents).toEqual([100, 50, 100]);
            expect(request.compulsoryExcess).toBe(590);
            expect(request.lineItems.map((line) => line.unitPrice)).toEqual([1000, 1000, 500]);

            expect($(element, '[data-id="saved-paired-number"]').textContent).toBe('INV/2026-27/0043');
            expect($(element, '[data-id="saved-paired-total"]').textContent).toBe('₹1,180.00');
            $(element, '[data-id="print-paired"]').click();
            await flushPromises();
            expect($(element, 'c-document-preview').recordId).toBe('bill2');
        });

        it('needs the car owner, and says what can\'t be split', async () => {
            const element = await claimPage();
            $(element, '[data-id="split-toggle"]').click();
            await flushPromises();
            await addItem(element, 0, 'Bumper', '1000');
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('car owner');

            await typeField(element, '[data-id="customer-name"]', 'Ramesh Kumar');
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('The customer pays nothing');
            await typeField(element, '[data-id="excess"]', '5000');
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('more than the insurance company');
            await typeField(element, '[data-id="excess"]', 'abc');
            expect($(element, '[data-id="missing-reason"]').textContent).toContain('Type the compulsory excess');
            await typeField(element, '[data-id="excess"]', '118');
            expect($(element, '[data-id="missing-reason"]')).toBeNull();

            // 1180 + 18% on 333 = 1572.94 (1573); insurer 1062 + 196.47 - 100 = 1158.47 (1158),
            // customer 196.47 + 100 = 296.47 (296): each rounds alone, 1454 together.
            await typeCell(element, 0, 'unitPrice', '900');
            await addItem(element, 1, 'Clip', '333');
            await typeCell(element, 1, 'insurerPercent', '50');
            await typeField(element, '[data-id="excess"]', '100');
            expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 1,455.00');
            expect($(element, '[data-id="split-rounding-note"]').textContent).toContain('together they come to Rs. 1,454.00');
        });

        it('a saved claim bill, opened, names its other half', async () => {
            getDocument.mockResolvedValue({
                documentType: 'bill', recordId: 'bill1', documentNumber: 'INV/2026-27/0042', versionNumber: 1, isLatestVersion: true,
                workshopProfileId: 'wp1', customer: null, vehicle: null, billToParty: ICICI, documentDate: '2026-11-03', notes: '',
                includeGst: true, pairedNumber: 'INV/2026-27/0043',
                lines: [{ description: 'Headlamp', quantity: 1, unitPrice: 1000, taxRatePercent: 18, gstType: 'CGST_SGST', discount: 500 }]
            });
            const element = await createScreen();
            CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__editId: 'bill1', c__opened: 'x' } });
            await flushPromises();
            await flushPromises();

            expect($(element, '[data-id="opened-pair"]').textContent).toContain('INV/2026-27/0043');
            expect($(element, '[data-id="split-toggle"]')).toBeNull();
            expect(cell(element, 0, 'discount').value).toBe('500');
            expect($(element, '[data-id="grand-total"]').textContent).toBe('Rs. 590.00');
        });
    });

    describe('capitals and the suggestion highlight', () => {
        it('vehicle number, chassis and GSTIN type in capitals, with the cursor kept where it was', async () => {
            saveDocument.mockResolvedValue(SAVED);
            const element = await createScreen();
            const box = field(element, '[data-field="registrationNumber"]').shadowRoot.querySelector('input');
            box.value = 'mp09ab1234';
            box.setSelectionRange(4, 4);
            box.dispatchEvent(new CustomEvent('input', { bubbles: true }));
            await flushPromises();
            expect(box.value).toBe('MP09AB1234');
            expect(box.selectionStart).toBe(4);

            await typeField(element, '[data-field="chassisNumber"]', 'ma3abc123');
            await typeField(element, '[data-id="customer-name"]', 'Sharma Traders');
            const gstin = field(element, '[data-field="gstin"]');
            gstin.shadowRoot.querySelector('input').value = '27aapfu0939f1zv';
            gstin.shadowRoot.querySelector('input').dispatchEvent(new CustomEvent('input', { bubbles: true }));
            await flushPromises();
            await addItem(element, 0, 'Wash', '200');
            $(element, '[data-id="save"]').click();
            await flushPromises();

            const { request } = saveDocument.mock.calls[0][0];
            expect(request.registrationNumber).toBe('MP09AB1234');
            expect(request.chassisNumber).toBe('MA3ABC123');
            expect(request.customerGstin).toBe('27AAPFU0939F1ZV');
        });

        it('a name box is left as typed', async () => {
            const element = await createScreen();
            await typeField(element, '[data-id="customer-name"]', 'ramesh kumar');
            expect(field(element, '[data-id="customer-name"]').shadowRoot.querySelector('input').value).toBe('ramesh kumar');
        });

        it('the suggestion the arrow keys are on is marked as the active one', async () => {
            searchParts.mockResolvedValue([
                { id: 'part1', name: 'Brake Pad', price: 100, currentStock: 3 },
                { id: 'part2', name: 'Brake Oil', price: 200, currentStock: 3 }
            ]);
            const element = await createScreen();
            await typeCell(element, 0, 'description', 'Bra');
            await wait(350);
            await flushPromises();
            press(cell(element, 0, 'description'), 'ArrowDown');
            press(cell(element, 0, 'description'), 'ArrowDown');
            await flushPromises();

            const options = [...grid(element).querySelectorAll('[data-id="suggestion"]')];
            expect(options.map((o) => o.classList.contains('suggestion_active'))).toEqual([false, true]);
            expect(options[1].getAttribute('aria-selected')).toBe('true');
        });
    });
});
