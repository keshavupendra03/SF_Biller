import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { disablePullToRefresh } from 'c/disablePullToRefresh';
import listStages from '@salesforce/apex/JobStageController.listStages';
import createStage from '@salesforce/apex/JobStageController.createStage';
import renameStage from '@salesforce/apex/JobStageController.renameStage';
import setStageActive from '@salesforce/apex/JobStageController.setStageActive';
import moveStage from '@salesforce/apex/JobStageController.moveStage';

export default class JobStages extends NavigationMixin(LightningElement) {
    @track stages = [];
    isLoading = true;

    editingStageId;
    editingName = '';

    newStageName = '';
    isSavingNewStage = false;

    connectedCallback() {
        disablePullToRefresh(this);
        this.loadStages();
    }

    loadStages() {
        this.isLoading = true;
        return listStages({ includeInactive: true })
            .then((results) => {
                this.stages = results;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    get decoratedStages() {
        return this.stages.map((s, index) => ({
            ...s,
            isEditing: s.id === this.editingStageId,
            isFirst: index === 0,
            isLast: index === this.stages.length - 1
        }));
    }

    get hasStages() {
        return this.stages.length > 0;
    }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Settings_Menu' }
        });
    }

    handleStartEdit(event) {
        const id = event.currentTarget.dataset.id;
        const stage = this.stages.find((s) => s.id === id);
        this.editingStageId = id;
        this.editingName = stage ? stage.name : '';
    }

    handleEditingNameChange(event) {
        this.editingName = event.target.value;
    }

    handleConfirmRename(event) {
        const id = event.currentTarget.dataset.id;
        if (!this.editingName) {
            return;
        }
        renameStage({ stageId: id, name: this.editingName })
            .then(() => {
                this.editingStageId = undefined;
                return this.loadStages();
            })
            .catch((error) => this.showError(error));
    }

    handleToggleActive(event) {
        const id = event.target.dataset.id;
        const active = event.target.checked;
        setStageActive({ stageId: id, active })
            .then(() => this.loadStages())
            .catch((error) => this.showError(error));
    }

    handleMoveUp(event) {
        const id = event.currentTarget.dataset.id;
        moveStage({ stageId: id, moveUp: true })
            .then(() => this.loadStages())
            .catch((error) => this.showError(error));
    }

    handleMoveDown(event) {
        const id = event.currentTarget.dataset.id;
        moveStage({ stageId: id, moveUp: false })
            .then(() => this.loadStages())
            .catch((error) => this.showError(error));
    }

    handleNewStageNameChange(event) {
        this.newStageName = event.target.value;
    }

    get canAddStage() {
        return !!this.newStageName && !this.isSavingNewStage;
    }

    get addStageDisabled() {
        return !this.canAddStage;
    }

    handleAddStage() {
        if (!this.canAddStage) {
            return;
        }
        this.isSavingNewStage = true;
        createStage({ name: this.newStageName })
            .then(() => {
                this.newStageName = '';
                return this.loadStages();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSavingNewStage = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
