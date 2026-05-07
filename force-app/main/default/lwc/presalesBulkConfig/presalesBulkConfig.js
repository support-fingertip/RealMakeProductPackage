import { LightningElement } from 'lwc';

export default class SalesAdminConsole extends LightningElement {

   activeTab = 'bulk';

handleMenu(event) {
    this.activeTab = event.currentTarget.dataset.name;
}

get bulkClass() {
    return this.activeTab === 'bulk' ? 'nav-item active' : 'nav-item';
}
get approvalClass() {
    return this.activeTab === 'approval' ? 'nav-item active' : 'nav-item';
}
get inventoryClass() {
    return this.activeTab === 'inventory' ? 'nav-item active' : 'nav-item';
}
get forecastClass() {
    return this.activeTab === 'forecast' ? 'nav-item active' : 'nav-item';
}

get isBulk() { return this.activeTab === 'bulk'; }
get isApproval() { return this.activeTab === 'approval'; }
get isInventory() { return this.activeTab === 'inventory'; }
get isForecast() { return this.activeTab === 'forecast'; }
}