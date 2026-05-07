import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Report Config CRUD
import getAllReportConfigs from '@salesforce/apex/ReportConfigController.getAllReportConfigs';
import getReportConfig from '@salesforce/apex/ReportConfigController.getReportConfig';
import saveReportConfig from '@salesforce/apex/ReportConfigController.saveReportConfig';
import deleteReportConfig from '@salesforce/apex/ReportConfigController.deleteReportConfig';
import cloneReportConfig from '@salesforce/apex/ReportConfigController.cloneReportConfig';

// Metadata
import getAllObjects from '@salesforce/apex/ReportConfigController.getAllObjects';
import getObjectFields from '@salesforce/apex/ReportConfigController.getObjectFields';
import getChildRelationships from '@salesforce/apex/ReportConfigController.getChildRelationships';
import getLookupObjectFields from '@salesforce/apex/ReportConfigController.getLookupObjectFields';

// Visibility
import getAllProfiles from '@salesforce/apex/ReportConfigController.getAllProfiles';
import getAllRoles from '@salesforce/apex/ReportConfigController.getAllRoles';
import searchUsers from '@salesforce/apex/ReportConfigController.searchUsers';

// Report execution
import executeReport from '@salesforce/apex/ReportDataService.executeReport';

export default class ReportConfigurator extends LightningElement {
    @track currentView = 'list'; // list | builder | preview
    @track isLoading = false;
    @track configurations = [];

    // ── Builder State ──
    @track editingConfigId = null;
    @track reportName = '';
    @track reportDescription = '';
    @track reportActive = false;
    @track currentStep = 1;

    // ── Report Config (single report, no sections) ──
    @track primaryObject = '';
    @track parentColumns = [];
    @track childObjects = [];
    @track parentFilters = [];
    @track sortField = 'CreatedDate';
    @track sortOrder = 'DESC';
    @track recordLimit = 500;

    // ── Visibility ──
    @track visibilityRules = [];
    @track showVisibilityModal = false;
    @track currentVisibilityRule = {};
    @track currentVisibilityRuleIndex = -1;
    @track profileOptions = [];
    @track roleOptions = [];
    @track userSearchResults = [];
    @track userSearchTerm = '';

    // ── Metadata ──
    @track objectOptions = [];
    @track parentFieldOptions = [];
    @track childRelationshipOptions = [];

    // ── Child Object Editor ──
    @track showChildObjectModal = false;
    @track currentChildObject = {};
    @track currentChildObjectIndex = -1;
    @track childObjectFields = [];

    // ── Child Modal Collapsible Sections ──
    @track showChildColumnsSection = true;
    @track showChildAggregatesSection = false;
    @track showChildFiltersSection = false;

    // ── Lookup Fields (Step 2) ──
    @track showLookupFieldsSection = false;
    @track selectedLookupField = '';
    @track lookupObjectFieldOptions = [];

    // ── Child Aggregate Editor ──
    @track showChildAggregateModal = false;
    @track currentChildAggregate = {};
    @track currentChildAggregateIndex = -1;

    // ── Child Filter Editor ──
    @track showChildFilterModal = false;
    @track currentChildFilter = {};
    @track currentChildFilterIndex = -1;

    // ── Parent Filter Editor ──
    @track showParentFilterModal = false;
    @track currentParentFilter = {};
    @track currentParentFilterIndex = -1;

    // ── Preview ──
    @track previewResult = null;
    @track previewError = '';

    // ── Options ──
    aggregationOptions = [
        { label: 'COUNT', value: 'COUNT' },
        { label: 'SUM', value: 'SUM' },
        { label: 'AVG', value: 'AVG' },
        { label: 'MIN', value: 'MIN' },
        { label: 'MAX', value: 'MAX' },
        { label: 'COUNT_DISTINCT', value: 'COUNT_DISTINCT' }
    ];

    operatorOptions = [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Greater Than', value: 'greaterThan' },
        { label: 'Less Than', value: 'lessThan' },
        { label: 'Contains', value: 'contains' },
        { label: 'Greater or Equal', value: 'greaterOrEqual' },
        { label: 'Less or Equal', value: 'lessOrEqual' }
    ];

    sortOrderOptions = [
        { label: 'Newest First (DESC)', value: 'DESC' },
        { label: 'Oldest First (ASC)', value: 'ASC' }
    ];

    displayModeOptions = [
        { label: 'Horizontal (Side-by-side columns)', value: 'horizontal' },
        { label: 'Vertical (Stacked rows below parent)', value: 'vertical' },
        { label: 'Aggregate Only (Summaries only)', value: 'aggregateOnly' },
        { label: 'Hybrid (Records + Summaries)', value: 'hybrid' }
    ];

    visibilityRuleTypeOptions = [
        { label: 'Profile', value: 'Profile' },
        { label: 'Role', value: 'Role' },
        { label: 'User', value: 'User' }
    ];

    visibilityOperatorOptions = [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Contains', value: 'contains' }
    ];

    static NUMERIC_TYPES = ['CURRENCY', 'DOUBLE', 'INTEGER', 'LONG', 'PERCENT', 'DECIMAL', 'NUMBER'];

    connectedCallback() {
        this.loadConfigurations();
        this.loadObjects();
        this.loadProfiles();
        this.loadRoles();
    }

    @api
    refresh() {
        this.loadConfigurations();
    }

    // ── View Getters ──
    get isListView() { return this.currentView === 'list'; }
    get isBuilderView() { return this.currentView === 'builder'; }
    get isPreviewView() { return this.currentView === 'preview'; }
    get hasConfigurations() { return this.configurations && this.configurations.length > 0; }

    // ── Step Getters ──
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get canGoNext() { return this.currentStep < 5; }
    get canGoPrev() { return this.currentStep > 1; }

    get stepItems() {
        return [
            { num: 1, label: 'Primary Object', isCurrent: this.currentStep === 1, isDone: this.currentStep > 1, cls: this.currentStep === 1 ? 'step-item step-current' : (this.currentStep > 1 ? 'step-item step-done' : 'step-item') },
            { num: 2, label: 'Parent Columns', isCurrent: this.currentStep === 2, isDone: this.currentStep > 2, cls: this.currentStep === 2 ? 'step-item step-current' : (this.currentStep > 2 ? 'step-item step-done' : 'step-item') },
            { num: 3, label: 'Child Objects', isCurrent: this.currentStep === 3, isDone: this.currentStep > 3, cls: this.currentStep === 3 ? 'step-item step-current' : (this.currentStep > 3 ? 'step-item step-done' : 'step-item') },
            { num: 4, label: 'Filters & Sort', isCurrent: this.currentStep === 4, isDone: this.currentStep > 4, cls: this.currentStep === 4 ? 'step-item step-current' : (this.currentStep > 4 ? 'step-item step-done' : 'step-item') },
            { num: 5, label: 'Sharing & Save', isCurrent: this.currentStep === 5, isDone: false, cls: this.currentStep === 5 ? 'step-item step-current' : 'step-item' }
        ];
    }

    get hasParentColumns() { return this.parentColumns && this.parentColumns.length > 0; }
    get hasChildObjects() { return this.childObjects && this.childObjects.length > 0; }
    get hasParentFilters() { return this.parentFilters && this.parentFilters.length > 0; }
    get hasVisibilityRules() { return this.visibilityRules && this.visibilityRules.length > 0; }

    get hasPreviewSections() {
        return this.previewResult && this.previewResult.sections && this.previewResult.sections.length > 0;
    }

    get isVisibilityRuleTypeProfile() { return this.currentVisibilityRule.ruleType === 'Profile'; }
    get isVisibilityRuleTypeRole() { return this.currentVisibilityRule.ruleType === 'Role'; }
    get isVisibilityRuleTypeUser() { return this.currentVisibilityRule.ruleType === 'User'; }

    get visibilityValueOptions() {
        if (this.currentVisibilityRule.ruleType === 'Profile') return this.profileOptions;
        if (this.currentVisibilityRule.ruleType === 'Role') return this.roleOptions;
        return [];
    }

    // Child object modal getters
    get currentChildObjectHasColumns() {
        return this.currentChildObject.columns && this.currentChildObject.columns.length > 0;
    }
    get currentChildObjectHasAggregates() {
        return this.currentChildObject.aggregates && this.currentChildObject.aggregates.length > 0;
    }
    get currentChildObjectHasFilters() {
        return this.currentChildObject.filters && this.currentChildObject.filters.length > 0;
    }
    get childObjectDisplayColumns() {
        if (!this.currentChildObject.columns) return [];
        return this.currentChildObject.columns.map((col, idx) => ({ ...col, index: idx, key: 'col-' + idx }));
    }
    get filteredChildAggregateFields() {
        if (!this.currentChildAggregate.aggregation) return this.childObjectFields;
        const agg = this.currentChildAggregate.aggregation;
        if (agg === 'COUNT' || agg === 'COUNT_DISTINCT') return this.childObjectFields;
        return this.childObjectFields.filter(f => ReportConfigurator.NUMERIC_TYPES.includes(f.type));
    }
    get childDisplayModeHelp() {
        const m = {
            horizontal: 'Child records appear as extra columns next to the parent. Best for small, predictable counts.',
            vertical: 'Child records appear as stacked rows under the parent. Best for variable counts.',
            aggregateOnly: 'Only shows calculated summaries (COUNT, SUM, etc.) - no individual child records.',
            hybrid: 'Shows both individual records AND calculated summaries together.'
        };
        return m[this.currentChildObject.displayMode] || '';
    }

    // Collapsible section toggle icons
    get childColumnsToggleIcon() { return this.showChildColumnsSection ? 'utility:chevrondown' : 'utility:chevronright'; }
    get childAggregatesToggleIcon() { return this.showChildAggregatesSection ? 'utility:chevrondown' : 'utility:chevronright'; }
    get childFiltersToggleIcon() { return this.showChildFiltersSection ? 'utility:chevrondown' : 'utility:chevronright'; }
    get lookupFieldsToggleIcon() { return this.showLookupFieldsSection ? 'utility:chevrondown' : 'utility:chevronright'; }

    // Lookup fields getters
    get hasLookupFields() {
        return this.parentFieldOptions.some(f => f.type === 'REFERENCE');
    }
    get lookupRelationshipOptions() {
        return this.parentFieldOptions
            .filter(f => f.type === 'REFERENCE')
            .map(f => ({ label: f.label, value: f.value }));
    }
    get hasLookupObjectFields() {
        return this.lookupObjectFieldOptions && this.lookupObjectFieldOptions.length > 0;
    }

    get parentColumnDisplay() {
        return this.parentColumns.map((pc, idx) => ({ ...pc, index: idx, key: 'pc-' + idx }));
    }

    get childObjectDisplay() {
        return this.childObjects.map((co, idx) => ({ ...co, index: idx, key: 'co-' + idx }));
    }

    get parentFilterDisplay() {
        return this.parentFilters.map((f, idx) => ({ ...f, index: idx, key: 'pf-' + idx }));
    }

    get visibilityRuleDisplay() {
        return this.visibilityRules.map((r, idx) => ({ ...r, index: idx, key: 'vr-' + idx }));
    }

    get childObjectAggregateDisplay() {
        if (!this.currentChildObject.aggregates) return [];
        return this.currentChildObject.aggregates.map((a, idx) => ({ ...a, index: idx, key: 'ca-' + idx }));
    }

    get childObjectFilterDisplay() {
        if (!this.currentChildObject.filters) return [];
        return this.currentChildObject.filters.map((f, idx) => ({ ...f, index: idx, key: 'cf-' + idx }));
    }

    // ── List View ──
    loadConfigurations() {
        this.isLoading = true;
        getAllReportConfigs()
            .then(result => { this.configurations = result; })
            .catch(error => { this.showToast('Error', this.getErrorMessage(error), 'error'); })
            .finally(() => { this.isLoading = false; });
    }

    loadObjects() {
        getAllObjects()
            .then(result => {
                this.objectOptions = result.map(o => ({ label: o.label + ' (' + o.value + ')', value: o.value }));
            })
            .catch(error => { console.error('Error loading objects:', error); });
    }

    handleNewReport() {
        this.resetForm();
        this.currentView = 'builder';
        this.currentStep = 1;
    }

    handleEditReport(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        getReportConfig({ configId })
            .then(config => {
                this.editingConfigId = config.Id;
                this.reportName = config.Name;
                this.reportDescription = config.Description__c || '';
                this.reportActive = config.Active__c || false;

                if (config.Configuration_JSON__c) {
                    const parsed = JSON.parse(config.Configuration_JSON__c);
                    this.visibilityRules = parsed.visibilityRules || [];

                    // Extract from single multiChild section
                    const sec = parsed.sections && parsed.sections[0] ? parsed.sections[0] : {};
                    this.primaryObject = sec.object || '';
                    this.parentColumns = sec.parentColumns || [];
                    this.childObjects = sec.childObjects || [];
                    this.parentFilters = sec.filters || [];
                    this.sortField = sec.sortField || 'CreatedDate';
                    this.sortOrder = sec.sortOrder || 'DESC';
                    this.recordLimit = sec.recordLimit || 500;

                    if (this.primaryObject) {
                        this.loadPrimaryObjectMeta(this.primaryObject);
                    }
                }

                this.currentView = 'builder';
                this.currentStep = 1;
            })
            .catch(error => { this.showToast('Error', this.getErrorMessage(error), 'error'); })
            .finally(() => { this.isLoading = false; });
    }

    handleDeleteReport(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        deleteReportConfig({ configId })
            .then(() => { this.showToast('Success', 'Report deleted', 'success'); this.loadConfigurations(); })
            .catch(error => { this.showToast('Error', this.getErrorMessage(error), 'error'); })
            .finally(() => { this.isLoading = false; });
    }

    handleCloneReport(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        cloneReportConfig({ configId })
            .then(() => { this.showToast('Success', 'Report cloned', 'success'); this.loadConfigurations(); })
            .catch(error => { this.showToast('Error', this.getErrorMessage(error), 'error'); })
            .finally(() => { this.isLoading = false; });
    }

    handleBackToList() {
        this.resetForm();
        this.currentView = 'list';
        this.loadConfigurations();
    }

    // ── Step Navigation ──
    handleStepClick(event) {
        const step = parseInt(event.currentTarget.dataset.step, 10);
        if (step >= 1 && step <= 5) {
            this.currentStep = step;
        }
    }

    handleNext() {
        // Validate current step
        if (this.currentStep === 1) {
            if (!this.reportName) { this.showToast('Required', 'Please enter a report name', 'error'); return; }
            if (!this.primaryObject) { this.showToast('Required', 'Please select a primary object', 'error'); return; }
        }
        if (this.currentStep === 2 && this.parentColumns.length === 0) {
            this.showToast('Required', 'Please add at least one parent column', 'error'); return;
        }
        if (this.currentStep < 5) this.currentStep++;
    }

    handlePrev() {
        if (this.currentStep > 1) this.currentStep--;
    }

    // ── Step 1: Primary Object ──
    handleReportNameChange(event) { this.reportName = event.target.value; }
    handleReportDescriptionChange(event) { this.reportDescription = event.target.value; }
    handleReportActiveChange(event) { this.reportActive = event.target.checked; }

    handlePrimaryObjectChange(event) {
        const objectName = event.target.value;
        this.primaryObject = objectName;
        this.parentColumns = [];
        this.childObjects = [];
        this.parentFilters = [];
        if (objectName) {
            this.loadPrimaryObjectMeta(objectName);
        }
    }

    loadPrimaryObjectMeta(objectName) {
        getObjectFields({ objectApiName: objectName })
            .then(result => {
                this.parentFieldOptions = result.map(f => ({
                    label: f.label + ' (' + f.value + ')',
                    value: f.value,
                    type: f.type
                }));
            })
            .catch(e => console.error('Error loading fields:', e));

        getChildRelationships({ objectApiName: objectName })
            .then(result => {
                this.childRelationshipOptions = result.map(r => ({
                    label: r.childLabel + ' (' + r.relationshipName + ')',
                    value: r.relationshipName,
                    childObject: r.childObject
                }));
            })
            .catch(e => console.error('Error loading relationships:', e));
    }

    // ── Step 2: Parent Columns ──
    handleAddParentColumn(event) {
        const fieldName = event.target.value;
        if (!fieldName) return;
        if (this.parentColumns.some(c => c.field === fieldName)) { event.target.value = ''; return; }
        const fieldInfo = this.parentFieldOptions.find(f => f.value === fieldName);
        this.parentColumns = [...this.parentColumns, {
            field: fieldName,
            label: fieldInfo ? fieldInfo.label.split(' (')[0] : fieldName
        }];
        event.target.value = '';
    }

    handleParentColumnLabelChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const cols = [...this.parentColumns];
        cols[idx] = { ...cols[idx], label: event.target.value };
        this.parentColumns = cols;
    }

    handleRemoveParentColumn(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.parentColumns = this.parentColumns.filter((_, i) => i !== idx);
    }

    // ── Step 3: Child Objects ──
    handleAddChildObject() {
        this.currentChildObject = {
            objectApiName: '', relationshipName: '', displayLabel: '',
            displayMode: 'horizontal', maxRecords: 3,
            columns: [], aggregates: [], filters: [],
            sortField: '', sortDirection: 'DESC'
        };
        this.currentChildObjectIndex = -1;
        this.childObjectFields = [];
        this.showChildColumnsSection = true;
        this.showChildAggregatesSection = false;
        this.showChildFiltersSection = false;
        this.showChildObjectModal = true;
    }

    handleEditChildObject(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.currentChildObject = JSON.parse(JSON.stringify(this.childObjects[idx]));
        this.currentChildObjectIndex = idx;
        if (this.currentChildObject.objectApiName) {
            this.loadChildObjFields(this.currentChildObject.objectApiName);
        }
        this.showChildColumnsSection = true;
        this.showChildAggregatesSection = (this.currentChildObject.aggregates && this.currentChildObject.aggregates.length > 0);
        this.showChildFiltersSection = (this.currentChildObject.filters && this.currentChildObject.filters.length > 0);
        this.showChildObjectModal = true;
    }

    handleRemoveChildObject(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.childObjects = this.childObjects.filter((_, i) => i !== idx);
    }

    // ── Child Object Modal ──
    handleChildObjectRelChange(event) {
        const relName = event.target.value;
        const rel = this.childRelationshipOptions.find(r => r.value === relName);
        this.currentChildObject = {
            ...this.currentChildObject,
            relationshipName: relName,
            objectApiName: rel ? rel.childObject : '',
            displayLabel: rel ? rel.label.split(' (')[0] : this.currentChildObject.displayLabel,
            columns: [], aggregates: []
        };
        if (rel && rel.childObject) this.loadChildObjFields(rel.childObject);
    }

    handleChildObjDisplayLabelChange(event) { this.currentChildObject = { ...this.currentChildObject, displayLabel: event.target.value }; }
    handleChildObjDisplayModeChange(event) { this.currentChildObject = { ...this.currentChildObject, displayMode: event.target.value }; }
    handleChildObjMaxRecordsChange(event) { this.currentChildObject = { ...this.currentChildObject, maxRecords: parseInt(event.target.value, 10) }; }
    handleChildObjSortFieldChange(event) { this.currentChildObject = { ...this.currentChildObject, sortField: event.target.value }; }
    handleChildObjSortDirChange(event) { this.currentChildObject = { ...this.currentChildObject, sortDirection: event.target.value }; }

    handleAddChildColumn(event) {
        const fieldName = event.target.value;
        if (!fieldName) return;
        const columns = [...(this.currentChildObject.columns || [])];
        if (columns.some(c => c.field === fieldName)) { event.target.value = ''; return; }
        const fi = this.childObjectFields.find(f => f.value === fieldName);
        columns.push({ field: fieldName, label: fi ? fi.label.split(' (')[0] : fieldName });
        this.currentChildObject = { ...this.currentChildObject, columns };
        event.target.value = '';
    }

    handleChildColumnLabelChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const cols = [...this.currentChildObject.columns];
        cols[idx] = { ...cols[idx], label: event.target.value };
        this.currentChildObject = { ...this.currentChildObject, columns: cols };
    }

    handleRemoveChildColumn(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.currentChildObject = { ...this.currentChildObject, columns: this.currentChildObject.columns.filter((_, i) => i !== idx) };
    }

    // Collapsible section toggles
    handleToggleChildColumns() { this.showChildColumnsSection = !this.showChildColumnsSection; }
    handleToggleChildAggregates() { this.showChildAggregatesSection = !this.showChildAggregatesSection; }
    handleToggleChildFilters() { this.showChildFiltersSection = !this.showChildFiltersSection; }
    handleToggleLookupFields() { this.showLookupFieldsSection = !this.showLookupFieldsSection; }

    // Lookup / Parent Object Fields handlers
    handleLookupRelationshipChange(event) {
        const lookupField = event.target.value;
        this.selectedLookupField = lookupField;
        this.lookupObjectFieldOptions = [];
        if (!lookupField || !this.primaryObject) return;

        getLookupObjectFields({ objectApiName: this.primaryObject, lookupFieldApiName: lookupField })
            .then(result => {
                this.lookupObjectFieldOptions = result.map(f => ({
                    label: f.label,
                    value: f.value,
                    type: f.type
                }));
            })
            .catch(e => console.error('Error loading lookup fields:', e));
    }

    handleAddLookupField(event) {
        const fieldPath = event.target.value;
        if (!fieldPath) return;
        if (this.parentColumns.some(c => c.field === fieldPath)) { event.target.value = ''; return; }
        const fi = this.lookupObjectFieldOptions.find(f => f.value === fieldPath);
        const label = fi ? fi.label.split(' (')[0] : fieldPath.replace('__r.', ' ').replace('.', ' ');
        this.parentColumns = [...this.parentColumns, { field: fieldPath, label }];
        event.target.value = '';
    }

    // Child Aggregates
    handleAddChildAggregate() {
        this.currentChildAggregate = { label: '', aggregation: 'COUNT', field: 'Id', filterGroup: '' };
        this.currentChildAggregateIndex = -1;
        this.showChildAggregateModal = true;
    }
    handleEditChildAggregate(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.currentChildAggregate = JSON.parse(JSON.stringify(this.currentChildObject.aggregates[idx]));
        this.currentChildAggregateIndex = idx;
        this.showChildAggregateModal = true;
    }
    handleRemoveChildAggregate(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.currentChildObject = { ...this.currentChildObject, aggregates: this.currentChildObject.aggregates.filter((_, i) => i !== idx) };
    }
    handleChildAggLabelChange(event) { this.currentChildAggregate = { ...this.currentChildAggregate, label: event.target.value }; }
    handleChildAggAggregationChange(event) { this.currentChildAggregate = { ...this.currentChildAggregate, aggregation: event.target.value }; }
    handleChildAggFieldChange(event) { this.currentChildAggregate = { ...this.currentChildAggregate, field: event.target.value }; }
    handleChildAggFilterGroupChange(event) { this.currentChildAggregate = { ...this.currentChildAggregate, filterGroup: event.target.value }; }

    handleSaveChildAggregate() {
        if (!this.currentChildAggregate.label || !this.currentChildAggregate.field) {
            this.showToast('Error', 'Label and Field are required', 'error'); return;
        }
        const aggs = [...(this.currentChildObject.aggregates || [])];
        if (this.currentChildAggregateIndex >= 0) aggs[this.currentChildAggregateIndex] = this.currentChildAggregate;
        else aggs.push(this.currentChildAggregate);
        this.currentChildObject = { ...this.currentChildObject, aggregates: aggs };
        this.showChildAggregateModal = false;
    }
    handleCancelChildAggregate() { this.showChildAggregateModal = false; }

    // Child Filters
    handleAddChildFilter() {
        this.currentChildFilter = { id: 'cf-' + Date.now(), field: '', operator: 'equals', value: '' };
        this.currentChildFilterIndex = -1;
        this.showChildFilterModal = true;
    }
    handleEditChildFilter(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.currentChildFilter = JSON.parse(JSON.stringify(this.currentChildObject.filters[idx]));
        this.currentChildFilterIndex = idx;
        this.showChildFilterModal = true;
    }
    handleRemoveChildFilter(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.currentChildObject = { ...this.currentChildObject, filters: this.currentChildObject.filters.filter((_, i) => i !== idx) };
    }
    handleChildFilterFieldChange(event) { this.currentChildFilter = { ...this.currentChildFilter, field: event.target.value }; }
    handleChildFilterOperatorChange(event) { this.currentChildFilter = { ...this.currentChildFilter, operator: event.target.value }; }
    handleChildFilterValueChange(event) { this.currentChildFilter = { ...this.currentChildFilter, value: event.target.value }; }

    handleSaveChildFilter() {
        if (!this.currentChildFilter.field || !this.currentChildFilter.value) {
            this.showToast('Error', 'Field and Value are required', 'error'); return;
        }
        const filters = [...(this.currentChildObject.filters || [])];
        if (this.currentChildFilterIndex >= 0) filters[this.currentChildFilterIndex] = this.currentChildFilter;
        else filters.push(this.currentChildFilter);
        this.currentChildObject = { ...this.currentChildObject, filters };
        this.showChildFilterModal = false;
    }
    handleCancelChildFilter() { this.showChildFilterModal = false; }

    handleSaveChildObject() {
        if (!this.currentChildObject.relationshipName) { this.showToast('Error', 'Select a child relationship', 'error'); return; }
        if (!this.currentChildObject.displayLabel) { this.showToast('Error', 'Enter a display label', 'error'); return; }
        const mode = this.currentChildObject.displayMode;
        if ((mode === 'horizontal' || mode === 'hybrid') && (!this.currentChildObject.columns || this.currentChildObject.columns.length === 0)) {
            this.showToast('Error', 'Add at least one column for Horizontal/Hybrid mode', 'error'); return;
        }
        if ((mode === 'aggregateOnly' || mode === 'hybrid') && (!this.currentChildObject.aggregates || this.currentChildObject.aggregates.length === 0)) {
            this.showToast('Error', 'Add at least one aggregate for Aggregate/Hybrid mode', 'error'); return;
        }

        const objs = [...this.childObjects];
        if (this.currentChildObjectIndex >= 0) objs[this.currentChildObjectIndex] = this.currentChildObject;
        else objs.push(this.currentChildObject);
        this.childObjects = objs;
        this.showChildObjectModal = false;
    }
    handleCancelChildObject() { this.showChildObjectModal = false; }

    loadChildObjFields(objectName) {
        getObjectFields({ objectApiName: objectName })
            .then(result => {
                this.childObjectFields = result.map(f => ({ label: f.label + ' (' + f.value + ')', value: f.value, type: f.type }));
            })
            .catch(e => console.error('Error loading child fields:', e));
    }

    // ── Step 4: Parent Filters & Sort ──
    handleSortFieldChange(event) { this.sortField = event.target.value; }
    handleSortOrderChange(event) { this.sortOrder = event.target.value; }
    handleRecordLimitChange(event) { this.recordLimit = parseInt(event.target.value, 10); }

    handleAddParentFilter() {
        this.currentParentFilter = { id: 'pf-' + Date.now(), field: '', operator: 'equals', value: '' };
        this.currentParentFilterIndex = -1;
        this.showParentFilterModal = true;
    }
    handleEditParentFilter(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.currentParentFilter = JSON.parse(JSON.stringify(this.parentFilters[idx]));
        this.currentParentFilterIndex = idx;
        this.showParentFilterModal = true;
    }
    handleRemoveParentFilter(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.parentFilters = this.parentFilters.filter((_, i) => i !== idx);
    }
    handleParentFilterFieldChange(event) { this.currentParentFilter = { ...this.currentParentFilter, field: event.target.value }; }
    handleParentFilterOperatorChange(event) { this.currentParentFilter = { ...this.currentParentFilter, operator: event.target.value }; }
    handleParentFilterValueChange(event) { this.currentParentFilter = { ...this.currentParentFilter, value: event.target.value }; }

    handleSaveParentFilter() {
        if (!this.currentParentFilter.field || !this.currentParentFilter.value) {
            this.showToast('Error', 'Field and Value are required', 'error'); return;
        }
        const filters = [...this.parentFilters];
        if (this.currentParentFilterIndex >= 0) filters[this.currentParentFilterIndex] = this.currentParentFilter;
        else filters.push(this.currentParentFilter);
        this.parentFilters = filters;
        this.showParentFilterModal = false;
    }
    handleCancelParentFilter() { this.showParentFilterModal = false; }

    // ── Step 5: Visibility ──
    handleAddVisibilityRule() {
        this.currentVisibilityRule = { id: 'vis-' + Date.now(), ruleType: 'Profile', operator: 'equals', value: '' };
        this.currentVisibilityRuleIndex = -1;
        this.showVisibilityModal = true;
    }
    handleEditVisibilityRule(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.currentVisibilityRule = JSON.parse(JSON.stringify(this.visibilityRules[idx]));
        this.currentVisibilityRuleIndex = idx;
        this.showVisibilityModal = true;
    }
    handleRemoveVisibilityRule(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.visibilityRules = this.visibilityRules.filter((_, i) => i !== idx);
    }
    handleVisibilityRuleTypeChange(event) {
        this.currentVisibilityRule = { ...this.currentVisibilityRule, ruleType: event.target.value, value: '' };
        this.userSearchResults = []; this.userSearchTerm = '';
    }
    handleVisibilityOperatorChange(event) { this.currentVisibilityRule = { ...this.currentVisibilityRule, operator: event.target.value }; }
    handleVisibilityValueChange(event) { this.currentVisibilityRule = { ...this.currentVisibilityRule, value: event.target.value }; }
    handleUserSearchTermChange(event) {
        this.userSearchTerm = event.target.value;
        if (this.userSearchTerm.length >= 2) {
            searchUsers({ searchTerm: this.userSearchTerm })
                .then(result => { this.userSearchResults = result.map(u => ({ label: u.label, value: u.value })); })
                .catch(() => { this.userSearchResults = []; });
        } else { this.userSearchResults = []; }
    }
    handleUserSelect(event) { this.currentVisibilityRule = { ...this.currentVisibilityRule, value: event.target.value }; }

    handleSaveVisibilityRule() {
        if (!this.currentVisibilityRule.value) { this.showToast('Error', 'Value is required', 'error'); return; }
        const rules = [...this.visibilityRules];
        if (this.currentVisibilityRuleIndex >= 0) rules[this.currentVisibilityRuleIndex] = this.currentVisibilityRule;
        else rules.push(this.currentVisibilityRule);
        this.visibilityRules = rules;
        this.showVisibilityModal = false;
    }
    handleCancelVisibilityRule() { this.showVisibilityModal = false; }

    loadProfiles() { getAllProfiles().then(r => { this.profileOptions = r.map(p => ({ label: p.label, value: p.value })); }).catch(() => {}); }
    loadRoles() { getAllRoles().then(r => { this.roleOptions = r.map(p => ({ label: p.label, value: p.value })); }).catch(() => {}); }

    // ── Build config JSON (internally uses multiChild section) ──
    buildConfigJson() {
        return JSON.stringify({
            sections: [{
                id: 'report-main',
                title: this.reportName,
                type: 'multiChild',
                object: this.primaryObject,
                parentColumns: this.parentColumns,
                childObjects: this.childObjects,
                filters: this.parentFilters,
                sortField: this.sortField,
                sortOrder: this.sortOrder,
                recordLimit: this.recordLimit
            }],
            visibilityRules: this.visibilityRules
        });
    }

    // ── Save Report ──
    handleSaveReport() {
        if (!this.reportName) { this.showToast('Error', 'Report name is required', 'error'); return; }
        if (!this.primaryObject) { this.showToast('Error', 'Primary object is required', 'error'); return; }
        if (this.parentColumns.length === 0) { this.showToast('Error', 'Add at least one parent column', 'error'); return; }

        this.isLoading = true;
        saveReportConfig({
            configId: this.editingConfigId,
            configName: this.reportName,
            description: this.reportDescription,
            active: this.reportActive,
            configJson: this.buildConfigJson()
        })
            .then(savedId => { this.editingConfigId = savedId; this.showToast('Success', 'Report saved!', 'success'); })
            .catch(error => { this.showToast('Error', this.getErrorMessage(error), 'error'); })
            .finally(() => { this.isLoading = false; });
    }

    // ── Preview ──
    handlePreviewReport() {
        if (!this.primaryObject || this.parentColumns.length === 0) {
            this.showToast('Error', 'Configure primary object and columns first', 'error'); return;
        }
        this.isLoading = true;
        this.previewError = '';
        this.previewResult = null;

        executeReport({ configJson: this.buildConfigJson(), filtersJson: '[]' })
            .then(result => {
                this.previewResult = {
                    sections: result.sections.map(sec => ({
                        ...sec,
                        hasRows: sec.rows && sec.rows.length > 0,
                        processedRows: sec.rows ? sec.rows.map((row, ri) => ({
                            key: 'row-' + ri,
                            cells: sec.columns.map(col => ({
                                key: col.fieldName,
                                value: row[col.fieldName] !== undefined ? row[col.fieldName] : '',
                                isNumber: col.columnType === 'number'
                            }))
                        })) : []
                    }))
                };
                this.currentView = 'preview';
            })
            .catch(error => { this.previewError = this.getErrorMessage(error); this.showToast('Error', this.previewError, 'error'); })
            .finally(() => { this.isLoading = false; });
    }

    handleBackToBuilder() { this.currentView = 'builder'; }

    // ── Helpers ──
    resetForm() {
        this.editingConfigId = null;
        this.reportName = '';
        this.reportDescription = '';
        this.reportActive = false;
        this.currentStep = 1;
        this.primaryObject = '';
        this.parentColumns = [];
        this.childObjects = [];
        this.parentFilters = [];
        this.sortField = 'CreatedDate';
        this.sortOrder = 'DESC';
        this.recordLimit = 500;
        this.visibilityRules = [];
        this.previewResult = null;
        this.previewError = '';
        this.showLookupFieldsSection = false;
        this.selectedLookupField = '';
        this.lookupObjectFieldOptions = [];
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (Array.isArray(error.body)) return error.body.map(e => e.message).join(', ');
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return 'Unknown error';
    }
}