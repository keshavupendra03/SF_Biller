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

const GST_RATE_OPTIONS = [0, 5, 12, 18, 28].map((rate) => ({ label: `${rate}%`, value: String(rate) }));

const EMPTY_CUSTOMER = { name: '', phone: '', address: '', gstin: '', state: '' };
const EMPTY_VEHICLE = { registrationNumber: '', make: '', model: '' };
const NEW_VEHICLE = '__new';
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

/**
 * Quick Bill — one screen to bill a counter sale of spare parts, or any
 * car customer, without setting up the customer/vehicle first.
 * QuickBillController resolves the customer (shared Walk-in Customer, or
 * matched/created by phone) and the vehicle, then creates the bill
 * through BillController.createBill like every other bill.
 */
export default class QuickBill extends NavigationMixin(LightningElement) {
    modeOptions = MODE_OPTIONS;
    gstRateOptions = GST_RATE_OPTIONS;

    mode = 'customer';
    customer = { ...EMPTY_CUSTOMER };
    showMoreCustomer = false;
    match;
    isLookingUp = false;

    selectedVehicleId = null;
    newVehicle = { ...EMPTY_VEHICLE };

    items = [];
    partSearchTerm = '';
    partResults = [];
    isSearchingParts = false;
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

    connectedCallback() {
        disablePullToRefresh(this);
        try {
            this.canScan = getBarcodeScanner().isAvailable();
        } catch (e) {
            this.canScan = false;
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

    get hasItems() {
        return this.items.length > 0;
    }

    get showEmptyItems() {
        return !this.hasItems;
    }

    get itemCount() {
        return this.items.reduce((sum, item) => sum + (Number(item.quantity) || 0), 0);
    }

    get itemCountLabel() {
        const count = this.itemCount;
        return `${count} ${count === 1 ? 'item' : 'items'}`;
    }

    get decoratedItems() {
        return this.items.map((item) => {
            const lineTotal = calculateLine(item).total;
            const stock = item.currentStock;
            const hasStock = item.partId && stock !== null && stock !== undefined;
            return {
                ...item,
                taxRateValue: String(item.taxRatePercent ?? 0),
                formattedLineTotal: formatAmount(lineTotal),
                isCustom: !item.partId,
                stockLabel: hasStock ? `${stock} in stock` : '',
                isShort: hasStock && Number(item.quantity) > Number(stock),
                decreaseDisabled: Number(item.quantity) <= 1
            };
        });
    }

    get hasPartResults() {
        return this.partResults.length > 0;
    }

    get decoratedPartResults() {
        return this.partResults.map((part) => ({
            ...part,
            formattedPrice: formatAmount(part.price),
            stockLabel: part.currentStock === null || part.currentStock === undefined ? '' : `${part.currentStock} in stock`,
            stockClass: Number(part.currentStock) > 0 ? 'slds-badge slds-theme_success' : 'slds-badge slds-theme_error',
            meta: [part.sku, part.hsnCode ? `HSN ${part.hsnCode}` : null].filter((p) => p).join(' · ')
        }));
    }

    get showNoPartResults() {
        return this.partSearchTerm.length >= 2 && !this.isSearchingParts && !this.hasPartResults;
    }

    handlePartSearchChange(event) {
        this.partSearchTerm = event.target.value || '';
        clearTimeout(this._searchTimer);
        if (this.partSearchTerm.length < 2) {
            this.partResults = [];
            return;
        }
        const term = this.partSearchTerm;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = setTimeout(() => this.runPartSearch(term), SEARCH_DELAY_MS);
    }

    runPartSearch(term) {
        this.isSearchingParts = true;
        const seq = ++this._searchSeq;
        return searchParts({ searchTerm: term })
            .then((results) => {
                if (seq === this._searchSeq) {
                    this.partResults = results || [];
                }
                return results || [];
            })
            .catch((error) => {
                this.showError(error);
                return [];
            })
            .finally(() => {
                if (seq === this._searchSeq) {
                    this.isSearchingParts = false;
                }
            });
    }

    handleSelectPart(event) {
        const part = this.partResults.find((p) => p.id === event.currentTarget.dataset.id);
        if (part) {
            this.addPart(part);
        }
    }

    // Tapping a part that's already on the bill adds one more of it.
    addPart(part) {
        const existing = this.items.find((item) => item.partId === part.id);
        if (existing) {
            this.items = this.items.map((item) =>
                item.key === existing.key ? { ...item, quantity: (Number(item.quantity) || 0) + 1 } : item
            );
        } else {
            this.items = [
                ...this.items,
                {
                    key: `item-${nextItemKey++}`,
                    partId: part.id,
                    description: part.name,
                    sku: part.sku,
                    quantity: 1,
                    unitPrice: part.price || 0,
                    taxRatePercent: part.taxRatePercent || 0,
                    gstType: part.gstType || 'CGST_SGST',
                    hsnSacCode: part.hsnCode || '',
                    unitLabel: part.unitLabel || '',
                    currentStock: part.currentStock
                }
            ];
        }
        this.partSearchTerm = '';
        this.partResults = [];
    }

    handleAddCustomItem() {
        this.items = [
            ...this.items,
            {
                key: `item-${nextItemKey++}`,
                partId: null,
                description: '',
                quantity: 1,
                unitPrice: null,
                taxRatePercent: 18,
                gstType: 'CGST_SGST',
                hsnSacCode: '',
                unitLabel: ''
            }
        ];
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
                    const exact = results.find((p) => p.barcode === code || p.sku === code);
                    const part = exact || (results.length === 1 ? results[0] : null);
                    if (part) {
                        this.addPart(part);
                        this.showToast(`Added ${part.name}`, '', 'success');
                    } else if (results.length) {
                        this.partSearchTerm = code;
                    } else {
                        this.showToast('No part found', `Nothing in inventory matches barcode ${code}.`, 'warning');
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

    updateItem(key, changes) {
        this.items = this.items.map((item) => (item.key === key ? { ...item, ...changes } : item));
    }

    handleItemFieldChange(event) {
        const { key, field } = event.target.dataset;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.updateItem(key, { [field]: field === 'description' ? value : value === '' ? null : Number(value) });
    }

    handleIncrease(event) {
        const item = this.items.find((i) => i.key === event.currentTarget.dataset.key);
        this.updateItem(item.key, { quantity: (Number(item.quantity) || 0) + 1 });
    }

    handleDecrease(event) {
        const item = this.items.find((i) => i.key === event.currentTarget.dataset.key);
        this.updateItem(item.key, { quantity: Math.max(1, (Number(item.quantity) || 0) - 1) });
    }

    handleRemoveItem(event) {
        const key = event.currentTarget.dataset.key;
        this.items = this.items.filter((item) => item.key !== key);
    }

    handleEditItem(event) {
        this.editingItem = this.items.find((item) => item.key === event.currentTarget.dataset.key);
    }

    handleItemEditorSave(event) {
        this.updateItem(this.editingItem.key, { ...event.detail, key: this.editingItem.key });
        this.editingItem = undefined;
    }

    handleItemEditorCancel() {
        this.editingItem = undefined;
    }

    // ---- totals ---------------------------------------------------------

    get totals() {
        return calculateBillTotals(this.items);
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
        if (this.items.some((item) => !(item.description || '').trim())) {
            return 'Give every custom item a name.';
        }
        if (this.items.some((item) => item.unitPrice === null || item.unitPrice === undefined || Number(item.unitPrice) < 0)) {
            return 'Enter a price for every item.';
        }
        if (this.items.some((item) => !(Number(item.quantity) > 0))) {
            return 'Every item needs a quantity of at least 1.';
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
            lineItems: this.items.map((item) => ({
                partId: item.partId,
                description: item.description.trim(),
                quantity: Number(item.quantity),
                unitPrice: Number(item.unitPrice),
                taxRatePercent: Number(item.taxRatePercent) || 0,
                gstType: item.gstType || 'CGST_SGST',
                hsnSacCode: item.hsnSacCode,
                unitLabel: item.unitLabel
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
        this.items = [];
        this.partSearchTerm = '';
        this.partResults = [];
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
