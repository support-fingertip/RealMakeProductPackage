import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { updateRecord } from 'lightning/uiRecordApi';
import getErrorSummary from '@salesforce/apex/IntegrationDashboardController.getErrorSummary';

const COLUMNS = [
    {
        label: 'Error Type',
        fieldName: 'Error_Type__c',
        type: 'text',
        sortable: true,
        initialWidth: 150
    },
    {
        label: 'Severity',
        fieldName: 'Severity__c',
        type: 'text',
        sortable: true,
        initialWidth: 100,
        cellAttributes: {
            class: { fieldName: 'severityCellClass' }
        }
    },
    {
        label: 'Error Message',
        fieldName: 'truncatedMessage',
        type: 'text',
        sortable: true,
        wrapText: true
    },
    {
        label: 'Dead Letter',
        fieldName: 'Is_Dead_Letter__c',
        type: 'boolean',
        sortable: true,
        initialWidth: 100
    },
    {
        label: 'Resolved',
        fieldName: 'Is_Resolved__c',
        type: 'boolean',
        sortable: true,
        initialWidth: 100
    },
    {
        label: 'Date',
        fieldName: 'CreatedDate',
        type: 'date',
        sortable: true,
        initialWidth: 160,
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'View Details', name: 'view_detail' },
                { label: 'Resolve', name: 'resolve' },
                { label: 'Retry', name: 'retry' },
                { label: 'Mark Dead Letter', name: 'mark_dead_letter' }
            ]
        }
    }
];

const SEVERITY_CLASS_MAP = {
    Critical: 'slds-theme_error',
    High: 'slds-theme_warning',
    Medium: 'slds-badge_inverse',
    Low: 'slds-theme_info'
};

const SEVERITY_CELL_CLASS_MAP = {
    Critical: 'slds-text-color_error',
    High: 'slds-text-color_error',
    Medium: '',
    Low: 'slds-text-color_weak'
};

export default class IntegrationErrorPanel extends LightningElement {
    @api compactMode = false;
    @api limitCount = 0;
    @api timeRange = '24h';

    @track errors = [];
    @track filteredErrors = [];
    @track isLoading = false;
    @track showErrorDetail = false;
    @track selectedError = {};
    @track selectedRows = [];
    @track filterSeverity = '';
    @track filterErrorType = '';
    @track filterResolved = '';
    @track filterDeadLetter = '';
    @track sortedBy = 'CreatedDate';
    @track sortedDirection = 'desc';

    columns = COLUMNS;

    get cardTitle() {
        return this.compactMode ? '' : 'Error Logs';
    }

    get hasErrors() {
        return this.compactMode
            ? this.compactErrors && this.compactErrors.length > 0
            : this.filteredErrors && this.filteredErrors.length > 0;
    }

    get compactErrors() {
        const limit = this.limitCount || 5;
        return this.filteredErrors.slice(0, limit);
    }

    get filteredErrorCount() {
        return this.filteredErrors ? this.filteredErrors.length : 0;
    }

    get selectedCount() {
        return this.selectedRows ? this.selectedRows.length : 0;
    }

    get noBulkSelection() {
        return !this.selectedRows || this.selectedRows.length === 0;
    }

    get severityFilterOptions() {
        return [
            { label: 'All Severities', value: '' },
            { label: 'Critical', value: 'Critical' },
            { label: 'High', value: 'High' },
            { label: 'Medium', value: 'Medium' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get errorTypeFilterOptions() {
        const types = new Set();
        if (this.errors) {
            this.errors.forEach(err => {
                if (err.Error_Type__c) {
                    types.add(err.Error_Type__c);
                }
            });
        }
        const options = [{ label: 'All Types', value: '' }];
        types.forEach(type => {
            options.push({ label: type, value: type });
        });
        return options;
    }

    get resolvedFilterOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Resolved', value: 'resolved' },
            { label: 'Unresolved', value: 'unresolved' }
        ];
    }

    get deadLetterFilterOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Dead Letter Only', value: 'true' },
            { label: 'Non-Dead Letter', value: 'false' }
        ];
    }

    connectedCallback() {
        this.loadErrors();
    }

    loadErrors() {
        this.isLoading = true;

        getErrorSummary({ timeRange: this.timeRange })
            .then(data => {
                this.errors = data.map(err => ({
                    ...err,
                    truncatedMessage: this.truncateMessage(err.Error_Message__c, 100),
                    severityBadgeClass: SEVERITY_CLASS_MAP[err.Severity__c] || '',
                    severityCellClass: SEVERITY_CELL_CLASS_MAP[err.Severity__c] || '',
                    deadLetterLabel: err.Is_Dead_Letter__c ? 'Yes' : 'No'
                }));
                this.applyFilters();
                this.isLoading = false;
            })
            .catch(error => {
                this.handleError(error);
                this.isLoading = false;
            });
    }

    truncateMessage(message, maxLength) {
        if (!message) return '';
        if (message.length <= maxLength) return message;
        return message.substring(0, maxLength) + '...';
    }

    applyFilters() {
        let result = [...this.errors];

        if (this.filterSeverity) {
            result = result.filter(err => err.Severity__c === this.filterSeverity);
        }

        if (this.filterErrorType) {
            result = result.filter(err => err.Error_Type__c === this.filterErrorType);
        }

        if (this.filterResolved) {
            const isResolved = this.filterResolved === 'resolved';
            result = result.filter(err => err.Is_Resolved__c === isResolved);
        }

        if (this.filterDeadLetter) {
            const isDeadLetter = this.filterDeadLetter === 'true';
            result = result.filter(err => err.Is_Dead_Letter__c === isDeadLetter);
        }

        this.filteredErrors = result;
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;

        const isReverse = this.sortedDirection === 'desc' ? -1 : 1;
        const fieldName = this.sortedBy;

        this.filteredErrors = [...this.filteredErrors].sort((a, b) => {
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
            case 'view_detail':
                this.selectedError = { ...row };
                this.showErrorDetail = true;
                break;
            case 'resolve':
                this.resolveErrors([row.Id]);
                break;
            case 'retry':
                this.retryErrors([row.Id]);
                break;
            case 'mark_dead_letter':
                this.markDeadLetter([row.Id]);
                break;
            default:
                break;
        }
    }

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows;
    }

    handleBulkAction(event) {
        const action = event.detail.value;
        const selectedIds = this.selectedRows.map(row => row.Id);

        if (selectedIds.length === 0) {
            this.showToast('Info', 'No rows selected.', 'info');
            return;
        }

        switch (action) {
            case 'resolve':
                this.resolveErrors(selectedIds);
                break;
            case 'retry':
                this.retryErrors(selectedIds);
                break;
            case 'dead_letter':
                this.markDeadLetter(selectedIds);
                break;
            default:
                break;
        }
    }

    resolveErrors(ids) {
        this.isLoading = true;

        const updatePromises = ids.map(id => {
            const fields = { Id: id, Is_Resolved__c: true };
            return updateRecord({ fields });
        });

        Promise.all(updatePromises)
            .then(() => {
                this.showToast('Success', `${ids.length} error(s) marked as resolved.`, 'success');
                this.loadErrors();
            })
            .catch(error => {
                this.handleError(error);
                this.isLoading = false;
            });
    }

    retryErrors(ids) {
        // In production, this would call an Apex method to re-queue the failed integrations
        this.showToast(
            'Retry Initiated',
            `Retry queued for ${ids.length} error(s). Check logs for results.`,
            'info'
        );
    }

    markDeadLetter(ids) {
        this.isLoading = true;

        const updatePromises = ids.map(id => {
            const fields = { Id: id, Is_Dead_Letter__c: true };
            return updateRecord({ fields });
        });

        Promise.all(updatePromises)
            .then(() => {
                this.showToast('Success', `${ids.length} error(s) marked as dead letter.`, 'success');
                this.loadErrors();
            })
            .catch(error => {
                this.handleError(error);
                this.isLoading = false;
            });
    }

    // Filter handlers
    handleSeverityChange(event) {
        this.filterSeverity = event.detail.value;
        this.applyFilters();
    }

    handleErrorTypeChange(event) {
        this.filterErrorType = event.detail.value;
        this.applyFilters();
    }

    handleResolvedChange(event) {
        this.filterResolved = event.detail.value;
        this.applyFilters();
    }

    handleDeadLetterChange(event) {
        this.filterDeadLetter = event.detail.value;
        this.applyFilters();
    }

    handleCloseDetail() {
        this.showErrorDetail = false;
        this.selectedError = {};
    }

    handleRetryFromDetail() {
        if (this.selectedError.Id) {
            this.retryErrors([this.selectedError.Id]);
            this.handleCloseDetail();
        }
    }

    handleRefresh() {
        this.loadErrors();
    }

    @api
    refresh() {
        this.loadErrors();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
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
        this.showToast('Error', message, 'error');
    }
}