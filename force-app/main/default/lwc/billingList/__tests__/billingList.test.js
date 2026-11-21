import { createElement } from 'lwc';
import BillingList from 'c/billingList';
import listBills from '@salesforce/apex/BillController.listBills';
import listEstimates from '@salesforce/apex/EstimateController.listEstimates';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/BillController.listBills', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/EstimateController.listEstimates', () => ({ default: jest.fn() }), { virtual: true });

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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// The search waits 300ms after typing stops.
function wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
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
        await wait(350);
        await flushPromises();

        expect(listBills).toHaveBeenCalledWith({ filter: 'All', searchTerm: 'INV/2026-27/0001' });
    });

    it('Quick Bill opens the Quick Bill tab', async () => {
        listBills.mockResolvedValue([]);
        const element = createElement('c-billing-list', { is: BillingList });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="quick-bill"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({ type: 'standard__navItemPage', attributes: { apiName: 'Quick_Bill' } });
    });

    describe('opening a saved bill or estimate in Easy Bill', () => {
        const BILL = { id: 'b1', invoiceNumber: 'INV/2026-27/0001', customerName: 'Papa', totalAmount: 590 };
        const PARTY_BILL = { id: 'b2', invoiceNumber: 'INV/2026-27/0002', customerName: 'Ramesh Kumar', billToPartyName: 'ICICI Lombard', totalAmount: 3500 };
        const ESTIMATE = { id: 'e1', estimateNumber: 'EST-0042', customerName: 'Walk-in Customer', billToPartyName: 'Sharma Transport', totalAmount: 800 };

        async function createList() {
            const element = createElement('c-billing-list', { is: BillingList });
            document.body.appendChild(element);
            await flushPromises();
            return element;
        }

        function $(element, selector) {
            return element.shadowRoot.querySelector(selector);
        }

        async function showEstimates(element) {
            $(element, '[data-id="list-type"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'estimates' } }));
            await flushPromises();
        }

        it('every bill has an Easy Bill button that opens it there', async () => {
            listBills.mockResolvedValue([BILL, PARTY_BILL]);
            const element = await createList();
            const buttons = element.shadowRoot.querySelectorAll('[data-id="easy-bill"]');
            expect(buttons).toHaveLength(2);

            buttons[1].click();

            const pageRef = mockNavigate.mock.calls[0][0];
            expect(pageRef.attributes).toEqual({ apiName: 'Easy_Bill' });
            expect(pageRef.state.c__editId).toBe('b2');
            expect(pageRef.state.c__opened).toBeTruthy();
        });

        it('the row itself still opens the bill details', async () => {
            listBills.mockResolvedValue([BILL]);
            const element = await createList();

            $(element, '[data-id="b1"]').click();

            expect(mockNavigate).toHaveBeenCalledWith({
                type: 'standard__navItemPage', attributes: { apiName: 'Bill_Detail' }, state: { c__recordId: 'b1' }
            });
        });

        it('a party bill is listed under the party, with the car owner as buyer', async () => {
            listBills.mockResolvedValue([PARTY_BILL]);
            const element = await createList();

            const row = $(element, '[data-id="row"]').textContent;
            expect(row).toContain('ICICI Lombard');
            expect($(element, '[data-id="bill-buyer"]').textContent).toBe('Buyer: Ramesh Kumar');
            expect(row).toContain('3,500.00');
        });

        it('Estimates lists saved estimates, each with Easy Bill, and the buttons make estimates', async () => {
            listBills.mockResolvedValue([BILL]);
            listEstimates.mockResolvedValue([ESTIMATE]);
            const element = await createList();

            await showEstimates(element);

            expect(listEstimates).toHaveBeenCalledWith({ searchTerm: '', workshopProfileId: undefined });
            expect($(element, '[data-id="row"]').textContent).toContain('EST-0042');
            expect($(element, '[data-id="row"]').textContent).toContain('Sharma Transport');
            expect($(element, '[data-id="bill-buyer"]')).toBeNull();
            expect($(element, '[data-id="quick-bill"]').label).toBe('Quick Estimate');

            $(element, '[data-id="easy-bill"]').click();
            expect(mockNavigate.mock.calls[0][0].state.c__editId).toBe('e1');

            $(element, '[data-id="e1"]').click();
            expect(mockNavigate.mock.calls[1][0]).toEqual({
                type: 'standard__navItemPage', attributes: { apiName: 'Estimate_Detail' }, state: { c__recordId: 'e1' }
            });

            $(element, '[data-id="fab"]').click();
            expect(mockNavigate.mock.calls[2][0].attributes).toEqual({ apiName: 'New_Estimate' });
        });

        it('searching while on Estimates searches estimates', async () => {
            listBills.mockResolvedValue([]);
            listEstimates.mockResolvedValue([]);
            const element = await createList();
            await showEstimates(element);

            const search = $(element, '[data-id="search"]');
            for (const typed of ['s', 'sh', 'sharma']) {
                search.value = typed;
                search.dispatchEvent(new CustomEvent('change'));
            }
            await wait(350);
            await flushPromises();

            expect(listEstimates).toHaveBeenCalledTimes(2);

            expect(listEstimates).toHaveBeenLastCalledWith({ searchTerm: 'sharma', workshopProfileId: undefined });
            expect($(element, 'p').textContent).toBe('No estimates found.');
        });
    });

    it('deleted bills are shown only when asked for, marked as deleted', async () => {
        listBills.mockResolvedValue([{ id: 'b1', invoiceNumber: 'INV/2026-27/0001', customerName: 'Papa', totalAmount: 590 }]);
        const element = createElement('c-billing-list', { is: BillingList });
        document.body.appendChild(element);
        await flushPromises();
        expect(element.shadowRoot.querySelector('[data-id="deleted-badge"]')).toBeNull();

        element.shadowRoot.querySelector('[data-id="toggle-deleted"]').click();
        await flushPromises();

        expect(listBills).toHaveBeenLastCalledWith({ filter: 'Cancelled', searchTerm: '', workshopProfileId: undefined });
        expect(element.shadowRoot.querySelector('[data-id="deleted-badge"]').textContent).toBe('Deleted');
        expect(element.shadowRoot.querySelector('[data-id="toggle-deleted"]').label).toBe('Back to bills');
    });

    describe('GST due-date reminder (G5)', () => {
        const LATE = { id: 'wp1', name: 'Speedy Motors', gstRegistrationType: 'Regular', gstFilingFrequency: 'Monthly', state: 'Madhya Pradesh', gstFiledUpTo: '2000-01-31' };
        const UP_TO_DATE = { id: 'wp2', name: 'Speedy Decor', gstRegistrationType: 'Regular', gstFilingFrequency: 'Monthly', state: 'Madhya Pradesh', gstFiledUpTo: '2099-12-31' };

        async function createList() {
            listBills.mockResolvedValue([]);
            const element = createElement('c-billing-list', { is: BillingList });
            document.body.appendChild(element);
            await flushPromises();
            return element;
        }

        it('shows returns that are late, at most three, naming the company, and opens GST Returns', async () => {
            listProfiles.mockResolvedValue([LATE, UP_TO_DATE]);
            const element = await createList();

            const reminder = element.shadowRoot.querySelector('[data-id="gst-reminder"]');
            expect(reminder.className).toContain('slds-theme_error');
            const lines = [...element.shadowRoot.querySelectorAll('[data-id="gst-reminder-line"]')].map((p) => p.textContent);
            expect(lines).toHaveLength(3);
            expect(lines.every((line) => line.startsWith('Speedy Motors: GSTR-') && line.includes('late'))).toBe(true);

            element.shadowRoot.querySelector('[data-id="open-gst-returns"]').click();
            expect(mockNavigate).toHaveBeenCalledWith({ type: 'standard__navItemPage', attributes: { apiName: 'GST_Returns' } });
        });

        it('shows nothing when every company is up to date, or for a company picked that is', async () => {
            listProfiles.mockResolvedValue([UP_TO_DATE, { ...LATE, gstRegistrationType: 'Unregistered' }]);
            const element = await createList();
            expect(element.shadowRoot.querySelector('[data-id="gst-reminder"]')).toBeNull();
        });

        it('a list that can\'t load the companies still works, without the reminder', async () => {
            listProfiles.mockRejectedValue(new Error('offline'));
            const element = await createList();
            expect(element.shadowRoot.querySelector('[data-id="gst-reminder"]')).toBeNull();
            expect(listBills).toHaveBeenCalled();
        });
    });
});
