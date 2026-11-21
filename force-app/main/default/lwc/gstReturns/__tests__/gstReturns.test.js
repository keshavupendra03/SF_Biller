import { createElement } from 'lwc';
import GstReturns from 'c/gstReturns';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';
import getReturn from '@salesforce/apex/GstReturnController.getReturn';
import downloadReturn from '@salesforce/apex/GstReturnController.downloadReturn';
import setGstFiledUpTo from '@salesforce/apex/WorkshopProfileController.setGstFiledUpTo';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GstReturnController.getReturn', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GstReturnController.downloadReturn', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WorkshopProfileController.setGstFiledUpTo', () => ({ default: jest.fn() }), { virtual: true });

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

const COMPANY = { id: 'wp1', name: 'Speedy Motors', gstin: '23AAACI7904G1ZV', gstFilingFrequency: 'Monthly', gstFiledUpTo: null };

const RETURN = {
    companyId: 'wp1', companyName: 'Speedy Motors', gstin: '23AAACI7904G1ZV', registrationType: 'Regular', filingFrequency: 'Monthly',
    startDate: '2026-10-01', endDate: '2026-10-31', isFiled: false, filedUpTo: null, billCount: 3, invoiceValue: 120570,
    b2b: [
        { billId: 'b1', gstin: '27AAPFU0939F1ZV', receiverName: 'Mumbai Fleet', invoiceNumber: 'INV/2026-27/0001', invoiceDate: '2026-10-02', invoiceValue: 2360, placeOfSupply: '27-Maharashtra', rate: 18, taxableValue: 2000, igst: 360, cgst: 0, sgst: 0 }
    ],
    b2cl: [
        { billId: 'b2', invoiceNumber: 'INV/2026-27/0002', invoiceDate: '2026-10-03', invoiceValue: 118000, placeOfSupply: '27-Maharashtra', rate: 18, taxableValue: 100000, igst: 18000, cgst: 0, sgst: 0 }
    ],
    b2cs: [{ placeOfSupply: '23-Madhya Pradesh', rate: 18, taxableValue: 500, igst: 0, cgst: 45, sgst: 45 }],
    nil: [{ description: 'Intra-State supplies to unregistered persons', nilRated: 700 }],
    hsnB2b: [{ hsn: '8708', description: 'Clutch', uqc: 'PCS-PIECES', quantity: 1, totalValue: 2360, rate: 18, taxableValue: 2000, igst: 360, cgst: 0, sgst: 0 }],
    hsnB2c: [{ hsn: '', description: 'Clip', uqc: 'PCS-PIECES', quantity: 1, totalValue: 59, rate: 18, taxableValue: 50, igst: 0, cgst: 4.5, sgst: 4.5 }],
    documents: [{ nature: 'Invoices for outward supply', fromNumber: 'INV/2026-27/0001', toNumber: 'INV/2026-27/0004', totalNumber: 4, cancelled: 1, netIssued: 3 }],
    gstr3b: { taxableValue: 102500, igst: 18360, cgst: 45, sgst: 45, nilRated: 700, unregisteredInterState: [{ placeOfSupply: '27-Maharashtra', taxableValue: 100000, igst: 18000 }] },
    issues: [
        { severity: 'error', message: 'No HSN/SAC on "Clip".', billId: 'b3', documentNumber: 'INV/2026-27/0003' },
        { severity: 'warning', message: '1 bill(s) worth Rs. 700.00 have no GST.', billId: null, documentNumber: null }
    ],
    errorCount: 1,
    warningCount: 1
};

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function createScreen() {
    const element = createElement('c-gst-returns', { is: GstReturns });
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();
    return element;
}

function $(element, selector) {
    return element.shadowRoot.querySelector(selector);
}

function $$(element, selector) {
    return [...element.shadowRoot.querySelectorAll(selector)];
}

describe('c-gst-returns', () => {
    beforeEach(() => {
        listProfiles.mockResolvedValue([COMPANY]);
        getReturn.mockResolvedValue(RETURN);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('opens on the last month that is over, for the company', async () => {
        const element = await createScreen();

        const now = new Date();
        const last = new Date(now.getFullYear(), now.getMonth(), 0);
        const pad = (n) => String(n).padStart(2, '0');
        const end = `${last.getFullYear()}-${pad(last.getMonth() + 1)}-${pad(last.getDate())}`;
        expect(getReturn).toHaveBeenCalledWith({ companyId: 'wp1', startDate: `${end.slice(0, 8)}01`, endDate: end });
        expect($(element, '[data-id="period"]').value).toBe(`${end.slice(0, 8)}01|${end}`);
    });

    it('a quarterly filer picks quarters', async () => {
        listProfiles.mockResolvedValue([{ ...COMPANY, gstFilingFrequency: 'Quarterly' }]);
        const element = await createScreen();

        expect($(element, '[data-id="period"]').options[1].label).toMatch(/^(Jan-Mar|Apr-Jun|Jul-Sep|Oct-Dec) \d{4}$/);
    });

    it('shows the checkup first: errors to put right, warnings to check, each bill one tap away', async () => {
        const element = await createScreen();

        expect($(element, '[data-id="checkup-title"]').textContent).toBe('1 to put right before filing, 1 to check');
        const issues = $$(element, '[data-id="issue"]');
        expect(issues).toHaveLength(2);
        expect(issues[0].className).toContain('gr-issue_error');
        expect(issues[0].textContent).toContain('No HSN/SAC');

        $(element, '[data-id="issue-bill"]').click();
        expect(mockNavigate).toHaveBeenCalledWith({ type: 'standard__navItemPage', attributes: { apiName: 'Bill_Detail' }, state: { c__recordId: 'b3' } });
    });

    it('a clean return says it is ready to file', async () => {
        getReturn.mockResolvedValue({ ...RETURN, issues: [], errorCount: 0, warningCount: 0 });
        const element = await createScreen();

        expect($(element, '[data-id="checkup-title"]').textContent).toBe('Ready to file: no problems found.');
    });

    it('sums each GSTR-1 table, and lays out GSTR-3B', async () => {
        const element = await createScreen();

        const tile = (key) => $(element, `[data-tile="${key}"]`).textContent;
        expect(tile('b2b')).toContain('1 invoice(s)');
        expect(tile('b2b')).toContain('Taxable Rs. 2,000.00');
        expect(tile('b2b')).toContain('Tax Rs. 360.00');
        expect(tile('b2cl')).toContain('Tax Rs. 18,000.00');
        expect(tile('nil')).toContain('Taxable Rs. 700.00');
        expect(tile('docs')).toContain('3 issued, 1 cancelled');
        expect($(element, '[data-id="b2b-table"]').textContent).toContain('Mumbai Fleet');
        expect($(element, '[data-id="hsn-table"]').textContent).toContain('(none)');
        const gstr3b = $(element, '[data-id="gstr3b-table"]').textContent;
        expect(gstr3b).toContain('3.1(a) Taxable supplies');
        expect(gstr3b).toContain('1,02,500.00');
        expect(gstr3b).toContain('3.2 Unregistered, 27-Maharashtra');
    });

    it('Mark as filed waits until the errors are put right', async () => {
        const element = await createScreen();

        expect($(element, '[data-id="mark-filed"]').disabled).toBe(true);
        expect($(element, '[data-id="mark-filed-hint"]').textContent).toContain('Put right the errors');
    });

    it('Mark as filed asks, then locks the period and reloads it', async () => {
        getReturn.mockResolvedValue({ ...RETURN, issues: [], errorCount: 0, warningCount: 0 });
        setGstFiledUpTo.mockImplementation(({ filedUpTo }) => Promise.resolve({ ...COMPANY, gstFiledUpTo: filedUpTo }));
        const element = await createScreen();
        const period = $(element, '[data-id="period"]').value.split('|');

        $(element, '[data-id="mark-filed"]').click();
        await flushPromises();
        expect($(element, '[data-id="confirm-filed"]').textContent).toContain('will be locked');
        getReturn.mockResolvedValue({ ...RETURN, issues: [], errorCount: 0, warningCount: 0, isFiled: true, filedUpTo: period[1] });
        $(element, '[data-id="confirm-filed-yes"]').click();
        await flushPromises();
        await flushPromises();

        expect(setGstFiledUpTo).toHaveBeenCalledWith({ companyId: 'wp1', filedUpTo: period[1] });
        expect($(element, '[data-id="status"]').textContent).toContain('Filed');
        expect($(element, '[data-id="mark-filed"]')).toBeNull();
        expect($(element, '[data-id="unmark-filed"]')).not.toBeNull();
    });

    it('a filed period can be unlocked, back to the month before it', async () => {
        getReturn.mockResolvedValue({ ...RETURN, isFiled: true, filedUpTo: '2026-10-31' });
        setGstFiledUpTo.mockResolvedValue({ ...COMPANY, gstFiledUpTo: null });
        const element = await createScreen();
        const start = $(element, '[data-id="period"]').value.split('|')[0];

        $(element, '[data-id="unmark-filed"]').click();
        await flushPromises();

        const day = new Date(`${start}T00:00:00`);
        const before = new Date(day.getFullYear(), day.getMonth(), 0);
        const pad = (n) => String(n).padStart(2, '0');
        expect(setGstFiledUpTo).toHaveBeenCalledWith({ companyId: 'wp1', filedUpTo: `${before.getFullYear()}-${pad(before.getMonth() + 1)}-${pad(before.getDate())}` });
    });

    it('Download for CA fetches the zip and saves it', async () => {
        downloadReturn.mockResolvedValue({ fileName: 'GST_23AAACI7904G1ZV_2026-10.zip', base64Data: btoa('zip') });
        global.URL.createObjectURL = jest.fn(() => 'blob:zip');
        global.URL.revokeObjectURL = jest.fn();
        const element = await createScreen();
        const anchor = $(element, 'a');
        anchor.click = jest.fn();

        $(element, '[data-id="download"]').click();
        await flushPromises();

        expect(downloadReturn).toHaveBeenCalledWith(expect.objectContaining({ companyId: 'wp1' }));
        expect(anchor.download).toBe('GST_23AAACI7904G1ZV_2026-10.zip');
        expect(anchor.click).toHaveBeenCalled();
    });

    it('a composition company sees its turnover, not GSTR-1', async () => {
        getReturn.mockResolvedValue({ ...RETURN, registrationType: 'Composition', compositionTurnover: 5000, issues: [], errorCount: 0, warningCount: 0 });
        const element = await createScreen();

        expect($(element, '[data-id="composition-turnover"]').textContent).toBe('Rs. 5,000.00');
        expect($(element, '[data-id="b2b-table"]')).toBeNull();
        expect($(element, '[data-id="download"]')).toBeNull();
    });

    it('a company that is not registered is told it has no returns', async () => {
        getReturn.mockResolvedValue({ ...RETURN, registrationType: 'Unregistered', issues: [], errorCount: 0, warningCount: 0 });
        const element = await createScreen();

        expect($(element, '[data-id="unregistered"]')).not.toBeNull();
        expect($(element, '[data-id="mark-filed"]')).toBeNull();
    });

    it('changing the period loads that return', async () => {
        const element = await createScreen();
        const options = $(element, '[data-id="period"]').options;

        $(element, '[data-id="period"]').dispatchEvent(new CustomEvent('change', { detail: { value: options[3].value } }));
        await flushPromises();

        const [start, end] = options[3].value.split('|');
        expect(getReturn).toHaveBeenLastCalledWith({ companyId: 'wp1', startDate: start, endDate: end });
    });

    describe('returns to file (G5)', () => {
        it('lists each return still to file, late ones marked, from the filed month on', async () => {
            listProfiles.mockResolvedValue([{ ...COMPANY, gstRegistrationType: 'Regular', state: 'Madhya Pradesh', gstFiledUpTo: '2000-01-31' }]);
            const element = await createScreen();

            const due = $$(element, '[data-id="due"]');
            expect(due).toHaveLength(12);
            expect(due[0].textContent).toContain('Late');
            expect(due[0].textContent).toContain('GSTR-1 for');
            expect(due[1].textContent).toContain('GSTR-3B for');
        });

        it('says when nothing is due, and is not shown to a company that isn\'t registered', async () => {
            listProfiles.mockResolvedValue([{ ...COMPANY, gstFiledUpTo: '2099-12-31' }]);
            const element = await createScreen();
            expect($(element, '[data-id="nothing-due"]').textContent).toContain('filed up to December 2099');
            document.body.removeChild(element);

            listProfiles.mockResolvedValue([{ ...COMPANY, gstRegistrationType: 'Unregistered' }]);
            getReturn.mockResolvedValue({ ...RETURN, registrationType: 'Unregistered' });
            const unregistered = await createScreen();
            expect($(unregistered, '[data-id="due-card"]')).toBeNull();
        });

        it('a composition company is reminded of CMP-08', async () => {
            listProfiles.mockResolvedValue([{ ...COMPANY, gstRegistrationType: 'Composition', gstFiledUpTo: '2000-03-31' }]);
            getReturn.mockResolvedValue({ ...RETURN, registrationType: 'Composition' });
            const element = await createScreen();
            const due = $$(element, '[data-id="due"]');
            expect(due.length).toBeGreaterThan(0);
            expect(due.every((d) => d.textContent.includes('CMP-08'))).toBe(true);
        });
    });
});
