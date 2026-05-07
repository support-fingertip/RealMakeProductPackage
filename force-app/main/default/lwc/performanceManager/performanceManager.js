import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import CHARTJS from '@salesforce/resourceUrl/chartjs';

import getFilterOptions from '@salesforce/apex/PerformanceTargetController.getFilterOptions';
import getDashboardData from '@salesforce/apex/PerformanceTargetController.getDashboardData';
import getLeaderboard from '@salesforce/apex/PerformanceTargetController.getLeaderboard';
import getTargets from '@salesforce/apex/PerformanceTargetController.getTargets';
import deleteTarget from '@salesforce/apex/PerformanceTargetController.deleteTarget';
import getTrendData from '@salesforce/apex/PerformanceTargetController.getTrendData';
import exportCSV from '@salesforce/apex/PerformanceTargetController.exportCSV';
import recalculateActuals from '@salesforce/apex/PerformanceTargetController.recalculateActuals';

const VIEWS = { DASHBOARD: 'dashboard', TARGETS: 'targets', DETAIL: 'detail' };

const METRIC_COLORS = {
    Leads_Generated: '#3b82f6',
    Site_Visits_Completed: '#8b5cf6',
    Bookings_Closed: '#22c55e',
    Revenue: '#f59e0b'
};

const STATUS_COLORS = {
    Achieved: '#22c55e',
    'On Track': '#3b82f6',
    'At Risk': '#f59e0b',
    Behind: '#ef4444'
};

export default class PerformanceManager extends NavigationMixin(LightningElement) {

    // ═══ State ═══
    @track activeView = VIEWS.DASHBOARD;
    @track isLoading = false;
    @track hasLoaded = false;
    chartJsLoaded = false;

    // Filter
    @track filterOptions = { projects: [], metrics: [], periodTypes: [], users: [] };
    @track selectedProjectId = '';
    @track selectedMetric = '';
    @track selectedPeriodType = '';
    @track selectedPeriodValue = '';
    @track selectedAssigneeId = '';
    @track selectedLevel = '';
    @track filterStartDate = '';
    @track filterEndDate = '';

    // Dashboard
    @track dashboardData = null;
    @track leaderboardEntries = [];

    // Targets
    @track targetList = [];

    // Detail
    @track selectedTarget = null;
    @track trendData = [];

    // Form
    @track showForm = false;
    @track formMode = 'create';
    @track editTarget = null;

    // Charts
    _barChart = null;
    _donutChart = null;
    _trendChart = null;
    _detailTrendChart = null;

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

    // ═══ Computed Getters ═══

    get isDashboardView() {
        return this.activeView === VIEWS.DASHBOARD;
    }

    get isTargetsView() {
        return this.activeView === VIEWS.TARGETS;
    }

    get isDetailView() {
        return this.activeView === VIEWS.DETAIL;
    }

    get dashboardTabClass() {
        return this.activeView === VIEWS.DASHBOARD ? 'view-tab view-tab--active' : 'view-tab';
    }

    get targetsTabClass() {
        return this.activeView === VIEWS.TARGETS ? 'view-tab view-tab--active' : 'view-tab';
    }

    get projectOptions() {
        const opts = [{ label: 'All Projects', value: '' }];
        if (this.filterOptions.projects) {
            this.filterOptions.projects.forEach(p => {
                opts.push({ label: p.label, value: p.value });
            });
        }
        return opts;
    }

    get metricOptions() {
        const opts = [{ label: 'All Metrics', value: '' }];
        if (this.filterOptions.metrics) {
            this.filterOptions.metrics.forEach(m => {
                opts.push({ label: m.label, value: m.value });
            });
        }
        return opts;
    }

    get periodTypeOptions() {
        const opts = [{ label: 'All Period Types', value: '' }];
        if (this.filterOptions.periods) {
            this.filterOptions.periods.forEach(p => {
                opts.push({ label: p.label, value: p.value });
            });
        }
        return opts;
    }

    get levelOptions() {
        const opts = [{ label: 'All Levels', value: '' }];
        if (this.filterOptions.targetLevels) {
            this.filterOptions.targetLevels.forEach(l => {
                opts.push({ label: l.label, value: l.value });
            });
        }
        return opts;
    }

    get assigneeOptions() {
        const opts = [{ label: 'All Assignees', value: '' }];
        if (this.filterOptions.users) {
            this.filterOptions.users.forEach(u => {
                opts.push({ label: u.label, value: u.value });
            });
        }
        return opts;
    }

    get dynamicPeriodOptions() {
        const opts = [{ label: 'All Periods', value: '' }];
        const now = new Date();
        const currentYear = now.getFullYear();
        const months = [
            'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'
        ];

        if (this.selectedPeriodType === 'Monthly') {
            for (let year = currentYear - 1; year <= currentYear + 1; year++) {
                for (let m = 0; m < 12; m++) {
                    const value = `${year}-${String(m + 1).padStart(2, '0')}`;
                    opts.push({ label: `${months[m]} ${year}`, value });
                }
            }
        } else if (this.selectedPeriodType === 'Quarterly') {
            const quarters = ['Q1 (Jan-Mar)', 'Q2 (Apr-Jun)', 'Q3 (Jul-Sep)', 'Q4 (Oct-Dec)'];
            for (let year = currentYear - 1; year <= currentYear + 1; year++) {
                quarters.forEach((q, idx) => {
                    opts.push({ label: `${q} ${year}`, value: `${year}-Q${idx + 1}` });
                });
            }
        } else if (this.selectedPeriodType === 'Yearly') {
            for (let year = currentYear - 2; year <= currentYear + 1; year++) {
                opts.push({ label: `${year}`, value: `${year}` });
            }
        }
        return opts;
    }

    get showDynamicPeriodSelector() {
        return this.selectedPeriodType === 'Monthly' || this.selectedPeriodType === 'Quarterly' || this.selectedPeriodType === 'Yearly';
    }

    get filterJson() {
        const filter = {};
        if (this.selectedProjectId) filter.projectId = this.selectedProjectId;
        if (this.selectedMetric) filter.metric = this.selectedMetric;
        if (this.selectedPeriodType) filter.periodType = this.selectedPeriodType;
        if (this.selectedAssigneeId) filter.assigneeId = this.selectedAssigneeId;
        if (this.selectedLevel) filter.level = this.selectedLevel;
        if (this.filterStartDate) filter.startDate = this.filterStartDate;
        if (this.filterEndDate) filter.endDate = this.filterEndDate;
        return JSON.stringify(filter);
    }

    get totalTargets() {
        if (!this.dashboardData) return 0;
        return this.dashboardData.totalTargets || 0;
    }

    get avgAchievement() {
        if (!this.dashboardData) return '0.0';
        return (this.dashboardData.avgAchievement || 0).toFixed(1);
    }

    get topPerformer() {
        if (!this.dashboardData || !this.dashboardData.topPerformerName) return 'N/A';
        return this.dashboardData.topPerformerName;
    }

    get targetsAtRisk() {
        if (!this.dashboardData) return 0;
        return this.dashboardData.targetsAtRisk || 0;
    }

    get hasTargets() {
        return this.targetList && this.targetList.length > 0;
    }

    get hasLevelBreakdown() {
        return this.levelBreakdown && this.levelBreakdown.length > 0;
    }

    get levelBreakdown() {
        if (!this.dashboardData || !this.dashboardData.targets) return [];

        const LEVEL_ICONS = {
            Organization: 'standard:account',
            Team: 'standard:groups',
            User: 'standard:user'
        };
        const LEVEL_COLORS = {
            Organization: '#8b5cf6',
            Team: '#0ea5e9',
            User: '#22c55e'
        };

        const levelMap = {};
        this.dashboardData.targets.forEach(ts => {
            const level = (ts.target && ts.target.Target_Level__c) || 'User';
            if (!levelMap[level]) {
                levelMap[level] = { count: 0, totalTarget: 0, totalActual: 0, totalPct: 0 };
            }
            const entry = levelMap[level];
            entry.count++;
            const tv = (ts.target && ts.target.Target_Value__c) || 0;
            const actual = ts.liveActual || 0;
            entry.totalTarget += tv;
            entry.totalActual += actual;
            const pct = tv > 0 ? (actual / tv) * 100 : 0;
            entry.totalPct += pct;
        });

        const levels = ['Organization', 'Team', 'User'];
        const results = [];
        levels.forEach(level => {
            const entry = levelMap[level];
            if (!entry) return;
            const avgPct = entry.count > 0 ? entry.totalPct / entry.count : 0;
            const overallPct = entry.totalTarget > 0 ? (entry.totalActual / entry.totalTarget) * 100 : 0;
            const cappedPct = Math.min(overallPct, 100);
            const color = LEVEL_COLORS[level] || '#94a3b8';
            results.push({
                level: level,
                iconName: LEVEL_ICONS[level] || 'standard:record',
                count: entry.count,
                avgAchievementDisplay: avgPct.toFixed(1) + '%',
                totalTargetDisplay: this.formatNumber(entry.totalTarget),
                totalActualDisplay: this.formatNumber(entry.totalActual),
                overallPctDisplay: overallPct.toFixed(1) + '%',
                progressBarStyle: `width: ${cappedPct}%; background: ${color};`
            });
        });

        return results;
    }

    get hasMetricBreakdown() {
        return this.dashboardData && this.dashboardData.metricBreakdown && this.dashboardData.metricBreakdown.length > 0;
    }

    get metricProgressCards() {
        if (!this.dashboardData || !this.dashboardData.metricBreakdown) return [];
        return this.dashboardData.metricBreakdown.map(mb => {
            const pct = mb.totalTarget > 0 ? (mb.totalActual / mb.totalTarget) * 100 : 0;
            const cappedPct = Math.min(pct, 100);
            const status = this.computeStatus(pct);
            const color = METRIC_COLORS[mb.metric] || '#94a3b8';
            return {
                name: mb.metric,
                label: mb.metricLabel || (mb.metric || '').replace(/_/g, ' '),
                actualDisplay: this.formatNumber(mb.totalActual),
                targetDisplay: this.formatNumber(mb.totalTarget),
                pctDisplay: pct.toFixed(1) + '%',
                status: status,
                statusClass: 'status-badge status-' + status.replace(/\s/g, '-').toLowerCase(),
                progressBarClass: 'progress-bar-fill',
                progressBarStyle: `width: ${cappedPct}%; background: ${color};`
            };
        });
    }

    get hasTargetProgressList() {
        return this.dashboardData && this.dashboardData.targets && this.dashboardData.targets.length > 0;
    }

    get targetProgressList() {
        if (!this.dashboardData || !this.dashboardData.targets) return [];
        return this.dashboardData.targets.map(ts => {
            const t = ts.target || {};
            const actual = ts.liveActual || 0;
            const tv = t.Target_Value__c || 0;
            const pct = tv > 0 ? (actual / tv) * 100 : 0;
            const cappedPct = Math.min(pct, 100);
            const status = this.computeStatus(pct);
            const color = METRIC_COLORS[t.Metric__c] || '#94a3b8';
            return {
                id: t.Id,
                name: t.Name || '',
                assigneeName: ts.assigneeName || 'Unassigned',
                metricDisplay: (t.Metric__c || '').replace(/_/g, ' '),
                actualDisplay: this.formatNumber(actual),
                targetDisplay: this.formatNumber(tv),
                pctDisplay: pct.toFixed(1) + '%',
                progressBarClass: 'progress-bar-fill',
                progressBarStyle: `width: ${cappedPct}%; background: ${color};`
            };
        });
    }

    get formattedTargetList() {
        const levelBadgeMap = {
            Organization: 'level-badge level-badge--org',
            Team: 'level-badge level-badge--team',
            User: 'level-badge level-badge--user'
        };
        return (this.targetList || []).map(ts => {
            const t = ts.target || {};
            const actual = ts.liveActual || 0;
            const tv = t.Target_Value__c || 0;
            const pct = tv > 0 ? (actual / tv) * 100 : 0;
            const status = this.computeStatus(pct);
            return {
                Id: t.Id,
                Name: t.Name,
                Target_Level__c: t.Target_Level__c,
                levelBadgeClass: levelBadgeMap[t.Target_Level__c] || 'level-badge',
                Status__c: status,
                achievementDisplay: pct.toFixed(1) + '%',
                statusClass: 'status-badge status-' + status.replace(/\s/g, '-').toLowerCase(),
                metricDisplay: (t.Metric__c || '').replace(/_/g, ' '),
                assigneeName: ts.assigneeName || 'Unassigned',
                periodDisplay: (t.Period_Type__c || '') + ' (' + (t.Period_Start__c || '') + ' - ' + (t.Period_End__c || '') + ')',
                targetDisplay: this.formatNumber(tv),
                actualDisplay: this.formatNumber(actual)
            };
        });
    }

    get detailAchievementDisplay() {
        if (!this.selectedTarget) return '0.0%';
        const t = this.selectedTarget.target || {};
        const tv = t.Target_Value__c || 0;
        const actual = this.selectedTarget.liveActual || 0;
        const pct = tv > 0 ? (actual / tv) * 100 : 0;
        return pct.toFixed(1) + '%';
    }

    get detailStatusClass() {
        if (!this.selectedTarget) return 'status-badge';
        const t = this.selectedTarget.target || {};
        const tv = t.Target_Value__c || 0;
        const actual = this.selectedTarget.liveActual || 0;
        const pct = tv > 0 ? (actual / tv) * 100 : 0;
        const status = this.computeStatus(pct);
        return 'status-badge status-' + status.replace(/\s/g, '-').toLowerCase();
    }

    get detailMetricDisplay() {
        if (!this.selectedTarget) return '';
        const t = this.selectedTarget.target || {};
        return (t.Metric__c || '').replace(/_/g, ' ');
    }

    get detailAssigneeName() {
        if (!this.selectedTarget) return 'Unassigned';
        return this.selectedTarget.assigneeName || 'Unassigned';
    }

    get detailPeriodDisplay() {
        if (!this.selectedTarget) return '';
        const t = this.selectedTarget.target || {};
        return (t.Period_Type__c || '') + ' (' + (t.Period_Start__c || '') + ' - ' + (t.Period_End__c || '') + ')';
    }

    get detailTargetDisplay() {
        if (!this.selectedTarget) return '0';
        const t = this.selectedTarget.target || {};
        return this.formatNumber(t.Target_Value__c);
    }

    get detailActualDisplay() {
        if (!this.selectedTarget) return '0';
        return this.formatNumber(this.selectedTarget.liveActual);
    }

    get detailTargetName() {
        if (!this.selectedTarget) return '';
        const t = this.selectedTarget.target || {};
        return t.Name || '';
    }

    get detailStatusLabel() {
        if (!this.selectedTarget) return 'Behind';
        const t = this.selectedTarget.target || {};
        const tv = t.Target_Value__c || 0;
        const actual = this.selectedTarget.liveActual || 0;
        const pct = tv > 0 ? (actual / tv) * 100 : 0;
        return this.computeStatus(pct);
    }

    get sourceFilterForClone() {
        const filter = {};
        if (this.selectedMetric) filter.metric = this.selectedMetric;
        if (this.selectedPeriodType) filter.periodType = this.selectedPeriodType;
        if (this.filterStartDate) filter.periodStart = this.filterStartDate;
        if (this.filterEndDate) filter.periodEnd = this.filterEndDate;
        if (this.selectedProjectId) filter.projectId = this.selectedProjectId;
        return filter;
    }

    // ═══ Data Loading ═══

    async loadDashboard() {
        this.isLoading = true;
        try {
            const [dashboard, leaderboard] = await Promise.all([
                getDashboardData({ filterJson: this.filterJson }),
                getLeaderboard({ filterJson: this.filterJson })
            ]);
            this.dashboardData = dashboard;
            this.leaderboardEntries = leaderboard || [];
            this.renderChartsAfterDelay();
        } catch (error) {
            this.showToast('Error', 'Failed to load dashboard: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadTargets() {
        this.isLoading = true;
        try {
            this.targetList = await getTargets({ filterJson: this.filterJson });
        } catch (error) {
            this.showToast('Error', 'Failed to load targets: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadDetail(targetId) {
        this.isLoading = true;
        try {
            const targets = await getTargets({ filterJson: JSON.stringify({ targetId: targetId }) });
            if (targets && targets.length > 0) {
                this.selectedTarget = targets[0];
            }
            this.trendData = await getTrendData({ targetId: targetId });
            this.renderDetailChartAfterDelay();
        } catch (error) {
            this.showToast('Error', 'Failed to load target details: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ═══ Chart Rendering ═══

    renderChartsAfterDelay() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.renderCharts();
        }, 300);
    }

    renderDetailChartAfterDelay() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.renderDetailTrendChart();
        }, 300);
    }

    renderCharts() {
        if (!this.chartJsLoaded || !this.dashboardData) return;

        this.renderBarChart();
        this.renderDonutChart();
        this.renderTrendChart();
    }

    renderBarChart() {
        const canvas = this.template.querySelector('canvas.bar-chart');
        if (!canvas) return;

        if (this._barChart) {
            this._barChart.destroy();
        }

        const breakdown = this.dashboardData.metricBreakdown || [];
        const labels = breakdown.map(m => m.metricLabel || (m.metric || '').replace(/_/g, ' '));
        const targets = breakdown.map(m => m.totalTarget || 0);
        const actuals = breakdown.map(m => m.totalActual || 0);
        const bgColors = breakdown.map(m => METRIC_COLORS[m.metric] || '#94a3b8');

        this._barChart = new window.Chart(canvas.getContext('2d'), {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: 'Target',
                        data: targets,
                        backgroundColor: bgColors.map(c => c + '40'),
                        borderColor: bgColors,
                        borderWidth: 2,
                        borderRadius: 6,
                        barPercentage: 0.6,
                        categoryPercentage: 0.7
                    },
                    {
                        label: 'Actual',
                        data: actuals,
                        backgroundColor: bgColors,
                        borderColor: bgColors,
                        borderWidth: 0,
                        borderRadius: 6,
                        barPercentage: 0.6,
                        categoryPercentage: 0.7
                    }
                ]
            },
            options: {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'top',
                        labels: {
                            font: { family: "'DM Sans', sans-serif", size: 12, weight: '600' },
                            padding: 16,
                            usePointStyle: true,
                            pointStyleWidth: 10
                        }
                    },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        titleFont: { family: "'DM Sans', sans-serif", size: 13 },
                        bodyFont: { family: "'DM Sans', sans-serif", size: 12 },
                        cornerRadius: 8,
                        padding: 12
                    }
                },
                scales: {
                    x: {
                        grid: { color: '#f1f5f9', drawBorder: false },
                        ticks: {
                            font: { family: "'DM Sans', sans-serif", size: 11 },
                            color: '#94a3b8'
                        }
                    },
                    y: {
                        grid: { display: false },
                        ticks: {
                            font: { family: "'DM Sans', sans-serif", size: 12, weight: '600' },
                            color: '#334155'
                        }
                    }
                }
            }
        });
    }

    renderDonutChart() {
        const canvas = this.template.querySelector('canvas.donut-chart');
        if (!canvas) return;

        if (this._donutChart) {
            this._donutChart.destroy();
        }

        // Compute status breakdown from targets since Apex doesn't provide it
        const statusCounts = {};
        if (this.dashboardData.targets) {
            this.dashboardData.targets.forEach(ts => {
                const tv = ts.target?.Target_Value__c || 0;
                const pct = tv > 0 ? (ts.liveActual / tv) * 100 : 0;
                let status;
                if (pct >= 100) status = 'Achieved';
                else if (pct >= 75) status = 'On Track';
                else if (pct >= 50) status = 'At Risk';
                else status = 'Behind';
                statusCounts[status] = (statusCounts[status] || 0) + 1;
            });
        }
        const labels = Object.keys(statusCounts);
        const data = Object.values(statusCounts);
        const colors = labels.map(l => STATUS_COLORS[l] || '#94a3b8');

        this._donutChart = new window.Chart(canvas.getContext('2d'), {
            type: 'doughnut',
            data: {
                labels: labels,
                datasets: [{
                    data: data,
                    backgroundColor: colors,
                    borderWidth: 3,
                    borderColor: '#ffffff',
                    hoverOffset: 8
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                cutout: '65%',
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            font: { family: "'DM Sans', sans-serif", size: 12, weight: '600' },
                            padding: 16,
                            usePointStyle: true,
                            pointStyleWidth: 10
                        }
                    },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        titleFont: { family: "'DM Sans', sans-serif", size: 13 },
                        bodyFont: { family: "'DM Sans', sans-serif", size: 12 },
                        cornerRadius: 8,
                        padding: 12,
                        callbacks: {
                            label: function(context) {
                                const total = context.dataset.data.reduce((a, b) => a + b, 0);
                                const pct = total > 0 ? ((context.parsed / total) * 100).toFixed(1) : 0;
                                return context.label + ': ' + context.parsed + ' (' + pct + '%)';
                            }
                        }
                    }
                }
            }
        });
    }

    renderTrendChart() {
        const canvas = this.template.querySelector('canvas.trend-chart');
        if (!canvas) return;

        if (this._trendChart) {
            this._trendChart.destroy();
        }

        const trendPoints = this.dashboardData.trendData || [];
        const labels = trendPoints.map(p => p.snapshotDate || '');
        const data = trendPoints.map(p => p.achievementPct || 0);

        this._trendChart = new window.Chart(canvas.getContext('2d'), {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Achievement %',
                    data: data,
                    borderColor: '#0ea5e9',
                    backgroundColor: 'rgba(14, 165, 233, 0.1)',
                    borderWidth: 3,
                    fill: true,
                    tension: 0.4,
                    pointBackgroundColor: '#0ea5e9',
                    pointBorderColor: '#ffffff',
                    pointBorderWidth: 2,
                    pointRadius: 5,
                    pointHoverRadius: 7
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        display: false
                    },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        titleFont: { family: "'DM Sans', sans-serif", size: 13 },
                        bodyFont: { family: "'DM Sans', sans-serif", size: 12 },
                        cornerRadius: 8,
                        padding: 12,
                        callbacks: {
                            label: function(context) {
                                return 'Achievement: ' + context.parsed.y.toFixed(1) + '%';
                            }
                        }
                    }
                },
                scales: {
                    x: {
                        grid: { color: '#f1f5f9', drawBorder: false },
                        ticks: {
                            font: { family: "'DM Sans', sans-serif", size: 11 },
                            color: '#94a3b8'
                        }
                    },
                    y: {
                        grid: { color: '#f1f5f9', drawBorder: false },
                        ticks: {
                            font: { family: "'DM Sans', sans-serif", size: 11 },
                            color: '#94a3b8',
                            callback: function(value) {
                                return value + '%';
                            }
                        },
                        suggestedMin: 0,
                        suggestedMax: 100
                    }
                }
            }
        });
    }

    renderDetailTrendChart() {
        if (!this.chartJsLoaded || !this.trendData || this.trendData.length === 0) return;

        const canvas = this.template.querySelector('canvas.detail-trend-chart');
        if (!canvas) return;

        if (this._detailTrendChart) {
            this._detailTrendChart.destroy();
        }

        const labels = this.trendData.map(p => p.snapshotDate || '');
        const actuals = this.trendData.map(p => p.actualValue || 0);
        const targetVal = this.selectedTarget && this.selectedTarget.target
            ? (this.selectedTarget.target.Target_Value__c || 0) : 0;
        const targets = this.trendData.map(() => targetVal);

        this._detailTrendChart = new window.Chart(canvas.getContext('2d'), {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: 'Actual',
                        data: actuals,
                        borderColor: '#22c55e',
                        backgroundColor: 'rgba(34, 197, 94, 0.1)',
                        borderWidth: 3,
                        fill: true,
                        tension: 0.4,
                        pointBackgroundColor: '#22c55e',
                        pointBorderColor: '#ffffff',
                        pointBorderWidth: 2,
                        pointRadius: 5
                    },
                    {
                        label: 'Target',
                        data: targets,
                        borderColor: '#ef4444',
                        backgroundColor: 'transparent',
                        borderWidth: 2,
                        borderDash: [6, 4],
                        fill: false,
                        tension: 0,
                        pointRadius: 3,
                        pointBackgroundColor: '#ef4444'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'top',
                        labels: {
                            font: { family: "'DM Sans', sans-serif", size: 12, weight: '600' },
                            padding: 16,
                            usePointStyle: true,
                            pointStyleWidth: 10
                        }
                    },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        titleFont: { family: "'DM Sans', sans-serif", size: 13 },
                        bodyFont: { family: "'DM Sans', sans-serif", size: 12 },
                        cornerRadius: 8,
                        padding: 12
                    }
                },
                scales: {
                    x: {
                        grid: { color: '#f1f5f9', drawBorder: false },
                        ticks: {
                            font: { family: "'DM Sans', sans-serif", size: 11 },
                            color: '#94a3b8'
                        }
                    },
                    y: {
                        grid: { color: '#f1f5f9', drawBorder: false },
                        ticks: {
                            font: { family: "'DM Sans', sans-serif", size: 11 },
                            color: '#94a3b8'
                        },
                        beginAtZero: true
                    }
                }
            }
        });
    }

    // ═══ View Navigation ═══

    handleViewChange(event) {
        const view = event.currentTarget.dataset.view;
        this.switchView(view);
    }

    switchView(view) {
        this.activeView = view;
        this.destroyAllCharts();

        if (view === VIEWS.DASHBOARD) {
            this.loadDashboard();
        } else if (view === VIEWS.TARGETS) {
            this.loadTargets();
        }
    }

    handleBack() {
        if (this.activeView === VIEWS.DETAIL) {
            this.selectedTarget = null;
            this.trendData = [];
            this.destroyDetailChart();
            this.switchView(VIEWS.TARGETS);
        } else {
            this.switchView(VIEWS.DASHBOARD);
        }
    }

    destroyAllCharts() {
        if (this._barChart) { this._barChart.destroy(); this._barChart = null; }
        if (this._donutChart) { this._donutChart.destroy(); this._donutChart = null; }
        if (this._trendChart) { this._trendChart.destroy(); this._trendChart = null; }
        this.destroyDetailChart();
    }

    destroyDetailChart() {
        if (this._detailTrendChart) { this._detailTrendChart.destroy(); this._detailTrendChart = null; }
    }

    // ═══ Filter Handlers ═══

    handleProjectChange(event) {
        this.selectedProjectId = event.detail.value;
        this.reloadCurrentView();
    }

    handleMetricChange(event) {
        this.selectedMetric = event.detail.value;
        this.reloadCurrentView();
    }

    handlePeriodTypeChange(event) {
        this.selectedPeriodType = event.detail.value;
        this.selectedPeriodValue = '';
        this.filterStartDate = '';
        this.filterEndDate = '';
        this.reloadCurrentView();
    }

    handlePeriodValueChange(event) {
        this.selectedPeriodValue = event.detail.value;
        if (!this.selectedPeriodValue) {
            this.filterStartDate = '';
            this.filterEndDate = '';
        } else if (this.selectedPeriodType === 'Monthly') {
            const [year, month] = this.selectedPeriodValue.split('-').map(Number);
            const start = new Date(year, month - 1, 1);
            const end = new Date(year, month, 0);
            this.filterStartDate = this.formatFilterDate(start);
            this.filterEndDate = this.formatFilterDate(end);
        } else if (this.selectedPeriodType === 'Quarterly') {
            const [year, q] = this.selectedPeriodValue.split('-Q');
            const quarter = parseInt(q, 10);
            const startMonth = (quarter - 1) * 3;
            const start = new Date(parseInt(year, 10), startMonth, 1);
            const end = new Date(parseInt(year, 10), startMonth + 3, 0);
            this.filterStartDate = this.formatFilterDate(start);
            this.filterEndDate = this.formatFilterDate(end);
        } else if (this.selectedPeriodType === 'Yearly') {
            const year = parseInt(this.selectedPeriodValue, 10);
            this.filterStartDate = `${year}-01-01`;
            this.filterEndDate = `${year}-12-31`;
        }
        this.reloadCurrentView();
    }

    handleLevelChange(event) {
        this.selectedLevel = event.detail.value;
        this.reloadCurrentView();
    }

    handleAssigneeChange(event) {
        this.selectedAssigneeId = event.detail.value;
        this.reloadCurrentView();
    }

    handleStartDateChange(event) {
        this.filterStartDate = event.detail.value;
        this.reloadCurrentView();
    }

    handleEndDateChange(event) {
        this.filterEndDate = event.detail.value;
        this.reloadCurrentView();
    }

    handleClearFilters() {
        this.selectedProjectId = '';
        this.selectedMetric = '';
        this.selectedPeriodType = '';
        this.selectedPeriodValue = '';
        this.selectedAssigneeId = '';
        this.selectedLevel = '';
        this.filterStartDate = '';
        this.filterEndDate = '';
        this.reloadCurrentView();
    }

    handleLevelCardClick(event) {
        const level = event.currentTarget.dataset.level;
        if (level) {
            this.selectedLevel = level;
            this.reloadCurrentView();
        }
    }

    reloadCurrentView() {
        if (this.activeView === VIEWS.DASHBOARD) {
            this.loadDashboard();
        } else if (this.activeView === VIEWS.TARGETS) {
            this.loadTargets();
        }
    }

    // ═══ Target Actions ═══

    handleCreateTarget() {
        this.formMode = 'create';
        this.editTarget = null;
        this.showForm = true;
    }

    handleBulkAssign() {
        this.formMode = 'bulk';
        this.editTarget = null;
        this.showForm = true;
    }

    handleCloneTargets() {
        this.formMode = 'clone';
        this.editTarget = null;
        this.showForm = true;
    }

    handleEditTarget(event) {
        const targetId = event.currentTarget.dataset.targetid;
        const ts = this.targetList.find(t => t.target && t.target.Id === targetId);
        if (ts) {
            this.formMode = 'edit';
            this.editTarget = ts.target;
            this.showForm = true;
        }
    }

    async handleDeleteTarget(event) {
        const targetId = event.currentTarget.dataset.targetid;
        if (!targetId) return;

        this.isLoading = true;
        try {
            await deleteTarget({ targetId: targetId });
            this.showToast('Success', 'Target deleted successfully.', 'success');
            this.reloadCurrentView();
        } catch (error) {
            this.showToast('Error', 'Failed to delete target: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleTargetSaved() {
        this.showForm = false;
        this.editTarget = null;
        this.reloadCurrentView();
    }

    handleFormCancel() {
        this.showForm = false;
        this.editTarget = null;
    }

    handleTargetClick(event) {
        const targetId = event.currentTarget.dataset.targetid;
        if (!targetId) return;
        this.activeView = VIEWS.DETAIL;
        this.loadDetail(targetId);
    }

    // ═══ Export & Recalculate ═══

    async handleExportCSV() {
        this.isLoading = true;
        try {
            const csvContent = await exportCSV({ filterJson: this.filterJson });
            this.downloadCSV(csvContent);
            this.showToast('Success', 'CSV exported successfully.', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to export CSV: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    downloadCSV(csvContent) {
        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = 'performance_targets_' + new Date().toISOString().slice(0, 10) + '.csv';
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    async handleRecalculate() {
        this.isLoading = true;
        try {
            await recalculateActuals({ filterJson: this.filterJson });
            this.showToast('Success', 'Actuals recalculated successfully.', 'success');
            this.reloadCurrentView();
        } catch (error) {
            this.showToast('Error', 'Failed to recalculate: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.reloadCurrentView();
    }

    // ═══ Utilities ═══

    stopPropagation(event) {
        event.stopPropagation();
    }

    computeStatus(pct) {
        if (pct >= 100) return 'Achieved';
        if (pct >= 75) return 'On Track';
        if (pct >= 50) return 'At Risk';
        return 'Behind';
    }

    formatNumber(value) {
        if (value == null) return '0';
        if (value >= 1000000) return (value / 1000000).toFixed(1) + 'M';
        if (value >= 1000) return (value / 1000).toFixed(1) + 'K';
        return String(Math.round(value));
    }

    formatFilterDate(d) {
        const year = d.getFullYear();
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
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