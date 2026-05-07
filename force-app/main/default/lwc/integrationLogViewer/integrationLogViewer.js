import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecentLogs from '@salesforce/apex/IntegrationDashboardController.getRecentLogs';
import getLogDetail from '@salesforce/apex/IntegrationDashboardController.getLogDetail';

const COLUMNS_FULL = [
    {
        label: 'Name',
        fieldName: 'nameUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_blank' },
        sortable: true
    },
    { label: 'Integration Key', fieldName: 'Integration_Key__c', type: 'text', sortable: true },
    { label: 'Direction', fieldName: 'Direction__c', type: 'text', sortable: true },
    {
        label: 'Status Code',
        fieldName: 'Response_Status_Code__c',
        type: 'number',
        sortable: true,
        cellAttributes: {
            class: { fieldName: 'statusCodeClass' }
        }
    },
    {
        label: 'Success',
        fieldName: 'Is_Success__c',
        type: 'boolean',
        sortable: true,
        cellAttributes: {
            iconName: { fieldName: 'successIcon' },
            iconPosition: 'left'
        }
    },
    {
        label: 'Execution Time (ms)',
        fieldName: 'Execution_Time_ms__c',
        type: 'number',
        sortable: true,
        cellAttributes: {
            class: { fieldName: 'executionTimeClass' }
        }
    },
    { label: 'Correlation ID', fieldName: 'Correlation_Id__c', type: 'text', sortable: true },
    {
        label: 'Date',
        fieldName: 'CreatedDate',
        type: 'date',
        sortable: true,
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'View Details', name: 'view_detail' }
            ]
        }
    }
];

const COLUMNS_COMPACT = [
    {
        label: 'Name',
        fieldName: 'nameUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_blank' }
    },
    { label: 'Integration Key', fieldName: 'Integration_Key__c', type: 'text' },
    {
        label: 'Status',
        fieldName: 'Response_Status_Code__c',
        type: 'number',
        cellAttributes: { class: { fieldName: 'statusCodeClass' } }
    },
    {
        label: 'Success',
        fieldName: 'Is_Success__c',
        type: 'boolean'
    },
    {
        label: 'Time (ms)',
        fieldName: 'Execution_Time_ms__c',
        type: 'number'
    },
    {
        label: 'Date',
        fieldName: 'CreatedDate',
        type: 'date',
        typeAttributes: {
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    }
];

const PAGE_SIZE = 25;
const AUTO_REFRESH_INTERVAL = 30; // seconds

export default class IntegrationLogViewer extends LightningElement {
    @api compactMode = false;
    @api limitCount = 0;
    @api timeRange = '24h';

    @track logs = [];
    @track displayedLogs = [];
    @track isLoading = false;
    @track isLoadingDetail = false;
    @track showLogDetail = false;
    @track selectedLog = {};
    @track filterIntegrationKey = '';
    @track filterDirection = '';
    @track filterStatus = '';
    @track filterFromDate = '';
    @track filterToDate = '';
    @track sortedBy = 'CreatedDate';
    @track sortedDirection = 'desc';
    @track currentPage = 1;
    @track isAutoRefreshOn = false;

    autoRefreshTimer;
    autoRefreshInterval = AUTO_REFRESH_INTERVAL;

    get columns() {
        return this.compactMode ? COLUMNS_COMPACT : COLUMNS_FULL;
    }

    get cardTitle() {
        return this.compactMode ? '' : 'Integration Logs';
    }

    get directionOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Inbound', value: 'Inbound' },
            { label: 'Outbound', value: 'Outbound' }
        ];
    }

    get statusFilterOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Success', value: 'success' },
            { label: 'Failure', value: 'failure' }
        ];
    }

    get hasLogs() {
        return this.displayedLogs && this.displayedLogs.length > 0;
    }

    get displayedLogCount() {
        return this.displayedLogs ? this.displayedLogs.length : 0;
    }

    get totalLogCount() {
        return this.logs ? this.logs.length : 0;
    }

    get totalPages() {
        if (this.compactMode) return 1;
        return Math.max(1, Math.ceil(this.filteredLogs.length / PAGE_SIZE));
    }

    get isPreviousDisabled() {
        return this.currentPage <= 1;
    }

    get isNextDisabled() {
        return this.currentPage >= this.totalPages;
    }

    get autoRefreshLabel() {
        return this.isAutoRefreshOn ? 'Auto-Refresh: ON' : 'Auto-Refresh: OFF';
    }

    get autoRefreshIcon() {
        return this.isAutoRefreshOn ? 'utility:pause' : 'utility:play';
    }

    get autoRefreshVariant() {
        return this.isAutoRefreshOn ? 'brand' : 'neutral';
    }

    get successIcon() {
        return this.selectedLog.Is_Success__c ? 'utility:success' : 'utility:error';
    }

    get successAltText() {
        return this.selectedLog.Is_Success__c ? 'Success' : 'Failed';
    }

    get statusCodeBadgeClass() {
        const code = this.selectedLog.Response_Status_Code__c;
        if (code >= 200 && code < 300) return 'slds-theme_success';
        if (code >= 400) return 'slds-theme_error';
        return 'slds-theme_warning';
    }

    _filteredLogs = [];
    get filteredLogs() {
        return this._filteredLogs;
    }

    connectedCallback() {
        this.loadLogs();
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
    }

    loadLogs() {
        this.isLoading = true;
        const limit = this.compactMode ? (this.limitCount || 10) : 500;

        getRecentLogs({ integrationKey: this.filterIntegrationKey || null, limitCount: limit })
            .then(data => {
                this.logs = data.map(log => ({
                    ...log,
                    nameUrl: '/' + log.Id,
                    statusCodeClass: this.getStatusCodeClass(log.Response_Status_Code__c),
                    executionTimeClass: this.getExecutionTimeClass(log.Execution_Time_ms__c),
                    successIcon: log.Is_Success__c ? 'utility:success' : 'utility:error'
                }));
                this.applyFilters();
                this.isLoading = false;
            })
            .catch(error => {
                this.handleError(error);
                this.isLoading = false;
            });
    }

    getStatusCodeClass(statusCode) {
        if (!statusCode) return '';
        if (statusCode >= 200 && statusCode < 300) return 'slds-text-color_success';
        if (statusCode >= 400) return 'slds-text-color_error';
        return 'slds-text-color_weak';
    }

    getExecutionTimeClass(executionTime) {
        if (!executionTime) return '';
        if (executionTime > 10000) return 'slds-text-color_error';
        if (executionTime > 5000) return 'slds-text-color_weak';
        return 'slds-text-color_success';
    }

    applyFilters() {
        let result = [...this.logs];

        // Integration key filter
        if (this.filterIntegrationKey) {
            const keyword = this.filterIntegrationKey.toLowerCase();
            result = result.filter(log =>
                log.Integration_Key__c && log.Integration_Key__c.toLowerCase().includes(keyword)
            );
        }

        // Direction filter
        if (this.filterDirection) {
            result = result.filter(log => log.Direction__c === this.filterDirection);
        }

        // Status filter
        if (this.filterStatus) {
            const isSuccess = this.filterStatus === 'success';
            result = result.filter(log => log.Is_Success__c === isSuccess);
        }

        // Date range filter
        if (this.filterFromDate) {
            const fromDate = new Date(this.filterFromDate);
            result = result.filter(log => new Date(log.CreatedDate) >= fromDate);
        }
        if (this.filterToDate) {
            const toDate = new Date(this.filterToDate);
            toDate.setHours(23, 59, 59, 999);
            result = result.filter(log => new Date(log.CreatedDate) <= toDate);
        }

        this._filteredLogs = result;
        this.paginateLogs();
    }

    paginateLogs() {
        if (this.compactMode) {
            this.displayedLogs = this._filteredLogs.slice(0, this.limitCount || 10);
            return;
        }

        const startIndex = (this.currentPage - 1) * PAGE_SIZE;
        const endIndex = startIndex + PAGE_SIZE;
        this.displayedLogs = this._filteredLogs.slice(startIndex, endIndex);
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;

        const fieldName = this.sortedBy === 'nameUrl' ? 'Name' : this.sortedBy;
        const isReverse = this.sortedDirection === 'desc' ? -1 : 1;

        this._filteredLogs = [...this._filteredLogs].sort((a, b) => {
            const valA = a[fieldName] || '';
            const valB = b[fieldName] || '';
            if (typeof valA === 'string') {
                return isReverse * valA.localeCompare(valB);
            }
            return isReverse * ((valA > valB) - (valB > valA));
        });

        this.currentPage = 1;
        this.paginateLogs();
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        if (action.name === 'view_detail') {
            this.openLogDetail(row);
        }
    }

    openLogDetail(row) {
        this.selectedLog = { ...row };
        this.showLogDetail = true;
        this.isLoadingDetail = true;

        getLogDetail({ logId: row.Id })
            .then(data => {
                this.selectedLog = {
                    ...this.selectedLog,
                    ...data,
                    formattedRequest: this.formatJson(data.Request_Body__c),
                    formattedResponse: this.formatJson(data.Response_Body__c)
                };
                this.isLoadingDetail = false;
            })
            .catch(error => {
                this.handleError(error);
                this.selectedLog.formattedRequest = 'Error loading request details.';
                this.selectedLog.formattedResponse = 'Error loading response details.';
                this.isLoadingDetail = false;
            });
    }

    formatJson(jsonString) {
        if (!jsonString) return '(empty)';
        try {
            const parsed = JSON.parse(jsonString);
            return JSON.stringify(parsed, null, 2);
        } catch (e) {
            return jsonString;
        }
    }

    handleCloseDetail() {
        this.showLogDetail = false;
        this.selectedLog = {};
    }

    // Filter handlers
    handleKeyFilterChange(event) {
        this.filterIntegrationKey = event.target.value;
        this.currentPage = 1;
        this.applyFilters();
    }

    handleDirectionChange(event) {
        this.filterDirection = event.detail.value;
        this.currentPage = 1;
        this.applyFilters();
    }

    handleStatusFilterChange(event) {
        this.filterStatus = event.detail.value;
        this.currentPage = 1;
        this.applyFilters();
    }

    handleFromDateChange(event) {
        this.filterFromDate = event.target.value;
        this.currentPage = 1;
        this.applyFilters();
    }

    handleToDateChange(event) {
        this.filterToDate = event.target.value;
        this.currentPage = 1;
        this.applyFilters();
    }

    handleClearFilters() {
        this.filterIntegrationKey = '';
        this.filterDirection = '';
        this.filterStatus = '';
        this.filterFromDate = '';
        this.filterToDate = '';
        this.currentPage = 1;
        this.applyFilters();
    }

    // Pagination
    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.paginateLogs();
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.paginateLogs();
        }
    }

    // Auto-refresh
    handleToggleAutoRefresh() {
        this.isAutoRefreshOn = !this.isAutoRefreshOn;
        if (this.isAutoRefreshOn) {
            this.startAutoRefresh();
        } else {
            this.stopAutoRefresh();
        }
    }

    startAutoRefresh() {
        this.stopAutoRefresh();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.autoRefreshTimer = setInterval(() => {
            this.loadLogs();
        }, this.autoRefreshInterval * 1000);
    }

    stopAutoRefresh() {
        if (this.autoRefreshTimer) {
            clearInterval(this.autoRefreshTimer);
            this.autoRefreshTimer = null;
        }
    }

    @api
    refresh() {
        this.loadLogs();
    }

    @api
    setIntegrationKeyFilter(integrationKey) {
        this.filterIntegrationKey = integrationKey;
        this.currentPage = 1;
        this.loadLogs();
    }

    handleRefresh() {
        this.loadLogs();
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
                variant: 'error'
            })
        );
    }
}