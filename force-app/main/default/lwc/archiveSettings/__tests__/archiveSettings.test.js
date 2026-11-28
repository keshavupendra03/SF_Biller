import { createElement } from 'lwc';
import ArchiveSettings from 'c/archiveSettings';
import getStatus from '@salesforce/apex/ArchiveController.getStatus';
import saveRules from '@salesforce/apex/ArchiveController.saveRules';
import runNow from '@salesforce/apex/ArchiveController.runNow';

jest.mock('@salesforce/apex/ArchiveController.getStatus', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ArchiveController.saveRules', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ArchiveController.runNow', () => ({ default: jest.fn() }), { virtual: true });

const RULES = {
    isOn: false, billsAfterMonths: 18, estimatesAfterMonths: 6, jobsAfterMonths: 6, jobSlipsAfterMonths: 6,
    customersDormantMonths: 24, mechanicMonthsAfterMonths: 24, storageAlertPercent: 70, lastRun: null, lastResult: null
};

function status(overrides = {}) {
    return {
        rules: { ...RULES }, dataUsedMb: 2, dataLimitMb: 5, fileUsedMb: 0, fileLimitMb: 20,
        archiveKb: 0, archiveFiles: 0, archivedBills: 0,
        billsReady: 12, billMonthsReady: ['2024-10', '2024-11'], billsBefore: '2025-05-01',
        estimatesToDelete: 3, estimatesBefore: '2026-05-26', downloadUrl: null,
        archivedCustomers: 0, archivedCars: 0, customersReady: 0, carsReady: 0, customersBefore: '2024-11-26', customersDue: true,
        archivedJobs: 0, archivedSlips: 0, archivedMonths: 0, jobsReady: 0, slipsReady: 0, jobsBefore: '2026-05-26', slipsBefore: '2026-05-26',
        workDue: true, monthsReady: 0, monthsBefore: '2024-11-01',
        ...overrides
    };
}

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function open() {
    const element = createElement('c-archive-settings', { is: ArchiveSettings });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

const $ = (el, sel) => el.shadowRoot.querySelector(sel);

describe('c-archive-settings', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows storage, the rules and what would happen now', async () => {
        getStatus.mockResolvedValue(status());
        const element = await open();

        expect($(element, '[data-id="data-text"]').textContent).toBe('2 MB of 5 MB used (40%)');
        expect($(element, '.as-bar-text:not([data-id])').textContent).toBe('Under 1 MB of 20 MB used');
        expect($(element, '[data-id="data-warning"]')).toBeNull();
        expect($(element, '[data-id="archive-text"]').textContent).toBe('Nothing archived yet.');
        expect($(element, '[data-id="bills-months"]').value).toBe(18);
        expect($(element, '[data-id="bills-ready"]').textContent).toBe('12 bills ready to archive: Oct 2024, Nov 2024.');
        expect($(element, '[data-id="estimates-ready"]').textContent).toContain('3 old estimates');
        expect($(element, '[data-id="download"]')).toBeNull();
    });

    it('warns when storage is above the chosen percent, and offers the archive download', async () => {
        getStatus.mockResolvedValue(status({ dataUsedMb: 4, archiveFiles: 3, archivedBills: 40, archiveKb: 12.5, downloadUrl: '/sfc/servlet.shepherd/document/download/d1/d2' }));
        const element = await open();

        expect($(element, '[data-id="data-warning"]')).not.toBeNull();
        expect($(element, '[data-id="archive-text"]').textContent).toBe('40 bills archived in 3 files (12.5 KB).');
        expect($(element, '[data-id="download"]').getAttribute('href')).toBe('/sfc/servlet.shepherd/document/download/d1/d2');
    });

    it('saves the rules as typed', async () => {
        getStatus.mockResolvedValue(status());
        saveRules.mockImplementation(({ rules }) => Promise.resolve(status({ rules })));
        const element = await open();

        $(element, '[data-id="is-on"]').dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));
        $(element, '[data-id="bills-months"]').dispatchEvent(new CustomEvent('change', { detail: { value: '12' } }));
        $(element, '[data-id="estimates-months"]').dispatchEvent(new CustomEvent('change', { detail: { value: '3' } }));
        $(element, '[data-id="save"]').click();
        await flushPromises();

        expect(saveRules).toHaveBeenCalledWith({ rules: expect.objectContaining({ isOn: true, billsAfterMonths: 12, estimatesAfterMonths: 3 }) });
    });

    it('Run now asks first, then starts the job', async () => {
        getStatus.mockResolvedValue(status());
        runNow.mockResolvedValue();
        const element = await open();

        $(element, '[data-id="run-now"]').click();
        await flushPromises();
        expect(runNow).not.toHaveBeenCalled();
        $(element, '[data-id="confirm-run-yes"]').click();
        await flushPromises();

        expect(runNow).toHaveBeenCalled();
    });

    it('with nothing ready, Run now is off and says why', async () => {
        getStatus.mockResolvedValue(status({ billsReady: 0, billMonthsReady: [], estimatesToDelete: 0 }));
        const element = await open();

        expect($(element, '[data-id="run-now"]').disabled).toBe(true);
        expect($(element, '[data-id="bills-ready"]').textContent).toContain('No bills are ready.');
        expect($(element, '[data-id="customers-ready"]').textContent).toBe('No customers are ready. Customers and Walk-in cars not seen since 26 Nov 2024 are archived.');
        expect($(element, '[data-id="work-ready"]').textContent).toBe('No jobs or job slips are ready. Jobs not moved since 26 May 2026 and job slips dated before 26 May 2026 are archived.');
        expect($(element, '[data-id="attendance-ready"]').textContent).toBe('No attendance is ready. Months before Nov 2024 are archived.');
    });

    it('shows jobs, job slips and attendance ready, and saves their rules', async () => {
        getStatus.mockResolvedValue(status({
            billsReady: 0, billMonthsReady: [], estimatesToDelete: 0, jobsReady: 12, slipsReady: 1, workDue: false, monthsReady: 6,
            archiveFiles: 3, archivedBills: 0, archivedJobs: 40, archivedSlips: 9, archivedMonths: 18, archiveKb: 8
        }));
        saveRules.mockImplementation(({ rules }) => Promise.resolve(status({ rules })));
        const element = await open();

        expect($(element, '[data-id="work-ready"]').textContent).toContain('12 jobs and 1 job slip ready to archive.');
        expect($(element, '[data-id="work-ready"]').textContent).toContain('Run now archives them');
        expect($(element, '[data-id="attendance-ready"]').textContent).toBe('6 attendance months (before Nov 2024) ready to archive.');
        expect($(element, '[data-id="run-now"]').disabled).toBe(false);
        expect($(element, '[data-id="archive-text"]').textContent).toBe('0 bills, 40 jobs, 9 job slips, 18 attendance months archived in 3 files (8 KB).');

        $(element, '[data-id="jobs-months"]').dispatchEvent(new CustomEvent('change', { detail: { value: '3' } }));
        $(element, '[data-id="slips-months"]').dispatchEvent(new CustomEvent('change', { detail: { value: '12' } }));
        $(element, '[data-id="attendance-months"]').dispatchEvent(new CustomEvent('change', { detail: { value: '36' } }));
        $(element, '[data-id="save"]').click();
        await flushPromises();
        expect(saveRules).toHaveBeenCalledWith({ rules: expect.objectContaining({ jobsAfterMonths: 3, jobSlipsAfterMonths: 12, mechanicMonthsAfterMonths: 36 }) });
    });

    it('shows dormant customers ready, their rule, and what the archive holds', async () => {
        getStatus.mockResolvedValue(status({
            billsReady: 0, billMonthsReady: [], estimatesToDelete: 0, customersReady: 4, carsReady: 1, customersDue: false,
            archiveFiles: 4, archivedBills: 10, archivedCustomers: 7, archivedCars: 1, archiveKb: 20
        }));
        saveRules.mockImplementation(({ rules }) => Promise.resolve(status({ rules })));
        const element = await open();

        const ready = $(element, '[data-id="customers-ready"]').textContent;
        expect(ready).toContain('4 customers and 1 Walk-in car not seen since 26 Nov 2024 ready to archive.');
        expect(ready).toContain('Run now archives them');
        expect($(element, '[data-id="run-now"]').disabled).toBe(false);
        expect($(element, '[data-id="archive-text"]').textContent).toBe('10 bills, 7 customers, 1 Walk-in car archived in 4 files (20 KB).');
        expect($(element, '[data-id="customers-months"]').value).toBe(24);

        $(element, '[data-id="customers-months"]').dispatchEvent(new CustomEvent('change', { detail: { value: '36' } }));
        $(element, '[data-id="save"]').click();
        await flushPromises();
        expect(saveRules).toHaveBeenCalledWith({ rules: expect.objectContaining({ customersDormantMonths: 36 }) });
    });
});
