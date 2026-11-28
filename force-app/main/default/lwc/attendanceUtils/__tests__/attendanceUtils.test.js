import {
    shiftMonth, shiftDay, monthStart, rupees, balanceText, earnedDetail, payText, calendarWeeks, dayCounts
} from 'c/attendanceUtils';

describe('c/attendanceUtils', () => {
    it('steps months and days across year ends', () => {
        expect(shiftMonth('2026-01-15', -1)).toBe('2025-12-01');
        expect(shiftMonth('2026-12-01', 1)).toBe('2027-01-01');
        expect(shiftDay('2026-03-01', -1)).toBe('2026-02-28');
        expect(monthStart('2026-11-25')).toBe('2026-11-01');
    });

    it('writes rupees with Indian grouping, paise only when there are some', () => {
        expect(rupees(150000)).toBe('₹1,50,000');
        expect(rupees(-800)).toBe('₹800');
        expect(rupees(99.5)).toBe('₹99.50');
        expect(rupees(null)).toBe('₹0');
    });

    it('says in one line who owes whom', () => {
        expect(balanceText('Raju', 4200, false)).toEqual({ text: 'Due to Raju: ₹4,200', cls: 'ab-balance ab-balance_due' });
        expect(balanceText('Raju', 4200, true).text).toBe('Left to pay Raju: ₹4,200');
        expect(balanceText('Raju', -800, true)).toEqual({ text: 'Raju owes ₹800', cls: 'ab-balance ab-balance_owes' });
        expect(balanceText('Raju', 0, true).text).toBe('Raju: all settled');
        expect(balanceText('Raju', 0.004, true).text).toBe('Raju: all settled');
    });

    it('explains how the pay was worked out', () => {
        expect(earnedDetail({ monthPayType: 'Monthly', monthPayAmount: 15000, daysAbsent: 2.5, offDaysWorked: 1 }))
            .toBe('₹15,000 salary, less 2.5 days absent, plus 1 weekly off worked');
        expect(earnedDetail({ monthPayType: 'Monthly', monthPayAmount: 15000, daysAbsent: 0 })).toBe('₹15,000 salary');
        expect(earnedDetail({ monthPayType: 'Daily', monthPayAmount: 600, daysPresent: 3.5, leaveDays: 1 })).toBe('₹600 a day × 4.5 days');
        expect(earnedDetail({ monthPayType: 'Daily', monthPayAmount: 600, daysPresent: 1, leaveDays: 0 })).toBe('₹600 a day × 1 day');
        expect(earnedDetail({ monthPayAmount: null })).toBe('No salary set for this month.');
    });

    it('describes the pay setting', () => {
        expect(payText({ hasPay: true, payType: 'Monthly', payAmount: 15000, weeklyOff: 'Sunday' })).toBe('₹15,000 a month · off on Sunday');
        expect(payText({ hasPay: true, payType: 'Daily', payAmount: 600, weeklyOff: 'None' })).toBe('₹600 a day · no weekly off');
        expect(payText({ hasPay: false })).toBe('Salary not set yet');
    });

    it('lays a month out in weeks starting on Monday', () => {
        // A 30-day month starting on a Wednesday (index 2).
        const days = Array.from({ length: 30 }, (_, i) => ({
            day: `2026-04-${String(i + 1).padStart(2, '0')}`,
            dayNumber: i + 1,
            status: i === 0 ? 'A' : '-',
            isWeeklyOff: i === 4,
            isFuture: i > 20
        }));
        const weeks = calendarWeeks(2, days, '2026-04-02');

        expect(weeks).toHaveLength(5);
        weeks.forEach((w) => expect(w.cells).toHaveLength(7));
        expect(weeks[0].cells[0].isBlank).toBe(true);
        expect(weeks[0].cells[2]).toMatchObject({ dayNumber: 1, mark: 'A' });
        expect(weeks[0].cells[2].cls).toContain('ab-absent');
        expect(weeks[0].cells[3].cls).toContain('ab-selected');
        expect(weeks[0].cells[6]).toMatchObject({ dayNumber: 5, mark: 'Off', title: expect.stringContaining('Weekly off') });
        expect(weeks[3].cells[1].isFuture).toBe(false);
        expect(weeks[3].cells[2]).toMatchObject({ dayNumber: 22, isFuture: true });
        expect(weeks[4].cells[6].isBlank).toBe(true);
    });

    it('counts the day, leaving a weekly off out of "not marked"', () => {
        expect(dayCounts([
            { status: 'P' }, { status: 'P' }, { status: 'A' }, { status: 'H' },
            { status: '-', isWeeklyOff: true }, { status: '-' }
        ])).toEqual({ P: 2, H: 1, A: 1, L: 0, unmarked: 1 });
    });
});
