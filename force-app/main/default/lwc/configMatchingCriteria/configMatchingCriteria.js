import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getAllProfiles from '@salesforce/apex/ConfigMatchingService.getAllProfiles';
import getAllRoles from '@salesforce/apex/ConfigMatchingService.getAllRoles';
import searchUsers from '@salesforce/apex/ConfigMatchingService.searchUsers';
import getFieldsForObject from '@salesforce/apex/ConfigMatchingService.getFieldsForObject';
import getPicklistValues from '@salesforce/apex/ConfigMatchingService.getPicklistValues';

export default class ConfigMatchingCriteria extends LightningElement {
    @api label = 'Matching Criteria';
    @api helpText = 'Define conditions to control when this configuration applies. If no conditions are set, this config applies to all records.';

    @track conditions = [];
    @track matchLogic = 'AND';
    @track showConditionModal = false;
    @track currentCondition = {};
    @track currentConditionIndex = -1;

    // Lookup data
    @track profileOptions = [];
    @track roleOptions = [];
    @track userSearchResults = [];
    @track userSearchTerm = '';
    @track objectFields = [];
    @track picklistValues = [];
    @track isLoadingPicklist = false;
    @track isLoadingFields = false;

    _initialized = false;
    _criteriaJson = '';
    _objectApiName = '';
    _profilesLoaded = false;

    // ============ PUBLIC API ============

    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        const newVal = value || '';
        if (newVal !== this._objectApiName) {
            this._objectApiName = newVal;
            if (this._initialized && newVal) {
                this.loadFieldsForObject();
            }
        }
    }

    @api
    get criteriaJson() {
        return this.buildCriteriaJson();
    }

    set criteriaJson(value) {
        this._criteriaJson = value;
        this.parseCriteriaJson(value);
    }

    @api
    validate() {
        return true;
    }

    // ============ LIFECYCLE ============

    connectedCallback() {
        if (!this._initialized) {
            this._initialized = true;
            this.loadLookupData();
        }
    }

    async loadLookupData() {
        try {
            const [profiles, roles] = await Promise.all([
                getAllProfiles(),
                getAllRoles()
            ]);
            this.profileOptions = (profiles || []).map(p => ({ label: p.label, value: p.value }));
            this.roleOptions = (roles || []).map(r => ({ label: r.label, value: r.value }));
            this._profilesLoaded = true;
        } catch (error) {
            console.error('Error loading profiles/roles:', error);
        }

        // Load fields (may already be set or set later via setter)
        if (this._objectApiName) {
            await this.loadFieldsForObject();
        }
    }

    async loadFieldsForObject() {
        if (!this._objectApiName) {
            this.objectFields = [];
            return;
        }
        this.isLoadingFields = true;
        try {
            const fields = await getFieldsForObject({ objectApiName: this._objectApiName });
            this.objectFields = (fields || []).map(f => ({
                label: f.label,
                value: f.value,
                type: f.type
            }));
        } catch (error) {
            console.error('Error loading fields for ' + this._objectApiName + ':', error);
            this.objectFields = [];
        } finally {
            this.isLoadingFields = false;
        }
    }

    // ============ CRITERIA JSON PARSE/BUILD ============

    parseCriteriaJson(jsonStr) {
        if (!jsonStr) {
            this.conditions = [];
            this.matchLogic = 'AND';
            return;
        }
        try {
            const parsed = JSON.parse(jsonStr);
            this.conditions = (parsed.conditions || []).map((c, i) => ({
                ...c,
                _id: 'cond-' + i + '-' + Date.now(),
                _index: i
            }));
            this.matchLogic = parsed.matchLogic || 'AND';
        } catch (e) {
            console.error('Error parsing matching criteria:', e);
            this.conditions = [];
            this.matchLogic = 'AND';
        }
    }

    buildCriteriaJson() {
        if (!this.conditions || this.conditions.length === 0) {
            return '';
        }
        const cleanConditions = this.conditions.map(c => {
            const clean = { type: c.type, operator: c.operator };
            if (c.type === 'field') {
                clean.fieldPath = c.fieldPath;
                clean.value = c.value;
            } else if (c.type === 'profile' || c.type === 'role') {
                clean.values = c.values || [];
            }
            return clean;
        });
        return JSON.stringify({
            conditions: cleanConditions,
            matchLogic: this.matchLogic
        });
    }

    // ============ CONDITION MANAGEMENT ============

    handleAddCondition() {
        // Reload fields if not loaded yet and objectApiName is available
        if (this._objectApiName && (!this.objectFields || this.objectFields.length === 0) && !this.isLoadingFields) {
            this.loadFieldsForObject();
        }
        this.currentCondition = {
            type: 'field',
            operator: 'equals',
            fieldPath: '',
            value: '',
            values: []
        };
        this.currentConditionIndex = -1;
        this.picklistValues = [];
        this.showConditionModal = true;
    }

    handleEditCondition(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.currentCondition = { ...this.conditions[index] };
        this.currentConditionIndex = index;
        // Reload fields if needed
        if (this._objectApiName && (!this.objectFields || this.objectFields.length === 0) && !this.isLoadingFields) {
            this.loadFieldsForObject();
        }
        if (this.currentCondition.type === 'field' && this.currentCondition.fieldPath) {
            this.loadPicklistValuesForField(this.currentCondition.fieldPath);
        }
        this.showConditionModal = true;
    }

    handleRemoveCondition(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.conditions = this.conditions.filter((_, i) => i !== index);
        this.fireChangeEvent();
    }

    handleSaveCondition() {
        if (!this.validateCondition()) return;

        if (this.currentConditionIndex === -1) {
            this.conditions = [...this.conditions, {
                ...this.currentCondition,
                _id: 'cond-' + this.conditions.length + '-' + Date.now(),
                _index: this.conditions.length
            }];
        } else {
            this.conditions = this.conditions.map((c, i) =>
                i === this.currentConditionIndex ? { ...this.currentCondition, _id: c._id, _index: i } : c
            );
        }
        this.showConditionModal = false;
        this.fireChangeEvent();
    }

    handleCancelCondition() {
        this.showConditionModal = false;
    }

    validateCondition() {
        const c = this.currentCondition;
        if (c.type === 'field') {
            if (!c.fieldPath) {
                this.showToast('Error', 'Please select a field', 'error');
                return false;
            }
            if (c.operator !== 'isNull' && c.operator !== 'isNotNull' && !c.value && c.value !== false && c.value !== 0) {
                this.showToast('Error', 'Please enter a value', 'error');
                return false;
            }
        } else if (c.type === 'profile' || c.type === 'role') {
            if (!c.values || c.values.length === 0) {
                this.showToast('Error', `Please select at least one ${c.type}`, 'error');
                return false;
            }
        }
        return true;
    }

    // ============ CONDITION FIELD HANDLERS ============

    handleConditionTypeChange(event) {
        const type = event.detail.value;
        this.currentCondition = {
            type,
            operator: type === 'field' ? 'equals' : 'in',
            fieldPath: '',
            value: '',
            values: []
        };
        this.picklistValues = [];
    }

    handleConditionOperatorChange(event) {
        this.currentCondition = { ...this.currentCondition, operator: event.detail.value };
    }

    handleConditionFieldChange(event) {
        const fieldPath = event.detail.value;
        this.currentCondition = { ...this.currentCondition, fieldPath, value: '' };
        this.loadPicklistValuesForField(fieldPath);
    }

    async loadPicklistValuesForField(fieldApiName) {
        if (!this._objectApiName || !fieldApiName) {
            this.picklistValues = [];
            return;
        }
        const field = this.objectFields.find(f => f.value === fieldApiName);
        if (field && (field.type === 'PICKLIST' || field.type === 'MULTIPICKLIST')) {
            this.isLoadingPicklist = true;
            try {
                const values = await getPicklistValues({
                    objectApiName: this._objectApiName,
                    fieldApiName: fieldApiName
                });
                this.picklistValues = (values || []).map(v => ({ label: v.label, value: v.value }));
            } catch (e) {
                console.error('Error loading picklist values:', e);
                this.picklistValues = [];
            } finally {
                this.isLoadingPicklist = false;
            }
        } else {
            this.picklistValues = [];
        }
    }

    handleConditionValueChange(event) {
        this.currentCondition = { ...this.currentCondition, value: event.detail.value || event.target.value };
    }

    handleProfileRoleSelect(event) {
        const selected = event.detail.value;
        const current = this.currentCondition.values || [];
        if (!current.includes(selected)) {
            this.currentCondition = { ...this.currentCondition, values: [...current, selected] };
        }
    }

    handleRemoveSelectedValue(event) {
        const val = event.currentTarget.dataset.value;
        const values = (this.currentCondition.values || []).filter(v => v !== val);
        this.currentCondition = { ...this.currentCondition, values };
    }

    handleUserSearch(event) {
        this.userSearchTerm = event.target.value;
        if (this.userSearchTerm.length >= 2) {
            searchUsers({ searchTerm: this.userSearchTerm })
                .then(result => {
                    this.userSearchResults = (result || []).map(u => ({ label: u.label, value: u.value }));
                })
                .catch(() => { this.userSearchResults = []; });
        } else {
            this.userSearchResults = [];
        }
    }

    handleMatchLogicChange(event) {
        this.matchLogic = event.detail.value;
        this.fireChangeEvent();
    }

    // ============ EVENT DISPATCH ============

    fireChangeEvent() {
        this.dispatchEvent(new CustomEvent('criteriachange', {
            detail: { criteriaJson: this.buildCriteriaJson() }
        }));
    }

    // ============ COMPUTED PROPERTIES ============

    get hasConditions() {
        return this.conditions && this.conditions.length > 0;
    }

    get hasObjectFields() {
        return this.objectFields && this.objectFields.length > 0;
    }

    get fieldDropdownDisabled() {
        return this.isLoadingFields || !this.hasObjectFields;
    }

    get fieldPlaceholder() {
        if (this.isLoadingFields) return 'Loading fields...';
        if (!this._objectApiName) return 'No object specified';
        if (!this.hasObjectFields) return 'No fields available';
        return 'Select a field...';
    }

    get conditionModalTitle() {
        return this.currentConditionIndex === -1 ? 'Add Condition' : 'Edit Condition';
    }

    get selectValueLabel() {
        return this.isProfileCondition ? 'Select Profiles' : 'Select Roles';
    }

    get selectValuePlaceholder() {
        return this.isProfileCondition ? 'Choose a profile...' : 'Choose a role...';
    }

    get conditionTypeOptions() {
        return [
            { label: 'Object Field', value: 'field' },
            { label: 'User Profile', value: 'profile' },
            { label: 'User Role', value: 'role' }
        ];
    }

    get fieldOperatorOptions() {
        return [
            { label: 'Equals', value: 'equals' },
            { label: 'Not Equals', value: 'notEquals' },
            { label: 'Contains', value: 'contains' },
            { label: 'Starts With', value: 'startsWith' },
            { label: 'Is Null', value: 'isNull' },
            { label: 'Is Not Null', value: 'isNotNull' },
            { label: 'Greater Than', value: 'greaterThan' },
            { label: 'Less Than', value: 'lessThan' }
        ];
    }

    get listOperatorOptions() {
        return [
            { label: 'Is In', value: 'in' },
            { label: 'Is Not In', value: 'notIn' }
        ];
    }

    get matchLogicOptions() {
        return [
            { label: 'All conditions must match (AND)', value: 'AND' },
            { label: 'Any condition can match (OR)', value: 'OR' }
        ];
    }

    get isFieldCondition() {
        return this.currentCondition.type === 'field';
    }

    get isProfileCondition() {
        return this.currentCondition.type === 'profile';
    }

    get isRoleCondition() {
        return this.currentCondition.type === 'role';
    }

    get isProfileOrRoleCondition() {
        return this.currentCondition.type === 'profile' || this.currentCondition.type === 'role';
    }

    get currentOperatorOptions() {
        if (this.isFieldCondition) return this.fieldOperatorOptions;
        return this.listOperatorOptions;
    }

    get currentValueOptions() {
        if (this.isProfileCondition) return this.profileOptions;
        if (this.isRoleCondition) return this.roleOptions;
        return [];
    }

    get hasPicklistValues() {
        return this.picklistValues && this.picklistValues.length > 0;
    }

    get showValueInput() {
        if (!this.isFieldCondition) return false;
        return this.currentCondition.operator !== 'isNull' && this.currentCondition.operator !== 'isNotNull';
    }

    get hasSelectedValues() {
        return this.currentCondition.values && this.currentCondition.values.length > 0;
    }

    get selectedValuePills() {
        return (this.currentCondition.values || []).map(v => ({ label: v, value: v }));
    }

    get conditionDisplay() {
        return this.conditions.map((c, i) => {
            let description = '';
            if (c.type === 'field') {
                const field = this.objectFields.find(f => f.value === c.fieldPath);
                const fieldLabel = field ? field.label : c.fieldPath;
                if (c.operator === 'isNull' || c.operator === 'isNotNull') {
                    description = `${fieldLabel} ${c.operator === 'isNull' ? 'is empty' : 'is not empty'}`;
                } else {
                    description = `${fieldLabel} ${c.operator} "${c.value}"`;
                }
            } else if (c.type === 'profile') {
                description = `Profile ${c.operator === 'notIn' ? 'not in' : 'in'}: ${(c.values || []).join(', ')}`;
            } else if (c.type === 'role') {
                description = `Role ${c.operator === 'notIn' ? 'not in' : 'in'}: ${(c.values || []).join(', ')}`;
            }
            return {
                ...c,
                _index: i,
                description,
                typeBadge: c.type === 'field' ? 'Field' : c.type === 'profile' ? 'Profile' : 'Role',
                typeBadgeClass: `slds-badge ${c.type === 'field' ? 'badge-field' : c.type === 'profile' ? 'badge-profile' : 'badge-role'}`
            };
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}