import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStatus from '@salesforce/apex/ArchiveController.getStatus';
import saveRules from '@salesforce/apex/ArchiveController.saveRules';
import runNow from '@salesforce/apex/ArchiveController.runNow';
import { disablePullToRefresh } from 'c/disablePullToRefresh';

function errorText(error) {
    return (error && error.body && error.body.message) || (error && error.message) || 'Something went wrong. Try again.';
}

function monthName(key) {
    const [y, m] = String(key).split('-').map(Number);
    return new Date(y, m - 1, 1).toLocaleDateString('en-IN', { month: 'short', year: 'numeric' });
}

function plural(count, word) {
    const n = count || 0;
    return `${n} ${word}${n === 1 ? '' : 's'}`;
}

function dateText(iso) {
    if (!iso) return '';
    const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
    return new Date(y, m - 1, d).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

/**
 * The Archive screen (More > Settings > Archive): how full storage is, how old
 * data must be before it's archived (or, for estimates, deleted), what would
 * go now, and running it. The work is ArchiveJob's.
 */
export default class ArchiveSettings extends LightningElement {
    status;
    form;
    isLoading = true;
    isSaving = false;
    confirmingRun = false;
    runStarted = false;

    connectedCallback() {
        disablePullToRefresh(this);
        this.load();
    }

    load() {
        this.isLoading = true;
        return getStatus()
            .then((s) => {
                this.status = s;
                this.form = { ...s.rules };
            })
            .catch((error) => this.toast('Error', errorText(error), 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ---- storage --------------------------------------------------------

    bar(used, max, alertAt) {
        const pct = max ? Math.min(100, Math.round((Number(used) / Number(max)) * 100)) : 0;
        const over = pct >= alertAt;
        // Salesforce reports whole MB: under 1 MB comes back as 0.
        return {
            text: Number(used) === 0 ? `Under 1 MB of ${max} MB used` : `${used} MB of ${max} MB used (${pct}%)`,
            style: `width: ${Math.max(pct, 2)}%`,
            cls: over ? 'as-bar-fill as-bar-fill_over' : 'as-bar-fill',
            over
        };
    }

    get dataBar() {
        const s = this.status;
        return this.bar(s.dataUsedMb || 0, s.dataLimitMb || 0, s.rules.storageAlertPercent);
    }

    get fileBar() {
        const s = this.status;
        return this.bar(s.fileUsedMb || 0, s.fileLimitMb || 0, 80);
    }

    get archiveText() {
        const s = this.status;
        if (!s.archiveFiles) {
            return 'Nothing archived yet.';
        }
        const parts = [plural(s.archivedBills, 'bill')];
        if (s.archivedCustomers) {
            parts.push(plural(s.archivedCustomers, 'customer'));
        }
        if (s.archivedCars) {
            parts.push(plural(s.archivedCars, 'Walk-in car'));
        }
        if (s.archivedJobs) {
            parts.push(plural(s.archivedJobs, 'job'));
        }
        if (s.archivedSlips) {
            parts.push(plural(s.archivedSlips, 'job slip'));
        }
        if (s.archivedMonths) {
            parts.push(plural(s.archivedMonths, 'attendance month'));
        }
        return `${parts.join(', ')} archived in ${plural(s.archiveFiles, 'file')} (${s.archiveKb} KB).`;
    }

    get hasStatus() {
        return !!this.status;
    }

    // ---- rules ----------------------------------------------------------

    handleField(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail && event.detail.checked !== undefined && field === 'isOn'
            ? event.detail.checked
            : (event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value);
        this.form = { ...this.form, [field]: field === 'isOn' ? value : (value === '' ? null : Number(value)) };
    }

    get saveLabel() {
        return this.isSaving ? 'Saving…' : 'Save';
    }

    handleSave() {
        this.isSaving = true;
        saveRules({ rules: this.form })
            .then((s) => {
                this.status = s;
                this.form = { ...s.rules };
                this.toast('Saved', s.rules.isOn ? 'Archiving runs every night.' : 'Nightly archiving is off.', 'success');
            })
            .catch((error) => this.toast('Not saved', errorText(error), 'error'))
            .finally(() => {
                this.isSaving = false;
            });
    }

    // ---- what would happen ---------------------------------------------

    get billsReadyText() {
        const s = this.status;
        if (!s.billsReady) {
            return `No bills are ready. Bills dated before ${dateText(s.billsBefore)} are archived once their month's GST is marked filed.`;
        }
        const months = s.billMonthsReady.map(monthName);
        const shown = months.length > 6 ? `${months.slice(0, 6).join(', ')} and ${months.length - 6} more` : months.join(', ');
        return `${s.billsReady} bill${s.billsReady === 1 ? '' : 's'} ready to archive: ${shown}.`;
    }

    get estimatesText() {
        const s = this.status;
        if (!s.estimatesToDelete) {
            return `No estimates to delete (those last dated before ${dateText(s.estimatesBefore)} are deleted).`;
        }
        return `${s.estimatesToDelete} old estimate${s.estimatesToDelete === 1 ? '' : 's'} (last dated before ${dateText(s.estimatesBefore)}) will be deleted.`;
    }

    get customersText() {
        const s = this.status;
        const before = dateText(s.customersBefore);
        if (!s.customersReady && !s.carsReady) {
            return `No customers are ready. Customers and Walk-in cars not seen since ${before} are archived.`;
        }
        const what = [s.customersReady ? plural(s.customersReady, 'customer') : '', s.carsReady ? plural(s.carsReady, 'Walk-in car') : '']
            .filter((p) => p)
            .join(' and ');
        const when = s.customersDue ? '' : ' Customers were archived in the last 28 days, so the nightly run leaves these for now; Run now archives them.';
        return `${what} not seen since ${before} ready to archive.${when}`;
    }

    get workText() {
        const s = this.status;
        if (!s.jobsReady && !s.slipsReady) {
            return `No jobs or job slips are ready. Jobs not moved since ${dateText(s.jobsBefore)} and job slips dated before ${dateText(s.slipsBefore)} are archived.`;
        }
        const what = [s.jobsReady ? plural(s.jobsReady, 'job') : '', s.slipsReady ? plural(s.slipsReady, 'job slip') : '']
            .filter((p) => p)
            .join(' and ');
        const when = s.workDue ? '' : ' Jobs and slips were archived in the last 28 days, so the nightly run leaves these for now; Run now archives them.';
        return `${what} ready to archive.${when}`;
    }

    get attendanceText() {
        const s = this.status;
        if (!s.monthsReady) {
            return `No attendance is ready. Months before ${monthName(String(s.monthsBefore || '').slice(0, 7))} are archived.`;
        }
        return `${plural(s.monthsReady, 'attendance month')} (before ${monthName(String(s.monthsBefore).slice(0, 7))}) ready to archive.`;
    }

    get nothingToDo() {
        const s = this.status;
        return !s.billsReady && !s.estimatesToDelete && !s.customersReady && !s.carsReady && !s.jobsReady && !s.slipsReady && !s.monthsReady;
    }

    get lastRunText() {
        const r = this.status.rules;
        if (!r.lastRun) {
            return 'Never run yet.';
        }
        const when = new Date(r.lastRun).toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
        return `${when}: ${r.lastResult || ''}`;
    }

    get hasDownload() {
        return !!(this.status && this.status.downloadUrl);
    }

    handleAskRun() {
        this.confirmingRun = true;
    }

    handleCancelRun() {
        this.confirmingRun = false;
    }

    handleRun() {
        this.confirmingRun = false;
        runNow()
            .then(() => {
                this.runStarted = true;
                this.toast('Archiving started', 'It runs in the background. Tap Refresh in a minute.', 'success');
            })
            .catch((error) => this.toast('Not started', errorText(error), 'error'));
    }

    handleRefresh() {
        this.runStarted = false;
        this.load();
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
