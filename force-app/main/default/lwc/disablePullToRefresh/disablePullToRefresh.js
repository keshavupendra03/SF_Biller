/**
 * Turns off the Salesforce Mobile App's native pull-to-refresh gesture for
 * whichever page calls this from its own connectedCallback. Official
 * Salesforce mechanism: firing an `updateScrollSettings` CustomEvent with
 * `isPullToRefreshEnabled: false` in its detail, bubbling/composed so the
 * mobile app's container (listening above the component tree) picks it up.
 * Has no effect outside the Salesforce Mobile App, so it's safe to call
 * unconditionally on every page, including ones used on desktop too.
 *
 * Why every page needs this, not just forms: pulling down while scrolled to
 * the top of ANY screen reloads it and discards whatever state that screen
 * was holding (a form half filled in, a search term, an expanded panel) —
 * not just screens with an obvious save button.
 */
export function disablePullToRefresh(element) {
    element.dispatchEvent(
        new CustomEvent('updateScrollSettings', {
            bubbles: true,
            composed: true,
            detail: { isPullToRefreshEnabled: false }
        })
    );
}
