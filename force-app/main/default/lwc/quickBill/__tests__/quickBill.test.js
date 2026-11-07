import { createElement } from 'lwc';
import QuickBill from 'c/quickBill';
import findCustomerByPhone from '@salesforce/apex/QuickBillController.findCustomerByPhone';
import createQuickBill from '@salesforce/apex/QuickBillController.createQuickBill';
import createQuickEstimate from '@salesforce/apex/QuickBillController.createQuickEstimate';
import searchParts from '@salesforce/apex/BillController.searchParts';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.findCustomerByPhone', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.createQuickBill', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.createQuickEstimate', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchParts', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchMakes', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchModels', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });

const mockScanner = {
    isAvailable: jest.fn(() => false),
    beginCapture: jest.fn(),
    endCapture: jest.fn(),
    barcodeTypes: { EAN_13: 'ean13' }
};
jest.mock('lightning/mobileCapabilities', () => ({ getBarcodeScanner: jest.fn(() => mockScanner) }), { virtual: true });

const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](pageRef) {
                mockNavigate(pageRef);
            }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
});

const BRAKE_PAD = {
    id: 'part1', name: 'Brake Pad Set', sku: 'BP-01', barcode: '8901234567890', price: 1200,
    taxRatePercent: 28, gstType: 'CGST_SGST', hsnCode: '8708', unitLabel: 'Set', currentStock: 1
};
const OIL = { id: 'part2', name: 'Engine Oil 1L', sku: 'OIL-1', price: 500, taxRatePercent: 18, gstType: 'CGST_SGST', currentStock: 20 };

const SUMMARY = { billId: 'bill1', invoiceNumber: 'INV/2026-27/0042', customerName: 'Walk-in Customer', totalAmount: 1000 };

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// The screen debounces part search (300ms) and phone lookup (400ms).
function wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function createQuickBillElement() {
    const element = createElement('c-quick-bill', { is: QuickBill });
    document.body.appendChild(element);
    return element;
}

function grid(element) {
    const child = element.shadowRoot.querySelector('c-line-item-grid');
    return child ? child.shadowRoot : null;
}

// Looks on the screen, then inside the item grid.
function $(element, selector) {
    const found = element.shadowRoot.querySelector(selector);
    if (found) {
        return found;
    }
    return grid(element) ? grid(element).querySelector(selector) : null;
}

function rows(element) {
    return [...grid(element).querySelectorAll('[data-id="item-row"]')];
}

function cell(element, rowIndex, field) {
    return rows(element)[rowIndex].querySelector(`input[data-field="${field}"]`);
}

async function typeCell(element, rowIndex, field, value) {
    const input = cell(element, rowIndex, field);
    input.value = value;
    input.dispatchEvent(new CustomEvent('input', { bubbles: true }));
    await flushPromises();
}

function pressKey(input, key, options) {
    input.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, composed: true, cancelable: true, ...options }));
}

function type(element, selector, value) {
    const input = $(element, selector);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

async function switchToWalkIn(element) {
    $(element, '[data-id="mode"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'walkin' } }));
    await flushPromises();
}

async function setGst(element, checked) {
    const toggle = $(element, '[data-id="include-gst"]');
    toggle.checked = checked;
    toggle.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
}

async function typeName(element, rowIndex, value, results) {
    searchParts.mockResolvedValue(results);
    await typeCell(element, rowIndex, 'description', value);
    await wait(350);
    await flushPromises();
}

describe('c-quick-bill', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('starts ready to type: one empty line, GST off, and no add-line button', async () => {
        const element = createQuickBillElement();
        await flushPromises();

        expect($(element, '[data-id="mode"]').value).toBe('customer');
        expect(rows(element)).toHaveLength(1);
        expect(cell(element, 0, 'quantity').value).toBe('1');
        expect(cell(element, 0, 'taxRatePercent').value).toBe('18');
        expect($(element, '[data-id="include-gst"]').checked).toBe(false);
        expect($(element, '[data-id="add-custom"]')).toBeNull();
        expect($(element, '[data-id="create"]').disabled).toBe(true);
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('phone number');
    });

    it('keeps item, quantity, price and GST in one line, in that order', async () => {
        const element = createQuickBillElement();
        await flushPromises();

        const inputs = [...rows(element)[0].querySelector('.item-line').querySelectorAll('input')];
        expect(inputs.map((i) => i.dataset.field)).toEqual(['description', 'quantity', 'unitPrice', 'taxRatePercent']);
    });

    it('leaves the row buttons out of the Tab order, so Tab goes from GST to the next item name', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await setGst(element, true);
        await typeCell(element, 0, 'description', 'Wheel alignment');
        await typeCell(element, 0, 'unitPrice', '600');

        const tabbable = [...rows(element)[0].querySelectorAll('input, button')].filter((node) => node.getAttribute('tabindex') !== '-1');
        expect(tabbable.map((node) => node.dataset.field)).toEqual(['description', 'quantity', 'unitPrice', 'taxRatePercent']);
        expect(rows(element)[0].querySelector('[data-id="remove-item"]')).not.toBeNull();
        expect(rows(element)[1]).toBeDefined();
    });

    it('adds the next line as soon as a price is typed, and only one', async () => {
        const element = createQuickBillElement();
        await flushPromises();

        await typeCell(element, 0, 'description', 'Wheel alignment');
        expect(rows(element)).toHaveLength(1);

        await typeCell(element, 0, 'unitPrice', '6');
        expect(rows(element)).toHaveLength(2);

        await typeCell(element, 0, 'unitPrice', '60');
        await typeCell(element, 0, 'unitPrice', '600');
        expect(rows(element)).toHaveLength(2);
        expect(cell(element, 1, 'description').value).toBe('');
        expect(cell(element, 1, 'taxRatePercent').value).toBe('18');
        // The box being typed in isn't rewritten as the row list changes.
        expect(cell(element, 0, 'unitPrice').value).toBe('600');

        await typeCell(element, 1, 'description', 'Car wash');
        await typeCell(element, 1, 'unitPrice', '200');
        expect(rows(element)).toHaveLength(3);
    });

    it('with GST off: the GST box is skipped, totals have no tax, and the bill says so', async () => {
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await switchToWalkIn(element);

        expect(cell(element, 0, 'taxRatePercent').disabled).toBe(true);
        await typeCell(element, 0, 'description', 'Wheel alignment');
        await typeCell(element, 0, 'quantity', '2');
        await typeCell(element, 0, 'unitPrice', '500');

        expect($(element, '[data-id="grand-total"]').textContent).toBe('₹1,000.00');
        expect($(element, '[data-id="line-amount"]').textContent).toBe('₹1,000.00');
        expect(element.shadowRoot.textContent).not.toContain('CGST');
        expect($(element, '[data-id="gst-excluded"]')).not.toBeNull();

        $(element, '[data-id="create"]').click();
        await flushPromises();

        const { request } = createQuickBill.mock.calls[0][0];
        expect(request.includeGst).toBe(false);
        expect(request).toEqual(expect.objectContaining({ isWalkIn: true, customerPhone: null, vehicleId: null, newVehicle: null }));
        // Sent with the typed rate: Apex keeps it for a newly created part and zeroes the bill's line.
        expect(request.lineItems).toEqual([
            expect.objectContaining({ partId: null, description: 'Wheel alignment', quantity: 2, unitPrice: 500, taxRatePercent: 18 })
        ]);
        expect($(element, '[data-id="created-number"]').textContent).toBe('INV/2026-27/0042');
    });

    it('with GST on: each line uses its own rate and totals include it', async () => {
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await setGst(element, true);
        expect(cell(element, 0, 'taxRatePercent').disabled).toBe(false);

        await typeCell(element, 0, 'description', 'Wheel alignment');
        await typeCell(element, 0, 'unitPrice', '1000');
        expect($(element, '[data-id="grand-total"]').textContent).toBe('₹1,180.00');
        expect(element.shadowRoot.textContent).toContain('CGST');
        expect($(element, '[data-id="gst-excluded"]')).toBeNull();

        await typeCell(element, 0, 'taxRatePercent', '5');
        expect($(element, '[data-id="grand-total"]').textContent).toBe('₹1,050.00');

        $(element, '[data-id="create"]').click();
        await flushPromises();
        const { request } = createQuickBill.mock.calls[0][0];
        expect(request.includeGst).toBe(true);
        expect(request.lineItems[0].taxRatePercent).toBe(5);
    });

    it('never sends the empty last line, and asks for what a started line is missing', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);

        await typeCell(element, 0, 'unitPrice', '500');
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('name');
        await typeCell(element, 0, 'description', 'Wheel alignment');
        expect($(element, '[data-id="create"]').disabled).toBe(false);

        await typeCell(element, 1, 'description', 'Car wash');
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('price');
        await typeCell(element, 1, 'description', '');
        expect($(element, '[data-id="create"]').disabled).toBe(false);
        expect($(element, '[data-id="grand-total"]').textContent).toBe('₹500.00');
    });

    it('typing a name suggests parts; arrow keys and Enter pick one and move to quantity', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await typeName(element, 0, 'e', [BRAKE_PAD, OIL]);
        expect($(element, '[data-id="suggestions"]')).toBeNull();

        await typeName(element, 0, 'en', [BRAKE_PAD, OIL]);
        expect(grid(element).querySelectorAll('[data-id="suggestion"]')).toHaveLength(2);

        const name = cell(element, 0, 'description');
        pressKey(name, 'ArrowDown');
        pressKey(name, 'ArrowDown');
        await flushPromises();
        expect(grid(element).querySelectorAll('[data-id="suggestion"]')[1].getAttribute('aria-selected')).toBe('true');

        pressKey(name, 'Enter');
        await flushPromises();

        expect($(element, '[data-id="suggestions"]')).toBeNull();
        expect(cell(element, 0, 'description').value).toBe('Engine Oil 1L');
        expect(cell(element, 0, 'unitPrice').value).toBe('500');
        expect(rows(element)).toHaveLength(2);
        expect(grid(element).activeElement).toBe(cell(element, 0, 'quantity'));
    });

    it('Tab on a highlighted suggestion picks it; Escape closes the list and keeps the typing', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await typeName(element, 0, 'brake', [BRAKE_PAD]);

        pressKey(cell(element, 0, 'description'), 'Escape');
        await flushPromises();
        expect($(element, '[data-id="suggestions"]')).toBeNull();
        expect(cell(element, 0, 'description').value).toBe('brake');

        await typeName(element, 0, 'brake p', [BRAKE_PAD]);
        pressKey(cell(element, 0, 'description'), 'ArrowDown');
        await flushPromises();
        pressKey(cell(element, 0, 'description'), 'Tab');
        await flushPromises();

        expect(cell(element, 0, 'description').value).toBe('Brake Pad Set');
        expect(cell(element, 0, 'taxRatePercent').value).toBe('28');
    });

    it('a tapped suggestion fills the line, and warns when quantity exceeds stock', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await typeName(element, 0, 'brake', [BRAKE_PAD]);

        $(element, '[data-id="suggestion"]').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
        await flushPromises();
        expect(cell(element, 0, 'unitPrice').value).toBe('1200');
        expect($(element, '[data-id="stock-note"]')).toBeNull();

        await typeCell(element, 0, 'quantity', '3');
        expect($(element, '[data-id="stock-note"]').textContent).toBe('Only 1 in stock');
    });

    it('picking a part already on the bill adds one to that line', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await typeName(element, 0, 'oil', [OIL]);
        $(element, '[data-id="suggestion"]').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
        await flushPromises();

        await typeName(element, 1, 'oil', [OIL]);
        $(element, '[data-id="suggestion"]').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
        await flushPromises();

        expect(rows(element)).toHaveLength(2);
        expect(cell(element, 0, 'quantity').value).toBe('2');
        expect(cell(element, 1, 'description').value).toBe('');
        expect(grid(element).activeElement).toBe(cell(element, 1, 'description'));
    });

    it('a part name typed in full and tabbed past links to that part, keeping a typed price', async () => {
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await switchToWalkIn(element);

        await typeName(element, 0, 'engine oil 1l', [OIL]);
        await typeCell(element, 0, 'unitPrice', '450');
        cell(element, 0, 'description').dispatchEvent(new CustomEvent('blur'));
        await flushPromises();

        expect(cell(element, 0, 'description').value).toBe('Engine Oil 1L');
        expect(cell(element, 0, 'unitPrice').value).toBe('450');

        $(element, '[data-id="create"]').click();
        await flushPromises();
        expect(createQuickBill.mock.calls[0][0].request.lineItems[0].partId).toBe('part2');
    });

    it('a name that only partly matches stays a typed item', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);

        await typeName(element, 0, 'oil', [OIL]);
        cell(element, 0, 'description').dispatchEvent(new CustomEvent('blur'));
        await flushPromises();

        expect(cell(element, 0, 'description').value).toBe('oil');
        expect($(element, '[data-id="suggestions"]')).toBeNull();
    });

    it('changing the name of a picked part unlinks it', async () => {
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await typeName(element, 0, 'oil', [OIL]);
        $(element, '[data-id="suggestion"]').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
        await flushPromises();

        await typeName(element, 0, 'Engine Oil 5L', []);
        $(element, '[data-id="create"]').click();
        await flushPromises();

        expect(createQuickBill.mock.calls[0][0].request.lineItems[0]).toEqual(
            expect.objectContaining({ partId: null, description: 'Engine Oil 5L', unitPrice: 500 })
        );
    });

    it('Ctrl+Enter from the grid creates the bill; plain Enter in a number box does not', async () => {
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await typeCell(element, 0, 'description', 'Wheel alignment');
        await typeCell(element, 0, 'unitPrice', '600');

        pressKey(cell(element, 0, 'unitPrice'), 'Enter');
        await flushPromises();
        expect(createQuickBill).not.toHaveBeenCalled();

        pressKey(cell(element, 0, 'unitPrice'), 'Enter', { ctrlKey: true });
        await flushPromises();
        expect(createQuickBill).toHaveBeenCalledTimes(1);
    });

    it('removing the only filled line leaves one empty line and disables Create', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await typeCell(element, 0, 'description', 'Wheel alignment');
        await typeCell(element, 0, 'unitPrice', '600');
        expect($(element, '[data-id="create"]').disabled).toBe(false);

        $(element, '[data-id="remove-item"]').click();
        await flushPromises();

        expect(rows(element)).toHaveLength(1);
        expect($(element, '[data-id="create"]').disabled).toBe(true);
    });

    it('typing a known phone number finds the customer and offers their vehicles', async () => {
        findCustomerByPhone.mockResolvedValue({
            id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111',
            vehicles: [{ id: 'veh1', registrationNumber: 'MP09AB1234' }, { id: 'veh2', registrationNumber: 'MP09CD5678' }]
        });
        createQuickBill.mockResolvedValue({ ...SUMMARY, customerName: 'Ramesh Kumar' });
        const element = createQuickBillElement();
        await flushPromises();

        type(element, 'lightning-input[data-field="phone"]', '9000011111');
        await wait(450);
        await flushPromises();

        expect(findCustomerByPhone).toHaveBeenCalledWith({ phone: '9000011111' });
        expect($(element, '[data-id="match-banner"]').textContent).toContain('Ramesh Kumar');
        expect($(element, 'lightning-input[data-field="name"]').value).toBe('Ramesh Kumar');
        expect($(element, 'lightning-input[data-field="name"]').disabled).toBe(true);

        const chips = element.shadowRoot.querySelectorAll('[data-id="vehicle-chip"]');
        expect([...chips].map((c) => c.label)).toEqual(['MP09AB1234', 'MP09CD5678', 'Other vehicle', 'No vehicle']);
        chips[1].click();
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('[data-id="vehicle-chip"]')[1].variant).toBe('brand');

        await typeCell(element, 0, 'description', 'Wheel alignment');
        await typeCell(element, 0, 'unitPrice', '600');
        $(element, '[data-id="create"]').click();
        await flushPromises();

        const { request } = createQuickBill.mock.calls[0][0];
        expect(request).toEqual(expect.objectContaining({ isWalkIn: false, customerPhone: '9000011111', vehicleId: 'veh2', newVehicle: null }));
    });

    it('a new customer can be billed with a typed vehicle', async () => {
        findCustomerByPhone.mockResolvedValue(null);
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await flushPromises();

        type(element, 'lightning-input[data-field="phone"]', '9826011111');
        await wait(450);
        await flushPromises();
        expect($(element, '[data-id="match-banner"]')).toBeNull();
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('name');

        type(element, 'lightning-input[data-field="name"]', 'Suresh Patel');
        type(element, 'lightning-input[data-field="registrationNumber"]', 'MP09ZZ0001');
        await typeCell(element, 0, 'description', 'Wheel alignment');
        await typeCell(element, 0, 'unitPrice', '600');

        $(element, '[data-id="create"]').click();
        await flushPromises();

        const { request } = createQuickBill.mock.calls[0][0];
        expect(request.customerName).toBe('Suresh Patel');
        expect(request.vehicleId).toBeNull();
        expect(request.newVehicle).toEqual({ registrationNumber: 'MP09ZZ0001', make: '', model: '' });
    });

    it('after creating: Print previews, View Bill navigates, New Quick Bill resets with GST back off', async () => {
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await setGst(element, true);
        await typeCell(element, 0, 'description', 'Wheel alignment');
        await typeCell(element, 0, 'unitPrice', '600');
        $(element, '[data-id="create"]').click();
        await flushPromises();

        $(element, '[data-id="print"]').click();
        await flushPromises();
        expect($(element, 'c-document-preview').recordId).toBe('bill1');

        $(element, '[data-id="view-document"]').click();
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage', attributes: { apiName: 'Bill_Detail' }, state: { c__recordId: 'bill1' }
        });

        $(element, '[data-id="new-document"]').click();
        await flushPromises();
        expect($(element, '[data-id="created-number"]')).toBeNull();
        expect(rows(element)).toHaveLength(1);
        expect(cell(element, 0, 'description').value).toBe('');
        expect($(element, '[data-id="include-gst"]').checked).toBe(false);
        expect($(element, '[data-id="mode"]').value).toBe('walkin');
        expect(grid(element).activeElement).toBe(cell(element, 0, 'description'));
    });

    it('scanning a barcode fills the empty line with the matching part', async () => {
        mockScanner.isAvailable.mockReturnValue(true);
        mockScanner.beginCapture.mockResolvedValue({ value: '8901234567890' });
        searchParts.mockResolvedValue([BRAKE_PAD, OIL]);
        const element = createQuickBillElement();
        await flushPromises();

        $(element, '[data-id="scan"]').click();
        await flushPromises();
        await flushPromises();

        expect(getBarcodeScanner).toHaveBeenCalled();
        expect(searchParts).toHaveBeenCalledWith({ searchTerm: '8901234567890' });
        expect(cell(element, 0, 'description').value).toBe('Brake Pad Set');
        expect(rows(element)).toHaveLength(2);
        expect(mockScanner.endCapture).toHaveBeenCalled();
        mockScanner.isAvailable.mockReturnValue(false);
    });

    describe('in estimate mode', () => {
        const ESTIMATE = { estimateId: 'est1', estimateNumber: 'EST-0042', customerName: 'Walk-in Customer', totalAmount: 600 };

        function createEstimateScreen() {
            const element = createElement('c-quick-bill', { is: QuickBill });
            element.documentType = 'estimate';
            document.body.appendChild(element);
            return element;
        }

        it('says estimate throughout, with no mention of a bill', async () => {
            const element = createEstimateScreen();
            await switchToWalkIn(element);

            const text = element.shadowRoot.textContent;
            expect(text).toContain('Quick Estimate');
            expect(text).toContain('The estimate is issued to');
            expect(text).toContain('Estimate date & notes');
            expect(text).toContain('Ctrl+Enter creates the estimate.');
            expect(text.toLowerCase()).not.toContain('bill');
            expect($(element, '[data-id="create"]').label).toBe('Create Estimate');
        });

        it('has the same one-line keyboard grid, with GST off by default', async () => {
            const element = createEstimateScreen();
            await switchToWalkIn(element);

            expect([...rows(element)[0].querySelectorAll('input')].map((i) => i.dataset.field)).toEqual(['description', 'quantity', 'unitPrice', 'taxRatePercent']);
            expect(cell(element, 0, 'taxRatePercent').disabled).toBe(true);
            await typeCell(element, 0, 'description', 'Wheel alignment');
            await typeCell(element, 0, 'unitPrice', '600');
            expect(rows(element)).toHaveLength(2);
            expect($(element, '[data-id="grand-total"]').textContent).toBe('₹600.00');

            await setGst(element, true);
            expect($(element, '[data-id="grand-total"]').textContent).toBe('₹708.00');
        });

        it('creates an estimate, not a bill, and sends the date as the estimate date', async () => {
            createQuickEstimate.mockResolvedValue(ESTIMATE);
            const element = createEstimateScreen();
            await switchToWalkIn(element);
            await typeCell(element, 0, 'description', 'Wheel alignment');
            await typeCell(element, 0, 'unitPrice', '600');

            $(element, '[data-id="create"]').click();
            await flushPromises();

            expect(createQuickBill).not.toHaveBeenCalled();
            const { request } = createQuickEstimate.mock.calls[0][0];
            expect(request).toEqual(expect.objectContaining({ isWalkIn: true, includeGst: false }));
            expect(request.documentDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
            expect(request.lineItems).toHaveLength(1);
        });

        it('after creating: previews the estimate, opens Estimate Details, and starts a new one', async () => {
            createQuickEstimate.mockResolvedValue(ESTIMATE);
            const element = createEstimateScreen();
            await switchToWalkIn(element);
            await typeCell(element, 0, 'description', 'Wheel alignment');
            await typeCell(element, 0, 'unitPrice', '600');
            $(element, '[data-id="create"]').click();
            await flushPromises();

            expect($(element, '[data-id="created-number"]').textContent).toBe('EST-0042');
            expect(element.shadowRoot.textContent).toContain('Estimate created');
            expect($(element, '[data-id="view-document"]').label).toBe('View Estimate');
            expect($(element, '[data-id="new-document"]').label).toBe('New Quick Estimate');

            $(element, '[data-id="print"]').click();
            await flushPromises();
            const preview = $(element, 'c-document-preview');
            expect(preview.recordId).toBe('est1');
            expect(preview.heading).toBe('EST-0042');

            $(element, '[data-id="view-document"]').click();
            expect(mockNavigate).toHaveBeenCalledWith({
                type: 'standard__navItemPage', attributes: { apiName: 'Estimate_Detail' }, state: { c__recordId: 'est1' }
            });

            $(element, '[data-id="new-document"]').click();
            await flushPromises();
            expect($(element, '[data-id="created-number"]')).toBeNull();
            expect(rows(element)).toHaveLength(1);
        });

        it('does not warn about stock, since a quote takes none', async () => {
            const element = createEstimateScreen();
            await switchToWalkIn(element);
            await typeName(element, 0, 'brake', [BRAKE_PAD]);
            $(element, '[data-id="suggestion"]').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
            await flushPromises();

            await typeCell(element, 0, 'quantity', '3');
            expect($(element, '[data-id="stock-note"]')).toBeNull();
        });
    });
});
