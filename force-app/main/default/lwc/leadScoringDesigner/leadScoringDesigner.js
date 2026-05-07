import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getLeadFields from '@salesforce/apex/LeadScoringDesignerController.getLeadFields';
import getPicklistValues from '@salesforce/apex/LeadScoringDesignerController.getPicklistValues';
import getRelatedObjects from '@salesforce/apex/LeadScoringDesignerController.getRelatedObjects';
import getRelatedObjectFields from '@salesforce/apex/LeadScoringDesignerController.getRelatedObjectFields';
import getRelatedObjectPicklistValues from '@salesforce/apex/LeadScoringDesignerController.getRelatedObjectPicklistValues';
import getLookupRecords from '@salesforce/apex/LeadScoringDesignerController.getLookupRecords';
import getRules from '@salesforce/apex/LeadScoringDesignerController.getRules';
import saveRules from '@salesforce/apex/LeadScoringDesignerController.saveRules';
import deleteRule from '@salesforce/apex/LeadScoringDesignerController.deleteRule';
import getTiers from '@salesforce/apex/LeadScoringDesignerController.getTiers';
import saveTiers from '@salesforce/apex/LeadScoringDesignerController.saveTiers';
import deleteTier from '@salesforce/apex/LeadScoringDesignerController.deleteTier';

let tempIdCounter = 0;

export default class LeadScoringDesigner extends LightningElement {
    // ═══════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════

    @track leadFields = [];
    @track filteredFields = [];
    @track rules = [];
    @track tiers = [];
    @track relatedObjects = [];
    @track picklistValues = [];
    @track relatedObjectFields = [];
    @track filterPicklistValues = [];

    isLoading = false;
    fieldSearch = '';
    activeTab = 'rules'; // 'rules' or 'tiers'
    @track maxScore = 100; // Configurable max score
    hasUnsavedChanges = false;

    // Rule form state
    showRuleForm = false;
    isEditingRule = false;
    @track ruleForm = {};

    // Tier form state
    showTierForm = false;
    isEditingTier = false;
    @track tierForm = {};

    // ═══════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════

    get isRulesTab() {
        return this.activeTab === 'rules';
    }

    get isTiersTab() {
        return this.activeTab === 'tiers';
    }

    get rulesTabClass() {
        return 'slds-tabs_default__item' + (this.isRulesTab ? ' slds-is-active' : '');
    }

    get tiersTabClass() {
        return 'slds-tabs_default__item' + (this.isTiersTab ? ' slds-is-active' : '');
    }

    get isFieldRule() {
        return this.ruleForm.Rule_Type__c === 'Field';
    }

    get isCountRule() {
        return this.ruleForm.Rule_Type__c === 'Count';
    }

    get hasPicklistValues() {
        return this.picklistValues.length > 0;
    }

    get ruleFormTitle() {
        return this.isEditingRule ? 'Edit Scoring Rule' : 'New Scoring Rule';
    }

    get tierFormTitle() {
        return this.isEditingTier ? 'Edit Tier' : 'New Tier';
    }

    get totalRules() {
        return this.rules.length;
    }

    get activeRuleCount() {
        return this.rules.filter(r => r.Is_Active__c).length;
    }

    get totalConfiguredPoints() {
        return this.rules
            .filter(r => r.Is_Active__c && r.Points__c > 0)
            .reduce((sum, r) => sum + r.Points__c, 0);
    }

    get remainingPoints() {
        return this.maxScore - this.totalConfiguredPoints;
    }

    get isOverBudget() {
        return this.totalConfiguredPoints > this.maxScore;
    }

    get pointsBudgetClass() {
        return this.isOverBudget ? 'slds-text-color_error' : 'slds-text-color_success';
    }

    get tierGaps() {
        if (this.tiers.length === 0) return [];
        const sorted = [...this.tiers].sort((a, b) => a.Min_Score__c - b.Min_Score__c);
        const gaps = [];

        if (sorted[0].Min_Score__c > 0) {
            gaps.push({ key: 'gap-start', from: 0, to: sorted[0].Min_Score__c - 1, label: '0 - ' + (sorted[0].Min_Score__c - 1) });
        }

        for (let i = 0; i < sorted.length - 1; i++) {
            const currentMax = sorted[i].Max_Score__c;
            const nextMin = sorted[i + 1].Min_Score__c;
            if (nextMin > currentMax + 1) {
                gaps.push({ key: 'gap-' + i, from: currentMax + 1, to: nextMin - 1, label: (currentMax + 1) + ' - ' + (nextMin - 1) });
            }
        }

        const lastMax = sorted[sorted.length - 1].Max_Score__c;
        if (lastMax < this.maxScore) {
            gaps.push({ key: 'gap-end', from: lastMax + 1, to: this.maxScore, label: (lastMax + 1) + ' - ' + this.maxScore });
        }

        return gaps;
    }

    get hasGaps() {
        return this.tierGaps.length > 0;
    }

    get operatorOptions() {
        return [
            { label: 'Equals', value: 'equals' },
            { label: 'Not Equals', value: 'not_equals' },
            { label: 'Contains', value: 'contains' },
            { label: 'Greater Than', value: 'greater_than' },
            { label: 'Less Than', value: 'less_than' },
            { label: 'Greater or Equal', value: 'greater_or_equal' },
            { label: 'Less or Equal', value: 'less_or_equal' }
        ];
    }

    get ruleTypeOptions() {
        return [
            { label: 'Field Value', value: 'Field' },
            { label: 'Related Count', value: 'Count' }
        ];
    }

    get categoryOptions() {
        return [
            { label: 'Profile', value: 'Profile' },
            { label: 'Source', value: 'Source' },
            { label: 'Status', value: 'Status' },
            { label: 'Activity', value: 'Activity' },
            { label: 'Engagement', value: 'Engagement' },
            { label: 'Negative', value: 'Negative' }
        ];
    }

    get relatedObjectOptions() {
        return this.relatedObjects.map(ro => ({
            label: ro.objectLabel + ' (' + ro.objectApiName + ')',
            value: ro.objectApiName
        }));
    }

    get fieldOptions() {
        return this.leadFields.map(f => ({
            label: f.label + ' (' + f.apiName + ')',
            value: f.apiName
        }));
    }

    get displayRules() {
        return this.rules.map((r, idx) => ({
            ...r,
            index: idx,
            _key: r.Id || r._tempId,
            statusBadge: r.Is_Active__c ? 'Active' : 'Inactive',
            statusVariant: r.Is_Active__c ? 'success' : 'default',
            pointsDisplay: (r.Points__c >= 0 ? '+' : '') + r.Points__c + ' pts',
            pointsClass: r.Points__c >= 0 ? 'points-positive' : 'points-negative',
            ruleDescription: this.buildRuleDescription(r),
            categoryBadge: r.Category__c || 'Uncategorized',
            toggleIconName: r.Is_Active__c ? 'utility:toggle_on' : 'utility:toggle_off'
        }));
    }

    get displayTiers() {
        return this.tiers.map((t, idx) => ({
            ...t,
            index: idx,
            _key: t.Id || t._tempId,
            rangeDisplay: t.Min_Score__c + ' - ' + t.Max_Score__c,
            badgeStyle: 'background-color: ' + (t.Color__c || '#95a5a6') + '; color: white; padding: 4px 12px; border-radius: 12px; font-weight: bold;'
        }));
    }

    // ═══════════════════════════════════════════
    // LIFECYCLE
    // ═══════════════════════════════════════════

    connectedCallback() {
        this._handleBeforeUnload = (event) => {
            if (this.hasUnsavedChanges) {
                event.preventDefault();
                event.returnValue = '';
            }
        };
        window.addEventListener('beforeunload', this._handleBeforeUnload);
        this.loadAllData();
    }

    disconnectedCallback() {
        if (this._handleBeforeUnload) {
            window.removeEventListener('beforeunload', this._handleBeforeUnload);
        }
    }

    async loadAllData() {
        this.isLoading = true;
        try {
            const [fields, existingRules, existingTiers, related] = await Promise.all([
                getLeadFields(),
                getRules(),
                getTiers(),
                getRelatedObjects()
            ]);

            this.leadFields = fields;
            this.filteredFields = [...fields];
            this.rules = existingRules.map(r => ({ ...r }));
            this.tiers = existingTiers.map(t => ({ ...t }));
            this.relatedObjects = related;
        } catch (error) {
            this.showError('Failed to load data', this.getErrorMessage(error));
        } finally {
            this.isLoading = false;
            this.hasUnsavedChanges = false;
        }
    }

    // ═══════════════════════════════════════════
    // TAB NAVIGATION
    // ═══════════════════════════════════════════

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    // ═══════════════════════════════════════════
    // FIELD SEARCH (Left Panel)
    // ═══════════════════════════════════════════

    handleFieldSearch(event) {
        this.fieldSearch = event.target.value.toLowerCase();
        if (!this.fieldSearch) {
            this.filteredFields = [...this.leadFields];
        } else {
            this.filteredFields = this.leadFields.filter(f =>
                f.label.toLowerCase().includes(this.fieldSearch) ||
                f.apiName.toLowerCase().includes(this.fieldSearch)
            );
        }
    }

    handleFieldClick(event) {
        const apiName = event.currentTarget.dataset.apiname;
        const field = this.leadFields.find(f => f.apiName === apiName);
        if (!field) return;

        this.activeTab = 'rules';
        this.initRuleForm();
        this.ruleForm.Rule_Type__c = 'Field';
        this.ruleForm.Field_API_Name__c = field.apiName;
        this.ruleForm.Field_Label__c = field.label;

        if (field.isPicklist) {
            this.loadPicklistValues(field.apiName);
        } else {
            this.picklistValues = [];
        }

        this.showRuleForm = true;
    }

    async loadPicklistValues(fieldApiName) {
        try {
            const values = await getPicklistValues({ fieldApiName });
            this.picklistValues = values.map(v => ({
                label: v.label,
                value: v.value
            }));
        } catch (error) {
            this.picklistValues = [];
        }
    }

    // ═══════════════════════════════════════════
    // RULE FORM HANDLERS
    // ═══════════════════════════════════════════

    initRuleForm() {
        this.ruleForm = {
            Rule_Type__c: 'Field',
            Field_API_Name__c: '',
            Field_Label__c: '',
            Operator__c: 'equals',
            Field_Value__c: '',
            Points__c: 10,
            Category__c: 'Profile',
            Is_Active__c: true,
            Related_Object__c: '',
            Lookup_Field__c: '',
            Count_Threshold__c: 1,
            Filter_Field__c: '',
            Filter_Value__c: ''
        };
        this.isEditingRule = false;
        this.picklistValues = [];
        this.relatedObjectFields = [];
        this.filterPicklistValues = [];
    }

    handleNewRule() {
        this.initRuleForm();
        this.showRuleForm = true;
    }

    handleEditRule(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const rule = this.rules[idx];
        this.ruleForm = { ...rule };
        this.isEditingRule = true;

        if (rule.Rule_Type__c === 'Field' && rule.Field_API_Name__c) {
            const field = this.leadFields.find(f => f.apiName === rule.Field_API_Name__c);
            if (field && field.isPicklist) {
                this.loadPicklistValues(rule.Field_API_Name__c);
            } else {
                this.picklistValues = [];
            }
        } else {
            this.picklistValues = [];
        }

        // Load related object fields when editing a Count rule
        if (rule.Rule_Type__c === 'Count' && rule.Related_Object__c) {
            this.loadRelatedObjectFields(rule.Related_Object__c).then(() => {
                // After fields load, load filter picklist/lookup values if filter field is set
                if (rule.Filter_Field__c) {
                    const fieldInfo = this.relatedObjectFields.find(f => f.value === rule.Filter_Field__c);
                    if (fieldInfo && fieldInfo.isPicklist) {
                        this.loadFilterPicklistValues(rule.Related_Object__c, rule.Filter_Field__c);
                    } else if (fieldInfo && fieldInfo.isLookup && fieldInfo.referenceTo) {
                        this.loadFilterLookupValues(fieldInfo.referenceTo);
                    }
                }
            });
        } else {
            this.relatedObjectFields = [];
        }

        this.showRuleForm = true;
    }

    handleRuleTypeChange(event) {
        this.ruleForm = { ...this.ruleForm, Rule_Type__c: event.detail.value };
        if (event.detail.value === 'Count') {
            this.picklistValues = [];
        }
    }

    handleRuleFieldChange(event) {
        const field = event.detail.value;
        const fieldInfo = this.leadFields.find(f => f.apiName === field);
        this.ruleForm = {
            ...this.ruleForm,
            Field_API_Name__c: field,
            Field_Label__c: fieldInfo ? fieldInfo.label : field
        };

        if (fieldInfo && fieldInfo.isPicklist) {
            this.loadPicklistValues(field);
        } else {
            this.picklistValues = [];
        }
    }

    handleRuleInputChange(event) {
        const fieldName = event.target.dataset.field;
        let value = event.target.value;

        // Handle checkbox
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        }

        // Handle number
        if (event.target.type === 'number') {
            value = parseFloat(value) || 0;
        }

        this.ruleForm = { ...this.ruleForm, [fieldName]: value };
    }

    handleRelatedObjectChange(event) {
        const objName = event.detail.value;
        const related = this.relatedObjects.find(ro => ro.objectApiName === objName);
        this.ruleForm = {
            ...this.ruleForm,
            Related_Object__c: objName,
            Lookup_Field__c: related ? related.lookupField : '',
            Filter_Field__c: '',
            Filter_Value__c: ''
        };
        this.filterPicklistValues = [];
        if (objName) {
            this.loadRelatedObjectFields(objName);
        } else {
            this.relatedObjectFields = [];
        }
    }

    async loadRelatedObjectFields(objectApiName) {
        try {
            const fields = await getRelatedObjectFields({ objectApiName });
            this.relatedObjectFields = fields.map(f => ({
                label: f.label + ' (' + f.apiName + ')',
                value: f.apiName,
                isPicklist: f.isPicklist,
                isLookup: f.isLookup,
                referenceTo: f.referenceTo
            }));
        } catch (error) {
            this.relatedObjectFields = [];
        }
    }

    handleFilterFieldChange(event) {
        const fieldApiName = event.detail.value;
        this.ruleForm = { ...this.ruleForm, Filter_Field__c: fieldApiName, Filter_Value__c: '' };
        this.filterPicklistValues = [];

        if (fieldApiName) {
            const fieldInfo = this.relatedObjectFields.find(f => f.value === fieldApiName);
            if (fieldInfo && fieldInfo.isPicklist) {
                this.loadFilterPicklistValues(this.ruleForm.Related_Object__c, fieldApiName);
            } else if (fieldInfo && fieldInfo.isLookup && fieldInfo.referenceTo) {
                this.loadFilterLookupValues(fieldInfo.referenceTo);
            }
        }
    }

    async loadFilterPicklistValues(objectApiName, fieldApiName) {
        try {
            const values = await getRelatedObjectPicklistValues({ objectApiName, fieldApiName });
            this.filterPicklistValues = values.map(v => ({
                label: v.label,
                value: v.value
            }));
        } catch (error) {
            this.filterPicklistValues = [];
        }
    }

    async loadFilterLookupValues(referenceTo) {
        try {
            const records = await getLookupRecords({ objectApiName: referenceTo });
            this.filterPicklistValues = records.map(r => ({
                label: r.label,
                value: r.value
            }));
        } catch (error) {
            this.filterPicklistValues = [];
        }
    }

    get filterFieldOptions() {
        return this.relatedObjectFields;
    }

    get hasFilterField() {
        return !!this.ruleForm.Filter_Field__c;
    }

    get hasFilterPicklistValues() {
        return this.filterPicklistValues.length > 0;
    }

    handleCancelRule() {
        this.showRuleForm = false;
        this.picklistValues = [];
    }

    handleMaxScoreChange(event) {
        this.maxScore = parseInt(event.target.value, 10) || 100;
    }

    async handleSaveRule() {
        // Validate required fields
        if (this.isFieldRule && !this.ruleForm.Field_API_Name__c) {
            this.showValidationError('Validation Error', 'Please select a field.');
            return;
        }
        if (this.isCountRule && !this.ruleForm.Related_Object__c) {
            this.showValidationError('Validation Error', 'Please select a related object.');
            return;
        }

        // Duplicate rule detection
        const isDuplicate = this.rules.some(existing => {
            const existingId = existing.Id || existing._tempId;
            const currentId = this.ruleForm.Id || this.ruleForm._tempId;
            if (this.isEditingRule && existingId === currentId) return false;

            if (this.isFieldRule) {
                return existing.Rule_Type__c === 'Field' &&
                       existing.Field_API_Name__c === this.ruleForm.Field_API_Name__c &&
                       existing.Operator__c === this.ruleForm.Operator__c &&
                       existing.Field_Value__c === this.ruleForm.Field_Value__c;
            } else {
                return existing.Rule_Type__c === 'Count' &&
                       existing.Related_Object__c === this.ruleForm.Related_Object__c &&
                       existing.Lookup_Field__c === this.ruleForm.Lookup_Field__c &&
                       existing.Filter_Field__c === this.ruleForm.Filter_Field__c &&
                       existing.Filter_Value__c === this.ruleForm.Filter_Value__c &&
                       existing.Operator__c === this.ruleForm.Operator__c &&
                       String(existing.Count_Threshold__c) === String(this.ruleForm.Count_Threshold__c);
            }
        });

        if (isDuplicate) {
            this.showValidationError('Duplicate Rule',
                this.isFieldRule
                    ? 'A rule already exists for ' + this.ruleForm.Field_API_Name__c + ' with operator "' + this.ruleForm.Operator__c + '" and value "' + this.ruleForm.Field_Value__c + '".'
                    : 'A rule already exists for ' + this.ruleForm.Related_Object__c + ' with the same filter and threshold.'
            );
            return;
        }

        // Points budget check
        const rulePoints = this.ruleForm.Points__c || 0;
        if (rulePoints > 0) {
            let adjustedTotal = this.totalConfiguredPoints;
            if (this.isEditingRule) {
                const oldRule = this.rules.find(r =>
                    (r.Id && r.Id === this.ruleForm.Id) ||
                    (r._tempId && r._tempId === this.ruleForm._tempId)
                );
                if (oldRule && oldRule.Points__c > 0) {
                    adjustedTotal -= oldRule.Points__c;
                }
            }
            if ((adjustedTotal + rulePoints) > this.maxScore) {
                this.showValidationError('Points Budget Exceeded',
                    'Adding ' + rulePoints + ' points would total ' + (adjustedTotal + rulePoints) +
                    ', exceeding the max score of ' + this.maxScore +
                    '. Remaining budget: ' + (this.maxScore - adjustedTotal) + ' points.');
                return;
            }
        }

        if (this.isEditingRule) {
            // Update existing rule in array
            const idx = this.rules.findIndex(r =>
                (r.Id && r.Id === this.ruleForm.Id) ||
                (r._tempId && r._tempId === this.ruleForm._tempId)
            );
            if (idx >= 0) {
                this.rules[idx] = { ...this.ruleForm };
                this.hasUnsavedChanges = true;
            }
        } else {
            // Add new rule with temp ID
            const newRule = { ...this.ruleForm, _tempId: 'temp_' + (++tempIdCounter) };
            this.rules = [...this.rules, newRule];
            this.hasUnsavedChanges = true;
        }

        this.showRuleForm = false;
        this.picklistValues = [];
    }

    async handleDeleteRule(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const rule = this.rules[idx];

        if (rule.Id) {
            this.isLoading = true;
            try {
                await deleteRule({ ruleId: rule.Id });
                this.showSuccess('Rule deleted successfully.');
            } catch (error) {
                this.showError('Delete Failed', this.getErrorMessage(error));
                this.isLoading = false;
                return;
            }
            this.isLoading = false;
        }

        this.rules = this.rules.filter((_, i) => i !== idx);
        this.hasUnsavedChanges = true;
    }

    handleToggleRuleActive(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const rule = this.rules[idx];

        // If activating, check budget
        if (!rule.Is_Active__c && rule.Points__c > 0) {
            if ((this.totalConfiguredPoints + rule.Points__c) > this.maxScore) {
                this.showValidationError('Points Budget Exceeded',
                    'Activating this rule would total ' + (this.totalConfiguredPoints + rule.Points__c) +
                    ' points, exceeding the max score of ' + this.maxScore + '.');
                return;
            }
        }

        const updated = [...this.rules];
        updated[idx] = { ...updated[idx], Is_Active__c: !updated[idx].Is_Active__c };
        this.rules = updated;
        this.hasUnsavedChanges = true;
    }

    // ═══════════════════════════════════════════
    // TIER FORM HANDLERS
    // ═══════════════════════════════════════════

    initTierForm() {
        this.tierForm = {
            Name: '',
            Min_Score__c: 0,
            Max_Score__c: 100,
            Color__c: '#3498db',
            Sequence__c: this.tiers.length + 1
        };
        this.isEditingTier = false;
    }

    handleNewTier() {
        this.initTierForm();
        this.showTierForm = true;
    }

    handleEditTier(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.tierForm = { ...this.tiers[idx] };
        this.isEditingTier = true;
        this.showTierForm = true;
    }

    handleTierInputChange(event) {
        const fieldName = event.target.dataset.field;
        let value = event.target.value;

        if (event.target.type === 'number') {
            value = parseFloat(value) || 0;
        }

        this.tierForm = { ...this.tierForm, [fieldName]: value };
    }

    handleCancelTier() {
        this.showTierForm = false;
    }

    handleSaveTier() {
        if (!this.tierForm.Name) {
            this.showValidationError('Validation Error', 'Please enter a tier name.');
            return;
        }

        // Mandatory Min/Max validation
        if (this.tierForm.Min_Score__c === null || this.tierForm.Min_Score__c === undefined ||
            this.tierForm.Max_Score__c === null || this.tierForm.Max_Score__c === undefined) {
            this.showValidationError('Validation Error', 'Min Score and Max Score are required.');
            return;
        }

        // Min < Max validation
        if (this.tierForm.Min_Score__c >= this.tierForm.Max_Score__c) {
            this.showValidationError('Validation Error', 'Min Score must be less than Max Score.');
            return;
        }

        // Tier cannot exceed max score
        if (this.tierForm.Max_Score__c > this.maxScore) {
            this.showValidationError('Validation Error',
                'Max Score (' + this.tierForm.Max_Score__c + ') cannot exceed the configured max score of ' + this.maxScore + '.');
            return;
        }

        // Overlap validation
        const newMin = this.tierForm.Min_Score__c;
        const newMax = this.tierForm.Max_Score__c;
        const currentId = this.tierForm.Id || this.tierForm._tempId;

        for (const tier of this.tiers) {
            const tierId = tier.Id || tier._tempId;
            // Skip the tier being edited
            if (this.isEditingTier && tierId === currentId) continue;

            if (newMin < tier.Max_Score__c && newMax > tier.Min_Score__c) {
                this.showValidationError('Validation Error',
                    `Range ${newMin}-${newMax} overlaps with tier "${tier.Name}" (${tier.Min_Score__c}-${tier.Max_Score__c}). Please adjust the ranges.`);
                return;
            }
        }

        if (this.isEditingTier) {
            const idx = this.tiers.findIndex(t =>
                (t.Id && t.Id === this.tierForm.Id) ||
                (t._tempId && t._tempId === this.tierForm._tempId)
            );
            if (idx >= 0) {
                this.tiers[idx] = { ...this.tierForm };
                this.hasUnsavedChanges = true;
            }
        } else {
            const newTier = { ...this.tierForm, _tempId: 'temp_' + (++tempIdCounter) };
            this.tiers = [...this.tiers, newTier];
            this.hasUnsavedChanges = true;
        }

        this.showTierForm = false;
    }

    async handleDeleteTier(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const tier = this.tiers[idx];

        if (tier.Id) {
            this.isLoading = true;
            try {
                await deleteTier({ tierId: tier.Id });
                this.showSuccess('Tier deleted successfully.');
            } catch (error) {
                this.showError('Delete Failed', this.getErrorMessage(error));
                this.isLoading = false;
                return;
            }
            this.isLoading = false;
        }

        this.tiers = this.tiers.filter((_, i) => i !== idx);
        this.hasUnsavedChanges = true;
    }

    // ═══════════════════════════════════════════
    // SAVE ALL
    // ═══════════════════════════════════════════

    async handleSaveAll() {
        this.isLoading = true;
        try {
            // Clean rules for serialization (remove temp IDs and _key)
            const cleanRules = this.rules.map(r => {
                const clean = { ...r };
                delete clean._tempId;
                delete clean._key;
                if (!clean.Id) delete clean.Id;
                return clean;
            });

            const cleanTiers = this.tiers.map(t => {
                const clean = { ...t };
                delete clean._tempId;
                delete clean._key;
                if (!clean.Id) delete clean.Id;
                return clean;
            });

            const [savedRules, savedTiers] = await Promise.all([
                cleanRules.length > 0 ? saveRules({ rulesJSON: JSON.stringify(cleanRules) }) : Promise.resolve([]),
                cleanTiers.length > 0 ? saveTiers({ tiersJSON: JSON.stringify(cleanTiers) }) : Promise.resolve([])
            ]);

            this.rules = savedRules.map(r => ({ ...r }));
            this.tiers = savedTiers.map(t => ({ ...t }));

            this.showSuccess('All scoring rules and tiers saved successfully!');
            this.hasUnsavedChanges = false;
        } catch (error) {
            this.showError('Save Failed', this.getErrorMessage(error));
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════

    buildRuleDescription(rule) {
        if (rule.Rule_Type__c === 'Count') {
            const opLabel = this.getOperatorLabel(rule.Operator__c);
            let desc = rule.Related_Object__c + ' count ' + opLabel + ' ' + (rule.Count_Threshold__c || 1);
            if (rule.Filter_Field__c && rule.Filter_Value__c) {
                desc += ' (where ' + rule.Filter_Field__c + ' = "' + rule.Filter_Value__c + '")';
            }
            return desc;
        }
        const opLabel = this.getOperatorLabel(rule.Operator__c);
        return (rule.Field_Label__c || rule.Field_API_Name__c) + ' ' + opLabel + ' "' + (rule.Field_Value__c || '') + '"';
    }

    getOperatorLabel(op) {
        const map = {
            'equals': '=',
            'not_equals': '!=',
            'contains': 'contains',
            'greater_than': '>',
            'less_than': '<',
            'greater_or_equal': '>=',
            'less_or_equal': '<='
        };
        return map[op] || op;
    }

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message,
            variant: 'success'
        }));
    }

    showError(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant: 'error',
            mode: 'sticky'
        }));
    }

    showValidationError(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant: 'error',
            mode: 'dismissible'
        }));
    }

    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}