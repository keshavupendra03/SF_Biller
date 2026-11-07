import { createElement } from 'lwc';
import QuickEstimate from 'c/quickEstimate';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.findCustomerByPhone', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.createQuickBill', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.createQuickEstimate', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchParts', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchMakes', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/VehicleMakeModelController.searchModels', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock(
    'lightning/mobileCapabilities',
    () => ({ getBarcodeScanner: jest.fn(() => ({ isAvailable: () => false })) }),
    { virtual: true }
);

describe('c-quick-estimate', () => {
    it('is the Quick Bill screen in estimate mode', () => {
        const element = createElement('c-quick-estimate', { is: QuickEstimate });
        document.body.appendChild(element);

        const screen = element.shadowRoot.querySelector('c-quick-bill');
        expect(screen.documentType).toBe('estimate');
        expect(screen.shadowRoot.textContent).toContain('Quick Estimate');

        document.body.removeChild(element);
    });
});
