import { createElement } from 'lwc';
import ArchivedBill from 'c/archivedBill';
import getArchivedBill from '@salesforce/apex/ArchiveController.getArchivedBill';
import restoreBill from '@salesforce/apex/ArchiveController.restoreBill';

jest.mock('@salesforce/apex/ArchiveController.getArchivedBill', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ArchiveController.restoreBill', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getArchivedPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getArchivedPublicLink', () => ({ default: jest.fn() }), { virtual: true });

const BILL = {
    billId: 'a1', documentId: 'doc1', companyName: 'Speedy Motors', invoiceNumber: 'INV/2024-25/0007', billDate: '2024-11-05',
    versionNumber: 1, isLatestVersion: true, isCancelled: false, customerName: 'Sharma Traders', vehicle: 'MP09AB1234',
    lineItems: [{ description: 'Clutch plate', quantity: 2, unitPrice: 1500, taxRatePercent: 18, discount: 100 }],
    subtotal: 2900, cgst: 261, sgst: 261, igst: 0, roundOff: 0, totalAmount: 3422
};

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function open() {
    const element = createElement('c-archived-bill', { is: ArchivedBill });
    element.billId = 'a1';
    element.documentId = 'doc1';
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

const $ = (el, sel) => el.shadowRoot.querySelector(sel);

describe('c-archived-bill', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the archived bill read-only, with its lines and totals', async () => {
        getArchivedBill.mockResolvedValue(BILL);
        const element = await open();

        expect(getArchivedBill).toHaveBeenCalledWith({ documentId: 'doc1', billId: 'a1' });
        expect($(element, '[data-id="heading"]').textContent).toBe('INV/2024-25/0007');
        expect($(element, '[data-id="customer"]').textContent).toBe('Sharma Traders');
        expect($(element, '[data-id="lines"]').textContent).toContain('2 × ₹1,500.00 · GST 18% · ₹100.00 off');
        expect($(element, '[data-id="total"]').textContent).toBe('₹3,422.00');
        expect($(element, '[data-id="deleted"]')).toBeNull();
    });

    it('prints through the same preview, from the archive copy', async () => {
        getArchivedBill.mockResolvedValue(BILL);
        const element = await open();

        $(element, '[data-id="print"]').click();
        await flushPromises();

        const preview = $(element, 'c-document-preview');
        expect(preview.recordId).toBe('a1');
        expect(preview.archiveId).toBe('doc1');
    });

    it('brings the bill back after asking, and says where it went', async () => {
        getArchivedBill.mockResolvedValue({ ...BILL, isCancelled: true });
        restoreBill.mockResolvedValue('new1');
        const element = await open();
        const restored = jest.fn();
        element.addEventListener('restored', restored);

        expect($(element, '[data-id="deleted"]')).not.toBeNull();
        $(element, '[data-id="restore"]').click();
        await flushPromises();
        expect(restoreBill).not.toHaveBeenCalled();
        $(element, '[data-id="restore-yes"]').click();
        await flushPromises();

        expect(restoreBill).toHaveBeenCalledWith({ billId: 'a1' });
        expect(restored.mock.calls[0][0].detail).toEqual({ billId: 'new1' });
    });

    it('Close says so', async () => {
        getArchivedBill.mockResolvedValue(BILL);
        const element = await open();
        const closed = jest.fn();
        element.addEventListener('close', closed);

        $(element, '[data-id="close"]').click();

        expect(closed).toHaveBeenCalled();
    });
});
