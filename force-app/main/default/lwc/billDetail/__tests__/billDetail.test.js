import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import BillDetail from 'c/billDetail';
import getBillSummary from '@salesforce/apex/BillController.getBillSummary';
import cancelBill from '@salesforce/apex/BillController.cancelBill';
// Record Payment feature disabled (2026-10) — uncomment alongside billDetail.js/.html to restore.
// import recordPayment from '@salesforce/apex/BillController.recordPayment';

jest.mock('@salesforce/apex/BillController.getBillSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.recordPayment', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.cancelBill', () => ({ default: jest.fn() }), { virtual: true });
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
    billId: 'a01xx0000000001',
    invoiceNumber: 'INV/2026-27/0002',
    financialYear: '2026-27',
    status: 'Partial',
    billDate: '2026-09-21',
    customerName: 'Papa',
    billToPartyName: null,
    notes: 'Renault Triber 2026',
    subtotal: 10285,
    cgst: 925.65,
    sgst: 925.65,
    igst: 0,
    totalAmount: 12136.3,
    lineItems: [
        { description: 'Bumper', quantity: 1, unitPrice: 500, taxRatePercent: 18, gstType: 'CGST_SGST', hsnSacCode: '8708', unitLabel: 'Pcs' }
    ],
    payments: [{ id: 'pay1', amount: 590, method: 'Cash', paidAt: '2026-09-21 19:50' }],
    amountPaid: 590,
    amountDue: 11546.3
};

function createDetail(recordId, extraState) {
    const element = createElement('c-bill-detail', { is: BillDetail });
    document.body.appendChild(element);
    CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: recordId, ...extraState } });
    return element;
}

describe('c-bill-detail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads the bill from the page reference and renders a read-only view', async () => {
        getBillSummary.mockResolvedValue(SUMMARY);

        const element = createDetail('a01xx0000000001');
        await flushPromises();

        expect(getBillSummary).toHaveBeenCalledWith({ billId: 'a01xx0000000001' });
        expect(element.shadowRoot.textContent).toContain('INV/2026-27/0002');
        expect(element.shadowRoot.textContent).toContain('Papa');
        expect(element.shadowRoot.textContent).toContain('Bumper');
        // Read-only — no editable line-item inputs on this screen.
        expect(element.shadowRoot.querySelectorAll('[data-field]')).toHaveLength(0);
    });

    it('shows the vehicle when the bill has one', async () => {
        getBillSummary.mockResolvedValue({ ...SUMMARY, vehicleId: 'a06xx0000000001', vehicleLabel: 'MH12AB1234 — Honda City' });
        const element = createDetail('a01xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Vehicle:');
        expect(element.shadowRoot.textContent).toContain('MH12AB1234 — Honda City');
    });

    it('shows the chassis number when the vehicle has one', async () => {
        getBillSummary.mockResolvedValue({
            ...SUMMARY,
            vehicleId: 'a06xx0000000001',
            vehicleLabel: 'MH12AB1234 — Honda City',
            vehicleChassisNumber: 'MA3ERLF1S00123456'
        });
        const element = createDetail('a01xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Chassis No.:');
        expect(element.shadowRoot.textContent).toContain('MA3ERLF1S00123456');
    });

    it('omits the chassis number line when the vehicle has none', async () => {
        getBillSummary.mockResolvedValue({ ...SUMMARY, vehicleId: 'a06xx0000000001', vehicleLabel: 'MH12AB1234 — Honda City' });
        const element = createDetail('a01xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('Chassis No.:');
    });

    it('omits the vehicle line for an older bill with none recorded', async () => {
        getBillSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a01xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('Vehicle:');
    });

    it('falls back to the customer name as Bill To when no bill-to party is set', async () => {
        getBillSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a01xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Bill To:');
        expect(element.shadowRoot.textContent).toContain('Papa');
    });

    // Record Payment feature disabled (2026-10) — uncomment alongside billDetail.js/.html to restore.
    // it('recording a payment calls recordPayment and refreshes the view with the response', async () => {
    //     getBillSummary.mockResolvedValue(SUMMARY);
    //     recordPayment.mockResolvedValue({ ...SUMMARY, status: 'Paid', amountPaid: 12136.3, amountDue: 0, payments: [...SUMMARY.payments, { id: 'pay2', amount: 11546.3, method: 'Cash', paidAt: 'now' }] });
    //
    //     const element = createDetail('a01xx0000000001');
    //     await flushPromises();
    //
    //     element.shadowRoot.querySelector('[data-id="record-payment"]').click();
    //     await flushPromises();
    //
    //     element.shadowRoot.querySelector('[data-id="submit-payment"]').click();
    //     await flushPromises();
    //
    //     expect(recordPayment).toHaveBeenCalledWith({ billId: 'a01xx0000000001', amount: 11546.3, method: 'Cash' });
    //     expect(element.shadowRoot.textContent).toContain('Due: ₹0');
    // });

    it('Print opens the document preview popup for this bill', async () => {
        getBillSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a01xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-document-preview')).toBeNull();
        element.shadowRoot.querySelector('[data-id="print"]').click();
        await flushPromises();

        const preview = element.shadowRoot.querySelector('c-document-preview');
        expect(preview.recordId).toBe('a01xx0000000001');
    });

    it('navigating to a different bill in the same tab reloads the new record, not the stale one', async () => {
        getBillSummary.mockResolvedValueOnce(SUMMARY);
        const element = createDetail('a01xx0000000001');
        await flushPromises();
        expect(element.shadowRoot.textContent).toContain('INV/2026-27/0002');

        const NEW_VERSION_SUMMARY = { ...SUMMARY, billId: 'a01xx0000000002', invoiceNumber: 'INV/2026-27/0005' };
        getBillSummary.mockResolvedValueOnce(NEW_VERSION_SUMMARY);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: 'a01xx0000000002' } });
        await flushPromises();

        expect(getBillSummary).toHaveBeenCalledWith({ billId: 'a01xx0000000002' });
        expect(element.shadowRoot.textContent).toContain('INV/2026-27/0005');
        expect(element.shadowRoot.textContent).not.toContain('INV/2026-27/0002');
    });

    it('Back returns to the originating customer when the bill was opened from one', async () => {
        getBillSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a01xx0000000001', { c__fromCustomerId: 'cust1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_Detail' },
            state: { c__customerId: 'cust1' }
        });
    });

    it('Back falls back to the Billing list when the bill was not opened from a customer', async () => {
        getBillSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a01xx0000000001');
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Billing_List' }
        });
    });

    it('Edit carries the originating customer id forward so Bill Detail can still go back there after saving', async () => {
        getBillSummary.mockResolvedValue(SUMMARY);
        const element = createDetail('a01xx0000000001', { c__fromCustomerId: 'cust1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="edit"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'New_Bill' },
            state: { c__recordId: 'a01xx0000000001', c__fromCustomerId: 'cust1' }
        });
    });

    describe('deleting', () => {
        function confirmDelete(element) {
            const confirm = element.shadowRoot.querySelector('c-delete-confirm');
            confirm.dispatchEvent(new CustomEvent('confirm'));
        }

        it('Delete Bill asks, then cancels the bill and shows it as deleted', async () => {
            getBillSummary.mockResolvedValue(SUMMARY);
            cancelBill.mockResolvedValue({ ...SUMMARY, isCancelled: true, cancelledOn: '2026-11-21' });
            const element = createDetail('a01xx0000000001');
            await flushPromises();
            const confirm = element.shadowRoot.querySelector('c-delete-confirm');
            expect(confirm.buttonLabel).toBe('Delete Bill');
            expect(confirm.message).toContain('number is kept and shown as cancelled');

            confirmDelete(element);
            await flushPromises();

            expect(cancelBill).toHaveBeenCalledWith({ billId: 'a01xx0000000001' });
            expect(element.shadowRoot.querySelector('[data-id="cancelled-note"]').textContent).toContain('Deleted on 2026-11-21');
            expect(element.shadowRoot.querySelector('c-delete-confirm')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="edit"]').disabled).toBe(true);
        });

        it('a bill in a month whose GST is filed says so, and can\'t be changed or deleted', async () => {
            getBillSummary.mockResolvedValue({ ...SUMMARY, isGstFiled: true, gstFiledUpTo: '2026-10-31' });
            const element = createDetail('a01xx0000000001');
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="filed-note"]').textContent).toContain('filed up to October 2026');
            expect(element.shadowRoot.querySelector('c-delete-confirm')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="edit"]').disabled).toBe(true);
        });

        it('a refused delete shows why, and leaves the bill as it was', async () => {
            getBillSummary.mockResolvedValue(SUMMARY);
            cancelBill.mockRejectedValue({ body: { message: 'GST returns are filed up to October 2026' } });
            const element = createDetail('a01xx0000000001');
            const toasts = [];
            element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
            await flushPromises();

            confirmDelete(element);
            await flushPromises();

            expect(toasts[0].message).toContain('filed up to October 2026');
            expect(element.shadowRoot.querySelector('[data-id="cancelled-note"]')).toBeNull();
        });
    });

    it('shows a line\'s discount, the round-off, and links an insurance claim\'s other bill (G5/G6)', async () => {
        getBillSummary.mockResolvedValue({
            ...SUMMARY,
            billToPartyId: 'party1',
            billToPartyName: 'ICICI Lombard',
            roundOff: -0.3,
            totalAmount: 12136,
            pairedBillId: 'a01xx0000000002',
            pairedInvoiceNumber: 'INV/2026-27/0003',
            lineItems: [{ ...SUMMARY.lineItems[0], discount: 250 }]
        });
        const element = createDetail('a01xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('(18% tax), ₹250.00 off');
        expect(element.shadowRoot.querySelector('[data-id="round-off"]').textContent).toBe('₹-0.30');
        expect(element.shadowRoot.querySelector('[data-id="paired-note"]').textContent).toContain('customer\'s share');

        element.shadowRoot.querySelector('[data-id="open-paired"]').click();
        expect(mockNavigate).toHaveBeenCalledWith(expect.objectContaining({
            attributes: { apiName: 'Bill_Detail' },
            state: expect.objectContaining({ c__recordId: 'a01xx0000000002' })
        }));
    });

    it('a bill with no round-off or pair shows neither', async () => {
        getBillSummary.mockResolvedValue({ ...SUMMARY, roundOff: 0 });
        const element = createDetail('a01xx0000000001');
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="round-off"]')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="paired-note"]')).toBeNull();
        expect(element.shadowRoot.textContent).not.toContain(' off');
    });
});
