import { createElement } from 'lwc';
import QuickBill from 'c/quickBill';
import findCustomerByPhone from '@salesforce/apex/QuickBillController.findCustomerByPhone';
import createQuickBill from '@salesforce/apex/QuickBillController.createQuickBill';
import searchParts from '@salesforce/apex/BillController.searchParts';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';

jest.mock('@salesforce/apex/QuickBillController.findCustomerByPhone', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.createQuickBill', () => ({ default: jest.fn() }), { virtual: true });
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
    taxRatePercent: 18, gstType: 'CGST_SGST', hsnCode: '8708', unitLabel: 'Set', currentStock: 1
};
const OIL = { id: 'part2', name: 'Engine Oil 1L', sku: 'OIL-1', price: 500, taxRatePercent: 18, gstType: 'CGST_SGST', currentStock: 20 };

const SUMMARY = { billId: 'bill1', invoiceNumber: 'INV/2026-27/0042', customerName: 'Walk-in Customer', totalAmount: 1416 };

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

function $(element, selector) {
    return element.shadowRoot.querySelector(selector);
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

async function searchAndPick(element, term, results, partId) {
    searchParts.mockResolvedValue(results);
    type(element, '[data-id="part-search"]', term);
    await wait(350);
    await flushPromises();
    $(element, `button.part-result[data-id="${partId}"]`).click();
    await flushPromises();
}

describe('c-quick-bill', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('starts in Customer mode with an empty cart and explains what is missing', async () => {
        const element = createQuickBillElement();
        await flushPromises();

        expect($(element, '[data-id="mode"]').value).toBe('customer');
        expect($(element, '[data-id="create"]').disabled).toBe(true);
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('phone number');
        expect(element.shadowRoot.textContent).toContain('Search a part above');
    });

    it('a walk-in parts sale: search, tap twice to add quantity 2, and create the bill', async () => {
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        expect(element.shadowRoot.textContent).toContain('Walk-in Customer');

        searchParts.mockResolvedValue([OIL]);
        type(element, '[data-id="part-search"]', 'oil');
        await wait(350);
        await flushPromises();
        $(element, 'button.part-result[data-id="part2"]').click();
        await flushPromises();

        type(element, '[data-id="part-search"]', 'oil');
        await wait(350);
        await flushPromises();
        $(element, 'button.part-result[data-id="part2"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('[data-id="item-row"]')).toHaveLength(1);
        expect($(element, 'lightning-input[data-field="quantity"]').value).toBe(2);
        expect($(element, '[data-id="grand-total"]').textContent).toBe('₹1,180.00');
        expect($(element, '[data-id="create"]').disabled).toBe(false);

        $(element, '[data-id="create"]').click();
        await flushPromises();

        const { request } = createQuickBill.mock.calls[0][0];
        expect(request).toEqual(expect.objectContaining({ isWalkIn: true, customerPhone: null, vehicleId: null, newVehicle: null }));
        expect(request.lineItems).toEqual([
            expect.objectContaining({ partId: 'part2', description: 'Engine Oil 1L', quantity: 2, unitPrice: 500, taxRatePercent: 18 })
        ]);
        expect($(element, '[data-id="created-number"]').textContent).toBe('INV/2026-27/0042');
    });

    it('stepper buttons change quantity and warn when it exceeds stock', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await searchAndPick(element, 'brake', [BRAKE_PAD], 'part1');

        expect(element.shadowRoot.textContent).toContain('1 in stock');
        expect(element.shadowRoot.textContent).not.toContain('not enough stock');
        expect($(element, '[data-id="decrease"]').disabled).toBe(true);

        $(element, '[data-id="increase"]').click();
        await flushPromises();
        expect($(element, 'lightning-input[data-field="quantity"]').value).toBe(2);
        expect(element.shadowRoot.textContent).toContain('not enough stock');

        $(element, '[data-id="decrease"]').click();
        await flushPromises();
        expect($(element, 'lightning-input[data-field="quantity"]').value).toBe(1);
    });

    it('a custom item needs a name and price before the bill can be created', async () => {
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await switchToWalkIn(element);

        $(element, '[data-id="add-custom"]').click();
        await flushPromises();
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('name');

        type(element, 'lightning-input[data-field="description"]', 'Wheel alignment');
        await flushPromises();
        expect($(element, '[data-id="missing-reason"]').textContent).toContain('price');

        type(element, 'lightning-input[data-field="unitPrice"]', '600');
        $(element, 'lightning-combobox[data-field="taxRatePercent"]').dispatchEvent(new CustomEvent('change', { detail: { value: '5' } }));
        await flushPromises();
        expect($(element, '[data-id="grand-total"]').textContent).toBe('₹630.00');

        $(element, '[data-id="create"]').click();
        await flushPromises();
        expect(createQuickBill.mock.calls[0][0].request.lineItems[0]).toEqual(
            expect.objectContaining({ partId: null, description: 'Wheel alignment', unitPrice: 600, taxRatePercent: 5 })
        );
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

        await searchAndPick(element, 'brake', [BRAKE_PAD], 'part1');
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
        await searchAndPick(element, 'oil', [OIL], 'part2');

        $(element, '[data-id="create"]').click();
        await flushPromises();

        const { request } = createQuickBill.mock.calls[0][0];
        expect(request.customerName).toBe('Suresh Patel');
        expect(request.vehicleId).toBeNull();
        expect(request.newVehicle).toEqual({ registrationNumber: 'MP09ZZ0001', make: '', model: '' });
    });

    it('after creating: Print opens the invoice preview, View Bill navigates, New Quick Bill resets', async () => {
        createQuickBill.mockResolvedValue(SUMMARY);
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await searchAndPick(element, 'oil', [OIL], 'part2');
        $(element, '[data-id="create"]').click();
        await flushPromises();

        $(element, '[data-id="print"]').click();
        await flushPromises();
        expect($(element, 'c-document-preview').recordId).toBe('bill1');

        $(element, '[data-id="view-bill"]').click();
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage', attributes: { apiName: 'Bill_Detail' }, state: { c__recordId: 'bill1' }
        });

        $(element, '[data-id="new-bill"]').click();
        await flushPromises();
        expect($(element, '[data-id="created-number"]')).toBeNull();
        expect(element.shadowRoot.querySelectorAll('[data-id="item-row"]')).toHaveLength(0);
        expect($(element, '[data-id="mode"]').value).toBe('walkin');
    });

    it('scanning a barcode adds the matching part', async () => {
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
        const rows = element.shadowRoot.querySelectorAll('[data-id="item-row"]');
        expect(rows).toHaveLength(1);
        expect(rows[0].textContent).toContain('Brake Pad Set');
        expect(mockScanner.endCapture).toHaveBeenCalled();
        mockScanner.isAvailable.mockReturnValue(false);
    });

    it('removing the only item disables Create again', async () => {
        const element = createQuickBillElement();
        await switchToWalkIn(element);
        await searchAndPick(element, 'oil', [OIL], 'part2');
        expect($(element, '[data-id="create"]').disabled).toBe(false);

        $(element, '[data-id="remove-item"]').click();
        await flushPromises();
        expect($(element, '[data-id="create"]').disabled).toBe(true);
    });
});
