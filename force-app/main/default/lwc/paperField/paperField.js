import { LightningElement, api } from 'lwc';

const SEARCH_DELAY_MS = 300;

/**
 * One typeable box on the Easy Bill page, styled to sit on the bill rather
 * than look like a form field. Enter goes to the next box (fires `advance`).
 *
 * With `search` (term => Promise of [{ value, label, sub }]) it also offers
 * matches under the box: up/down to move, Enter or Tab to pick (fires `pick`).
 */
export default class PaperField extends LightningElement {
    @api value = '';
    @api label;
    @api placeholder;
    @api type = 'text';
    @api multiline = false;
    @api strong = false;
    @api search;
    // 0 shows the whole list as soon as the box gets focus.
    @api minChars = 2;

    options = [];
    highlightIndex = -1;

    _timer;
    _seq = 0;

    // LWC templates can't bind a <textarea> value (it becomes an attribute, which
    // a textarea ignores), so it's set here. Only when different, so the cursor
    // stays put while typing.
    renderedCallback() {
        const box = this.template.querySelector('textarea');
        const value = this.value || '';
        if (box && box.value !== value) {
            box.value = value;
        }
    }

    disconnectedCallback() {
        clearTimeout(this._timer);
    }

    @api
    focus() {
        const box = this.template.querySelector('input, textarea');
        if (box) {
            box.focus();
            if (box.select) {
                box.select();
            }
        }
    }

    get boxClass() {
        return this.strong ? 'paper-box paper-box_strong' : 'paper-box';
    }

    get hasOptions() {
        return this.options.length > 0;
    }

    get decoratedOptions() {
        return this.options.map((option, index) => ({
            ...option,
            optionClass: index === this.highlightIndex ? 'option option_active' : 'option',
            ariaSelected: index === this.highlightIndex ? 'true' : 'false'
        }));
    }

    close() {
        clearTimeout(this._timer);
        this._seq++;
        this.options = [];
        this.highlightIndex = -1;
    }

    runSearch(term) {
        const seq = ++this._seq;
        return this.search(term)
            .then((options) => {
                if (seq === this._seq) {
                    this.options = options || [];
                    this.highlightIndex = -1;
                }
            })
            .catch(() => {
                // Suggestions are only a help: typing still works without them.
                this.options = [];
            });
    }

    handleInput(event) {
        const value = event.target.value;
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { value } }));
        if (!this.search) {
            return;
        }
        clearTimeout(this._timer);
        const term = value.trim();
        if (term.length < this.minChars) {
            this.close();
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setTimeout(() => this.runSearch(term), SEARCH_DELAY_MS);
    }

    handleFocus() {
        if (this.search && Number(this.minChars) === 0) {
            this.runSearch((this.value || '').trim());
        }
    }

    handleBlur() {
        this.close();
        this.dispatchEvent(new CustomEvent('leave'));
    }

    handleKeydown(event) {
        const count = this.options.length;
        if (event.key === 'ArrowDown' && count) {
            event.preventDefault();
            this.highlightIndex = (this.highlightIndex + 1) % count;
        } else if (event.key === 'ArrowUp' && count) {
            event.preventDefault();
            this.highlightIndex = this.highlightIndex <= 0 ? count - 1 : this.highlightIndex - 1;
        } else if (event.key === 'Escape') {
            this.close();
        } else if (event.key === 'Tab' && !event.shiftKey && count && this.highlightIndex >= 0) {
            this.pick(this.options[this.highlightIndex]);
        } else if (event.key === 'Enter' && !event.ctrlKey && !event.metaKey) {
            if (count && this.highlightIndex >= 0) {
                event.preventDefault();
                this.pick(this.options[this.highlightIndex]);
                this.dispatchEvent(new CustomEvent('advance'));
            } else if (!this.multiline) {
                event.preventDefault();
                this.close();
                this.dispatchEvent(new CustomEvent('advance'));
            }
        }
    }

    // mousedown, not click: the box must keep focus, or its blur would close
    // this list before the click lands.
    handleOptionMouseDown(event) {
        event.preventDefault();
        const option = this.options.find((o) => o.value === event.currentTarget.dataset.value);
        if (option) {
            this.pick(option);
        }
    }

    pick(option) {
        this.close();
        this.dispatchEvent(new CustomEvent('pick', { detail: { option } }));
    }
}
