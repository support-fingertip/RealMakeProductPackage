import { LightningElement, wire, track, api } from 'lwc';
import getUniversalConfig from '@salesforce/apex/RoundRobinConfiguratorController.getUniversalConfig';
import getExistingConfiguration from '@salesforce/apex/RoundRobinConfiguratorController.getExistingConfiguration';
import getLeadFieldPicklistValues from '@salesforce/apex/RoundRobinConfiguratorController.getLeadFieldPicklistValues';
import searchLookup from '@salesforce/apex/RoundRobinConfiguratorController.searchLookup';
import saveFieldPriority from '@salesforce/apex/RoundRobinConfiguratorController.saveFieldPriority';
import saveConfiguration from '@salesforce/apex/RoundRobinConfiguratorController.saveConfiguration';
import checkDuplicateFilters from '@salesforce/apex/RoundRobinConfiguratorController.checkDuplicateFilters';
import getAllConfigurations from '@salesforce/apex/RoundRobinConfiguratorController.getAllConfigurations';
import deleteConfiguration from '@salesforce/apex/RoundRobinConfiguratorController.deleteConfiguration';
import toggleActive from '@salesforce/apex/RoundRobinConfiguratorController.toggleActive';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';

let filterId = 0;

const LIST_COLUMNS = [
    { label: 'Configuration Name', fieldName: 'name', type: 'text', sortable: true },
    {
        label: 'Status', fieldName: 'statusLabel', type: 'text', sortable: true,
        cellAttributes: {
            class: { fieldName: 'statusClass' }
        }
    },
    { label: 'Filters', fieldName: 'filterCount', type: 'number', sortable: true },
    { label: 'Members', fieldName: 'memberCount', type: 'number', sortable: true },
    { label: 'Total Priority', fieldName: 'totalPriority', type: 'number', sortable: true },
    { label: 'Last Modified', fieldName: 'lastModifiedDate', type: 'date', sortable: true,
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Activate/Deactivate', name: 'toggle_active' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

export default class RoundRobinConfigurator extends NavigationMixin(LightningElement) {
    @api recordId;

    // ─── List Mode Properties ────────────────────────────────────
    @track viewMode = 'list';
    @track allConfigs = [];
    @track listSearchTerm = '';
    @track showDeleteModal = false;
    @track deleteTargetId = null;
    @track deleteTargetName = '';
    @track listColumns = LIST_COLUMNS;
    @track sortedBy = 'name';
    @track sortedDirection = 'asc';
    _openedFromRecordPage = false;
    _hasInitialized = false;

    // ─── Form Mode Properties ────────────────────────────────────
    @track bucketData = {};
    @track memberSelections = {};
    @track filters = [];
    @track selectedFieldApiNames = [];

    @track leadFields = [];
    @track assignmentTypes = [];
    @track activeUsers = [];

    // Priority map from universal config
    @track fieldPriorityMap = {};

    isSaving = false;
    isLoading = true;
    isValidating = false;
    @track validationErrors = [];
    @track validationWarnings = [];
    @track showValidation = false;
    _lookupSearchTimeout;
    _prioritySaveTimeout;

    // ─── View Mode Getters ───────────────────────────────────────
    get isListMode() {
        return this.viewMode === 'list';
    }

    get isFormMode() {
        return this.viewMode === 'form';
    }

    get formTitle() {
        return this.bucketData.Id ? 'Edit Configuration' : 'New Configuration';
    }

    get configCount() {
        return this.allConfigs.length;
    }

    get hasConfigs() {
        return this.allConfigs.length > 0;
    }

    get filteredConfigs() {
        if (!this.listSearchTerm) {
            return this.allConfigs;
        }
        const term = this.listSearchTerm.toLowerCase();
        return this.allConfigs.filter(c =>
            c.name && c.name.toLowerCase().includes(term)
        );
    }

    // ─── Form Getters ────────────────────────────────────────────
    get assignmentTabs() {
        return this.assignmentTypes.map(type => ({
            label: type,
            value: type,
            selectedIds: this.memberSelections[type] || []
        }));
    }

    get userOptions() {
        return this.activeUsers.map(u => ({
            label: u.label,
            value: u.value
        }));
    }

    get leadFieldOptions() {
        return this.leadFields.map(f => ({
            label: `${f.label} (${f.apiName})`,
            value: f.apiName
        })).sort((a, b) => a.label.localeCompare(b.label));
    }

    get hasFilters() {
        return this.filters && this.filters.length > 0;
    }

    get sortedFilters() {
        return [...this.filters].sort((a, b) => a.preferenceOrder - b.preferenceOrder);
    }

    get bucketName() {
        return this.bucketData.Name || '';
    }

    get totalPriorityWeight() {
        return this.filters.reduce((sum, f) => sum + (f.fieldPriority || 0), 0);
    }

    // ─── Reset to list when user navigates back to this tab ────────
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (pageRef) {
            if (this._hasInitialized && !this._openedFromRecordPage && this.viewMode === 'form') {
                this.resetFormState();
                this.viewMode = 'list';
                this.loadAllConfigs();
            }
            this._hasInitialized = true;
        }
    }

    // ─── Wire config + load existing data ───────────────────────────
    @wire(getUniversalConfig)
    wiredConfig({ data, error }) {
        if (data) {
            this.leadFields = data.leadFields || [];
            this.assignmentTypes = data.assignmentTypes || [];
            this.activeUsers = data.activeUsers || [];
            this.fieldPriorityMap = data.fieldPriorityMap || {};

            if (this.recordId) {
                this._openedFromRecordPage = true;
                this.viewMode = 'form';
                this.loadExistingData();
            } else {
                this.viewMode = 'list';
                this.loadAllConfigs();
            }
        } else if (error) {
            this.showToast('Error', 'Error loading configuration', 'error');
            this.isLoading = false;
        }
    }

    // ─── List Mode Methods ───────────────────────────────────────
    async loadAllConfigs() {
        try {
            this.isLoading = true;
            const result = await getAllConfigurations();
            this.allConfigs = (result || []).map(c => ({
                ...c,
                statusLabel: c.isActive ? 'Active' : 'Inactive',
                statusClass: c.isActive ? 'slds-text-color_success' : 'slds-text-color_weak'
            }));
        } catch (e) {
            this.showToast('Error', 'Error loading configurations', 'error');
            console.error(e);
        } finally {
            this.isLoading = false;
        }
    }

    handleListSearch(event) {
        this.listSearchTerm = event.target.value;
    }

    handleNewConfig() {
        this.resetFormState();
        this.viewMode = 'form';
    }

    handleRefreshList() {
        this.loadAllConfigs();
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        switch (action.name) {
            case 'edit':
                this.handleEditConfig(row.id);
                break;
            case 'toggle_active':
                this.handleToggleActive(row.id, row.isActive);
                break;
            case 'delete':
                this.deleteTargetId = row.id;
                this.deleteTargetName = row.name;
                this.showDeleteModal = true;
                break;
            default:
                break;
        }
    }

    async handleEditConfig(bucketId) {
        this.resetFormState();
        this.recordId = bucketId;
        this.viewMode = 'form';
        this.isLoading = true;
        await this.loadExistingData();
    }

    async handleToggleActive(bucketId, currentStatus) {
        try {
            await toggleActive({ bucketId: bucketId, isActive: !currentStatus });
            this.showToast('Success', `Configuration ${currentStatus ? 'deactivated' : 'activated'} successfully`, 'success');
            this.loadAllConfigs();
        } catch (e) {
            this.showToast('Error', 'Error toggling active status', 'error');
            console.error(e);
        }
    }

    async confirmDelete() {
        try {
            await deleteConfiguration({ bucketId: this.deleteTargetId });
            this.showToast('Success', 'Configuration deleted successfully', 'success');
            this.showDeleteModal = false;
            this.deleteTargetId = null;
            this.deleteTargetName = '';
            this.loadAllConfigs();
        } catch (e) {
            this.showToast('Error', 'Error deleting configuration', 'error');
            console.error(e);
        }
    }

    cancelDelete() {
        this.showDeleteModal = false;
        this.deleteTargetId = null;
        this.deleteTargetName = '';
    }

    handleBackToList() {
        this.resetFormState();
        this.viewMode = 'list';
        this.loadAllConfigs();
    }

    resetFormState() {
        this.bucketData = {};
        this.memberSelections = {};
        this.filters = [];
        this.selectedFieldApiNames = [];
        this.validationErrors = [];
        this.validationWarnings = [];
        this.showValidation = false;
        this.recordId = null;
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        const data = [...this.allConfigs];
        const key = this.sortedBy;
        const dir = this.sortedDirection === 'asc' ? 1 : -1;
        data.sort((a, b) => {
            let valA = a[key] || '';
            let valB = b[key] || '';
            if (typeof valA === 'string') valA = valA.toLowerCase();
            if (typeof valB === 'string') valB = valB.toLowerCase();
            return valA > valB ? dir : valA < valB ? -dir : 0;
        });
        this.allConfigs = data;
    }

    // ─── Load Existing Data (Form Mode) ──────────────────────────
    async loadExistingData() {
        try {
            const result = await getExistingConfiguration({ bucketId: this.recordId });
            if (result) {
                this.bucketData = {
                    Id: result.bucket.Id,
                    Name: result.bucket.Name,
                    Is_Active__c: result.bucket.Is_Active__c
                };

                // Load filters
                if (result.filters && result.filters.length > 0) {
                    const loadedFilters = [];
                    const selectedApis = [];
                    for (const f of result.filters) {
                        filterId++;
                        const fieldDef = this.leadFields.find(lf => lf.apiName === f.Field_API_Name__c);
                        const isPicklist = f.Field_Type__c === 'PICKLIST' || f.Field_Type__c === 'MULTIPICKLIST';
                        const isRef = f.Field_Type__c === 'REFERENCE';
                        const priority = f.Field_Priority__c || this.fieldPriorityMap[f.Field_API_Name__c] || 0;
                        const filterObj = {
                            id: 'filter-' + filterId,
                            fieldApiName: f.Field_API_Name__c,
                            fieldLabel: f.Field_Label__c || (fieldDef ? fieldDef.label : f.Field_API_Name__c),
                            fieldType: f.Field_Type__c || (fieldDef ? fieldDef.type : 'STRING'),
                            referenceObjectName: fieldDef ? (fieldDef.referenceObjectName || '') : '',
                            value: f.Field_Value__c,
                            preferenceOrder: f.Preference_Order__c,
                            picklistOptions: [],
                            isPicklist: isPicklist,
                            isReference: isRef,
                            isText: !isPicklist && !isRef,
                            fieldPriority: priority,
                            lookupResults: [],
                            lookupSearchTerm: '',
                            selectedLookupName: isRef ? (f.Display_Value__c || f.Field_Value__c || '') : '',
                            showLookupDropdown: false
                        };
                        loadedFilters.push(filterObj);
                        selectedApis.push(f.Field_API_Name__c);

                        if (isPicklist) {
                            this.loadPicklistValues(f.Field_API_Name__c, filterObj.id);
                        }
                    }
                    this.filters = loadedFilters;
                    this.selectedFieldApiNames = selectedApis;
                }

                // Load members
                if (result.members && result.members.length > 0) {
                    const memberMap = {};
                    for (const m of result.members) {
                        if (!memberMap[m.Assignment_Type__c]) {
                            memberMap[m.Assignment_Type__c] = [];
                        }
                        memberMap[m.Assignment_Type__c].push(m.User__c);
                    }
                    this.memberSelections = memberMap;
                }
            }
        } catch (e) {
            this.showToast('Error', 'Error loading existing configuration', 'error');
            console.error(e);
        } finally {
            this.isLoading = false;
        }
    }

    async loadPicklistValues(fieldApiName, fId) {
        try {
            const result = await getLeadFieldPicklistValues({ fieldApiName });
            this.filters = this.filters.map(f => {
                if (f.id === fId) {
                    return {
                        ...f,
                        picklistOptions: result.map(o => ({ label: o.label, value: o.value }))
                    };
                }
                return f;
            });
        } catch (e) {
            console.error('Error loading picklist values', e);
        }
    }

    // ─── Event Handlers ─────────────────────────────────────────────
    handleBucketFieldChange(event) {
        const fieldName = event.target.name;
        if (fieldName === 'Is_Active__c') {
            this.bucketData = { ...this.bucketData, [fieldName]: event.target.checked };
        } else {
            this.bucketData = { ...this.bucketData, [fieldName]: event.target.value };
        }
    }

    handleUserChange(event) {
        const type = event.target.name;
        const selectedIds = event.detail.value;
        this.memberSelections = { ...this.memberSelections, [type]: selectedIds };
    }

    handleFieldSelection(event) {
        const newSelected = event.detail.value;
        const prevSelected = [...this.selectedFieldApiNames];
        this.selectedFieldApiNames = newSelected;

        const added = newSelected.filter(f => !prevSelected.includes(f));
        const removed = prevSelected.filter(f => !newSelected.includes(f));

        for (const apiName of added) {
            const fieldDef = this.leadFields.find(f => f.apiName === apiName);
            if (fieldDef) {
                filterId++;
                const priority = this.fieldPriorityMap[apiName] || 0;
                this.filters = [...this.filters, {
                    id: 'filter-' + filterId,
                    fieldApiName: fieldDef.apiName,
                    fieldLabel: fieldDef.label,
                    fieldType: fieldDef.type,
                    referenceObjectName: fieldDef.referenceObjectName || '',
                    value: '',
                    preferenceOrder: this.filters.length + 1,
                    picklistOptions: [],
                    isPicklist: fieldDef.type === 'PICKLIST' || fieldDef.type === 'MULTIPICKLIST',
                    isReference: fieldDef.type === 'REFERENCE',
                    isText: fieldDef.type !== 'PICKLIST' && fieldDef.type !== 'MULTIPICKLIST' && fieldDef.type !== 'REFERENCE',
                    fieldPriority: priority,
                    lookupResults: [],
                    lookupSearchTerm: '',
                    selectedLookupName: '',
                    showLookupDropdown: false
                }];

                if (fieldDef.type === 'PICKLIST' || fieldDef.type === 'MULTIPICKLIST') {
                    this.loadPicklistValues(fieldDef.apiName, 'filter-' + filterId);
                }
            }
        }

        if (removed.length > 0) {
            this.filters = this.filters.filter(f => !removed.includes(f.fieldApiName));
            this.filters = this.filters.map((f, idx) => ({
                ...f,
                preferenceOrder: idx + 1
            }));
        }
    }

    handleFilterValueChange(event) {
        const fId = event.target.dataset.filterId;
        const val = event.detail ? event.detail.value : event.target.value;
        this.filters = this.filters.map(f =>
            f.id === fId ? { ...f, value: val } : f
        );
    }

    // ─── Priority Change Handler ────────────────────────────────────
    handlePriorityChange(event) {
        const fId = event.target.dataset.filterId;
        const newPriority = parseInt(event.target.value, 10) || 0;

        const filter = this.filters.find(f => f.id === fId);
        if (!filter) return;

        this.filters = this.filters.map(f =>
            f.id === fId ? { ...f, fieldPriority: newPriority } : f
        );

        this.fieldPriorityMap = { ...this.fieldPriorityMap, [filter.fieldApiName]: newPriority };

        if (this._prioritySaveTimeout) {
            clearTimeout(this._prioritySaveTimeout);
        }
        this._prioritySaveTimeout = setTimeout(() => {
            this.savePriorityToUniversalTable(filter.fieldApiName, filter.fieldLabel, newPriority);
        }, 500);
    }

    async savePriorityToUniversalTable(fieldApiName, fieldLabel, priority) {
        try {
            await saveFieldPriority({
                fieldApiName: fieldApiName,
                fieldLabel: fieldLabel,
                priority: priority,
                active: true
            });
        } catch (e) {
            console.error('Error saving field priority', e);
            this.showToast('Warning', 'Priority saved locally but failed to save universally', 'warning');
        }
    }

    // ─── Lookup Search Handlers ─────────────────────────────────────
    handleLookupSearch(event) {
        const fId = event.target.dataset.filterId;
        const searchTerm = event.detail ? event.detail.value : event.target.value;

        this.filters = this.filters.map(f =>
            f.id === fId ? { ...f, lookupSearchTerm: searchTerm, showLookupDropdown: false } : f
        );

        if (this._lookupSearchTimeout) {
            clearTimeout(this._lookupSearchTimeout);
        }

        if (!searchTerm || searchTerm.length < 2) {
            this.filters = this.filters.map(f =>
                f.id === fId ? { ...f, lookupResults: [], showLookupDropdown: false } : f
            );
            return;
        }

        this._lookupSearchTimeout = setTimeout(() => {
            this.performLookupSearch(fId, searchTerm);
        }, 300);
    }

    async performLookupSearch(fId, searchTerm) {
        const filter = this.filters.find(f => f.id === fId);
        if (!filter || !filter.referenceObjectName) return;

        try {
            const results = await searchLookup({
                objectName: filter.referenceObjectName,
                searchText: searchTerm
            });
            this.filters = this.filters.map(f => {
                if (f.id === fId) {
                    return {
                        ...f,
                        lookupResults: results.map(r => ({ ...r })),
                        showLookupDropdown: results.length > 0
                    };
                }
                return f;
            });
        } catch (e) {
            console.error('Lookup search error', e);
        }
    }

    handleLookupSelect(event) {
        const fId = event.currentTarget.dataset.filterId;
        const recordId = event.currentTarget.dataset.recordId;
        const recordName = event.currentTarget.dataset.recordName;

        this.filters = this.filters.map(f => {
            if (f.id === fId) {
                return {
                    ...f,
                    value: recordId,
                    selectedLookupName: recordName,
                    lookupSearchTerm: '',
                    lookupResults: [],
                    showLookupDropdown: false
                };
            }
            return f;
        });
    }

    handleClearLookup(event) {
        const fId = event.target.dataset.filterId || event.currentTarget.dataset.filterId;
        this.filters = this.filters.map(f => {
            if (f.id === fId) {
                return {
                    ...f,
                    value: '',
                    selectedLookupName: '',
                    lookupSearchTerm: '',
                    lookupResults: [],
                    showLookupDropdown: false
                };
            }
            return f;
        });
    }

    handleMoveUp(event) {
        const fId = event.target.dataset.filterId || event.currentTarget.dataset.filterId;
        const sorted = this.sortedFilters;
        const idx = sorted.findIndex(f => f.id === fId);
        if (idx > 0) {
            const prevOrder = sorted[idx - 1].preferenceOrder;
            const currOrder = sorted[idx].preferenceOrder;
            this.filters = this.filters.map(f => {
                if (f.id === sorted[idx].id) return { ...f, preferenceOrder: prevOrder };
                if (f.id === sorted[idx - 1].id) return { ...f, preferenceOrder: currOrder };
                return f;
            });
        }
    }

    handleMoveDown(event) {
        const fId = event.target.dataset.filterId || event.currentTarget.dataset.filterId;
        const sorted = this.sortedFilters;
        const idx = sorted.findIndex(f => f.id === fId);
        if (idx < sorted.length - 1) {
            const nextOrder = sorted[idx + 1].preferenceOrder;
            const currOrder = sorted[idx].preferenceOrder;
            this.filters = this.filters.map(f => {
                if (f.id === sorted[idx].id) return { ...f, preferenceOrder: nextOrder };
                if (f.id === sorted[idx + 1].id) return { ...f, preferenceOrder: currOrder };
                return f;
            });
        }
    }

    handleRemoveFilter(event) {
        const fId = event.target.dataset.filterId || event.currentTarget.dataset.filterId;
        const filterToRemove = this.filters.find(f => f.id === fId);
        if (filterToRemove) {
            this.selectedFieldApiNames = this.selectedFieldApiNames.filter(
                api => api !== filterToRemove.fieldApiName
            );
            this.filters = this.filters.filter(f => f.id !== fId);
            this.filters = this.filters.map((f, idx) => ({
                ...f,
                preferenceOrder: idx + 1
            }));
        }
    }

    // ─── Validate ───────────────────────────────────────────────────
    handleValidate() {
        this.validationErrors = [];
        this.validationWarnings = [];

        if (!this.bucketData.Name) {
            this.validationErrors.push('Configuration Name is required.');
        }
        if (this.filters.length === 0) {
            this.validationErrors.push('At least one filter is required.');
        }
        const emptyFilters = this.filters.filter(f => !f.value || f.value.trim() === '');
        if (emptyFilters.length > 0) {
            this.validationErrors.push(`Set values for: ${emptyFilters.map(f => f.fieldLabel).join(', ')}`);
        }

        const hasAnyMember = Object.values(this.memberSelections).some(
            users => users && users.length > 0
        );
        if (!hasAnyMember) {
            this.validationErrors.push('At least one active member is required.');
        }

        if (this.validationErrors.length === 0) {
            this.validationWarnings.push('All validations passed.');
        }

        this.showValidation = true;
    }

    // ─── Save ───────────────────────────────────────────────────────
    async handleSave() {
        this.handleValidate();
        if (this.validationErrors.length > 0) return;

        this.isSaving = true;

        try {
            const filterRecords = this.sortedFilters.map(f => ({
                sobjectType: 'Round_Robin_Filter__c',
                Field_API_Name__c: f.fieldApiName,
                Field_Label__c: f.fieldLabel,
                Field_Value__c: f.value,
                Display_Value__c: f.isReference ? (f.selectedLookupName || '') : '',
                Field_Type__c: f.fieldType,
                Preference_Order__c: f.preferenceOrder,
                Field_Priority__c: f.fieldPriority || 0
            }));

            const isDuplicate = await checkDuplicateFilters({
                excludeBucketId: this.bucketData.Id || null,
                filters: filterRecords
            });

            if (isDuplicate) {
                this.showToast('Duplicate', 'Another active Round Robin has the same filter combination.', 'error');
                this.isSaving = false;
                return;
            }

            const membersToSave = [];
            Object.keys(this.memberSelections).forEach(type => {
                const userIds = this.memberSelections[type];
                if (userIds && userIds.length > 0) {
                    userIds.forEach(uid => {
                        membersToSave.push({
                            sobjectType: 'Round_Robin_Member__c',
                            User__c: uid,
                            Assignment_Type__c: type,
                            Is_Active__c: true
                        });
                    });
                }
            });

            const bucketObj = { sobjectType: 'Round_Robin__c', ...this.bucketData };
            if (this.recordId) bucketObj.Id = this.recordId;

            await saveConfiguration({
                bucket: bucketObj,
                members: membersToSave,
                filters: filterRecords
            });

            this.showToast('Success', 'Configuration saved successfully', 'success');

            if (this._openedFromRecordPage) {
                this.handleCancel();
            } else {
                this.handleBackToList();
            }
        } catch (error) {
            console.error(error);
            this.showToast('Error', error.body ? error.body.message : error.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        if (this._openedFromRecordPage) {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Round_Robin__c',
                    actionName: 'list'
                }
            });
        } else {
            this.handleBackToList();
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}