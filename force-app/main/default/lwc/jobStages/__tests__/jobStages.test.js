import { createElement } from 'lwc';
import JobStages from 'c/jobStages';
import listStages from '@salesforce/apex/JobStageController.listStages';
import createStage from '@salesforce/apex/JobStageController.createStage';
import moveStage from '@salesforce/apex/JobStageController.moveStage';

jest.mock('@salesforce/apex/JobStageController.listStages', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobStageController.createStage', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobStageController.renameStage', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobStageController.setStageActive', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/JobStageController.moveStage', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-job-stages', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders stages with the first row unable to move up', async () => {
        listStages.mockResolvedValue([
            { id: 's1', name: 'vehicle recieved', sortOrder: 1, isActive: true },
            { id: 's2', name: 'work started', sortOrder: 2, isActive: true }
        ]);

        const element = createElement('c-job-stages', { is: JobStages });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('vehicle recieved');
        const upButtons = element.shadowRoot.querySelectorAll('[data-action="up"]');
        expect(upButtons[0].disabled).toBe(true);
        expect(upButtons[1].disabled).toBe(false);
    });

    it('moving a stage down calls moveStage with moveUp false', async () => {
        listStages.mockResolvedValue([
            { id: 's1', name: 'vehicle recieved', sortOrder: 1, isActive: true },
            { id: 's2', name: 'work started', sortOrder: 2, isActive: true }
        ]);
        moveStage.mockResolvedValue();

        const element = createElement('c-job-stages', { is: JobStages });
        document.body.appendChild(element);
        await flushPromises();

        const downButtons = element.shadowRoot.querySelectorAll('[data-action="down"]');
        downButtons[0].click();
        await flushPromises();

        expect(moveStage).toHaveBeenCalledWith({ stageId: 's1', moveUp: false });
    });

    it('adding a stage calls createStage and refreshes the list', async () => {
        listStages.mockResolvedValue([]);
        createStage.mockResolvedValue({ id: 's9', name: 'Quality Check', sortOrder: 1, isActive: true });

        const element = createElement('c-job-stages', { is: JobStages });
        document.body.appendChild(element);
        await flushPromises();

        const input = element.shadowRoot.querySelector('[data-id="new-stage-name"]');
        input.value = 'Quality Check';
        input.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="add-stage"]').click();
        await flushPromises();

        expect(createStage).toHaveBeenCalledWith({ name: 'Quality Check' });
        expect(listStages).toHaveBeenCalledTimes(2);
    });
});
