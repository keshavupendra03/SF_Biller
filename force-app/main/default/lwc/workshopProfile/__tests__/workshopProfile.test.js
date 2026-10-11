import { createElement } from 'lwc';
import WorkshopProfile from 'c/workshopProfile';
import getProfile from '@salesforce/apex/WorkshopProfileController.getProfile';
import saveProfile from '@salesforce/apex/WorkshopProfileController.saveProfile';

jest.mock('@salesforce/apex/WorkshopProfileController.getProfile', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WorkshopProfileController.saveProfile', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-workshop-profile', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads an existing profile into the form', async () => {
        getProfile.mockResolvedValue({ name: 'Keshav Car WS', phone: '6268471199', gstin: 'FDJSG23575HFH' });

        const element = createElement('c-workshop-profile', { is: WorkshopProfile });
        document.body.appendChild(element);
        await flushPromises();

        const nameInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'name'
        );
        expect(nameInput.value).toBe('Keshav Car WS');
    });

    it('saves the profile with the entered values', async () => {
        getProfile.mockResolvedValue(null);
        saveProfile.mockResolvedValue({});

        const element = createElement('c-workshop-profile', { is: WorkshopProfile });
        document.body.appendChild(element);
        await flushPromises();

        const nameInput = Array.from(element.shadowRoot.querySelectorAll('[data-field]')).find(
            (el) => el.dataset.field === 'name'
        );
        nameInput.value = 'Keshav Car WS';
        nameInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(saveProfile).toHaveBeenCalledWith({
            input: expect.objectContaining({ name: 'Keshav Car WS' })
        });
    });
});
