import { LightningElement, api } from 'lwc';

export default class RrSummaryCard extends LightningElement {
    @api data = {};
    @api teams = {};
    @api filters = [];

    get ruleName() {
        return this.data.Name || 'Untitled Rule';
    }

    get hasFilters() {
        return this.filters && this.filters.length > 0;
    }

    get sortedFilters() {
        if (!this.filters) return [];
        return [...this.filters].sort((a, b) => (a.preferenceOrder || 0) - (b.preferenceOrder || 0));
    }

    get populatedFields() {
        if (!this.data) return [];

        return Object.keys(this.data)
            .filter(key => key !== 'Name' && key !== 'sobjectType' && key !== 'Id' && this.data[key])
            .map(key => ({
                key: key,
                label: key.replace('__c', '').replace(/_/g, ' '),
                value: String(this.data[key])
            }));
    }

    get hasTeams() {
        return this.teamSummary.length > 0;
    }

    get teamSummary() {
        if (!this.teams) return [];

        return Object.keys(this.teams)
            .filter(role => this.teams[role] && this.teams[role].length > 0)
            .map(role => ({
                role: role,
                count: this.teams[role].length
            }));
    }
}