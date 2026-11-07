import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';
import getDay from '@salesforce/apex/ServiceBookController.getDay';
import search from '@salesforce/apex/ServiceBookController.search';
import { disablePullToRefresh } from 'c/disablePullToRefresh';

const SEARCH_DELAY_MS = 300;
const SHOWN_VISITS = 3;

let nextCardKey = 1;

function toIso(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function fromIso(iso) {
    const [year, month, day] = iso.split('-').map(Number);
    return new Date(year, month - 1, day);
}

function formatShort(iso) {
    return fromIso(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

// What was typed in the search box, put in the right box of a new card.
function draftFromSearch(term) {
    const text = (term || '').trim();
    if (!text) {
        return {};
    }
    if (/^[+\d\s-]{6,}$/.test(text)) {
        return { phone: text };
    }
    if (/\d/.test(text)) {
        return { registrationNumber: text.toUpperCase() };
    }
    return { customerName: text };
}

/**
 * The workshop's daily service book: a page per date with a card for each car
 * worked on, and one search box across every car and customer. Built to be run
 * from the keyboard: the cursor starts in the search box; Enter opens a result
 * (or a new card, if nothing matched) with the cursor ready to write; Esc goes
 * back to the search box.
 */
export default class ServiceBook extends LightningElement {
    selectedDate = toIso(new Date());
    cards = [];
    isLoading = true;

    searchTerm = '';
    results = [];
    hasSearched = false;
    highlightIndex = -1;

    _searchTimer;
    _searchSeq = 0;
    _daySeq = 0;
    _focusTimers = [];
    _focusCardKey;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadDay();
        // Not on a phone, where it would pop the keyboard over the page.
        // Lightning takes focus back while its page settles, hence the retries.
        if (FORM_FACTOR === 'Large') {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._focusTimers = [0, 800, 2000, 4000].map((delay) => setTimeout(() => this.focusSearchIfNowhereElse(), delay));
        }
    }

    disconnectedCallback() {
        clearTimeout(this._searchTimer);
        this._focusTimers.forEach((timer) => clearTimeout(timer));
    }

    renderedCallback() {
        if (this._focusCardKey) {
            const card = this.template.querySelector(`c-service-card[data-key="${this._focusCardKey.key}"]`);
            if (card) {
                const { isNew } = this._focusCardKey;
                this._focusCardKey = undefined;
                if (isNew) {
                    card.focusFirstBox();
                } else {
                    card.focusWork();
                }
            }
        }
    }

    focusSearchIfNowhereElse() {
        if (!this.template.activeElement) {
            this.focusSearch();
        }
    }

    focusSearch() {
        const box = this.template.querySelector('[data-id="search"]');
        if (box) {
            box.focus();
        }
    }

    // ---- the page -------------------------------------------------------

    get today() {
        return toIso(new Date());
    }

    get isToday() {
        return this.selectedDate === this.today;
    }

    get isNotToday() {
        return !this.isToday;
    }

    get dateHeading() {
        return fromIso(this.selectedDate).toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
    }

    get writeButtonLabel() {
        return this.isToday ? 'Write for today' : `Write for ${formatShort(this.selectedDate)}`;
    }

    get showEmptyDay() {
        return !this.isLoading && this.cards.length === 0;
    }

    loadDay() {
        const seq = ++this._daySeq;
        this.isLoading = true;
        return getDay({ entryDate: this.selectedDate })
            .then((cards) => {
                if (seq === this._daySeq) {
                    this.cards = (cards || []).map((card) => ({ ...card, key: `car-${card.vehicleId}` }));
                }
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                if (seq === this._daySeq) {
                    this.isLoading = false;
                }
            });
    }

    goToDate(iso) {
        if (!iso || iso === this.selectedDate) {
            return;
        }
        // No book pages from the future.
        this.selectedDate = iso > this.today ? this.today : iso;
        this.clearSearch();
        // Empties the page first, so each card saves anything unsaved as it goes.
        this.cards = [];
        this.loadDay();
        // Ready to search on the new page, without tabbing back. Not on a phone,
        // where it would pop the keyboard over the page.
        if (FORM_FACTOR === 'Large') {
            this.focusSearch();
        }
    }

    shiftDate(days) {
        const date = fromIso(this.selectedDate);
        date.setDate(date.getDate() + days);
        this.goToDate(toIso(date));
    }

    handlePreviousDay() {
        this.shiftDate(-1);
    }

    handleNextDay() {
        this.shiftDate(1);
    }

    handleToday() {
        this.goToDate(this.today);
    }

    handleDateChange(event) {
        this.goToDate(event.target.value);
    }

    handleOpenDate(event) {
        this.goToDate(event.detail.date);
    }

    handleCardDone() {
        this.focusSearch();
    }

    // Noted on the parent's copy only, so a car opened from search again finds
    // this card. The card itself ignores updates after it's created.
    handleCarKnown(event) {
        const key = event.currentTarget.dataset.key;
        this.cards = this.cards.map((card) => (card.key === key ? { ...card, vehicleId: event.detail.vehicleId } : card));
    }

    // ---- search ---------------------------------------------------------

    get isSearching() {
        return this.searchTerm.trim().length >= 2;
    }

    get dayClass() {
        return this.isSearching ? 'sb-day sb-hidden' : 'sb-day';
    }

    get decoratedResults() {
        return this.results.map((result, index) => {
            const visits = result.visits || [];
            return {
                ...result,
                index,
                key: result.vehicleId || result.customerId,
                rowClass: index === this.highlightIndex ? 'sb-result sb-result_active' : 'sb-result',
                hasNoCar: !result.vehicleId,
                shownVisits: visits.slice(0, SHOWN_VISITS).map((visit) => ({ ...visit, dateLabel: formatShort(visit.entryDate) })),
                moreVisitsLabel: visits.length > SHOWN_VISITS ? `and ${visits.length - SHOWN_VISITS} older` : '',
                hasNoVisits: !!result.vehicleId && visits.length === 0 && !result.workDone
            };
        });
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get showNoResults() {
        return this.isSearching && this.hasSearched && !this.hasResults;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
        this.highlightIndex = -1;
        clearTimeout(this._searchTimer);
        const term = this.searchTerm.trim();
        this._searchSeq++;
        if (term.length < 2) {
            this.results = [];
            this.hasSearched = false;
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = setTimeout(() => this.runSearch(term), SEARCH_DELAY_MS);
    }

    runSearch(term) {
        const seq = ++this._searchSeq;
        return search({ term, entryDate: this.selectedDate })
            .then((results) => {
                if (seq === this._searchSeq) {
                    this.results = results || [];
                    this.hasSearched = true;
                }
            })
            .catch((error) => this.showError(error));
    }

    handleSearchKeydown(event) {
        const count = this.results.length;
        if (event.key === 'ArrowDown' && count) {
            event.preventDefault();
            this.highlightIndex = (this.highlightIndex + 1) % count;
        } else if (event.key === 'ArrowUp' && count) {
            event.preventDefault();
            this.highlightIndex = this.highlightIndex <= 0 ? count - 1 : this.highlightIndex - 1;
        } else if (event.key === 'Escape') {
            this.clearSearch();
        } else if (event.key === 'Enter') {
            event.preventDefault();
            this.handleSearchEnter();
        }
    }

    handleSearchEnter() {
        if (this.highlightIndex >= 0) {
            this.openResult(this.results[this.highlightIndex]);
        } else if (this.results.length === 1) {
            this.openResult(this.results[0]);
        } else if (this.results.length > 1) {
            this.highlightIndex = 0;
        } else if (this.showNoResults) {
            this.handleNewCar();
        }
    }

    handleResultClick(event) {
        this.openResult(this.results[Number(event.currentTarget.dataset.index)]);
    }

    clearSearch() {
        clearTimeout(this._searchTimer);
        this._searchSeq++;
        this.searchTerm = '';
        this.results = [];
        this.hasSearched = false;
        this.highlightIndex = -1;
    }

    // Nothing is saved yet: looking a car up mustn't put a card in the book.
    // The card makes its entry when something is written on it.
    openResult(result) {
        if (!result.vehicleId) {
            this.addNewCard({ customerId: result.customerId, customerName: result.customerName, phone: result.phone || '' }, false);
            return;
        }
        const existing = this.cards.find((card) => card.vehicleId === result.vehicleId);
        const key = existing ? existing.key : `car-${result.vehicleId}`;
        if (!existing) {
            this.cards = [{ ...result, key, openVisits: true }, ...this.cards];
        }
        this.clearSearch();
        this._focusCardKey = { key, isNew: false };
    }

    handleNewCar() {
        this.addNewCard(draftFromSearch(this.searchTerm), true);
    }

    addNewCard(draft, startAtTop) {
        const key = `new-${nextCardKey++}`;
        this.cards = [{ key, visits: [], draft }, ...this.cards];
        this.clearSearch();
        this._focusCardKey = { key, isNew: startAtTop };
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }
}
