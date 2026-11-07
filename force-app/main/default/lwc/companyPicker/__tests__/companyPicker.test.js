import { createElement } from 'lwc';
import CompanyPicker from 'c/companyPicker';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';

jest.mock('@salesforce/apex/WorkshopProfileController.listProfiles', () => ({ default: jest.fn() }), { virtual: true });

const MOTORS = { id: 'wp1', name: 'Speedy Motors', gstin: '23AAA', isPrimary: true };
const DECOR = { id: 'wp2', name: 'Speedy Decor', gstin: '23BBB', isPrimary: false };

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function createPicker(props) {
    const element = createElement('c-company-picker', { is: CompanyPicker });
    Object.assign(element, props);
    const changes = [];
    element.addEventListener('companychange', (event) => changes.push(event.detail));
    document.body.appendChild(element);
    await flushPromises();
    return { element, changes };
}

function choices(element) {
    return [...element.shadowRoot.querySelectorAll('[data-id="company-choice"]')];
}

describe('c-company-picker', () => {
    beforeEach(() => {
        window.localStorage.clear();
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows nothing with one company, but still tells the screen which one it is', async () => {
        listProfiles.mockResolvedValue([MOTORS]);
        const { element, changes } = await createPicker();

        expect(element.shadowRoot.querySelector('[data-id="company-picker"]')).toBeNull();
        expect(changes).toEqual([{ id: 'wp1', profile: MOTORS }]);
    });

    it('reports no company when none exists yet', async () => {
        listProfiles.mockResolvedValue([]);
        const { changes } = await createPicker();

        expect(changes).toEqual([{ id: null, profile: null }]);
    });

    it('offers both companies, starts on the first, and shows its GSTIN', async () => {
        listProfiles.mockResolvedValue([MOTORS, DECOR]);
        const { element, changes } = await createPicker();

        expect(choices(element).map((c) => c.label)).toEqual(['Speedy Motors', 'Speedy Decor']);
        expect(choices(element)[0].variant).toBe('brand');
        expect(element.shadowRoot.querySelector('[data-id="company-gstin"]').textContent).toContain('23AAA');
        expect(changes[0].id).toBe('wp1');
    });

    it('choosing a company tells the screen, shows its GSTIN, and is remembered next time', async () => {
        listProfiles.mockResolvedValue([MOTORS, DECOR]);
        const { element, changes } = await createPicker();

        choices(element)[1].click();
        await flushPromises();

        expect(changes[1]).toEqual({ id: 'wp2', profile: DECOR });
        expect(choices(element)[1].variant).toBe('brand');
        expect(element.shadowRoot.querySelector('[data-id="company-gstin"]').textContent).toContain('23BBB');

        const next = await createPicker();
        expect(next.changes[0].id).toBe('wp2');
    });

    it('a value already set wins over the remembered company', async () => {
        window.localStorage.setItem('wsBiller.selectedCompany', 'wp2');
        listProfiles.mockResolvedValue([MOTORS, DECOR]);
        const { changes } = await createPicker({ value: 'wp1' });

        expect(changes[0].id).toBe('wp1');
    });

    it('ignores a remembered company that no longer exists', async () => {
        window.localStorage.setItem('wsBiller.selectedCompany', 'gone');
        listProfiles.mockResolvedValue([MOTORS, DECOR]);
        const { changes } = await createPicker();

        expect(changes[0].id).toBe('wp1');
    });

    it('locked shows the company as text with no way to change it', async () => {
        listProfiles.mockResolvedValue([MOTORS, DECOR]);
        const { element } = await createPicker({ value: 'wp2', locked: true });

        expect(choices(element)).toHaveLength(0);
        expect(element.shadowRoot.querySelector('[data-id="company-locked"]').textContent).toBe('Speedy Decor');
    });

    it('resetting the value falls back to the starting company and tells the screen', async () => {
        listProfiles.mockResolvedValue([MOTORS, DECOR]);
        const { element, changes } = await createPicker({ value: 'wp2' });

        element.value = undefined;
        await flushPromises();

        expect(changes[changes.length - 1].id).toBe('wp1');
    });

    it('allow-all adds All, starts there, filters by company, and never remembers', async () => {
        listProfiles.mockResolvedValue([MOTORS, DECOR]);
        const { element, changes } = await createPicker({ allowAll: true });

        expect(choices(element).map((c) => c.label)).toEqual(['All', 'Speedy Motors', 'Speedy Decor']);
        expect(choices(element)[0].variant).toBe('brand');
        expect(changes).toEqual([]);

        choices(element)[2].click();
        await flushPromises();
        expect(changes[0].id).toBe('wp2');
        expect(window.localStorage.getItem('wsBiller.selectedCompany')).toBeNull();

        choices(element)[0].click();
        await flushPromises();
        expect(changes[1]).toEqual({ id: null, profile: null });
    });
});
