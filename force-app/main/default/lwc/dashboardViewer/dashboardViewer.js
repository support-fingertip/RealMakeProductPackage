import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableDashboards from '@salesforce/apex/DashboardConfigController.getAvailableDashboards';
import getDashboardConfig from '@salesforce/apex/DashboardConfigController.getDashboardConfig';
import getPicklistValues from '@salesforce/apex/DashboardConfigController.getPicklistValues';
import getTopLevelUsers from '@salesforce/apex/DashboardConfigController.getTopLevelUsers';
import getSubordinateUsers from '@salesforce/apex/DashboardConfigController.getSubordinateUsers';
import getTopLevelManagers from '@salesforce/apex/DashboardConfigController.getTopLevelManagers';
import getDirectReports from '@salesforce/apex/DashboardConfigController.getDirectReports';
import getDashboardData from '@salesforce/apex/DashboardDataService.getDashboardData';
import getReportData from '@salesforce/apex/DashboardDataService.getReportData';

// Multi-color palette for bar charts — each bar gets a different vivid color
const MULTI_BAR_COLORS = [
    { f: '#0070d2', l: '#1e9bff' },
    { f: '#2e844a', l: '#43d17a' },
    { f: '#e87400', l: '#f4a127' },
    { f: '#7c4dff', l: '#a87fff' },
    { f: '#0b827c', l: '#12b8b0' },
    { f: '#c23934', l: '#e74c3c' },
    { f: '#e3066a', l: '#ff4d9e' },
    { f: '#07aee3', l: '#29ccff' },
];

const CHART_COLORS = [
    '#0176d3', '#2e844a', '#dd7a01', '#ea001e', '#9050e9',
    '#0b827c', '#e3066a', '#16325c', '#f59e0b', '#6366f1',
    '#ec4899', '#14b8a6', '#f97316', '#8b5cf6'
];

// Color → soft background map for emoji icon wraps
const COLOR_BG_MAP = {
    '#0070d2': 'rgba(0,112,210,0.12)',   '#0176d3': 'rgba(1,118,211,0.12)',
    '#2e844a': 'rgba(46,132,74,0.12)',   '#45c65a': 'rgba(69,198,90,0.12)',
    '#dd7a01': 'rgba(221,122,1,0.12)',   '#e87400': 'rgba(232,116,0,0.12)',
    '#ea001e': 'rgba(234,0,30,0.12)',    '#c23934': 'rgba(194,57,52,0.12)',
    '#9050e9': 'rgba(144,80,233,0.12)',  '#7c4dff': 'rgba(124,77,255,0.12)',
    '#0b827c': 'rgba(11,130,124,0.12)', '#16325c': 'rgba(22,50,92,0.12)',
    '#e3066a': 'rgba(227,6,106,0.12)',   '#07aee3': 'rgba(7,174,227,0.12)',
};

export default class DashboardViewer extends LightningElement {
    @track availableDashboards = [];
    @track selectedDashboardId = '';
    @track dashboardConfig = null;
    @track components = [];
    @track filterConfigs = [];
    @track activeFilters = {};
    @track filterPicklistOptions = {};

    @track isLoading = false;
    @track isDashboardLoading = false;
    @track componentData = {};

    @track headerConfig = null;
    @track hierarchyState = {};

    @track showReportModal = false;
    @track reportModalTitle = '';
    @track reportColumns = [];
    @track reportRows = [];
    @track reportTotalRecords = 0;
    @track isReportLoading = false;
    @track reportComponentId = '';

    connectedCallback() {
        this.loadDashboards();
    }

    loadDashboards() {
        this.isLoading = true;
        getAvailableDashboards()
            .then(result => {
                this.availableDashboards = result;
                this.isLoading = false;
                if (result.length === 1) {
                    this.selectedDashboardId = result[0].id;
                    this.loadDashboard(result[0].id);
                }
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load dashboards', 'error');
                this.isLoading = false;
                console.error(error);
            });
    }

    get dashboardOptions() { return this.availableDashboards.map(d => ({ label: d.name, value: d.id })); }
    get hasDashboards() { return this.availableDashboards.length > 0; }
    get noDashboards() { return !this.isLoading && this.availableDashboards.length === 0; }
    get showDashboard() { return this.dashboardConfig !== null; }
    get dashboardTitle() { return this.dashboardConfig ? this.dashboardConfig.Name : ''; }
    get hasFilters() { return this.filterConfigs.length > 0; }
    get hasReportRows() { return this.reportRows.length > 0; }

    get hasHeader() { return this.headerConfig && (this.headerConfig.title || this.headerConfig.subtitle); }
    get headerTitle() { return this.headerConfig ? this.headerConfig.title : ''; }
    get headerSubtitle() { return this.headerConfig ? this.headerConfig.subtitle : ''; }
    get showHeaderDate() { return this.headerConfig && this.headerConfig.showDate; }
    get headerStyle() {
        if (!this.headerConfig) return '';
        const gs = this.headerConfig.gradientStart || '#1b2a4a';
        const ge = this.headerConfig.gradientEnd || '#0176d3';
        const tc = this.headerConfig.textColor || '#ffffff';
        return `background: linear-gradient(135deg, ${gs} 0%, ${ge} 100%); color: ${tc};`;
    }
    get currentDateFormatted() {
        return new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
    }

    handleDashboardChange(event) {
        this.selectedDashboardId = event.detail.value;
        this.loadDashboard(this.selectedDashboardId);
    }

    loadDashboard(configId) {
        this.isDashboardLoading = true;
        this.componentData = {};

        getDashboardConfig({ configId })
            .then(config => {
                this.dashboardConfig = config;
                const json = JSON.parse(config.Configuration_JSON__c);
                this.components = (json.components || []).sort((a, b) => (a.order || 0) - (b.order || 0));
                this.filterConfigs = json.filters || [];
                this.headerConfig = json.header || null;
                this.activeFilters = {};

                this.filterConfigs.forEach(f => {
                    if (f.defaultValue) {
                        this.activeFilters[f.id] = { filterId: f.id, field: f.field, type: f.type, value: f.defaultValue };
                    }
                });

                const plPromises = this.filterConfigs
                    .filter(f => f.type === 'picklist' && f.object && f.field)
                    .map(f => getPicklistValues({ objectApiName: f.object, fieldApiName: f.field })
                        .then(options => { this.filterPicklistOptions = { ...this.filterPicklistOptions, [f.id]: options.map(o => ({ label: o.label, value: o.value })) }; })
                        .catch(e => console.error('Picklist error:', e))
                    );

                this.hierarchyState = {};
                const hierPromises = this.filterConfigs
                    .filter(f => f.type === 'hierarchy')
                    .map(f => {
                        this.hierarchyState = { ...this.hierarchyState, [f.id]: { levels: [], isLoading: true } };
                        const loaderFn = f.hierarchyMode === 'manager' ? getTopLevelManagers : getTopLevelUsers;
                        return loaderFn()
                            .then(users => { this.hierarchyState = { ...this.hierarchyState, [f.id]: { levels: [{ users, selectedUserId: '' }], isLoading: false } }; })
                            .catch(() => { this.hierarchyState = { ...this.hierarchyState, [f.id]: { levels: [], isLoading: false } }; });
                    });

                return Promise.all([...plPromises, ...hierPromises]);
            })
            .then(() => { this.isDashboardLoading = false; this.refreshData(); })
            .catch(error => { this.showToast('Error', 'Failed to load dashboard', 'error'); this.isDashboardLoading = false; console.error(error); });
    }

    refreshData() {
        if (!this.selectedDashboardId) return;
        this.isDashboardLoading = true;
        const filtersArray = Object.values(this.activeFilters);
        getDashboardData({ configId: this.selectedDashboardId, activeFiltersJson: JSON.stringify(filtersArray) })
            .then(results => {
                const dataMap = {};
                results.forEach(r => { dataMap[r.componentId] = r; });
                this.componentData = dataMap;
                this.isDashboardLoading = false;
            })
            .catch(error => { this.showToast('Error', 'Failed to load data', 'error'); this.isDashboardLoading = false; console.error(error); });
    }

    // ── Filters ──
    get renderedFilters() {
        const nonHierCount = this.filterConfigs.filter(f => f.type !== 'hierarchy').length;
        let colSize = nonHierCount <= 2 ? '4' : nonHierCount <= 4 ? '3' : '2';
        return this.filterConfigs.map(f => {
            const isDateRange = f.type === 'dateRange';
            const filterColClass = `slds-col slds-size_${isDateRange ? Math.min(parseInt(colSize,10)*2,6) : colSize}-of-12 slds-m-bottom_x-small`;
            return {
                ...f, isDateRange, isDateLiteral: f.type === 'dateLiteral', isPicklist: f.type === 'picklist',
                isText: f.type === 'text', isCurrentUser: f.type === 'currentUser',
                isUserHierarchy: f.type === 'userHierarchy', isHierarchy: f.type === 'hierarchy',
                picklistOptions: this.filterPicklistOptions[f.id] || [],
                currentValue: this.activeFilters[f.id]?.value || '',
                startDate: this.activeFilters[f.id]?.value?.start || '',
                endDate: this.activeFilters[f.id]?.value?.end || '',
                hierarchyLevels: this.getHierarchyLevels(f.id),
                hierarchyLoading: this.hierarchyState[f.id]?.isLoading || false,
                hierarchyModeLabel: f.type === 'hierarchy' ? (f.hierarchyMode === 'manager' ? 'Reporting Manager' : 'Role Hierarchy') : '',
                filterColClass
            };
        });
    }

    getHierarchyLevels(filterId) {
        const state = this.hierarchyState[filterId];
        if (!state || !state.levels) return [];
        const filterConfig = this.filterConfigs.find(f => f.id === filterId);
        const isManagerMode = filterConfig && filterConfig.hierarchyMode === 'manager';
        return state.levels.map((level, index) => ({
            ...level, key: `${filterId}-level-${index}`, levelIndex: index, filterId,
            levelLabel: index === 0 ? (isManagerMode ? 'Select Manager' : 'Select User') : (isManagerMode ? `Level ${index+1} - Direct Report` : `Level ${index+1} - Subordinate`),
            userOptions: (level.users || []).map(u => ({ label: `${u.name}${u.role ? ' ('+u.role+')' : ''}`, value: u.id })),
            selectedUserId: level.selectedUserId || ''
        }));
    }

    get dateLiteralOptions() {
        return [
            { label: 'All Time', value: '' }, { label: 'Today', value: 'TODAY' },
            { label: 'This Week', value: 'THIS_WEEK' }, { label: 'Last Week', value: 'LAST_WEEK' },
            { label: 'This Month', value: 'THIS_MONTH' }, { label: 'Last Month', value: 'LAST_MONTH' },
            { label: 'This Quarter', value: 'THIS_QUARTER' }, { label: 'Last Quarter', value: 'LAST_QUARTER' },
            { label: 'This Year', value: 'THIS_YEAR' }, { label: 'Last Year', value: 'LAST_YEAR' },
            { label: 'Last 30 Days', value: 'LAST_N_DAYS:30' }, { label: 'Last 90 Days', value: 'LAST_N_DAYS:90' }
        ];
    }

    handleFilterChange(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const filterConfig = this.filterConfigs.find(f => f.id === filterId);
        const value = event.detail ? event.detail.value : event.target.value;
        if (value) {
            this.activeFilters = { ...this.activeFilters, [filterId]: { filterId, field: filterConfig.field, type: filterConfig.type, value } };
        } else {
            const updated = { ...this.activeFilters }; delete updated[filterId]; this.activeFilters = updated;
        }
    }

    handleDateStartChange(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const filterConfig = this.filterConfigs.find(f => f.id === filterId);
        const existing = this.activeFilters[filterId]?.value || {};
        this.activeFilters = { ...this.activeFilters, [filterId]: { filterId, field: filterConfig.field, type: 'dateRange', value: { ...existing, start: event.target.value } } };
    }

    handleDateEndChange(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const filterConfig = this.filterConfigs.find(f => f.id === filterId);
        const existing = this.activeFilters[filterId]?.value || {};
        this.activeFilters = { ...this.activeFilters, [filterId]: { filterId, field: filterConfig.field, type: 'dateRange', value: { ...existing, end: event.target.value } } };
    }

    handleHierarchyChange(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const levelIndex = parseInt(event.currentTarget.dataset.levelIndex, 10);
        const selectedUserId = event.detail.value;
        const filterConfig = this.filterConfigs.find(f => f.id === filterId);
        const isManagerMode = filterConfig.hierarchyMode === 'manager';
        const state = JSON.parse(JSON.stringify(this.hierarchyState[filterId] || { levels: [] }));
        state.levels[levelIndex].selectedUserId = selectedUserId;
        state.levels = state.levels.slice(0, levelIndex + 1);
        state.isLoading = true;
        this.hierarchyState = { ...this.hierarchyState, [filterId]: state };
        this.activeFilters = { ...this.activeFilters, [filterId]: { filterId, field: filterConfig.field, type: 'hierarchy', hierarchyMode: filterConfig.hierarchyMode || 'role', value: selectedUserId } };
        const drillFn = isManagerMode ? getDirectReports : getSubordinateUsers;
        drillFn({ userId: selectedUserId })
            .then(result => {
                const cs = JSON.parse(JSON.stringify(this.hierarchyState[filterId]));
                cs.isLoading = false;
                if (result.hasSubordinates && result.subordinates?.length > 0) cs.levels.push({ users: result.subordinates, selectedUserId: '' });
                this.hierarchyState = { ...this.hierarchyState, [filterId]: cs };
            })
            .catch(error => {
                const cs = JSON.parse(JSON.stringify(this.hierarchyState[filterId]));
                cs.isLoading = false;
                this.hierarchyState = { ...this.hierarchyState, [filterId]: cs };
                console.error(error);
            });
    }

    handleClearHierarchy(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const state = this.hierarchyState[filterId];
        if (state?.levels?.length > 0) {
            this.hierarchyState = { ...this.hierarchyState, [filterId]: { levels: [{ users: state.levels[0].users, selectedUserId: '' }], isLoading: false } };
        }
        const updated = { ...this.activeFilters }; delete updated[filterId]; this.activeFilters = updated;
    }

    handleApplyFilters() { this.refreshData(); }
    handleClearFilters() {
        this.activeFilters = {};
        this.filterConfigs.forEach(f => {
            if (f.defaultValue) this.activeFilters[f.id] = { filterId: f.id, field: f.field, type: f.type, value: f.defaultValue };
            if (f.type === 'hierarchy' && this.hierarchyState[f.id]) {
                const state = this.hierarchyState[f.id];
                if (state.levels?.length > 0) this.hierarchyState = { ...this.hierarchyState, [f.id]: { levels: [{ users: state.levels[0].users, selectedUserId: '' }], isLoading: false } };
            }
        });
        this.refreshData();
    }

    // ── View Report ──
    handleViewReport(event) {
        const compId = event.currentTarget.dataset.compId;
        const comp = this.components.find(c => c.id === compId);
        if (!comp) return;
        this.reportComponentId = compId;
        this.reportModalTitle = comp.title || 'Report';
        this.reportColumns = []; this.reportRows = []; this.reportTotalRecords = 0;
        this.isReportLoading = true; this.showReportModal = true;
        const filtersArray = Object.values(this.activeFilters);
        getReportData({ componentJson: JSON.stringify(comp), activeFiltersJson: JSON.stringify(filtersArray) })
            .then(result => {
                this.reportColumns = result.columns || [];
                this.reportRows = (result.rows || []).map((row, idx) => ({
                    ...row, _key: `row-${idx}`,
                    _cells: (result.columns || []).map(col => ({ key: `${idx}-${col.fieldName}`, value: row[col.fieldName] || '' }))
                }));
                this.reportTotalRecords = result.totalRecords || 0;
                this.isReportLoading = false;
            })
            .catch(error => { this.showToast('Error', 'Failed to load report', 'error'); this.isReportLoading = false; console.error(error); });
    }

    closeReportModal() { this.showReportModal = false; }

    handleDownloadExcel() {
        if (!this.reportColumns.length || !this.reportRows.length) return;
        const headers = this.reportColumns.map(c => `"${(c.label||c.fieldName).replace(/"/g,'""')}"`);
        let csv = headers.join(',') + '\n';
        this.reportRows.forEach(row => {
            const cells = this.reportColumns.map(col => `"${String(row[col.fieldName]||'').replace(/"/g,'""')}"`);
            csv += cells.join(',') + '\n';
        });
        const encodedUri = 'data:text/csv;charset=utf-8,' + encodeURIComponent('\uFEFF' + csv);
        const fileName = `${this.reportModalTitle || 'Report'}_${new Date().toISOString().split('T')[0]}.csv`;
        const link = document.createElement('a');
        link.setAttribute('href', encodedUri); link.setAttribute('download', fileName);
        link.style.visibility = 'hidden'; link.style.position = 'absolute';
        this.template.querySelector('.report-modal-body').appendChild(link);
        link.click(); link.remove();
    }

    // ── Download Dashboard ──
    handleDownloadDashboard() {
        try {
            const comps = this.renderedComponents;
            if (!comps?.length) { this.showToast('Info', 'No components to download', 'info'); return; }
            const colWidth = 100, totalWidth = 1200, cardHeight = 180, cardGap = 12, padding = 16;
            let rows = [], currentRow = [], currentRowWidth = 0;
            comps.forEach(comp => {
                const size = parseInt(comp.size, 10) || 3;
                if (currentRowWidth + size > 12) { rows.push(currentRow); currentRow = []; currentRowWidth = 0; }
                currentRow.push({ ...comp, gridSize: size }); currentRowWidth += size;
            });
            if (currentRow.length > 0) rows.push(currentRow);
            const svgHeight = rows.length * (cardHeight + cardGap) + padding * 2;
            let svgContent = '';
            let yPos = padding;
            rows.forEach(row => {
                let xPos = padding;
                row.forEach(comp => {
                    const w = (comp.gridSize / 12) * (totalWidth - padding * 2) - cardGap;
                    const color = comp.color || '#0070d2';
                    svgContent += `<rect x="${xPos}" y="${yPos}" width="${w}" height="${cardHeight}" rx="10" fill="white" stroke="#e2e8f0" stroke-width="1"/>`;
                    svgContent += `<rect x="${xPos}" y="${yPos}" width="${w}" height="4" rx="2" fill="${color}"/>`;
                    svgContent += `<text x="${xPos + 12}" y="${yPos + 24}" font-size="12" font-weight="700" fill="#1e293b">${this._escXml(comp.title || '')}</text>`;
                    if (comp.isKpi) {
                        svgContent += `<text x="${xPos + w/2}" y="${yPos + cardHeight/2 + 12}" text-anchor="middle" font-size="30" font-weight="800" fill="${color}">${this._escXml(comp.formattedValue || '0')}</text>`;
                        svgContent += `<text x="${xPos + w/2}" y="${yPos + cardHeight/2 + 30}" text-anchor="middle" font-size="11" fill="#64748b">${this._escXml(comp.aggregation||'')} of ${this._escXml(comp.field||'')}</text>`;
                    } else if (comp.svgContent) {
                        const innerSvg = comp.svgContent.replace(/<svg[^>]*>/, '').replace(/<\/svg>/, '');
                        const vbMatch = comp.svgContent.match(/viewBox="([^"]+)"/);
                        const viewBox = vbMatch ? vbMatch[1] : '0 0 400 200';
                        svgContent += `<svg x="${xPos+8}" y="${yPos+35}" width="${w-16}" height="${cardHeight-45}" viewBox="${viewBox}" preserveAspectRatio="xMidYMid meet">${innerSvg}</svg>`;
                    }
                    xPos += w + cardGap;
                });
                yPos += cardHeight + cardGap;
            });
            const fullSvg = `<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" width="${totalWidth}" height="${svgHeight}" viewBox="0 0 ${totalWidth} ${svgHeight}" style="font-family:Arial,sans-serif;"><rect width="100%" height="100%" fill="#f5f7fa"/>${svgContent}</svg>`;
            const img = new Image();
            const scale = 2;
            img.onload = () => {
                const canvas = document.createElement('canvas');
                canvas.width = totalWidth * scale; canvas.height = svgHeight * scale;
                const ctx = canvas.getContext('2d'); ctx.scale(scale, scale);
                ctx.drawImage(img, 0, 0, totalWidth, svgHeight);
                const pngDataUri = canvas.toDataURL('image/png');
                const link = document.createElement('a');
                link.setAttribute('href', pngDataUri);
                link.setAttribute('download', `${this.dashboardTitle || 'Dashboard'}_${new Date().toISOString().split('T')[0]}.png`);
                link.style.visibility = 'hidden'; link.style.position = 'absolute';
                this.template.querySelector('.components-grid').appendChild(link);
                link.click(); link.remove();
                this.showToast('Success', 'Dashboard downloaded as PNG', 'success');
            };
            img.onerror = () => this.showToast('Error', 'Failed to render image', 'error');
            img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(fullSvg);
        } catch (e) { this.showToast('Error', 'Download failed: ' + e.message, 'error'); console.error(e); }
    }

    _escXml(str) {
        return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }

    // ── Color helpers ──
    _colorBg(hex) {
        const h = (hex || '').toLowerCase();
        return COLOR_BG_MAP[h] || 'rgba(0,112,210,0.12)';
    }

    _colorKey(hex) {
        if (!hex) return 'blue';
        const h = hex.toLowerCase();
        if (h.includes('2e844a') || h === '#45c65a') return 'green';
        if (h.includes('9050') || h.includes('7c4d') || h === '#7c4dff') return 'purple';
        if (h.includes('dd7a') || h.includes('e874') || h === '#e87400') return 'orange';
        if (h.includes('ea00') || h.includes('c239') || h === '#c23934') return 'red';
        return 'blue';
    }

    _achievementClass(pct) {
        if (pct == null) return '';
        if (pct >= 70) return 'achievement-high';
        if (pct >= 40) return 'achievement-mid';
        return 'achievement-low';
    }

    _barFillClass(pct) {
        if (pct == null) return 'bar-fill-blue';
        if (pct >= 70) return 'bar-fill-green';
        if (pct >= 40) return 'bar-fill-orange';
        return 'bar-fill-red';
    }

    _rankClass(idx) {
        if (idx === 0) return 'rank-badge rank-gold';
        if (idx === 1) return 'rank-badge rank-silver';
        if (idx === 2) return 'rank-badge rank-bronze';
        return 'rank-badge rank-default';
    }

    _statusBgClass(severity, colorKey) {
        if (severity) {
            const s = severity.toLowerCase();
            if (s.includes('high') || s.includes('critical') || s.includes('urgent')) return 'status-card-item status-bg-red';
            if (s.includes('medium') || s.includes('moderate') || s.includes('warning')) return 'status-card-item status-bg-orange';
            if (s.includes('low') || s.includes('normal') || s.includes('good')) return 'status-card-item status-bg-green';
        }
        return `status-card-item status-bg-${colorKey || 'blue'}`;
    }

    // ── renderedComponents ──
    get renderedComponents() {
        const MULTI_METRIC_TYPES = ['progressBar','rankedList','metricCards','rankedTable','achievementCard','targetProgress','statusCard'];
        return this.components.map(comp => {
          try {
            const data = this.componentData[comp.id] || {};
            const isKpi = comp.type === 'kpi';
            const isBar = comp.type === 'bar';
            const isPie = comp.type === 'pie';
            const isDonut = comp.type === 'donut';
            const isLine = comp.type === 'line';
            const isProgressBar = comp.type === 'progressBar';
            const isRankedList = comp.type === 'rankedList';
            const isMetricCards = comp.type === 'metricCards';
            const isRankedTable = comp.type === 'rankedTable';
            const isAchievementCard = comp.type === 'achievementCard';
            const isTargetProgress = comp.type === 'targetProgress';
            const isStatusCard = comp.type === 'statusCard';
            const isMultiMetric = MULTI_METRIC_TYPES.includes(comp.type);
            const isLegacyChart = ['bar','pie','donut','line'].includes(comp.type);
            const colorKey = this._colorKey(comp.color);

            // ── Emoji icon & color background ──
            const emojiIcon = comp.emojiIcon || '';
            const iconBgStyle = `background:${this._colorBg(comp.color)};`;
            // Bar thickness from config (default 38px for bar chart, 20px for progress bars)
            const bh = comp.barThickness || (isBar ? 38 : 20);
            const barThicknessStyle = `--dv-bar-h:${bh}px;`;

            let formattedValue = '';
            if (isKpi && data.value !== undefined) formattedValue = this.formatValue(data.value, comp.format);

            let chartData = [], svgContent = '';
            if (isLegacyChart && data.chartData) {
                chartData = data.chartData;
                if (isBar) svgContent = this.buildBarChartSvg(chartData, comp.color, comp.xAxisLabel, comp.yAxisLabel, comp.barThickness);
                else if (isPie || isDonut) svgContent = this.buildPieChartSvg(chartData, isDonut);
                else if (isLine) svgContent = this.buildLineChartSvg(chartData, comp.color, comp.xAxisLabel, comp.yAxisLabel);
            }

            const kpiIconClass = `kpi-icon-wrap kpi-icon-${colorKey}`;
            const kpiValueClass = `kpi-value kpi-color-${colorKey}`;
            const kpiBorderClass = `kpi-border-${colorKey}`;

            const typeBadgeMap = {
                kpi:'', bar:'Bar Chart', pie:'Pie Chart', donut:'Donut', line:'Line Chart',
                progressBar:'Progress Bars', rankedList:'Ranked', metricCards:'Cards',
                rankedTable:'Ranked List', achievementCard:'Achievement %',
                targetProgress:'Progress Bars', statusCard:'Map View'
            };
            const typeBadgeText = comp.badge || typeBadgeMap[comp.type] || '';

            // ── Multi-metric processing ──
            let processedItems = [];
            if (isMultiMetric && data.multiMetricData) {
                processedItems = data.multiMetricData.map((item, idx) => {
                    const rank = idx + 1;
                    const rankClass = this._rankClass(idx);
                    const achievementPct = item.achievement != null ? item.achievement
                        : (item.target && item.target > 0 ? ((item.primaryValue / item.target) * 100) : null);
                    const achievementClass = this._achievementClass(achievementPct);
                    const barFillClass = `progress-bar-fill ${this._barFillClass(achievementPct)}`;
                    const progressWidth = achievementPct != null ? Math.min(achievementPct, 100) : 0;
                    const gap = item.target != null ? item.target - item.primaryValue : 0;
                    const statusBgClass = this._statusBgClass(item.severity, colorKey);
                    const metricsDisplay = [];
                    if (item.metrics) {
                        (comp.metrics || []).forEach(mc => {
                            const val = item.metrics[mc.label];
                            metricsDisplay.push({ label: mc.label, value: this.formatValue(val, mc.format), key: `${item.groupLabel}-${mc.label}` });
                        });
                    }
                    const columnsDisplay = [];
                    if (item.columns) {
                        (comp.columns || []).forEach(cc => {
                            const val = item.columns[cc.label];
                            columnsDisplay.push({ label: cc.label, value: this.formatValue(val, cc.format), key: `${item.groupLabel}-${cc.label}` });
                        });
                    }
                    return {
                        ...item, key: `item-${comp.id}-${idx}`, rank, rankClass,
                        formattedPrimary: this.formatValue(item.primaryValue, comp.format || 'number'),
                        formattedSecondary: item.secondaryValue != null ? this.formatValue(item.secondaryValue, 'number') : '',
                        formattedTarget: item.target != null ? this.formatValue(item.target, comp.format || 'number') : '',
                        achievementPct: achievementPct != null ? achievementPct.toFixed(1) : '',
                        achievementClass,
                        achievementStyle: `color: ${achievementPct != null ? (achievementPct >= 70 ? '#2e844a' : achievementPct >= 40 ? '#e87400' : '#c23934') : '#999'}`,
                        barFillClass,
                        progressWidth: `width: ${progressWidth}%`,
                        gap: gap > 0 ? this.formatValue(gap, comp.format || 'number') : '',
                        hasGap: gap > 0, statusBgClass, metricsDisplay,
                        hasMetrics: metricsDisplay.length > 0, columnsDisplay,
                        badgeText: item.badge || '', hasBadge: !!item.badge,
                        hasSubtitle: !!item.subtitle, hasAchievement: achievementPct != null,
                        hasTarget: item.target != null && item.target > 0,
                        initials: (item.groupLabel || '?').charAt(0).toUpperCase()
                    };
                });
            }

            let columnHeaders = [];
            if (isRankedTable && processedItems.length > 0 && processedItems[0].columnsDisplay) {
                columnHeaders = processedItems[0].columnsDisplay.map(c => ({ label: c.label, key: `hdr-${c.key}` }));
            }

            const icons = comp.icons || [];
            const displayIcon = icons.length > 0 ? icons[0] : (comp.icon || 'standard:default');
            const extraIcons = icons.length > 1 ? icons.slice(1) : [];
            const sizeClass = `slds-col slds-size_${comp.size || 3}-of-12 slds-p-bottom_small`;

            return {
                ...comp, sizeClass,
                isKpi, isBar, isPie: isPie && !isDonut, isDonut, isLine,
                isProgressBar, isRankedList, isMetricCards, isRankedTable,
                isAchievementCard, isTargetProgress, isStatusCard,
                isChart: isLegacyChart, isMultiMetric,
                formattedValue, chartData, svgContent, processedItems,
                hasItems: processedItems.length > 0, columnHeaders,
                hasColumnHeaders: columnHeaders.length > 0,
                hasError: !!data.errorMessage, errorMessage: data.errorMessage,
                kpiIconClass, kpiValueClass, kpiBorderClass,
                badgeText: typeBadgeText, hasBadge: !!typeBadgeText,
                iconStyle: `color: ${comp.color || '#0070d2'};`, colorKey,
                displayIcon, extraIcons: extraIcons.map((ic,i) => ({ icon: ic, key: `extra-${i}` })),
                hasExtraIcons: extraIcons.length > 0,
                // ── NEW: emoji + color bg + bar thickness ──
                emojiIcon,
                iconBgStyle,
                barThicknessStyle,
            };
          } catch (err) {
            const sizeClass = `slds-col slds-size_${comp.size || 3}-of-12 slds-p-bottom_small`;
            return {
                ...comp, sizeClass,
                isKpi:false, isBar:false, isPie:false, isDonut:false, isLine:false,
                isProgressBar:false, isRankedList:false, isMetricCards:false, isRankedTable:false,
                isAchievementCard:false, isTargetProgress:false, isStatusCard:false,
                isChart:false, isMultiMetric:false,
                formattedValue:'', chartData:[], svgContent:'', processedItems:[],
                hasItems:false, columnHeaders:[], hasColumnHeaders:false,
                hasError:true, errorMessage:'Render error: ' + (err.message || err),
                kpiIconClass:'kpi-icon-wrap kpi-icon-default', kpiValueClass:'kpi-value',
                kpiBorderClass:'', iconStyle:'', badgeText:'', hasBadge:false,
                colorKey:'blue', displayIcon: comp.icon || 'standard:default',
                extraIcons:[], hasExtraIcons:false,
                emojiIcon: comp.emojiIcon || '',
                iconBgStyle: 'background:rgba(0,112,210,0.12);',
            };
          }
        });
    }

    // ── Value Formatter ──
    formatValue(value, format) {
        if (value === null || value === undefined) return '0';
        const num = Number(value);
        if (isNaN(num)) return '0';
        if (format === 'currency') {
            if (num >= 10000000) return '₹' + (num/10000000).toFixed(1) + 'Cr';
            if (num >= 100000)   return '₹' + (num/100000).toFixed(1) + 'L';
            if (num >= 1000)     return '₹' + (num/1000).toFixed(1) + 'K';
            return '₹' + this._formatIndian(num);
        }
        if (format === 'percent') return num.toFixed(1) + '%';
        if (num >= 10000000) return (num/10000000).toFixed(1) + 'Cr';
        if (num >= 100000)   return (num/100000).toFixed(1) + 'L';
        if (num >= 1000)     return (num/1000).toFixed(1) + 'K';
        return this._formatIndian(num);
    }

    _formatIndian(num) {
        const str = Math.round(num).toString();
        if (str.length <= 3) return str;
        let lastThree = str.substring(str.length - 3);
        let remaining = str.substring(0, str.length - 3);
        if (remaining.length > 0) lastThree = ',' + lastThree;
        return remaining.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + lastThree;
    }

    // ── SVG Chart Builders ──

    // BAR CHART — thick multi-color bars, barThickness configurable from component settings
    buildBarChartSvg(data, color, xAxisLabel, yAxisLabel, barThickness) {
        if (!data || data.length === 0) return '';
        const maxVal = Math.max(...data.map(d => d.value));
        if (maxVal === 0) return '';

        const BAR_H = Math.max(20, Math.min(60, barThickness || 38));
        const GAP = Math.round(BAR_H * 0.35);
        const LBL_W = 140, VAL_W = 65, PLOT_W = 400;
        const TOTAL_W = LBL_W + PLOT_W + VAL_W;
        const BOTTOM_PAD = xAxisLabel ? 32 : 10;
        const SVG_H = data.length * (BAR_H + GAP) + 14 + BOTTOM_PAD;
        const RX = Math.min(BAR_H / 2, 12);

        let defs = '';
        MULTI_BAR_COLORS.forEach(({ f, l }, gi) => {
            defs += `<linearGradient id="dvbg${gi}" x1="0" y1="0" x2="1" y2="0">`
                + `<stop offset="0%" stop-color="${f}"/>`
                + `<stop offset="100%" stop-color="${l}"/>`
                + `</linearGradient>`;
        });

        let bars = '';
        data.forEach((d, i) => {
            const y = i * (BAR_H + GAP) + 10;
            const bw = maxVal > 0 ? Math.max((d.value / maxVal) * PLOT_W, 8) : 8;
            const gi = i % MULTI_BAR_COLORS.length;
            const fc = MULTI_BAR_COLORS[gi].f;
            const lbl = (d.label || '(blank)').length > 18
                ? (d.label || '').slice(0, 18) + '…'
                : (d.label || '(blank)');

            bars += `<rect x="${LBL_W}" y="${y}" width="${PLOT_W}" height="${BAR_H}" rx="${RX}" fill="#eef2f8"/>`;
            bars += `<rect x="${LBL_W}" y="${y}" width="${bw}" height="${BAR_H}" rx="${RX}" fill="url(#dvbg${gi})"/>`;
            bars += `<text x="${LBL_W - 12}" y="${y + BAR_H/2 + 5}" text-anchor="end" font-size="13" font-weight="600" fill="#1e293b">${this._escXml(lbl)}</text>`;
            bars += `<text x="${LBL_W + bw + 12}" y="${y + BAR_H/2 + 5}" font-size="13" fill="${fc}" font-weight="700">${this.formatValue(d.value, 'number')}</text>`;
        });

        if (xAxisLabel) {
            bars += `<text x="${TOTAL_W/2}" y="${SVG_H - 6}" text-anchor="middle" font-size="11" fill="#64748b" font-weight="600">${this._escXml(xAxisLabel)}</text>`;
        }

        return `<svg viewBox="0 0 ${TOTAL_W} ${SVG_H}" xmlns="http://www.w3.org/2000/svg" style="width:100%;height:auto;"><defs>${defs}</defs>${bars}</svg>`;
    }

    buildPieChartSvg(data, isDonut) {
        if (!data || data.length === 0) return '';
        const total = data.reduce((s, d) => s + d.value, 0);
        if (total === 0) return '';
        const cx = 120, cy = 120, r = 100, innerR = isDonut ? 55 : 0;
        let startAngle = -Math.PI / 2;
        let paths = '', legends = '';
        data.forEach((d, i) => {
            const sliceAngle = (d.value / total) * 2 * Math.PI;
            const endAngle = startAngle + sliceAngle;
            const largeArc = sliceAngle > Math.PI ? 1 : 0;
            const col = CHART_COLORS[i % CHART_COLORS.length];
            const x1 = cx + r * Math.cos(startAngle), y1 = cy + r * Math.sin(startAngle);
            const x2 = cx + r * Math.cos(endAngle), y2 = cy + r * Math.sin(endAngle);
            if (innerR > 0) {
                const ix1 = cx + innerR * Math.cos(endAngle), iy1 = cy + innerR * Math.sin(endAngle);
                const ix2 = cx + innerR * Math.cos(startAngle), iy2 = cy + innerR * Math.sin(startAngle);
                paths += `<path d="M ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2} L ${ix1} ${iy1} A ${innerR} ${innerR} 0 ${largeArc} 0 ${ix2} ${iy2} Z" fill="${col}" opacity="0.9"/>`;
            } else {
                paths += `<path d="M ${cx} ${cy} L ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2} Z" fill="${col}" opacity="0.9"/>`;
            }
            const pct = ((d.value / total) * 100).toFixed(1);
            const truncLabel = d.label.length > 14 ? d.label.substring(0, 14) + '..' : d.label;
            const ly = 15 + i * 22;
            legends += `<rect x="260" y="${ly - 10}" width="12" height="12" rx="2" fill="${col}"/>`;
            legends += `<text x="278" y="${ly}" font-size="11" fill="#1e293b">${truncLabel}: ${this.formatValue(d.value,'number')} (${pct}%)</text>`;
            startAngle = endAngle;
        });
        if (isDonut) {
            paths += `<text x="${cx}" y="${cy - 5}" text-anchor="middle" font-size="22" font-weight="800" fill="#181818">${this.formatValue(total,'number')}</text>`;
            paths += `<text x="${cx}" y="${cy + 14}" text-anchor="middle" font-size="11" fill="#64748b">Total</text>`;
        }
        return `<svg viewBox="0 0 440 240" xmlns="http://www.w3.org/2000/svg" style="width:100%;height:auto;">${paths}${legends}</svg>`;
    }

    buildLineChartSvg(data, color, xAxisLabel, yAxisLabel) {
        if (!data || data.length === 0) return '';
        const maxVal = Math.max(...data.map(d => d.value));
        if (maxVal === 0) return '';
        const W = 400, H = 200, PL = yAxisLabel ? 60 : 50, PR = 20, PT = 20, PB = xAxisLabel ? 55 : 40;
        const plotW = W - PL - PR, plotH = H - PT - PB;
        let points = '', dots = '', labels = '';
        data.forEach((d, i) => {
            const x = PL + (i / (data.length - 1 || 1)) * plotW;
            const y = PT + plotH - (d.value / maxVal) * plotH;
            points += `${x},${y} `;
            dots += `<circle cx="${x}" cy="${y}" r="5" fill="${color||'#0070d2'}" stroke="white" stroke-width="2.5"/>`;
            dots += `<text x="${x}" y="${y - 9}" text-anchor="middle" font-size="9" fill="#1e293b" font-weight="700">${this.formatValue(d.value,'number')}</text>`;
            if (data.length <= 10) {
                const truncLabel = d.label.length > 8 ? d.label.substring(0, 8) + '..' : d.label;
                labels += `<text x="${x}" y="${PT + plotH + 18}" text-anchor="middle" font-size="10" fill="#64748b">${truncLabel}</text>`;
            }
        });
        let grid = '';
        for (let i = 0; i <= 4; i++) {
            const y = PT + (i / 4) * plotH;
            const val = maxVal - (i / 4) * maxVal;
            grid += `<line x1="${PL}" y1="${y}" x2="${W - PR}" y2="${y}" stroke="#e2e8f0" stroke-width="1"/>`;
            grid += `<text x="${PL - 8}" y="${y + 4}" text-anchor="end" font-size="10" fill="#64748b">${this.formatValue(val,'number')}</text>`;
        }
        const fillPoints = `${PL},${PT + plotH} ${points} ${PL + plotW},${PT + plotH}`;
        let axisLabels = '';
        if (xAxisLabel) axisLabels += `<text x="${PL + plotW/2}" y="${H - 2}" text-anchor="middle" font-size="11" fill="#64748b" font-weight="600">${xAxisLabel}</text>`;
        if (yAxisLabel) axisLabels += `<text x="12" y="${PT + plotH/2}" text-anchor="middle" font-size="11" fill="#64748b" font-weight="600" transform="rotate(-90, 12, ${PT + plotH/2})">${yAxisLabel}</text>`;
        return `<svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg" style="width:100%;height:auto;">${grid}<polygon points="${fillPoints}" fill="${color||'#0070d2'}" opacity="0.08"/><polyline points="${points}" fill="none" stroke="${color||'#0070d2'}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>${dots}${labels}${axisLabels}</svg>`;
    }

    // ── Rendered callback: inject SVG into chart containers ──
    renderedCallback() {
        const chartContainers = this.template.querySelectorAll('[data-chart-id]');
        chartContainers.forEach(container => {
            const compId = container.dataset.chartId;
            const comp = this.renderedComponents.find(c => c.id === compId);
            if (comp && comp.svgContent && container.innerHTML !== comp.svgContent) {
                container.innerHTML = comp.svgContent;
            }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}