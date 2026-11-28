/**
 * Plain helpers for the Attendance screen (attendanceBook): dates, the
 * calendar layout and the words for amounts. No Salesforce calls here, so they
 * are easy to test.
 */

export const STATUS = {
    P: { label: 'Present', short: 'P', cls: 'ab-present' },
    H: { label: 'Half day', short: '½', cls: 'ab-half' },
    A: { label: 'Absent', short: 'A', cls: 'ab-absent' },
    L: { label: 'Paid leave', short: 'L', cls: 'ab-leave' },
    '-': { label: 'Not marked', short: '', cls: 'ab-unmarked' }
};

export const WEEKDAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

export function toIso(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function fromIso(iso) {
    const [year, month, day] = String(iso).slice(0, 10).split('-').map(Number);
    return new Date(year, month - 1, day || 1);
}

export function monthStart(iso) {
    return String(iso).slice(0, 7) + '-01';
}

/** The first day of the month `delta` months away. */
export function shiftMonth(iso, delta) {
    const d = fromIso(monthStart(iso));
    return toIso(new Date(d.getFullYear(), d.getMonth() + delta, 1));
}

export function shiftDay(iso, delta) {
    const d = fromIso(iso);
    return toIso(new Date(d.getFullYear(), d.getMonth(), d.getDate() + delta));
}

export function monthLabel(iso) {
    return fromIso(monthStart(iso)).toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });
}

export function dayLabel(iso) {
    return fromIso(iso).toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
}

export function shortDate(iso) {
    return fromIso(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
}

/** ₹ with Indian grouping, no paise when there are none. */
export function rupees(amount) {
    const n = Number(amount) || 0;
    const whole = Math.round(n * 100) % 100 === 0;
    return '₹' + Math.abs(n).toLocaleString('en-IN', { minimumFractionDigits: whole ? 0 : 2, maximumFractionDigits: 2 });
}

/**
 * The one line that says where a mechanic stands. Positive: the workshop owes
 * the mechanic; negative: the mechanic owes (an advance not yet earned).
 */
export function balanceText(name, balance, isCurrentMonth) {
    const n = Math.round((Number(balance) || 0) * 100) / 100;
    if (n > 0) {
        return { text: `${isCurrentMonth ? 'Left to pay' : 'Due to'} ${name}: ${rupees(n)}`, cls: 'ab-balance ab-balance_due' };
    }
    if (n < 0) {
        return { text: `${name} owes ${rupees(n)}`, cls: 'ab-balance ab-balance_owes' };
    }
    return { text: `${name}: all settled`, cls: 'ab-balance ab-balance_settled' };
}

/** How the month's pay was worked out, in words. */
export function earnedDetail(month) {
    const amount = Number(month.monthPayAmount) || 0;
    if (!amount) {
        return 'No salary set for this month.';
    }
    if (month.monthPayType === 'Daily') {
        const days = (Number(month.daysPresent) || 0) + (Number(month.leaveDays) || 0);
        return `${rupees(amount)} a day × ${days} day${days === 1 ? '' : 's'}`;
    }
    const parts = [`${rupees(amount)} salary`];
    const absent = Number(month.daysAbsent) || 0;
    if (absent) {
        parts.push(`less ${absent} day${absent === 1 ? '' : 's'} absent`);
    }
    if (month.offDaysWorked) {
        parts.push(`plus ${month.offDaysWorked} weekly off worked`);
    }
    return parts.join(', ');
}

/** The pay setting in a few words: "Monthly ₹15,000 · Off on Sunday". */
export function payText(month) {
    if (!month.hasPay) {
        return 'Salary not set yet';
    }
    const kind = month.payType === 'Daily' ? `${rupees(month.payAmount)} a day` : `${rupees(month.payAmount)} a month`;
    const off = !month.weeklyOff || month.weeklyOff === 'None' ? 'no weekly off' : `off on ${month.weeklyOff}`;
    return `${kind} · ${off}`;
}

/**
 * Calendar rows for a month that starts on `firstWeekday` (0 = Monday): blank
 * cells before day 1, then the days, in weeks of seven.
 */
export function calendarWeeks(firstWeekday, days, selectedIso) {
    const cells = [];
    for (let i = 0; i < firstWeekday; i++) {
        cells.push({ key: `blank-${i}`, isBlank: true, cls: 'ab-cal-cell ab-cal-blank' });
    }
    (days || []).forEach((d) => {
        const status = STATUS[d.status] || STATUS['-'];
        const showOff = d.isWeeklyOff && d.status === '-';
        const classes = ['ab-cal-cell', 'ab-cal-day', status.cls];
        if (showOff) classes.push('ab-off');
        if (d.isFuture) classes.push('ab-future');
        if (d.day === selectedIso) classes.push('ab-selected');
        cells.push({
            key: d.day,
            day: d.day,
            dayNumber: d.dayNumber,
            mark: showOff ? 'Off' : status.short,
            title: `${shortDate(d.day)}: ${showOff ? 'Weekly off' : status.label}`,
            isFuture: d.isFuture,
            cls: classes.join(' ')
        });
    });
    while (cells.length % 7) {
        cells.push({ key: `end-${cells.length}`, isBlank: true, cls: 'ab-cal-cell ab-cal-blank' });
    }
    const weeks = [];
    for (let i = 0; i < cells.length; i += 7) {
        weeks.push({ key: `week-${i / 7}`, cells: cells.slice(i, i + 7) });
    }
    return weeks;
}

/** Counts for the day's summary line. */
export function dayCounts(rows) {
    const counts = { P: 0, H: 0, A: 0, L: 0, unmarked: 0 };
    (rows || []).forEach((r) => {
        if (r.status === '-' || !r.status) {
            if (!r.isWeeklyOff) counts.unmarked++;
        } else if (counts[r.status] !== undefined) {
            counts[r.status]++;
        }
    });
    return counts;
}

export const ENTRY_TYPES = {
    advance: { label: 'Advance', verb: 'Give advance', sign: -1 },
    payment: { label: 'Salary paid', verb: 'Pay salary', sign: -1 },
    bonus: { label: 'Bonus', verb: 'Add bonus', sign: 1 },
    deduction: { label: 'Deduction', verb: 'Add deduction', sign: -1 }
};
