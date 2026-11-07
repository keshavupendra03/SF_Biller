import { createElement } from 'lwc';
import CustomerList from 'c/customerList';
import listCustomers from '@salesforce/apex/CustomerController.listCustomers';
import createCustomer from '@salesforce/apex/BillController.createCustomer';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';

jest.mock('@salesforce/apex/CustomerController.listCustomers', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.createCustomer', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-customer-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads and renders customers on connect', async () => {
        listCustomers.mockResolvedValue([
            { id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111', email: '' }
        ]);

        const element = createElement('c-customer-list', { is: CustomerList });
        document.body.appendChild(element);
        await flushPromises();

        expect(listCustomers).toHaveBeenCalledWith({ searchTerm: '' });
        expect(element.shadowRoot.textContent).toContain('Ramesh Kumar');
    });

    it('re-queries as the search term changes', async () => {
        listCustomers.mockResolvedValue([]);

        const element = createElement('c-customer-list', { is: CustomerList });
        document.body.appendChild(element);
        await flushPromises();

        const search = element.shadowRoot.querySelector('[data-id="search"]');
        search.value = 'Ramesh';
        search.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(listCustomers).toHaveBeenCalledWith({ searchTerm: 'Ramesh' });
    });

    it('creating a customer inline refreshes the list', async () => {
        listCustomers.mockResolvedValue([]);
        createCustomer.mockResolvedValue({ id: 'cust9', name: 'Brand New Co', phone: '9000000009' });

        const element = createElement('c-customer-list', { is: CustomerList });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="fab"]').click();
        await flushPromises();

        const nameInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'name'
        );
        nameInput.value = 'Brand New Co';
        nameInput.dispatchEvent(new CustomEvent('change'));
        const phoneInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'phone'
        );
        phoneInput.value = '9000000009';
        phoneInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(createCustomer).toHaveBeenCalledTimes(1);
        expect(listCustomers).toHaveBeenCalledTimes(2);
    });

    it('Print Job Slip previews a completely blank slip, and Close dismisses it', async () => {
        listCustomers.mockResolvedValue([]);
        listProfiles.mockResolvedValue([{ id: 'profile1', name: 'Speedy Motors' }]);
        const element = createElement('c-customer-list', { is: CustomerList });
        document.body.appendChild(element);
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-document-preview')).toBeNull();

        element.shadowRoot.querySelector('[data-id="print-job-slip"]').click();
        await flushPromises();

        const preview = element.shadowRoot.querySelector('c-document-preview');
        expect(preview.recordId).toBe('profile1');
        expect(preview.pageName).toBe('JobSlipPdf');

        preview.dispatchEvent(new CustomEvent('close'));
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-document-preview')).toBeNull();
    });

    it('Print Job Slip asks for workshop details when there is no profile yet', async () => {
        listCustomers.mockResolvedValue([]);
        listProfiles.mockResolvedValue([]);
        const element = createElement('c-customer-list', { is: CustomerList });
        document.body.appendChild(element);
        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="print-job-slip"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-document-preview')).toBeNull();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe('Workshop profile needed');
    });

    it('Print Job Slip asks which company when there are two, and prints that one', async () => {
        listCustomers.mockResolvedValue([]);
        listProfiles.mockResolvedValue([{ id: 'wp1', name: 'Speedy Motors' }, { id: 'wp2', name: 'Speedy Decor' }]);
        const element = createElement('c-customer-list', { is: CustomerList });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="print-job-slip"]').click();
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-document-preview')).toBeNull();

        element.shadowRoot.querySelector('[data-id="wp2"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-document-preview').recordId).toBe('wp2');
    });
});
