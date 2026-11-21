import { createElement } from 'lwc';
import DeleteConfirm from 'c/deleteConfirm';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function create(props) {
    const element = createElement('c-delete-confirm', { is: DeleteConfirm });
    Object.assign(element, props);
    const confirmed = jest.fn();
    element.addEventListener('confirm', confirmed);
    document.body.appendChild(element);
    await flushPromises();
    return { element, confirmed };
}

function $(element, selector) {
    return element.shadowRoot.querySelector(selector);
}

describe('c-delete-confirm', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('asks first, in the page, saying what will happen', async () => {
        const { element, confirmed } = await create({ buttonLabel: 'Delete Bill', message: 'Delete INV/1?' });
        expect($(element, '[data-id="delete"]').label).toBe('Delete Bill');
        expect($(element, '[data-id="confirm-panel"]')).toBeNull();

        $(element, '[data-id="delete"]').click();
        await flushPromises();

        expect($(element, '[data-id="confirm-message"]').textContent).toBe('Delete INV/1?');
        expect(confirmed).not.toHaveBeenCalled();
    });

    it('"Keep it" changes nothing; "Yes, delete" tells the screen', async () => {
        const { element, confirmed } = await create({ message: 'Delete?' });
        $(element, '[data-id="delete"]').click();
        await flushPromises();
        $(element, '[data-id="confirm-no"]').click();
        await flushPromises();
        expect($(element, '[data-id="confirm-panel"]')).toBeNull();
        expect(confirmed).not.toHaveBeenCalled();

        $(element, '[data-id="delete"]').click();
        await flushPromises();
        $(element, '[data-id="confirm-yes"]').click();
        await flushPromises();
        expect(confirmed).toHaveBeenCalledTimes(1);
    });

    it('can\'t be pressed while the screen is busy deleting', async () => {
        const { element } = await create({ message: 'Delete?', busy: true });
        expect($(element, '[data-id="delete"]').disabled).toBe(true);
    });
});
