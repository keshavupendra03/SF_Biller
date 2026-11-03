import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';
import findCustomerByPhone from '@salesforce/apex/QuickBillController.findCustomerByPhone';
import createQuickBill from '@salesforce/apex/QuickBillController.createQuickBill';
import searchParts from '@salesforce/apex/BillController.searchParts';
import { calculateLine, calculateBillTotals } from 'c/gstMath';
import { disablePullToRefresh } from 'c/disablePullToRefresh';

const MODE_OPTIONS = [
    { label: 'Customer', value: 'customer' },
    { label: 'Walk-in', value: 'walkin' }
];

const EMPTY_CUSTOMER = { name: '', phone: '', address: '', gstin: '', state: '' };
const EMPTY_VEHICLE = { registrationNumber: '', make: '', model: '' };
const NEW_VEHICLE = '__new';
const DEFAULT_GST_RATE = '18';
const SEARCH_DELAY_MS = 300;
const PHONE_LOOKUP_DELAY_MS = 400;

function todayIso() {
    const now = new Date();
    const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
    return local.toISOString().slice(0, 10);
}

function formatAmount(value) {
    return (Number(value) || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

let nextItemKey = 1;

// Cell values stay as the strings typed, so a half-typed "1." isn't
// rewritten under the cursor; they're converted when the bill is built.
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

/**
 * Quick Bill — one screen to bill a counter sale of spare parts, or any
 * car customer, without setting up the customer/vehicle first.
 * QuickBillController resolves the customer (shared Walk-in Customer, or
 * matched/created by phone) and the vehicle, then creates the bill
 * through BillController.createBill like every other bill.
 */
export default class QuickBill extends NavigationMixin(LightningElement) {
    modeOptions = MODE_OPTIONS;

    mode = 'customer';
    customer = { ...EMPTY_CUSTOMER };
    showMoreCustomer = false;
    match;
    isLookingUp = false;

    selectedVehicleId = null;
    newVehicle = { ...EMPTY_VEHICLE };

    // Always ends in one empty row, ready to type into (setItems keeps it so).
    items = [newRow()];
    includeGst = false;
    // The row whose name is being typed, and the parts suggested for it.
    suggestKey = null;
    partResults = [];
    highlightIndex = -1;
    canScan = false;

    billDate = todayIso();
    notes = '';
    showMoreOptions = false;

    editingItem;
    isSubmitting = false;
    createdBill;
    showPreview = false;

    _searchTimer;
    _phoneTimer;
    _searchSeq = 0;
    _lastSearchTerm;
    _lastResults = [];
    _pendingFocus;

    connectedCallback() {
        disablePullToRefresh(this);
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
        clearTimeout(this._phoneTimer);
    }

    // ---- customer -------------------------------------------------------

    get isWalkIn() {
        return this.mode === 'walkin';
    }

    get isCustomerMode() {
        return !this.isWalkIn;
    }

    get hasMatch() {
        return !!this.match;
    }

    get nameDisabled() {
        return this.hasMatch;
    }

    get moreCustomerLabel() {
        return this.showMoreCustomer ? 'Hide address & GST details' : 'Add address & GST details';
    }

    handleModeChange(event) {
        this.mode = event.detail.value;
    }

    handleCustomerFieldChange(event) {
        const field = event.target.dataset.field;
        this.customer = { ...this.customer, [field]: event.target.value };
        if (field === 'phone') {
            this.schedulePhoneLookup();
        }
    }

    handleToggleMoreCustomer() {
        this.showMoreCustomer = !this.showMoreCustomer;
    }

    schedulePhoneLookup() {
        clearTimeout(this._phoneTimer);
        const phone = this.customer.phone;
        const hadMatch = this.hasMatch;
        this.match = undefined;
        this.selectedVehicleId = null;
        if (hadMatch) {
            this.customer = { ...this.customer, name: '' };
        }
        if ((phone || '').replace(/\D/g, '').length < 10) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._phoneTimer = setTimeout(() => this.lookUpPhone(phone), PHONE_LOOKUP_DELAY_MS);
    }

    lookUpPhone(phone) {
        this.isLookingUp = true;
        return findCustomerByPhone({ phone })
            .then((match) => {
                // Ignore a reply for a number that has since been edited.
                if (phone !== this.customer.phone) {
                    return;
                }
                this.match = match || undefined;
                if (match) {
                    this.customer = {
                        ...this.customer,
                        name: match.name,
                        address: this.customer.address || match.address || '',
                        gstin: this.customer.gstin || match.gstin || '',
                        state: this.customer.state || match.state || ''
                    };
                    this.selectedVehicleId = match.vehicles && match.vehicles.length === 1 ? match.vehicles[0].id : null;
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLookingUp = false;
            });
    }

    // ---- vehicle --------------------------------------------------------

    get matchVehicles() {
        return this.hasMatch && this.match.vehicles ? this.match.vehicles : [];
    }

    get hasMatchVehicles() {
        return this.matchVehicles.length > 0;
    }

    get vehicleChips() {
        const chips = this.matchVehicles.map((v) => ({
            value: v.id,
            label: v.registrationNumber,
            variant: v.id === this.selectedVehicleId ? 'brand' : 'neutral'
        }));
        chips.push({ value: NEW_VEHICLE, label: 'Other vehicle', variant: this.isNewVehicleSelected ? 'brand' : 'neutral' });
        chips.push({ value: '', label: 'No vehicle', variant: this.isNoVehicleSelected ? 'brand' : 'neutral' });
        return chips;
    }

    get isNewVehicleSelected() {
        return this.selectedVehicleId === NEW_VEHICLE;
    }

    get isNoVehicleSelected() {
        return !this.selectedVehicleId;
    }

    // With a matched customer the typed-vehicle fields appear only for
    // "Other vehicle"; for a new customer they're simply optional.
    get showVehicleFields() {
        return this.hasMatchVehicles ? this.isNewVehicleSelected : true;
    }

    handleVehicleChip(event) {
        this.selectedVehicleId = event.target.dataset.value || null;
    }

    handleVehicleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.newVehicle = { ...this.newVehicle, [field]: value };
    }

    // ---- items ----------------------------------------------------------

    // Typing a price into the last row is what opens the next one, so Tab
    // from that row lands on a new item name with nothing to click.
    setItems(rows) {
        const last = rows[rows.length - 1];
        this.items = !last || hasPrice(last) ? [...rows, newRow()] : rows;
    }

    updateRow(key, changes) {
        this.setItems(this.items.map((row) => (row.key === key ? { ...row, ...changes } : row)));
    }

    get filledItems() {
        return this.items.filter((row) => !isBlankRow(row));
    }

    get hasItems() {
        return this.filledItems.length > 0;
    }

    get itemCount() {
        return this.filledItems.reduce((sum, row) => sum + (Number(row.quantity) || 0), 0);
    }

    get itemCountLabel() {
        const count = this.itemCount;
        return `${count} ${count === 1 ? 'item' : 'items'}`;
    }

    get gstDisabled() {
        return !this.includeGst;
    }

    get isGstExcluded() {
        return this.hasItems && !this.includeGst;
    }

    toBillLine(row) {
        return this.includeGst ? row : { ...row, taxRatePercent: 0 };
    }

    get decoratedItems() {
        return this.items.map((row, index) => {
            const number = index + 1;
            const stock = row.currentStock;
            const isShort = !!row.partId && stock !== null && stock !== undefined && Number(row.quantity) > Number(stock);
            const showSuggestions = row.key === this.suggestKey && this.partResults.length > 0;
            return {
                ...row,
                isFilled: !isBlankRow(row),
                formattedAmount: hasPrice(row) ? `₹${formatAmount(calculateLine(this.toBillLine(row)).total)}` : '',
                stockNote: isShort ? `Only ${stock} in stock` : '',
                showSuggestions,
                suggestions: showSuggestions ? this.decoratedPartResults : [],
                nameLabel: `Item ${number} name`,
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

    handleToggleGst(event) {
        this.includeGst = event.target.checked;
    }

    focusCell(key, field) {
        const input = this.template.querySelector(`input[data-key="${key}"][data-field="${field}"]`);
        if (input) {
            input.focus();
            input.select();
        }
    }

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

    handleCellInput(event) {
        const { key, field } = event.target.dataset;
        this.updateRow(key, { [field]: event.target.value });
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
            if (count && this.highlightIndex >= 0) {
                this.selectPart(key, this.partResults[this.highlightIndex]);
            } else {
                // Also how a USB barcode scanner finishes: code, then Enter.
                this.closeSuggestions();
                this.linkExactPart(key).then(() => this.focusCell(key, 'quantity'));
            }
        }
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
                const fields = partFields(part);
                this.updateRow(key, hasPrice(current) ? { ...fields, unitPrice: current.unitPrice } : fields);
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

    // Ctrl+Enter from anywhere in the grid, so finishing a bill doesn't mean
    // tabbing through the empty last row.
    handleGridKeydown(event) {
        if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
            event.preventDefault();
            this.handleCreate();
        }
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

    handleRemoveItem(event) {
        const key = event.currentTarget.dataset.key;
        this.setItems(this.items.filter((row) => row.key !== key));
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

    // ---- totals ---------------------------------------------------------

    get totals() {
        return calculateBillTotals(this.filledItems.map((row) => this.toBillLine(row)));
    }

    get formattedSubtotal() {
        return formatAmount(this.totals.subtotal);
    }

    get formattedCgst() {
        return formatAmount(this.totals.cgst);
    }

    get formattedSgst() {
        return formatAmount(this.totals.sgst);
    }

    get formattedIgst() {
        return formatAmount(this.totals.igst);
    }

    get formattedTotal() {
        return formatAmount(this.totals.grandTotal);
    }

    get hasCgstSgst() {
        return this.totals.cgst > 0 || this.totals.sgst > 0;
    }

    get hasIgst() {
        return this.totals.igst > 0;
    }

    // ---- more options ---------------------------------------------------

    get moreOptionsLabel() {
        return this.showMoreOptions ? 'Hide bill date & notes' : 'Bill date & notes';
    }

    get moreOptionsIcon() {
        return this.showMoreOptions ? 'utility:chevronup' : 'utility:chevrondown';
    }

    handleToggleMoreOptions() {
        this.showMoreOptions = !this.showMoreOptions;
    }

    handleBillDateChange(event) {
        this.billDate = event.target.value;
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    // ---- submit ---------------------------------------------------------

    // The first thing still missing, shown above the Create button.
    get missingReason() {
        if (this.isCustomerMode) {
            if ((this.customer.phone || '').replace(/\D/g, '').length < 10) {
                return 'Enter the customer’s 10-digit phone number, or switch to Walk-in.';
            }
            if (!this.hasMatch && !(this.customer.name || '').trim()) {
                return 'Enter the customer’s name.';
            }
        }
        if (!this.hasItems) {
            return 'Add at least one part or item.';
        }
        const rows = this.filledItems;
        if (rows.some((row) => !row.description.trim())) {
            return 'Give every item a name.';
        }
        if (rows.some((row) => !hasPrice(row) || Number(row.unitPrice) < 0)) {
            return 'Enter a price for every item.';
        }
        if (rows.some((row) => !(Number(row.quantity) > 0))) {
            return 'Every item needs a quantity.';
        }
        return '';
    }

    get createDisabled() {
        return this.isSubmitting || this.isLookingUp || !!this.missingReason;
    }

    get createLabel() {
        return this.isSubmitting ? 'Creating…' : 'Create Bill';
    }

    buildRequest() {
        const typedVehicle = this.showVehicleFields && this.newVehicle.registrationNumber.trim() ? { ...this.newVehicle } : null;
        return {
            isWalkIn: this.isWalkIn,
            customerName: this.isWalkIn ? null : this.customer.name,
            customerPhone: this.isWalkIn ? null : this.customer.phone,
            customerAddress: this.isWalkIn ? null : this.customer.address,
            customerGstin: this.isWalkIn ? null : this.customer.gstin,
            customerState: this.isWalkIn ? null : this.customer.state,
            vehicleId: this.isWalkIn || !this.selectedVehicleId || this.isNewVehicleSelected ? null : this.selectedVehicleId,
            newVehicle: this.isWalkIn ? null : typedVehicle,
            billDate: this.billDate || null,
            notes: this.notes,
            includeGst: this.includeGst,
            lineItems: this.filledItems.map((row) => ({
                partId: row.partId,
                description: row.description.trim(),
                quantity: Number(row.quantity),
                unitPrice: Number(row.unitPrice),
                taxRatePercent: Number(row.taxRatePercent) || 0,
                gstType: row.gstType || 'CGST_SGST',
                hsnSacCode: row.hsnSacCode,
                unitLabel: row.unitLabel
            }))
        };
    }

    handleCreate() {
        if (this.createDisabled) {
            return;
        }
        this.isSubmitting = true;
        createQuickBill({ request: this.buildRequest() })
            .then((summary) => {
                this.createdBill = { ...summary, formattedTotal: formatAmount(summary.totalAmount) };
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    // ---- after creation -------------------------------------------------

    get isCreated() {
        return !!this.createdBill;
    }

    get isEditing() {
        return !this.createdBill;
    }

    handlePrint() {
        this.showPreview = true;
    }

    handleClosePreview() {
        this.showPreview = false;
    }

    handleViewBill() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Bill_Detail' },
            state: { c__recordId: this.createdBill.billId }
        });
    }

    // Keeps the Walk-in/Customer choice — a counter usually bills the same
    // kind of sale several times in a row.
    handleNewBill() {
        this.customer = { ...EMPTY_CUSTOMER };
        this.match = undefined;
        this.showMoreCustomer = false;
        this.selectedVehicleId = null;
        this.newVehicle = { ...EMPTY_VEHICLE };
        const row = newRow();
        this.items = [row];
        this.includeGst = false;
        this.closeSuggestions();
        // Walk-in goes straight to the items; Customer starts at the phone box.
        this._pendingFocus = this.isWalkIn ? { key: row.key, field: 'description' } : undefined;
        this.billDate = todayIso();
        this.notes = '';
        this.showMoreOptions = false;
        this.createdBill = undefined;
        this.showPreview = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
