import { createElement } from 'lwc';
import MechanicList from 'c/mechanicList';
import listMechanics from '@salesforce/apex/DirectoryController.listMechanics';
import createMechanic from '@salesforce/apex/DirectoryController.createMechanic';
import setMechanicActive from '@salesforce/apex/DirectoryController.setMechanicActive';

jest.mock('@salesforce/apex/DirectoryController.listMechanics', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DirectoryController.createMechanic', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DirectoryController.setMechanicActive', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-mechanic-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads active mechanics by default', async () => {
        listMechanics.mockResolvedValue([{ id: 'm1', name: 'Aniket', phone: '8319476994', isActive: true }]);

        const element = createElement('c-mechanic-list', { is: MechanicList });
        document.body.appendChild(element);
        await flushPromises();

        expect(listMechanics).toHaveBeenCalledWith({ includeInactive: false });
        expect(element.shadowRoot.textContent).toContain('Aniket');
    });

    it('toggling show inactive re-queries including inactive records', async () => {
        listMechanics.mockResolvedValue([]);

        const element = createElement('c-mechanic-list', { is: MechanicList });
        document.body.appendChild(element);
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('[data-id="show-inactive"]');
        toggle.checked = true;
        toggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(listMechanics).toHaveBeenCalledWith({ includeInactive: true });
    });

    it('creating a mechanic refreshes the list', async () => {
        listMechanics.mockResolvedValue([]);
        createMechanic.mockResolvedValue({ id: 'm9', name: 'New Guy', phone: '', isActive: true });

        const element = createElement('c-mechanic-list', { is: MechanicList });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="fab"]').click();
        await flushPromises();

        const nameInput = element.shadowRoot.querySelector('[data-id="new-name"]');
        nameInput.value = 'New Guy';
        nameInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(createMechanic).toHaveBeenCalledWith({ name: 'New Guy', phone: '' });
        expect(listMechanics).toHaveBeenCalledTimes(2);
    });

    it('toggling a mechanic active switch calls setMechanicActive', async () => {
        listMechanics.mockResolvedValue([{ id: 'm1', name: 'Aniket', phone: '', isActive: true }]);
        setMechanicActive.mockResolvedValue();

        const element = createElement('c-mechanic-list', { is: MechanicList });
        document.body.appendChild(element);
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('lightning-input[data-id="m1"]');
        toggle.checked = false;
        toggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(setMechanicActive).toHaveBeenCalledWith({ mechanicId: 'm1', active: false });
    });
});
