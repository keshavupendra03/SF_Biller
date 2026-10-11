import { LightningElement, api } from 'lwc';
import searchMakes from '@salesforce/apex/VehicleMakeModelController.searchMakes';
import searchModels from '@salesforce/apex/VehicleMakeModelController.searchModels';

export default class VehicleMakeModelField extends LightningElement {
    @api label;
    @api source = 'make'; // 'make' | 'model'
    @api make = '';

    _value = '';
    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val || '';
    }

    suggestions = [];
    showSuggestions = false;

    get hasSuggestions() {
        return this.showSuggestions && this.suggestions.length > 0;
    }

    handleChange(event) {
        this._value = event.target.value;
        this.search(this._value);
        this.emitChange();
    }

    handleFocus() {
        this.search(this._value);
    }

    handleBlur() {
        this.showSuggestions = false;
    }

    search(term) {
        const request =
            this.source === 'model' ? searchModels({ make: this.make, term }) : searchMakes({ term });
        request
            .then((results) => {
                this.suggestions = results || [];
                this.showSuggestions = this.suggestions.length > 0;
            })
            .catch(() => {
                this.suggestions = [];
                this.showSuggestions = false;
            });
    }

    handleSelectMouseDown(event) {
        // Keeps focus on the input (suppresses the default blur a mousedown
        // on a sibling button would otherwise cause) so the suggestion list
        // is still rendered when the selection below runs.
        event.preventDefault();
        this._value = event.currentTarget.dataset.value;
        this.showSuggestions = false;
        this.emitChange();
    }

    emitChange() {
        this.dispatchEvent(new CustomEvent('change', { detail: { value: this._value } }));
    }
}
