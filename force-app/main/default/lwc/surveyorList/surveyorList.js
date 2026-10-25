import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import listSurveyors from '@salesforce/apex/DirectoryController.listSurveyors';
import createSurveyor from '@salesforce/apex/DirectoryController.createSurveyor';
import setSurveyorActive from '@salesforce/apex/DirectoryController.setSurveyorActive';

export default class SurveyorList extends LightningElement {
    @track people = [];

    showInactive = false;
    isLoading = true;

    showCreateForm = false;
    newName = '';
    newPhone = '';
    isSaving = false;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadPeople();
    }

    loadPeople() {
        this.isLoading = true;
        return listSurveyors({ includeInactive: this.showInactive })
            .then((results) => {
                this.people = results;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasPeople() {
        return this.people.length > 0;
    }

    handleToggleShowInactive(event) {
        this.showInactive = event.target.checked;
        this.loadPeople();
    }

    handleToggleCreateForm() {
        this.showCreateForm = !this.showCreateForm;
        if (!this.showCreateForm) {
            this.newName = '';
            this.newPhone = '';
        }
    }

    handleNameChange(event) {
        this.newName = event.target.value;
    }

    handlePhoneChange(event) {
        this.newPhone = event.target.value;
    }

    get canSave() {
        return !!this.newName && !this.isSaving;
    }

    get saveDisabled() {
        return !this.canSave;
    }

    handleSave() {
        if (!this.canSave) {
            return;
        }
        this.isSaving = true;
        createSurveyor({ name: this.newName, phone: this.newPhone })
            .then(() => {
                this.showToast('Surveyor added', '', 'success');
                this.showCreateForm = false;
                this.newName = '';
                this.newPhone = '';
                return this.loadPeople();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleToggleActive(event) {
        const id = event.target.dataset.id;
        const active = event.target.checked;
        setSurveyorActive({ surveyorId: id, active })
            .then(() => this.loadPeople())
            .catch((error) => this.showError(error));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message =
            (error && error.body && error.body.message) ||
            (error && error.message) ||
            'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
