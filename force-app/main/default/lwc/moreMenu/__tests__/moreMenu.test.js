import { createElement } from 'lwc';
import MoreMenu from 'c/moreMenu';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-more-menu', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders Reports, Directory, and Settings cards', async () => {
        const element = createElement('c-more-menu', { is: MoreMenu });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Reports');
        expect(element.shadowRoot.textContent).toContain('Directory');
        expect(element.shadowRoot.textContent).toContain('Settings');
        expect(element.shadowRoot.querySelectorAll('[data-id]')).toHaveLength(3);
    });
});
