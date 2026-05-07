import { LightningElement } from 'lwc';

export default class PresalesAdminConfig extends LightningElement {

    activeTab = 'duplication';

    handleMenu(event) {
        this.activeTab = event.currentTarget.dataset.name;
    }

    get dupClass() {
        return this.activeTab === 'duplication' ? 'nav-item active' : 'nav-item';
    }

    get rrClass() {
        return this.activeTab === 'roundRobin' ? 'nav-item active' : 'nav-item';
    }

    get salesClass() {
        return this.activeTab === 'sales' ? 'nav-item active' : 'nav-item';
    }

    get scoreClass() {
        return this.activeTab === 'scoring' ? 'nav-item active' : 'nav-item';
    }

    get integrationClass() {
        return this.activeTab === 'integration' ? 'nav-item active' : 'nav-item';
    }

    get isDup() {
        return this.activeTab === 'duplication';
    }

    get isRR() {
        return this.activeTab === 'roundRobin';
    }

    get isSales() {
        return this.activeTab === 'sales';
    }

    get isScore() {
        return this.activeTab === 'scoring';
    }

    get isIntegration() {
        return this.activeTab === 'integration';
    }
}