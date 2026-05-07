import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLogSummary from '@salesforce/apex/IntegrationDashboardController.getLogSummary';
import getEndpointHealth from '@salesforce/apex/IntegrationDashboardController.getEndpointHealth';
import getErrorSummary from '@salesforce/apex/IntegrationDashboardController.getErrorSummary';

const TIME_RANGE_MAP = {
    '1h': 'Last1Hour',
    '6h': 'Last6Hours',
    '24h': 'Last24Hours',
    '7d': 'Last7Days',
    '30d': 'Last30Days'
};

export default class IntegrationMonitorCards extends LightningElement {
    @api timeRange = '24h';

    @track isLoading = false;
    @track totalIntegrations = 0;
    @track successRate = 0;
    @track avgResponseTime = 0;
    @track activeErrors = 0;
    @track failedLast24h = 0;
    @track totalCalls = 0;

    connectedCallback() {
        this.loadMetrics();
    }

    loadMetrics() {
        this.isLoading = true;
        const apexTimeRange = TIME_RANGE_MAP[this.timeRange] || 'Last24Hours';

        Promise.all([
            getLogSummary({ timeRange: apexTimeRange }),
            getEndpointHealth(),
            getErrorSummary({ timeRange: apexTimeRange })
        ])
            .then(([logSummaryData, endpointHealthData, errorSummaryData]) => {
                this.processLogSummary(logSummaryData);
                this.processEndpointHealth(endpointHealthData);
                this.processErrorSummary(errorSummaryData);
                this.isLoading = false;
            })
            .catch(error => {
                this.handleError(error);
                this.isLoading = false;
            });
    }

    processLogSummary(data) {
        if (!data || data.length === 0) {
            this.totalCalls = 0;
            this.successRate = 0;
            this.failedLast24h = 0;
            return;
        }

        let totalCount = 0;
        let successCount = 0;

        data.forEach(summary => {
            totalCount += summary.totalCount || 0;
            successCount += summary.successCount || 0;
        });

        this.totalCalls = totalCount;
        this.successRate = totalCount > 0
            ? ((successCount / totalCount) * 100)
            : 0;
        this.failedLast24h = totalCount - successCount;
    }

    processEndpointHealth(data) {
        if (!data || data.length === 0) {
            this.totalIntegrations = 0;
            this.avgResponseTime = 0;
            return;
        }

        this.totalIntegrations = data.length;

        let totalAvgTime = 0;
        let endpointsWithData = 0;

        data.forEach(ep => {
            if (ep.avgResponseTimeMs && ep.avgResponseTimeMs > 0) {
                totalAvgTime += ep.avgResponseTimeMs;
                endpointsWithData++;
            }
        });

        this.avgResponseTime = endpointsWithData > 0
            ? (totalAvgTime / endpointsWithData)
            : 0;
    }

    processErrorSummary(data) {
        if (!data || data.length === 0) {
            this.activeErrors = 0;
            return;
        }

        let totalErrors = 0;
        data.forEach(summary => {
            totalErrors += summary.errorCount || 0;
        });

        this.activeErrors = totalErrors;
    }

    // --- Computed display properties ---

    get formattedSuccessRate() {
        return this.successRate.toFixed(1);
    }

    get formattedAvgResponseTime() {
        if (this.avgResponseTime >= 1000) {
            return (this.avgResponseTime / 1000).toFixed(1) + 's';
        }
        return Math.round(this.avgResponseTime) + 'ms';
    }

    // --- Success Rate styling ---

    get successRateClass() {
        const base = 'slds-text-heading_large slds-m-top_x-small';
        if (this.successRate >= 99) return base + ' slds-text-color_success';
        if (this.successRate >= 95) return base;
        if (this.successRate >= 80) return base + ' slds-text-color_weak';
        return base + ' slds-text-color_error';
    }

    get successRateIcon() {
        if (this.successRate >= 95) return 'utility:success';
        if (this.successRate >= 80) return 'utility:warning';
        return 'utility:error';
    }

    get successRateIconClass() {
        if (this.successRate >= 95) return 'slds-icon-text-success slds-m-bottom_x-small';
        if (this.successRate >= 80) return 'slds-icon-text-warning slds-m-bottom_x-small';
        return 'slds-icon-text-error slds-m-bottom_x-small';
    }

    get successRateVariant() {
        if (this.successRate >= 95) return 'base';
        return 'warning';
    }

    // --- Response Time styling ---

    get avgResponseTimeClass() {
        const base = 'slds-text-heading_large slds-m-top_x-small';
        if (this.avgResponseTime < 2000) return base + ' slds-text-color_success';
        if (this.avgResponseTime < 5000) return base + ' slds-text-color_weak';
        return base + ' slds-text-color_error';
    }

    get responseTimeIconClass() {
        if (this.avgResponseTime < 2000) return 'slds-icon-text-success slds-m-bottom_x-small';
        if (this.avgResponseTime < 5000) return 'slds-icon-text-warning slds-m-bottom_x-small';
        return 'slds-icon-text-error slds-m-bottom_x-small';
    }

    // --- Active Errors styling ---

    get activeErrorsClass() {
        const base = 'slds-text-heading_large slds-m-top_x-small';
        if (this.activeErrors === 0) return base + ' slds-text-color_success';
        if (this.activeErrors <= 5) return base + ' slds-text-color_weak';
        return base + ' slds-text-color_error';
    }

    get activeErrorsIconClass() {
        if (this.activeErrors === 0) return 'slds-icon-text-success slds-m-bottom_x-small';
        if (this.activeErrors <= 5) return 'slds-icon-text-warning slds-m-bottom_x-small';
        return 'slds-icon-text-error slds-m-bottom_x-small';
    }

    // --- Failed Last 24h styling ---

    get failedLast24hClass() {
        const base = 'slds-text-heading_large slds-m-top_x-small';
        if (this.failedLast24h === 0) return base + ' slds-text-color_success';
        if (this.failedLast24h <= 10) return base + ' slds-text-color_weak';
        return base + ' slds-text-color_error';
    }

    get failedIconClass() {
        if (this.failedLast24h === 0) return 'slds-icon-text-success slds-m-bottom_x-small';
        if (this.failedLast24h <= 10) return 'slds-icon-text-warning slds-m-bottom_x-small';
        return 'slds-icon-text-error slds-m-bottom_x-small';
    }

    // --- System Health computed ---

    get healthStatus() {
        if (this.activeErrors === 0 && this.successRate >= 99) return 'Healthy';
        if (this.activeErrors <= 5 && this.successRate >= 90) return 'Degraded';
        return 'Unhealthy';
    }

    get healthIcon() {
        const status = this.healthStatus;
        if (status === 'Healthy') return 'utility:like';
        if (status === 'Degraded') return 'utility:warning';
        return 'utility:dislike';
    }

    get healthIconClass() {
        const status = this.healthStatus;
        if (status === 'Healthy') return 'slds-icon-text-success slds-m-bottom_x-small';
        if (status === 'Degraded') return 'slds-icon-text-warning slds-m-bottom_x-small';
        return 'slds-icon-text-error slds-m-bottom_x-small';
    }

    get healthTextClass() {
        const base = 'slds-text-heading_large slds-m-top_x-small';
        const status = this.healthStatus;
        if (status === 'Healthy') return base + ' slds-text-color_success';
        if (status === 'Degraded') return base + ' slds-text-color_weak';
        return base + ' slds-text-color_error';
    }

    // --- Click handlers ---

    handleCardClick(event) {
        const metric = event.currentTarget.dataset.metric;
        if (metric) {
            this.dispatchEvent(new CustomEvent('metricclick', {
                detail: { metric: metric }
            }));
        }
    }

    handleCardKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleCardClick(event);
        }
    }

    @api
    refresh() {
        this.loadMetrics();
    }

    handleError(error) {
        let message = 'An unexpected error occurred while loading metrics.';
        if (error) {
            if (error.body && error.body.message) {
                message = error.body.message;
            } else if (error.message) {
                message = error.message;
            }
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error Loading Metrics',
                message: message,
                variant: 'error'
            })
        );
    }
}