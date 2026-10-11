import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const MENU_ITEMS = [
    {
        id: 'reports',
        title: 'Reports',
        description: 'Cash summary, revenue, mechanic job counts',
        icon: 'utility:chart',
        tabApiName: 'standard-report',
        isStandardTab: true
    },
    {
        id: 'directory',
        title: 'Directory',
        description: 'Mechanics, surveyors, bill-to parties',
        icon: 'utility:people',
        tabApiName: 'Directory_Menu'
    },
    {
        id: 'settings',
        title: 'Settings',
        description: 'Workshop profile, job stages',
        icon: 'utility:settings',
        tabApiName: 'Settings_Menu'
    }
];

export default class MoreMenu extends NavigationMixin(LightningElement) {
    menuItems = MENU_ITEMS;

    handleNavigate(event) {
        const id = event.currentTarget.dataset.id;
        const item = MENU_ITEMS.find((i) => i.id === id);
        if (!item) {
            return;
        }
        this[NavigationMixin.Navigate](
            item.isStandardTab
                ? { type: 'standard__objectPage', attributes: { objectApiName: 'Report', actionName: 'home' } }
                : { type: 'standard__navItemPage', attributes: { apiName: item.tabApiName } }
        );
    }
}
