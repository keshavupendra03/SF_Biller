import { createElement } from 'lwc';
import WorkshopProfile from 'c/workshopProfile';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';
import saveProfile from '@salesforce/apex/WorkshopProfileController.saveProfile';
import addProfile from '@salesforce/apex/WorkshopProfileController.addProfile';
import setGstFiledUpTo from '@salesforce/apex/WorkshopProfileController.setGstFiledUpTo';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WorkshopProfileController.saveProfile', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WorkshopProfileController.addProfile', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WorkshopProfileController.setGstFiledUpTo', () => ({ default: jest.fn() }), { virtual: true });

const MOTORS = { id: 'wp1', name: 'Keshav Car WS', phone: '6268471199', gstin: 'FDJSG23575HFH', invoicePrefix: 'INV' };
const DECOR = { id: 'wp2', name: 'Keshav Decor', gstin: 'DECOR123', invoicePrefix: 'DEC' };

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function createScreen() {
    const element = createElement('c-workshop-profile', { is: WorkshopProfile });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

function field(element, name) {
    return element.shadowRoot.querySelector(`[data-field="${name}"]`);
}

function type(element, name, value) {
    const input = field(element, name);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
}

function choices(element) {
    return [...element.shadowRoot.querySelectorAll('[data-id="company-choice"]')];
}

describe('c-workshop-profile', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads an existing profile into the form', async () => {
        listProfiles.mockResolvedValue([MOTORS]);
        const element = await createScreen();

        expect(field(element, 'name').value).toBe('Keshav Car WS');
        expect(field(element, 'invoicePrefix').value).toBe('INV');
        expect(choices(element)).toHaveLength(0);
    });

    it('saves the profile with the entered values', async () => {
        listProfiles.mockResolvedValue([]);
        saveProfile.mockResolvedValue({ id: 'wp1' });
        const element = await createScreen();
        expect(element.shadowRoot.querySelector('[data-id="add-company"]')).toBeNull();

        type(element, 'name', 'Keshav Car WS');
        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(saveProfile).toHaveBeenCalledWith({ input: expect.objectContaining({ name: 'Keshav Car WS' }) });
    });

    it('adds a second company from a blank form, and then offers no third', async () => {
        listProfiles.mockResolvedValueOnce([MOTORS]).mockResolvedValueOnce([MOTORS, DECOR]);
        addProfile.mockResolvedValue(DECOR);
        const element = await createScreen();

        element.shadowRoot.querySelector('[data-id="add-company"]').click();
        await flushPromises();
        expect(field(element, 'name').value).toBe('');
        expect(element.shadowRoot.querySelector('[data-id="save"]').label).toBe('Add Company');

        type(element, 'name', 'Keshav Decor');
        type(element, 'invoicePrefix', 'DEC');
        await flushPromises();
        expect(element.shadowRoot.textContent).toContain('DEC/2026-27/0001');

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();
        await flushPromises();

        expect(addProfile).toHaveBeenCalledWith({ input: expect.objectContaining({ name: 'Keshav Decor', invoicePrefix: 'DEC' }) });
        expect(saveProfile).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('[data-id="add-company"]')).toBeNull();
        expect(field(element, 'name').value).toBe('Keshav Decor');
    });

    it('cancelling the add goes back to the first company', async () => {
        listProfiles.mockResolvedValue([MOTORS]);
        const element = await createScreen();

        element.shadowRoot.querySelector('[data-id="add-company"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="cancel-add"]').click();
        await flushPromises();

        expect(field(element, 'name').value).toBe('Keshav Car WS');
    });

    it('switches between the two companies and saves the one showing', async () => {
        listProfiles.mockResolvedValue([MOTORS, DECOR]);
        saveProfile.mockResolvedValue(DECOR);
        const element = await createScreen();

        expect(choices(element).map((c) => c.label)).toEqual(['Keshav Car WS', 'Keshav Decor']);
        choices(element)[1].click();
        await flushPromises();
        expect(field(element, 'gstin').value).toBe('DECOR123');

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(saveProfile).toHaveBeenCalledWith({ input: expect.objectContaining({ id: 'wp2', name: 'Keshav Decor' }) });
    });

    it('shows the server message when a company is refused', async () => {
        listProfiles.mockResolvedValue([MOTORS]);
        addProfile.mockRejectedValue({ body: { message: 'Each company needs its own invoice prefix. INV is already used.' } });
        const element = await createScreen();
        const toast = jest.fn();
        element.addEventListener('lightning__showtoast', toast);

        element.shadowRoot.querySelector('[data-id="add-company"]').click();
        await flushPromises();
        type(element, 'name', 'Keshav Decor');
        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(toast.mock.calls[0][0].detail.message).toContain('own invoice prefix');
    });

    describe('GST details', () => {
        it('shows the GST settings, Regular and Monthly unless saved otherwise, and saves a change', async () => {
            listProfiles.mockResolvedValue([MOTORS]);
            saveProfile.mockResolvedValue(MOTORS);
            const element = await createScreen();
            expect(field(element, 'gstRegistrationType').value).toBe('Regular');
            expect(field(element, 'gstFilingFrequency').value).toBe('Monthly');

            field(element, 'gstRegistrationType').dispatchEvent(new CustomEvent('change', { detail: { value: 'Composition' } }));
            field(element, 'gstFilingFrequency').dispatchEvent(new CustomEvent('change', { detail: { value: 'Quarterly' } }));
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="save"]').click();
            await flushPromises();

            expect(saveProfile.mock.calls[0][0].input).toEqual(expect.objectContaining({
                gstRegistrationType: 'Composition', gstFilingFrequency: 'Quarterly'
            }));
        });

        it('a company that is not registered is not asked how often it files', async () => {
            listProfiles.mockResolvedValue([{ ...MOTORS, gstRegistrationType: 'Unregistered' }]);
            const element = await createScreen();

            expect(field(element, 'gstFilingFrequency')).toBeNull();
        });

        it('the state is picked from a list, and an older "MP" shows as Madhya Pradesh', async () => {
            listProfiles.mockResolvedValue([{ ...MOTORS, state: 'MP' }]);
            const element = await createScreen();

            const state = field(element, 'state');
            expect(state.tagName).toBe('LIGHTNING-COMBOBOX');
            expect(state.options).toContainEqual({ label: 'Madhya Pradesh', value: 'Madhya Pradesh' });
            expect(state.value).toBe('Madhya Pradesh');
        });

        it('a GSTIN fills in a blank state', async () => {
            listProfiles.mockResolvedValue([{ ...MOTORS, gstin: '', state: '' }]);
            const element = await createScreen();

            type(element, 'gstin', '27AAPFU0939F1ZV');
            await flushPromises();

            expect(field(element, 'state').value).toBe('Maharashtra');
        });
    });

    describe('GST returns filed up to', () => {
        it('picking a filed month saves it at once, and says what is locked', async () => {
            listProfiles.mockResolvedValue([MOTORS]);
            setGstFiledUpTo.mockResolvedValue({ ...MOTORS, gstFiledUpTo: '2026-10-31' });
            const element = await createScreen();
            const filed = element.shadowRoot.querySelector('[data-id="filed-up-to"]');
            expect(filed.options[0]).toEqual({ label: 'Nothing filed yet', value: '' });
            expect(filed.value).toBe('');

            filed.dispatchEvent(new CustomEvent('change', { detail: { value: '2026-10-31' } }));
            await flushPromises();

            expect(setGstFiledUpTo).toHaveBeenCalledWith({ companyId: 'wp1', filedUpTo: '2026-10-31' });
            expect(element.shadowRoot.querySelector('[data-id="filed-up-to"]').value).toBe('2026-10-31');
            expect(element.shadowRoot.querySelector('[data-id="filed-up-to-hint"]').textContent).toContain('filed up to October 2026');
        });

        it('"Nothing filed yet" unlocks everything', async () => {
            listProfiles.mockResolvedValue([{ ...MOTORS, gstFiledUpTo: '2026-10-31' }]);
            setGstFiledUpTo.mockResolvedValue({ ...MOTORS, gstFiledUpTo: null });
            const element = await createScreen();

            element.shadowRoot.querySelector('[data-id="filed-up-to"]').dispatchEvent(new CustomEvent('change', { detail: { value: '' } }));
            await flushPromises();

            expect(setGstFiledUpTo).toHaveBeenCalledWith({ companyId: 'wp1', filedUpTo: null });
        });

        it('is not offered to a company that isn\'t registered, or one being added', async () => {
            listProfiles.mockResolvedValue([{ ...MOTORS, gstRegistrationType: 'Unregistered' }]);
            const element = await createScreen();
            expect(element.shadowRoot.querySelector('[data-id="filed-up-to"]')).toBeNull();
        });
    });

    it('rounds totals to whole rupees unless turned off, and saves the choice (G5)', async () => {
        listProfiles.mockResolvedValue([MOTORS]);
        saveProfile.mockResolvedValue(MOTORS);
        const element = await createScreen();
        const toggle = element.shadowRoot.querySelector('[data-id="round-off"]');
        expect(toggle.checked).toBe(true);
        expect(element.shadowRoot.querySelector('[data-id="round-off-hint"]').textContent).toContain('nearest rupee');

        toggle.checked = false;
        toggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        expect(element.shadowRoot.querySelector('[data-id="round-off-hint"]').textContent).toContain('to the paisa');
        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(saveProfile.mock.calls[0][0].input.roundOffTotals).toBe(false);
    });

    it('a company saved with round-off off shows it off', async () => {
        listProfiles.mockResolvedValue([{ ...MOTORS, roundOffTotals: false }]);
        const element = await createScreen();
        expect(element.shadowRoot.querySelector('[data-id="round-off"]').checked).toBe(false);
    });
});
