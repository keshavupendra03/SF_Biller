import { createElement } from 'lwc';
import BillingList from 'c/billingList';
import listBills from '@salesforce/apex/BillController.listBills';

jest.mock('@salesforce/apex/BillController.listBills', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-billing-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads all bills by default', async () => {
        listBills.mockResolvedValue([
            { id: 'b1', invoiceNumber: 'INV/2026-27/0001', customerName: 'Papa', totalAmount: 590, status: 'Paid' }
        ]);

        const element = createElement('c-billing-list', { is: BillingList });
        document.body.appendChild(element);
        await flushPromises();

        expect(listBills).toHaveBeenCalledWith({ filter: 'All', searchTerm: '' });
        expect(element.shadowRoot.textContent).toContain('INV/2026-27/0001');
    });

    // Record Payment feature disabled (2026-10) — uncomment alongside billingList.js/.html to restore the All/Dues Only filter.
    // it('switching to Dues Only re-queries with that filter', async () => {
    //     listBills.mockResolvedValue([]);
    //
    //     const element = createElement('c-billing-list', { is: BillingList });
    //     document.body.appendChild(element);
    //     await flushPromises();
    //
    //     element.shadowRoot.querySelector('[data-id="filter-dues"]').click();
    //     await flushPromises();
    //
    //     expect(listBills).toHaveBeenCalledWith({ filter: 'DuesOnly', searchTerm: '' });
    // });

    it('typing in the search box re-queries with that search term', async () => {
        listBills.mockResolvedValue([]);

        const element = createElement('c-billing-list', { is: BillingList });
        document.body.appendChild(element);
        await flushPromises();

        const searchInput = element.shadowRoot.querySelector('[data-id="search"]');
        searchInput.value = 'INV/2026-27/0001';
        searchInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(listBills).toHaveBeenCalledWith({ filter: 'All', searchTerm: 'INV/2026-27/0001' });
    });
});
