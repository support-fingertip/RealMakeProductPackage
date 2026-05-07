import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAllObjects from '@salesforce/apex/DynamicFormConfigController.getAllObjects';
import getObjectFields from '@salesforce/apex/DynamicFormConfigController.getObjectFields';
import getChildRelationships from '@salesforce/apex/DynamicFormConfigController.getChildRelationships';
import getAllProfiles from '@salesforce/apex/DynamicFormConfigController.getAllProfiles';
import getAllRoles from '@salesforce/apex/DynamicFormConfigController.getAllRoles';
import searchUsers from '@salesforce/apex/DynamicFormConfigController.searchUsers';
import saveConfiguration from '@salesforce/apex/DynamicFormConfigController.saveConfiguration';
import getConfiguration from '@salesforce/apex/DynamicFormConfigController.getConfiguration';
import getAllConfigurations from '@salesforce/apex/DynamicFormConfigController.getAllConfigurations';
import deleteConfiguration from '@salesforce/apex/DynamicFormConfigController.deleteConfiguration';
import cloneConfiguration from '@salesforce/apex/DynamicFormConfigController.cloneConfiguration';
import getDocumentCategoriesForObject from '@salesforce/apex/DynamicFormConfigController.getDocumentCategoriesForObject';

export default class FormConfiguratorBuilder extends LightningElement {
    // View state
    @track currentView = 'list'; // 'list' or 'builder'
    @track configurations = [];
    @track editingConfigId = null;

    // Form fields
    @track formName = '';
    @track selectedObject = '';
    @track contextObject = '';
    @track buttonLabel = '';
    @track description = '';
    @track isActive = true;
    @track saveFormNameToField = '';
    @track contextLookupField = '';

    // Object & field data
    @track objectOptions = [];
    @track availableFields = [];
    @track contextFields = [];

    // Sections
    @track sections = [];

    // Conditions
    @track conditions = [];
    @track newCondField = '';
    @track newCondOperator = 'equals';
    @track newCondValue = '';

    // Child configs
    @track childConfigs = [];
    @track childRelationships = [];
    @track selectedChildRelationship = '';

    // Visibility rules
    @track visibilityRules = [];
    @track showRuleModal = false;
    @track currentRule = {};

    @track profileOptions = [];
    @track roleOptions = [];
    @track userOptions = [];

    // Document Upload config
    @track enableDocumentUpload = false;
    @track documentCategories = [];

    @track isLoading = false;

    ruleTypes = [
        { label: 'Profile', value: 'Profile' },
        { label: 'Role', value: 'Role' },
        { label: 'User', value: 'User' }
    ];

    operatorOptions = [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Contains', value: 'contains' },
        { label: 'Not Contains', value: 'notContains' }
    ];

    conditionOperatorOptions = [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Contains', value: 'contains' },
        { label: 'Not Contains', value: 'notContains' }
    ];

    fieldConditionOperators = [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Contains', value: 'contains' },
        { label: 'Not Contains', value: 'notContains' }
    ];

    columnOptions = [
        { label: '1 Column', value: '1' },
        { label: '2 Columns', value: '2' }
    ];

    connectedCallback() {
        this.loadObjects();
        this.loadProfiles();
        this.loadRoles();
        this.loadConfigurations();
    }

    @api
    refresh() {
        this.loadConfigurations();
    }

    // ── Data Loading ──

    loadObjects() {
        getAllObjects()
            .then(result => {
                this.objectOptions = result.map(obj => ({
                    label: `${obj.label} (${obj.value})`,
                    value: obj.value
                }));
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load objects', 'error');
                console.error(error);
            });
    }

    loadProfiles() {
        getAllProfiles()
            .then(result => {
                this.profileOptions = result.map(p => ({ label: p.label, value: p.label }));
            })
            .catch(error => console.error('Error loading profiles:', error));
    }

    loadRoles() {
        getAllRoles()
            .then(result => {
                this.roleOptions = result.map(r => ({ label: r.label, value: r.label }));
            })
            .catch(error => console.error('Error loading roles:', error));
    }

    loadConfigurations() {
        this.isLoading = true;
        getAllConfigurations()
            .then(result => {
                this.configurations = result;
                this.isLoading = false;
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load configurations', 'error');
                this.isLoading = false;
                console.error(error);
            });
    }

    loadFieldsForObject(objectApiName) {
        if (!objectApiName) return Promise.resolve([]);
        return getObjectFields({ objectApiName })
            .then(result => result.map(field => ({
                label: field.label,
                value: field.value,
                type: field.type,
                isSystemRequired: field.isSystemRequired
            })));
    }

    loadChildRelationships() {
        if (!this.selectedObject) return;
        getChildRelationships({ objectApiName: this.selectedObject })
            .then(result => {
                this.childRelationships = result;
            })
            .catch(error => console.error('Error loading child relationships:', error));
    }

    loadContextFields() {
        if (!this.contextObject) {
            this.contextFields = [];
            return;
        }
        this.loadFieldsForObject(this.contextObject)
            .then(fields => { this.contextFields = fields; })
            .catch(error => console.error('Error loading context fields:', error));
    }

    // ── View Management ──

    get isListView() { return this.currentView === 'list'; }
    get isBuilderView() { return this.currentView === 'builder'; }
    get hasConfigurations() { return this.configurations.length > 0; }
    get builderTitle() { return this.editingConfigId ? 'Edit Configuration' : 'New Configuration'; }

    handleNewConfig() {
        this.resetForm();
        this.currentView = 'builder';
    }

    handleBackToList() {
        this.resetForm();
        this.currentView = 'list';
        this.loadConfigurations();
    }

    handleEditConfig(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        getConfiguration({ configId })
            .then(config => {
                this.editingConfigId = config.Id;
                this.formName = config.Name;
                this.selectedObject = config.Object_API_Name__c || '';
                this.contextObject = config.Context_Object__c || '';
                this.buttonLabel = config.Button_Label__c || '';
                this.description = config.Description__c || '';
                this.isActive = config.Active__c;

                // Parse JSON config
                if (config.Configuration_JSON__c) {
                    const json = JSON.parse(config.Configuration_JSON__c);
                    this.saveFormNameToField = json.saveFormNameToField || '';
                    this.contextLookupField = json.contextLookupField || '';

                    // Load visibility rules
                    this.visibilityRules = (json.visibilityRules || []).map((r, i) => ({
                        ...r, key: `rule-${i}-${Date.now()}`
                    }));

                    // Load conditions
                    this.conditions = (json.conditions || []).map((c, i) => ({
                        ...c, key: `cond-${i}-${Date.now()}`,
                        fieldLabel: c.fieldLabel || c.field
                    }));

                    // Load sections
                    this.sections = (json.sections || []).map((s, i) => ({
                        id: `section-${i}-${Date.now()}`,
                        label: s.label,
                        columns: s.columns || '2',
                        order: s.order || (i + 1),
                        fields: (s.fields || []).map((f, j) => ({
                            id: `field-${i}-${j}-${Date.now()}`,
                            apiName: f.apiName,
                            label: f.label,
                            isRequired: f.isRequired || false,
                            defaultValue: f.defaultValue || '',
                            order: f.order || (j + 1),
                            showCondition: f.showCondition ? { ...f.showCondition } : null
                        })),
                        get hasFields() { return this.fields.length > 0; }
                    }));

                    // Load child configs
                    this.childConfigs = (json.childConfigs || []).map((cc, i) => ({
                        id: `child-${i}-${Date.now()}`,
                        childObject: cc.childObject,
                        relationshipField: cc.relationshipField,
                        sectionLabel: cc.sectionLabel || cc.childObject,
                        fields: (cc.fields || []).map((f, j) => ({
                            id: `cfield-${i}-${j}-${Date.now()}`,
                            apiName: f.apiName,
                            label: f.label,
                            isRequired: f.isRequired || false,
                            order: f.order || (j + 1)
                        })),
                        availableFields: [],
                        get hasFields() { return this.fields.length > 0; }
                    }));
                }

                // Load dependent data
                const promises = [];
                if (this.selectedObject) {
                    promises.push(
                        this.loadFieldsForObject(this.selectedObject).then(fields => {
                            this.availableFields = fields;
                        })
                    );
                    this.loadChildRelationships();
                }
                if (this.contextObject) {
                    promises.push(
                        this.loadFieldsForObject(this.contextObject).then(fields => {
                            this.contextFields = fields;
                        })
                    );
                }

                // Load child object fields
                this.childConfigs.forEach(cc => {
                    promises.push(
                        this.loadFieldsForObject(cc.childObject).then(fields => {
                            cc.availableFields = fields.map(f => ({
                                label: `${f.label} (${f.value})`,
                                value: f.value,
                                fieldLabel: f.label
                            }));
                        })
                    );
                });

                // Load document upload config if present
                if (this.selectedObject) {
                    promises.push(
                        this.loadDocumentCategories().then(() => {
                            if (config.Configuration_JSON__c) {
                                const json = JSON.parse(config.Configuration_JSON__c);
                                this._restoreDocUploadConfig(json.documentUploadConfig);
                            }
                        })
                    );
                }

                return Promise.all(promises);
            })
            .then(() => {
                this.currentView = 'builder';
                this.isLoading = false;
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load configuration', 'error');
                this.isLoading = false;
                console.error(error);
            });
    }

    handleDeleteConfig(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        deleteConfiguration({ configId })
            .then(() => {
                this.showToast('Success', 'Configuration deleted', 'success');
                this.loadConfigurations();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to delete configuration', 'error');
                this.isLoading = false;
                console.error(error);
            });
    }

    handleCloneConfig(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        cloneConfiguration({ configId })
            .then(() => {
                this.showToast('Success', 'Configuration cloned', 'success');
                this.loadConfigurations();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to clone configuration', 'error');
                this.isLoading = false;
                console.error(error);
            });
    }

    // ── Basic Info Handlers ──

    handleFormNameChange(event) { this.formName = event.target.value; }
    handleButtonLabelChange(event) { this.buttonLabel = event.target.value; }
    handleDescriptionChange(event) { this.description = event.target.value; }
    handleActiveChange(event) { this.isActive = event.target.checked; }
    handleSaveFieldChange(event) { this.saveFormNameToField = event.target.value; }
    handleContextLookupFieldChange(event) { this.contextLookupField = event.detail.value; }

    get contextLookupFieldOptions() {
        // Show REFERENCE (lookup) fields on the target object that could point to the context object
        const options = [{ label: '-- None --', value: '' }];
        if (this.availableFields && this.availableFields.length > 0) {
            this.availableFields
                .filter(f => f.type === 'REFERENCE')
                .forEach(f => {
                    options.push({ label: `${f.label} (${f.value})`, value: f.value });
                });
        }
        return options;
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.sections = [];
        this.childConfigs = [];
        this.availableFields = [];
        this.documentCategories = [];
        this.enableDocumentUpload = false;

        this.isLoading = true;
        Promise.all([
            this.loadFieldsForObject(this.selectedObject).then(fields => {
                this.availableFields = fields;
            }),
            getChildRelationships({ objectApiName: this.selectedObject }).then(result => {
                this.childRelationships = result;
            })
        ])
        .then(() => { this.isLoading = false; })
        .catch(error => {
            this.isLoading = false;
            console.error(error);
        });
    }

    handleContextObjectChange(event) {
        this.contextObject = event.detail.value;
        this.conditions = [];
        this.loadContextFields();
    }

    // ── Conditions ──

    get hasConditions() { return this.conditions.length > 0; }

    get contextFieldOptions() {
        return this.contextFields.map(f => ({
            label: `${f.label} (${f.value})`,
            value: f.value
        }));
    }

    handleCondFieldChange(event) { this.newCondField = event.detail.value; }
    handleCondOperatorChange(event) { this.newCondOperator = event.detail.value; }
    handleCondValueChange(event) { this.newCondValue = event.target.value; }

    handleAddCondition() {
        if (!this.newCondField || !this.newCondValue) {
            this.showToast('Validation', 'Field and Value are required for conditions', 'warning');
            return;
        }
        const fieldInfo = this.contextFields.find(f => f.value === this.newCondField);
        this.conditions = [...this.conditions, {
            key: `cond-${Date.now()}-${Math.random()}`,
            field: this.newCondField,
            fieldLabel: fieldInfo ? fieldInfo.label : this.newCondField,
            operator: this.newCondOperator,
            value: this.newCondValue
        }];
        this.newCondField = '';
        this.newCondOperator = 'equals';
        this.newCondValue = '';
    }

    handleRemoveCondition(event) {
        const key = event.currentTarget.dataset.key;
        this.conditions = this.conditions.filter(c => c.key !== key);
    }

    // ── Sections ──

    get hasSections() { return this.sections.length > 0; }

    get availableFieldOptions() {
        return this.availableFields.map(f => ({
            label: `${f.label} (${f.value})`,
            value: f.value
        }));
    }

    handleAddSection() {
        const newSection = {
            id: `section-${Date.now()}-${Math.random()}`,
            label: `Section ${this.sections.length + 1}`,
            columns: '2',
            order: this.sections.length + 1,
            fields: [],
            get hasFields() { return this.fields.length > 0; }
        };
        this.sections = [...this.sections, newSection];
    }

    handleSectionLabelChange(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        this.sections = this.sections.map(s =>
            s.id === sectionId ? this._updateSection(s, { label: event.target.value }) : s
        );
    }

    handleSectionColumnsChange(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        this.sections = this.sections.map(s =>
            s.id === sectionId ? this._updateSection(s, { columns: event.detail.value }) : s
        );
    }

    handleRemoveSection(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        this.sections = this.sections.filter(s => s.id !== sectionId)
            .map((s, i) => this._updateSection(s, { order: i + 1 }));
    }

    handleMoveSectionUp(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const idx = this.sections.findIndex(s => s.id === sectionId);
        if (idx > 0) {
            const arr = [...this.sections];
            [arr[idx], arr[idx - 1]] = [arr[idx - 1], arr[idx]];
            this.sections = arr.map((s, i) => this._updateSection(s, { order: i + 1 }));
        }
    }

    handleMoveSectionDown(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const idx = this.sections.findIndex(s => s.id === sectionId);
        if (idx < this.sections.length - 1) {
            const arr = [...this.sections];
            [arr[idx], arr[idx + 1]] = [arr[idx + 1], arr[idx]];
            this.sections = arr.map((s, i) => this._updateSection(s, { order: i + 1 }));
        }
    }

    // ── Section Fields ──

    handleFieldAddToSection(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldApiName = event.detail.value;
        if (!fieldApiName) return;

        const fieldInfo = this.availableFields.find(f => f.value === fieldApiName);
        if (!fieldInfo) return;

        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            if (s.fields.some(f => f.apiName === fieldApiName)) return s;

            const newField = {
                id: `field-${Date.now()}-${Math.random()}`,
                apiName: fieldInfo.value,
                label: fieldInfo.label,
                isRequired: fieldInfo.isSystemRequired || false,
                defaultValue: '',
                order: s.fields.length + 1
            };
            return this._updateSection(s, { fields: [...s.fields, newField] });
        });

        // Reset the combobox
        event.target.value = null;
    }

    handleFieldRequiredChange(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            return this._updateSection(s, {
                fields: s.fields.map(f =>
                    f.id === fieldId ? { ...f, isRequired: event.target.checked } : f
                )
            });
        });
    }

    handleFieldDefaultChange(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            return this._updateSection(s, {
                fields: s.fields.map(f =>
                    f.id === fieldId ? { ...f, defaultValue: event.target.value } : f
                )
            });
        });
    }

    handleFieldMoveUp(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            const idx = s.fields.findIndex(f => f.id === fieldId);
            if (idx > 0) {
                const arr = [...s.fields];
                [arr[idx], arr[idx - 1]] = [arr[idx - 1], arr[idx]];
                return this._updateSection(s, {
                    fields: arr.map((f, i) => ({ ...f, order: i + 1 }))
                });
            }
            return s;
        });
    }

    handleFieldMoveDown(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            const idx = s.fields.findIndex(f => f.id === fieldId);
            if (idx < s.fields.length - 1) {
                const arr = [...s.fields];
                [arr[idx], arr[idx + 1]] = [arr[idx + 1], arr[idx]];
                return this._updateSection(s, {
                    fields: arr.map((f, i) => ({ ...f, order: i + 1 }))
                });
            }
            return s;
        });
    }

    handleFieldRemove(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            return this._updateSection(s, {
                fields: s.fields.filter(f => f.id !== fieldId)
                    .map((f, i) => ({ ...f, order: i + 1 }))
            });
        });
    }

    // ── Field-Level Conditions ──

    get allFormFieldOptions() {
        const options = [];
        this.sections.forEach(s => {
            s.fields.forEach(f => {
                options.push({
                    label: `${f.label} (${f.apiName})`,
                    value: f.apiName
                });
            });
        });
        return options;
    }

    handleToggleFieldCondition(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            return this._updateSection(s, {
                fields: s.fields.map(f => {
                    if (f.id !== fieldId) return f;
                    if (f.showCondition) {
                        return { ...f, showCondition: null };
                    }
                    return {
                        ...f,
                        showCondition: { field: '', operator: 'equals', value: '' }
                    };
                })
            });
        });
    }

    handleFieldCondFieldChange(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            return this._updateSection(s, {
                fields: s.fields.map(f => {
                    if (f.id !== fieldId) return f;
                    return {
                        ...f,
                        showCondition: { ...f.showCondition, field: event.detail.value }
                    };
                })
            });
        });
    }

    handleFieldCondOperatorChange(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            return this._updateSection(s, {
                fields: s.fields.map(f => {
                    if (f.id !== fieldId) return f;
                    return {
                        ...f,
                        showCondition: { ...f.showCondition, operator: event.detail.value }
                    };
                })
            });
        });
    }

    handleFieldCondValueChange(event) {
        const sectionId = event.currentTarget.dataset.sectionId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.sections = this.sections.map(s => {
            if (s.id !== sectionId) return s;
            return this._updateSection(s, {
                fields: s.fields.map(f => {
                    if (f.id !== fieldId) return f;
                    return {
                        ...f,
                        showCondition: { ...f.showCondition, value: event.target.value }
                    };
                })
            });
        });
    }

    _updateSection(section, updates) {
        const updated = { ...section, ...updates };
        if (!updates.fields) {
            updated.fields = [...section.fields];
        }
        Object.defineProperty(updated, 'hasFields', {
            get() { return this.fields.length > 0; },
            enumerable: true,
            configurable: true
        });
        return updated;
    }

    // ── Child Configs ──

    get hasChildConfigs() { return this.childConfigs.length > 0; }

    get childRelationshipOptions() {
        return this.childRelationships.map(r => ({
            label: r.label,
            value: `${r.childObjectName}|${r.relationshipFieldName}|${r.relationshipName}`
        }));
    }

    handleChildRelSelect(event) {
        this.selectedChildRelationship = event.detail.value;
    }

    handleAddChildConfig() {
        if (!this.selectedChildRelationship) {
            this.showToast('Validation', 'Select a child relationship first', 'warning');
            return;
        }

        const parts = this.selectedChildRelationship.split('|');
        const childObject = parts[0];
        const relationshipField = parts[1];

        const newChild = {
            id: `child-${Date.now()}-${Math.random()}`,
            childObject: childObject,
            relationshipField: relationshipField,
            sectionLabel: childObject,
            fields: [],
            availableFields: [],
            get hasFields() { return this.fields.length > 0; }
        };

        // Load fields for the child object
        this.loadFieldsForObject(childObject).then(fields => {
            newChild.availableFields = fields.map(f => ({
                label: `${f.label} (${f.value})`,
                value: f.value,
                fieldLabel: f.label
            }));
            this.childConfigs = [...this.childConfigs, newChild];
        });

        this.selectedChildRelationship = '';
    }

    handleChildLabelChange(event) {
        const childId = event.currentTarget.dataset.childId;
        this.childConfigs = this.childConfigs.map(c =>
            c.id === childId ? this._updateChild(c, { sectionLabel: event.target.value }) : c
        );
    }

    handleRemoveChildConfig(event) {
        const childId = event.currentTarget.dataset.childId;
        this.childConfigs = this.childConfigs.filter(c => c.id !== childId);
    }

    handleChildFieldAdd(event) {
        const childId = event.currentTarget.dataset.childId;
        const fieldApiName = event.detail.value;
        if (!fieldApiName) return;

        this.childConfigs = this.childConfigs.map(c => {
            if (c.id !== childId) return c;
            if (c.fields.some(f => f.apiName === fieldApiName)) return c;

            const fieldInfo = c.availableFields.find(f => f.value === fieldApiName);
            const newField = {
                id: `cfield-${Date.now()}-${Math.random()}`,
                apiName: fieldApiName,
                label: fieldInfo ? fieldInfo.fieldLabel : fieldApiName,
                isRequired: false,
                order: c.fields.length + 1
            };
            return this._updateChild(c, { fields: [...c.fields, newField] });
        });

        event.target.value = null;
    }

    handleChildFieldRequiredChange(event) {
        const childId = event.currentTarget.dataset.childId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.childConfigs = this.childConfigs.map(c => {
            if (c.id !== childId) return c;
            return this._updateChild(c, {
                fields: c.fields.map(f =>
                    f.id === fieldId ? { ...f, isRequired: event.target.checked } : f
                )
            });
        });
    }

    handleChildFieldMoveUp(event) {
        const childId = event.currentTarget.dataset.childId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.childConfigs = this.childConfigs.map(c => {
            if (c.id !== childId) return c;
            const idx = c.fields.findIndex(f => f.id === fieldId);
            if (idx > 0) {
                const arr = [...c.fields];
                [arr[idx], arr[idx - 1]] = [arr[idx - 1], arr[idx]];
                return this._updateChild(c, { fields: arr.map((f, i) => ({ ...f, order: i + 1 })) });
            }
            return c;
        });
    }

    handleChildFieldMoveDown(event) {
        const childId = event.currentTarget.dataset.childId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.childConfigs = this.childConfigs.map(c => {
            if (c.id !== childId) return c;
            const idx = c.fields.findIndex(f => f.id === fieldId);
            if (idx < c.fields.length - 1) {
                const arr = [...c.fields];
                [arr[idx], arr[idx + 1]] = [arr[idx + 1], arr[idx]];
                return this._updateChild(c, { fields: arr.map((f, i) => ({ ...f, order: i + 1 })) });
            }
            return c;
        });
    }

    handleChildFieldRemove(event) {
        const childId = event.currentTarget.dataset.childId;
        const fieldId = event.currentTarget.dataset.fieldId;
        this.childConfigs = this.childConfigs.map(c => {
            if (c.id !== childId) return c;
            return this._updateChild(c, {
                fields: c.fields.filter(f => f.id !== fieldId)
                    .map((f, i) => ({ ...f, order: i + 1 }))
            });
        });
    }

    _updateChild(child, updates) {
        const updated = { ...child, ...updates };
        if (!updates.fields) {
            updated.fields = [...child.fields];
        }
        if (!updates.availableFields) {
            updated.availableFields = [...child.availableFields];
        }
        Object.defineProperty(updated, 'hasFields', {
            get() { return this.fields.length > 0; },
            enumerable: true,
            configurable: true
        });
        return updated;
    }

    // ── Visibility Rules ──

    get hasVisibilityRules() { return this.visibilityRules.length > 0; }
    get showProfilePicker() { return this.currentRule.ruleType === 'Profile'; }
    get showRolePicker() { return this.currentRule.ruleType === 'Role'; }
    get showUserPicker() { return this.currentRule.ruleType === 'User'; }
    get hasUserOptions() { return this.userOptions.length > 0; }

    handleAddRule() {
        this.currentRule = { ruleType: 'Profile', operator: 'equals', value: '' };
        this.showRuleModal = true;
    }

    handleRuleTypeChange(event) {
        this.currentRule = { ...this.currentRule, ruleType: event.detail.value, value: '' };
        if (this.currentRule.ruleType === 'User') {
            this.userOptions = [];
        }
    }

    handleOperatorChange(event) {
        this.currentRule = { ...this.currentRule, operator: event.detail.value };
    }

    handleRuleValueChange(event) {
        this.currentRule = { ...this.currentRule, value: event.detail.value };
    }

    handleUserSearch(event) {
        const searchTerm = event.target.value;
        if (searchTerm && searchTerm.length >= 2) {
            searchUsers({ searchTerm })
                .then(result => {
                    this.userOptions = result.map(u => ({ label: u.label, value: u.value }));
                })
                .catch(error => console.error('Error searching users:', error));
        }
    }

    handleSaveRule() {
        if (this.currentRule.value) {
            this.visibilityRules = [...this.visibilityRules, {
                ...this.currentRule,
                key: `rule-${Date.now()}-${Math.random()}`
            }];
            this.closeRuleModal();
        }
    }

    handleRemoveRule(event) {
        const ruleKey = event.currentTarget.dataset.key;
        this.visibilityRules = this.visibilityRules.filter(r => r.key !== ruleKey);
    }

    closeRuleModal() {
        this.showRuleModal = false;
        this.currentRule = {};
    }

    // ── Document Upload Config ──

    get hasDocumentCategories() {
        return this.documentCategories && this.documentCategories.length > 0;
    }

    async loadDocumentCategories() {
        try {
            const cats = await getDocumentCategoriesForObject({ objectApiName: this.selectedObject });
            this.documentCategories = (cats || []).map(c => ({
                ...c,
                isSelected: false,
                documentTypes: (c.documentTypes || []).map(dt => ({
                    ...dt,
                    isSelected: false,
                    isRequired: false
                }))
            }));
        } catch (e) {
            console.error('Error loading document categories:', e);
            this.documentCategories = [];
        }
    }

    handleDocUploadToggle(event) {
        this.enableDocumentUpload = event.target.checked;
        if (this.enableDocumentUpload && this.documentCategories.length === 0 && this.selectedObject) {
            this.loadDocumentCategories();
        }
    }

    handleDocCategoryToggle(event) {
        const catValue = event.currentTarget.dataset.category;
        const checked = event.target.checked;
        this.documentCategories = this.documentCategories.map(c => {
            if (c.value === catValue) {
                return {
                    ...c,
                    isSelected: checked,
                    documentTypes: c.documentTypes.map(dt => ({
                        ...dt,
                        isSelected: checked ? dt.isSelected : false,
                        isRequired: checked ? dt.isRequired : false
                    }))
                };
            }
            return c;
        });
    }

    handleDocTypeToggle(event) {
        const catValue = event.currentTarget.dataset.category;
        const typeValue = event.currentTarget.dataset.type;
        const checked = event.target.checked;
        this.documentCategories = this.documentCategories.map(c => {
            if (c.value === catValue) {
                return {
                    ...c,
                    documentTypes: c.documentTypes.map(dt =>
                        dt.value === typeValue ? { ...dt, isSelected: checked, isRequired: checked ? dt.isRequired : false } : dt
                    )
                };
            }
            return c;
        });
    }

    handleDocTypeRequiredToggle(event) {
        const catValue = event.currentTarget.dataset.category;
        const typeValue = event.currentTarget.dataset.type;
        const checked = event.target.checked;
        this.documentCategories = this.documentCategories.map(c => {
            if (c.value === catValue) {
                return {
                    ...c,
                    documentTypes: c.documentTypes.map(dt =>
                        dt.value === typeValue ? { ...dt, isRequired: checked } : dt
                    )
                };
            }
            return c;
        });
    }

    _buildDocUploadConfig() {
        if (!this.enableDocumentUpload) return null;
        const docs = [];
        for (const cat of this.documentCategories) {
            if (!cat.isSelected) continue;
            for (const dt of cat.documentTypes) {
                if (!dt.isSelected) continue;
                docs.push({
                    category: cat.value,
                    categoryLabel: cat.label,
                    documentType: dt.value,
                    documentTypeLabel: dt.label,
                    isRequired: dt.isRequired
                });
            }
        }
        return docs.length > 0 ? docs : null;
    }

    _restoreDocUploadConfig(docConfig) {
        if (!docConfig || !Array.isArray(docConfig)) {
            this.enableDocumentUpload = false;
            return;
        }
        this.enableDocumentUpload = true;
        const selectedMap = {};
        for (const d of docConfig) {
            const key = d.category + '|' + d.documentType;
            selectedMap[key] = d.isRequired || false;
        }
        const selectedCats = new Set(docConfig.map(d => d.category));
        this.documentCategories = this.documentCategories.map(c => ({
            ...c,
            isSelected: selectedCats.has(c.value),
            documentTypes: c.documentTypes.map(dt => {
                const key = c.value + '|' + dt.value;
                return {
                    ...dt,
                    isSelected: selectedMap.hasOwnProperty(key),
                    isRequired: selectedMap[key] || false
                };
            })
        }));
    }

    // ── Save ──

    handleSave() {
        if (!this.validateForm()) return;

        const configJson = {
            formName: this.formName,
            targetObject: this.selectedObject,
            contextObject: this.contextObject,
            buttonLabel: this.buttonLabel,
            saveFormNameToField: this.saveFormNameToField,
            contextLookupField: this.contextLookupField,
            conditions: this.conditions.map(c => ({
                field: c.field,
                fieldLabel: c.fieldLabel,
                operator: c.operator,
                value: c.value
            })),
            visibilityRules: this.visibilityRules.map(r => ({
                ruleType: r.ruleType,
                operator: r.operator,
                value: r.value
            })),
            sections: this.sections.map(s => ({
                label: s.label,
                columns: s.columns,
                order: s.order,
                fields: s.fields.map(f => {
                    const fieldData = {
                        apiName: f.apiName,
                        label: f.label,
                        isRequired: f.isRequired,
                        defaultValue: f.defaultValue || '',
                        order: f.order
                    };
                    if (f.showCondition && f.showCondition.field) {
                        fieldData.showCondition = {
                            field: f.showCondition.field,
                            operator: f.showCondition.operator,
                            value: f.showCondition.value
                        };
                    }
                    return fieldData;
                })
            })),
            childConfigs: this.childConfigs.map(cc => ({
                childObject: cc.childObject,
                relationshipField: cc.relationshipField,
                sectionLabel: cc.sectionLabel,
                fields: cc.fields.map(f => ({
                    apiName: f.apiName,
                    label: f.label,
                    isRequired: f.isRequired,
                    order: f.order
                }))
            })),
            documentUploadConfig: this._buildDocUploadConfig()
        };

        this.isLoading = true;
        saveConfiguration({
            configId: this.editingConfigId,
            configName: this.formName,
            objectApiName: this.selectedObject,
            contextObjectApiName: this.contextObject,
            buttonLabel: this.buttonLabel,
            configJson: JSON.stringify(configJson),
            description: this.description,
            active: this.isActive
        })
            .then(() => {
                this.showToast('Success', 'Configuration saved successfully', 'success');
                this.isLoading = false;
                this.handleBackToList();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to save configuration', 'error');
                this.isLoading = false;
                console.error(error);
            });
    }

    validateForm() {
        if (!this.formName) {
            this.showToast('Validation Error', 'Form name is required', 'error');
            return false;
        }
        if (!this.selectedObject) {
            this.showToast('Validation Error', 'Please select a target object', 'error');
            return false;
        }
        const totalFields = this.sections.reduce((sum, s) => sum + s.fields.length, 0);
        if (totalFields === 0) {
            this.showToast('Validation Error', 'Please add at least one field to a section', 'error');
            return false;
        }
        return true;
    }

    resetForm() {
        this.editingConfigId = null;
        this.formName = '';
        this.selectedObject = '';
        this.contextObject = '';
        this.buttonLabel = '';
        this.description = '';
        this.isActive = true;
        this.saveFormNameToField = '';
        this.contextLookupField = '';
        this.sections = [];
        this.conditions = [];
        this.childConfigs = [];
        this.visibilityRules = [];
        this.availableFields = [];
        this.contextFields = [];
        this.childRelationships = [];
        this.selectedChildRelationship = '';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}