import { createElement } from 'lwc';
import WorkshopProfile from 'c/workshopProfile';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';
import saveProfile from '@salesforce/apex/WorkshopProfileController.saveProfile';
import addProfile from '@salesforce/apex/WorkshopProfileController.addProfile';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WorkshopProfileController.saveProfile', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WorkshopProfileController.addProfile', () => ({ default: jest.fn() }), { virtual: true });

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
});
