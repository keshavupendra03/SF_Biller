import { LightningElement, api } from 'lwc';
import listProfiles from '@salesforce/apex/WorkshopProfileController.listProfiles';

const REMEMBERED_KEY = 'wsBiller.selectedCompany';

function rememberedCompany() {
    try {
        return window.localStorage.getItem(REMEMBERED_KEY);
    } catch (e) {
        return null;
    }
}

function rememberCompany(id) {
    try {
        window.localStorage.setItem(REMEMBERED_KEY, id);
    } catch (e) {
        // Only a convenience: without it the screen starts on the first company.
    }
}

/**
 * Which company this bill, estimate or job slip is for. Shows nothing while
 * there's only one company, so single-company workshops never see it.
 *
 * Starts on the company last chosen on this device. Fires `companychange` with
 * { id, profile } when loaded and on every choice; id and profile are null if
 * no company exists yet (or for "All" with allow-all).
 */
export default class CompanyPicker extends LightningElement {
    // Shows the document's company as plain text, for a saved document's new
    // version, which has to stay with its company.
    @api locked = false;
    // Adds an "All" choice, for filtering lists rather than making a document.
    @api allowAll = false;

    profiles = [];
    _value;
    _isLoaded = false;

    @api
    get value() {
        return this._value;
    }
    set value(id) {
        this._value = id;
        // A form was reset: fall back to the usual starting company.
        if (!id && this._isLoaded && !this.allowAll) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            Promise.resolve().then(() => this.selectStartingCompany());
        }
    }

    connectedCallback() {
        listProfiles()
            .then((profiles) => {
                this.profiles = profiles || [];
                this._isLoaded = true;
                this.selectStartingCompany();
            })
            .catch((error) => {
                this.dispatchEvent(new CustomEvent('companyerror', { detail: { error } }));
            });
    }

    selectStartingCompany() {
        if (this.allowAll) {
            return;
        }
        const has = (id) => this.profiles.some((p) => p.id === id);
        let id = null;
        if (has(this._value)) {
            id = this._value;
        } else if (has(rememberedCompany())) {
            id = rememberedCompany();
        } else if (this.profiles.length) {
            id = this.profiles[0].id;
        }
        this.select(id);
    }

    select(id) {
        this._value = id;
        const profile = this.profiles.find((p) => p.id === id) || null;
        this.dispatchEvent(new CustomEvent('companychange', { detail: { id: profile ? id : null, profile } }));
    }

    get isShown() {
        return this.profiles.length > 1;
    }

    get selectedProfile() {
        return this.profiles.find((p) => p.id === this._value);
    }

    // Nothing selected while the list is filtered to "All".
    get selectedName() {
        const profile = this.selectedProfile;
        return profile ? profile.name : '';
    }

    get selectedGstin() {
        const profile = this.selectedProfile;
        return profile ? profile.gstin : '';
    }

    get showChoices() {
        return !this.locked;
    }

    get choices() {
        const choices = this.profiles.map((p) => ({
            id: p.id,
            label: p.name,
            variant: p.id === this._value ? 'brand' : 'neutral'
        }));
        if (this.allowAll) {
            choices.unshift({ id: '', label: 'All', variant: this._value ? 'neutral' : 'brand' });
        }
        return choices;
    }

    handleChoose(event) {
        const id = event.currentTarget.dataset.value || null;
        if (id && !this.allowAll) {
            rememberCompany(id);
        }
        this.select(id);
    }
}
