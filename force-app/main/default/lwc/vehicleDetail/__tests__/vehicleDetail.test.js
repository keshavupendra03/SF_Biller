import { createElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import VehicleDetail from 'c/vehicleDetail';
import getVehicleDetail from '@salesforce/apex/VehicleController.getVehicleDetail';
import updateVehicle from '@salesforce/apex/VehicleController.updateVehicle';

jest.mock('@salesforce/apex/VehicleController.getVehicleDetail', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/VehicleController.updateVehicle', () => ({ default: jest.fn() }), { virtual: true });

const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    // eslint-disable-next-line global-require
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](pageRef) {
                mockNavigate(pageRef);
            }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: createTestWireAdapter(jest.fn()) };
});

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const DETAIL = {
    id: 'veh1',
    registrationNumber: 'MP09AB1234',
    make: 'Maruti Suzuki',
    model: 'Swift',
    year: 2022,
    color: 'White',
    chassisNumber: 'MA3ERLF1S00123456',
    customerId: 'cust1',
    customerName: 'Ramesh Kumar'
};

describe('c-vehicle-detail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads and displays the vehicle, including the chassis number', async () => {
        getVehicleDetail.mockResolvedValue(DETAIL);

        const element = createElement('c-vehicle-detail', { is: VehicleDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__recordId: 'veh1', c__fromCustomerId: 'cust1' } });
        await flushPromises();

        expect(getVehicleDetail).toHaveBeenCalledWith({ vehicleId: 'veh1' });
        expect(element.shadowRoot.textContent).toContain('MP09AB1234');
        expect(element.shadowRoot.textContent).toContain('MA3ERLF1S00123456');
        expect(element.shadowRoot.textContent).toContain('Ramesh Kumar');
    });

    it('omits the chassis number line when none is set', async () => {
        getVehicleDetail.mockResolvedValue({ ...DETAIL, chassisNumber: null });

        const element = createElement('c-vehicle-detail', { is: VehicleDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__recordId: 'veh1' } });
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('Chassis Number');
    });

    it('editing updates every field including chassis number, then reloads', async () => {
        getVehicleDetail.mockResolvedValue(DETAIL);
        updateVehicle.mockResolvedValue();

        const element = createElement('c-vehicle-detail', { is: VehicleDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__recordId: 'veh1' } });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="toggle-edit"]').click();
        await flushPromises();

        const chassisInput = element.shadowRoot.querySelector('[data-field="chassisNumber"]');
        chassisInput.value = 'NEWCHASSIS123456';
        chassisInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save-edit"]').click();
        await flushPromises();

        expect(updateVehicle).toHaveBeenCalledWith({
            vehicleId: 'veh1',
            input: expect.objectContaining({
                registrationNumber: 'MP09AB1234',
                chassisNumber: 'NEWCHASSIS123456'
            })
        });
        expect(getVehicleDetail).toHaveBeenCalledTimes(2);
    });

    it('back navigates to the customer it was opened from, when present', async () => {
        getVehicleDetail.mockResolvedValue(DETAIL);

        const element = createElement('c-vehicle-detail', { is: VehicleDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__recordId: 'veh1', c__fromCustomerId: 'cust1' } });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_Detail' },
            state: { c__customerId: 'cust1' }
        });
    });

    it('back falls back to the customer list when no originating customer is known', async () => {
        getVehicleDetail.mockResolvedValue(DETAIL);

        const element = createElement('c-vehicle-detail', { is: VehicleDetail });
        document.body.appendChild(element);
        CurrentPageReference.emit({ state: { c__recordId: 'veh1' } });
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="back"]').click();

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Customer_List' }
        });
    });
});
