import { createElement } from 'lwc';
import AttendanceBook from 'c/attendanceBook';
import getDay from '@salesforce/apex/AttendanceController.getDay';
import markDay from '@salesforce/apex/AttendanceController.markDay';
import markAllPresent from '@salesforce/apex/AttendanceController.markAllPresent';
import getMonth from '@salesforce/apex/AttendanceController.getMonth';
import getPayMonth from '@salesforce/apex/AttendanceController.getPayMonth';
import addEntry from '@salesforce/apex/AttendanceController.addEntry';
import removeEntry from '@salesforce/apex/AttendanceController.removeEntry';
import savePay from '@salesforce/apex/AttendanceController.savePay';

jest.mock('@salesforce/apex/AttendanceController.getDay', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AttendanceController.markDay', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AttendanceController.markAllPresent', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AttendanceController.getMonth', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AttendanceController.getPayMonth', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AttendanceController.addEntry', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AttendanceController.removeEntry', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/AttendanceController.savePay', () => ({ default: jest.fn() }), { virtual: true });

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

function todayIso() {
    const d = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
const MONTH = todayIso().slice(0, 7) + '-01';

const DAY = {
    day: todayIso(),
    rows: [
        { mechanicId: 'm1', name: 'Anil', status: '-', isWeeklyOff: false },
        { mechanicId: 'm2', name: 'Deepak', status: '-', isWeeklyOff: true }
    ]
};

function monthData(overrides = {}) {
    return {
        mechanicId: 'm1', name: 'Anil', isActive: true, month: MONTH, hasPay: true,
        payType: 'Monthly', payAmount: 15000, weeklyOff: 'Sunday', monthPayType: 'Monthly', monthPayAmount: 15000,
        firstWeekday: 0,
        days: Array.from({ length: 28 }, (_, i) => ({ day: `${MONTH.slice(0, 8)}${String(i + 1).padStart(2, '0')}`, dayNumber: i + 1, status: '-', isWeeklyOff: false, isFuture: false })),
        daysPresent: 0, daysAbsent: 0, halfDays: 0, leaveDays: 0, offDays: 0, offDaysWorked: 0,
        earned: 15000, extra: 0, advances: 0, paid: 0, broughtForward: 0, balance: 15000, entries: [],
        ...overrides
    };
}

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function createScreen() {
    const element = createElement('c-attendance-book', { is: AttendanceBook });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

const $ = (el, sel) => el.shadowRoot.querySelector(sel);
const $$ = (el, sel) => [...el.shadowRoot.querySelectorAll(sel)];

async function openTab(element, view) {
    $(element, `button[data-view="${view}"]`).click();
    await flushPromises();
    await flushPromises();
}

function buttonByLabel(root, label) {
    return [...root.querySelectorAll('lightning-button')].find((b) => b.label === label);
}

describe('c-attendance-book', () => {
    beforeEach(() => {
        getDay.mockResolvedValue(JSON.parse(JSON.stringify(DAY)));
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    describe('Today', () => {
        it('lists the mechanics with big Present / Half day / Absent buttons, and counts the day', async () => {
            const element = await createScreen();

            const rows = $$(element, '[data-id="day-row"]');
            expect(rows).toHaveLength(2);
            expect(rows[0].textContent).toContain('Anil');
            expect(rows[0].querySelectorAll('[data-id="mark"]')).toHaveLength(3);
            expect(rows[1].querySelector('[data-id="row-status"]').textContent).toBe('Weekly off');
            expect($(element, '[data-id="day-counts"]').textContent).toBe('0 present · 0 absent · 1 not marked');
            expect(getDay).toHaveBeenCalledWith({ day: todayIso() });
        });

        it('one tap marks a mechanic, and tapping the same mark again takes it off', async () => {
            markDay.mockResolvedValueOnce({ mechanicId: 'm1', status: 'A' }).mockResolvedValueOnce({ mechanicId: 'm1', status: '-' });
            const element = await createScreen();

            $$(element, '[data-id="mark"]')[2].click();
            await flushPromises();
            expect(markDay).toHaveBeenCalledWith({ mechanicId: 'm1', day: todayIso(), status: 'A' });
            const absent = $$(element, '[data-id="mark"]')[2];
            expect(absent.getAttribute('aria-pressed')).toBe('true');
            expect(absent.className).toContain('ab-mark_on');
            expect($(element, '[data-id="day-counts"]').textContent).toBe('0 present · 1 absent');

            $$(element, '[data-id="mark"]')[2].click();
            await flushPromises();
            expect(markDay).toHaveBeenLastCalledWith({ mechanicId: 'm1', day: todayIso(), status: '-' });
            expect($$(element, '[data-id="day-row"]')[0].querySelector('[data-id="row-status"]').textContent).toBe('Not marked yet');
        });

        it('a mark that could not be saved goes back, with the reason', async () => {
            markDay.mockRejectedValue({ body: { message: 'Attendance can\'t be marked for a day that hasn\'t come yet.' } });
            const element = await createScreen();
            const toast = jest.fn();
            element.addEventListener('lightning__showtoast', toast);

            $$(element, '[data-id="mark"]')[0].click();
            await flushPromises();
            await flushPromises();

            expect($$(element, '[data-id="mark"]')[0].getAttribute('aria-pressed')).toBe('false');
            expect(toast.mock.calls[0][0].detail.message).toContain('hasn\'t come yet');
        });

        it('marks everyone else present in one go', async () => {
            markAllPresent.mockResolvedValue({ day: todayIso(), rows: [{ ...DAY.rows[0], status: 'P' }, DAY.rows[1]] });
            const element = await createScreen();

            $(element, '[data-id="mark-all"]').click();
            await flushPromises();

            expect(markAllPresent).toHaveBeenCalledWith({ day: todayIso() });
            expect($(element, '[data-id="day-counts"]').textContent).toBe('1 present · 0 absent');
            expect($(element, '[data-id="mark-all"]').disabled).toBe(true);
        });

        it('with no mechanics yet, says so and offers to add them', async () => {
            getDay.mockResolvedValue({ day: todayIso(), rows: [] });
            const element = await createScreen();

            expect($(element, '[data-id="no-mechanics"]')).not.toBeNull();
            buttonByLabel(element.shadowRoot, 'Add mechanics').click();
            expect(mockNavigate).toHaveBeenCalledWith({ type: 'standard__navItemPage', attributes: { apiName: 'Mechanic_List' } });
        });
    });

    describe('Month', () => {
        it('shows the first mechanic\'s calendar, and a tapped day can be changed', async () => {
            getMonth.mockResolvedValue(monthData());
            markDay.mockResolvedValue({ mechanicId: 'm1', status: 'H' });
            const element = await createScreen();
            await openTab(element, 'month');

            expect(getMonth).toHaveBeenCalledWith({ mechanicId: 'm1', month: MONTH });
            expect($$(element, '[data-id="cal-day"]')).toHaveLength(28);
            expect($(element, '[data-id="month-earned"]').textContent).toBe('₹15,000 — ₹15,000 salary');

            $$(element, '[data-id="cal-day"]')[2].click();
            await flushPromises();
            const halfDay = $$(element, '[data-id="cal-mark"]').find((b) => b.textContent === 'Half day');
            halfDay.click();
            await flushPromises();

            expect(markDay).toHaveBeenCalledWith({ mechanicId: 'm1', day: `${MONTH.slice(0, 8)}03`, status: 'H' });
            expect(getMonth).toHaveBeenCalledTimes(2);
        });

        it('an archived month is shown, but its days can\'t be changed', async () => {
            getMonth.mockResolvedValue(monthData({ isArchived: true }));
            const element = await createScreen();
            await openTab(element, 'month');

            expect($(element, '[data-id="month-archived"]').textContent).toContain('archived');
            $$(element, '[data-id="cal-day"]')[2].click();
            await flushPromises();
            expect($(element, '[data-id="day-edit"]')).toBeNull();
            expect(markDay).not.toHaveBeenCalled();
        });

        it('switches mechanic with the chips', async () => {
            getMonth.mockResolvedValue(monthData());
            const element = await createScreen();
            await openTab(element, 'month');

            $$(element, '[data-id="mechanic-chip"]')[1].click();
            await flushPromises();

            expect(getMonth).toHaveBeenLastCalledWith({ mechanicId: 'm2', month: MONTH });
        });
    });

    describe('Pay', () => {
        it('says what is left to pay, and gives an advance', async () => {
            getPayMonth.mockResolvedValue([monthData()]);
            addEntry.mockResolvedValue(monthData({
                advances: 3000, balance: 12000,
                entries: [{ id: 'e1', type: 'advance', amount: 3000, entryDate: todayIso(), method: 'UPI', note: 'Rent' }]
            }));
            const element = await createScreen();
            await openTab(element, 'pay');

            expect($(element, '[data-id="balance"]').textContent).toBe('Left to pay Anil: ₹15,000');

            $(element, '[data-id="give-advance"]').click();
            await flushPromises();
            const form = $(element, '[data-id="entry-form"]');
            expect(form.textContent).toContain('Give advance');
            const amount = form.querySelector('[data-id="entry-amount"]');
            amount.value = '3000';
            amount.dispatchEvent(new CustomEvent('change', { detail: { value: '3000' } }));
            $(element, '[data-id="save-entry"]').click();
            await flushPromises();

            expect(addEntry).toHaveBeenCalledWith({ input: { mechanicId: 'm1', type: 'advance', amount: 3000, entryDate: todayIso(), method: 'Cash', note: '' } });
            expect($(element, '[data-id="balance"]').textContent).toBe('Left to pay Anil: ₹12,000');
            expect($(element, '[data-id="entries"]').textContent).toContain('UPI · Rent');
        });

        it('Pay salary starts at what is left to pay', async () => {
            getPayMonth.mockResolvedValue([monthData({ balance: 11500 })]);
            addEntry.mockResolvedValue(monthData({ paid: 11500, balance: 0 }));
            const element = await createScreen();
            await openTab(element, 'pay');

            $(element, '[data-id="pay-salary"]').click();
            await flushPromises();
            $(element, '[data-id="save-entry"]').click();
            await flushPromises();

            expect(addEntry.mock.calls[0][0].input).toMatchObject({ type: 'payment', amount: 11500 });
            expect($(element, '[data-id="balance"]').textContent).toBe('Anil: all settled');
        });

        it('an entry typed by mistake is removed after asking', async () => {
            const withEntry = monthData({ advances: 500, balance: 14500, entries: [{ id: 'e1', type: 'advance', amount: 500, entryDate: todayIso(), method: 'Cash' }] });
            getPayMonth.mockResolvedValue([withEntry]);
            removeEntry.mockResolvedValue(monthData());
            const element = await createScreen();
            await openTab(element, 'pay');

            $(element, '[data-id="remove-entry"]').click();
            await flushPromises();
            expect(removeEntry).not.toHaveBeenCalled();
            $(element, '[data-id="confirm-remove"]').click();
            await flushPromises();

            expect(removeEntry).toHaveBeenCalledWith({ mechanicId: 'm1', month: MONTH, entryId: 'e1' });
            expect($(element, '[data-id="entries"]')).toBeNull();
        });

        it('a mechanic with no salary set is asked for one, and it is saved', async () => {
            getPayMonth.mockResolvedValueOnce([monthData({ hasPay: false, payType: null, payAmount: null })]).mockResolvedValue([monthData()]);
            savePay.mockResolvedValue(monthData());
            const element = await createScreen();
            await openTab(element, 'pay');

            expect($(element, '[data-id="pay-card"]').textContent).toContain('Set this mechanic\'s salary');
            $(element, '[data-id="edit-pay"]').click();
            await flushPromises();
            const amount = [...$(element, '[data-id="pay-form"]').querySelectorAll('lightning-input')][0];
            amount.dispatchEvent(new CustomEvent('change', { detail: { value: '15000' } }));
            $(element, '[data-id="save-pay"]').click();
            await flushPromises();
            await flushPromises();

            expect(savePay).toHaveBeenCalledWith({ input: { mechanicId: 'm1', payType: 'Monthly', payAmount: 15000, weeklyOff: 'Sunday' } });
            expect($(element, '[data-id="balance"]').textContent).toBe('Left to pay Anil: ₹15,000');
        });

        it('an archived month shows its pay and entries, with nothing to change', async () => {
            getPayMonth.mockResolvedValue([monthData({ isArchived: true, advances: 5000, balance: 10000,
                entries: [{ id: 'e1', type: 'advance', amount: 5000, entryDate: MONTH, method: 'Cash' }] })]);
            const element = await createScreen();
            await openTab(element, 'pay');

            expect($(element, '[data-id="pay-archived"]')).not.toBeNull();
            expect(buttonByLabel(element.shadowRoot, 'Give advance')).toBeUndefined();
            expect($(element, '[data-id="entries"]').textContent).toContain('5,000');
            expect($(element, '[data-id="remove-entry"]')).toBeNull();
        });

        it('a past month says what is due, not what is left', async () => {
            getPayMonth.mockResolvedValue([monthData({ balance: 2000 })]);
            const element = await createScreen();
            await openTab(element, 'pay');

            $(element, '[data-id="prev-pay-month"]').click();
            await flushPromises();

            expect(getPayMonth).toHaveBeenLastCalledWith({ month: expect.stringMatching(/-01$/) });
            expect($(element, '[data-id="balance"]').textContent).toBe('Due to Anil: ₹2,000');
        });
    });
});
