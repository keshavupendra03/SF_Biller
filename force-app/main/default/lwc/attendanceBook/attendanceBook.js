import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDay from '@salesforce/apex/AttendanceController.getDay';
import markDay from '@salesforce/apex/AttendanceController.markDay';
import markAllPresent from '@salesforce/apex/AttendanceController.markAllPresent';
import getMonth from '@salesforce/apex/AttendanceController.getMonth';
import getPayMonth from '@salesforce/apex/AttendanceController.getPayMonth';
import addEntry from '@salesforce/apex/AttendanceController.addEntry';
import removeEntry from '@salesforce/apex/AttendanceController.removeEntry';
import savePay from '@salesforce/apex/AttendanceController.savePay';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import {
    STATUS, WEEKDAYS, ENTRY_TYPES, toIso, monthStart, shiftMonth, shiftDay, monthLabel, dayLabel, shortDate,
    rupees, balanceText, earnedDetail, payText, calendarWeeks, dayCounts
} from 'c/attendanceUtils';

const VIEWS = [
    { value: 'today', label: 'Today', icon: 'utility:check' },
    { value: 'month', label: 'Month', icon: 'utility:event' },
    { value: 'pay', label: 'Pay', icon: 'utility:moneybag' }
];
const DAY_BUTTONS = ['P', 'H', 'A'];
const CALENDAR_BUTTONS = ['P', 'H', 'A', 'L', '-'];
const METHODS = ['Cash', 'UPI', 'Bank Transfer'];

// This month's monthly salary assumes the days still to come are worked.
function earnedLabel(month, isCurrent) {
    if (!isCurrent) {
        return 'Pay for the month';
    }
    return month.monthPayType === 'Daily' ? 'Earned so far' : 'Pay this month (if no more absences)';
}

function errorText(error) {
    return (error && error.body && error.body.message) || (error && error.message) || 'Something went wrong. Try again.';
}

/**
 * Mechanic attendance and pay, built for people who don't live in software:
 * three big tabs (Today, Month, Pay), one tap to mark a mechanic, and one line
 * that says what is owed. The rules are in MechanicPay (Apex).
 */
export default class AttendanceBook extends NavigationMixin(LightningElement) {
    view = 'today';

    // Today
    day = toIso(new Date());
    dayRows = [];
    dayLoading = true;
    savingIds = [];
    markingAll = false;

    // Month
    month = monthStart(toIso(new Date()));
    monthMechanicId;
    monthData;
    monthLoading = false;
    selectedCalDay;

    // Pay
    payMonth = monthStart(toIso(new Date()));
    payList = [];
    payLoading = false;
    entryForm; // { mechanicId, type, amount, entryDate, method, note, saving }
    payForm; // { mechanicId, payType, payAmount, weeklyOff, saving }
    confirmRemove; // { mechanicId, entryId }

    _daySeq = 0;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadDay();
    }

    // ---- tabs -----------------------------------------------------------

    get views() {
        return VIEWS.map((v) => ({
            ...v,
            cls: v.value === this.view ? 'ab-tab ab-tab_active' : 'ab-tab',
            pressed: String(v.value === this.view)
        }));
    }

    get isToday() {
        return this.view === 'today';
    }

    get isMonth() {
        return this.view === 'month';
    }

    get isPay() {
        return this.view === 'pay';
    }

    handleView(event) {
        this.view = event.currentTarget.dataset.view;
        if (this.isMonth) {
            if (!this.monthMechanicId && this.dayRows.length) {
                this.monthMechanicId = this.dayRows[0].mechanicId;
            }
            this.loadMonth();
        } else if (this.isPay) {
            this.loadPay();
        } else {
            this.loadDay();
        }
    }

    get hasMechanics() {
        return this.dayRows.length > 0;
    }

    get noMechanics() {
        return !this.dayLoading && this.dayRows.length === 0;
    }

    handleAddMechanics() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'Mechanic_List' } });
    }

    // ---- Today ----------------------------------------------------------

    get todayIso() {
        return toIso(new Date());
    }

    get dayHeading() {
        return dayLabel(this.day);
    }

    get dayIsToday() {
        return this.day === this.todayIso;
    }

    get dayNotToday() {
        return !this.dayIsToday;
    }

    get dayCountsText() {
        const c = dayCounts(this.dayRows);
        const parts = [`${c.P} present`];
        if (c.H) parts.push(`${c.H} half day`);
        parts.push(`${c.A} absent`);
        if (c.L) parts.push(`${c.L} on leave`);
        if (c.unmarked) parts.push(`${c.unmarked} not marked`);
        return parts.join(' · ');
    }

    get allMarked() {
        return dayCounts(this.dayRows).unmarked === 0;
    }

    get markAllLabel() {
        return this.markingAll ? 'Marking…' : 'Mark everyone else present';
    }

    get markAllDisabled() {
        return this.markingAll || this.allMarked;
    }

    get decoratedDayRows() {
        return this.dayRows.map((row) => {
            const saving = this.savingIds.includes(row.mechanicId);
            return {
                ...row,
                saving,
                statusText: row.status === '-' ? (row.isWeeklyOff ? 'Weekly off' : 'Not marked yet') : STATUS[row.status].label,
                rowCls: `ab-row ${STATUS[row.status] ? STATUS[row.status].cls : ''}`,
                buttons: DAY_BUTTONS.map((s) => ({
                    status: s,
                    label: STATUS[s].label,
                    pressed: String(row.status === s),
                    cls: `ab-mark ab-mark_${s}${row.status === s ? ' ab-mark_on' : ''}`,
                    disabled: saving
                }))
            };
        });
    }

    loadDay() {
        const seq = ++this._daySeq;
        this.dayLoading = true;
        return getDay({ day: this.day })
            .then((view) => {
                if (seq === this._daySeq) {
                    this.dayRows = view.rows || [];
                }
            })
            .catch((error) => this.toast('Error', errorText(error), 'error'))
            .finally(() => {
                if (seq === this._daySeq) {
                    this.dayLoading = false;
                }
            });
    }

    handlePrevDay() {
        this.day = shiftDay(this.day, -1);
        this.loadDay();
    }

    handleNextDay() {
        if (!this.dayIsToday) {
            this.day = shiftDay(this.day, 1);
            this.loadDay();
        }
    }

    handleDayPicked(event) {
        const value = event.detail.value || event.target.value;
        if (value && value <= this.todayIso) {
            this.day = value;
            this.loadDay();
        }
    }

    handleGoToday() {
        this.day = this.todayIso;
        this.loadDay();
    }

    // Tapping the mark a mechanic already has takes it off again.
    handleMark(event) {
        const { mechanicId, status } = event.currentTarget.dataset;
        const row = this.dayRows.find((r) => r.mechanicId === mechanicId);
        if (!row || this.savingIds.includes(mechanicId)) {
            return;
        }
        const next = row.status === status ? '-' : status;
        const previous = row.status;
        this.setRowStatus(mechanicId, next);
        this.savingIds = [...this.savingIds, mechanicId];
        markDay({ mechanicId, day: this.day, status: next })
            .then((saved) => this.setRowStatus(mechanicId, saved.status))
            .catch((error) => {
                this.setRowStatus(mechanicId, previous);
                this.toast('Not saved', errorText(error), 'error');
            })
            .finally(() => {
                this.savingIds = this.savingIds.filter((id) => id !== mechanicId);
            });
    }

    setRowStatus(mechanicId, status) {
        this.dayRows = this.dayRows.map((r) => (r.mechanicId === mechanicId ? { ...r, status } : r));
    }

    handleMarkAll() {
        this.markingAll = true;
        markAllPresent({ day: this.day })
            .then((view) => {
                this.dayRows = view.rows || [];
                this.toast('Marked present', '', 'success');
            })
            .catch((error) => this.toast('Not saved', errorText(error), 'error'))
            .finally(() => {
                this.markingAll = false;
            });
    }

    // ---- Month ----------------------------------------------------------

    get monthHeading() {
        return monthLabel(this.month);
    }

    get monthIsCurrent() {
        return this.month === monthStart(this.todayIso);
    }

    get mechanicChips() {
        return this.dayRows.map((r) => ({
            id: r.mechanicId,
            name: r.name,
            cls: r.mechanicId === this.monthMechanicId ? 'ab-chip ab-chip_on' : 'ab-chip',
            pressed: String(r.mechanicId === this.monthMechanicId)
        }));
    }

    get weekdayHeads() {
        return WEEKDAYS.map((d) => ({ key: d, label: d.slice(0, 3) }));
    }

    get weeks() {
        return this.monthData ? calendarWeeks(this.monthData.firstWeekday, this.monthData.days, this.selectedCalDay) : [];
    }

    get selectedDayLabel() {
        return this.selectedCalDay ? dayLabel(this.selectedCalDay) : '';
    }

    get calendarButtons() {
        const cell = this.monthData && this.monthData.days.find((d) => d.day === this.selectedCalDay);
        return CALENDAR_BUTTONS.map((s) => ({
            status: s,
            label: s === '-' ? 'Clear' : STATUS[s].label,
            cls: `ab-mark ab-mark_${s === '-' ? 'clear' : s}${cell && cell.status === s && s !== '-' ? ' ab-mark_on' : ''}`
        }));
    }

    get monthSummary() {
        const m = this.monthData;
        if (!m) return [];
        const items = [
            { key: 'p', label: 'Present', value: m.daysPresent, cls: 'ab-stat ab-present' },
            { key: 'a', label: 'Absent', value: m.daysAbsent, cls: 'ab-stat ab-absent' }
        ];
        if (m.halfDays) items.push({ key: 'h', label: 'Half days', value: m.halfDays, cls: 'ab-stat ab-half' });
        if (m.leaveDays) items.push({ key: 'l', label: 'Paid leave', value: m.leaveDays, cls: 'ab-stat ab-leave' });
        if (m.offDaysWorked) items.push({ key: 'o', label: 'Off days worked', value: m.offDaysWorked, cls: 'ab-stat ab-present' });
        return items;
    }

    get monthEarnedText() {
        return this.monthData ? `${rupees(this.monthData.earned)} — ${earnedDetail(this.monthData)}` : '';
    }

    get monthEarnedLabel() {
        return this.monthData ? earnedLabel(this.monthData, this.monthIsCurrent) : '';
    }

    loadMonth() {
        if (!this.monthMechanicId) {
            return Promise.resolve();
        }
        this.monthLoading = true;
        return getMonth({ mechanicId: this.monthMechanicId, month: this.month })
            .then((data) => {
                this.monthData = data;
            })
            .catch((error) => this.toast('Error', errorText(error), 'error'))
            .finally(() => {
                this.monthLoading = false;
            });
    }

    handlePickMechanic(event) {
        this.monthMechanicId = event.currentTarget.dataset.mechanic;
        this.selectedCalDay = undefined;
        this.loadMonth();
    }

    handlePrevMonth() {
        this.month = shiftMonth(this.month, -1);
        this.selectedCalDay = undefined;
        this.loadMonth();
    }

    handleNextMonth() {
        if (!this.monthIsCurrent) {
            this.month = shiftMonth(this.month, 1);
            this.selectedCalDay = undefined;
            this.loadMonth();
        }
    }

    // Archived into Files (AttendanceArchive): shown, not changed.
    get monthIsArchived() {
        return !!(this.monthData && this.monthData.isArchived);
    }

    handlePickDay(event) {
        const { day, future } = event.currentTarget.dataset;
        if (this.monthIsArchived) {
            return;
        }
        if (day && future !== 'true') {
            this.selectedCalDay = this.selectedCalDay === day ? undefined : day;
        }
    }

    handleCalendarMark(event) {
        const status = event.currentTarget.dataset.status;
        const day = this.selectedCalDay;
        markDay({ mechanicId: this.monthMechanicId, day, status })
            .then(() => this.loadMonth())
            .then(() => {
                if (day === this.day) {
                    this.setRowStatus(this.monthMechanicId, status);
                }
            })
            .catch((error) => this.toast('Not saved', errorText(error), 'error'));
    }

    // ---- Pay ------------------------------------------------------------

    get payHeading() {
        return monthLabel(this.payMonth);
    }

    get payIsCurrent() {
        return this.payMonth === monthStart(this.todayIso);
    }

    get noPayList() {
        return !this.payLoading && this.payList.length === 0;
    }

    get methodOptions() {
        return METHODS.map((m) => ({ label: m, value: m }));
    }

    get payTypeOptions() {
        return [
            { label: 'Monthly salary', value: 'Monthly' },
            { label: 'Daily wage', value: 'Daily' }
        ];
    }

    get weeklyOffOptions() {
        return [...['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'].map((d) => ({ label: d, value: d })), { label: 'No weekly off', value: 'None' }];
    }

    get payCards() {
        return this.payList.map((m) => {
            const balance = balanceText(m.name, m.balance, this.payIsCurrent);
            const form = this.entryForm && this.entryForm.mechanicId === m.mechanicId ? this.entryForm : null;
            const editingPay = this.payForm && this.payForm.mechanicId === m.mechanicId ? this.payForm : null;
            return {
                ...m,
                payText: payText(m),
                payLinkLabel: m.hasPay ? 'Change pay' : 'Set salary',
                noPay: !m.hasPay,
                balanceText: balance.text,
                balanceCls: balance.cls,
                earnedLabel: earnedLabel(m, this.payIsCurrent),
                earnedText: rupees(m.earned),
                earnedDetail: earnedDetail(m),
                hasBrought: Number(m.broughtForward) !== 0,
                broughtText: (Number(m.broughtForward) < 0 ? '− ' : '') + rupees(m.broughtForward),
                broughtHint: Number(m.broughtForward) < 0 ? 'owed from last month' : 'still due from last month',
                hasExtra: Number(m.extra) !== 0,
                extraText: (Number(m.extra) < 0 ? '− ' : '+ ') + rupees(m.extra),
                advancesText: '− ' + rupees(m.advances),
                paidText: '− ' + rupees(m.paid),
                cardCls: m.isActive ? 'ab-card' : 'ab-card ab-card_inactive',
                canChange: !m.isArchived,
                entryForm: form,
                entryTitle: form ? ENTRY_TYPES[form.type].verb : '',
                entryNeedsMethod: form && (form.type === 'advance' || form.type === 'payment'),
                entrySaveLabel: form && form.saving ? 'Saving…' : 'Save',
                editingPay,
                paySaveLabel: editingPay && editingPay.saving ? 'Saving…' : 'Save pay',
                payAmountLabel: editingPay && editingPay.payType === 'Daily' ? 'Daily wage (₹)' : 'Monthly salary (₹)',
                hasEntries: m.entries && m.entries.length > 0,
                entryRows: (m.entries || []).map((e) => ({
                    ...e,
                    typeLabel: ENTRY_TYPES[e.type] ? ENTRY_TYPES[e.type].label : e.type,
                    dateText: shortDate(e.entryDate),
                    amountText: (e.type === 'bonus' ? '+ ' : '− ') + rupees(e.amount),
                    detail: [e.method, e.note].filter(Boolean).join(' · '),
                    confirming: this.confirmRemove && this.confirmRemove.entryId === e.id,
                    amountCls: e.type === 'bonus' ? 'ab-entry-amount ab-plus' : 'ab-entry-amount'
                }))
            };
        });
    }

    loadPay() {
        this.payLoading = true;
        return getPayMonth({ month: this.payMonth })
            .then((list) => {
                this.payList = list || [];
            })
            .catch((error) => this.toast('Error', errorText(error), 'error'))
            .finally(() => {
                this.payLoading = false;
            });
    }

    handlePrevPayMonth() {
        this.payMonth = shiftMonth(this.payMonth, -1);
        this.entryForm = undefined;
        this.loadPay();
    }

    handleNextPayMonth() {
        if (!this.payIsCurrent) {
            this.payMonth = shiftMonth(this.payMonth, 1);
            this.entryForm = undefined;
            this.loadPay();
        }
    }

    // A salary payment starts at what is left to pay.
    handleOpenEntry(event) {
        const { mechanicId, type } = event.currentTarget.dataset;
        const m = this.payList.find((x) => x.mechanicId === mechanicId);
        const due = m && Number(m.balance) > 0 ? Number(m.balance) : null;
        this.payForm = undefined;
        this.entryForm = {
            mechanicId,
            type,
            amount: type === 'payment' ? due : null,
            entryDate: this.payIsCurrent ? this.todayIso : this.lastDayOfPayMonth,
            method: 'Cash',
            note: '',
            saving: false
        };
    }

    get lastDayOfPayMonth() {
        return shiftDay(shiftMonth(this.payMonth, 1), -1);
    }

    handleEntryField(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.entryForm = { ...this.entryForm, [field]: value };
    }

    handleCancelEntry() {
        this.entryForm = undefined;
    }

    handleSaveEntry() {
        const f = this.entryForm;
        if (!f || !(Number(f.amount) > 0)) {
            this.toast('Type the amount', 'Enter how much, in rupees.', 'warning');
            return;
        }
        this.entryForm = { ...f, saving: true };
        addEntry({
            input: {
                mechanicId: f.mechanicId,
                type: f.type,
                amount: Number(f.amount),
                entryDate: f.entryDate,
                method: f.type === 'advance' || f.type === 'payment' ? f.method : null,
                note: f.note
            }
        })
            .then((month) => {
                this.entryForm = undefined;
                this.replaceMonth(month);
                this.toast(`${ENTRY_TYPES[f.type].label} saved`, `${rupees(f.amount)} for ${month.name}`, 'success');
            })
            .catch((error) => {
                this.entryForm = { ...f, saving: false };
                this.toast('Not saved', errorText(error), 'error');
            });
    }

    // The entry's month may be another month than the one shown: reload then.
    replaceMonth(month) {
        if (monthStart(month.month) === this.payMonth) {
            this.payList = this.payList.map((m) => (m.mechanicId === month.mechanicId ? month : m));
        } else {
            this.loadPay();
        }
    }

    handleAskRemove(event) {
        const { mechanicId, entryId } = event.currentTarget.dataset;
        this.confirmRemove = { mechanicId, entryId };
    }

    handleKeepEntry() {
        this.confirmRemove = undefined;
    }

    handleRemoveEntry() {
        const { mechanicId, entryId } = this.confirmRemove;
        this.confirmRemove = undefined;
        removeEntry({ mechanicId, month: this.payMonth, entryId })
            .then((month) => {
                this.replaceMonth(month);
                this.toast('Removed', '', 'success');
            })
            .catch((error) => this.toast('Not removed', errorText(error), 'error'));
    }

    handleEditPay(event) {
        const mechanicId = event.currentTarget.dataset.mechanicId;
        const m = this.payList.find((x) => x.mechanicId === mechanicId);
        this.entryForm = undefined;
        this.payForm = {
            mechanicId,
            payType: m.payType || 'Monthly',
            payAmount: m.payAmount,
            weeklyOff: m.weeklyOff || 'Sunday',
            saving: false
        };
    }

    handlePayField(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.payForm = { ...this.payForm, [field]: value };
    }

    handleCancelPay() {
        this.payForm = undefined;
    }

    handleSavePay() {
        const f = this.payForm;
        if (!(Number(f.payAmount) > 0)) {
            this.toast('Type the amount', f.payType === 'Daily' ? 'Enter the daily wage.' : 'Enter the monthly salary.', 'warning');
            return;
        }
        this.payForm = { ...f, saving: true };
        savePay({ input: { mechanicId: f.mechanicId, payType: f.payType, payAmount: Number(f.payAmount), weeklyOff: f.weeklyOff } })
            .then(() => {
                this.payForm = undefined;
                this.toast('Pay saved', '', 'success');
                return Promise.all([this.loadPay(), this.loadDay()]);
            })
            .catch((error) => {
                this.payForm = { ...f, saving: false };
                this.toast('Not saved', errorText(error), 'error');
            });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
