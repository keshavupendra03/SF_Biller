import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';
import searchParts from '@salesforce/apex/BillController.searchParts';
import { calculateLine } from 'c/gstMath';

const DEFAULT_GST_RATE = '18';
const SEARCH_DELAY_MS = 300;

let nextItemKey = 1;

// Cell values stay as the strings typed, so a half-typed "1." isn't
// rewritten under the cursor; they're converted when the document is built.
function newRow() {
    return {
        key: `item-${nextItemKey++}`,
        partId: null,
        description: '',
        quantity: '1',
        unitPrice: '',
        taxRatePercent: DEFAULT_GST_RATE,
        gstType: 'CGST_SGST',
        hsnSacCode: '',
        unitLabel: ''
    };
}

function asText(value) {
    return value === null || value === undefined ? '' : String(value);
}

function hasPrice(row) {
    return asText(row.unitPrice).trim() !== '';
}

// Quantity and GST always carry defaults, so they don't make a row "filled".
function isBlankRow(row) {
    return !row.partId && !row.description.trim() && !hasPrice(row);
}

function partFields(part) {
    return {
        partId: part.id,
        description: part.name,
        unitPrice: asText(part.price),
        taxRatePercent: part.taxRatePercent === null || part.taxRatePercent === undefined ? DEFAULT_GST_RATE : String(part.taxRatePercent),
        gstType: part.gstType || 'CGST_SGST',
        hsnSacCode: part.hsnCode || '',
        unitLabel: part.unitLabel || '',
        currentStock: part.currentStock
    };
}

function isExactMatch(part, term) {
    return (part.name || '').toLowerCase() === term.toLowerCase() || part.sku === term || part.barcode === term;
}

function formatAmount(value) {
    return (Number(value) || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/**
 * The type-along item lines shared by Quick Bill, Quick Estimate and Easy Bill.
 * Always ends in one empty line. Tab or Enter moves along the line and on to
 * the next, up/down moves between lines, and typing a name suggests parts.
 *
 * Variants: 'compact' (slds inputs, GST box always shown, greyed while off)
 * and 'paper' (drawn like the printed bill's table, with Sr and HSN, and a GST
 * column only while GST is on).
 *
 * Fires `lineschange` with the filled lines on every change, and `finish` when
 * Enter is pressed on the empty last line.
 *
 * Cells are plain <input>s, not lightning-input: moving between them needs
 * focus() plus select(), which lightning-input doesn't expose.
 */
export default class LineItemGrid extends LightningElement {
    @api variant = 'compact';
    @api includeGst = false;
    // Only a bill takes stock; a quote may be for more than is on the shelf.
    @api warnStock = false;

    items = [newRow()];
    // The row whose name is being typed, and the parts suggested for it.
    suggestKey = null;
    partResults = [];
    highlightIndex = -1;
    canScan = false;
    editingItem;

    _searchTimer;
    _searchSeq = 0;
    _lastSearchTerm;
    _lastResults = [];
    _pendingFocus;

    connectedCallback() {
        try {
            this.canScan = getBarcodeScanner().isAvailable();
        } catch (e) {
            this.canScan = false;
        }
    }

    renderedCallback() {
        if (this._pendingFocus) {
            const { key, field } = this._pendingFocus;
            this._pendingFocus = undefined;
            this.focusCell(key, field);
        }
    }

    disconnectedCallback() {
        clearTimeout(this._searchTimer);
    }

    @api
    focusFirst() {
        this.focusCell(this.items[0].key, 'description');
    }

    // ---- view state -----------------------------------------------------

    get isPaper() {
        return this.variant === 'paper';
    }

    get showGstCell() {
        return !this.isPaper || this.includeGst;
    }

    get gstDisabled() {
        return !this.includeGst;
    }

    get gridClass() {
        return this.isPaper ? 'item-grid item-grid_paper' : 'item-grid';
    }

    get lineClass() {
        if (!this.isPaper) {
            return 'item-line';
        }
        return this.includeGst ? 'item-line item-line_paper item-line_paper-gst' : 'item-line item-line_paper';
    }

    get headerClass() {
        return `${this.lineClass} item-header`;
    }

    get textInputClass() {
        return this.isPaper ? 'paper-input' : 'slds-input item-input';
    }

    get numberInputClass() {
        return this.isPaper ? 'paper-input cell-number' : 'slds-input item-input cell-number';
    }

    get editableFields() {
        const fields = ['description'];
        if (this.isPaper) {
            fields.push('hsnSacCode');
        }
        fields.push('quantity', 'unitPrice');
        if (this.includeGst) {
            fields.push('taxRatePercent');
        }
        return fields;
    }

    toBillLine(row) {
        return this.includeGst ? row : { ...row, taxRatePercent: 0 };
    }

    get decoratedItems() {
        return this.items.map((row, index) => {
            const number = index + 1;
            const stock = row.currentStock;
            const isShort = this.warnStock && !!row.partId && stock !== null && stock !== undefined && Number(row.quantity) > Number(stock);
            const showSuggestions = row.key === this.suggestKey && this.partResults.length > 0;
            return {
                ...row,
                number,
                isFilled: !isBlankRow(row),
                showDetails: !this.isPaper && !isBlankRow(row),
                formattedAmount: hasPrice(row) ? `₹${formatAmount(calculateLine(this.toBillLine(row)).total)}` : '',
                stockNote: isShort ? `Only ${stock} in stock` : '',
                showSuggestions,
                suggestions: showSuggestions ? this.decoratedPartResults : [],
                nameLabel: `Item ${number} name`,
                hsnLabel: `Item ${number} HSN`,
                quantityLabel: `Item ${number} quantity`,
                priceLabel: `Item ${number} price`,
                gstLabel: `Item ${number} GST percent`
            };
        });
    }

    get decoratedPartResults() {
        return this.partResults.map((part, index) => {
            const isActive = index === this.highlightIndex;
            return {
                ...part,
                formattedPrice: formatAmount(part.price),
                stockLabel: part.currentStock === null || part.currentStock === undefined ? '' : `${part.currentStock} in stock`,
                stockClass: Number(part.currentStock) > 0 ? 'slds-badge slds-theme_success' : 'slds-badge slds-theme_error',
                optionClass: isActive ? 'slds-button slds-button_reset suggestion suggestion_active' : 'slds-button slds-button_reset suggestion',
                ariaSelected: isActive ? 'true' : 'false'
            };
        });
    }

    // ---- rows -----------------------------------------------------------

    // Typing a price into the last row is what opens the next one, so Tab
    // from that row lands on a new item name with nothing to click.
    setItems(rows) {
        const last = rows[rows.length - 1];
        this.items = !last || hasPrice(last) ? [...rows, newRow()] : rows;
        this.dispatchEvent(
            new CustomEvent('lineschange', {
                detail: { lines: this.items.filter((row) => !isBlankRow(row)).map((row) => ({ ...row })) }
            })
        );
    }

    updateRow(key, changes) {
        this.setItems(this.items.map((row) => (row.key === key ? { ...row, ...changes } : row)));
    }

    removeRow(key) {
        const index = this.items.findIndex((row) => row.key === key);
        this.setItems(this.items.filter((row) => row.key !== key));
        const next = this.items[Math.min(index, this.items.length - 1)];
        this._pendingFocus = { key: next.key, field: 'description' };
    }

    handleRemoveItem(event) {
        this.removeRow(event.currentTarget.dataset.key);
    }

    handleEditItem(event) {
        this.editingItem = this.items.find((row) => row.key === event.currentTarget.dataset.key);
    }

    handleItemEditorSave(event) {
        const { quantity, unitPrice, taxRatePercent, ...rest } = event.detail;
        this.updateRow(this.editingItem.key, {
            ...rest,
            key: this.editingItem.key,
            quantity: asText(quantity),
            unitPrice: asText(unitPrice),
            taxRatePercent: asText(taxRatePercent)
        });
        this.editingItem = undefined;
    }

    handleItemEditorCancel() {
        this.editingItem = undefined;
    }

    // ---- moving between cells -------------------------------------------

    focusCell(key, field) {
        const input = this.template.querySelector(`input[data-key="${key}"][data-field="${field}"]`);
        if (input) {
            input.focus();
            input.select();
        }
    }

    focusNextCell(key, field) {
        const fields = this.editableFields;
        const next = fields[fields.indexOf(field) + 1];
        if (next) {
            this.focusCell(key, next);
            return;
        }
        const index = this.items.findIndex((row) => row.key === key);
        const nextRow = this.items[index + 1];
        if (nextRow) {
            this.focusCell(nextRow.key, 'description');
        }
    }

    focusSameCellInRow(key, field, step) {
        const index = this.items.findIndex((row) => row.key === key);
        const row = this.items[index + step];
        if (row) {
            this.focusCell(row.key, field);
        }
    }

    // Shared by every cell. Up/down mustn't nudge a number box's value by
    // accident, so they always move between lines instead.
    handleCommonKeys(event) {
        const { key, field } = event.target.dataset;
        if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault();
            this.focusSameCellInRow(key, field, event.key === 'ArrowDown' ? 1 : -1);
        } else if (event.key === 'Delete' && event.ctrlKey) {
            event.preventDefault();
            this.removeRow(key);
        }
    }

    handleCellKeydown(event) {
        if (event.key === 'Enter' && !event.ctrlKey && !event.metaKey) {
            event.preventDefault();
            const { key, field } = event.target.dataset;
            this.focusNextCell(key, field);
            return;
        }
        this.handleCommonKeys(event);
    }

    handleCellInput(event) {
        const { key, field } = event.target.dataset;
        this.updateRow(key, { [field]: event.target.value });
    }

    // ---- part lookup in the name box ------------------------------------

    closeSuggestions() {
        clearTimeout(this._searchTimer);
        this._searchSeq++;
        this.suggestKey = null;
        this.partResults = [];
        this.highlightIndex = -1;
    }

    // Editing a name unlinks the part: what's on the row is no longer that
    // part, so its stock mustn't be deducted.
    handleNameInput(event) {
        const { key } = event.target.dataset;
        const value = event.target.value;
        this.updateRow(key, { description: value, partId: null, currentStock: undefined });
        clearTimeout(this._searchTimer);
        this.suggestKey = key;
        this.highlightIndex = -1;
        const term = value.trim();
        if (term.length < 2) {
            this.partResults = [];
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = setTimeout(() => this.runPartSearch(term), SEARCH_DELAY_MS);
    }

    runPartSearch(term) {
        const seq = ++this._searchSeq;
        return searchParts({ searchTerm: term })
            .then((results) => {
                const found = results || [];
                this._lastSearchTerm = term;
                this._lastResults = found;
                if (seq === this._searchSeq) {
                    this.partResults = found;
                }
                return found;
            })
            .catch((error) => {
                this.showError(error);
                return [];
            });
    }

    handleNameKeydown(event) {
        const { key } = event.target.dataset;
        const count = this.suggestKey === key ? this.partResults.length : 0;
        if (event.key === 'ArrowDown' && count) {
            event.preventDefault();
            this.highlightIndex = (this.highlightIndex + 1) % count;
        } else if (event.key === 'ArrowUp' && count) {
            event.preventDefault();
            this.highlightIndex = this.highlightIndex <= 0 ? count - 1 : this.highlightIndex - 1;
        } else if (event.key === 'Escape') {
            this.closeSuggestions();
        } else if (event.key === 'Tab' && !event.shiftKey && count && this.highlightIndex >= 0) {
            event.preventDefault();
            this.selectPart(key, this.partResults[this.highlightIndex]);
        } else if (event.key === 'Enter' && !event.ctrlKey && !event.metaKey) {
            event.preventDefault();
            this.handleNameEnter(key, count);
        } else {
            this.handleCommonKeys(event);
        }
    }

    handleNameEnter(key, count) {
        if (count && this.highlightIndex >= 0) {
            this.selectPart(key, this.partResults[this.highlightIndex]);
            return;
        }
        this.closeSuggestions();
        if (isBlankRow(this.items.find((row) => row.key === key))) {
            this.dispatchEvent(new CustomEvent('finish'));
            return;
        }
        // Move at once, not after a server lookup, or a fast typist's next keys
        // land in this box. Leaving the box runs the part link (handleNameBlur).
        this.focusNextCell(key, 'description');
    }

    handleNameBlur(event) {
        const { key } = event.target.dataset;
        this.closeSuggestions();
        this.linkExactPart(key);
    }

    // A name typed in full and tabbed past is still that part, so its stock
    // deducts and it doesn't become a duplicate. A price already typed stays.
    linkExactPart(key) {
        const row = this.items.find((r) => r.key === key);
        const term = row ? row.description.trim() : '';
        if (!row || row.partId || term.length < 2) {
            return Promise.resolve();
        }
        const lookup = term === this._lastSearchTerm ? Promise.resolve(this._lastResults) : searchParts({ searchTerm: term });
        return lookup
            .then((results) => {
                const part = (results || []).find((p) => isExactMatch(p, term));
                const current = this.items.find((r) => r.key === key);
                if (!part || !current || current.partId || current.description.trim() !== term) {
                    return;
                }
                // The cursor has moved on by now, so keep anything typed meanwhile.
                const fields = partFields(part);
                this.updateRow(key, {
                    ...fields,
                    unitPrice: hasPrice(current) ? current.unitPrice : fields.unitPrice,
                    hsnSacCode: current.hsnSacCode || fields.hsnSacCode
                });
            })
            .catch((error) => this.showError(error));
    }

    // mousedown, not click: the name box must keep focus, or its blur would
    // close this list before the click lands.
    handleSuggestionMouseDown(event) {
        event.preventDefault();
        const { key, partId } = event.currentTarget.dataset;
        const part = this.partResults.find((p) => p.id === partId);
        if (part) {
            this.selectPart(key, part);
        }
    }

    // A part already on the bill adds one more to that row instead of a
    // second row.
    selectPart(key, part, moveFocus = true) {
        this.closeSuggestions();
        const existing = this.items.find((row) => row.partId === part.id && row.key !== key);
        if (existing) {
            this.setItems(
                this.items
                    .filter((row) => row.key !== key)
                    .map((row) => (row.key === existing.key ? { ...row, quantity: String((Number(row.quantity) || 0) + 1) } : row))
            );
            this._pendingFocus = moveFocus ? { key: this.items[this.items.length - 1].key, field: 'description' } : undefined;
            return;
        }
        this.updateRow(key, partFields(part));
        this._pendingFocus = moveFocus ? { key, field: 'quantity' } : undefined;
    }

    handleScan() {
        const scanner = getBarcodeScanner();
        scanner
            .beginCapture({ barcodeTypes: Object.values(scanner.barcodeTypes || {}) })
            .then((result) => {
                const code = (result && result.value ? result.value : '').trim();
                if (!code) {
                    return undefined;
                }
                return this.runPartSearch(code).then((results) => {
                    const part = results.find((p) => p.barcode === code || p.sku === code) || (results.length === 1 ? results[0] : null);
                    if (!results.length) {
                        this.showToast('No part found', `Nothing in inventory matches barcode ${code}.`, 'warning');
                        return;
                    }
                    const key = this.emptyRowKey();
                    if (part) {
                        this.selectPart(key, part, false);
                        this.showToast(`Added ${part.name}`, '', 'success');
                    } else {
                        this.updateRow(key, { description: code });
                        this.suggestKey = key;
                    }
                });
            })
            .catch((error) => {
                // The user backing out of the scanner isn't an error.
                if (error && error.code !== 'USER_DISMISSED') {
                    this.showToast('Scan failed', error.message || 'Could not read the barcode.', 'error');
                }
            })
            .finally(() => scanner.endCapture());
    }

    emptyRowKey() {
        const last = this.items[this.items.length - 1];
        if (isBlankRow(last)) {
            return last.key;
        }
        const row = newRow();
        this.items = [...this.items, row];
        return row.key;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
