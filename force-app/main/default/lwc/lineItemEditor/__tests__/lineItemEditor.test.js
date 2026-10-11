import { createElement } from 'lwc';
import LineItemEditor from 'c/lineItemEditor';
import searchParts from '@salesforce/apex/BillController.searchParts';

jest.mock('@salesforce/apex/BillController.searchParts', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createEditor(record) {
    const element = createElement('c-line-item-editor', { is: LineItemEditor });
    element.record = record;
    document.body.appendChild(element);
    return element;
}

describe('c-line-item-editor', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('a new blank line starts straight in inventory-search mode', () => {
        const element = createEditor({ key: 1, description: '', quantity: 1, unitPrice: 0 });
        expect(element.shadowRoot.querySelector('[data-id="part-search"]')).not.toBeNull();
        expect(element.shadowRoot.textContent).toContain('Add Line Item');
    });

    it('switching to "Use a manual line instead" defaults the tax rate to 18% when none is set yet', async () => {
        const element = createEditor({ key: 1, description: '', quantity: 1, unitPrice: 0, taxRatePercent: 0 });

        element.shadowRoot.querySelector('[data-id="use-manual-line"]').click();
        await flushPromises();

        const taxRateInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'taxRatePercent'
        );
        expect(taxRateInput.value).toBe(18);
    });

    it('switching to "Use a manual line instead" does not overwrite a tax rate carried over from a selected part', async () => {
        searchParts.mockResolvedValue([
            {
                id: '02ixx0000000001',
                name: 'Brake Pad',
                price: 500,
                taxRatePercent: 28,
                gstType: 'CGST_SGST',
                hsnCode: '8708',
                unitLabel: 'pcs',
                currentStock: 10
            }
        ]);
        const element = createEditor({ key: 1, description: '', quantity: 1, unitPrice: 0 });
        const search = element.shadowRoot.querySelector('[data-id="part-search"]');
        search.value = 'Brake';
        search.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        element.shadowRoot.querySelector('button[data-id="02ixx0000000001"]').click();
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="change-part"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="use-manual-line"]').click();
        await flushPromises();

        const taxRateInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'taxRatePercent'
        );
        expect(taxRateInput.value).toBe(28);
    });

    it('an existing part-linked line shows "From inventory" with a Change link', () => {
        const element = createEditor({
            key: 1,
            partId: '02ixx0000000001',
            description: 'Brake Pad',
            quantity: 2,
            unitPrice: 500,
            taxRatePercent: 18,
            gstType: 'CGST_SGST'
        });

        expect(element.shadowRoot.textContent).toContain('From inventory: Brake Pad');
        expect(element.shadowRoot.textContent).toContain('Edit Line Item');
        const descriptionInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'description'
        );
        expect(descriptionInput.value).toBe('Brake Pad');
    });

    it('an existing manual line shows its fields directly with a "Search inventory" option', () => {
        const element = createEditor({
            key: 1,
            partId: null,
            description: 'Labour',
            quantity: 1,
            unitPrice: 300,
            taxRatePercent: 0
        });

        expect(element.shadowRoot.querySelector('[data-id="part-search"]')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Manual line');
        const descriptionInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'description'
        );
        expect(descriptionInput.value).toBe('Labour');
    });

    it('selecting a searched part fills the line and exits search mode', async () => {
        searchParts.mockResolvedValue([
            {
                id: '02ixx0000000001',
                name: 'Brake Pad',
                price: 500,
                taxRatePercent: 18,
                gstType: 'CGST_SGST',
                hsnCode: '8708',
                unitLabel: 'pcs',
                currentStock: 10
            }
        ]);

        const element = createEditor({ key: 1, description: '', quantity: 1, unitPrice: 0 });
        const search = element.shadowRoot.querySelector('[data-id="part-search"]');
        search.value = 'Brake';
        search.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot.querySelector('button[data-id="02ixx0000000001"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="part-search"]')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('From inventory: Brake Pad');
    });

    it('Save emits the edited line with numeric fields coerced', async () => {
        const element = createEditor({
            key: 5,
            partId: null,
            description: 'Labour',
            quantity: '1',
            unitPrice: '300',
            taxRatePercent: '18'
        });
        const handler = jest.fn();
        element.addEventListener('save', handler);

        const quantityInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'quantity'
        );
        quantityInput.value = '2';
        quantityInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save"]').click();

        expect(handler).toHaveBeenCalledTimes(1);
        const detail = handler.mock.calls[0][0].detail;
        expect(detail.quantity).toBe(2);
        expect(detail.unitPrice).toBe(300);
        expect(detail.taxRatePercent).toBe(18);
        expect(detail.key).toBe(5);
    });

    it('Cancel fires a cancel event without saving', () => {
        const element = createEditor({ key: 1, description: 'Labour', quantity: 1, unitPrice: 300 });
        const handler = jest.fn();
        element.addEventListener('cancel', handler);

        element.shadowRoot.querySelector('[data-id="cancel"]').click();

        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('Save is disabled until description, quantity, and price are valid', () => {
        const element = createEditor({ key: 1, partId: null, description: '', quantity: 0, unitPrice: 0 });
        expect(element.shadowRoot.querySelector('[data-id="save"]').disabled).toBe(true);
    });
});
