import { createElement } from 'lwc';
import VehicleMakeModelField from 'c/vehicleMakeModelField';
import searchMakes from '@salesforce/apex/VehicleMakeModelController.searchMakes';
import searchModels from '@salesforce/apex/VehicleMakeModelController.searchModels';

jest.mock('@salesforce/apex/VehicleMakeModelController.searchMakes', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/VehicleMakeModelController.searchModels', () => ({ default: jest.fn() }), {
    virtual: true
});

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-vehicle-make-model-field', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('searches makes as the user types when source is "make"', async () => {
        searchMakes.mockResolvedValue(['Maruti Suzuki', 'Mahindra']);

        const element = createElement('c-vehicle-make-model-field', { is: VehicleMakeModelField });
        element.label = 'Make';
        element.source = 'make';
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('[data-id="input"]');
        input.value = 'Mar';
        input.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(searchMakes).toHaveBeenCalledWith({ term: 'Mar' });
        const options = element.shadowRoot.querySelectorAll('.search-result-row');
        expect(options).toHaveLength(2);
        expect(options[0].textContent).toBe('Maruti Suzuki');
    });

    it('searches models scoped to the given make when source is "model"', async () => {
        searchModels.mockResolvedValue(['Swift', 'Baleno']);

        const element = createElement('c-vehicle-make-model-field', { is: VehicleMakeModelField });
        element.label = 'Model';
        element.source = 'model';
        element.make = 'Maruti Suzuki';
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('[data-id="input"]');
        input.value = 'S';
        input.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(searchModels).toHaveBeenCalledWith({ make: 'Maruti Suzuki', term: 'S' });
    });

    it('selecting a suggestion sets the value and dispatches change', async () => {
        searchMakes.mockResolvedValue(['Maruti Suzuki', 'Mahindra']);

        const element = createElement('c-vehicle-make-model-field', { is: VehicleMakeModelField });
        element.label = 'Make';
        element.source = 'make';
        const handler = jest.fn();
        element.addEventListener('change', handler);
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('[data-id="input"]');
        input.value = 'Mar';
        input.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot.querySelector('[data-value="Maruti Suzuki"]').dispatchEvent(new CustomEvent('mousedown'));
        await flushPromises();

        expect(element.value).toBe('Maruti Suzuki');
        expect(handler).toHaveBeenCalledWith(
            expect.objectContaining({ detail: { value: 'Maruti Suzuki' } })
        );
        expect(element.shadowRoot.querySelectorAll('.search-result-row')).toHaveLength(0);
    });

    it('free-typed text with no matching suggestions is kept as-is and shows no dropdown', async () => {
        searchMakes.mockResolvedValue([]);

        const element = createElement('c-vehicle-make-model-field', { is: VehicleMakeModelField });
        element.label = 'Make';
        element.source = 'make';
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('[data-id="input"]');
        input.value = 'Some Brand Nobody Loaded Yet';
        input.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(element.value).toBe('Some Brand Nobody Loaded Yet');
        expect(element.shadowRoot.querySelectorAll('.search-result-row')).toHaveLength(0);
    });

    it('blurring the input hides the suggestion list', async () => {
        searchMakes.mockResolvedValue(['Maruti Suzuki']);

        const element = createElement('c-vehicle-make-model-field', { is: VehicleMakeModelField });
        element.label = 'Make';
        element.source = 'make';
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('[data-id="input"]');
        input.value = 'Mar';
        input.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('.search-result-row')).toHaveLength(1);

        input.dispatchEvent(new CustomEvent('blur'));
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('.search-result-row')).toHaveLength(0);
    });
});
