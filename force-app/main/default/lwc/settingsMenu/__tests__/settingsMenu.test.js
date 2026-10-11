import { createElement } from 'lwc';
import SettingsMenu from 'c/settingsMenu';

describe('c-settings-menu', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders Workshop Profile and Job Stages cards', () => {
        const element = createElement('c-settings-menu', { is: SettingsMenu });
        document.body.appendChild(element);

        expect(element.shadowRoot.textContent).toContain('Workshop Profile');
        expect(element.shadowRoot.textContent).toContain('Job Stages');
    });
});
