import { LightningElement, wire, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { updateRecord } from 'lightning/uiRecordApi';
import getEndpointHealth from '@salesforce/apex/IntegrationDashboardController.getEndpointHealth';

const COLUMNS = [
    {
        label: 'Name',
        fieldName: 'nameUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_blank' },
        sortable: true
    },
    { label: 'Integration Key', fieldName: 'Integration_Key__c', type: 'text', sortable: true },
    { label: 'Base URL', fieldName: 'Base_URL__c', type: 'text', sortable: true },
    {
        label: 'HTTP Method',
        fieldName: 'HTTP_Method__c',
        type: 'text',
        sortable: true,
        cellAttributes: { class: { fieldName: 'methodClass' } }
    },
    {
        label: 'Active',
        fieldName: 'Active__c',
        type: 'boolean',
        sortable: true
    },
    { label: 'Category', fieldName: 'Category__c', type: 'text', sortable: true },
    {
        label: 'Execution Mode',
        fieldName: 'Execution_Mode__c',
        type: 'text',
        sortable: true
    },
    { label: 'Owner Team', fieldName: 'Owner_Team__c', type: 'text', sortable: true },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Clone', name: 'clone' },
                { label: 'Activate/Deactivate', name: 'toggle_active' },
                { label: 'View Logs', name: 'view_logs' },
                { label: 'Test', name: 'test' }
            ]
        }
    }
];

export default class IntegrationEndpointList extends LightningElement {
    @track endpoints = [];
    @track filteredEndpoints = [];
    @track isLoading = true;
    @track searchKeyword = '';
    @track selectedCategory = '';
    @track selectedStatus = '';
    @track sortedBy = 'Name';
    @track sortedDirection = 'asc';
    @track showEndpointForm = false;
    @track selectedEndpointId = null;
    @track isCloneMode = false;

    columns = COLUMNS;
    wiredEndpointResult;

    get categoryOptions() {
        const categories = new Set();
        if (this.endpoints) {
            this.endpoints.forEach(ep => {
                if (ep.Category__c) {
                    categories.add(ep.Category__c);
                }
            });
        }
        const options = [{ label: 'All Categories', value: '' }];
        categories.forEach(cat => {
            options.push({ label: cat, value: cat });
        });
        return options;
    }

    get statusOptions() {
        return [
            { label: 'All Statuses', value: '' },
            { label: 'Active', value: 'active' },
            { label: 'Inactive', value: 'inactive' }
        ];
    }

    get hasRecords() {
        return this.filteredEndpoints && this.filteredEndpoints.length > 0;
    }

    get filteredRecordCount() {
        return this.filteredEndpoints ? this.filteredEndpoints.length : 0;
    }

    get totalRecordCount() {
        return this.endpoints ? this.endpoints.length : 0;
    }

    @wire(getEndpointHealth)
    wiredEndpoints(result) {
        this.wiredEndpointResult = result;
        this.isLoading = true;
        if (result.data) {
            this.endpoints = result.data.map(ep => ({
                ...ep,
                nameUrl: '/' + ep.Id,
                methodClass: this.getMethodClass(ep.HTTP_Method__c)
            }));
            this.applyFilters();
            this.isLoading = false;
        } else if (result.error) {
            this.handleError(result.error);
            this.isLoading = false;
        }
    }

    getMethodClass(method) {
        const classMap = {
            GET: 'slds-text-color_success',
            POST: 'slds-text-color_default',
            PUT: 'slds-text-color_weak',
            PATCH: 'slds-text-color_weak',
            DELETE: 'slds-text-color_error'
        };
        return classMap[method] || '';
    }

    handleSearchChange(event) {
        this.searchKeyword = event.target.value;
        this.applyFilters();
    }

    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value;
        this.applyFilters();
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
        this.applyFilters();
    }

    handleClearFilters() {
        this.searchKeyword = '';
        this.selectedCategory = '';
        this.selectedStatus = '';
        this.applyFilters();
    }

    applyFilters() {
        if (!this.endpoints) {
            this.filteredEndpoints = [];
            return;
        }

        let result = [...this.endpoints];

        // Keyword search
        if (this.searchKeyword) {
            const keyword = this.searchKeyword.toLowerCase();
            result = result.filter(ep =>
                (ep.Name && ep.Name.toLowerCase().includes(keyword)) ||
                (ep.Integration_Key__c && ep.Integration_Key__c.toLowerCase().includes(keyword)) ||
                (ep.Base_URL__c && ep.Base_URL__c.toLowerCase().includes(keyword)) ||
                (ep.Description__c && ep.Description__c.toLowerCase().includes(keyword))
            );
        }

        // Category filter
        if (this.selectedCategory) {
            result = result.filter(ep => ep.Category__c === this.selectedCategory);
        }

        // Status filter
        if (this.selectedStatus) {
            const isActive = this.selectedStatus === 'active';
            result = result.filter(ep => ep.Active__c === isActive);
        }

        this.filteredEndpoints = result;
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;

        const fieldName = this.sortedBy === 'nameUrl' ? 'Name' : this.sortedBy;
        const isReverse = this.sortedDirection === 'desc' ? -1 : 1;

        this.filteredEndpoints = [...this.filteredEndpoints].sort((a, b) => {
            const valA = a[fieldName] || '';
            const valB = b[fieldName] || '';
            if (typeof valA === 'string') {
                return isReverse * valA.localeCompare(valB);
            }
            return isReverse * ((valA > valB) - (valB > valA));
        });
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'edit':
                this.handleEditEndpoint(row.Id);
                break;
            case 'clone':
                this.handleCloneEndpoint(row.Id);
                break;
            case 'toggle_active':
                this.handleToggleActive(row);
                break;
            case 'view_logs':
                this.handleViewLogs(row);
                break;
            case 'test':
                this.handleTest(row);
                break;
            default:
                break;
        }
    }

    handleNewEndpoint() {
        this.selectedEndpointId = null;
        this.isCloneMode = false;
        this.showEndpointForm = true;
    }

    handleEditEndpoint(recordId) {
        this.selectedEndpointId = recordId;
        this.isCloneMode = false;
        this.showEndpointForm = true;
    }

    handleCloneEndpoint(recordId) {
        this.selectedEndpointId = recordId;
        this.isCloneMode = true;
        this.showEndpointForm = true;
    }

    handleToggleActive(row) {
        const fields = {
            Id: row.Id,
            Active__c: !row.Active__c
        };

        updateRecord({ fields })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: `Endpoint ${row.Active__c ? 'deactivated' : 'activated'} successfully.`,
                        variant: 'success'
                    })
                );
                return refreshApex(this.wiredEndpointResult);
            })
            .catch(error => {
                this.handleError(error);
            });
    }

    handleViewLogs(row) {
        this.dispatchEvent(new CustomEvent('viewlogs', {
            detail: {
                integrationKey: row.Integration_Key__c,
                endpointId: row.Id
            }
        }));
    }

    handleTest(row) {
        this.dispatchEvent(new CustomEvent('test', {
            detail: {
                endpointId: row.Id,
                integrationKey: row.Integration_Key__c
            }
        }));
    }

    handleEndpointSaved() {
        this.showEndpointForm = false;
        this.selectedEndpointId = null;
        this.isCloneMode = false;
        refreshApex(this.wiredEndpointResult);

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Endpoint saved successfully.',
                variant: 'success'
            })
        );
    }

    handleFormClose() {
        this.showEndpointForm = false;
        this.selectedEndpointId = null;
        this.isCloneMode = false;
    }

    @api
    refresh() {
        return refreshApex(this.wiredEndpointResult);
    }

    handleError(error) {
        let message = 'An unexpected error occurred.';
        if (error) {
            if (error.body && error.body.message) {
                message = error.body.message;
            } else if (error.message) {
                message = error.message;
            }
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }
}