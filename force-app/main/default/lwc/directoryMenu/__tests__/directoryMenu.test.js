import { createElement } from 'lwc';
import DirectoryMenu from 'c/directoryMenu';

describe('c-directory-menu', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders Mechanics, Surveyors, and Bill-To Parties cards', () => {
        const element = createElement('c-directory-menu', { is: DirectoryMenu });
        document.body.appendChild(element);

        expect(element.shadowRoot.textContent).toContain('Mechanics');
        expect(element.shadowRoot.textContent).toContain('Surveyors');
        expect(element.shadowRoot.textContent).toContain('Bill-To Parties');
    });
});
