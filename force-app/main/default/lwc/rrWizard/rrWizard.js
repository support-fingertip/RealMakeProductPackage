import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getUniversalConfig from '@salesforce/apex/RoundRobinConfiguratorController.getUniversalConfig';
import getLeadFieldPicklistValues from '@salesforce/apex/RoundRobinConfiguratorController.getLeadFieldPicklistValues';
import searchLookup from '@salesforce/apex/RoundRobinConfiguratorController.searchLookup';
import saveConfiguration from '@salesforce/apex/RoundRobinConfiguratorController.saveConfiguration';
import checkDuplicateFilters from '@salesforce/apex/RoundRobinConfiguratorController.checkDuplicateFilters';

let filterId = 0;

export default class RrWizard extends NavigationMixin(LightningElement) {
    @track currentStep = '1';
    @track rrData = { Name: '', Is_Active__c: false };
    @track teamData = {};

    // Dynamic field selection
    @track leadFields = [];
    @track selectedFieldApiNames = [];
    @track filters = [];
    @track assignmentTypes = [];
    @track activeUsers = [];

    // Priority map from universal config
    @track fieldPriorityMap = {};

    isLoading = false;
    configLoaded = false;
    _lookupSearchTimeout;

    // ─── Step getters ───────────────────────────────────────────────
    get isStep1() { return this.currentStep === '1'; }
    get isStep2() { return this.currentStep === '2'; }
    get isStep3() { return this.currentStep === '3'; }
    get isStep4() { return this.currentStep === '4'; }

    get isFirstStep() { return this.currentStep === '1'; }
    get isLastStep() { return this.currentStep === '4'; }
    get nextLabel() { return this.currentStep === '4' ? 'Save & Activate' : 'Next'; }

    get stepNumber() { return parseInt(this.currentStep, 10); }

    get progressStyle() {
        const pct = ((this.stepNumber) / 4) * 100;
        return `width: ${pct}%`;
    }

    // ─── Field Options for multi-select (Step 1) ────────────────────
    get leadFieldOptions() {
        return this.leadFields.map(f => ({
            label: `${f.label} (${f.apiName})`,
            value: f.apiName
        })).sort((a, b) => a.label.localeCompare(b.label));
    }

    // ─── Filter display ─────────────────────────────────────────────
    get hasFilters() {
        return this.filters && this.filters.length > 0;
    }

    get sortedFilters() {
        return [...this.filters].sort((a, b) => a.preferenceOrder - b.preferenceOrder);
    }

    // ─── Team tabs ──────────────────────────────────────────────────
    get assignmentTabs() {
        return this.assignmentTypes.map(type => ({
            label: type,
            value: type,
            selectedUsers: this.teamData[type] || []
        }));
    }

    get userOptions() {
        return this.activeUsers.map(u => ({
            label: u.label,
            value: u.value
        }));
    }

    // ─── Summary getters ────────────────────────────────────────────
    get summaryFilters() {
        return this.sortedFilters.map(f => ({
            ...f,
            displayValue: f.selectedLookupName || f.value || '(not set)',
            priorityDisplay: f.fieldPriority ? String(f.fieldPriority) : '0'
        }));
    }

    get summaryTeams() {
        return Object.keys(this.teamData)
            .filter(role => this.teamData[role] && this.teamData[role].length > 0)
            .map(role => ({
                role,
                count: this.teamData[role].length
            }));
    }

    get hasTeams() {
        return this.summaryTeams.length > 0;
    }

    get totalPriorityWeight() {
        return this.filters.reduce((sum, f) => sum + (f.fieldPriority || 0), 0);
    }

    // ─── Wire config ────────────────────────────────────────────────
    @wire(getUniversalConfig)
    wiredConfig({ data, error }) {
        if (data) {
            this.leadFields = data.leadFields || [];
            this.assignmentTypes = data.assignmentTypes || [];
            this.activeUsers = data.activeUsers || [];
            this.fieldPriorityMap = data.fieldPriorityMap || {};
            this.configLoaded = true;
        } else if (error) {
            this.showToast('Error', 'Error loading configuration', 'error');
        }
    }

    // ─── Step 1: Name + Select Fields ───────────────────────────────
    handleNameChange(event) {
        this.rrData = { ...this.rrData, Name: event.target.value };
    }

    handleActiveChange(event) {
        this.rrData = { ...this.rrData, Is_Active__c: event.target.checked };
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
            console.error('Error loading picklist values for', fieldApiName, e);
        }
    }

    // ─── Step 2: Preference Order + Values ──────────────────────────
    handlePreferenceChange(event) {
        const fId = event.target.dataset.filterId;
        const newOrder = parseInt(event.target.value, 10);
        this.filters = this.filters.map(f =>
            f.id === fId ? { ...f, preferenceOrder: newOrder } : f
        );
    }

    handleFilterValueChange(event) {
        const fId = event.target.dataset.filterId;
        const val = event.detail ? event.detail.value : event.target.value;
        this.filters = this.filters.map(f =>
            f.id === fId ? { ...f, value: val } : f
        );
    }

    // ─── Lookup Search Handlers ─────────────────────────────────────
    handleLookupSearch(event) {
        const fId = event.target.dataset.filterId;
        const searchTerm = event.target.value;

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

    // ─── Step 3: Team Members ───────────────────────────────────────
    handleTeamUpdate(event) {
        const { role, userIds } = event.detail;
        this.teamData = { ...this.teamData, [role]: userIds };
    }

    handleUserChange(event) {
        const type = event.target.name;
        const selectedIds = event.detail.value;
        this.teamData = { ...this.teamData, [type]: selectedIds };
    }

    // ─── Navigation ─────────────────────────────────────────────────
    handleStepClick(event) {
        const targetStep = event.target.value || event.currentTarget.dataset.step;
        const targetNum = parseInt(targetStep, 10);
        const currentNum = parseInt(this.currentStep, 10);

        if (targetNum <= currentNum) {
            this.currentStep = String(targetNum);
            return;
        }

        if (currentNum === 1 && !this.validateStep1()) return;
        if (currentNum === 2 && !this.validateStep2()) return;
        if (targetNum <= currentNum + 1) {
            this.currentStep = String(targetNum);
        }
    }

    goNext() {
        if (this.currentStep === '1') {
            if (!this.validateStep1()) return;
            this.currentStep = '2';
        } else if (this.currentStep === '2') {
            if (!this.validateStep2()) return;
            this.currentStep = '3';
        } else if (this.currentStep === '3') {
            if (!this.validateStep3()) return;
            this.currentStep = '4';
        } else {
            this.handleSave();
        }
    }

    goBack() {
        const stepNum = parseInt(this.currentStep, 10);
        if (stepNum > 1) this.currentStep = String(stepNum - 1);
    }

    // ─── Validations ────────────────────────────────────────────────
    validateStep1() {
        if (!this.rrData.Name || this.rrData.Name.trim() === '') {
            this.showToast('Required', 'Rule Name is required', 'warning');
            return false;
        }
        if (this.selectedFieldApiNames.length === 0) {
            this.showToast('Required', 'Select at least one Lead field for filtering', 'warning');
            return false;
        }
        return true;
    }

    validateStep2() {
        const emptyFilters = this.filters.filter(f => !f.value || f.value.trim() === '');
        if (emptyFilters.length > 0) {
            const names = emptyFilters.map(f => f.fieldLabel).join(', ');
            this.showToast('Required', `Set values for: ${names}`, 'warning');
            return false;
        }
        return true;
    }

    validateStep3() {
        const hasAnyMember = Object.values(this.teamData).some(
            users => users && users.length > 0
        );
        if (!hasAnyMember) {
            this.showToast('Required', 'Add at least one team member', 'warning');
            return false;
        }
        return true;
    }

    // ─── Save ───────────────────────────────────────────────────────
    async handleSave() {
        this.isLoading = true;

        try {
            const filterRecords = this.sortedFilters.map(f => ({
                sobjectType: 'Round_Robin_Filter__c',
                Field_API_Name__c: f.fieldApiName,
                Field_Label__c: f.fieldLabel,
                Field_Value__c: f.value,
                Field_Type__c: f.fieldType,
                Preference_Order__c: f.preferenceOrder,
                Field_Priority__c: f.fieldPriority || 0
            }));

            const isDuplicate = await checkDuplicateFilters({
                excludeBucketId: this.rrData.Id || null,
                filters: filterRecords
            });

            if (isDuplicate) {
                this.showToast('Duplicate Found', 'Another active Round Robin already has the same filter combination.', 'error');
                this.isLoading = false;
                return;
            }

            const membersToSave = [];
            Object.keys(this.teamData).forEach(type => {
                const userIds = this.teamData[type];
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

            const bucketObj = { sobjectType: 'Round_Robin__c', ...this.rrData };

            await saveConfiguration({
                bucket: bucketObj,
                members: membersToSave,
                filters: filterRecords
            });

            this.showToast('Success', 'Round Robin configuration saved successfully!', 'success');
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: 'Round_Robin__c', actionName: 'list' }
            });
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Error saving configuration', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Round_Robin__c', actionName: 'list' }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}