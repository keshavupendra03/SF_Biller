import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import CustomerDetail from 'c/customerDetail';
import getCustomerDetail from '@salesforce/apex/CustomerController.getCustomerDetail';
import updateCustomer from '@salesforce/apex/CustomerController.updateCustomer';
import createVehicle from '@salesforce/apex/CustomerController.createVehicle';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/CustomerController.getCustomerDetail', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/CustomerController.updateCustomer', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/CustomerController.createVehicle', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPdfDownload', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DocumentPdfService.getPublicLink', () => ({ default: jest.fn() }), { virtual: true });

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

const DETAIL = {
    id: 'cust1',
    name: 'Ramesh Kumar',
    phone: '9000011111',
    email: '',
    address: '',
    gstin: '',
    state: '',
    lifetimeSpend: 1500,
    vehicles: [{ id: 'veh1', registrationNumber: 'MP09AB1234', make: 'Maruti', model: 'Swift', year: 2020, color: '' }],
    jobs: [{ id: 'job1', jobNumber: 'JOB-0001', stageName: 'Received', vehicleLabel: 'MP09AB1234', createdDate: '2026-01-01' }],
    bills: [{ id: 'bill1', documentNumber: 'INV/2026-27/0001', status: 'Unpaid', totalAmount: 500, documentDate: '2026-01-01' }],
    estimates: [{ id: 'est1', documentNumber: 'EST-0001', status: 'Draft', totalAmount: 300, documentDate: '2026-01-01' }]
};

function createPageRef(customerId) {
    return { type: 'standard__navItemPage', attributes: {}, state: { c__customerId: customerId } };
}

describe('c-customer-detail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads the customer detail from the page reference and renders vehicles/bills/estimates', async () => {
        getCustomerDetail.mockResolvedValue(DETAIL);

        const element = createElement('c-customer-detail', { is: CustomerDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit(createPageRef('cust1'));
        await flushPromises();

        expect(getCustomerDetail).toHaveBeenCalledWith({ customerId: 'cust1' });
        expect(element.shadowRoot.textContent).toContain('Ramesh Kumar');
        expect(element.shadowRoot.textContent).toContain('MP09AB1234');
        expect(element.shadowRoot.textContent).toContain('INV/2026-27/0001');
        expect(element.shadowRoot.textContent).toContain('EST-0001');
        expect(element.shadowRoot.textContent).toContain('JOB-0001');
    });

    it('opening a job carries the current customer id so its Back can return here', async () => {
        getCustomerDetail.mockResolvedValue(DETAIL);

        const element = createElement('c-customer-detail', { is: CustomerDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit(createPageRef('cust1'));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="job1"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Job_Detail' },
            state: { c__recordId: 'job1', c__fromCustomerId: 'cust1' }
        });
    });

    it('opening a bill carries the current customer id so its Back can return here', async () => {
        getCustomerDetail.mockResolvedValue(DETAIL);

        const element = createElement('c-customer-detail', { is: CustomerDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit(createPageRef('cust1'));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="bill1"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: 'bill1', c__fromCustomerId: 'cust1' }
        });
    });

    it('opening an estimate carries the current customer id so its Back can return here', async () => {
        getCustomerDetail.mockResolvedValue(DETAIL);

        const element = createElement('c-customer-detail', { is: CustomerDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit(createPageRef('cust1'));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="est1"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Estimate_Detail' },
            state: { c__recordId: 'est1', c__fromCustomerId: 'cust1' }
        });
    });

    it('adding a vehicle calls createVehicle and reloads the detail', async () => {
        getCustomerDetail.mockResolvedValue(DETAIL);
        createVehicle.mockResolvedValue({ id: 'veh2', registrationNumber: 'MP09ZZ9999' });

        const element = createElement('c-customer-detail', { is: CustomerDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit(createPageRef('cust1'));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-add-vehicle"]').click();
        await flushPromises();

        const regInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'registrationNumber'
        );
        regInput.value = 'MP09ZZ9999';
        regInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="save-vehicle"]').click();
        await flushPromises();

        expect(createVehicle).toHaveBeenCalledWith({
            customerId: 'cust1',
            input: expect.objectContaining({ registrationNumber: 'MP09ZZ9999' })
        });
        expect(getCustomerDetail).toHaveBeenCalledTimes(2);
    });

    it('editing the customer calls updateCustomer with the edited values', async () => {
        getCustomerDetail.mockResolvedValue(DETAIL);
        updateCustomer.mockResolvedValue();

        const element = createElement('c-customer-detail', { is: CustomerDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit(createPageRef('cust1'));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-edit"]').click();
        await flushPromises();

        const nameInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'name'
        );
        nameInput.value = 'Ramesh Kumar Updated';
        nameInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save-edit"]').click();
        await flushPromises();

        expect(updateCustomer).toHaveBeenCalledWith({
            customerId: 'cust1',
            input: expect.objectContaining({ name: 'Ramesh Kumar Updated' })
        });
    });

    describe('job slips', () => {
        const WITH_SLIPS = {
            ...DETAIL,
            jobSlips: [{ id: 'slip1', slipNumber: 'JS-0007', slipDate: '2026-10-30', vehicleLabel: 'MP09AB1234', visitReason: 'Accident' }]
        };

        async function renderDetail(detail) {
            getCustomerDetail.mockResolvedValue(detail);
            const element = createElement('c-customer-detail', { is: CustomerDetail });
            document.body.appendChild(element);
            CurrentPageReference.emit(createPageRef('cust1'));
            await flushPromises();
            return element;
        }

        it('lists the customer job slips and opens one on the Job Slip screen', async () => {
            const element = await renderDetail(WITH_SLIPS);
            expect(element.shadowRoot.textContent).toContain('JS-0007');
            expect(element.shadowRoot.textContent).toContain('Accident');

            element.shadowRoot.querySelector('[data-id="slip1"]').click();

            expect(mockNavigate).toHaveBeenCalledWith({
                type: 'standard__navItemPage',
                attributes: { apiName: 'Job_Slip' },
                state: { c__recordId: 'slip1', c__fromCustomerId: 'cust1' }
            });
        });

        it('shows a hint when there are no job slips yet', async () => {
            const element = await renderDetail({ ...DETAIL, jobSlips: [] });
            expect(element.shadowRoot.textContent).toContain('No job slips yet.');
        });

        it('+ New Slip opens a new slip for this customer', async () => {
            const element = await renderDetail(WITH_SLIPS);
            element.shadowRoot.querySelector('[data-id="new-job-slip"]').click();

            expect(mockNavigate).toHaveBeenCalledWith({
                type: 'standard__navItemPage',
                attributes: { apiName: 'Job_Slip' },
                state: { c__customerId: 'cust1' }
            });
        });

        it('Print Blank asks which vehicle, then previews the blank slip for it', async () => {
            const element = await renderDetail(WITH_SLIPS);
            element.shadowRoot.querySelector('[data-id="print-blank-slip"]').click();
            await flushPromises();
            expect(element.shadowRoot.querySelector('c-document-preview')).toBeNull();

            element.shadowRoot.querySelector('[data-id="blank-slip-vehicle"]').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="blank-slip-vehicle"]')).toBeNull();
            const preview = element.shadowRoot.querySelector('c-document-preview');
            expect(preview.recordId).toBe('veh1');
            expect(preview.pageName).toBe('JobSlipPdf');
        });

        it('Print Blank with "Another vehicle" previews a slip with just the customer details', async () => {
            const element = await renderDetail(WITH_SLIPS);
            element.shadowRoot.querySelector('[data-id="print-blank-slip"]').click();
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="blank-slip-no-vehicle"]').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-document-preview').recordId).toBe('cust1');
        });

        it('Print Blank goes straight to the preview when the customer has no vehicles', async () => {
            const element = await renderDetail({ ...WITH_SLIPS, vehicles: [] });
            element.shadowRoot.querySelector('[data-id="print-blank-slip"]').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-document-preview').recordId).toBe('cust1');
        });
    });
});
