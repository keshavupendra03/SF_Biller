import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import InventoryDetail from 'c/inventoryDetail';
import getPartDetail from '@salesforce/apex/PartController.getPartDetail';
import updatePart from '@salesforce/apex/PartController.updatePart';
import adjustStock from '@salesforce/apex/PartController.adjustStock';

jest.mock('@salesforce/apex/PartController.getPartDetail', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PartController.updatePart', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PartController.adjustStock', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const DETAIL = {
    part: {
        id: 'p1',
        name: 'Brake Pad',
        sku: 'BP-1',
        barcode: '',
        price: 500,
        currentStock: 10,
        lowStockThreshold: 5,
        isLowStock: false,
        gstType: 'CGST_SGST',
        taxRatePercent: 18,
        hsnCode: '8708',
        unitLabel: 'pcs'
    }
};

describe('c-inventory-detail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads the part detail from the page reference', async () => {
        getPartDetail.mockResolvedValue(DETAIL);

        const element = createElement('c-inventory-detail', { is: InventoryDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__partId: 'p1' } });
        await flushPromises();

        expect(getPartDetail).toHaveBeenCalledWith({ partId: 'p1' });
        expect(element.shadowRoot.textContent).toContain('Brake Pad');
    });

    it('adjusting stock calls adjustStock and reloads', async () => {
        getPartDetail.mockResolvedValue(DETAIL);
        adjustStock.mockResolvedValue();

        const element = createElement('c-inventory-detail', { is: InventoryDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__partId: 'p1' } });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-adjust"]').click();
        await flushPromises();

        const qty = element.shadowRoot.querySelector('[data-id="adjust-quantity"]');
        qty.value = '5';
        qty.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="submit-adjust"]').click();
        await flushPromises();

        expect(adjustStock).toHaveBeenCalledWith({
            partId: 'p1',
            quantityDelta: 5
        });
        expect(getPartDetail).toHaveBeenCalledTimes(2);
    });

    it('editing the part calls updatePart', async () => {
        getPartDetail.mockResolvedValue(DETAIL);
        updatePart.mockResolvedValue();

        const element = createElement('c-inventory-detail', { is: InventoryDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__partId: 'p1' } });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-edit"]').click();
        await flushPromises();

        const priceInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'price'
        );
        priceInput.value = '600';
        priceInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save-edit"]').click();
        await flushPromises();

        expect(updatePart).toHaveBeenCalledWith({
            partId: 'p1',
            input: expect.objectContaining({ price: 600 })
        });
    });
});
