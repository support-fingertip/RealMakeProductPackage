import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSourceConfigs from '@salesforce/apex/IntegrationMappingController.getSourceConfigs';
import getSourceConfigWithRules from '@salesforce/apex/IntegrationMappingController.getSourceConfigWithRules';
import saveSourceConfig from '@salesforce/apex/IntegrationMappingController.saveSourceConfig';
import deleteSourceConfig from '@salesforce/apex/IntegrationMappingController.deleteSourceConfig';
import saveFieldRules from '@salesforce/apex/IntegrationMappingController.saveFieldRules';
import getTargetObjectOptions from '@salesforce/apex/IntegrationMappingController.getTargetObjectOptions';
import getObjectFields from '@salesforce/apex/IntegrationMappingController.getObjectFields';

let tempIdCounter = 0;

export default class IntegrationMappingDesigner extends LightningElement {
    @track sourceConfigs = [];
    @track selectedConfig = null;
    @track mappingRules = [];
    @track sfFields = [];
    @track apiFields = [];

    @track configForm = {};
    @track targetObjectOptions = [];

    isLoading = false;
    showConfigForm = false;
    isNewConfig = false;
    apiFieldSearch = '';
    sfFieldSearch = '';
    isDragOver = false;
    dragData = null;

    // ═══════════════════════════════════════════
    // LIFECYCLE
    // ═══════════════════════════════════════════

    connectedCallback() {
        this.loadConfigs();
        this.loadTargetObjects();
    }

    // ═══════════════════════════════════════════
    // DATA LOADING
    // ═══════════════════════════════════════════

    async loadConfigs() {
        this.isLoading = true;
        try {
            const configs = await getSourceConfigs();
            this.sourceConfigs = configs.map(c => ({
                ...c,
                cardClass: 'config-card' + (this.selectedConfig && this.selectedConfig.Id === c.Id ? ' active' : '')
            }));
        } catch (error) {
            this.showError('Error loading configs', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadTargetObjects() {
        try {
            const objects = await getTargetObjectOptions();
            this.targetObjectOptions = objects.map(o => ({ label: `${o.label} (${o.apiName})`, value: o.apiName }));
        } catch (error) {
            this.showError('Error loading objects', error);
        }
    }

    async loadConfigDetails(configId) {
        this.isLoading = true;
        try {
            const config = await getSourceConfigWithRules({ configId });
            this.selectedConfig = config;

            // Load SF fields for the target object
            await this.loadSfFields(config.Target_Object__c);

            // Parse API schema
            this.parseApiSchema(config.API_Schema_JSON__c);

            // Load existing mapping rules
            this.mappingRules = (config.Integration_Field_Rules__r || []).map(r => ({
                id: r.Id,
                tempId: 'rule-' + (++tempIdCounter),
                apiFieldName: r.API_Field_Name__c,
                apiFieldLabel: r.API_Field_Label__c || r.API_Field_Name__c,
                sfFieldApiName: r.SF_Field_API_Name__c,
                isRequired: r.Is_Required__c,
                defaultValue: r.Default_Value__c,
                dataType: r.Data_Type__c || 'Text',
                transformExpression: r.Transform_Expression__c,
                isActive: r.Is_Active__c,
                isStatic: r.Is_Static__c || false,
                sequence: r.Sequence__c,
                isLookupType: r.Data_Type__c === 'Lookup',
                lookupRule: r.Integration_Lookup_Rules__r && r.Integration_Lookup_Rules__r.length > 0
                    ? {
                        id: r.Integration_Lookup_Rules__r[0].Id,
                        lookupObject: r.Integration_Lookup_Rules__r[0].Lookup_Object__c,
                        matchField: r.Integration_Lookup_Rules__r[0].Match_Field__c,
                        returnField: r.Integration_Lookup_Rules__r[0].Return_Field__c,
                        failOnNoMatch: r.Integration_Lookup_Rules__r[0].Fail_On_No_Match__c,
                        additionalFilter: r.Integration_Lookup_Rules__r[0].Additional_Filter__c
                    }
                    : { lookupObject: '', matchField: '', returnField: 'Id', failOnNoMatch: false, additionalFilter: '' }
            }));

            // Populate config form
            this.configForm = {
                id: config.Id,
                name: config.Name,
                sourceName: config.Source_Name__c,
                targetObject: config.Target_Object__c,
                isActive: config.Is_Active__c,
                version: config.Version__c,
                description: config.Description__c,
                apiSchemaJson: config.API_Schema_JSON__c,
                validationRulesJson: config.Validation_Rules_JSON__c,
                endpointUrl: this.generateEndpointUrl(config.Source_Name__c),
                enableDuplicateCheck: config.Enable_Duplicate_Check__c || false
            };

            this.showConfigForm = true;
            this.isNewConfig = false;

            // Refresh config list to show active state
            this.sourceConfigs = this.sourceConfigs.map(c => ({
                ...c,
                cardClass: 'config-card' + (c.Id === configId ? ' active' : '')
            }));
        } catch (error) {
            this.showError('Error loading config details', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadSfFields(objectApiName) {
        try {
            const fields = await getObjectFields({ objectApiName });
            this.sfFields = fields;
        } catch (error) {
            this.showError('Error loading SF fields', error);
        }
    }

    parseApiSchema(schemaJson) {
        if (!schemaJson) {
            this.apiFields = [];
            return;
        }
        try {
            this.apiFields = JSON.parse(schemaJson);
        } catch (e) {
            this.apiFields = [];
        }
    }

    // ═══════════════════════════════════════════
    // COMPUTED PROPERTIES
    // ═══════════════════════════════════════════

    get hasConfigs() {
        return this.sourceConfigs && this.sourceConfigs.length > 0;
    }

    get hasApiFields() {
        return this.apiFields && this.apiFields.length > 0;
    }

    get hasMappings() {
        return this.mappingRules && this.mappingRules.length > 0;
    }

    get showMappingDesigner() {
        return this.selectedConfig != null && this.showConfigForm;
    }

    get mappingCount() {
        return this.mappingRules ? this.mappingRules.length : 0;
    }

    get dropZoneClass() {
        return 'drop-zone' + (this.isDragOver ? ' drag-over' : '');
    }

    get mappedApiFieldNames() {
        return new Set(this.mappingRules.filter(r => !r.isStatic).map(r => r.apiFieldName));
    }

    get mappedSfFieldNames() {
        return new Set(this.mappingRules.map(r => r.sfFieldApiName).filter(Boolean));
    }

    get filteredApiFields() {
        const mapped = this.mappedApiFieldNames;
        const search = (this.apiFieldSearch || '').toLowerCase();
        return (this.apiFields || [])
            .filter(f => {
                const matchesSearch = !search ||
                    (f.name || '').toLowerCase().includes(search) ||
                    (f.label || '').toLowerCase().includes(search);
                return matchesSearch;
            })
            .map(f => ({
                ...f,
                itemClass: 'field-item' + (mapped.has(f.name) ? ' mapped' : '')
            }));
    }

    get filteredSfFields() {
        const mapped = this.mappedSfFieldNames;
        const search = (this.sfFieldSearch || '').toLowerCase();
        return (this.sfFields || [])
            .filter(f => {
                const matchesSearch = !search ||
                    (f.apiName || '').toLowerCase().includes(search) ||
                    (f.label || '').toLowerCase().includes(search);
                return matchesSearch;
            })
            .map(f => ({
                ...f,
                itemClass: 'field-item' + (mapped.has(f.apiName) ? ' mapped' : '')
            }));
    }

    get sfFieldOptions() {
        return (this.sfFields || []).map(f => ({
            label: `${f.label} (${f.apiName})`,
            value: f.apiName
        }));
    }

    get dataTypeOptions() {
        return [
            { label: 'Text', value: 'Text' },
            { label: 'Number', value: 'Number' },
            { label: 'Date', value: 'Date' },
            { label: 'DateTime', value: 'DateTime' },
            { label: 'Boolean', value: 'Boolean' },
            { label: 'Currency', value: 'Currency' },
            { label: 'Lookup', value: 'Lookup' },
            { label: 'Picklist', value: 'Picklist' },
            { label: 'Email', value: 'Email' },
            { label: 'Phone', value: 'Phone' }
        ];
    }

    // ═══════════════════════════════════════════
    // CONFIG HANDLERS
    // ═══════════════════════════════════════════

    handleNewConfig() {
        this.selectedConfig = null;
        this.mappingRules = [];
        this.apiFields = [];
        this.configForm = {
            id: null,
            name: '',
            sourceName: '',
            targetObject: '',
            isActive: true,
            version: 1,
            description: '',
            apiSchemaJson: '',
            validationRulesJson: '',
            endpointUrl: '',
            enableDuplicateCheck: false
        };
        this.showConfigForm = true;
        this.isNewConfig = true;

        this.sourceConfigs = this.sourceConfigs.map(c => ({
            ...c,
            cardClass: 'config-card'
        }));
    }

    handleSelectConfig(event) {
        const configId = event.currentTarget.dataset.id;
        this.loadConfigDetails(configId);
    }

    handleCancelConfig() {
        this.showConfigForm = false;
        this.selectedConfig = null;
        this.mappingRules = [];
        this.sourceConfigs = this.sourceConfigs.map(c => ({
            ...c,
            cardClass: 'config-card'
        }));
    }

    handleConfigFormChange(event) {
        const field = event.target.dataset.field;
        const isCheckbox = field === 'isActive' || field === 'enableDuplicateCheck';
        const value = isCheckbox ? event.target.checked : event.target.value;
        this.configForm = { ...this.configForm, [field]: value };

        // Auto-generate endpoint URL when source name changes
        if (field === 'sourceName') {
            this.configForm = {
                ...this.configForm,
                endpointUrl: this.generateEndpointUrl(value)
            };
        }

        // Reload API schema if changed
        if (field === 'apiSchemaJson') {
            this.parseApiSchema(value);
        }

        // Reload SF fields if target object changed
        if (field === 'targetObject' && value) {
            this.loadSfFields(value);
        }
    }

    async handleSaveConfig() {
        if (!this.configForm.name || !this.configForm.sourceName || !this.configForm.targetObject) {
            this.showToast('Validation Error', 'Config Name, Source Name, and Target Object are required.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            const configId = await saveSourceConfig({
                configJSON: JSON.stringify(this.configForm)
            });

            this.showToast('Success', 'Integration source config saved.', 'success');
            await this.loadConfigs();

            // If new, load the details to show mapping designer
            if (this.isNewConfig) {
                await this.loadConfigDetails(configId);
            }
        } catch (error) {
            this.showError('Error saving config', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteConfig() {
        if (!this.selectedConfig) return;

        this.isLoading = true;
        try {
            await deleteSourceConfig({ configId: this.selectedConfig.Id });
            this.showToast('Success', 'Config deleted.', 'success');
            this.handleCancelConfig();
            await this.loadConfigs();
        } catch (error) {
            this.showError('Error deleting config', error);
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════════════════════════════════════
    // DRAG AND DROP
    // ═══════════════════════════════════════════

    handleDragStart(event) {
        const fieldName = event.currentTarget.dataset.fieldName;
        this.dragData = this.apiFields.find(f => f.name === fieldName);
        event.currentTarget.classList.add('dragging');
        event.dataTransfer.effectAllowed = 'copy';
        event.dataTransfer.setData('text/plain', fieldName);
    }

    handleDragEnd(event) {
        event.currentTarget.classList.remove('dragging');
        this.dragData = null;
    }

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'copy';
        this.isDragOver = true;
    }

    handleDragLeave() {
        this.isDragOver = false;
    }

    handleDrop(event) {
        event.preventDefault();
        this.isDragOver = false;

        if (!this.dragData) return;

        // Check if already mapped
        if (this.mappedApiFieldNames.has(this.dragData.name)) {
            this.showToast('Already Mapped', `"${this.dragData.label || this.dragData.name}" is already mapped.`, 'warning');
            return;
        }

        // Auto-match SF field by name
        const autoMatch = this.sfFields.find(
            f => f.apiName.toLowerCase().replace(/__c$/i, '').replace(/_/g, '') ===
                 this.dragData.name.toLowerCase().replace(/_/g, '')
        );

        const newRule = {
            id: null,
            tempId: 'rule-' + (++tempIdCounter),
            apiFieldName: this.dragData.name,
            apiFieldLabel: this.dragData.label || this.dragData.name,
            sfFieldApiName: autoMatch ? autoMatch.apiName : '',
            isRequired: this.dragData.required || false,
            defaultValue: '',
            dataType: this.dragData.type || 'Text',
            transformExpression: '',
            isActive: true,
            isStatic: false,
            sequence: this.mappingRules.length + 1,
            isLookupType: (this.dragData.type || '').toLowerCase() === 'lookup',
            lookupRule: { lookupObject: '', matchField: '', returnField: 'Id', failOnNoMatch: false, additionalFilter: '' }
        };

        this.mappingRules = [...this.mappingRules, newRule];
        this.dragData = null;
    }

    // ═══════════════════════════════════════════
    // STATIC VALUE
    // ═══════════════════════════════════════════

    handleAddStaticValue() {
        const newRule = {
            id: null,
            tempId: 'rule-' + (++tempIdCounter),
            apiFieldName: '',
            apiFieldLabel: '',
            sfFieldApiName: '',
            isRequired: false,
            defaultValue: '',
            dataType: 'Text',
            transformExpression: '',
            isActive: true,
            isStatic: true,
            sequence: this.mappingRules.length + 1,
            isLookupType: false,
            lookupRule: { lookupObject: '', matchField: '', returnField: 'Id', failOnNoMatch: false, additionalFilter: '' }
        };
        this.mappingRules = [...this.mappingRules, newRule];
    }

    // ═══════════════════════════════════════════
    // MAPPING RULE HANDLERS
    // ═══════════════════════════════════════════

    handleSfFieldChange(event) {
        const tempId = event.target.dataset.tempId;
        const value = event.detail.value;
        this.mappingRules = this.mappingRules.map(r =>
            r.tempId === tempId ? { ...r, sfFieldApiName: value } : r
        );
    }

    handleRuleFieldChange(event) {
        const tempId = event.target.dataset.tempId;
        const field = event.target.dataset.field;
        const value = field === 'isRequired' ? event.target.checked : event.target.value;

        this.mappingRules = this.mappingRules.map(r => {
            if (r.tempId === tempId) {
                const updated = { ...r, [field]: value };
                if (field === 'dataType') {
                    updated.isLookupType = value === 'Lookup';
                }
                return updated;
            }
            return r;
        });
    }

    handleLookupFieldChange(event) {
        const tempId = event.target.dataset.tempId;
        const field = event.target.dataset.field;
        const value = field === 'failOnNoMatch' ? event.target.checked : event.target.value;

        this.mappingRules = this.mappingRules.map(r => {
            if (r.tempId === tempId) {
                return {
                    ...r,
                    lookupRule: { ...r.lookupRule, [field]: value }
                };
            }
            return r;
        });
    }

    handleRemoveMapping(event) {
        const tempId = event.currentTarget.dataset.tempId;
        this.mappingRules = this.mappingRules.filter(r => r.tempId !== tempId);
    }

    // ═══════════════════════════════════════════
    // SEARCH HANDLERS
    // ═══════════════════════════════════════════

    handleApiFieldSearch(event) {
        this.apiFieldSearch = event.target.value;
    }

    handleSfFieldSearch(event) {
        this.sfFieldSearch = event.target.value;
    }

    // ═══════════════════════════════════════════
    // SAVE MAPPINGS
    // ═══════════════════════════════════════════

    async handleSaveMappings() {
        // Validate all rules have SF field selected
        const incomplete = this.mappingRules.filter(r => !r.sfFieldApiName);
        if (incomplete.length > 0) {
            this.showToast('Validation Error',
                `${incomplete.length} mapping(s) do not have a Salesforce field selected.`, 'error');
            return;
        }

        // Validate static rules have a value
        const emptyStatic = this.mappingRules.filter(r => r.isStatic && !r.defaultValue);
        if (emptyStatic.length > 0) {
            this.showToast('Validation Error',
                `${emptyStatic.length} static rule(s) do not have a value set.`, 'error');
            return;
        }

        // Validate lookup rules
        const badLookups = this.mappingRules.filter(
            r => r.isLookupType && (!r.lookupRule.lookupObject || !r.lookupRule.matchField)
        );
        if (badLookups.length > 0) {
            this.showToast('Validation Error',
                'Lookup mappings require Lookup Object and Match Field.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            const rulesPayload = this.mappingRules.map((r, idx) => ({
                id: r.id,
                apiFieldName: r.apiFieldName,
                apiFieldLabel: r.apiFieldLabel,
                sfFieldApiName: r.sfFieldApiName,
                isRequired: r.isRequired,
                defaultValue: r.defaultValue,
                dataType: r.dataType,
                transformExpression: r.transformExpression,
                isActive: r.isActive,
                isStatic: r.isStatic,
                sequence: idx + 1,
                lookupRule: r.isLookupType ? {
                    id: r.lookupRule.id || null,
                    lookupObject: r.lookupRule.lookupObject,
                    matchField: r.lookupRule.matchField,
                    returnField: r.lookupRule.returnField || 'Id',
                    failOnNoMatch: r.lookupRule.failOnNoMatch,
                    additionalFilter: r.lookupRule.additionalFilter
                } : null
            }));

            await saveFieldRules({
                configId: this.selectedConfig.Id,
                rulesJSON: JSON.stringify(rulesPayload)
            });

            this.showToast('Success', `${rulesPayload.length} field mapping(s) saved.`, 'success');

            // Reload to get actual IDs
            await this.loadConfigDetails(this.selectedConfig.Id);
        } catch (error) {
            this.showError('Error saving mappings', error);
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════════════════════════════════════
    // ENDPOINT URL
    // ═══════════════════════════════════════════

    generateEndpointUrl(sourceName) {
        if (!sourceName) return '';
        return window.location.origin + '/services/apexrest/integration/' + sourceName;
    }

    handleCopyEndpointUrl() {
        const url = this.configForm.endpointUrl;
        if (url) {
            navigator.clipboard.writeText(url).then(() => {
                this.showToast('Copied', 'Endpoint URL copied to clipboard.', 'success');
            });
        }
    }

    // ═══════════════════════════════════════════
    // PDF DOCUMENTATION
    // ═══════════════════════════════════════════

    handleViewApiDoc() {
        if (!this.selectedConfig) return;
        const url = '/apex/IntegrationAPIDoc?id=' + this.selectedConfig.Id;
        window.open(url, '_blank');
    }

    handleDownloadPdf() {
        if (!this.selectedConfig) return;
        const url = '/apex/IntegrationAPIDoc?id=' + this.selectedConfig.Id + '&format=pdf';
        window.open(url, '_blank');
    }

    // ═══════════════════════════════════════════
    // UTILITY
    // ═══════════════════════════════════════════

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(title, error) {
        const message = error?.body?.message || error?.message || JSON.stringify(error);
        this.showToast(title, message, 'error');
    }
}