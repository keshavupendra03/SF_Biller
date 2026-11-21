import { LightningElement, api } from 'lwc';

/**
 * A Delete button that asks first, in the page rather than a pop-up, so it
 * works the same in the Salesforce Mobile App and on a laptop. Fires
 * `confirm` when "Yes, delete" is pressed; the screen does the deleting.
 */
export default class DeleteConfirm extends LightningElement {
    @api buttonLabel = 'Delete';
    // What will happen, said plainly: shown when asking.
    @api message;
    @api confirmLabel = 'Yes, delete';
    // While the screen is deleting: the buttons can't be pressed twice.
    @api busy = false;

    isAsking = false;

    handleAsk() {
        this.isAsking = true;
    }

    handleNo() {
        this.isAsking = false;
    }

    handleYes() {
        this.isAsking = false;
        this.dispatchEvent(new CustomEvent('confirm'));
    }
}
