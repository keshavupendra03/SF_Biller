import { createElement } from 'lwc';
import DocumentPreview from 'c/documentPreview';
import getPdfDownload from '@salesforce/apex/DocumentPdfService.getPdfDownload';
import getPublicLink from '@salesforce/apex/DocumentPdfService.getPublicLink';

jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });

// Separate file so '@salesforce/client/formFactor' can be mocked 'Small'
// for the whole file — the mocked value is bound into the component once,
// at first import, so it can't be flipped per-test within one file.
jest.mock('@salesforce/client/formFactor', () => ({ default: 'Small' }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const LINK = {
    documentNumber: 'INV/2026-27/0001',
    viewUrl: 'https://example.my.salesforce.com/sfc/p/view',
    downloadUrl: 'https://example.my.salesforce.com/sfc/dist/download'
};

function createPreview() {
    const element = createElement('c-document-preview', { is: DocumentPreview });
    element.recordId = 'a01xx0000000001';
    document.body.appendChild(element);
    return element;
}

describe('c-document-preview (mobile)', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        delete navigator.share;
        jest.clearAllMocks();
    });

    it('pre-fetches the public link as soon as the popup opens, before Download is tapped', async () => {
        getPublicLink.mockResolvedValue(LINK);
        createPreview();
        await flushPromises();

        expect(getPublicLink).toHaveBeenCalledWith({ recordId: 'a01xx0000000001' });
    });

    it('Download hands the link to the native share sheet instead of opening it directly', async () => {
        getPublicLink.mockResolvedValue(LINK);
        navigator.share = jest.fn().mockResolvedValue();

        const element = createPreview();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="download"]').click();
        await flushPromises();

        expect(navigator.share).toHaveBeenCalledWith({
            title: LINK.documentNumber,
            text: `${LINK.documentNumber} PDF`,
            url: LINK.downloadUrl
        });
        expect(getPdfDownload).not.toHaveBeenCalled();
    });

    it('falls back to a plain anchor click when the share sheet is unavailable', async () => {
        getPublicLink.mockResolvedValue(LINK);
        // navigator.share left undefined, as on the user's device.
        const clickSpy = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});

        const element = createPreview();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="download"]').click();
        await flushPromises();

        const anchor = element.shadowRoot.querySelector('a');
        expect(anchor.href).toBe(LINK.downloadUrl);
        expect(anchor.target).toBe('_blank');
        expect(anchor.hasAttribute('download')).toBe(false);
        expect(clickSpy).toHaveBeenCalledTimes(1);
        clickSpy.mockRestore();
    });

    it('a cancelled share sheet (AbortError) does not fall back to the anchor or show an error', async () => {
        getPublicLink.mockResolvedValue(LINK);
        const abortError = new Error('cancelled');
        abortError.name = 'AbortError';
        navigator.share = jest.fn().mockRejectedValue(abortError);
        const clickSpy = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});

        const element = createPreview();
        await flushPromises();
        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);
        element.shadowRoot.querySelector('[data-id="download"]').click();
        await flushPromises();

        expect(clickSpy).not.toHaveBeenCalled();
        expect(toastHandler).not.toHaveBeenCalled();
        clickSpy.mockRestore();
    });
});
