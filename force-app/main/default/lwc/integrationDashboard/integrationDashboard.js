import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class IntegrationDashboard extends LightningElement {
    @track selectedTimeRange = '24h';
    @track activeTab = 'dashboard';

    get timeRangeOptions() {
        return [
            { label: 'Last 1 Hour', value: '1h' },
            { label: 'Last 6 Hours', value: '6h' },
            { label: 'Last 24 Hours', value: '24h' },
            { label: 'Last 7 Days', value: '7d' },
            { label: 'Last 30 Days', value: '30d' }
        ];
    }

    handleTimeRangeChange(event) {
        this.selectedTimeRange = event.detail.value;
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    @api
    refresh() {
        this.handleRefreshAll();
    }

    handleRefreshAll() {
        // Dispatch refresh events to all child components
        this.template.querySelectorAll(
            'c-integration-monitor-cards, c-integration-log-viewer, c-integration-error-panel, c-integration-endpoint-list'
        ).forEach(child => {
            if (child.refresh && typeof child.refresh === 'function') {
                child.refresh();
            }
        });

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Refreshed',
                message: 'Dashboard data has been refreshed.',
                variant: 'success'
            })
        );
    }

    handleOpenSettings() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Settings',
                message: 'Settings panel is not yet implemented.',
                variant: 'info'
            })
        );
    }

    handleMetricClick(event) {
        const metricType = event.detail.metric;
        const tabMapping = {
            totalIntegrations: 'endpoints',
            successRate: 'logs',
            avgResponseTime: 'logs',
            activeErrors: 'errors',
            failedLast24h: 'errors'
        };

        if (tabMapping[metricType]) {
            this.activeTab = tabMapping[metricType];
        }
    }

    handleViewEndpointLogs(event) {
        this.activeTab = 'logs';
        // Allow tab render then set filter
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const logViewer = this.template.querySelector('c-integration-log-viewer:not([compact-mode])');
            if (logViewer && logViewer.setIntegrationKeyFilter) {
                logViewer.setIntegrationKeyFilter(event.detail.integrationKey);
            }
        }, 200);
    }

    handleTestEndpoint(event) {
        this.activeTab = 'test';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const testConsole = this.template.querySelector('c-integration-test-console');
            if (testConsole && testConsole.setEndpoint) {
                testConsole.setEndpoint(event.detail.endpointId);
            }
        }, 200);
    }
}