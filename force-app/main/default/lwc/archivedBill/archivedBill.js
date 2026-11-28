import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getArchivedBill from '@salesforce/apex/ArchiveController.getArchivedBill';
import restoreBill from '@salesforce/apex/ArchiveController.restoreBill';

function rupees(value) {
    return '₹' + (Number(value) || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function errorText(error) {
    return (error && error.body && error.body.message) || (error && error.message) || 'Something went wrong. Try again.';
}

/**
 * One archived bill (BillArchive), read-only: what it billed, and Print, which
 * gives the same PDF as before it was archived. "Bring back" puts it (with its
 * versions and insurance pair) back into Salesforce under the same number.
 * Fires close, and restored with the bill's new Id.
 */
export default class ArchivedBill extends LightningElement {
    @api billId;
    @api documentId;

    bill;
    isLoading = true;
    showPreview = false;
    confirmingRestore = false;
    isRestoring = false;

    connectedCallback() {
        getArchivedBill({ documentId: this.documentId, billId: this.billId })
            .then((bill) => {
                this.bill = bill;
            })
            .catch((error) => this.toast('Error', errorText(error), 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    get heading() {
        return this.bill ? this.bill.invoiceNumber : 'Old bill';
    }

    get dateText() {
        return this.bill && this.bill.billDate
            ? new Date(this.bill.billDate).toLocaleDateString('en-IN', { day: 'numeric', month: 'long', year: 'numeric' })
            : '';
    }

    get versionText() {
        if (!this.bill || this.bill.versionNumber <= 1) {
            return '';
        }
        return this.bill.isLatestVersion ? `Version ${this.bill.versionNumber}` : `Version ${this.bill.versionNumber} (replaced by a later version)`;
    }

    get lines() {
        return (this.bill ? this.bill.lineItems : []).map((l, i) => ({
            key: `line-${i}`,
            description: l.description,
            detail: `${l.quantity} × ${rupees(l.unitPrice)}${Number(l.taxRatePercent) > 0 ? ` · GST ${Number(l.taxRatePercent)}%` : ''}${Number(l.discount) > 0 ? ` · ${rupees(l.discount)} off` : ''}`
        }));
    }

    get totals() {
        const b = this.bill;
        if (!b) return [];
        const rows = [{ key: 'sub', label: 'Subtotal', value: rupees(b.subtotal) }];
        if (Number(b.cgst)) rows.push({ key: 'cgst', label: 'CGST', value: rupees(b.cgst) });
        if (Number(b.sgst)) rows.push({ key: 'sgst', label: 'SGST', value: rupees(b.sgst) });
        if (Number(b.igst)) rows.push({ key: 'igst', label: 'IGST', value: rupees(b.igst) });
        if (Number(b.roundOff)) rows.push({ key: 'round', label: 'Round off', value: rupees(b.roundOff) });
        return rows;
    }

    get totalText() {
        return this.bill ? rupees(this.bill.totalAmount) : '';
    }

    get restoreLabel() {
        return this.isRestoring ? 'Bringing back…' : 'Yes, bring it back';
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handlePrint() {
        this.showPreview = true;
    }

    handleClosePreview() {
        this.showPreview = false;
    }

    handleAskRestore() {
        this.confirmingRestore = true;
    }

    handleKeep() {
        this.confirmingRestore = false;
    }

    handleRestore() {
        this.isRestoring = true;
        restoreBill({ billId: this.billId })
            .then((newId) => {
                this.toast('Brought back', `${this.bill.invoiceNumber} is back in Billing.`, 'success');
                this.dispatchEvent(new CustomEvent('restored', { detail: { billId: newId } }));
            })
            .catch((error) => this.toast('Not brought back', errorText(error), 'error'))
            .finally(() => {
                this.isRestoring = false;
                this.confirmingRestore = false;
            });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
