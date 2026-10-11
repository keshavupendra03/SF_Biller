import { createElement } from 'lwc';
import InventoryList from 'c/inventoryList';
import listParts from '@salesforce/apex/PartController.listParts';
import createPart from '@salesforce/apex/PartController.createPart';

jest.mock('@salesforce/apex/PartController.listParts', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PartController.createPart', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-inventory-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads parts on connect and flags low stock', async () => {
        listParts.mockResolvedValue([
            { id: 'p1', name: 'Bumper', currentStock: -1, price: 500, isLowStock: true },
            { id: 'p2', name: 'Grille', currentStock: 10, price: 200, isLowStock: false }
        ]);

        const element = createElement('c-inventory-list', { is: InventoryList });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Bumper');
        const warningIcons = element.shadowRoot.querySelectorAll('[data-id="low-stock-icon"]');
        expect(warningIcons).toHaveLength(1);
    });

    it('creating a part with opening stock refreshes the list', async () => {
        listParts.mockResolvedValue([]);
        createPart.mockResolvedValue({ id: 'p9', name: 'New Part' });

        const element = createElement('c-inventory-list', { is: InventoryList });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="fab"]').click();
        await flushPromises();

        const nameInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'name'
        );
        nameInput.value = 'New Part';
        nameInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(createPart).toHaveBeenCalledTimes(1);
        expect(listParts).toHaveBeenCalledTimes(2);
    });
});
