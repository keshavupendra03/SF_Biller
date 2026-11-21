import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getReturn from '@salesforce/apex/GstReturnController.getReturn';
import downloadReturn from '@salesforce/apex/GstReturnController.downloadReturn';
import setGstFiledUpTo from '@salesforce/apex/WorkshopProfileController.setGstFiledUpTo';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import { gstPeriods, monthLabel, gstDueDates } from 'c/gst';

function formatAmount(value) {
    return (Number(value) || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatDate(iso) {
    if (!iso) {
        return '';
    }
    const [year, month, day] = iso.split('-');
    return `${day}-${month}-${year}`;
}

function sum(rows, field) {
    return (rows || []).reduce((total, row) => total + (Number(row[field]) || 0), 0);
}

function taxOf(row) {
    return (Number(row.igst) || 0) + (Number(row.cgst) || 0) + (Number(row.sgst) || 0);
}

/**
 * GST Returns (architecture.md §D.1, stage G3): one company's GSTR-1 and the
 * sales side of GSTR-3B for a month or quarter, with the GST checkup first,
 * so what needs putting right is seen before the figures. "Download for CA"
 * gives the offline tool's CSV files in one zip; "Mark as filed" locks the
 * period (GstFilingLock), once the checkup has no errors.
 */
export default class GstReturns extends NavigationMixin(LightningElement) {
    companyId;
    profile;
    periodValue;
    ret;
    isLoading = false;
    isDownloading = false;
    isSavingFiled = false;
    confirmFiled = false;

    _seq = 0;

    connectedCallback() {
        disablePullToRefresh(this);
    }

    // ---- due dates (G5) ------------------------------------------------------

    // Returns still to file for this company, from its "filed up to" month.
    get dueDates() {
        return gstDueDates(this.profile).map((d) => ({
            ...d,
            badgeClass: d.isLate ? 'slds-badge slds-theme_error' : d.isSoon ? 'slds-badge slds-theme_warning' : 'slds-badge',
            badgeLabel: d.isLate ? 'Late' : d.isSoon ? 'Due soon' : 'Due'
        }));
    }

    get hasDueDates() {
        return this.dueDates.length > 0;
    }

    get showDueCard() {
        const type = this.profile && this.profile.gstRegistrationType;
        return !!this.profile && type !== 'Unregistered';
    }

    get nothingDueText() {
        const filed = this.profile && this.profile.gstFiledUpTo;
        return filed ? `Nothing due: returns are marked filed up to ${monthLabel(filed)}.` : 'Nothing due yet.';
    }

    get dueNote() {
        return 'Usual due dates. The government sometimes extends one: check the GST portal if a date looks off.';
    }

    // ---- choosing ----------------------------------------------------------

    handleCompanyChange(event) {
        this.companyId = event.detail.id;
        this.profile = event.detail.profile;
        // The latest period that's over: the one usually being filed.
        const periods = this.periods;
        const latestOver = periods.find((p) => p.isOver) || periods[0];
        this.periodValue = latestOver ? latestOver.value : undefined;
        this.loadReturn();
    }

    get periods() {
        return gstPeriods(this.profile ? this.profile.gstFilingFrequency : 'Monthly');
    }

    get periodOptions() {
        return this.periods.map(({ label, value }) => ({ label, value }));
    }

    get period() {
        return this.periods.find((p) => p.value === this.periodValue);
    }

    handlePeriodChange(event) {
        this.periodValue = event.detail.value;
        this.confirmFiled = false;
        this.loadReturn();
    }

    loadReturn() {
        const period = this.period;
        if (!this.companyId || !period) {
            this.ret = undefined;
            return Promise.resolve();
        }
        const seq = ++this._seq;
        this.isLoading = true;
        return getReturn({ companyId: this.companyId, startDate: period.start, endDate: period.end })
            .then((ret) => {
                if (seq === this._seq) {
                    this.ret = ret;
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                if (seq === this._seq) {
                    this.isLoading = false;
                }
            });
    }

    // ---- what the return says ------------------------------------------------

    get hasReturn() {
        return !!this.ret;
    }

    get isRegular() {
        return this.hasReturn && this.ret.registrationType === 'Regular';
    }

    get isComposition() {
        return this.hasReturn && this.ret.registrationType === 'Composition';
    }

    get isUnregistered() {
        return this.hasReturn && this.ret.registrationType === 'Unregistered';
    }

    get periodText() {
        return this.hasReturn ? `${formatDate(this.ret.startDate)} to ${formatDate(this.ret.endDate)}` : '';
    }

    get statusText() {
        if (this.ret.isFiled) {
            return `Filed (GST returns filed up to ${monthLabel(this.ret.filedUpTo)}): its bills are locked.`;
        }
        return 'Not filed yet.';
    }

    get statusClass() {
        return this.ret.isFiled ? 'slds-badge slds-theme_success' : 'slds-badge';
    }

    get statusLabel() {
        return this.ret.isFiled ? 'Filed' : 'Not filed';
    }

    get summaryText() {
        return `${this.ret.billCount} bill(s), Rs. ${formatAmount(this.ret.invoiceValue)}`;
    }

    get compositionTurnover() {
        return formatAmount(this.ret.compositionTurnover);
    }

    // The checkup: errors stop "Mark as filed", warnings are to know.
    get issues() {
        return (this.ret.issues || []).map((issue, index) => ({
            ...issue,
            key: `issue-${index}`,
            isError: issue.severity === 'error',
            icon: issue.severity === 'error' ? 'utility:error' : 'utility:warning',
            iconVariant: issue.severity === 'error' ? 'error' : 'warning',
            rowClass: issue.severity === 'error' ? 'gr-issue gr-issue_error' : 'gr-issue gr-issue_warning'
        }));
    }

    get hasIssues() {
        return this.issues.length > 0;
    }

    get checkupTitle() {
        if (!this.hasIssues) {
            return 'Ready to file: no problems found.';
        }
        const parts = [];
        if (this.ret.errorCount) {
            parts.push(`${this.ret.errorCount} to put right before filing`);
        }
        if (this.ret.warningCount) {
            parts.push(`${this.ret.warningCount} to check`);
        }
        return parts.join(', ');
    }

    get checkupClass() {
        if (!this.hasIssues) {
            return 'gr-checkup-title gr-checkup-title_ok';
        }
        return this.ret.errorCount ? 'gr-checkup-title gr-checkup-title_error' : 'gr-checkup-title gr-checkup-title_warning';
    }

    // One tile per GSTR-1 table: how many, taxable value, tax.
    get tiles() {
        const r = this.ret;
        const invoices = (rows) => new Set(rows.map((row) => row.invoiceNumber)).size;
        return [
            { key: 'b2b', label: 'B2B (Table 4)', count: `${invoices(r.b2b)} invoice(s)`, taxable: sum(r.b2b, 'taxableValue'), tax: r.b2b.reduce((t, row) => t + taxOf(row), 0) },
            { key: 'b2cl', label: 'B2C Large (Table 5)', count: `${invoices(r.b2cl)} invoice(s)`, taxable: sum(r.b2cl, 'taxableValue'), tax: r.b2cl.reduce((t, row) => t + taxOf(row), 0) },
            { key: 'b2cs', label: 'B2C Small (Table 7)', count: `${r.b2cs.length} row(s)`, taxable: sum(r.b2cs, 'taxableValue'), tax: r.b2cs.reduce((t, row) => t + taxOf(row), 0) },
            { key: 'nil', label: 'Nil rated (Table 8)', count: '', taxable: sum(r.nil, 'nilRated'), tax: 0 },
            { key: 'hsn', label: 'HSN summary (Table 12)', count: `${r.hsnB2b.length + r.hsnB2c.length} row(s)`, taxable: sum(r.hsnB2b, 'taxableValue') + sum(r.hsnB2c, 'taxableValue'), tax: null },
            { key: 'docs', label: 'Documents issued (Table 13)', count: `${sum(r.documents, 'netIssued')} issued, ${sum(r.documents, 'cancelled')} cancelled`, taxable: null, tax: null }
        ].map((tile) => ({
            ...tile,
            taxableText: tile.taxable === null ? '' : `Taxable Rs. ${formatAmount(tile.taxable)}`,
            taxText: tile.tax === null || tile.tax === 0 ? '' : `Tax Rs. ${formatAmount(tile.tax)}`
        }));
    }

    get b2bRows() {
        return this.invoiceRows(this.ret.b2b);
    }

    get b2clRows() {
        return this.invoiceRows(this.ret.b2cl);
    }

    invoiceRows(rows) {
        return rows.map((row) => ({
            ...row,
            key: `${row.invoiceNumber}-${row.rate}`,
            date: formatDate(row.invoiceDate),
            value: formatAmount(row.invoiceValue),
            taxable: formatAmount(row.taxableValue),
            tax: formatAmount(taxOf(row))
        }));
    }

    get b2csRows() {
        return this.ret.b2cs.map((row) => ({
            ...row,
            key: `${row.placeOfSupply}-${row.rate}`,
            taxable: formatAmount(row.taxableValue),
            tax: formatAmount(taxOf(row))
        }));
    }

    get nilRows() {
        return this.ret.nil.map((row) => ({ ...row, key: row.description, value: formatAmount(row.nilRated) }));
    }

    get hsnRows() {
        const decorate = (kind) => (row) => ({
            ...row,
            key: `${kind}-${row.hsn}-${row.uqc}-${row.rate}`,
            kind,
            hsnText: row.hsn || '(none)',
            taxable: formatAmount(row.taxableValue),
            tax: formatAmount(taxOf(row)),
            total: formatAmount(row.totalValue)
        });
        return [...this.ret.hsnB2b.map(decorate('B2B')), ...this.ret.hsnB2c.map(decorate('B2C'))];
    }

    get documentRows() {
        return this.ret.documents.map((row) => ({ ...row, key: `${row.fromNumber}-${row.toNumber}` }));
    }

    get gstr3bRows() {
        const g = this.ret.gstr3b;
        const rows = [
            { key: '3.1a', label: '3.1(a) Taxable supplies', taxable: g.taxableValue, igst: g.igst, cgst: g.cgst, sgst: g.sgst },
            { key: '3.1c', label: '3.1(c) Nil rated', taxable: g.nilRated, igst: 0, cgst: 0, sgst: 0 },
            ...g.unregisteredInterState.map((row) => ({
                key: `3.2-${row.placeOfSupply}`, label: `3.2 Unregistered, ${row.placeOfSupply}`, taxable: row.taxableValue, igst: row.igst, cgst: 0, sgst: 0
            }))
        ];
        return rows.map((row) => ({
            ...row,
            taxable: formatAmount(row.taxable),
            igst: formatAmount(row.igst),
            cgst: formatAmount(row.cgst),
            sgst: formatAmount(row.sgst)
        }));
    }

    // ---- actions -------------------------------------------------------------

    handleOpenBill(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: event.currentTarget.dataset.billId }
        });
    }

    get downloadLabel() {
        return this.isDownloading ? 'Preparing…' : 'Download for CA (zip)';
    }

    handleDownload() {
        const period = this.period;
        this.isDownloading = true;
        downloadReturn({ companyId: this.companyId, startDate: period.start, endDate: period.end })
            .then((download) => {
                const bytes = atob(download.base64Data);
                const buffer = new Uint8Array(bytes.length);
                for (let i = 0; i < bytes.length; i++) {
                    buffer[i] = bytes.charCodeAt(i);
                }
                const url = URL.createObjectURL(new Blob([buffer], { type: 'application/zip' }));
                const anchor = this.refs.downloadLink;
                anchor.href = url;
                anchor.download = download.fileName;
                anchor.click();
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => URL.revokeObjectURL(url), 10000);
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isDownloading = false;
            });
    }

    // Only a period that's over, not filed, and with nothing left to put right.
    get canMarkFiled() {
        return this.hasReturn && !this.ret.isFiled && this.period && this.period.isOver && !this.ret.errorCount;
    }

    get showMarkFiled() {
        return this.hasReturn && !this.ret.isFiled && this.period && this.period.isOver && !this.isUnregistered;
    }

    get markFiledHint() {
        return this.ret.errorCount ? 'Put right the errors in the checkup first.' : '';
    }

    get markFiledDisabled() {
        return !this.canMarkFiled || this.isSavingFiled;
    }

    get confirmFiledText() {
        return `Mark ${this.period.label} as filed? Bills dated up to ${formatDate(this.period.end)} will be locked: they can't be added, changed or deleted.`;
    }

    handleAskFiled() {
        this.confirmFiled = true;
    }

    handleCancelFiled() {
        this.confirmFiled = false;
    }

    handleConfirmFiled() {
        this.saveFiledUpTo(this.period.end, `${this.period.label} marked as filed`);
    }

    // Undo: filed only up to the month before this period.
    handleUnmarkFiled() {
        const start = new Date(`${this.period.start}T00:00:00`);
        const before = new Date(start.getFullYear(), start.getMonth(), 0);
        const pad = (n) => String(n).padStart(2, '0');
        this.saveFiledUpTo(`${before.getFullYear()}-${pad(before.getMonth() + 1)}-${pad(before.getDate())}`, `${this.period.label} unlocked`);
    }

    saveFiledUpTo(filedUpTo, message) {
        this.isSavingFiled = true;
        setGstFiledUpTo({ companyId: this.companyId, filedUpTo })
            .then((saved) => {
                this.profile = { ...this.profile, gstFiledUpTo: saved.gstFiledUpTo };
                this.confirmFiled = false;
                this.showToast(message, '', 'success');
                return this.loadReturn();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSavingFiled = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
