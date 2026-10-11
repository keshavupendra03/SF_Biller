import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import JobDetail from 'c/jobDetail';
import getJobDetail from '@salesforce/apex/JobController.getJobDetail';

jest.mock('@salesforce/apex/JobController.getJobDetail', () => ({ default: jest.fn() }), { virtual: true });

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
    id: 'job1',
    jobNumber: 'JOB-0001',
    createdDate: '2026-10-01',
    stageId: 'stage1',
    stageName: 'Received',
    customerId: 'cust1',
    customerName: 'Ramesh Kumar',
    customerPhone: '9000011111',
    customerAddress: '6 Durga Plaza Dewas Road Ujjain',
    vehicleId: 'veh1',
    vehicleRegistrationNumber: 'MP09AB1234',
    vehicleMakeModel: 'Maruti Swift',
    vehicleYear: 2022,
    vehicleColor: 'White',
    surveyorId: 'surv1',
    surveyorName: 'Bhaiyo Jio',
    mechanicNames: 'Suresh, Aniket',
    notes: 'Front bumper repair',
    bills: [{ id: 'bill1', documentNumber: 'INV/2026-27/0001', status: 'Unpaid', totalAmount: 500, documentDate: '2026-10-01' }],
    estimates: [{ id: 'est1', documentNumber: 'EST-0001', status: 'Draft', totalAmount: 300, documentDate: '2026-10-01' }]
};

function createDetail(recordId, extraState) {
    const element = createElement('c-job-detail', { is: JobDetail });
    document.body.appendChild(element);
    CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: recordId, ...extraState } });
    return element;
}

describe('c-job-detail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads the job from the page reference and renders customer/vehicle/stage details', async () => {
        getJobDetail.mockResolvedValue(SUMMARY);

        const element = createDetail('job1');
        await flushPromises();

        expect(getJobDetail).toHaveBeenCalledWith({ jobId: 'job1' });
        expect(element.shadowRoot.textContent).toContain('JOB-0001');
        expect(element.shadowRoot.textContent).toContain('Received');
        expect(element.shadowRoot.textContent).toContain('Ramesh Kumar');
        expect(element.shadowRoot.textContent).toContain('9000011111');
        expect(element.shadowRoot.textContent).toContain('MP09AB1234');
        expect(element.shadowRoot.textContent).toContain('Maruti Swift');
        expect(element.shadowRoot.textContent).toContain('Bhaiyo Jio');
        expect(element.shadowRoot.textContent).toContain('Suresh, Aniket');
        expect(element.shadowRoot.textContent).toContain('Front bumper repair');
    });

    it('lists bills and estimates linked to the job', async () => {
        getJobDetail.mockResolvedValue(SUMMARY);
        const element = createDetail('job1');
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('INV/2026-27/0001');
        expect(element.shadowRoot.textContent).toContain('EST-0001');
    });

    it('omits the bills/estimates sections gracefully when there are none yet', async () => {
        getJobDetail.mockResolvedValue({ ...SUMMARY, bills: [], estimates: [] });
        const element = createDetail('job1');
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('No bills yet.');
        expect(element.shadowRoot.textContent).toContain('No estimates yet.');
    });

    it('tapping a bill opens Bill Detail', async () => {
        getJobDetail.mockResolvedValue(SUMMARY);
        const element = createDetail('job1');
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="bill1"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: 'bill1' }
        });
    });

    it('tapping an estimate opens Estimate Detail', async () => {
        getJobDetail.mockResolvedValue(SUMMARY);
        const element = createDetail('job1');
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="est1"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Estimate_Detail' },
            state: { c__recordId: 'est1' }
        });
    });

    it('Back returns to the originating customer when the job was opened from one', async () => {
        getJobDetail.mockResolvedValue(SUMMARY);
        const element = createDetail('job1', { c__fromCustomerId: 'cust1' });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_Detail' },
            state: { c__customerId: 'cust1' }
        });
    });

    it('Back falls back to the Jobs board when the job was not opened from a customer', async () => {
        getJobDetail.mockResolvedValue(SUMMARY);
        const element = createDetail('job1');
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Jobs_Board' }
        });
    });

    it('navigating to a different job in the same tab reloads the new record, not the stale one', async () => {
        getJobDetail.mockResolvedValueOnce(SUMMARY);
        const element = createDetail('job1');
        await flushPromises();
        expect(element.shadowRoot.textContent).toContain('JOB-0001');

        const OTHER_JOB = { ...SUMMARY, id: 'job2', jobNumber: 'JOB-0002' };
        getJobDetail.mockResolvedValueOnce(OTHER_JOB);
        CurrentPageReference.emit({ type: 'standard__navItemPage', attributes: {}, state: { c__recordId: 'job2' } });
        await flushPromises();

        expect(getJobDetail).toHaveBeenCalledWith({ jobId: 'job2' });
        expect(element.shadowRoot.textContent).toContain('JOB-0002');
        expect(element.shadowRoot.textContent).not.toContain('JOB-0001');
    });
});
