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

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchCustomers', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchParts', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.findCustomerByPhone', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchMakes', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchModels', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/PaperBillController.getCustomer', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PaperBillController.amountInWords', () => ({ default: jest.fn(() => Promise.resolve('')) }), { virtual: true });
jest.mock('@salesforce/apex/PaperBillController.saveDocument', () => ({ default: jest.fn() }), { virtual: true });
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
    id: 'wp1', name: 'Keshav Motors', address: 'Dewas Road, Ujjain', phone: '9039472001', email: '', gstin: '23ABC', state: 'MP',
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
});
