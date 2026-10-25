import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { disablePullToRefresh } from 'c/disablePullToRefresh';

const MENU_ITEMS = [
    { id: 'workshopProfile', title: 'Workshop Profile', icon: 'utility:store', tabApiName: 'Workshop_Profile_Page' },
    { id: 'jobStages', title: 'Job Stages', icon: 'utility:trail', tabApiName: 'Job_Stages_Page' }
];

export default class SettingsMenu extends NavigationMixin(LightningElement) {
    menuItems = MENU_ITEMS;

    connectedCallback() {
        disablePullToRefresh(this);
    }

    handleNavigate(event) {
        const id = event.currentTarget.dataset.id;
        const item = MENU_ITEMS.find((i) => i.id === id);
        if (!item) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: item.tabApiName }
        });
    }
}
