import { LightningElement, api, track, wire } from 'lwc';
import { gql, graphql } from 'lightning/graphql';

export default class UnitLookup extends LightningElement {
    @api label = 'Unit';
    @api required = false;
    @api disabled = false;
    @api helpText;
    @api
    get projectId() {
        return this._projectId;
    }
    set projectId(val) {
        this._projectId = val;
        // Clear options when project changes
        if (!val) {
            this.options = [];
            this.value = undefined;
        }
    }

    @track options = [];
    @track value;
    @track isLoading = false;

    _projectId;

    get graphqlQuery() {
        if (!this._projectId) {
            return undefined;
        }
        return gql`
            query UnitsByProject($projectId: ID!) {
                uiapi {
                    query {
                        Unit__c(where: { Project__c: { eq: $projectId } }, first: 200, orderBy: { Name: { order: ASC } }) {
                            edges {
                                node {
                                    Id
                                    Name {
                                        value
                                    }
                                }
                            }
                        }
                    }
                }
            }
        `;
    }

    get graphqlVariables() {
        return { projectId: this._projectId };
    }

    @wire(graphql, { query: '$graphqlQuery', variables: '$graphqlVariables' })
    wiredUnits({ data, error }) {
        this.isLoading = false;
        if (data) {
            const records = data?.uiapi?.query?.Unit__c?.edges?.map(e => e.node) || [];
            this.options = records.map(r => ({
                label: r.Name?.value,
                value: r.Id
            }));
            // Clear selection when project changes
            this.value = undefined;
            this.dispatchEvent(new CustomEvent('unitselect', { detail: { unitId: null, unitName: null } }));
        } else if (error) {
            this.options = [];
            this.value = undefined;
        }
    }

    handleChange(event) {
        this.value = event.detail.value;
        const selected = this.options.find(o => o.value === this.value);
        this.dispatchEvent(
            new CustomEvent('unitselect', {
                detail: { unitId: this.value, unitName: selected ? selected.label : null },
                bubbles: true,
                composed: true
            })
        );
    }

    @api
    clearSelection() {
        this.value = undefined;
        const combobox = this.template.querySelector('[data-id="unitCombobox"]');
        if (combobox) {
            combobox.value = undefined;
        }
        this.dispatchEvent(new CustomEvent('unitselect', { detail: { unitId: null, unitName: null } }));
    }
}