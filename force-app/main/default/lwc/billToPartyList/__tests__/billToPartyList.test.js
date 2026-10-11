import { createElement } from 'lwc';
import BillToPartyList from 'c/billToPartyList';
import listBillToParties from '@salesforce/apex/DirectoryController.listBillToParties';
import createBillToParty from '@salesforce/apex/DirectoryController.createBillToParty';

jest.mock('@salesforce/apex/DirectoryController.listBillToParties', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DirectoryController.createBillToParty', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-bill-to-party-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads parties on connect', async () => {
        listBillToParties.mockResolvedValue([{ id: 'p1', name: 'Aakash Siroliya', gstin: 'BZJGZ1234F1Z5' }]);

        const element = createElement('c-bill-to-party-list', { is: BillToPartyList });
        document.body.appendChild(element);
        await flushPromises();

        expect(listBillToParties).toHaveBeenCalledWith({ searchTerm: '' });
        expect(element.shadowRoot.textContent).toContain('Aakash Siroliya');
    });

    it('creating a party refreshes the list', async () => {
        listBillToParties.mockResolvedValue([]);
        createBillToParty.mockResolvedValue({ id: 'p9', name: 'Acme Logistics' });

        const element = createElement('c-bill-to-party-list', { is: BillToPartyList });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="fab"]').click();
        await flushPromises();

        const nameInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'name'
        );
        nameInput.value = 'Acme Logistics';
        nameInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(createBillToParty).toHaveBeenCalledWith({
            input: expect.objectContaining({ name: 'Acme Logistics' })
        });
        expect(listBillToParties).toHaveBeenCalledTimes(2);
    });
});
