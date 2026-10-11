import { createElement } from 'lwc';
import SurveyorList from 'c/surveyorList';
import listSurveyors from '@salesforce/apex/DirectoryController.listSurveyors';
import createSurveyor from '@salesforce/apex/DirectoryController.createSurveyor';
import setSurveyorActive from '@salesforce/apex/DirectoryController.setSurveyorActive';

jest.mock('@salesforce/apex/DirectoryController.listSurveyors', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DirectoryController.createSurveyor', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DirectoryController.setSurveyorActive', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-surveyor-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads active surveyors by default', async () => {
        listSurveyors.mockResolvedValue([{ id: 's1', name: 'Bhaiyo Jio', phone: '9131360083', isActive: true }]);

        const element = createElement('c-surveyor-list', { is: SurveyorList });
        document.body.appendChild(element);
        await flushPromises();

        expect(listSurveyors).toHaveBeenCalledWith({ includeInactive: false });
        expect(element.shadowRoot.textContent).toContain('Bhaiyo Jio');
    });

    it('creating a surveyor refreshes the list', async () => {
        listSurveyors.mockResolvedValue([]);
        createSurveyor.mockResolvedValue({ id: 's9', name: 'New Surveyor', phone: '', isActive: true });

        const element = createElement('c-surveyor-list', { is: SurveyorList });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="fab"]').click();
        await flushPromises();

        const nameInput = element.shadowRoot.querySelector('[data-id="new-name"]');
        nameInput.value = 'New Surveyor';
        nameInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="save"]').click();
        await flushPromises();

        expect(createSurveyor).toHaveBeenCalledWith({ name: 'New Surveyor', phone: '' });
        expect(listSurveyors).toHaveBeenCalledTimes(2);
    });

    it('toggling a surveyor active switch calls setSurveyorActive', async () => {
        listSurveyors.mockResolvedValue([{ id: 's1', name: 'Bhaiyo Jio', phone: '', isActive: true }]);
        setSurveyorActive.mockResolvedValue();

        const element = createElement('c-surveyor-list', { is: SurveyorList });
        document.body.appendChild(element);
        await flushPromises();

        const toggle = element.shadowRoot.querySelector('lightning-input[data-id="s1"]');
        toggle.checked = false;
        toggle.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(setSurveyorActive).toHaveBeenCalledWith({ surveyorId: 's1', active: false });
    });
});
