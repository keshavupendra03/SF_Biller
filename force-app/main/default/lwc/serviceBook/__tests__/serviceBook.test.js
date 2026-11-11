import { createElement } from 'lwc';
import ServiceBook from 'c/serviceBook';
import getDay from '@salesforce/apex/ServiceBookController.getDay';
import search from '@salesforce/apex/ServiceBookController.search';
import saveWork from '@salesforce/apex/ServiceBookController.saveWork';
import saveCardDetails from '@salesforce/apex/ServiceBookController.saveCardDetails';
import changeVisit from '@salesforce/apex/ServiceBookController.changeVisit';
import getVehicleCard from '@salesforce/apex/ServiceBookController.getVehicleCard';
import searchCarModels from '@salesforce/apex/ServiceBookController.searchCarModels';
import searchCustomers from '@salesforce/apex/BillController.searchCustomers';
import getCustomer from '@salesforce/apex/PaperBillController.getCustomer';
import findCustomerByPhone from '@salesforce/apex/QuickBillController.findCustomerByPhone';

jest.mock('@salesforce/apex/ServiceBookController.getDay', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ServiceBookController.search', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ServiceBookController.saveWork', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ServiceBookController.saveCardDetails', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ServiceBookController.changeVisit', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ServiceBookController.getVehicleCard', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ServiceBookController.searchCarModels', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BillController.searchCustomers', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PaperBillController.getCustomer', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/QuickBillController.findCustomerByPhone', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/client/formFactor', () => ({ default: 'Large' }), { virtual: true });

const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](pageRef) {
                mockNavigate(pageRef);
            }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
});

const CAR = {
    vehicleId: 'veh1', customerId: 'cust1', customerName: 'Ramesh Kumar', phone: '9000011111',
    carModel: 'Maruti Swift', registrationNumber: 'MP09AB1234', workDone: 'Oil changed\nWashed', hasEntryForDate: true,
    // Same visit, an earlier day.
    visitStart: '2026-10-20',
    visitDays: [{ entryDate: '2026-10-20', workDone: 'Brake pads replaced' }],
    otherVisits: [{ startDate: '2026-09-01', endDate: '2026-09-02', days: [
        { entryDate: '2026-09-01', workDone: 'Clutch plate' },
        { entryDate: '2026-09-02', workDone: 'Clutch bearing' }
    ] }]
};
const NOT_TODAY = { ...CAR, workDone: null, hasEntryForDate: false };

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function todayIso() {
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

async function createScreen() {
    const element = createElement('c-service-book', { is: ServiceBook });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

function $(element, selector) {
    return element.shadowRoot.querySelector(selector);
}

function cards(element) {
    return [...element.shadowRoot.querySelectorAll('c-service-card')];
}

function inCard(card, selector) {
    return card.shadowRoot.querySelector(selector);
}

async function typeSearch(element, value) {
    const box = $(element, '[data-id="search"]');
    box.value = value;
    box.dispatchEvent(new CustomEvent('change'));
    await wait(350);
    await flushPromises();
}

function press(element, key) {
    $(element, '[data-id="search"]').dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, composed: true, cancelable: true }));
}

async function typeWork(card, value) {
    const box = inCard(card, '[data-id="work"]');
    box.value = value;
    box.dispatchEvent(new CustomEvent('input', { bubbles: true }));
    await flushPromises();
}

async function typeField(card, selector, value) {
    const box = inCard(card, `c-paper-field${selector}`).shadowRoot.querySelector('input');
    box.value = value;
    box.dispatchEvent(new CustomEvent('input', { bubbles: true }));
    await flushPromises();
}

describe('c-service-book', () => {
    beforeEach(() => {
        getDay.mockResolvedValue([]);
        search.mockResolvedValue([]);
        saveWork.mockResolvedValue(CAR);
        searchCustomers.mockResolvedValue([]);
        searchCarModels.mockResolvedValue([]);
        findCustomerByPhone.mockResolvedValue(null);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('opens on today with the cursor in the search box', async () => {
        const element = await createScreen();

        expect(getDay).toHaveBeenCalledWith({ entryDate: todayIso() });
        expect($(element, '[data-id="today-tag"]')).not.toBeNull();
        expect($(element, '[data-id="next-day"]').disabled).toBe(true);
        expect($(element, '[data-id="empty-day"]')).not.toBeNull();

        // Lightning takes focus back as its page settles, so it asks again.
        const search = $(element, '[data-id="search"]');
        search.focus = jest.fn();
        await wait(850);
        expect(search.focus).toHaveBeenCalled();
    });

    it('shows a card for each car on the day, with every detail', async () => {
        getDay.mockResolvedValue([CAR]);
        const element = await createScreen();

        const card = cards(element)[0];
        expect(inCard(card, '[data-id="card-number"]').textContent).toBe('MP09AB1234');
        expect(inCard(card, '[data-id="card-model"]').textContent).toBe('Maruti Swift');
        expect(inCard(card, '[data-id="card-name"]').textContent).toBe('Ramesh Kumar');
        expect(inCard(card, '[data-id="card-phone"]').textContent).toBe('9000011111');
        expect(inCard(card, '[data-id="work"]').value).toBe('Oil changed\nWashed');
        expect($(element, '[data-id="empty-day"]')).toBeNull();
    });

    it('previous day, the calendar and Go to today change the page', async () => {
        const element = await createScreen();
        const today = todayIso();

        $(element, '[data-id="previous-day"]').click();
        await flushPromises();
        const yesterday = getDay.mock.calls[getDay.mock.calls.length - 1][0].entryDate;
        expect(yesterday < today).toBe(true);
        expect($(element, '[data-id="today-tag"]')).toBeNull();
        expect($(element, '[data-id="next-day"]').disabled).toBe(false);

        const picker = $(element, '[data-id="date-picker"]');
        picker.value = '2026-10-20';
        picker.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        expect(getDay).toHaveBeenLastCalledWith({ entryDate: '2026-10-20' });
        expect($(element, '[data-id="date-heading"]').textContent).toContain('20 October 2026');

        $(element, '[data-id="go-today"]').click();
        await flushPromises();
        expect(getDay).toHaveBeenLastCalledWith({ entryDate: today });
    });

    it('changing the date puts the cursor back in the search box', async () => {
        const element = await createScreen();
        const box = $(element, '[data-id="search"]');
        box.focus = jest.fn();

        $(element, '[data-id="previous-day"]').click();
        await flushPromises();

        expect(box.focus).toHaveBeenCalled();
    });

    it('does not open a page from the future', async () => {
        const element = await createScreen();

        const picker = $(element, '[data-id="date-picker"]');
        picker.value = '2099-01-01';
        picker.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect($(element, '[data-id="today-tag"]')).not.toBeNull();
    });

    it('search shows the car and what was done before, while the page stays underneath', async () => {
        getDay.mockResolvedValue([{ ...CAR, vehicleId: 'veh9', key: 'x' }]);
        search.mockResolvedValue([NOT_TODAY]);
        const element = await createScreen();

        await typeSearch(element, 'swift');

        expect(search).toHaveBeenCalledWith({ term: 'swift', entryDate: todayIso() });
        const result = $(element, '[data-id="result"]');
        expect(result.textContent).toContain('MP09AB1234');
        expect(result.textContent).toContain('Ramesh Kumar');
        expect(result.textContent).toContain('Brake pads replaced');
        expect($(element, '[data-id="day"]').className).toContain('sb-hidden');
        expect(cards(element)).toHaveLength(1);
    });

    it('a single result opens with Enter, cursor in Work Done, with nothing saved until something is typed', async () => {
        search.mockResolvedValue([NOT_TODAY]);
        const element = await createScreen();
        await typeSearch(element, 'MP09AB');

        press(element, 'Enter');
        await flushPromises();

        const card = cards(element)[0];
        expect(inCard(card, '[data-id="card-number"]').textContent).toBe('MP09AB1234');
        expect(card.shadowRoot.activeElement).toBe(inCard(card, '[data-id="work"]'));
        expect(inCard(card, '[data-id="earlier-days"]').textContent).toContain('Brake pads replaced');
        expect($(element, '[data-id="search"]').value).toBe('');

        await wait(900);
        expect(saveWork).not.toHaveBeenCalled();

        await typeWork(card, 'Clutch adjusted');
        await wait(900);
        await flushPromises();
        expect(saveWork).toHaveBeenCalledWith({
            request: { entryDate: todayIso(), workDone: 'Clutch adjusted', startNewVisit: false, vehicleId: 'veh1' }
        });
    });

    it('with several results, arrows choose and Enter opens', async () => {
        const second = { ...NOT_TODAY, vehicleId: 'veh2', registrationNumber: 'MP09CD5678' };
        search.mockResolvedValue([NOT_TODAY, second]);
        const element = await createScreen();
        await typeSearch(element, 'ramesh');

        press(element, 'ArrowDown');
        press(element, 'ArrowDown');
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('[data-id="result"]')[1].className).toContain('sb-result_active');

        press(element, 'Enter');
        await flushPromises();
        expect(inCard(cards(element)[0], '[data-id="card-number"]').textContent).toBe('MP09CD5678');
    });

    it('opening a car already on the page goes to its card rather than adding a second', async () => {
        getDay.mockResolvedValue([CAR]);
        search.mockResolvedValue([CAR]);
        const element = await createScreen();
        await typeSearch(element, 'swift');

        press(element, 'Enter');
        await flushPromises();

        expect(cards(element)).toHaveLength(1);
        expect(cards(element)[0].shadowRoot.activeElement).toBe(inCard(cards(element)[0], '[data-id="work"]'));
    });

    it('Esc in the search box clears it', async () => {
        search.mockResolvedValue([NOT_TODAY]);
        const element = await createScreen();
        await typeSearch(element, 'swift');

        press(element, 'Escape');
        await flushPromises();

        expect($(element, '[data-id="result"]')).toBeNull();
        expect($(element, '[data-id="day"]').className).not.toContain('sb-hidden');
    });

    it('nothing found: Enter starts a new card with what was typed already in the right box', async () => {
        const element = await createScreen();
        await typeSearch(element, 'mp09zz0001');
        expect($(element, '[data-id="no-results"]')).not.toBeNull();

        press(element, 'Enter');
        await flushPromises();
        expect(inCard(cards(element)[0], 'c-paper-field[data-field="registrationNumber"]').value).toBe('MP09ZZ0001');
    });

    it('a typed mobile number or name also goes in the right box', async () => {
        const element = await createScreen();
        await typeSearch(element, '98260 11111');
        press(element, 'Enter');
        await flushPromises();
        expect(inCard(cards(element)[0], 'c-paper-field[data-field="phone"]').value).toBe('98260 11111');

        await typeSearch(element, 'Suresh Patel');
        press(element, 'Enter');
        await flushPromises();
        expect(inCard(cards(element)[0], 'c-paper-field[data-field="customerName"]').value).toBe('Suresh Patel');
    });

    it('a customer with no car on file opens as a new card with their details', async () => {
        search.mockResolvedValue([{ customerId: 'cust2', customerName: 'Suresh Patel', phone: '9826011111', visits: [] }]);
        const element = await createScreen();
        await typeSearch(element, 'suresh');
        expect($(element, '[data-id="result"]').textContent).toContain('No car on file yet');

        press(element, 'Enter');
        await flushPromises();

        const card = cards(element)[0];
        expect(inCard(card, 'c-paper-field[data-field="customerName"]').value).toBe('Suresh Patel');
        expect(inCard(card, 'c-paper-field[data-field="phone"]').value).toBe('9826011111');
        await typeField(card, '[data-field="registrationNumber"]', 'MP09ZZ0001');
        await typeWork(card, 'Washed');
        await wait(900);
        await flushPromises();
        expect(saveWork.mock.calls[0][0].request).toEqual(expect.objectContaining({ customerId: 'cust2', registrationNumber: 'MP09ZZ0001' }));
    });

    it('New Car: the car number comes first, and is all it needs to save', async () => {
        const created = { vehicleId: 'veh7', registrationNumber: 'MP09ZZ0001', carModel: '', workDone: 'Washed', visits: [] };
        saveWork.mockResolvedValue(created);
        const element = await createScreen();

        $(element, '[data-id="new-car"]').click();
        await flushPromises();
        const card = cards(element)[0];
        expect(inCard(card, 'c-paper-field').dataset.field).toBe('registrationNumber');
        expect(inCard(card, '[data-id="make-bill"]').disabled).toBe(true);

        await typeWork(card, 'Washed');
        expect(inCard(card, '[data-id="missing-details"]').textContent).toContain('car number');
        await wait(900);
        expect(saveWork).not.toHaveBeenCalled();

        await typeField(card, '[data-field="registrationNumber"]', 'MP09ZZ0001');
        expect(inCard(card, '[data-id="missing-details"]')).toBeNull();
        await typeWork(card, 'Washed');
        await wait(900);
        await flushPromises();

        expect(saveWork.mock.calls[0][0].request).toEqual(expect.objectContaining({
            registrationNumber: 'MP09ZZ0001', customerName: '', phone: '', workDone: 'Washed'
        }));
        expect(inCard(card, '[data-id="card-number"]').textContent).toBe('MP09ZZ0001');
        expect(inCard(card, '[data-id="save-state"]').textContent).toBe('Saved');
    });

    describe('a card with no customer yet', () => {
        const NO_CUSTOMER = { vehicleId: 'veh7', registrationNumber: 'MP09ZZ0001', carModel: '', workDone: 'Washed', visits: [] };
        const WITH_NAME = { ...NO_CUSTOMER, customerId: 'cust9', customerName: 'Suresh Patel' };

        async function openCard() {
            getDay.mockResolvedValue([NO_CUSTOMER]);
            const element = await createScreen();
            return cards(element)[0];
        }

        function blurField(card, selector) {
            inCard(card, `c-paper-field${selector}`).shadowRoot.querySelector('input').dispatchEvent(new CustomEvent('blur'));
        }

        it('has Bill and Estimate off, says why, and keeps the boxes for what is missing', async () => {
            const card = await openCard();

            expect(inCard(card, '[data-id="make-bill"]').disabled).toBe(true);
            expect(inCard(card, '[data-id="make-estimate"]').disabled).toBe(true);
            expect(inCard(card, '[data-id="no-customer-hint"]').textContent).toContain('customer name or mobile');
            expect(inCard(card, 'c-paper-field[data-field="customerName"]')).not.toBeNull();
            expect(inCard(card, 'c-paper-field[data-field="phone"]')).not.toBeNull();
            expect(inCard(card, 'c-paper-field[data-field="carModel"]')).not.toBeNull();
            expect(inCard(card, 'c-paper-field[data-field="registrationNumber"]')).toBeNull();
        });

        it('adding a name turns on Bill and Estimate, and the name replaces its box', async () => {
            saveCardDetails.mockResolvedValue(WITH_NAME);
            const card = await openCard();

            await typeField(card, '[data-field="customerName"]', 'Suresh Patel');
            blurField(card, '[data-field="customerName"]');
            await wait(200);
            await flushPromises();

            expect(saveCardDetails.mock.calls[0][0].request).toEqual(expect.objectContaining({
                vehicleId: 'veh7', entryDate: todayIso(), customerName: 'Suresh Patel'
            }));
            expect(inCard(card, '[data-id="card-name"]').textContent).toBe('Suresh Patel');
            expect(inCard(card, 'c-paper-field[data-field="customerName"]')).toBeNull();
            expect(inCard(card, 'c-paper-field[data-field="phone"]')).not.toBeNull();
            expect(inCard(card, '[data-id="make-bill"]').disabled).toBe(false);
            expect(inCard(card, '[data-id="no-customer-hint"]')).toBeNull();
        });

        it('does not save half a customer while moving from name to mobile', async () => {
            saveCardDetails.mockResolvedValue(WITH_NAME);
            const card = await openCard();

            await typeField(card, '[data-field="customerName"]', 'Suresh Patel');
            const mobile = inCard(card, 'c-paper-field[data-field="phone"]');
            mobile.shadowRoot.querySelector('input').focus();
            blurField(card, '[data-field="customerName"]');
            await wait(200);
            expect(saveCardDetails).not.toHaveBeenCalled();

            await typeField(card, '[data-field="phone"]', '9826011111');
            mobile.shadowRoot.querySelector('input').blur();
            blurField(card, '[data-field="phone"]');
            await wait(200);
            await flushPromises();

            expect(saveCardDetails).toHaveBeenCalledTimes(1);
            expect(saveCardDetails.mock.calls[0][0].request).toEqual(expect.objectContaining({ customerName: 'Suresh Patel', phone: '9826011111' }));
        });

        it('picking an existing customer links the car straight away', async () => {
            searchCustomers.mockResolvedValue([{ id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111' }]);
            getCustomer.mockResolvedValue({ id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111', vehicles: [{ id: 'veh1', registrationNumber: 'MP09AB1234' }] });
            saveCardDetails.mockResolvedValue({ ...NO_CUSTOMER, customerId: 'cust1', customerName: 'Ramesh Kumar', phone: '9000011111' });
            const card = await openCard();

            await typeField(card, '[data-field="customerName"]', 'Ram');
            await wait(350);
            inCard(card, 'c-paper-field[data-field="customerName"]').shadowRoot.querySelector('[data-id="option"]').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
            await flushPromises();
            await flushPromises();

            expect(saveCardDetails.mock.calls[0][0].request.customerId).toBe('cust1');
            expect(getVehicleCard).not.toHaveBeenCalled();
            expect(inCard(card, '[data-id="card-number"]').textContent).toBe('MP09ZZ0001');
            expect(inCard(card, '[data-id="make-bill"]').disabled).toBe(false);
        });

        it('keeps what was typed until the save is confirmed', async () => {
            let finishSaving;
            saveCardDetails.mockReturnValueOnce(new Promise((resolve) => {
                finishSaving = resolve;
            }));
            const card = await openCard();

            await typeField(card, '[data-field="customerName"]', 'Suresh Patel');
            blurField(card, '[data-field="customerName"]');
            await wait(200);
            expect(inCard(card, 'c-paper-field[data-field="customerName"]').value).toBe('Suresh Patel');
            expect(inCard(card, '[data-id="save-state"]').textContent).toBe('Saving…');

            finishSaving(WITH_NAME);
            await flushPromises();
            expect(inCard(card, '[data-id="card-name"]').textContent).toBe('Suresh Patel');
            expect(inCard(card, '[data-id="save-state"]').textContent).toBe('Saved');
        });

        it('a failed save says so and leaves the text in the box', async () => {
            saveCardDetails.mockRejectedValueOnce({ body: { message: 'Something went wrong.' } });
            const card = await openCard();

            await typeField(card, '[data-field="customerName"]', 'Suresh Patel');
            blurField(card, '[data-field="customerName"]');
            await wait(200);
            await flushPromises();

            expect(inCard(card, 'c-paper-field[data-field="customerName"]').value).toBe('Suresh Patel');
            expect(inCard(card, '[data-id="save-state"]').textContent).toBe('Not saved');
        });

        it('leaving the page saves details typed but not yet saved', async () => {
            saveCardDetails.mockResolvedValue(WITH_NAME);
            getDay.mockResolvedValueOnce([NO_CUSTOMER]).mockResolvedValue([]);
            const element = await createScreen();

            await typeField(cards(element)[0], '[data-field="customerName"]', 'Suresh Patel');
            $(element, '[data-id="previous-day"]').click();
            await flushPromises();

            expect(saveCardDetails.mock.calls[0][0].request.customerName).toBe('Suresh Patel');
        });

        it('a card with every detail has no boxes', async () => {
            getDay.mockResolvedValue([CAR]);
            const element = await createScreen();

            expect(inCard(cards(element)[0], 'c-paper-field')).toBeNull();
            expect(inCard(cards(element)[0], '[data-id="make-bill"]').disabled).toBe(false);
        });
    });

    it('a known car number typed on a new card becomes that car, keeping what was typed', async () => {
        search.mockResolvedValue([{ ...CAR, workDone: 'Oil changed' }]);
        const element = await createScreen();
        $(element, '[data-id="new-car"]').click();
        await flushPromises();
        const card = cards(element)[0];
        await typeWork(card, 'Washed');

        await typeField(card, '[data-field="registrationNumber"]', 'mp09ab1234');
        inCard(card, 'c-paper-field[data-field="registrationNumber"]').shadowRoot.querySelector('input').dispatchEvent(new CustomEvent('blur'));
        await flushPromises();
        await flushPromises();

        expect(inCard(card, '[data-id="card-number"]').textContent).toBe('MP09AB1234');
        expect(inCard(card, '[data-id="work"]').value).toBe('Oil changed\nWashed');
        expect(inCard(card, '[data-id="earlier-days"]').textContent).toContain('Brake pads replaced');
    });

    it('picking a customer with one car on a new card opens that car', async () => {
        searchCustomers.mockResolvedValue([{ id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111' }]);
        getCustomer.mockResolvedValue({ id: 'cust1', name: 'Ramesh Kumar', phone: '9000011111', vehicles: [{ id: 'veh1', registrationNumber: 'MP09AB1234' }] });
        getVehicleCard.mockResolvedValue(NOT_TODAY);
        const element = await createScreen();
        $(element, '[data-id="new-car"]').click();
        await flushPromises();
        const card = cards(element)[0];

        await typeField(card, '[data-field="customerName"]', 'Ram');
        await wait(350);
        inCard(card, 'c-paper-field[data-field="customerName"]').shadowRoot.querySelector('[data-id="option"]').dispatchEvent(new CustomEvent('mousedown', { bubbles: true, cancelable: true }));
        await flushPromises();
        await flushPromises();

        expect(getVehicleCard).toHaveBeenCalledWith({ vehicleId: 'veh1', entryDate: todayIso() });
        expect(inCard(card, '[data-id="card-number"]').textContent).toBe('MP09AB1234');
    });

    it('Enter in Work Done is left alone so it makes a new line, and Esc returns to search', async () => {
        getDay.mockResolvedValue([CAR]);
        const element = await createScreen();
        const box = inCard(cards(element)[0], '[data-id="work"]');

        const enter = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, composed: true, cancelable: true });
        box.dispatchEvent(enter);
        expect(enter.defaultPrevented).toBe(false);

        const search = $(element, '[data-id="search"]');
        search.focus = jest.fn();
        box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, composed: true, cancelable: true }));
        await flushPromises();
        expect(search.focus).toHaveBeenCalled();
    });

    it('the box grows as lines are added', async () => {
        getDay.mockResolvedValue([CAR]);
        const element = await createScreen();
        const card = cards(element)[0];

        await typeWork(card, 'a\nb\nc\nd\ne');
        expect(inCard(card, '[data-id="work"]').rows).toBe(6);
    });

    it('saves everything typed even if more arrives during a save', async () => {
        let finishFirst;
        saveWork.mockReturnValueOnce(new Promise((resolve) => {
            finishFirst = resolve;
        }));
        getDay.mockResolvedValue([CAR]);
        const element = await createScreen();
        const card = cards(element)[0];

        await typeWork(card, 'one');
        await wait(900);
        await typeWork(card, 'one\ntwo');
        await wait(900);
        expect(saveWork).toHaveBeenCalledTimes(1);

        finishFirst(CAR);
        await flushPromises();
        await flushPromises();

        expect(saveWork).toHaveBeenCalledTimes(2);
        expect(saveWork.mock.calls[1][0].request.workDone).toBe('one\ntwo');
    });

    it('changing the date saves what was just typed rather than losing it', async () => {
        getDay.mockResolvedValue([CAR]);
        const element = await createScreen();
        await typeWork(cards(element)[0], 'typed just now');

        getDay.mockResolvedValue([]);
        $(element, '[data-id="previous-day"]').click();
        await flushPromises();

        expect(saveWork.mock.calls[0][0].request.workDone).toBe('typed just now');
        expect(saveWork.mock.calls[0][0].request.entryDate).toBe(todayIso());
    });

    it('says when a save failed, and keeps the text', async () => {
        saveWork.mockRejectedValue({ body: { message: 'Something went wrong.' } });
        getDay.mockResolvedValue([CAR]);
        const element = await createScreen();
        const card = cards(element)[0];

        await typeWork(card, 'Clutch adjusted');
        await wait(900);
        await flushPromises();

        expect(inCard(card, '[data-id="save-state"]').textContent).toBe('Not saved');
        expect(inCard(card, '[data-id="work"]').value).toBe('Clutch adjusted');
    });

    it('other visits are one link away, grouped by visit, and a date opens that day', async () => {
        getDay.mockResolvedValue([CAR]);
        const element = await createScreen();
        const card = cards(element)[0];
        expect(inCard(card, '[data-id="visits"]')).toBeNull();
        expect(inCard(card, '[data-id="toggle-visits"]').textContent).toBe('Show 1 other visit');

        inCard(card, '[data-id="toggle-visits"]').click();
        await flushPromises();
        const other = inCard(card, '[data-id="visits"]').textContent;
        expect(other).toContain('1 Sept 2026 to 2 Sept 2026');
        expect(other).toContain('Clutch plate');
        expect(other).toContain('Clutch bearing');

        const dates = card.shadowRoot.querySelectorAll('[data-id="visits"] [data-id="visit-date"]');
        dates[1].click();
        await flushPromises();
        expect(getDay).toHaveBeenLastCalledWith({ entryDate: '2026-09-02' });
    });

    describe('a visit over several days', () => {
        it('shows every day of the visit on the card without opening anything', async () => {
            getDay.mockResolvedValue([CAR]);
            const element = await createScreen();
            const card = cards(element)[0];

            expect(inCard(card, '[data-id="earlier-days"]').textContent).toContain('20 Oct 2026');
            expect(inCard(card, '[data-id="earlier-days"]').textContent).toContain('Brake pads replaced');
            expect(inCard(card, '[data-id="work-label"]').textContent).toContain('Work Done on');
            expect(inCard(card, '[data-id="visit-text"]').textContent).toBe('Same visit, started 20 Oct 2026');
            expect(inCard(card, '[data-id="start-new-visit"]')).not.toBeNull();
        });

        it('a day looked back at also shows the days after it', async () => {
            getDay.mockResolvedValue([{ ...CAR, visitStart: todayIso(), visitDays: [{ entryDate: '2099-01-01', workDone: 'Later work' }] }]);
            const element = await createScreen();

            expect(inCard(cards(element)[0], '[data-id="later-days"]').textContent).toContain('Later work');
            expect(inCard(cards(element)[0], '[data-id="earlier-days"]')).toBeNull();
        });

        it('Start new visit on a written day moves it, and the undo button puts it back', async () => {
            const asNewVisit = { ...CAR, visitStart: todayIso(), visitDays: [], previousVisitStart: '2026-10-20' };
            changeVisit.mockResolvedValueOnce(asNewVisit).mockResolvedValueOnce(CAR);
            getDay.mockResolvedValue([CAR]);
            const element = await createScreen();
            const card = cards(element)[0];

            inCard(card, '[data-id="start-new-visit"]').click();
            await flushPromises();
            expect(changeVisit).toHaveBeenCalledWith({ vehicleId: 'veh1', entryDate: todayIso(), startNew: true });
            expect(inCard(card, '[data-id="visit-text"]').textContent).toBe('New visit');
            expect(inCard(card, '[data-id="earlier-days"]')).toBeNull();
            expect(inCard(card, '[data-id="join-visit"]').label).toBe('Add to visit from 20 Oct 2026');

            inCard(card, '[data-id="join-visit"]').click();
            await flushPromises();
            expect(changeVisit).toHaveBeenLastCalledWith({ vehicleId: 'veh1', entryDate: todayIso(), startNew: false });
            expect(inCard(card, '[data-id="earlier-days"]').textContent).toContain('Brake pads replaced');
        });

        it('on a day with nothing written yet, Start new visit is sent with the first save', async () => {
            saveWork.mockResolvedValue({ ...CAR, workDone: 'Fresh work', visitStart: todayIso(), visitDays: [] });
            search.mockResolvedValue([NOT_TODAY]);
            const element = await createScreen();
            await typeSearch(element, 'swift');
            press(element, 'Enter');
            await flushPromises();
            const card = cards(element)[0];

            inCard(card, '[data-id="start-new-visit"]').click();
            await flushPromises();
            expect(changeVisit).not.toHaveBeenCalled();
            expect(inCard(card, '[data-id="earlier-days"]')).toBeNull();
            expect(inCard(card, '[data-id="visit-text"]').textContent).toBe('New visit');

            await typeWork(card, 'Fresh work');
            await wait(900);
            await flushPromises();
            expect(saveWork.mock.calls[0][0].request.startNewVisit).toBe(true);
        });

        it('a car with no earlier work has no visit bar', async () => {
            getDay.mockResolvedValue([{ ...CAR, visitStart: todayIso(), visitDays: [], otherVisits: [] }]);
            const element = await createScreen();

            expect(inCard(cards(element)[0], '[data-id="visit-bar"]')).toBeNull();
            expect(inCard(cards(element)[0], '[data-id="work-label"]').textContent).toBe('Work Done');
        });

        it('search results show the whole visit, and count older visits', async () => {
            search.mockResolvedValue([CAR]);
            const element = await createScreen();
            await typeSearch(element, 'swift');

            const result = $(element, '[data-id="result"]').textContent;
            expect(result).toContain('Brake pads replaced');
            expect(result).toContain('Oil changed');
            expect(result).toContain('and 1 older visit');
            expect(result).not.toContain('Clutch plate');
        });

        it('Bill passes the date, so Easy Bill can show this visit', async () => {
            getDay.mockResolvedValue([CAR]);
            const element = await createScreen();

            inCard(cards(element)[0], '[data-id="make-bill"]').click();
            expect(mockNavigate.mock.calls[0][0].state.c__entryDate).toBe(todayIso());
        });
    });

    it('Bill and Estimate open Easy Bill with the customer and car, saving first', async () => {
        getDay.mockResolvedValue([CAR]);
        const element = await createScreen();
        const card = cards(element)[0];
        await typeWork(card, 'typed just now');

        inCard(card, '[data-id="make-bill"]').click();
        expect(saveWork).toHaveBeenCalledTimes(1);
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Easy_Bill' },
            state: expect.objectContaining({ c__documentType: 'bill', c__customerId: 'cust1', c__vehicleId: 'veh1' })
        });

        await flushPromises();
        inCard(card, '[data-id="make-estimate"]').click();
        expect(mockNavigate.mock.calls[1][0].state.c__documentType).toBe('estimate');
    });
});
