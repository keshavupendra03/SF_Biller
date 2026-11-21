import { createElement } from 'lwc';
import BillToPartyPicker from 'c/billToPartyPicker';
import listBillToParties from '@salesforce/apex/DirectoryController.listBillToParties';

jest.mock('@salesforce/apex/DirectoryController.listBillToParties', () => ({ default: jest.fn() }), { virtual: true });

const ICICI = { id: 'p1', name: 'ICICI Lombard', gstin: '23AAACI7904G1ZV', contactPhone: '', address: 'MG Road, Indore', state: 'Madhya Pradesh' };
const SHARMA = { id: 'p2', name: 'Sharma Transport', gstin: '', contactPhone: '9827012345', address: '', state: '' };

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function createPicker() {
    const element = createElement('c-bill-to-party-picker', { is: BillToPartyPicker });
    const changes = [];
    element.addEventListener('partychange', (event) => changes.push(event.detail));
    document.body.appendChild(element);
    await flushPromises();
    return { element, changes };
}

function $(element, selector) {
    return element.shadowRoot.querySelector(selector);
}

function box(element) {
    return $(element, '[data-id="party-search"]');
}

function options(element) {
    return [...element.shadowRoot.querySelectorAll('[data-id="party-option"]')];
}

function isOpen(element) {
    return $(element, '.slds-combobox').classList.contains('slds-is-open');
}

function press(element, key, extra) {
    box(element).dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true, ...extra }));
}

async function focusBox(element) {
    box(element).dispatchEvent(new CustomEvent('focus'));
    await flushPromises();
}

async function typeName(element, value) {
    box(element).value = value;
    box(element).dispatchEvent(new CustomEvent('input'));
    await wait(300);
    await flushPromises();
}

describe('c-bill-to-party-picker', () => {
    beforeEach(() => {
        listBillToParties.mockResolvedValue([ICICI, SHARMA]);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('lists the saved parties as soon as the box is entered, without typing', async () => {
        const { element } = await createPicker();
        expect(isOpen(element)).toBe(false);

        await focusBox(element);

        expect(listBillToParties).toHaveBeenCalledWith({ searchTerm: '' });
        expect(isOpen(element)).toBe(true);
        expect(options(element).map((o) => o.textContent)).toEqual([
            expect.stringContaining('ICICI Lombard'),
            expect.stringContaining('Sharma Transport')
        ]);
        expect(options(element)[0].textContent).toContain('23AAACI7904G1ZV');
    });

    it('shows at most eight saved parties', async () => {
        listBillToParties.mockResolvedValue(Array.from({ length: 12 }, (_, i) => ({ id: `p${i}`, name: `Party ${i}` })));
        const { element } = await createPicker();
        await focusBox(element);

        expect(options(element)).toHaveLength(8);
    });

    it('arrow down and Enter pick a party, and report its Id', async () => {
        const { element, changes } = await createPicker();
        await focusBox(element);

        press(element, 'ArrowDown');
        press(element, 'ArrowDown');
        await flushPromises();
        expect(options(element)[1].getAttribute('aria-selected')).toBe('true');
        press(element, 'Enter');
        await flushPromises();

        expect($(element, '[data-id="party-selected-name"]').textContent).toBe('Sharma Transport');
        expect(changes[changes.length - 1]).toEqual({ billToPartyId: 'p2', billToParty: null, name: 'Sharma Transport' });
        expect(box(element)).toBeNull();
    });

    it('a tapped party is picked, with its details shown', async () => {
        const { element, changes } = await createPicker();
        await focusBox(element);

        options(element)[0].dispatchEvent(new CustomEvent('mousedown', { cancelable: true }));
        await flushPromises();

        expect($(element, '[data-id="party-selected"]').textContent).toContain('GSTIN 23AAACI7904G1ZV');
        expect($(element, '[data-id="party-selected"]').textContent).toContain('MG Road, Indore');
        expect(changes[changes.length - 1].billToPartyId).toBe('p1');
    });

    it('typing searches, and a name not picked is a new party with optional details', async () => {
        listBillToParties.mockResolvedValue([]);
        const { element, changes } = await createPicker();

        await typeName(element, 'Verma Fleet');

        expect(listBillToParties).toHaveBeenLastCalledWith({ searchTerm: 'Verma Fleet' });
        expect($(element, '[data-id="new-party-note"]').textContent).toContain('saved for next time');
        expect(changes[changes.length - 1]).toEqual({
            billToPartyId: null,
            billToParty: { name: 'Verma Fleet', address: '', contactPhone: '', gstin: '', state: '' },
            name: 'Verma Fleet'
        });

        const gstin = $(element, 'lightning-input[data-field="gstin"]');
        gstin.value = '23ABCDE1234F1Z5';
        gstin.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(changes[changes.length - 1].billToParty.gstin).toBe('23ABCDE1234F1Z5');
    });

    it('a saved name typed in full is that party once the cursor leaves', async () => {
        const { element, changes } = await createPicker();
        await typeName(element, 'icici lombard');

        box(element).dispatchEvent(new CustomEvent('blur'));
        await flushPromises();

        expect($(element, '[data-id="party-selected-name"]').textContent).toBe('ICICI Lombard');
        expect(changes[changes.length - 1].billToPartyId).toBe('p1');
    });

    it('Change goes back to an empty box, and reports no party', async () => {
        const { element, changes } = await createPicker();
        await focusBox(element);
        options(element)[0].dispatchEvent(new CustomEvent('mousedown', { cancelable: true }));
        await flushPromises();

        $(element, '[data-id="party-change"]').click();
        await flushPromises();

        expect(box(element).value).toBe('');
        expect(changes[changes.length - 1]).toEqual({ billToPartyId: null, billToParty: null, name: '' });
    });

    it('Escape closes the list and keeps what was typed', async () => {
        const { element } = await createPicker();
        await typeName(element, 'Sha');
        expect(isOpen(element)).toBe(true);

        press(element, 'Escape');
        await flushPromises();

        expect(isOpen(element)).toBe(false);
        expect(box(element).value).toBe('Sha');
    });

    it('a new party\'s GSTIN fills in its state, picked from a list', async () => {
        listBillToParties.mockResolvedValue([]);
        const { element, changes } = await createPicker();
        await typeName(element, 'Verma Fleet');

        expect($(element, '[data-field="state"]').tagName).toBe('LIGHTNING-COMBOBOX');
        const gstin = $(element, 'lightning-input[data-field="gstin"]');
        gstin.value = '27AAPFU0939F1ZV';
        gstin.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(changes[changes.length - 1].billToParty).toEqual(expect.objectContaining({ gstin: '27AAPFU0939F1ZV', state: 'Maharashtra' }));
        expect($(element, '[data-field="state"]').value).toBe('Maharashtra');
    });
});
