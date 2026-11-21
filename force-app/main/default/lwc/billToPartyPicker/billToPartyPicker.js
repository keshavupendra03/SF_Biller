import { LightningElement, api } from 'lwc';
import listBillToParties from '@salesforce/apex/DirectoryController.listBillToParties';
import { STATE_OPTIONS, checkGstinBox, withStateFromGstin, changedValue } from 'c/gst';

const SEARCH_DELAY_MS = 250;
const PARTIES_SHOWN = 8;
const EMPTY_DETAILS = { address: '', contactPhone: '', gstin: '', state: '' };

/**
 * Pick a saved Bill To Party, or type a new one, for Quick Bill and Quick
 * Estimate. Saved parties list as soon as the box is entered, so a regular
 * party is picked without typing; ↑ ↓ and Enter pick from the keyboard. A
 * name that isn't picked is a new party, with optional details, which
 * BillToPartyService saves for next time (or matches to a saved party of the
 * same name).
 *
 * Fires `partychange` with { billToPartyId, billToParty, name }: the picked
 * party's Id, or the typed party, never both.
 */
export default class BillToPartyPicker extends LightningElement {
    stateOptions = STATE_OPTIONS;
    term = '';
    results = [];
    highlightIndex = -1;
    isOpen = false;
    selected;
    details = { ...EMPTY_DETAILS };

    // Everything the last search found, not just what's shown, for the
    // exact-name match on leaving the box.
    _all = [];
    _timer;
    _seq = 0;
    _focusAfterRender = false;

    @api
    focus() {
        const input = this.template.querySelector('[data-id="party-search"]');
        if (input) {
            input.focus();
        }
    }

    renderedCallback() {
        if (this._focusAfterRender) {
            this._focusAfterRender = false;
            this.focus();
        }
    }

    disconnectedCallback() {
        clearTimeout(this._timer);
    }

    get isNewParty() {
        return !this.selected && !!this.term.trim();
    }

    get selectedDetails() {
        const s = this.selected;
        return [s.gstin && `GSTIN ${s.gstin}`, s.contactPhone, s.address, s.state].filter((part) => part).join(' · ');
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click${this.isOpen ? ' slds-is-open' : ''}`;
    }

    get ariaExpanded() {
        return this.isOpen ? 'true' : 'false';
    }

    get decoratedResults() {
        return this.results.map((party, index) => ({
            ...party,
            meta: [party.gstin, party.contactPhone, party.state].filter((part) => part).join(' · '),
            optionClass: `slds-media slds-listbox__option slds-listbox__option_entity slds-listbox__option_has-meta${
                index === this.highlightIndex ? ' slds-has-focus party-option_active' : ''
            }`,
            ariaSelected: index === this.highlightIndex ? 'true' : 'false'
        }));
    }

    // ---- searching --------------------------------------------------------

    runSearch(term) {
        const seq = ++this._seq;
        return listBillToParties({ searchTerm: term })
            .then((results) => {
                if (seq !== this._seq) {
                    return;
                }
                this._all = results;
                this.results = results.slice(0, PARTIES_SHOWN);
                this.highlightIndex = -1;
                this.isOpen = this.results.length > 0;
            })
            .catch(() => {
                // Suggestions are only a help: a typed new party still works.
                this.close();
            });
    }

    close() {
        clearTimeout(this._timer);
        this._seq++;
        this.isOpen = false;
        this.highlightIndex = -1;
    }

    handleFocus() {
        this.runSearch(this.term.trim());
    }

    handleInput(event) {
        this.term = event.target.value;
        this.notify();
        clearTimeout(this._timer);
        const term = this.term.trim();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setTimeout(() => this.runSearch(term), SEARCH_DELAY_MS);
    }

    // A saved party's name typed in full, without picking it, still finds it.
    handleBlur() {
        this.close();
        const typed = this.term.trim().toLowerCase();
        const hasDetails = Object.values(this.details).some((value) => value.trim());
        if (!typed || hasDetails) {
            return;
        }
        const known = this._all.find((party) => (party.name || '').toLowerCase() === typed);
        if (known) {
            this.pick(known);
        }
    }

    handleKeydown(event) {
        const count = this.results.length;
        if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault();
            if (!this.isOpen) {
                this.runSearch(this.term.trim());
                return;
            }
            if (!count) {
                return;
            }
            const step = event.key === 'ArrowDown' ? 1 : -1;
            this.highlightIndex = this.highlightIndex < 0 && step < 0 ? count - 1 : (this.highlightIndex + step + count) % count;
        } else if (event.key === 'Escape') {
            if (this.isOpen) {
                event.preventDefault();
                event.stopPropagation();
            }
            this.close();
        } else if ((event.key === 'Enter' || (event.key === 'Tab' && !event.shiftKey)) && this.isOpen && this.highlightIndex >= 0) {
            if (event.key === 'Enter') {
                event.preventDefault();
            }
            this.pick(this.results[this.highlightIndex]);
        } else if (event.key === 'Enter') {
            event.preventDefault();
            this.close();
        }
    }

    // mousedown, not click: the box must keep focus, or its blur would close
    // the list before the click lands.
    handleOptionMouseDown(event) {
        event.preventDefault();
        const party = this.results.find((p) => p.id === event.currentTarget.dataset.value);
        if (party) {
            this.pick(party);
        }
    }

    // ---- choosing ---------------------------------------------------------

    pick(party) {
        this.close();
        this.selected = party;
        this.term = party.name;
        this.details = { ...EMPTY_DETAILS };
        this.notify();
    }

    handleChange() {
        this.selected = undefined;
        this.term = '';
        this.details = { ...EMPTY_DETAILS };
        this._focusAfterRender = true;
        this.notify();
    }

    handleDetailChange(event) {
        const field = event.target.dataset.field;
        this.details = { ...this.details, [field]: changedValue(event) || '' };
        if (field === 'gstin') {
            checkGstinBox(event.target);
            this.details = withStateFromGstin(this.details);
        }
        this.notify();
    }

    notify() {
        const name = this.selected ? this.selected.name : this.term.trim();
        const detail = this.selected
            ? { billToPartyId: this.selected.id, billToParty: null, name }
            : { billToPartyId: null, billToParty: name ? { name, ...this.details } : null, name };
        this.dispatchEvent(new CustomEvent('partychange', { detail }));
    }
}
