import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import getProjects from '@salesforce/apex/ProjectBoardControllerClass.getProjects';
import getProjectStatuses from '@salesforce/apex/ProjectBoardControllerClass.getProjectStatuses';
import getPlots from '@salesforce/apex/ProjectBoardControllerClass.getPlots';
import getTowers from '@salesforce/apex/ProjectBoardControllerClass.getTowers';
import getUnitsByTower from '@salesforce/apex/ProjectBoardControllerClass.getUnitsByTower';
import getProjectImages from '@salesforce/apex/ProjectBoardControllerClass.getProjectImages';
import saveProjectImage from '@salesforce/apex/ProjectBoardControllerClass.saveProjectImage';
import PROPERTY_IMAGES from '@salesforce/resourceUrl/Property_images';

const TYPE_GRADIENTS = {
    'Apartment'    : 'linear-gradient(135deg,#0f2027 0%,#203a43 50%,#2c5364 100%)',
    'Villa'        : 'linear-gradient(135deg,#134e5e 0%,#71b280 100%)',
    'Plot'         : 'linear-gradient(135deg,#373b44 0%,#4286f4 100%)',
    'Duplex'       : 'linear-gradient(135deg,#3a1c71 0%,#d76d77 50%,#ffaf7b 100%)',
    'Penthouse'    : 'linear-gradient(135deg,#1a1a2e 0%,#16213e 50%,#0f3460 100%)',
    'Commercial'   : 'linear-gradient(135deg,#1d3557 0%,#457b9d 100%)',
    'default'      : 'linear-gradient(135deg,#1d3557 0%,#457b9d 100%)'
};

const TYPE_IMAGES = {
    'Apartment'  : PROPERTY_IMAGES + '/Property_images/Apartment.jpg',
    'Villa'      : PROPERTY_IMAGES + '/Property_images/villa.jpg',
    'Plot'       : PROPERTY_IMAGES + '/Property_images/plot.jpg',
    'Duplex'     : PROPERTY_IMAGES + '/Property_images/Duplex.jpg',
    'Penthouse'  : PROPERTY_IMAGES + '/Property_images/penthouse.jpg',
    'Commercial' : PROPERTY_IMAGES + '/Property_images/commercial.jpg',
    'default'    : PROPERTY_IMAGES + '/default.jpg'
};

const STATUS_RIBBON = {
    'Available'           : { bg: '#22c55e', color: '#fff' },
    'Booked'              : { bg: '#3b82f6', color: '#fff' },
    'Sold'                : { bg: '#ef4444', color: '#fff' },
    'NOT RELEASE FOR SALE': { bg: '#f59e0b', color: '#fff' },
    'BLOCKED'             : { bg: '#9ca3af', color: '#fff' }
};

const STATUS_CELL_CLASS = {
    'Available'           : 'cell--available',
    'Booked'              : 'cell--booked',
    'Sold'                : 'cell--sold',
    'NOT RELEASE FOR SALE': 'cell--notrel',
    'BLOCKED'             : 'cell--blocked'
};

const TOWER_TYPES = ['Apartment', 'Penthouse', 'Duplex'];

export default class ProjectBoard extends NavigationMixin(LightningElement) {

    // ── View state ──────────────────────────────────────────────
    @track showProjects = true;
    @track showTowers = false;
    @track showFloorGrid = false;
    @track showPlots = false;
    @track isLoading = false;

    // ── Project data ────────────────────────────────────────────
    @track allProjects = [];
    @track filteredProjects = [];
    searchTerm = '';
    selectedType = 'all';
    @track projectStatusOptions = [];
    selectedProjectStatus = 'all';

    // ── Tower data ──────────────────────────────────────────────
    @track allTowers = [];
    selectedProjectId = null;
    projectName = '';
    @track selectedProjectImage = '';
    @track selectedProjectGradient = '';
    @track selectedPropertyTypes = [];
    @track activePropertyTab = '';
    @track isMixedProject = false;

    // ── Floor grid data ─────────────────────────────────────────
    @track floorRows = [];
    @track allFloorUnits = [];
    selectedTowerId = null;
    selectedTowerName = '';
    filterBhk = '';

    // ── Unit data (flat grid) ───────────────────────────────────
    @track allPlots = [];
    @track filteredPlots = [];
    selectedUnitStatus = 'all';

    get typedPlots() {
        if (!this.activePropertyTab) {
            return this.allPlots;
        }
        return this.allPlots.filter(p => p.Unit_Type__c === this.activePropertyTab);
    }

    // ── Summary stats ───────────────────────────────────────────
    totalProjects = 0;
    totalAvailableUnits = 0;
    totalBookedUnits = 0;
    totalSoldUnits = 0;

    _fontsLoaded = false;

    // ── New Project modal ─────────────────────────────────────
    @track showNewProjectModal = false;
    @track newProjectRecordId = null;

    // ── Image upload ──────────────────────────────────────────
    @track showImageUploadModal = false;
    @track imageUploadProjectId = null;
    @track imageUploadProjectName = '';
    @track projectImageMap = {};

    // ── Lifecycle ───────────────────────────────────────────────
    connectedCallback() {
        this.loadProjects();
        this.loadProjectStatuses();
        // Reload data when user navigates back to this page (bfcache restore)
        this._boundPageShow = this._handlePageShow.bind(this);
        window.addEventListener('pageshow', this._boundPageShow);
    }

    disconnectedCallback() {
        if (this._boundPageShow) {
            window.removeEventListener('pageshow', this._boundPageShow);
        }
    }

    _handlePageShow(event) {
        // event.persisted = true means page was restored from back-forward cache
        if (event.persisted) {
            if (this.showProjects) {
                this.loadProjects();
            } else if (this.showTowers && this.selectedProjectId) {
                this.loadTowersData(this.selectedProjectId);
            } else if (this.showFloorGrid && this.selectedTowerId) {
                this.loadFloorGridData(this.selectedTowerId);
            }
        }
    }

    renderedCallback() {
        if (this._fontsLoaded) return;
        this._fontsLoaded = true;
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = 'https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@400;600;700&family=DM+Sans:wght@300;400;500;600&display=swap';
        document.head.appendChild(link);
    }

    // ══════════════════════════════════════════════════════════════
    // DATA LOADING
    // ══════════════════════════════════════════════════════════════

    async loadProjects() {
        this.isLoading = true;
        try {
            const data = await getProjects();
            this.allProjects = data.map(p => this.enrichProject(p));

            // Fetch custom uploaded images for all projects
            const projectIds = data.map(p => p.Id);
            if (projectIds.length > 0) {
                try {
                    this.projectImageMap = await getProjectImages({ projectIds });
                } catch (imgErr) {
                    this.projectImageMap = {};
                }
                // Override imageUrl where a custom image has been uploaded
                this.allProjects = this.allProjects.map(p => ({
                    ...p,
                    imageUrl: this.projectImageMap[p.Id] || p.imageUrl,
                    hasCustomImage: !!this.projectImageMap[p.Id]
                }));
            }

            this.calculateGlobalStats();
            this.applyProjectFilters();
        } catch (e) {
            this.showToast('Error', 'Failed to load projects', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadProjectStatuses() {
        try {
            const data = await getProjectStatuses();
            const options = (data || []).map(s => ({ label: s, value: s }));
            this.projectStatusOptions = [
                { label: 'All Statuses', value: 'all' },
                ...options
            ];
        } catch (e) {
            this.projectStatusOptions = [{ label: 'All Statuses', value: 'all' }];
        }
    }

    async loadTowersData(projectId) {
        this.isLoading = true;
        try {
            const data = await getTowers({ projectId });
            this.allTowers = data.map(t => this.enrichTower(t));
        } catch (e) {
            this.showToast('Error', 'Failed to load towers', 'error');
            this.allTowers = [];
        } finally {
            this.isLoading = false;
        }
    }

    async loadFloorGridData(towerId) {
        this.isLoading = true;
        try {
            const data = await getUnitsByTower({ towerId });
            this.selectedTowerName = data.towerName || this.selectedTowerName;
            const floors = data.floors || [];
            this.allFloorUnits = [];
            this.floorRows = floors.map(f => {
                const enrichedUnits = f.units.map(u => {
                    this.allFloorUnits.push(u);
                    return this.enrichFloorUnit(u);
                });
                return {
                    floorNumber: f.floorNumber,
                    floorLabel: 'F' + (f.floorNumber != null ? f.floorNumber : '?'),
                    units: enrichedUnits
                };
            });
        } catch (e) {
            this.showToast('Error', 'Failed to load floor data', 'error');
            this.floorRows = [];
        } finally {
            this.isLoading = false;
        }
    }

    async loadPlots(projectId) {
        this.isLoading = true;
        try {
            const data = await getPlots({ Project: projectId });
            this.allPlots = data.map(p => this.enrichPlot(p));
            this.selectedUnitStatus = 'all';
            this.applyUnitFilters();
        } catch (e) {
            this.showToast('Error', 'Failed to load units', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ══════════════════════════════════════════════════════════════
    // ENRICHMENT
    // ══════════════════════════════════════════════════════════════

    enrichProject(p) {
        const total = p.Total_Units__c || 0;
        const available = Math.max(0, p.Available_Units__c || 0);
        const booked = Math.max(0, p.Booked_Units__c || 0);
        const notReleased = Math.max(0, total - available - booked);
        const sold = total > 0 ? Math.max(0, total - available - booked - notReleased) : 0;
        const pct = total > 0 ? Math.min(100, (booked / total) * 100) : 0;
        const propertyTypes = p.Property_Types__c
            ? p.Property_Types__c.split(';').map(s => s.trim()).filter(Boolean)
            : [];
        const primaryType = propertyTypes.length > 0 ? propertyTypes[0] : '';
        const gradient = TYPE_GRADIENTS[primaryType] || TYPE_GRADIENTS['default'];
        const imageUrl = TYPE_IMAGES[primaryType] || TYPE_IMAGES['default'];
        const locationParts = [p.Address__c, p.City__c, p.State__c].filter(Boolean);
        const locationText = locationParts.join(', ') || 'Location not specified';

        const statusColors = {
            'Active': 'background:#16a34a;color:#fff',
            'Upcoming': 'background:#2563eb;color:#fff',
            'Completed': 'background:#7c3aed;color:#fff',
            'On Hold': 'background:#d97706;color:#fff',
            'Launched': 'background:#059669;color:#fff',
            'Pre-Launch': 'background:#0ea5e9;color:#fff'
        };
        const projectStatus = p.Project_Status__c || '';
        const statusPillStyle = statusColors[projectStatus] || 'background:rgba(14,165,233,0.9);color:#fff';
        const hasStatus = !!projectStatus;

        return {
            ...p,
            bookedTotal: booked,
            notReleasedCount: notReleased,
            soldCount: sold,
            availableCount: available,
            propertyTypeList: propertyTypes,
            primaryType,
            locationText,
            imageUrl,
            hasStatus,
            statusPillStyle,
            progressPercentage: pct.toFixed(1) + '%',
            progressStyle: `width:${pct}%`,
            cardStyle: `background:${gradient}`
        };
    }

    enrichTower(t) {
        const available = t.availableCount || 0;
        const booked = t.bookedCount || 0;
        const sold = t.soldCount || 0;
        const notReleased = t.notReleasedCount || 0;
        const blocked = t.blockedCount || 0;
        const total = t.totalUnitCount || 1;

        const pA = (available / total) * 100;
        const pB = pA + (booked / total) * 100;
        const pS = pB + (sold / total) * 100;
        const pN = pS + (notReleased / total) * 100;

        const donutStyle = `background: conic-gradient(#22c55e 0% ${pA}%, #3b82f6 ${pA}% ${pB}%, #ef4444 ${pB}% ${pS}%, #f59e0b ${pS}% ${pN}%, #9ca3af ${pN}% 100%)`;
        const floors = t.Total_Floors__c || 5;
        const buildingHeight = Math.min(Math.max(floors * 8, 60), 160);

        return {
            ...t,
            donutStyle,
            buildingStyle: `height:${buildingHeight}px`,
            totalUnits: total
        };
    }

    enrichFloorUnit(u) {
        const status = u.Status__c || '';
        const cellClass = 'unit-cell ' + (STATUS_CELL_CLASS[status] || 'cell--default');
        const area = u.Super_Builtup_Area__c || u.Super_Built_Up_Area__c || u.Carpet_Area__c || '';
        const displayArea = area ? (area + ' sqft') : '';
        return {
            ...u,
            cellClass,
            displayArea,
            tooltip: `${u.Name || ''} | ${u.BHK_Type__c || ''} | ${status} | ${displayArea}`
        };
    }

    enrichPlot(p) {
        const ribbonCfg = STATUS_RIBBON[p.Status__c] || { bg: '#6b7280', color: '#fff' };
        const statusClass = this.getStatusClass(p.Status__c);
        const towerName = p.Tower__r ? p.Tower__r.Name : (p.Tower_Block__c || '');
        return {
            ...p,
            isAvailable: p.Status__c === 'Available',
            unitCardClass: `unit-card unit-card--${statusClass}`,
            ribbonStyle: `background:${ribbonCfg.bg};color:${ribbonCfg.color}`,
            towerName,
            displayArea: p.Super_Builtup_Area__c || p.Super_Built_Up_Area__c || p.Carpet_Area__c || ''
        };
    }

    getStatusClass(status) {
        const map = {
            'Available': 'available', 'Booked': 'booked', 'Sold': 'sold',
            'NOT RELEASE FOR SALE': 'notrel', 'BLOCKED': 'blocked'
        };
        return map[status] || 'default';
    }

    // ══════════════════════════════════════════════════════════════
    // STATS & FILTERS
    // ══════════════════════════════════════════════════════════════

    calculateGlobalStats() {
        this.totalProjects = this.allProjects.length;
        this.totalAvailableUnits = this.allProjects.reduce((s, p) => s + (p.availableCount || 0), 0);
        this.totalBookedUnits    = this.allProjects.reduce((s, p) => s + (p.bookedTotal || 0), 0);
        this.totalSoldUnits      = Math.max(0, this.allProjects.reduce((s, p) => s + (p.notReleasedCount || 0), 0));
    }

    applyProjectFilters() {
        let result = [...this.allProjects];
        if (this.selectedType !== 'all') {
            result = result.filter(p => p.primaryType === this.selectedType);
        }
        if (this.selectedProjectStatus !== 'all') {
            result = result.filter(p => p.Project_Status__c === this.selectedProjectStatus);
        }
        if (this.searchTerm) {
            const q = this.searchTerm.toLowerCase();
            result = result.filter(p =>
                (p.Name && p.Name.toLowerCase().includes(q)) ||
                (p.Address__c && p.Address__c.toLowerCase().includes(q)) ||
                (p.City__c && p.City__c.toLowerCase().includes(q))
            );
        }
        this.filteredProjects = result;
    }

    applyUnitFilters() {
        const base = this.typedPlots;
        if (this.selectedUnitStatus === 'all') {
            this.filteredPlots = [...base];
        } else {
            this.filteredPlots = base.filter(p => p.Status__c === this.selectedUnitStatus);
        }
    }

    // ══════════════════════════════════════════════════════════════
    // COMPUTED GETTERS
    // ══════════════════════════════════════════════════════════════

    get projectTypeOptions() {
        const types = [...new Set(this.allProjects.map(p => p.primaryType).filter(Boolean))];
        const icons = {
            'Apartment': '🏢', 'Villa': '🏡', 'Plot': '🌿',
            'Duplex': '🏘️', 'Penthouse': '🌇', 'Commercial': '🏬'
        };
        return [
            {
                value: 'all', label: 'All Types', icon: '🏗️',
                count: this.allProjects.length,
                cssClass: this.selectedType === 'all' ? 'type-tab type-tab--active' : 'type-tab'
            },
            ...types.map(t => ({
                value: t, label: t, icon: icons[t] || '🏠',
                count: this.allProjects.filter(p => p.primaryType === t).length,
                cssClass: this.selectedType === t ? 'type-tab type-tab--active' : 'type-tab'
            }))
        ];
    }

    get unitStatusOptions() {
        const statuses = [
            { value: 'all',                  label: 'All',          dot: '#6b7280' },
            { value: 'Available',            label: 'Available',    dot: '#22c55e' },
            { value: 'Booked',               label: 'Booked',       dot: '#3b82f6' },
            { value: 'Sold',                 label: 'Sold',         dot: '#ef4444' },
            { value: 'NOT RELEASE FOR SALE', label: 'Not Released', dot: '#f59e0b' },
            { value: 'BLOCKED',              label: 'Blocked',      dot: '#9ca3af' }
        ];
        const base = this.typedPlots;
        return statuses.map(s => ({
            ...s,
            count: s.value === 'all'
                ? base.length
                : base.filter(p => p.Status__c === s.value).length,
            dotStyle: `background:${s.dot}`,
            chipClass: this.selectedUnitStatus === s.value ? 'unit-chip unit-chip--active' : 'unit-chip'
        }));
    }

    get projectStatusSummary() {
        const statusValues = this.projectStatusOptions
            .filter(o => o.value !== 'all')
            .map(o => o.value);
        const list = statusValues.length
            ? statusValues
            : [...new Set(this.filteredProjects.map(p => p.Project_Status__c).filter(Boolean))];

        const summary = list.map(s => ({
            label: s,
            count: this.filteredProjects.filter(p => p.Project_Status__c === s).length
        }));

        const unspecifiedCount = this.filteredProjects.filter(p => !p.Project_Status__c).length;
        if (unspecifiedCount > 0) {
            summary.push({ label: 'Unspecified', count: unspecifiedCount });
        }
        return summary;
    }

    get propertyTypeTabs() {
        return this.selectedPropertyTypes.map(pt => ({
            value: pt, label: pt,
            tabClass: this.activePropertyTab === pt ? 'prop-tab prop-tab--active' : 'prop-tab'
        }));
    }

    get showTowerCards() {
        return TOWER_TYPES.includes(this.activePropertyTab);
    }

    get showUnitGridInTowers() {
        return this.activePropertyTab && !TOWER_TYPES.includes(this.activePropertyTab);
    }

    get bhkFilterOptions() {
        const bhks = [...new Set(this.allFloorUnits.map(u => u.BHK_Type__c).filter(Boolean))].sort();
        return [{ label: 'All BHK', value: '' }, ...bhks.map(b => ({ label: b, value: b }))];
    }

    get filteredFloorRows() {
        if (!this.filterBhk) return this.floorRows;
        return this.floorRows.map(floor => ({
            ...floor,
            units: floor.units.filter(u => u.BHK_Type__c === this.filterBhk)
        })).filter(floor => floor.units.length > 0);
    }

    get floorGridSummary() {
        const counts = { Available: 0, Booked: 0, Sold: 0, 'NOT RELEASE FOR SALE': 0, BLOCKED: 0 };
        this.allFloorUnits.forEach(u => {
            if (u.Status__c in counts) counts[u.Status__c]++;
        });
        return [
            { label: 'Available', count: counts['Available'], cls: 'summary-chip summary-chip--available' },
            { label: 'Booked', count: counts['Booked'], cls: 'summary-chip summary-chip--booked' },
            { label: 'Sold', count: counts['Sold'], cls: 'summary-chip summary-chip--sold' },
            { label: 'Not Released', count: counts['NOT RELEASE FOR SALE'], cls: 'summary-chip summary-chip--notrel' },
            { label: 'Blocked', count: counts['BLOCKED'], cls: 'summary-chip summary-chip--blocked' }
        ];
    }

    get hasProjectBackground() {
        return !!this.selectedProjectImage && !this.showProjects;
    }

    get projectBackgroundStyle() {
        return this.selectedProjectGradient || '';
    }

    get noProjectsFound() { return !this.isLoading && this.filteredProjects.length === 0 && this.showProjects; }
    get noUnitsFound() { return !this.isLoading && this.filteredPlots.length === 0 && this.showPlots; }
    get noTowersFound() { return !this.isLoading && this.allTowers.length === 0 && this.showTowers && this.showTowerCards; }
    get noFloorUnits() { return !this.isLoading && this.floorRows.length === 0 && this.showFloorGrid; }

    // ══════════════════════════════════════════════════════════════
    // EVENT HANDLERS
    // ══════════════════════════════════════════════════════════════

    handleTypeFilter(event) {
        this.selectedType = event.currentTarget.dataset.value;
        this.applyProjectFilters();
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.applyProjectFilters();
    }

    handleProjectStatusChange(event) {
        this.selectedProjectStatus = event.detail.value;
        this.applyProjectFilters();
    }

    handleLoadPlots(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.projectName = name;
        this.selectedProjectId = id;

        const proj = this.allProjects.find(p => p.Id === id);
        this.selectedProjectImage = proj ? proj.imageUrl : (TYPE_IMAGES['default']);
        this.selectedProjectGradient = proj ? proj.cardStyle : '';
        const propertyTypes = proj ? (proj.propertyTypeList || []) : [];
        this.selectedPropertyTypes = propertyTypes;
        this.isMixedProject = propertyTypes.length > 1;

        const hasTowerType = propertyTypes.some(t => TOWER_TYPES.includes(t));

        if (hasTowerType) {
            this.activePropertyTab = propertyTypes.find(t => TOWER_TYPES.includes(t)) || propertyTypes[0];
            this.showProjects = false;
            this.showTowers = true;
            this.showPlots = false;
            this.showFloorGrid = false;
            this.loadTowersData(id);
            if (this.isMixedProject) this.loadPlots(id);
        } else {
            this.activePropertyTab = propertyTypes[0] || '';
            this.showProjects = false;
            this.showPlots = true;
            this.showTowers = false;
            this.showFloorGrid = false;
            this.loadPlots(id);
        }
    }

    handlePropertyTypeTab(event) {
        const newTab = event.currentTarget.dataset.value;
        this.activePropertyTab = newTab;
        this.selectedUnitStatus = 'all';
        if (TOWER_TYPES.includes(newTab)) {
            if (this.allTowers.length === 0) this.loadTowersData(this.selectedProjectId);
        } else {
            this.showFloorGrid = false;
            if (this.allPlots.length === 0) {
                this.loadPlots(this.selectedProjectId);
            } else {
                this.applyUnitFilters();
            }
        }
    }

    handleTowerClick(event) {
        this.selectedTowerId = event.currentTarget.dataset.id;
        this.selectedTowerName = event.currentTarget.dataset.name;
        this.showTowers = false;
        this.showFloorGrid = true;
        this.filterBhk = '';
        this.loadFloorGridData(this.selectedTowerId);
    }

    handleBhkFilter(event) { this.filterBhk = event.detail.value; }

    handleUnitCellClick(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, objectApiName: 'Unit__c', actionName: 'view' }
        });
    }

    handleBack() {
        if (this.showFloorGrid) {
            this.showFloorGrid = false;
            this.showTowers = true;
            this.floorRows = [];
            this.allFloorUnits = [];
            this.filterBhk = '';
        } else if (this.showTowers || this.showPlots) {
            this.handleBackToProjects();
        }
    }

    handleBackToProjects() {
        this.showTowers = false;
        this.showFloorGrid = false;
        this.showPlots = false;
        this.showProjects = true;
        this.allTowers = [];
        this.allPlots = [];
        this.filteredPlots = [];
        this.floorRows = [];
        this.allFloorUnits = [];
        this.selectedPropertyTypes = [];
        this.activePropertyTab = '';
        this.isMixedProject = false;
        this.filterBhk = '';
        this.selectedProjectImage = '';
        this.selectedProjectGradient = '';
        this.loadProjects(); // Refresh project data with latest unit counts
    }

    handleBackToTowers() {
        this.showFloorGrid = false;
        this.showTowers = true;
        this.floorRows = [];
        this.allFloorUnits = [];
        this.filterBhk = '';
        if (this.selectedProjectId) {
            this.loadTowersData(this.selectedProjectId); // Refresh tower unit counts
        }
    }

    handleUnitFilter(event) {
        this.selectedUnitStatus = event.currentTarget.dataset.value;
        this.applyUnitFilters();
    }

    handleNavigatePlot(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, objectApiName: 'Unit__c', actionName: 'view' }
        });
    }

    // ══════════════════════════════════════════════════════════════
    // NEW PROJECT (modal with lightning-record-form + image upload)
    // ══════════════════════════════════════════════════════════════

    handleNewProject() {
        this.showNewProjectModal = true;
        this.newProjectRecordId = null;
    }

    handleNewProjectSuccess(event) {
        this.newProjectRecordId = event.detail.id;
        this.showToast('Success', 'Project created successfully', 'success');
    }

    handleNewProjectImageUploadFinished(event) {
        const files = event.detail.files;
        if (files && files.length > 0 && this.newProjectRecordId) {
            saveProjectImage({
                projectId: this.newProjectRecordId,
                contentDocumentId: files[0].documentId
            })
                .then(() => {
                    this.showToast('Success', 'Image uploaded successfully', 'success');
                })
                .catch(() => {
                    this.showToast('Error', 'Failed to link image', 'error');
                });
        }
    }

    handleCloseNewProjectModal() {
        this.showNewProjectModal = false;
        if (this.newProjectRecordId) {
            this.loadProjects();
        }
        this.newProjectRecordId = null;
    }

    // ══════════════════════════════════════════════════════════════
    // NEW UNIT (standard form with pre-populated Project)
    // ══════════════════════════════════════════════════════════════

    handleNewUnit() {
        const defaultValues = encodeDefaultFieldValues({
            Project__c: this.selectedProjectId
        });
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Unit__c',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: defaultValues
            }
        });
    }

    // ══════════════════════════════════════════════════════════════
    // IMAGE UPLOAD ON EXISTING PROJECT CARDS
    // ══════════════════════════════════════════════════════════════

    handleUploadImage(event) {
        event.stopPropagation();
        this.imageUploadProjectId = event.currentTarget.dataset.id;
        this.imageUploadProjectName = event.currentTarget.dataset.name;
        this.showImageUploadModal = true;
    }

    handleCloseImageUpload() {
        this.showImageUploadModal = false;
        this.imageUploadProjectId = null;
        this.imageUploadProjectName = '';
    }

    async handleImageUploadFinished(event) {
        const files = event.detail.files;
        if (files && files.length > 0) {
            try {
                await saveProjectImage({
                    projectId: this.imageUploadProjectId,
                    contentDocumentId: files[0].documentId
                });
                this.showToast('Success', 'Project image updated', 'success');
                this.handleCloseImageUpload();
                await this.loadProjects();
            } catch (e) {
                this.showToast('Error', 'Failed to update image', 'error');
            }
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}