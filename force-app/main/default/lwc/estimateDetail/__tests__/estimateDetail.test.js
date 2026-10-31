import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import EstimateDetail from 'c/estimateDetail';
import getEstimateSummary from '@salesforce/apex/EstimateController.getEstimateSummary';

jest.mock('@salesforce/apex/EstimateController.getEstimateSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });

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

const SUMMARY = {
    estimateId: 'a02xx0000000001',
    estimateNumber: 'EST-0005',
    status: 'Draft',
    estimateDate: '2026-10-01',
    customerName: 'Ramesh Kumar',
    billToPartyName: null,
    notes: '',
    subtotal: 500,
    cgst: 45,
    sgst: 45,
    igst: 0,
    totalAmount: 590,
    lineItems: [
        { description: 'Diagnostic Fee', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', hsnSacCode: '', unitLabel: '' }
    ]
};

function createDetail(recordId, extraState) {
    const element = createElement('c-estimate-detail', { is: EstimateDetail });
    document.body.appendChild(element);
    CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: recordId, ...extraState } });
    return element;
}

describe('c-estimate-detail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads the estimate from the page reference and renders a read-only view', async () => {
        getEstimateSummary.mockResolvedValue(SUMMARY);

        const element = createDetail('a02xx0000000001');
        await flushPromises();

        expect(getEstimateSummary).toHaveBeenCalledWith({ estimateId: 'a02xx0000000001' });
        expect(element.shadowRoot.textContent).toContain('EST-0005');
        expect(element.shadowRoot.textContent).toContain('Diagnostic Fee');
        expect(element.shadowRoot.querySelectorAll('[data-field]')).toHaveLength(0);
    });

    it('shows the vehicle when the estimate has one', async () => {
        getEstimateSummary.mockResolvedValue({ ...SUMMARY, vehicleId: 'a06xx0000000001', vehicleLabel: 'MH12AB1234 — Honda City' });
        const element = createDetail('a02xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Vehicle:');
        expect(element.shadowRoot.textContent).toContain('MH12AB1234 — Honda City');
    });

    it('shows the chassis number when the vehicle has one', async () => {
        getEstimateSummary.mockResolvedValue({
            ...SUMMARY,
            vehicleId: 'a06xx0000000001',
            vehicleLabel: 'MH12AB1234 — Honda City',
            vehicleChassisNumber: 'MA3ERLF1S00123456'
        });
        const element = createDetail('a02xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Chassis No.:');
        expect(element.shadowRoot.textContent).toContain('MA3ERLF1S00123456');
    });

    it('omits the chassis number line when the vehicle has none', async () => {
        getEstimateSummary.mockResolvedValue({ ...SUMMARY, vehicleId: 'a06xx0000000001', vehicleLabel: 'MH12AB1234 — Honda City' });
        const element = createDetail('a02xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('Chassis No.:');
    });

    it('offers Create Bill for a Draft estimate but not a Converted one', async () => {
        getEstimateSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a02xx0000000001');
        await flushPromises();
        expect(element.shadowRoot.querySelector('[data-id="create-bill"]')).not.toBeNull();

        document.body.removeChild(element);
        getEstimateSummary.mockResolvedValue({ ...SUMMARY, status: 'Converted' });
        const convertedElement = createDetail('a02xx0000000001');
        await flushPromises();
        expect(convertedElement.shadowRoot.querySelector('[data-id="create-bill"]')).toBeNull();
    });

    it('Create Bill navigates to New_Bill carrying the source estimate id and the originating customer', async () => {
        getEstimateSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a02xx0000000001', { c__fromCustomerId: 'cust1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="create-bill"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'New_Bill' },
            state: { c__sourceEstimateId: 'a02xx0000000001', c__fromCustomerId: 'cust1' }
        });
    });

    it('Back returns to the originating customer when the estimate was opened from one', async () => {
        getEstimateSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a02xx0000000001', { c__fromCustomerId: 'cust1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_Detail' },
            state: { c__customerId: 'cust1' }
        });
    });

    it('Back falls back to the Customer list when the estimate was not opened from a customer', async () => {
        getEstimateSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a02xx0000000001');
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_List' }
        });
    });

    it('Edit carries the originating customer id forward', async () => {
        getEstimateSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a02xx0000000001', { c__fromCustomerId: 'cust1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="edit"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'New_Estimate' },
            state: { c__recordId: 'a02xx0000000001', c__fromCustomerId: 'cust1' }
        });
    });

    it('navigating to a different estimate in the same tab reloads the new record, not the stale one', async () => {
        getEstimateSummary.mockResolvedValueOnce(SUMMARY);
        const element = createDetail('a02xx0000000001');
        await flushPromises();
        expect(element.shadowRoot.textContent).toContain('EST-0005');

        const NEW_VERSION_SUMMARY = { ...SUMMARY, estimateId: 'a02xx0000000002', estimateNumber: 'EST-0006' };
        getEstimateSummary.mockResolvedValueOnce(NEW_VERSION_SUMMARY);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: 'a02xx0000000002' } });
        await flushPromises();

        expect(getEstimateSummary).toHaveBeenCalledWith({ estimateId: 'a02xx0000000002' });
        expect(element.shadowRoot.textContent).toContain('EST-0006');
        expect(element.shadowRoot.textContent).not.toContain('EST-0005');
    });

    it('Print opens the document preview popup for this estimate', async () => {
        getEstimateSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a02xx0000000001');
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="print"]').click();
        await flushPromises();

        const preview = element.shadowRoot.querySelector('c-document-preview');
        expect(preview.recordId).toBe('a02xx0000000001');
    });
});
