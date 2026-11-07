import { createElement } from 'lwc';
import JobBoard from 'c/jobBoard';
import getBoardData from '@salesforce/apex/JobController.getBoardData';
import searchVehicles from '@salesforce/apex/JobController.searchVehicles';
import getActiveMechanics from '@salesforce/apex/JobController.getActiveMechanics';
import getActiveSurveyors from '@salesforce/apex/JobController.getActiveSurveyors';
import createJob from '@salesforce/apex/JobController.createJob';
import moveJob from '@salesforce/apex/JobController.moveJob';
import assignMechanics from '@salesforce/apex/JobController.assignMechanics';
import searchCustomers from '@salesforce/apex/BillController.searchCustomers';
import createCustomer from '@salesforce/apex/BillController.createCustomer';

jest.mock('@salesforce/apex/JobController.getBoardData', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobController.searchVehicles', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobController.getActiveMechanics', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobController.getActiveSurveyors', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobController.createJob', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobController.moveJob', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobController.assignMechanics', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchCustomers', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.createCustomer', () => ({ default: jest.fn() }), { virtual: true });

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

const STAGES = [
    { id: 'stageReceived', name: 'Received', sortOrder: 1 },
    { id: 'stageProgress', name: 'In Progress', sortOrder: 2 }
];

function boardWithOneJob() {
    return {
        stages: STAGES,
        jobs: [
            {
                id: 'job1',
                jobNumber: 'JOB-0001',
                stageId: 'stageReceived',
                customerId: 'cust1',
                customerName: 'Ramesh Kumar',
                customerPhone: '9000011111',
                vehicleId: 'veh1',
                vehicleLabel: 'MP09AB1234 — Maruti Swift',
                surveyorId: null,
                surveyorName: null,
                notes: null,
                mechanicIds: [],
                mechanicNames: null
            }
        ]
    };
}

describe('c-job-board', () => {
    beforeEach(() => {
        searchVehicles.mockResolvedValue([]);
    });

    beforeEach(() => {
        getActiveMechanics.mockResolvedValue([]);
        getActiveSurveyors.mockResolvedValue([]);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders columns for each active stage with their jobs', async () => {
        getBoardData.mockResolvedValue(boardWithOneJob());

        const element = createElement('c-job-board', { is: JobBoard });
        document.body.appendChild(element);
        await flushPromises();

        const columns = element.shadowRoot.querySelectorAll('.board-column');
        expect(columns).toHaveLength(2);
        expect(element.shadowRoot.textContent).toContain('JOB-0001');
        expect(element.shadowRoot.textContent).toContain('Ramesh Kumar');
    });

    it('tapping a job number opens its Job Detail screen', async () => {
        getBoardData.mockResolvedValue(boardWithOneJob());

        const element = createElement('c-job-board', { is: JobBoard });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-job-id="job1"].job-number-link').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Job_Detail' },
            state: { c__recordId: 'job1' }
        });
    });

    it('loads the board with no search term by default, and re-queries with the term on change', async () => {
        getBoardData.mockResolvedValue(boardWithOneJob());

        const element = createElement('c-job-board', { is: JobBoard });
        document.body.appendChild(element);
        await flushPromises();

        expect(getBoardData).toHaveBeenCalledWith({ searchTerm: '' });

        const searchInput = element.shadowRoot.querySelector('[data-id="board-search"]');
        searchInput.value = 'MP09AB1234';
        searchInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(getBoardData).toHaveBeenCalledWith({ searchTerm: 'MP09AB1234' });
    });

    it('moving a job via the "Move to" combobox calls moveJob and reloads the board', async () => {
        getBoardData.mockResolvedValue(boardWithOneJob());
        moveJob.mockResolvedValue();

        const element = createElement('c-job-board', { is: JobBoard });
        document.body.appendChild(element);
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox[data-job-id="job1"]');
        combobox.value = 'stageProgress';
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'stageProgress' } }));
        await flushPromises();

        expect(moveJob).toHaveBeenCalledWith({ jobId: 'job1', newStageId: 'stageProgress' });
        expect(getBoardData).toHaveBeenCalledTimes(2);
    });

    it('toggling a mechanic checkbox on a job card calls assignMechanics with the updated list', async () => {
        getBoardData.mockResolvedValue(boardWithOneJob());
        getActiveMechanics.mockResolvedValue([{ id: 'mech1', name: 'Suresh', phone: '900' }]);
        assignMechanics.mockResolvedValue();

        const element = createElement('c-job-board', { is: JobBoard });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-mechanics"][data-job-id="job1"]').click();
        await flushPromises();

        const checkbox = element.shadowRoot.querySelector(
            'lightning-input[data-job-id="job1"][data-mechanic-id="mech1"]'
        );
        checkbox.checked = true;
        checkbox.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(assignMechanics).toHaveBeenCalledWith({ jobId: 'job1', mechanicIds: ['mech1'] });
    });

    it('create-job form stays disabled until a customer and a vehicle are chosen', async () => {
        getBoardData.mockResolvedValue({ stages: STAGES, jobs: [] });
        searchCustomers.mockResolvedValue([{ id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111' }]);

        const element = createElement('c-job-board', { is: JobBoard });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-create-form"]').click();
        await flushPromises();

        let submitButton = element.shadowRoot.querySelector('[data-id="submit-job"]');
        expect(submitButton.disabled).toBe(true);

        const customerSearch = element.shadowRoot.querySelector('[data-id="job-customer-search"]');
        customerSearch.value = 'Ramesh';
        customerSearch.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        element.shadowRoot.querySelector('button[data-id="cust1"]').click();
        await flushPromises();

        submitButton = element.shadowRoot.querySelector('[data-id="submit-job"]');
        expect(submitButton.disabled).toBe(true); // still no vehicle

        const newVehicleToggle = element.shadowRoot.querySelector('[data-id="new-vehicle-toggle"]');
        newVehicleToggle.checked = true;
        newVehicleToggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const regInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'registrationNumber'
        );
        regInput.value = 'MP09ZZ9999';
        regInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        submitButton = element.shadowRoot.querySelector('[data-id="submit-job"]');
        expect(submitButton.disabled).toBe(false);
    });

    it('submits createJob with the expected request shape', async () => {
        getBoardData.mockResolvedValue({ stages: STAGES, jobs: [] });
        searchCustomers.mockResolvedValue([{ id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111' }]);
        createJob.mockResolvedValue({ id: 'job1' });

        const element = createElement('c-job-board', { is: JobBoard });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-create-form"]').click();
        await flushPromises();

        const customerSearch = element.shadowRoot.querySelector('[data-id="job-customer-search"]');
        customerSearch.value = 'Ramesh';
        customerSearch.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        element.shadowRoot.querySelector('button[data-id="cust1"]').click();
        await flushPromises();

        const newVehicleToggle = element.shadowRoot.querySelector('[data-id="new-vehicle-toggle"]');
        newVehicleToggle.checked = true;
        newVehicleToggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const regInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'registrationNumber'
        );
        regInput.value = 'MP09ZZ9999';
        regInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="submit-job"]').click();
        await flushPromises();

        expect(createJob).toHaveBeenCalledTimes(1);
        const request = createJob.mock.calls[0][0].request;
        expect(request.customerId).toBe('cust1');
        expect(request.newVehicle.registrationNumber).toBe('MP09ZZ9999');
    });

    it('creating a new customer inline selects it for the job being created', async () => {
        getBoardData.mockResolvedValue({ stages: STAGES, jobs: [] });
        createCustomer.mockResolvedValue({ id: 'cust9', name: 'Brand New Co', phone: '9000000009' });

        const element = createElement('c-job-board', { is: JobBoard });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-create-form"]').click();
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('[data-id="new-customer-toggle"]');
        toggle.checked = true;
        toggle.dispatchEvent(new CustomEvent('change'));
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

        element.shadowRoot.querySelector('[data-id="save-new-customer"]').click();
        await flushPromises();

        expect(createCustomer).toHaveBeenCalledTimes(1);
        expect(element.shadowRoot.querySelector('[data-id="job-customer-search"]')).toBeNull();
    });

    describe('filling in the vehicle for an existing customer', () => {
        const CITY = { id: 'veh1', registrationNumber: 'MP09AA1111', make: 'Honda', model: 'City' };
        const SWIFT = { id: 'veh2', registrationNumber: 'MP09BB2222', make: 'Maruti', model: 'Swift' };

        async function openFormAndPickCustomer() {
            getBoardData.mockResolvedValue({ stages: STAGES, jobs: [] });
            searchCustomers.mockResolvedValue([{ id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111' }]);
            createJob.mockResolvedValue({ id: 'job1' });

            const element = createElement('c-job-board', { is: JobBoard });
            document.body.appendChild(element);
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="toggle-create-form"]').click();
            await flushPromises();

            const customerSearch = element.shadowRoot.querySelector('[data-id="job-customer-search"]');
            customerSearch.value = 'Ramesh';
            customerSearch.dispatchEvent(new CustomEvent('change'));
            await flushPromises();
            element.shadowRoot.querySelector('button[data-id="cust1"]').click();
            return element;
        }

        it('picking a customer fills in their first vehicle, ready to submit', async () => {
            searchVehicles.mockResolvedValue([CITY, SWIFT]);
            const element = await openFormAndPickCustomer();
            await flushPromises();

            expect(searchVehicles).toHaveBeenCalledWith({ customerId: 'cust1', searchTerm: '' });
            expect(element.shadowRoot.textContent).toContain('MP09AA1111');
            expect(element.shadowRoot.querySelector('[data-id="job-vehicle-search"]')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="submit-job"]').disabled).toBe(false);

            element.shadowRoot.querySelector('[data-id="submit-job"]').click();
            await flushPromises();
            expect(createJob.mock.calls[0][0].request.vehicleId).toBe('veh1');
        });

        it('a customer with no vehicles is left to search or add one', async () => {
            searchVehicles.mockResolvedValue([]);
            const element = await openFormAndPickCustomer();
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="job-vehicle-search"]')).not.toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="submit-job"]').disabled).toBe(true);
        });

        it('Change lists the other vehicles of the customer, and one can be picked', async () => {
            searchVehicles.mockResolvedValue([CITY, SWIFT]);
            const element = await openFormAndPickCustomer();
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="change-vehicle"]').click();
            await flushPromises();
            expect(element.shadowRoot.querySelector('button[data-id="veh1"]')).not.toBeNull();

            element.shadowRoot.querySelector('button[data-id="veh2"]').click();
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="submit-job"]').click();
            await flushPromises();

            expect(createJob.mock.calls[0][0].request.vehicleId).toBe('veh2');
        });

        it('does not overwrite This is a new vehicle if it was turned on while loading', async () => {
            let finishLoading;
            searchVehicles.mockReturnValue(new Promise((resolve) => {
                finishLoading = resolve;
            }));
            const element = await openFormAndPickCustomer();
            await flushPromises();

            const toggle = element.shadowRoot.querySelector('[data-id="new-vehicle-toggle"]');
            toggle.checked = true;
            toggle.dispatchEvent(new CustomEvent('change'));
            await flushPromises();
            finishLoading([CITY]);
            await flushPromises();

            expect(element.shadowRoot.textContent).not.toContain('MP09AA1111');
            expect(element.shadowRoot.querySelector('[data-field="registrationNumber"]')).not.toBeNull();
        });

        it('ignores a late answer for a customer that was since changed', async () => {
            let finishLoading;
            searchVehicles.mockReturnValue(new Promise((resolve) => {
                finishLoading = resolve;
            }));
            const element = await openFormAndPickCustomer();
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="change-customer"]').click();
            await flushPromises();
            finishLoading([CITY]);
            await flushPromises();

            expect(element.shadowRoot.textContent).not.toContain('MP09AA1111');
        });
    });
});
