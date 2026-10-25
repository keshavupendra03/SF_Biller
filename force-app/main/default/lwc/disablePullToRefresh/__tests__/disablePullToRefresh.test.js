import { disablePullToRefresh } from 'c/disablePullToRefresh';

describe('c/disablePullToRefresh', () => {
    it('dispatches a bubbling, composed updateScrollSettings event with isPullToRefreshEnabled false', () => {
        const element = document.createElement('div');
        const handler = jest.fn();
        element.addEventListener('updateScrollSettings', handler);

        disablePullToRefresh(element);

        expect(handler).toHaveBeenCalledTimes(1);
        const event = handler.mock.calls[0][0];
        expect(event.detail).toEqual({ isPullToRefreshEnabled: false });
        expect(event.bubbles).toBe(true);
        expect(event.composed).toBe(true);
    });
});
