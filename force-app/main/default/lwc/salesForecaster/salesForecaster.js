import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import CHARTJS from '@salesforce/resourceUrl/chartjs';

import getFilterOptions from '@salesforce/apex/ForecastingController.getFilterOptions';
import getDashboardData from '@salesforce/apex/ForecastingController.getDashboardData';
import getReverseForecast from '@salesforce/apex/ForecastingController.getReverseForecast';
import getForwardForecast from '@salesforce/apex/ForecastingController.getForwardForecast';
import getForwardForecastForMonth from '@salesforce/apex/ForecastingController.getForwardForecastForMonth';
import exportForecastCSV from '@salesforce/apex/ForecastingController.exportForecastCSV';
import exportForecastPDF from '@salesforce/apex/ForecastingController.exportForecastPDF';

const VIEWS = { DASHBOARD: 'dashboard', REVERSE: 'reverse', FORWARD: 'forward' };

const STAGE_COLORS = {
    LEAD: '#3b82f6',
    SV_SCHEDULED: '#06b6d4',
    SV_COMPLETED: '#8b5cf6',
    COST_SHEET: '#f59e0b',
    BOOKED: '#22c55e'
};

const HEALTH_STATUS_COLORS = { Good: '#22c55e', Warning: '#f59e0b', Critical: '#ef4444' };

const PIE_COLORS = ['#3b82f6', '#06b6d4', '#8b5cf6', '#f59e0b', '#22c55e', '#ef4444', '#ec4899', '#6366f1'];

const CONVERSION_COLORS = ['#3b82f6', '#06b6d4', '#8b5cf6', '#f59e0b'];

export default class SalesForecaster extends NavigationMixin(LightningElement) {

    // ═══ State ═══
    @track activeView = VIEWS.DASHBOARD;
    @track isLoading = false;
    @track hasLoaded = false;
    chartJsLoaded = false;

    // Filter
    @track filterOptions = { projects: [], sources: [], owners: [] };
    @track selectedProjectId = '';
    @track selectedSource = '';
    @track selectedOwnerId = '';
    @track filterStartDate = '';
    @track filterEndDate = '';

    // Dashboard data
    @track dashboardData = null;
    @track forecastMonths = 3;

    // Reverse Forecast
    @track reverseTargetStage = 'BOOKED';
    @track reverseTargetCount = 10;
    @track reverseTimelineDays = '';
    @track reverseShowAllTimeline = true;
    @track reverseResult = null;

    // Forward Forecast
    @track forwardMonths = 3;
    @track forwardResult = null;
    @track forecastType = 'duration';
    @track specificYear = '';
    @track specificMonth = '';

    // Forward Forecast — Date Range mode
    @track histStartYear = '';
    @track histStartMonth = '';
    @track histEndYear = '';
    @track histEndMonth = '';
    @track futureStartYear = '';
    @track futureStartMonth = '';
    @track futureEndYear = '';
    @track futureEndMonth = '';

    // AI Insights
    @track aiInsight = '';
    @track isAiLoading = false;

    // Charts
    _funnelChart = null;
    _sourceChart = null;
    _trendChart = null;
    _reverseChart = null;
    _reverseWaterfallChart = null;
    _reverseDropoffChart = null;
    _reverseMultiplierChart = null;
    _conversionChart = null;
    _historicalTrendChart = null;
    _revenueSourceChart = null;
    _healthRadarChart = null;
    _dropOffChart = null;

    // ═══ Lifecycle ═══

    connectedCallback() {
        this.initialize();
    }

    async initialize() {
        this.isLoading = true;
        try {
            if (!this.chartJsLoaded) {
                await loadScript(this, CHARTJS);
                this.chartJsLoaded = true;
            }
            this.filterOptions = await getFilterOptions();
            await this.loadDashboard();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
            this.hasLoaded = true;
        }
    }

    // ═══ Data Loading ═══

    async loadDashboard() {
        this.isLoading = true;
        try {
            const filterJson = this.buildFilterJson();
            this.dashboardData = await getDashboardData({ filterJson, forecastMonths: this.forecastMonths });
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.renderDashboardCharts(); }, 250);
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadReverseForecast() {
        const count = parseInt(this.reverseTargetCount, 10);
        if (!count || count <= 0 || isNaN(count)) {
            this.showToast('Validation', 'Please enter a valid target count greater than 0.', 'warning');
            return;
        }
        if (!this.reverseTargetStage) {
            this.showToast('Validation', 'Please select a target stage.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            const filterJson = this.buildFilterJson();
            this.reverseResult = await getReverseForecast({
                targetStage: this.reverseTargetStage,
                targetCount: count,
                filterJson
            });
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.renderReverseCharts(); }, 250);
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadForwardForecast() {
        // Validate required fields before proceeding (prevents Invalid time value error)
        if (this.forecastType === 'daterange') {
            if (!this.histStartYear || !this.histStartMonth || !this.histEndYear || !this.histEndMonth ||
                !this.futureStartYear || !this.futureStartMonth || !this.futureEndYear || !this.futureEndMonth) {
                return;
            }
        }
        if (this.forecastType === 'specific') {
            if (!this.specificYear || !this.specificMonth) {
                return;
            }
        }
        this.isLoading = true;
        try {
            const filterJson = this.buildForwardFilterJson();

            if (this.forecastType === 'daterange') {
                // For date range mode, set filter dates for historical period
                // and calculate forward months from future period
                const histStart = new Date(parseInt(this.histStartYear, 10), parseInt(this.histStartMonth, 10) - 1, 1);
                const histEnd = new Date(parseInt(this.histEndYear, 10), parseInt(this.histEndMonth, 10) - 1, 28);
                const futureStart = new Date(parseInt(this.futureStartYear, 10), parseInt(this.futureStartMonth, 10) - 1, 1);
                const futureEnd = new Date(parseInt(this.futureEndYear, 10), parseInt(this.futureEndMonth, 10) - 1, 28);

                const futureMonths = Math.max(1,
                    (futureEnd.getFullYear() - futureStart.getFullYear()) * 12
                    + (futureEnd.getMonth() - futureStart.getMonth()) + 1
                );

                // Build filter with historical date range
                const filter = {};
                if (this.selectedProjectId) filter.projectId = this.selectedProjectId;
                if (this.selectedSource) filter.source = this.selectedSource;
                if (this.selectedOwnerId) filter.ownerId = this.selectedOwnerId;
                filter.startDate = histStart.toISOString().split('T')[0];
                filter.endDate = histEnd.toISOString().split('T')[0];

                const rangeFilterJson = JSON.stringify(filter);

                // If future start is a specific month, use ForMonth; else use duration
                if (futureMonths === 1) {
                    this.forwardResult = await getForwardForecastForMonth({
                        filterJson: rangeFilterJson,
                        targetYear: parseInt(this.futureStartYear, 10),
                        targetMonth: parseInt(this.futureStartMonth, 10)
                    });
                } else {
                    this.forwardResult = await getForwardForecast({
                        filterJson: rangeFilterJson,
                        forecastMonths: futureMonths
                    });
                }
            } else if (this.forecastType === 'specific' && this.specificYear && this.specificMonth) {
                this.forwardResult = await getForwardForecastForMonth({
                    filterJson,
                    targetYear: parseInt(this.specificYear, 10),
                    targetMonth: parseInt(this.specificMonth, 10)
                });
            } else {
                this.forwardResult = await getForwardForecast({
                    filterJson,
                    forecastMonths: parseInt(this.forwardMonths, 10)
                });
            }
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.renderForwardCharts(); }, 250);
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ═══ Filter ═══

    buildFilterJson() {
        const filter = {};
        if (this.selectedProjectId) filter.projectId = this.selectedProjectId;
        if (this.selectedSource) filter.source = this.selectedSource;
        if (this.selectedOwnerId) filter.ownerId = this.selectedOwnerId;
        if (this.filterStartDate) filter.startDate = this.filterStartDate;
        if (this.filterEndDate) filter.endDate = this.filterEndDate;
        return JSON.stringify(filter);
    }

    buildForwardFilterJson() {
        const filter = {};
        if (this.selectedProjectId) filter.projectId = this.selectedProjectId;
        if (this.selectedSource) filter.source = this.selectedSource;
        if (this.selectedOwnerId) filter.ownerId = this.selectedOwnerId;
        // Exclude startDate/endDate — forward forecast needs full historical
        // data for its own lookback window, not the user's date filter.
        return JSON.stringify(filter);
    }

    handleProjectChange(event) { this.selectedProjectId = event.detail.value; }
    handleSourceChange(event) { this.selectedSource = event.detail.value; }
    handleOwnerChange(event) { this.selectedOwnerId = event.detail.value; }
    handleStartDateChange(event) { this.filterStartDate = event.detail.value; }
    handleEndDateChange(event) { this.filterEndDate = event.detail.value; }

    handleApplyFilter() {
        if (this.activeView === VIEWS.DASHBOARD) {
            this.loadDashboard();
        } else if (this.activeView === VIEWS.REVERSE && this.reverseResult) {
            this.loadReverseForecast();
        } else if (this.activeView === VIEWS.FORWARD && this.forwardResult) {
            this.loadForwardForecast();
        }
    }

    handleClearFilter() {
        this.selectedProjectId = '';
        this.selectedSource = '';
        this.selectedOwnerId = '';
        this.filterStartDate = '';
        this.filterEndDate = '';
        this.handleApplyFilter();
    }

    // ═══ View Tabs ═══

    handleViewChange(event) {
        this.activeView = event.currentTarget.dataset.view;
        if (this.activeView === VIEWS.DASHBOARD && this.dashboardData) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.renderDashboardCharts(); }, 250);
        }
    }

    get isDashboardView() { return this.activeView === VIEWS.DASHBOARD; }
    get isReverseView() { return this.activeView === VIEWS.REVERSE; }
    get isForwardView() { return this.activeView === VIEWS.FORWARD; }

    get dashboardTabClass() { return 'view-tab' + (this.isDashboardView ? ' view-tab--active' : ''); }
    get reverseTabClass() { return 'view-tab' + (this.isReverseView ? ' view-tab--active' : ''); }
    get forwardTabClass() { return 'view-tab' + (this.isForwardView ? ' view-tab--active' : ''); }

    // ═══ Filter Options (combobox) ═══

    get projectOptions() {
        const opts = [{ label: 'All Projects', value: '' }];
        if (this.filterOptions.projects) {
            for (const p of this.filterOptions.projects) {
                opts.push({ label: p.label, value: p.value });
            }
        }
        return opts;
    }

    get sourceOptions() {
        const opts = [{ label: 'All Sources', value: '' }];
        if (this.filterOptions.sources) {
            for (const s of this.filterOptions.sources) {
                opts.push({ label: s.label, value: s.value });
            }
        }
        return opts;
    }

    get ownerOptions() {
        const opts = [{ label: 'All Owners', value: '' }];
        if (this.filterOptions.owners) {
            for (const o of this.filterOptions.owners) {
                opts.push({ label: o.label, value: o.value });
            }
        }
        return opts;
    }

    get forecastMonthOptions() {
        return [
            { label: '1 Month', value: '1' },
            { label: '3 Months', value: '3' },
            { label: '6 Months', value: '6' },
            { label: '12 Months', value: '12' }
        ];
    }

    get stageOptions() {
        return [
            { label: 'Booked', value: 'BOOKED' },
            { label: 'Cost Sheet', value: 'COST_SHEET' },
            { label: 'SV Completed', value: 'SV_COMPLETED' },
            { label: 'SV Scheduled', value: 'SV_SCHEDULED' }
        ];
    }

    // ═══ Dashboard Computed Getters ═══

    get summaryCards() {
        if (!this.dashboardData || !this.dashboardData.funnel) return [];
        const f = this.dashboardData.funnel;
        const fc = this.dashboardData.forecast;
        const h = this.dashboardData.health;
        return [
            { key: 'leads', label: 'Total Leads', value: this.formatNumber(f.totalLeads), icon: 'standard:lead', color: '#3b82f6', helpText: 'Total number of active leads (excluding unqualified/closed)' },
            { key: 'svs', label: 'Site Visits', value: this.formatNumber(this.getStageFunnelCount('SV_COMPLETED')), icon: 'standard:visit', color: '#8b5cf6', helpText: 'Leads who completed a site visit' },
            { key: 'bookings', label: 'Bookings', value: this.formatNumber(f.totalBookings), icon: 'standard:opportunity', color: '#22c55e', helpText: 'Total confirmed bookings (non-cancelled)' },
            { key: 'conv', label: 'Overall Conversion', value: f.overallConversionRate + '%', icon: 'standard:dashboard', color: '#06b6d4', helpText: 'Percentage of leads that converted to bookings' },
            { key: 'health', label: 'Pipeline Health', value: (h ? h.healthGrade : 'N/A'), icon: 'standard:flow', color: h && h.healthScore >= 70 ? '#22c55e' : (h && h.healthScore >= 40 ? '#f59e0b' : '#ef4444'), helpText: 'Overall pipeline health grade based on 5 components' },
            { key: 'revenue', label: 'Revenue Forecast', value: this.formatCurrency(fc && fc.monthlyForecasts && fc.monthlyForecasts.length > 0 ? fc.monthlyForecasts.reduce((s, m) => s + (m.predictedRevenue || 0), 0) : 0), icon: 'standard:currency', color: '#f59e0b', helpText: 'Total predicted revenue across all forecast months' }
        ];
    }

    get funnelStages() {
        if (!this.dashboardData || !this.dashboardData.funnel) return [];
        return this.dashboardData.funnel.stages.map(s => ({
            ...s,
            barWidth: s.cumulativeRate + '%',
            barStyle: `width: ${s.cumulativeRate}%; background: ${STAGE_COLORS[s.stageKey] || '#94a3b8'};`,
            color: STAGE_COLORS[s.stageKey] || '#94a3b8'
        }));
    }

    get healthData() {
        if (!this.dashboardData || !this.dashboardData.health) return null;
        const h = this.dashboardData.health;
        return {
            ...h,
            gradeClass: 'health-grade grade-' + h.healthGrade,
            components: h.components.map(c => ({
                ...c,
                dotStyle: `background: ${HEALTH_STATUS_COLORS[c.status] || '#94a3b8'};`,
                barStyle: `width: ${c.score}%; background: ${HEALTH_STATUS_COLORS[c.status] || '#94a3b8'};`
            }))
        };
    }

    get sourceData() {
        if (!this.dashboardData || !this.dashboardData.sources) return [];
        return this.dashboardData.sources.map(s => ({
            ...s,
            formattedRevenue: this.formatCurrency(s.revenue)
        }));
    }

    get campaignData() {
        if (!this.dashboardData || !this.dashboardData.campaigns) return [];
        return this.dashboardData.campaigns.map(c => ({
            ...c,
            formattedSpend: this.formatCurrency(c.spend),
            formattedRevenue: this.formatCurrency(c.revenue),
            roiClass: c.roi > 0 ? 'roi-positive' : 'roi-negative'
        }));
    }

    get hasCampaigns() { return this.campaignData.length > 0; }
    get hasSources() { return this.sourceData.length > 0; }

    get conversionDetails() {
        if (!this.dashboardData || !this.dashboardData.conversionDetails) return [];
        return this.dashboardData.conversionDetails.map(c => ({
            ...c,
            rateClass: c.rate >= 50 ? 'conv-high' : (c.rate >= 25 ? 'conv-mid' : 'conv-low'),
            formattedRate: c.rate + '%',
            formattedDropOff: this.formatNumber(c.dropOff)
        }));
    }

    get hasConversionDetails() {
        return this.conversionDetails.length > 0;
    }

    get hasMonthlyTrend() {
        return this.dashboardData && this.dashboardData.monthlyTrend && this.dashboardData.monthlyTrend.length > 0;
    }

    get monthlyTrendData() {
        if (!this.hasMonthlyTrend) return [];
        return this.dashboardData.monthlyTrend;
    }

    get avgBookingValue() {
        if (!this.dashboardData || !this.dashboardData.avgBookingValue) return '0';
        return this.formatCurrency(this.dashboardData.avgBookingValue);
    }

    get avgSalesCycleDashboard() {
        if (!this.dashboardData || !this.dashboardData.forecast) return '0';
        return this.dashboardData.forecast.avgSalesCycleDays + ' days';
    }

    get leadVelocityDashboard() {
        if (!this.dashboardData || !this.dashboardData.forecast) return '0%';
        const v = this.dashboardData.forecast.leadVelocityRate;
        return (v >= 0 ? '+' : '') + v + '%';
    }

    get leadVelocityDashboardClass() {
        if (!this.dashboardData || !this.dashboardData.forecast) return 'metric-value-lg';
        return this.dashboardData.forecast.leadVelocityRate >= 0 ? 'velocity-positive' : 'velocity-negative';
    }

    // ═══ Reverse Forecast Getters ═══

    get reverseStages() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length === 0) return [];
        const counts = this.reverseResult.requiredAtEachStage.map(s => s.count);
        const maxCount = counts.length > 0 ? Math.max(...counts) : 0;
        return this.reverseResult.requiredAtEachStage.map(s => ({
            ...s,
            barStyle: `width: ${maxCount > 0 ? (s.count / maxCount * 100) : 0}%; background: ${STAGE_COLORS[s.stageKey] || '#94a3b8'};`,
            color: STAGE_COLORS[s.stageKey] || '#94a3b8',
            formattedCount: this.formatNumber(s.count)
        }));
    }

    get reverseInsight() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length === 0) return '';
        const stages = this.reverseResult.requiredAtEachStage;
        const first = stages[0];
        const last = stages[stages.length - 1];
        let insight = `To achieve ${this.formatNumber(last.count)} at ${last.stageLabel}, you need approximately ${this.formatNumber(first.count)} at ${first.stageLabel} stage, based on your current conversion rates.`;
        const days = parseInt(this.reverseTimelineDays, 10);
        if (!this.reverseShowAllTimeline && days > 0) {
            const dailyLeads = Math.ceil(first.count / days);
            insight += ` Within ${days} days, that means ~${this.formatNumber(dailyLeads)} new leads per day.`;
        }
        return insight;
    }

    get showDailyBreakdown() {
        return this.reverseResult && !this.reverseShowAllTimeline && parseInt(this.reverseTimelineDays, 10) > 0;
    }

    get dailyBreakdownStages() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage) return [];
        const days = parseInt(this.reverseTimelineDays, 10);
        if (!days || days <= 0) return [];
        return this.reverseResult.requiredAtEachStage.map(s => {
            const daily = Math.ceil(s.count / days);
            const color = STAGE_COLORS[s.stageKey] || '#94a3b8';
            return {
                stageKey: s.stageKey,
                stageLabel: s.stageLabel,
                dailyCount: this.formatNumber(daily),
                totalCount: this.formatNumber(s.count),
                borderStyle: `border-top: 4px solid ${color};`,
                colorStyle: `color: ${color};`,
                tooltipText: `You need ${this.formatNumber(s.count)} total at ${s.stageLabel} over ${days} days = ~${this.formatNumber(daily)} per day`
            };
        });
    }

    // Estimated days per stage transition (heuristic based on typical sales cycles)
    get _stageEstimatedDays() {
        return {
            LEAD: 0,
            SV_SCHEDULED: 7,
            SV_COMPLETED: 5,
            COST_SHEET: 10,
            BOOKED: 14
        };
    }

    get reverseTimelineStages() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length === 0) return [];
        const stages = this.reverseResult.requiredAtEachStage;
        const estDays = this._stageEstimatedDays;
        return stages.map((s, idx) => {
            const color = STAGE_COLORS[s.stageKey] || '#94a3b8';
            const isLast = idx === stages.length - 1;
            const nextStage = !isLast ? stages[idx + 1] : null;
            const dropOffCount = nextStage ? s.count - nextStage.count : 0;
            const crDisplay = s.conversionRate != null && s.conversionRate < 100
                ? s.conversionRate + '%'
                : (idx === 0 ? 'Entry' : '100%');
            const days = estDays[s.stageKey] || 7;
            const durationLabel = days === 0 ? 'Start' : (days < 7 ? days + ' days' : Math.round(days / 7) + (Math.round(days / 7) === 1 ? ' week' : ' weeks'));
            const dropOffText = dropOffCount > 0 ? ', ~' + this.formatNumber(dropOffCount) + ' leads drop off before next stage' : '';
            return {
                stageKey: s.stageKey,
                stageLabel: s.stageLabel,
                formattedCount: this.formatNumber(s.count),
                stepNumber: idx + 1,
                hasConnector: !isLast,
                conversionLabel: nextStage && nextStage.conversionRate != null ? nextStage.conversionRate + '% pass' : '',
                conversionRateDisplay: crDisplay,
                dropOff: dropOffCount > 0 ? '-' + this.formatNumber(dropOffCount) : '',
                estimatedDuration: durationLabel,
                nodeStyle: `background: ${color};`,
                cardBorderStyle: `border-top: 4px solid ${color};`,
                stageColorStyle: `color: ${color};`,
                nodeTooltip: `Step ${idx + 1}: ${s.stageLabel}`,
                cardTooltip: `${s.stageLabel}: Need ${this.formatNumber(s.count)} leads, ${crDisplay} conversion rate, ~${durationLabel}${dropOffText}`
            };
        });
    }

    get totalEstimatedWeeks() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage) return '—';
        const estDays = this._stageEstimatedDays;
        const stages = this.reverseResult.requiredAtEachStage;
        let totalDays = 0;
        for (const s of stages) {
            totalDays += estDays[s.stageKey] || 7;
        }
        const weeks = Math.round(totalDays / 7);
        return weeks + (weeks === 1 ? ' week' : ' weeks') + ' (' + totalDays + ' days)';
    }

    get overallConversionRate() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length < 2) return '—';
        const stages = this.reverseResult.requiredAtEachStage;
        const first = stages[0].count;
        const last = stages[stages.length - 1].count;
        if (first === 0) return '0%';
        return ((last / first) * 100).toFixed(1) + '%';
    }

    get totalDropOff() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length < 2) return '—';
        const stages = this.reverseResult.requiredAtEachStage;
        const dropped = stages[0].count - stages[stages.length - 1].count;
        return this.formatNumber(dropped) + ' leads';
    }

    get reverseMultipliers() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length === 0) return [];
        const stages = this.reverseResult.requiredAtEachStage;
        const targetCount = stages[stages.length - 1].count;
        return stages.map(s => {
            const mult = targetCount > 0 ? (s.count / targetCount) : 0;
            const color = STAGE_COLORS[s.stageKey] || '#94a3b8';
            return {
                stageKey: s.stageKey,
                stageLabel: s.stageLabel,
                multiplierDisplay: mult.toFixed(1) + 'x',
                description: s.count === targetCount ? 'Target' : this.formatNumber(s.count) + ' needed',
                borderStyle: `border-top: 3px solid ${color};`,
                colorStyle: `color: ${color};`
            };
        });
    }

    // ═══ Forward Forecast Getters ═══

    get forwardForecasts() {
        if (!this.forwardResult || !this.forwardResult.monthlyForecasts) return [];
        return this.forwardResult.monthlyForecasts.map(m => ({
            ...m,
            formattedRevenue: this.formatCurrency(m.predictedRevenue)
        }));
    }

    get forwardVelocity() {
        if (!this.forwardResult) return '0';
        const v = this.forwardResult.leadVelocityRate;
        return (v >= 0 ? '+' : '') + v + '%';
    }

    get velocityClass() {
        if (!this.forwardResult) return 'metric-value-lg';
        return this.forwardResult.leadVelocityRate >= 0 ? 'velocity-positive' : 'velocity-negative';
    }

    get forwardSalesCycle() {
        if (!this.forwardResult) return '0';
        return this.forwardResult.avgSalesCycleDays + ' days';
    }

    get forwardTotalRevenue() {
        if (!this.forwardResult || !this.forwardResult.monthlyForecasts) return '0';
        const total = this.forwardResult.monthlyForecasts.reduce((s, m) => s + (m.predictedRevenue || 0), 0);
        return this.formatCurrency(total);
    }

    get forwardTotalBookings() {
        if (!this.forwardResult || !this.forwardResult.monthlyForecasts) return '0';
        const total = this.forwardResult.monthlyForecasts.reduce((s, m) => s + (m.predictedBookings || 0), 0);
        return this.formatNumber(total);
    }

    get forwardTotalLeads() {
        if (!this.forwardResult || !this.forwardResult.monthlyForecasts) return '0';
        const total = this.forwardResult.monthlyForecasts.reduce((s, m) => s + (m.predictedLeads || 0), 0);
        return this.formatNumber(total);
    }

    // ═══ Reverse Forecast Handlers ═══

    handleTargetStageChange(event) { this.reverseTargetStage = event.detail.value; }
    handleTargetCountChange(event) { this.reverseTargetCount = event.detail.value; }
    handleTimelineDaysChange(event) { this.reverseTimelineDays = event.detail.value; }
    handleShowAllTimelineChange(event) {
        this.reverseShowAllTimeline = event.target.checked;
        if (this.reverseShowAllTimeline) {
            this.reverseTimelineDays = '';
        }
    }
    handleCalculateReverse() { this.loadReverseForecast(); }

    // ═══ Forward Forecast Handlers ═══

    handleForwardMonthsChange(event) { this.forwardMonths = event.detail.value; }
    handleForecastTypeChange(event) { this.forecastType = event.detail.value; }
    handleSpecificYearChange(event) { this.specificYear = event.detail.value; }
    handleSpecificMonthChange(event) { this.specificMonth = event.detail.value; }

    get forecastTypeOptions() {
        return [
            { label: 'Duration Based', value: 'duration' },
            { label: 'Specific Month', value: 'specific' },
            { label: 'Date Range (Historic + Future)', value: 'daterange' }
        ];
    }

    get isDurationForecast() { return this.forecastType === 'duration'; }
    get isSpecificMonthForecast() { return this.forecastType === 'specific'; }
    get isDateRangeForecast() { return this.forecastType === 'daterange'; }

    get yearOptions() {
        const currentYear = new Date().getFullYear();
        const options = [];
        for (let y = currentYear; y <= currentYear + 5; y++) {
            options.push({ label: String(y), value: String(y) });
        }
        return options;
    }

    get historicYearOptions() {
        const currentYear = new Date().getFullYear();
        const options = [];
        for (let y = currentYear - 5; y <= currentYear; y++) {
            options.push({ label: String(y), value: String(y) });
        }
        return options;
    }

    get futureYearOptions() {
        const currentYear = new Date().getFullYear();
        const options = [];
        for (let y = currentYear; y <= currentYear + 5; y++) {
            options.push({ label: String(y), value: String(y) });
        }
        return options;
    }

    get monthOptions() {
        const months = [
            'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'
        ];
        return months.map((m, i) => ({ label: m, value: String(i + 1) }));
    }

    handleHistStartYearChange(event) { this.histStartYear = event.detail.value; }
    handleHistStartMonthChange(event) { this.histStartMonth = event.detail.value; }
    handleHistEndYearChange(event) { this.histEndYear = event.detail.value; }
    handleHistEndMonthChange(event) { this.histEndMonth = event.detail.value; }
    handleFutureStartYearChange(event) { this.futureStartYear = event.detail.value; }
    handleFutureStartMonthChange(event) { this.futureStartMonth = event.detail.value; }
    handleFutureEndYearChange(event) { this.futureEndYear = event.detail.value; }
    handleFutureEndMonthChange(event) { this.futureEndMonth = event.detail.value; }

    handleGenerateForward() {
        if (this.forecastType === 'specific') {
            if (!this.specificYear || !this.specificMonth) {
                this.showToast('Warning', 'Please select both Year and Month.', 'warning');
                return;
            }
        }
        if (this.forecastType === 'daterange') {
            if (!this.histStartYear || !this.histStartMonth || !this.histEndYear || !this.histEndMonth) {
                this.showToast('Warning', 'Please select full Historical Period (start and end).', 'warning');
                return;
            }
            if (!this.futureStartYear || !this.futureStartMonth || !this.futureEndYear || !this.futureEndMonth) {
                this.showToast('Warning', 'Please select full Future Forecast Period (start and end).', 'warning');
                return;
            }
        }
        this.loadForwardForecast();
    }

    // ═══ Export Handlers ═══

    async handleExportCSV() {
        this.isLoading = true;
        try {
            const filterJson = this.buildFilterJson();
            const csv = await exportForecastCSV({ filterJson, forecastMonths: this.forecastMonths });
            this.downloadFile('Sales_Forecast.csv', csv, 'text/csv');
            this.showToast('Success', 'CSV exported successfully.', 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleExportPDF() {
        this.isLoading = true;
        try {
            const filterJson = this.buildFilterJson();
            const downloadUrl = await exportForecastPDF({ filterJson, forecastMonths: this.forecastMonths });
            window.open(downloadUrl, '_blank');
            this.showToast('Success', 'PDF generated successfully.', 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        if (this.activeView === VIEWS.DASHBOARD) {
            this.loadDashboard();
        } else if (this.activeView === VIEWS.REVERSE && this.reverseResult) {
            this.loadReverseForecast();
        } else if (this.activeView === VIEWS.FORWARD && this.forwardResult) {
            this.loadForwardForecast();
        }
    }

    // ═══ AI Insights ═══

    async handleGetAiInsight() {
        if (!this.forwardResult || !this.forwardResult.monthlyForecasts) {
            this.showToast('Info', 'Please generate a forecast first.', 'info');
            return;
        }

        this.isAiLoading = true;
        this.aiInsight = '';

        try {
            // Build a summary of forecast data for the AI prompt
            const forecasts = this.forwardResult.monthlyForecasts;
            let summaryText = 'Sales Forecast Data:\n';
            for (const mf of forecasts) {
                summaryText += `${mf.periodLabel}: Leads=${mf.predictedLeads}, Site Visits=${mf.predictedSiteVisits}, Bookings=${mf.predictedBookings}, Revenue=${mf.predictedRevenue}, Seasonality=${mf.seasonalityIndex}\n`;
            }
            summaryText += `Lead Velocity Rate: ${this.forwardResult.leadVelocityRate}%\n`;
            summaryText += `Avg Sales Cycle: ${this.forwardResult.avgSalesCycleDays} days\n`;

            const prompt = `You are a sales analytics expert. Analyze this forecast data and provide 3-5 actionable insights in clear bullet points. Focus on trends, risks, and opportunities. Keep it concise.\n\n${summaryText}`;

            // Call AI API via Apex
            const result = await this._callAiInsight(prompt);
            this.aiInsight = result;
        } catch (error) {
            this.aiInsight = 'Unable to generate AI insights at this time. Please ensure the AI integration is configured.';
            this.showToast('Info', 'AI insights require backend integration to be configured.', 'info');
        } finally {
            this.isAiLoading = false;
        }
    }

    async _callAiInsight(prompt) {
        // This calls the Apex method for AI insight generation
        // For now, generate a client-side analytical summary as a placeholder
        // until the Apex AI integration is wired up
        const forecasts = this.forwardResult.monthlyForecasts;
        if (!forecasts || forecasts.length === 0) return 'No forecast data available.';

        const insights = [];
        const totalLeads = forecasts.reduce((s, m) => s + (m.predictedLeads || 0), 0);
        const totalBookings = forecasts.reduce((s, m) => s + (m.predictedBookings || 0), 0);
        const totalRevenue = forecasts.reduce((s, m) => s + (m.predictedRevenue || 0), 0);
        const avgMonthlyLeads = Math.round(totalLeads / forecasts.length);
        const avgMonthlyBookings = Math.round(totalBookings / forecasts.length);

        insights.push(`📊 Over the forecast period, you are projected to generate ${totalLeads.toLocaleString('en-IN')} leads resulting in ${totalBookings.toLocaleString('en-IN')} bookings with total revenue of ₹${this.formatCurrency(totalRevenue)}.`);

        // Trend analysis
        if (forecasts.length >= 2) {
            const firstMonth = forecasts[0];
            const lastMonth = forecasts[forecasts.length - 1];
            const leadGrowth = firstMonth.predictedLeads > 0
                ? (((lastMonth.predictedLeads - firstMonth.predictedLeads) / firstMonth.predictedLeads) * 100).toFixed(1)
                : 0;
            if (leadGrowth > 0) {
                insights.push(`📈 Lead volume shows an upward trend of +${leadGrowth}% from ${firstMonth.periodLabel} to ${lastMonth.periodLabel}. Consider scaling your sales team capacity accordingly.`);
            } else if (leadGrowth < 0) {
                insights.push(`📉 Lead volume shows a declining trend of ${leadGrowth}% from ${firstMonth.periodLabel} to ${lastMonth.periodLabel}. Review marketing spend and lead generation strategies.`);
            } else {
                insights.push(`➡️ Lead volume remains stable across the forecast period. Look for opportunities to accelerate growth through new channels.`);
            }
        }

        // Conversion insight
        const overallConv = totalLeads > 0 ? ((totalBookings / totalLeads) * 100).toFixed(1) : 0;
        if (overallConv < 5) {
            insights.push(`⚠️ Projected conversion rate is ${overallConv}% — below industry benchmarks. Focus on improving site visit completion rates and follow-up processes.`);
        } else if (overallConv >= 10) {
            insights.push(`✅ Strong projected conversion rate of ${overallConv}%. Your pipeline efficiency is performing well — maintain current practices.`);
        } else {
            insights.push(`💡 Projected conversion rate is ${overallConv}%. There is room for improvement — consider optimizing the site visit to booking conversion stage.`);
        }

        // Velocity insight
        const velocity = this.forwardResult.leadVelocityRate;
        if (velocity > 10) {
            insights.push(`🚀 Lead velocity rate of +${velocity}% indicates strong month-over-month growth momentum. This is a positive signal for pipeline health.`);
        } else if (velocity < -10) {
            insights.push(`🔴 Lead velocity rate of ${velocity}% indicates declining momentum. Immediate action recommended on lead generation activities.`);
        }

        // Seasonality insight
        const highSeason = forecasts.reduce((max, m) => (m.seasonalityIndex || 1) > (max.seasonalityIndex || 1) ? m : max, forecasts[0]);
        if (highSeason.seasonalityIndex > 1.1) {
            insights.push(`📅 Peak seasonal period expected in ${highSeason.periodLabel} (index: ${highSeason.seasonalityIndex}). Plan additional resources and inventory for this period.`);
        }

        return insights.join('\n\n');
    }

    // ═══ Chart Rendering ═══

    renderDashboardCharts() {
        this.renderFunnelChart();
        this.renderSourceChart();
        this.renderConversionChart();
        this.renderHistoricalTrendChart();
        this.renderRevenueSourceChart();
        this.renderHealthRadarChart();
        this.renderDropOffChart();
    }

    renderForwardCharts() {
        this.renderTrendChart();
    }

    renderFunnelChart() {
        if (!this.dashboardData || !this.dashboardData.funnel || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.funnel-chart');
        if (!canvas) return;

        if (this._funnelChart) this._funnelChart.destroy();

        const stages = this.dashboardData.funnel.stages;
        this._funnelChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: stages.map(s => s.stageLabel),
                datasets: [{
                    label: 'Count',
                    data: stages.map(s => s.count),
                    backgroundColor: stages.map(s => STAGE_COLORS[s.stageKey] || '#94a3b8'),
                    borderRadius: 6,
                    barThickness: 32
                }]
            },
            options: {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        titleFont: { size: 13, weight: 'bold' },
                        bodyFont: { size: 12 },
                        padding: 12,
                        cornerRadius: 8,
                        callbacks: {
                            label: ctx => `Count: ${ctx.raw.toLocaleString('en-IN')}`,
                            afterLabel: ctx => `Cumulative: ${stages[ctx.dataIndex].cumulativeRate}%`
                        }
                    }
                },
                scales: {
                    x: { grid: { display: false }, ticks: { precision: 0, font: { size: 11 } } },
                    y: { grid: { display: false }, ticks: { font: { size: 12, weight: 'bold' } } }
                }
            }
        });
    }

    renderSourceChart() {
        if (!this.dashboardData || !this.dashboardData.sources || this.dashboardData.sources.length === 0 || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.source-chart');
        if (!canvas) return;

        if (this._sourceChart) this._sourceChart.destroy();

        const sources = this.dashboardData.sources;
        this._sourceChart = new window.Chart(canvas, {
            type: 'doughnut',
            data: {
                labels: sources.map(s => s.source),
                datasets: [{
                    data: sources.map(s => s.leadCount),
                    backgroundColor: PIE_COLORS.slice(0, sources.length),
                    borderWidth: 2,
                    borderColor: '#fff'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                cutout: '60%',
                plugins: {
                    legend: { position: 'right', labels: { font: { size: 11 }, padding: 12, usePointStyle: true } },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        callbacks: {
                            label: ctx => {
                                const total = ctx.dataset.data.reduce((a, b) => a + b, 0);
                                const pct = total > 0 ? ((ctx.raw / total) * 100).toFixed(1) : 0;
                                return `${ctx.label}: ${ctx.raw} leads (${pct}%)`;
                            },
                            afterLabel: ctx => `Conv: ${sources[ctx.dataIndex].conversionRate}%`
                        }
                    }
                }
            }
        });
    }

    renderConversionChart() {
        if (!this.dashboardData || !this.dashboardData.conversionDetails || this.dashboardData.conversionDetails.length === 0 || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.conversion-chart');
        if (!canvas) return;

        if (this._conversionChart) this._conversionChart.destroy();

        const details = this.dashboardData.conversionDetails;
        this._conversionChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: details.map(d => d.label),
                datasets: [{
                    label: 'Conversion Rate (%)',
                    data: details.map(d => d.rate),
                    backgroundColor: CONVERSION_COLORS.slice(0, details.length),
                    borderRadius: 8,
                    barThickness: 40
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        callbacks: {
                            label: ctx => `Conversion: ${ctx.raw}%`,
                            afterLabel: ctx => `Drop-off: ${details[ctx.dataIndex].dropOff.toLocaleString('en-IN')}`
                        }
                    }
                },
                scales: {
                    x: { grid: { display: false }, ticks: { font: { size: 11 }, maxRotation: 0 } },
                    y: {
                        beginAtZero: true,
                        max: 100,
                        grid: { color: '#f1f5f9' },
                        ticks: { callback: val => val + '%', font: { size: 11 } }
                    }
                }
            }
        });
    }

    renderHistoricalTrendChart() {
        if (!this.dashboardData || !this.dashboardData.monthlyTrend || this.dashboardData.monthlyTrend.length === 0 || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.historical-trend-chart');
        if (!canvas) return;

        if (this._historicalTrendChart) this._historicalTrendChart.destroy();

        const trend = this.dashboardData.monthlyTrend;
        this._historicalTrendChart = new window.Chart(canvas, {
            type: 'line',
            data: {
                labels: trend.map(t => t.periodLabel),
                datasets: [
                    {
                        label: 'Leads',
                        data: trend.map(t => t.leads),
                        borderColor: '#3b82f6',
                        backgroundColor: 'rgba(59, 130, 246, 0.08)',
                        fill: true,
                        tension: 0.4,
                        pointRadius: 5,
                        pointBackgroundColor: '#3b82f6',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        borderWidth: 2.5
                    },
                    {
                        label: 'Site Visits',
                        data: trend.map(t => t.siteVisits),
                        borderColor: '#8b5cf6',
                        backgroundColor: 'rgba(139, 92, 246, 0.08)',
                        fill: true,
                        tension: 0.4,
                        pointRadius: 5,
                        pointBackgroundColor: '#8b5cf6',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        borderWidth: 2.5
                    },
                    {
                        label: 'Bookings',
                        data: trend.map(t => t.bookings),
                        borderColor: '#22c55e',
                        backgroundColor: 'rgba(34, 197, 94, 0.08)',
                        fill: true,
                        tension: 0.4,
                        pointRadius: 5,
                        pointBackgroundColor: '#22c55e',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        borderWidth: 2.5
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: { mode: 'index', intersect: false },
                plugins: {
                    legend: { position: 'top', labels: { font: { size: 12 }, usePointStyle: true, padding: 16 } },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        titleFont: { size: 13, weight: 'bold' }
                    }
                },
                scales: {
                    x: { grid: { display: false }, ticks: { font: { size: 11 } } },
                    y: { beginAtZero: true, grid: { color: '#f1f5f9' }, ticks: { precision: 0, font: { size: 11 } } }
                }
            }
        });
    }

    renderRevenueSourceChart() {
        if (!this.dashboardData || !this.dashboardData.sources || this.dashboardData.sources.length === 0 || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.revenue-source-chart');
        if (!canvas) return;

        if (this._revenueSourceChart) this._revenueSourceChart.destroy();

        const sources = this.dashboardData.sources;

        this._revenueSourceChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: sources.map(s => s.source),
                datasets: [
                    {
                        label: 'Bookings',
                        data: sources.map(s => s.bookingCount),
                        backgroundColor: '#22c55e',
                        borderRadius: 4,
                        barThickness: 20,
                        yAxisID: 'y'
                    },
                    {
                        label: 'Leads',
                        data: sources.map(s => s.leadCount),
                        backgroundColor: '#3b82f6',
                        borderRadius: 4,
                        barThickness: 20,
                        yAxisID: 'y'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'top', labels: { font: { size: 11 }, usePointStyle: true, padding: 12 } },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        callbacks: {
                            afterBody: (items) => {
                                const idx = items[0].dataIndex;
                                return `Revenue: ${this.formatCurrency(sources[idx].revenue)}\nConversion: ${sources[idx].conversionRate}%`;
                            }
                        }
                    }
                },
                scales: {
                    x: { grid: { display: false }, ticks: { font: { size: 10 }, maxRotation: 45 } },
                    y: { beginAtZero: true, grid: { color: '#f1f5f9' }, ticks: { precision: 0, font: { size: 11 } } }
                }
            }
        });
    }

    renderHealthRadarChart() {
        if (!this.dashboardData || !this.dashboardData.health || !this.dashboardData.health.components || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.health-radar-chart');
        if (!canvas) return;

        if (this._healthRadarChart) this._healthRadarChart.destroy();

        const comps = this.dashboardData.health.components;
        this._healthRadarChart = new window.Chart(canvas, {
            type: 'radar',
            data: {
                labels: comps.map(c => c.name),
                datasets: [{
                    label: 'Score',
                    data: comps.map(c => c.score),
                    backgroundColor: 'rgba(14, 165, 233, 0.15)',
                    borderColor: '#0ea5e9',
                    borderWidth: 2.5,
                    pointBackgroundColor: comps.map(c => HEALTH_STATUS_COLORS[c.status] || '#94a3b8'),
                    pointBorderColor: '#fff',
                    pointBorderWidth: 2,
                    pointRadius: 6
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        callbacks: {
                            label: ctx => `Score: ${ctx.raw}/100`,
                            afterLabel: ctx => `Status: ${comps[ctx.dataIndex].status}`
                        }
                    }
                },
                scales: {
                    r: {
                        beginAtZero: true,
                        max: 100,
                        ticks: { stepSize: 25, font: { size: 10 }, backdropColor: 'transparent' },
                        pointLabels: { font: { size: 11, weight: '600' }, color: '#475569' },
                        grid: { color: '#e2e8f0' },
                        angleLines: { color: '#e2e8f0' }
                    }
                }
            }
        });
    }

    renderDropOffChart() {
        if (!this.dashboardData || !this.dashboardData.conversionDetails || this.dashboardData.conversionDetails.length === 0 || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.dropoff-chart');
        if (!canvas) return;

        if (this._dropOffChart) this._dropOffChart.destroy();

        const details = this.dashboardData.conversionDetails;
        this._dropOffChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: details.map(d => d.label),
                datasets: [
                    {
                        label: 'Converted',
                        data: details.map(d => d.toCount),
                        backgroundColor: '#22c55e',
                        borderRadius: 4,
                        barThickness: 28
                    },
                    {
                        label: 'Dropped Off',
                        data: details.map(d => d.dropOff),
                        backgroundColor: '#ef4444',
                        borderRadius: 4,
                        barThickness: 28
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'top', labels: { font: { size: 11 }, usePointStyle: true, padding: 12 } },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8
                    }
                },
                scales: {
                    x: { stacked: true, grid: { display: false }, ticks: { font: { size: 10 }, maxRotation: 0 } },
                    y: { stacked: true, beginAtZero: true, grid: { color: '#f1f5f9' }, ticks: { precision: 0, font: { size: 11 } } }
                }
            }
        });
    }

    renderTrendChart() {
        if (!this.forwardResult || !this.forwardResult.monthlyForecasts || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.trend-chart');
        if (!canvas) return;

        if (this._trendChart) this._trendChart.destroy();

        const forecasts = this.forwardResult.monthlyForecasts;
        this._trendChart = new window.Chart(canvas, {
            type: 'line',
            data: {
                labels: forecasts.map(f => f.periodLabel),
                datasets: [
                    {
                        label: 'Leads',
                        data: forecasts.map(f => f.predictedLeads),
                        borderColor: '#3b82f6',
                        backgroundColor: 'rgba(59, 130, 246, 0.1)',
                        fill: true,
                        tension: 0.3,
                        pointRadius: 5,
                        pointBackgroundColor: '#3b82f6',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        borderWidth: 2.5
                    },
                    {
                        label: 'Site Visits',
                        data: forecasts.map(f => f.predictedSiteVisits),
                        borderColor: '#8b5cf6',
                        backgroundColor: 'rgba(139, 92, 246, 0.1)',
                        fill: true,
                        tension: 0.3,
                        pointRadius: 5,
                        pointBackgroundColor: '#8b5cf6',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        borderWidth: 2.5
                    },
                    {
                        label: 'Bookings',
                        data: forecasts.map(f => f.predictedBookings),
                        borderColor: '#22c55e',
                        backgroundColor: 'rgba(34, 197, 94, 0.1)',
                        fill: true,
                        tension: 0.3,
                        pointRadius: 5,
                        pointBackgroundColor: '#22c55e',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        borderWidth: 2.5
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: { mode: 'index', intersect: false },
                plugins: {
                    legend: { position: 'top', labels: { font: { size: 12 }, usePointStyle: true, padding: 16 } },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        titleFont: { size: 13, weight: 'bold' }
                    }
                },
                scales: {
                    x: { grid: { display: false } },
                    y: { beginAtZero: true, grid: { color: '#f1f5f9' }, ticks: { precision: 0 } }
                }
            }
        });
    }

    renderReverseCharts() {
        this.renderReverseChart();
        this.renderReverseWaterfallChart();
        this.renderReverseDropoffChart();
        this.renderReverseMultiplierChart();
    }

    renderReverseChart() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length === 0 || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.reverse-chart');
        if (!canvas) return;

        if (this._reverseChart) this._reverseChart.destroy();

        const stages = this.reverseResult.requiredAtEachStage;
        this._reverseChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: stages.map(s => s.stageLabel),
                datasets: [{
                    label: 'Required Count',
                    data: stages.map(s => s.count),
                    backgroundColor: stages.map(s => STAGE_COLORS[s.stageKey] || '#94a3b8'),
                    borderRadius: 6,
                    barThickness: 32
                }]
            },
            options: {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        callbacks: {
                            label: ctx => `Required: ${ctx.raw.toLocaleString('en-IN')}`,
                            afterLabel: ctx => stages[ctx.dataIndex].conversionRate ? `Conv Rate: ${stages[ctx.dataIndex].conversionRate}%` : ''
                        }
                    }
                },
                scales: {
                    x: { grid: { display: false }, ticks: { precision: 0 } },
                    y: { grid: { display: false }, ticks: { font: { size: 12, weight: 'bold' } } }
                }
            }
        });
    }

    renderReverseWaterfallChart() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length < 2 || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.reverse-waterfall-chart');
        if (!canvas) return;

        if (this._reverseWaterfallChart) this._reverseWaterfallChart.destroy();

        const stages = this.reverseResult.requiredAtEachStage;
        // Build conversion rate labels (between stages)
        const labels = [];
        const rates = [];
        const colors = [];
        for (let i = 1; i < stages.length; i++) {
            labels.push(stages[i - 1].stageLabel + ' → ' + stages[i].stageLabel);
            const cr = stages[i].conversionRate != null ? stages[i].conversionRate : 10;
            rates.push(cr);
            // Color code: green for >30%, amber for 10-30%, red for <10%
            colors.push(cr >= 30 ? '#22c55e' : cr >= 10 ? '#f59e0b' : '#ef4444');
        }

        this._reverseWaterfallChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Conversion Rate %',
                    data: rates,
                    backgroundColor: colors,
                    borderRadius: 6,
                    barThickness: 28
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        callbacks: {
                            label: ctx => `Conversion: ${ctx.raw}%`
                        }
                    }
                },
                scales: {
                    x: { grid: { display: false }, ticks: { font: { size: 10 }, maxRotation: 45 } },
                    y: {
                        beginAtZero: true,
                        max: 100,
                        grid: { color: '#f1f5f9' },
                        ticks: { callback: v => v + '%' }
                    }
                }
            }
        });
    }

    renderReverseDropoffChart() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length < 2 || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.reverse-dropoff-chart');
        if (!canvas) return;

        if (this._reverseDropoffChart) this._reverseDropoffChart.destroy();

        const stages = this.reverseResult.requiredAtEachStage;
        const labels = [];
        const dropoffs = [];
        const colors = [];
        for (let i = 0; i < stages.length - 1; i++) {
            const drop = stages[i].count - stages[i + 1].count;
            labels.push(stages[i].stageLabel + ' → ' + stages[i + 1].stageLabel);
            dropoffs.push(drop > 0 ? drop : 0);
            colors.push(STAGE_COLORS[stages[i].stageKey] || '#94a3b8');
        }

        this._reverseDropoffChart = new window.Chart(canvas, {
            type: 'doughnut',
            data: {
                labels: labels,
                datasets: [{
                    data: dropoffs,
                    backgroundColor: colors,
                    borderWidth: 2,
                    borderColor: '#ffffff',
                    hoverOffset: 6
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                cutout: '55%',
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: { padding: 12, usePointStyle: true, pointStyle: 'circle', font: { size: 11 } }
                    },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        callbacks: {
                            label: ctx => {
                                const total = ctx.dataset.data.reduce((a, b) => a + b, 0);
                                const pct = total > 0 ? ((ctx.raw / total) * 100).toFixed(1) : 0;
                                return `${ctx.label}: ${ctx.raw.toLocaleString('en-IN')} (${pct}%)`;
                            }
                        }
                    }
                }
            }
        });
    }

    renderReverseMultiplierChart() {
        if (!this.reverseResult || !this.reverseResult.requiredAtEachStage || this.reverseResult.requiredAtEachStage.length === 0 || !this.chartJsLoaded) return;
        const canvas = this.template.querySelector('.reverse-multiplier-chart');
        if (!canvas) return;

        if (this._reverseMultiplierChart) this._reverseMultiplierChart.destroy();

        const stages = this.reverseResult.requiredAtEachStage;
        const targetCount = stages[stages.length - 1].count;
        const labels = stages.map(s => s.stageLabel);
        const multipliers = stages.map(s => targetCount > 0 ? parseFloat((s.count / targetCount).toFixed(1)) : 0);
        const bgColors = stages.map(s => {
            const c = STAGE_COLORS[s.stageKey] || '#94a3b8';
            return c + '33'; // 20% opacity
        });
        const borderColors = stages.map(s => STAGE_COLORS[s.stageKey] || '#94a3b8');

        this._reverseMultiplierChart = new window.Chart(canvas, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Effort Multiplier',
                    data: multipliers,
                    fill: true,
                    backgroundColor: bgColors[0],
                    borderColor: '#3b82f6',
                    borderWidth: 3,
                    pointBackgroundColor: borderColors,
                    pointBorderColor: '#ffffff',
                    pointBorderWidth: 2,
                    pointRadius: 8,
                    pointHoverRadius: 10,
                    tension: 0.3
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        callbacks: {
                            label: ctx => `${ctx.raw}x effort needed`,
                            afterLabel: ctx => `Count: ${stages[ctx.dataIndex].count.toLocaleString('en-IN')}`
                        }
                    }
                },
                scales: {
                    x: { grid: { display: false }, ticks: { font: { size: 12, weight: 'bold' } } },
                    y: {
                        beginAtZero: true,
                        grid: { color: '#f1f5f9' },
                        ticks: { callback: v => v + 'x' }
                    }
                }
            }
        });
    }

    // ═══ AI Chatbot Context (anonymized summary only - no PII) ═══

    get dashboardContextJson() {
        if (!this.dashboardData) return '';

        const parts = [];
        const d = this.dashboardData;

        // Funnel summary
        if (d.funnel) {
            parts.push('PIPELINE SUMMARY:');
            parts.push('Total Active Leads: ' + (d.funnel.totalLeads || 0));
            parts.push('Total Bookings: ' + (d.funnel.totalBookings || 0));
            parts.push('Overall Conversion Rate: ' + (d.funnel.overallConversionRate || 0) + '%');
            if (d.funnel.stages) {
                parts.push('FUNNEL STAGES:');
                d.funnel.stages.forEach(s => {
                    parts.push('- ' + s.stageLabel + ': ' + s.count + ' (Conversion: ' + s.conversionRate + '%, Cumulative: ' + s.cumulativeRate + '%)');
                });
            }
        }

        // Pipeline health
        if (d.health) {
            parts.push('PIPELINE HEALTH:');
            parts.push('Health Grade: ' + d.health.healthGrade + ' (Score: ' + d.health.healthScore + '/100)');
            if (d.health.components) {
                d.health.components.forEach(c => {
                    parts.push('- ' + c.name + ': ' + c.score + '/100 (' + c.status + ')');
                });
            }
        }

        // Source breakdown (category labels only - no PII)
        if (d.sources && d.sources.length > 0) {
            parts.push('LEAD SOURCES:');
            d.sources.forEach(s => {
                parts.push('- ' + s.source + ': ' + s.leadCount + ' leads, ' + s.bookingCount + ' bookings, ' + s.conversionRate + '% conversion');
            });
        }

        // Monthly trend
        if (d.monthlyTrend && d.monthlyTrend.length > 0) {
            parts.push('MONTHLY TREND (Historical):');
            d.monthlyTrend.forEach(m => {
                parts.push('- ' + m.periodLabel + ': ' + m.leads + ' leads, ' + m.siteVisits + ' site visits, ' + m.bookings + ' bookings');
            });
        }

        // Forward forecast
        if (d.forecast && d.forecast.monthlyForecasts) {
            parts.push('FORWARD FORECAST (Predicted):');
            d.forecast.monthlyForecasts.forEach(f => {
                parts.push('- ' + f.periodLabel + ': ' + f.predictedLeads + ' leads, ' + f.predictedSiteVisits + ' site visits, ' + f.predictedBookings + ' bookings (Revenue: ' + (f.predictedRevenue || 0) + ')');
            });
            parts.push('Lead Velocity Rate: ' + (d.forecast.leadVelocityRate || 0) + '%');
            parts.push('Avg Sales Cycle: ' + (d.forecast.avgSalesCycleDays || 0) + ' days');
        }

        // Average booking value
        if (d.avgBookingValue) {
            parts.push('Average Booking Value: ' + d.avgBookingValue);
        }

        return parts.join('\n');
    }

    // ═══ Utility ═══

    getStageFunnelCount(stageKey) {
        if (!this.dashboardData || !this.dashboardData.funnel) return 0;
        const stage = this.dashboardData.funnel.stages.find(s => s.stageKey === stageKey);
        return stage ? stage.count : 0;
    }

    formatNumber(value) {
        if (value == null) return '0';
        return Number(value).toLocaleString('en-IN');
    }

    formatCurrency(value) {
        if (value == null || value === 0) return '0';
        if (value >= 10000000) return (value / 10000000).toFixed(1) + ' Cr';
        if (value >= 100000) return (value / 100000).toFixed(1) + ' L';
        if (value >= 1000) return (value / 1000).toFixed(1) + ' K';
        return Number(value).toLocaleString('en-IN');
    }

    downloadFile(filename, content, mimeType) {
        const blob = new Blob([content], { type: mimeType });
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (!error) return 'An unexpected error occurred. Please try again.';
        if (typeof error === 'string') return error;
        if (error.body) {
            if (error.body.output && error.body.output.errors && error.body.output.errors.length > 0) {
                return error.body.output.errors.map(e => e.message).join(', ');
            }
            if (error.body.message) return error.body.message;
        }
        if (error.message) return error.message;
        return 'An unexpected error occurred. Please try again.';
    }
}