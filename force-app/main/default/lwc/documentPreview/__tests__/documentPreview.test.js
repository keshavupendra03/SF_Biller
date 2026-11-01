import { createElement } from 'lwc';
import DocumentPreview from 'c/documentPreview';
import getPdfDownload from '@salesforce/apex/DocumentPdfService.getPdfDownload';
import getPublicLink from '@salesforce/apex/DocumentPdfService.getPublicLink';

jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });

// A mocked module value is bound into the component once, at first import
// of this test file — it can't be changed per-test (see
// documentPreview.mobile.test.js, which mocks 'Small' for the whole file
// instead). This file covers desktop ('Large', the sfdx-lwc-jest default).
jest.mock('@salesforce/client/formFactor', () => ({ default: 'Large' }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-document-preview (desktop)', () => {
    beforeEach(() => {
        global.URL.createObjectURL = jest.fn(() => 'blob:fake-url');
        global.URL.revokeObjectURL = jest.fn();
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createPreview() {
        const element = createElement('c-document-preview', { is: DocumentPreview });
        element.recordId = 'a01xx0000000001';
        element.heading = 'INV/2026-27/0001';
        document.body.appendChild(element);
        return element;
    }

    it('frames the HTML version of the invoice page for the given record', () => {
        const element = createPreview();
        const frame = element.shadowRoot.querySelector('[data-id="preview-frame"]');
        expect(frame.getAttribute('src')).toBe('/apex/InvoicePdf?id=a01xx0000000001&format=html');
    });

    it('frames the page named by pageName instead, for job slips', () => {
        const element = createElement('c-document-preview', { is: DocumentPreview });
        element.recordId = 'a0Jxx0000000001';
        element.pageName = 'JobSlipPdf';
        document.body.appendChild(element);
        const frame = element.shadowRoot.querySelector('[data-id="preview-frame"]');
        expect(frame.getAttribute('src')).toBe('/apex/JobSlipPdf?id=a0Jxx0000000001&format=html');
    });

    it('Close fires a close event', () => {
        const element = createPreview();
        const handler = jest.fn();
        element.addEventListener('close', handler);

        element.shadowRoot.querySelector('[data-id="close"]').click();

        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('Download builds the PDF in-page and creates no public link', async () => {
        getPdfDownload.mockResolvedValue({ fileName: 'INV-2026-27-0001.pdf', base64Data: btoa('%PDF-1.4') });
        const clickSpy = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});

        const element = createPreview();
        element.shadowRoot.querySelector('[data-id="download"]').click();
        await flushPromises();

        expect(getPdfDownload).toHaveBeenCalledWith({ recordId: 'a01xx0000000001' });
        expect(getPublicLink).not.toHaveBeenCalled();
        expect(clickSpy).toHaveBeenCalledTimes(1);
        expect(element.shadowRoot.querySelector('a').download).toBe('INV-2026-27-0001.pdf');
        clickSpy.mockRestore();
    });
});
