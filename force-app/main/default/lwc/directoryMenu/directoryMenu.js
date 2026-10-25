import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { disablePullToRefresh } from 'c/disablePullToRefresh';

const MENU_ITEMS = [
    { id: 'mechanics', title: 'Mechanics', icon: 'utility:wrench', tabApiName: 'Mechanic_List' },
    { id: 'surveyors', title: 'Surveyors', icon: 'utility:checkin', tabApiName: 'Surveyor_List' },
    { id: 'billToParties', title: 'Bill-To Parties', icon: 'utility:company', tabApiName: 'Bill_To_Party_List' }
];

export default class DirectoryMenu extends NavigationMixin(LightningElement) {
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
