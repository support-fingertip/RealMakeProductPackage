import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAllDashboardConfigs from '@salesforce/apex/DashboardConfigController.getAllDashboardConfigs';
import getDashboardConfig from '@salesforce/apex/DashboardConfigController.getDashboardConfig';
import saveDashboardConfig from '@salesforce/apex/DashboardConfigController.saveDashboardConfig';
import deleteDashboardConfig from '@salesforce/apex/DashboardConfigController.deleteDashboardConfig';
import cloneDashboardConfig from '@salesforce/apex/DashboardConfigController.cloneDashboardConfig';
import getAllObjects from '@salesforce/apex/DashboardConfigController.getAllObjects';
import getObjectFields from '@salesforce/apex/DashboardConfigController.getObjectFields';
import getAllProfiles from '@salesforce/apex/DashboardConfigController.getAllProfiles';
import getAllRoles from '@salesforce/apex/DashboardConfigController.getAllRoles';
import searchUsers from '@salesforce/apex/DashboardConfigController.searchUsers';

// Full icon library with categories
const ALL_ICONS = [
    // Sales & Revenue
    { emoji: '💰', label: 'money', cat: 'sales' },
    { emoji: '💵', label: 'cash', cat: 'sales' },
    { emoji: '💳', label: 'card', cat: 'sales' },
    { emoji: '🏦', label: 'bank', cat: 'sales' },
    { emoji: '🧾', label: 'invoice', cat: 'sales' },
    { emoji: '📈', label: 'trending up', cat: 'sales' },
    { emoji: '📉', label: 'trending down', cat: 'sales' },
    { emoji: '🎯', label: 'target', cat: 'sales' },
    { emoji: '🏆', label: 'trophy', cat: 'sales' },
    { emoji: '🥇', label: 'gold medal', cat: 'sales' },
    { emoji: '🥈', label: 'silver medal', cat: 'sales' },
    { emoji: '🥉', label: 'bronze medal', cat: 'sales' },
    { emoji: '🎖️', label: 'medal', cat: 'sales' },
    { emoji: '💎', label: 'diamond', cat: 'sales' },
    { emoji: '🏅', label: 'sports medal', cat: 'sales' },
    // Analytics & Charts
    { emoji: '📊', label: 'bar chart', cat: 'analytics' },
    { emoji: '📋', label: 'clipboard report', cat: 'analytics' },
    { emoji: '📌', label: 'pin task', cat: 'analytics' },
    { emoji: '📎', label: 'paperclip', cat: 'analytics' },
    { emoji: '🔢', label: 'numbers', cat: 'analytics' },
    { emoji: '🧮', label: 'calculator', cat: 'analytics' },
    { emoji: '📐', label: 'measure', cat: 'analytics' },
    { emoji: '🔍', label: 'search', cat: 'analytics' },
    { emoji: '🔎', label: 'zoom', cat: 'analytics' },
    { emoji: '🗂️', label: 'files', cat: 'analytics' },
    { emoji: '📁', label: 'folder', cat: 'analytics' },
    { emoji: '📂', label: 'open folder', cat: 'analytics' },
    { emoji: '🗃️', label: 'card file', cat: 'analytics' },
    { emoji: '📑', label: 'pages', cat: 'analytics' },
    { emoji: '📝', label: 'memo', cat: 'analytics' },
    // People & Teams
    { emoji: '👥', label: 'team', cat: 'people' },
    { emoji: '👤', label: 'person', cat: 'people' },
    { emoji: '🧑‍💼', label: 'employee', cat: 'people' },
    { emoji: '👔', label: 'executive', cat: 'people' },
    { emoji: '🤝', label: 'handshake deal', cat: 'people' },
    { emoji: '🙌', label: 'hands raised', cat: 'people' },
    { emoji: '👏', label: 'clap achievement', cat: 'people' },
    { emoji: '🧑‍🤝‍🧑', label: 'partners', cat: 'people' },
    { emoji: '👨‍💻', label: 'developer', cat: 'people' },
    { emoji: '👩‍💼', label: 'manager', cat: 'people' },
    // Products & Inventory
    { emoji: '📦', label: 'package box', cat: 'products' },
    { emoji: '🛒', label: 'shopping cart', cat: 'products' },
    { emoji: '🏪', label: 'store shop', cat: 'products' },
    { emoji: '🏬', label: 'department store', cat: 'products' },
    { emoji: '🏭', label: 'factory', cat: 'products' },
    { emoji: '🚚', label: 'delivery truck', cat: 'products' },
    { emoji: '🛍️', label: 'shopping bag', cat: 'products' },
    { emoji: '🏷️', label: 'price tag', cat: 'products' },
    { emoji: '⚙️', label: 'settings gear', cat: 'products' },
    { emoji: '🔧', label: 'wrench tool', cat: 'products' },
    { emoji: '🔩', label: 'bolt screw', cat: 'products' },
    { emoji: '🏗️', label: 'construction', cat: 'products' },
    // Status & Alerts
    { emoji: '⭐', label: 'star rating', cat: 'status' },
    { emoji: '🌟', label: 'glowing star', cat: 'status' },
    { emoji: '✅', label: 'check done', cat: 'status' },
    { emoji: '❌', label: 'cross error', cat: 'status' },
    { emoji: '⚠️', label: 'warning alert', cat: 'status' },
    { emoji: '🔔', label: 'bell notification', cat: 'status' },
    { emoji: '🔕', label: 'bell off', cat: 'status' },
    { emoji: '🚨', label: 'alarm siren', cat: 'status' },
    { emoji: '🟢', label: 'green circle ok', cat: 'status' },
    { emoji: '🟡', label: 'yellow warning', cat: 'status' },
    { emoji: '🔴', label: 'red circle issue', cat: 'status' },
    { emoji: '🔵', label: 'blue circle info', cat: 'status' },
    { emoji: '🏁', label: 'finish flag', cat: 'status' },
    { emoji: '🚩', label: 'flag priority', cat: 'status' },
    { emoji: '📍', label: 'location pin', cat: 'status' },
    // Energy & Growth
    { emoji: '🚀', label: 'rocket launch', cat: 'energy' },
    { emoji: '⚡', label: 'lightning bolt', cat: 'energy' },
    { emoji: '🔥', label: 'fire hot', cat: 'energy' },
    { emoji: '💡', label: 'lightbulb idea', cat: 'energy' },
    { emoji: '🌱', label: 'growth seedling', cat: 'energy' },
    { emoji: '🌿', label: 'leaves organic', cat: 'energy' },
    { emoji: '🌍', label: 'world globe', cat: 'energy' },
    { emoji: '☀️', label: 'sun bright', cat: 'energy' },
    { emoji: '⭐', label: 'star shine', cat: 'energy' },
    { emoji: '👑', label: 'crown king', cat: 'energy' },
    { emoji: '💫', label: 'sparkle dizzy', cat: 'energy' },
    { emoji: '✨', label: 'sparkles magic', cat: 'energy' },
    { emoji: '🎉', label: 'party celebrate', cat: 'energy' },
    { emoji: '🎊', label: 'confetti', cat: 'energy' },
    { emoji: '🎁', label: 'gift reward', cat: 'energy' },
];

const COLOR_BG_MAP = {
    '#0070d2': 'rgba(0,112,210,0.1)',
    '#2e844a': 'rgba(46,132,74,0.1)',
    '#dd7a01': 'rgba(221,122,1,0.1)',
    '#ea001e': 'rgba(234,0,30,0.1)',
    '#9050e9': 'rgba(144,80,233,0.1)',
    '#0b827c': 'rgba(11,130,124,0.1)',
    '#16325c': 'rgba(22,50,92,0.1)',
    '#e3066a': 'rgba(227,6,106,0.1)',
    '#07aee3': 'rgba(7,174,227,0.1)',
    '#45c65a': 'rgba(69,198,90,0.1)',
};

export default class DashboardConfigurator extends LightningElement {
    @track currentView = 'list';
    @track currentStep = 1;
    @track configurations = [];
    @track editingConfigId = null;
    @track isLoading = false;

    // Basic info
    @track dashboardName = '';
    @track description = '';
    @track isActive = true;
    @track showHeaderSection = false;
    @track headerConfig = { title: '', subtitle: '', showDate: true, gradientStart: '#1b2a4a', gradientEnd: '#0176d3', textColor: '#ffffff' };

    // Components
    @track components = [];
    @track selectedCompId = null;

    // Icon picker state
    @track iconSearchQuery = '';
    @track selectedIconCat = 'all';
    @track showAdvancedSection = false;

    // Filters
    @track filters = [];
    @track showFilterModal = false;
    @track currentFilter = {};
    @track currentFilterFields = [];

    // Visibility rules
    @track visibilityRules = [];
    @track showRuleModal = false;
    @track currentRule = {};
    @track profileOptions = [];
    @track roleOptions = [];
    @track userOptions = [];

    // Field data
    @track objectOptions = [];
    @track fieldOptionsCache = {};
    @track selectedCompFields = [];

    // ── Static option arrays ──

    componentTypeOptions = [
        { label: 'KPI Card', value: 'kpi', emoji: '📊' },
        { label: 'Bar Chart', value: 'bar', emoji: '📉' },
        { label: 'Pie Chart', value: 'pie', emoji: '🥧' },
        { label: 'Donut', value: 'donut', emoji: '🍩' },
        { label: 'Line Chart', value: 'line', emoji: '📈' },
        { label: 'Progress Bars', value: 'progressBar', emoji: '🟩' },
        { label: 'Ranked List', value: 'rankedList', emoji: '🏆' },
        { label: 'Metric Cards', value: 'metricCards', emoji: '🗂️' },
        { label: 'Ranked Table', value: 'rankedTable', emoji: '📋' },
        { label: 'Achievement %', value: 'achievementCard', emoji: '🎯' },
        { label: 'Target Progress', value: 'targetProgress', emoji: '🚀' },
        { label: 'Status Cards', value: 'statusCard', emoji: '🗺️' },
    ];

    filterTypeOptions = [
        { label: 'Date Range', value: 'dateRange', emoji: '📅' },
        { label: 'Date Literal', value: 'dateLiteral', emoji: '🗓️' },
        { label: 'Picklist', value: 'picklist', emoji: '🔽' },
        { label: 'Text', value: 'text', emoji: '🔤' },
        { label: 'Current User', value: 'currentUser', emoji: '👤' },
        { label: 'User Hierarchy', value: 'userHierarchy', emoji: '👥' },
        { label: 'Cascading Hierarchy', value: 'hierarchy', emoji: '🌲' },
    ];

    aggregationOptions = [
        { label: 'COUNT', value: 'COUNT' },
        { label: 'SUM', value: 'SUM' },
        { label: 'AVG', value: 'AVG' },
        { label: 'MIN', value: 'MIN' },
        { label: 'MAX', value: 'MAX' }
    ];

    sizeOptions = [
        { label: '1/4 Width', value: '3', shortLabel: '¼' },
        { label: '1/3 Width', value: '4', shortLabel: '⅓' },
        { label: '1/2 Width', value: '6', shortLabel: '½' },
        { label: '2/3 Width', value: '8', shortLabel: '⅔' },
        { label: 'Full Width', value: '12', shortLabel: '↔' }
    ];

    formatOptions = [
        { label: 'Number', value: 'number' },
        { label: 'Currency (₹)', value: 'currency' },
        { label: 'Percent (%)', value: 'percent' }
    ];

    colorOptions = [
        { label: 'Blue', value: '#0070d2' },
        { label: 'Green', value: '#2e844a' },
        { label: 'Orange', value: '#dd7a01' },
        { label: 'Red', value: '#ea001e' },
        { label: 'Purple', value: '#9050e9' },
        { label: 'Teal', value: '#0b827c' },
        { label: 'Navy', value: '#16325c' },
        { label: 'Pink', value: '#e3066a' },
        { label: 'Sky', value: '#07aee3' },
        { label: 'Lime', value: '#45c65a' },
    ];

    staticFilterOperatorOptions = [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Contains', value: 'contains' },
        { label: 'Greater Than', value: 'greaterThan' },
        { label: 'Less Than', value: 'lessThan' }
    ];

    maxGroupsOptions = [
        { label: 'Top 5', value: '5' },
        { label: 'Top 10', value: '10' },
        { label: 'Top 15', value: '15' },
        { label: 'Top 20 (default)', value: '' },
        { label: 'Top 25', value: '25' },
        { label: 'Top 50', value: '50' }
    ];

    dateLiteralOptions = [
        { label: 'Today', value: 'TODAY' },
        { label: 'Yesterday', value: 'YESTERDAY' },
        { label: 'This Week', value: 'THIS_WEEK' },
        { label: 'Last Week', value: 'LAST_WEEK' },
        { label: 'This Month', value: 'THIS_MONTH' },
        { label: 'Last Month', value: 'LAST_MONTH' },
        { label: 'This Quarter', value: 'THIS_QUARTER' },
        { label: 'Last Quarter', value: 'LAST_QUARTER' },
        { label: 'This Year', value: 'THIS_YEAR' },
        { label: 'Last Year', value: 'LAST_YEAR' },
        { label: 'Last 30 Days', value: 'LAST_N_DAYS:30' },
        { label: 'Last 60 Days', value: 'LAST_N_DAYS:60' },
        { label: 'Last 90 Days', value: 'LAST_N_DAYS:90' }
    ];

    hierarchyModeOptions = [
        { label: 'Role Hierarchy', value: 'role' },
        { label: 'Reporting Manager (ManagerId)', value: 'manager' }
    ];

    ruleTypes = [
        { label: 'Profile', value: 'Profile' },
        { label: 'Role', value: 'Role' },
        { label: 'User', value: 'User' }
    ];

    ruleOperatorOptions = [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Contains', value: 'contains' }
    ];

    // ── Icon categories ──
    get iconCategories() {
        return [
            { key: 'all', label: 'All', catBtnClass: `dc-icon-cat-btn${this.selectedIconCat === 'all' ? ' dc-icon-cat-active' : ''}` },
            { key: 'sales', label: '💰 Sales', catBtnClass: `dc-icon-cat-btn${this.selectedIconCat === 'sales' ? ' dc-icon-cat-active' : ''}` },
            { key: 'analytics', label: '📊 Analytics', catBtnClass: `dc-icon-cat-btn${this.selectedIconCat === 'analytics' ? ' dc-icon-cat-active' : ''}` },
            { key: 'people', label: '👥 People', catBtnClass: `dc-icon-cat-btn${this.selectedIconCat === 'people' ? ' dc-icon-cat-active' : ''}` },
            { key: 'products', label: '📦 Products', catBtnClass: `dc-icon-cat-btn${this.selectedIconCat === 'products' ? ' dc-icon-cat-active' : ''}` },
            { key: 'status', label: '⭐ Status', catBtnClass: `dc-icon-cat-btn${this.selectedIconCat === 'status' ? ' dc-icon-cat-active' : ''}` },
            { key: 'energy', label: '🚀 Energy', catBtnClass: `dc-icon-cat-btn${this.selectedIconCat === 'energy' ? ' dc-icon-cat-active' : ''}` },
        ];
    }

    get filteredIconOptions() {
        const sel = this._getSelectedComp();
        const q = (this.iconSearchQuery || '').toLowerCase();
        let icons = ALL_ICONS;
        if (this.selectedIconCat !== 'all') icons = icons.filter(i => i.cat === this.selectedIconCat);
        if (q) icons = icons.filter(i => i.label.toLowerCase().includes(q));
        // Deduplicate by emoji
        const seen = new Set();
        icons = icons.filter(i => { if (seen.has(i.emoji)) return false; seen.add(i.emoji); return true; });
        return icons.map((ico, idx) => ({
            ...ico,
            key: `${ico.emoji}-${idx}`,
            btnClass: `dc-icon-btn${sel && sel.emojiIcon === ico.emoji ? ' dc-icon-btn-sel' : ''}`
        }));
    }

    // ── Lifecycle ──
    connectedCallback() {
        this.loadConfigurations();
        this.loadObjects();
        this.loadProfiles();
        this.loadRoles();
    }

    @api refresh() { this.loadConfigurations(); }

    loadConfigurations() {
        this.isLoading = true;
        getAllDashboardConfigs()
            .then(r => { this.configurations = r; this.isLoading = false; })
            .catch(e => { this.showToast('Error', 'Failed to load', 'error'); this.isLoading = false; console.error(e); });
    }

    loadObjects() {
        getAllObjects()
            .then(r => { this.objectOptions = r.map(o => ({ label: `${o.label} (${o.value})`, value: o.value })).sort((a, b) => a.label.localeCompare(b.label)); })
            .catch(console.error);
    }

    loadProfiles() { getAllProfiles().then(r => { this.profileOptions = r.map(p => ({ label: p.label, value: p.value })); }).catch(console.error); }
    loadRoles() { getAllRoles().then(r => { this.roleOptions = r.map(r2 => ({ label: r2.label, value: r2.value })); }).catch(console.error); }

    loadFieldsForObject(objectApiName) {
        if (this.fieldOptionsCache[objectApiName]) return Promise.resolve(this.fieldOptionsCache[objectApiName]);
        return getObjectFields({ objectApiName }).then(r => {
            const fields = r.map(f => ({ label: `${f.label} (${f.value})`, value: f.value, type: f.type }));
            this.fieldOptionsCache[objectApiName] = fields;
            return fields;
        });
    }

    // ── View & Step ──
    get isListView() { return this.currentView === 'list'; }
    get isBuilderView() { return this.currentView === 'builder'; }
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get hasConfigurations() { return this.configurations.length > 0; }
    get hasComponents() { return this.components.length > 0; }
    get hasFilters() { return this.filters.length > 0; }
    get hasVisibilityRules() { return this.visibilityRules.length > 0; }
    get configurationsCount() { return this.configurations.length; }
    get builderTitle() { return this.editingConfigId ? 'Edit Dashboard' : 'New Dashboard'; }
    get activeStatusLabel() { return this.isActive ? '✅ Active' : '⬜ Inactive'; }
    get activeStatusClass() { return `dc-active-status${this.isActive ? ' dc-active-on' : ' dc-active-off'}`; }
    get headerChevron() { return this.showHeaderSection ? '▲' : '▼'; }
    get advancedChevron() { return this.showAdvancedSection ? '▲' : '▼'; }
    get dashboardNameOrDefault() { return this.dashboardName || 'My Dashboard'; }

    _tabClass(n) {
        if (this.currentStep === n) return 'dc-stab dc-stab-active';
        if (this.currentStep > n) return 'dc-stab dc-stab-done';
        return 'dc-stab';
    }

    get step1TabClass() { return this._tabClass(1); }
    get step2TabClass() { return this._tabClass(2); }
    get step3TabClass() { return this._tabClass(3); }
    get step4TabClass() { return this._tabClass(4); }

    goToStep1() { this.currentStep = 1; }
    goToStep2() { this.currentStep = 2; }
    goToStep3() { this.currentStep = 3; }
    goToStep4() { this.currentStep = 4; }

    // ── List Actions ──
    handleNewConfig() { this.resetForm(); this.currentStep = 1; this.currentView = 'builder'; }

    handleBackToList() { this.resetForm(); this.currentView = 'list'; this.loadConfigurations(); }

    handleEditConfig(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        getDashboardConfig({ configId }).then(config => {
            this.editingConfigId = config.Id;
            this.dashboardName = config.Name;
            this.description = config.Description__c || '';
            this.isActive = config.Active__c;
            if (config.Configuration_JSON__c) {
                const json = JSON.parse(config.Configuration_JSON__c);
                this.components = (json.components || []).map((c, i) => ({ ...c, id: c.id || `comp-${i}`, staticFilters: c.staticFilters || [], emojiIcon: c.emojiIcon || '📊' }));
                this.filters = (json.filters || []).map((f, i) => ({ ...f, id: f.id || `filter-${i}` }));
                this.visibilityRules = (json.visibilityRules || []).map((r, i) => ({ ...r, key: `rule-${i}` }));
                if (json.header) { this.headerConfig = { ...this.headerConfig, ...json.header }; this.showHeaderSection = !!(json.header.title); }
            }
            this.currentStep = 1;
            this.currentView = 'builder';
            this.isLoading = false;
        }).catch(e => { this.showToast('Error', 'Failed to load', 'error'); this.isLoading = false; });
    }

    handleDeleteConfig(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        deleteDashboardConfig({ configId }).then(() => { this.showToast('Success', 'Deleted', 'success'); this.loadConfigurations(); }).catch(e => { this.showToast('Error', 'Failed', 'error'); this.isLoading = false; });
    }

    handleCloneConfig(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        cloneDashboardConfig({ configId }).then(() => { this.showToast('Success', 'Cloned', 'success'); this.loadConfigurations(); }).catch(e => { this.showToast('Error', 'Failed', 'error'); this.isLoading = false; });
    }

    // ── Basic Info ──
    handleNameChange(e) { this.dashboardName = e.target.value; }
    handleDescriptionChange(e) { this.description = e.target.value; }
    handleActiveChange(e) { this.isActive = e.target.checked; }
    toggleHeaderSection() { this.showHeaderSection = !this.showHeaderSection; }
    handleHeaderTitleChange(e) { this.headerConfig = { ...this.headerConfig, title: e.target.value }; }
    handleHeaderSubtitleChange(e) { this.headerConfig = { ...this.headerConfig, subtitle: e.target.value }; }
    handleHeaderGradientStartChange(e) { this.headerConfig = { ...this.headerConfig, gradientStart: e.target.value }; }
    handleHeaderGradientEndChange(e) { this.headerConfig = { ...this.headerConfig, gradientEnd: e.target.value }; }
    handleHeaderTextColorChange(e) { this.headerConfig = { ...this.headerConfig, textColor: e.target.value }; }
    handleHeaderShowDateChange(e) { this.headerConfig = { ...this.headerConfig, showDate: e.target.checked }; }

    get hasHeaderConfig() { return !!(this.headerConfig && (this.headerConfig.title || this.headerConfig.subtitle)); }
    get previewHeaderStyle() {
        const gs = this.headerConfig.gradientStart || '#1b2a4a';
        const ge = this.headerConfig.gradientEnd || '#0176d3';
        const tc = this.headerConfig.textColor || '#ffffff';
        return `background:linear-gradient(135deg,${gs} 0%,${ge} 100%);color:${tc};`;
    }

    // ── Component Selection ──
    _getSelectedComp() { return this.components.find(c => c.id === this.selectedCompId); }

    handleSelectComp(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedCompId = this.selectedCompId === id ? null : id;
        this.iconSearchQuery = '';
        this.selectedIconCat = 'all';
        this.showAdvancedSection = false;
        const comp = this.components.find(c => c.id === id);
        if (comp && comp.object) {
            this.loadFieldsForObject(comp.object).then(fields => { this.selectedCompFields = fields; });
        } else {
            this.selectedCompFields = [];
        }
    }

    handleSelectCompFromPreview(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedCompId = id;
        this.iconSearchQuery = '';
        this.selectedIconCat = 'all';
        this.goToStep2();
        const comp = this.components.find(c => c.id === id);
        if (comp && comp.object) {
            this.loadFieldsForObject(comp.object).then(fields => { this.selectedCompFields = fields; });
        }
    }

    stopProp(event) { event.stopPropagation(); }

    // ── Quick Add ──
    handleQuickAddComponent(event) {
        const type = event.currentTarget.dataset.type;
        this._addNewComp(type);
    }

    handleAddComponent() { this._addNewComp('kpi'); }

    _addNewComp(type) {
        const typeOpt = this.componentTypeOptions.find(t => t.value === type);
        const id = `comp-${Date.now()}-${Math.random().toString(36).substr(2, 5)}`;
        const newComp = {
            id, type, title: typeOpt ? typeOpt.label : 'New Component',
            badge: '', object: '', aggregation: 'COUNT', field: 'Id',
            groupByField: '', size: type === 'kpi' ? '3' : '6',
            color: '#0070d2', format: 'number', emojiIcon: typeOpt ? typeOpt.emoji : '📊',
            maxGroups: '', staticFilters: [], metrics: [], columns: [], order: this.components.length + 1
        };
        this.components = [...this.components, newComp];
        this.selectedCompId = id;
        this.selectedCompFields = [];
        this.iconSearchQuery = '';
        this.selectedIconCat = 'all';
        this.showAdvancedSection = false;
    }

    handleRemoveComponent(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this.components = this.components.filter(c => c.id !== id).map((c, i) => ({ ...c, order: i + 1 }));
        if (this.selectedCompId === id) this.selectedCompId = null;
    }

    handleMoveComponentUp(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const idx = this.components.findIndex(c => c.id === id);
        if (idx > 0) {
            const arr = [...this.components];
            [arr[idx], arr[idx - 1]] = [arr[idx - 1], arr[idx]];
            this.components = arr.map((c, i) => ({ ...c, order: i + 1 }));
        }
    }

    handleMoveComponentDown(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const idx = this.components.findIndex(c => c.id === id);
        if (idx < this.components.length - 1) {
            const arr = [...this.components];
            [arr[idx], arr[idx + 1]] = [arr[idx + 1], arr[idx]];
            this.components = arr.map((c, i) => ({ ...c, order: i + 1 }));
        }
    }

    // ── Inline Edit Handlers ──
    _updateSelected(patch) {
        this.components = this.components.map(c => c.id === this.selectedCompId ? { ...c, ...patch } : c);
    }

    handleInlineTypeChange(event) { this._updateSelected({ type: event.currentTarget.dataset.type }); }
    handleInlineFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this._updateSelected({ [field]: event.target.value });
    }
    handleInlineObjectChange(event) {
        const obj = event.detail.value;
        this._updateSelected({ object: obj, field: 'Id', groupByField: '' });
        this.loadFieldsForObject(obj).then(fields => { this.selectedCompFields = fields; });
    }
    handleInlineAggChange(event) { this._updateSelected({ aggregation: event.detail.value }); }
    handleInlineFieldSelectChange(event) { this._updateSelected({ field: event.detail.value }); }
    handleInlineGroupByChange(event) { this._updateSelected({ groupByField: event.detail.value }); }
    handleInlineMaxGroupsChange(event) { this._updateSelected({ maxGroups: event.detail.value }); }
    handleInlineSizeChange(event) { this._updateSelected({ size: event.currentTarget.dataset.size }); }
    handleInlineFormatChange(event) { this._updateSelected({ format: event.detail.value }); }
    handleInlineColorChange(event) { this._updateSelected({ color: event.currentTarget.dataset.color }); }

    // ── Icon Picker ──
    handleIconSearch(event) { this.iconSearchQuery = event.target.value; }
    handleIconCatFilter(event) {
        event.stopPropagation();
        this.selectedIconCat = event.currentTarget.dataset.cat;
    }
    handleIconSelect(event) {
        event.stopPropagation();
        const emoji = event.currentTarget.dataset.emoji;
        this._updateSelected({ emojiIcon: emoji });
    }

    toggleAdvanced() { this.showAdvancedSection = !this.showAdvancedSection; }

    // ── Static Filters on Component ──
    handleAddStaticFilter() {
        const comp = this._getSelectedComp();
        if (!comp) return;
        const filters = [...(comp.staticFilters || [])];
        filters.push({ field: '', operator: 'equals', value: '', key: `sf-${Date.now()}` });
        this._updateSelected({ staticFilters: filters });
    }
    handleStaticFilterFieldChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const comp = this._getSelectedComp();
        const filters = [...(comp.staticFilters || [])];
        filters[idx] = { ...filters[idx], field: event.detail.value };
        this._updateSelected({ staticFilters: filters });
    }
    handleStaticFilterOperatorChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const comp = this._getSelectedComp();
        const filters = [...(comp.staticFilters || [])];
        filters[idx] = { ...filters[idx], operator: event.detail.value };
        this._updateSelected({ staticFilters: filters });
    }
    handleStaticFilterValueChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const comp = this._getSelectedComp();
        const filters = [...(comp.staticFilters || [])];
        filters[idx] = { ...filters[idx], value: event.target.value };
        this._updateSelected({ staticFilters: filters });
    }
    handleRemoveStaticFilter(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const comp = this._getSelectedComp();
        const filters = [...(comp.staticFilters || [])];
        filters.splice(idx, 1);
        this._updateSelected({ staticFilters: filters });
    }
    get staticFiltersList() {
        const comp = this._getSelectedComp();
        return ((comp && comp.staticFilters) || []).map((f, i) => ({ ...f, index: i, key: f.key || `sf-${i}` }));
    }

    // ── Computed for selected comp shortcuts ──
    get selectedCompTitle() { const c = this._getSelectedComp(); return c ? c.title : ''; }
    get selectedCompBadge() { const c = this._getSelectedComp(); return c ? (c.badge || '') : ''; }
    get selectedCompObject() { const c = this._getSelectedComp(); return c ? c.object : ''; }
    get selectedCompAgg() { const c = this._getSelectedComp(); return c ? c.aggregation : 'COUNT'; }
    get selectedCompField() { const c = this._getSelectedComp(); return c ? c.field : ''; }
    get selectedCompGroupBy() { const c = this._getSelectedComp(); return c ? c.groupByField : ''; }
    get selectedCompMaxGroups() { const c = this._getSelectedComp(); return c ? c.maxGroups : ''; }
    get selectedCompFormat() { const c = this._getSelectedComp(); return c ? c.format : 'number'; }
    get selectedCompEmoji() { const c = this._getSelectedComp(); return c ? (c.emojiIcon || '📊') : '📊'; }

    // ── Bar Thickness ──
    get selectedCompHasBars() {
        const c = this._getSelectedComp();
        return c && ['bar','progressBar','targetProgress','rankedList','rankedTable','achievementCard'].includes(c.type);
    }
    get selectedCompBarThickness() {
        const c = this._getSelectedComp();
        return c ? (c.barThickness || 38) : 38;
    }
    get selectedCompBarThicknessLabel() {
        const t = this.selectedCompBarThickness;
        if (t <= 20) return 'Thin (' + t + 'px)';
        if (t <= 32) return 'Medium (' + t + 'px)';
        if (t <= 44) return 'Thick (' + t + 'px)';
        return 'Extra Thick (' + t + 'px)';
    }
    handleInlineBarThicknessChange(event) {
        this._updateSelected({ barThickness: parseInt(event.target.value, 10) });
    }
    get selectedCompNeedsGroupBy() { const c = this._getSelectedComp(); return c && c.type !== 'kpi'; }
    get selectedCompFieldOptions() { return this.selectedCompFields; }
    get selectedCompAllFields() { return this.selectedCompFields; }

    // ── ComponentsList for display ──
    get componentsList() {
        const sel = this.selectedCompId;
        return this.components.map(c => {
            const typeOpt = this.componentTypeOptions.find(t => t.value === c.type) || {};
            const sizeOpt = this.sizeOptions.find(s => s.value === c.size) || {};
            const bg = COLOR_BG_MAP[c.color] || 'rgba(0,112,210,0.1)';
            return {
                ...c,
                typeLabel: typeOpt.label || c.type,
                sizeLabel: sizeOpt.label || c.size,
                emojiIcon: c.emojiIcon || typeOpt.emoji || '📊',
                isSelected: c.id === sel,
                rowClass: `dc-comp-row${c.id === sel ? ' dc-comp-row-active' : ''}`,
                iconBgStyle: `background:${bg};`,
                colorDotStyle: `background:${c.color};`,
            };
        });
    }

    // ── componentTypeOptionsWithClass (for inline type grid) ──
    get componentTypeOptionsWithClass() {
        const comp = this._getSelectedComp();
        const selType = comp ? comp.type : '';
        return this.componentTypeOptions.map(wt => ({
            ...wt,
            btnClass: `dc-type-btn${selType === wt.value ? ' dc-type-btn-sel' : ''}`
        }));
    }

    // ── sizeOptionsWithClass ──
    get sizeOptionsWithClass() {
        const comp = this._getSelectedComp();
        const selSize = comp ? comp.size : '3';
        return this.sizeOptions.map(sz => ({
            ...sz,
            btnClass: `dc-size-pill${selSize === sz.value ? ' dc-size-pill-sel' : ''}`
        }));
    }

    // ── colorOptionsWithClass ──
    get colorOptionsWithClass() {
        const comp = this._getSelectedComp();
        const selColor = comp ? comp.color : '#0070d2';
        return this.colorOptions.map(col => ({
            ...col,
            swatchClass: `dc-swatch${selColor === col.value ? ' dc-swatch-sel' : ''}`,
            swatchStyle: `background:${col.value};`
        }));
    }

    // ── filterTypeOptions with modalPillClass ──
    get filterTypeOptionsForModal() {
        return this.filterTypeOptions.map(ft => ({
            ...ft,
            modalPillClass: `dc-ftype-pill${this.currentFilter.type === ft.value ? ' dc-ftype-pill-sel' : ''}`
        }));
    }

    // ── previewComponents — exact match to viewer rendering ──
    get previewComponents() {
        const colMap = { 3:'dc-prev-col dc-prev-col-3', 4:'dc-prev-col dc-prev-col-4', 6:'dc-prev-col dc-prev-col-6', 8:'dc-prev-col dc-prev-col-8', 12:'dc-prev-col dc-prev-col-12' };

        // Same 8-color palette as viewer's MULTI_BAR_COLORS
        const BAR_PALETTE = [
            { f:'#0070d2', l:'#1e9bff' }, { f:'#2e844a', l:'#43d17a' },
            { f:'#e87400', l:'#f4a127' }, { f:'#7c4dff', l:'#a87fff' },
            { f:'#0b827c', l:'#12b8b0' }, { f:'#c23934', l:'#e74c3c' },
            { f:'#e3066a', l:'#ff4d9e' }, { f:'#07aee3', l:'#29ccff' },
        ];

        // Sample data labels for each widget type
        const BAR_LABELS  = ['(blank)', 'Registered', 'Agreement Done', 'Draft', 'Cancelled'];
        const BAR_WIDTHS  = [100, 48, 43, 43, 43];
        const RANKED_NAMES = ['Item #1', 'Item #2', 'Item #3', 'Item #4'];
        const RANKED_VALS  = ['₹1,18,400', '₹97,500', '₹55,250', '₹42,000'];
        const STATUS_NAMES = ['Group A', 'Group B', 'Group C'];

        return this.components.map(c => {
            const typeOpt = this.componentTypeOptions.find(t => t.value === c.type) || {};
            const emoji = c.emojiIcon || typeOpt.emoji || '📊';
            const bg = COLOR_BG_MAP[c.color] || 'rgba(0,112,210,0.1)';
            const isKpi = c.type === 'kpi';
            const isSelected = c.id === this.selectedCompId;
            const type = c.type;

            // Which preview style to show
            const showMiniBars   = ['bar', 'progressBar', 'targetProgress'].includes(type);
            const showMiniRanked = ['rankedList', 'rankedTable', 'metricCards'].includes(type);
            const showMiniDonut  = ['pie', 'donut', 'achievementCard'].includes(type);
            const showMiniStatus = type === 'statusCard';
            const showMiniLine   = type === 'line';

            // ── Build mini bars — thick, colorful, with labels ──
            const miniBars = showMiniBars ? BAR_LABELS.map((lbl, i) => {
                const col = BAR_PALETTE[i % BAR_PALETTE.length];
                return {
                    key: `mb-${i}`,
                    label: lbl,
                    val: String(20 - i * 3),
                    fillStyle: `width:${BAR_WIDTHS[i]}%;background:linear-gradient(90deg,${col.f},${col.l});border-radius:9px;`,
                    valStyle: `color:${col.f};`
                };
            }) : [];

            // ── Build mini ranked rows ──
            const miniRanked = showMiniRanked ? RANKED_NAMES.map((name, i) => ({
                key: `mr-${i}`, n: i + 1, name,
                val: RANKED_VALS[i] || '',
                numClass: `dc-mini-rank-num ${i===0?'dc-mini-rank-gold':i===1?'dc-mini-rank-silver':i===2?'dc-mini-rank-bronze':'dc-mini-rank-def'}`,
            })) : [];

            // ── Donut preview ──
            const donutStyle = showMiniDonut
                ? `background:conic-gradient(${c.color} 0% 65%,#e2e8f0 65% 100%);width:56px;height:56px;border-radius:50%;margin:6px auto;`
                : '';

            // ── Status cards preview ──
            const statusColors = ['#2e844a','#0070d2','#e87400'];
            const miniStatus = showMiniStatus ? STATUS_NAMES.map((name, i) => ({
                key: `ms-${i}`, name,
                style: `border-left-color:${statusColors[i]};background:${COLOR_BG_MAP[statusColors[i]]||'rgba(0,112,210,0.06)'};`
            })) : [];

            // ── Line chart mini polyline ──
            const miniLinePoints = showMiniLine
                ? '0,35 24,20 48,28 72,10 96,18 120,8'
                : '';
            const miniLineFill = showMiniLine
                ? '0,40 0,35 24,20 48,28 72,10 96,18 120,8 120,40'
                : '';

            return {
                ...c,
                emojiIcon: emoji,
                typeLabel: typeOpt.label || c.type,
                isKpi, isSelected,
                showMiniBars, showMiniRanked, showMiniDonut, showMiniStatus, showMiniLine,
                miniBars, miniRanked, donutStyle, miniStatus, miniLinePoints, miniLineFill,
                colClass: colMap[c.size] || 'dc-prev-col dc-prev-col-3',
                cardClass: `dc-prev-card${isSelected ? ' dc-prev-card-sel' : ''}`,
                accentStyle: `background:${c.color};`,
                iconBgStyle: `background:${bg};`,
                badgeStyle: `background:${bg};color:${c.color};border-color:${c.color}25;`,
                valueStyle: `color:${c.color};`,
            };
        });
    }

    // ── filtersList computed ──
    get filtersList() {
        return this.filters.map(f => ({
            ...f,
            typeLabel: (this.filterTypeOptions.find(t => t.value === f.type) || {}).label || f.type,
            typeEmoji: (this.filterTypeOptions.find(t => t.value === f.type) || {}).emoji || '🔽',
        }));
    }

    // ── Filter Modal ──
    handleQuickAddFilter(event) {
        const type = event.currentTarget.dataset.type;
        this._openFilterModal(type);
    }

    _openFilterModal(type) {
        this.currentFilter = {
            id: `filter-${Date.now()}`,
            label: '', type: type || 'dateRange', field: '', object: '',
            defaultValue: '', hierarchyMode: 'role', appliesTo: 'all'
        };
        this.currentFilterFields = [];
        this.showFilterModal = true;
    }

    handleEditFilter(event) {
        const id = event.currentTarget.dataset.id;
        const f = this.filters.find(x => x.id === id);
        this.currentFilter = { ...f };
        if (f.object) this.loadFieldsForObject(f.object).then(fields => { this.currentFilterFields = fields; });
        this.showFilterModal = true;
    }

    handleRemoveFilter(event) { const id = event.currentTarget.dataset.id; this.filters = this.filters.filter(f => f.id !== id); }
    handleFilterLabelChange(e) { this.currentFilter = { ...this.currentFilter, label: e.target.value }; }
    handleFilterTypeClick(event) { this.currentFilter = { ...this.currentFilter, type: event.currentTarget.dataset.type }; }
    handleFilterTypeChange(e) { this.currentFilter = { ...this.currentFilter, type: e.detail.value }; }
    handleFilterObjectChange(e) {
        const obj = e.detail.value;
        this.currentFilter = { ...this.currentFilter, object: obj, field: '' };
        this.loadFieldsForObject(obj).then(fields => { this.currentFilterFields = fields; });
    }
    handleFilterFieldChange(e) { this.currentFilter = { ...this.currentFilter, field: e.detail.value }; }
    handleFilterDefaultChange(e) { this.currentFilter = { ...this.currentFilter, defaultValue: e.detail ? e.detail.value : e.target.value }; }
    handleHierarchyModeChange(e) { this.currentFilter = { ...this.currentFilter, hierarchyMode: e.detail.value }; }
    get showHierarchyMode() { return this.currentFilter.type === 'hierarchy'; }
    get showDateLiteralDefault() { return this.currentFilter.type === 'dateLiteral'; }

    // filter modal pill class getter
    get filterTypeOptions() {
        return this._filterTypeOptions || [
            { label: 'Date Range', value: 'dateRange', emoji: '📅' },
            { label: 'Date Literal', value: 'dateLiteral', emoji: '🗓️' },
            { label: 'Picklist', value: 'picklist', emoji: '🔽' },
            { label: 'Text', value: 'text', emoji: '🔤' },
            { label: 'Current User', value: 'currentUser', emoji: '👤' },
            { label: 'User Hierarchy', value: 'userHierarchy', emoji: '👥' },
            { label: 'Cascading Hierarchy', value: 'hierarchy', emoji: '🌲' },
        ];
    }

    get filterTypeOptionsForTemplate() {
        return this.filterTypeOptions.map(ft => ({
            ...ft,
            modalPillClass: `dc-ftype-pill${this.currentFilter.type === ft.value ? ' dc-ftype-pill-sel' : ''}`
        }));
    }

    handleSaveFilter() {
        if (!this.currentFilter.label) { this.showToast('Validation', 'Filter label required', 'warning'); return; }
        const idx = this.filters.findIndex(f => f.id === this.currentFilter.id);
        if (idx >= 0) {
            this.filters = this.filters.map(f => f.id === this.currentFilter.id ? { ...this.currentFilter } : f);
        } else {
            this.filters = [...this.filters, { ...this.currentFilter }];
        }
        this.showFilterModal = false;
    }

    closeFilterModal() { this.showFilterModal = false; }

    // ── Visibility Rules ──
    get showProfilePicker() { return this.currentRule.ruleType === 'Profile'; }
    get showRolePicker() { return this.currentRule.ruleType === 'Role'; }
    get showUserPicker() { return this.currentRule.ruleType === 'User'; }
    get hasUserOptions() { return this.userOptions.length > 0; }

    handleAddRule() { this.currentRule = { ruleType: 'Profile', operator: 'equals', value: '' }; this.showRuleModal = true; }
    handleRuleTypeChange(e) { this.currentRule = { ...this.currentRule, ruleType: e.detail.value, value: '' }; }
    handleRuleOperatorChange(e) { this.currentRule = { ...this.currentRule, operator: e.detail.value }; }
    handleRuleValueChange(e) { this.currentRule = { ...this.currentRule, value: e.detail.value }; }
    handleUserSearch(e) {
        const term = e.target.value;
        if (term && term.length >= 2) searchUsers({ searchTerm: term }).then(r => { this.userOptions = r.map(u => ({ label: u.label, value: u.value })); }).catch(console.error);
    }
    handleSaveRule() {
        if (this.currentRule.value) {
            this.visibilityRules = [...this.visibilityRules, { ...this.currentRule, key: `rule-${Date.now()}` }];
            this.showRuleModal = false;
        }
    }
    handleRemoveRule(e) { const key = e.currentTarget.dataset.key; this.visibilityRules = this.visibilityRules.filter(r => r.key !== key); }
    closeRuleModal() { this.showRuleModal = false; }

    // ── Save ──
    handleSave() {
        if (!this.dashboardName) { this.showToast('Validation', 'Dashboard name is required', 'error'); return; }
        if (this.components.length === 0) { this.showToast('Validation', 'Add at least one component', 'error'); return; }

        const configJson = {
            header: this.headerConfig,
            components: this.components.map(c => {
                const comp = { ...c };
                delete comp.typeLabel; delete comp.sizeLabel; delete comp.rowClass;
                delete comp.iconBgStyle; delete comp.colorDotStyle; delete comp.isSelected;
                if (comp.staticFilters) comp.staticFilters = comp.staticFilters.map(sf => ({ field: sf.field, operator: sf.operator, value: sf.value }));
                return comp;
            }),
            filters: this.filters.map(f => { const x = { ...f }; delete x.typeLabel; delete x.typeEmoji; return x; }),
            visibilityRules: this.visibilityRules.map(r => ({ ruleType: r.ruleType, operator: r.operator, value: r.value }))
        };

        this.isLoading = true;
        saveDashboardConfig({ configId: this.editingConfigId, configName: this.dashboardName, description: this.description, active: this.isActive, configJson: JSON.stringify(configJson) })
            .then(() => { this.showToast('Success', 'Dashboard saved!', 'success'); this.isLoading = false; this.handleBackToList(); })
            .catch(e => { this.showToast('Error', 'Failed to save', 'error'); this.isLoading = false; console.error(e); });
    }

    resetForm() {
        this.editingConfigId = null; this.dashboardName = ''; this.description = ''; this.isActive = true;
        this.components = []; this.filters = []; this.visibilityRules = [];
        this.headerConfig = { title: '', subtitle: '', showDate: true, gradientStart: '#1b2a4a', gradientEnd: '#0176d3', textColor: '#ffffff' };
        this.showHeaderSection = false; this.selectedCompId = null; this.currentStep = 1;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}