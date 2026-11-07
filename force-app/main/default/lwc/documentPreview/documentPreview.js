import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';
import getPdfDownload from '@salesforce/apex/DocumentPdfService.getPdfDownload';
import getPublicLink from '@salesforce/apex/DocumentPdfService.getPublicLink';

export default class DocumentPreview extends LightningElement {
    @api recordId;
    @api heading = 'Preview';
    // The Visualforce page that renders this document — InvoicePdf for
    // bills/estimates, JobSlipPdf for job slips. DocumentPdfService picks
    // the same page server-side from the record type when making the PDF.
    @api pageName = 'InvoicePdf';
    // Which company a blank job slip is for. Other documents know their own.
    @api workshopProfileId;

    isFrameLoading = true;
    isDownloading = false;

    // navigator.share() only works when it's still inside the browser's
    // "recent user gesture" window — an await on an Apex round-trip
    // usually burns that window before share() ever runs. Pre-fetching
    // the link as soon as the popup opens means the Download tap, a few
    // seconds later, almost always chains off an already-resolved promise
    // (a same-tick microtask) instead of a fresh network call.
    _linkPromise;

    connectedCallback() {
        if (this.isPhone) {
            this._linkPromise = this.fetchLink();
        }
    }

    get previewUrl() {
        const company = this.workshopProfileId ? `&workshop=${this.workshopProfileId}` : '';
        return `/apex/${this.pageName}?id=${this.recordId}&format=html${company}`;
    }

    fetchLink() {
        return getPublicLink({ recordId: this.recordId, workshopProfileId: this.workshopProfileId });
    }

    get isPhone() {
        return FORM_FACTOR === 'Small';
    }

    get downloadLabel() {
        return this.isDownloading ? 'Preparing…' : 'Download PDF';
    }

    handleFrameLoad() {
        this.isFrameLoading = false;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleDownload() {
        if (this.isDownloading) {
            return;
        }
        this.isDownloading = true;
        const work = this.isPhone ? this.downloadViaShareSheet() : this.downloadInPage();
        work.catch((error) => this.showError(error)).finally(() => {
            this.isDownloading = false;
        });
    }

    // The Salesforce Mobile App opens standard__webPage links in its own
    // embedded browser tab, which doesn't complete file downloads the way
    // a real browser does — that's why a plain "open this URL" approach
    // didn't work. The OS share sheet (Chrome, Drive, Files, WhatsApp, …)
    // runs outside that embedded tab, so handing the link to navigator
    // .share() is what actually lets the phone save the file.
    //
    // When share() itself isn't available (confirmed on-device: the app
    // fell through to the old fallback, which then failed with "Page
    // doesn't exist" even though the URL is a genuine, working link —
    // Salesforce's own NavigationMixin rejects it, not the destination),
    // fall back to a plain anchor click instead of NavigationMixin. A
    // real <a href target="_blank"> is a native DOM action that doesn't
    // go through Salesforce's own URL classification at all.
    downloadViaShareSheet() {
        const linkPromise = this._linkPromise || this.fetchLink();
        return linkPromise.then((link) => {
            if (!navigator.share) {
                this.openInBrowser(link.downloadUrl);
                return undefined;
            }
            return navigator.share({
                title: link.documentNumber,
                text: `${link.documentNumber} PDF`,
                url: link.downloadUrl
            }).catch((error) => {
                // AbortError just means the user closed the share sheet without picking anything.
                if (error && error.name !== 'AbortError') {
                    this.openInBrowser(link.downloadUrl);
                }
            });
        });
    }

    openInBrowser(url) {
        const anchor = this.refs.downloadLink;
        anchor.removeAttribute('download');
        anchor.target = '_blank';
        anchor.rel = 'noopener';
        anchor.href = url;
        anchor.click();
    }

    downloadInPage() {
        return getPdfDownload({ recordId: this.recordId, workshopProfileId: this.workshopProfileId }).then((download) => {
            const bytes = atob(download.base64Data);
            const buffer = new Uint8Array(bytes.length);
            for (let i = 0; i < bytes.length; i++) {
                buffer[i] = bytes.charCodeAt(i);
            }
            const url = URL.createObjectURL(new Blob([buffer], { type: 'application/pdf' }));
            const anchor = this.refs.downloadLink;
            anchor.href = url;
            anchor.download = download.fileName;
            anchor.click();
            // Revoke after the click has been handed off to the browser.
            setTimeout(() => URL.revokeObjectURL(url), 10000);
        });
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'Could not prepare the PDF.';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }
}
