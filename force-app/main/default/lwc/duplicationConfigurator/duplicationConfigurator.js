import { LightningElement, track, wire } from 'lwc';
import getAllObjects from '@salesforce/apex/DuplicationConfigController.getAllObjects';
import getObjectFields from '@salesforce/apex/DuplicationConfigController.getObjectFields';
import getRelatedObjectFieldsImperative from '@salesforce/apex/DuplicationConfigController.getRelatedObjectFieldsImperative';
import getRelatedObjects from '@salesforce/apex/DuplicationConfigController.getRelatedObjects';
import saveConfiguration from '@salesforce/apex/DuplicationConfigController.saveConfiguration';
import getConfigurationsByObject from '@salesforce/apex/DuplicationConfigController.getConfigurationsByObject';
import getConfigurationWithMappings from '@salesforce/apex/DuplicationConfigController.getConfigurationWithMappings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DuplicationConfiguration extends LightningElement {
    @track objectOptions = [];
    @track selectedObject = '';
    @track fieldOptions = [];
    @track expressionValue = '';
    @track relatedObjectOptions = [];
    @track selectedRelatedObject = '';
    @track relatedFieldOptions = [];
    @track relatedExpressionValue = '';
    @track isLoading = false;
    @track showExpressionBuilder = false;
    @track showRelatedExpressionBuilder = false;
    
    // Edit Mode
    @track existingConfigs = [];
    @track selectedConfigId = '';
    @track isEditMode = false;

    // Field Mapping Data
    @track fieldMappings = [];
    mappingIdCounter = 0;

    // Mapping Type Options
    mappingTypeOptions = [
        { label: 'Map from Primary Object', value: 'field' },
        { label: 'Manual Value', value: 'manual' }
    ];

    // Load all objects on component initialization
    @wire(getAllObjects)
    wiredObjects({ error, data }) {
        if (data) {
            this.objectOptions = data.map(obj => ({
                label: obj.label,
                value: obj.value
            }));
        } else if (error) {
            this.showError('Error loading objects', error.body.message);
        }
    }

    // Initialize with one empty mapping row
    connectedCallback() {
        this.initializeFieldMappings();
    }

    // Initialize field mappings with one row
    initializeFieldMappings() {
        this.fieldMappings = [{
            id: this.generateMappingId(),
            relatedField: '',
            mappingType: '',
            sourceValue: '',
            isFieldMapping: false,
            isManualValue: false,
            showPlaceholder: true
        }];
    }

    // Generate unique mapping ID
    generateMappingId() {
        return `mapping_${this.mappingIdCounter++}`;
    }

    // Handle object selection
    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.expressionValue = '';
        this.showExpressionBuilder = false;
        
        // Reset related object selections
        this.selectedRelatedObject = '';
        this.relatedExpressionValue = '';
        this.showRelatedExpressionBuilder = false;
        
        // Reset field mappings
        this.initializeFieldMappings();
        
        // Reset edit mode
        this.isEditMode = false;
        this.selectedConfigId = '';
        this.existingConfigs = [];

        if (this.selectedObject) {
            this.loadObjectFields(this.selectedObject);
            this.loadRelatedObjects(this.selectedObject);
            this.loadExistingConfigs(this.selectedObject);
            this.showExpressionBuilder = true;
        }
    }

    // Load existing configurations for selected object
    loadExistingConfigs(objectApiName) {
        getConfigurationsByObject({ objectApiName })
            .then(result => {
                this.existingConfigs = result || [];
            })
            .catch(error => {
                this.existingConfigs = [];
            });
    }

    // Handle editing an existing configuration
    handleEditConfig(event) {
        const configId = event.target.dataset.id || event.currentTarget.dataset.id;
        if (!configId) return;

        this.isLoading = true;
        getConfigurationWithMappings({ configId })
            .then(result => {
                this.isEditMode = true;
                this.selectedConfigId = configId;
                this.expressionValue = result.config.Primary_Expression__c || '';
                this.showExpressionBuilder = true;

                // Helper to set field mappings from result
                const setFieldMappings = () => {
                    if (result.mappings && result.mappings.length > 0) {
                        this.fieldMappings = result.mappings.map(m => ({
                            id: this.generateMappingId(),
                            relatedField: m.Related_object_field__c || '',
                            mappingType: m.Mapping_Type__c || '',
                            sourceValue: m.Primary_Object_Field_value__c || '',
                            isFieldMapping: m.Mapping_Type__c === 'field',
                            isManualValue: m.Mapping_Type__c === 'manual',
                            showPlaceholder: !m.Mapping_Type__c
                        }));
                    } else {
                        this.initializeFieldMappings();
                    }
                };

                if (result.config.Related_Object_API_Name__c) {
                    this.selectedRelatedObject = result.config.Related_Object_API_Name__c;
                    this.relatedExpressionValue = result.config.Related_Expression__c || '';
                    this.showRelatedExpressionBuilder = true;
                    // Load related field options and set field mappings in the same synchronous block
                    // to avoid intermediate renders where options are empty
                    getRelatedObjectFieldsImperative({ objectApiName: this.selectedRelatedObject })
                        .then(fieldResult => {
                            this.relatedFieldOptions = fieldResult.map(field => ({
                                label: `${field.label} (${field.value})`,
                                value: field.value,
                                type: field.type
                            }));
                            setFieldMappings();
                            this.isLoading = false;
                            this.showSuccess('Loaded', 'Configuration loaded for editing.');
                        })
                        .catch(error => {
                            const errorMsg = error.body ? error.body.message : (error.message || 'Unknown error');
                            this.showError('Error loading related object fields', errorMsg);
                            // Still set field mappings so user can see the configuration
                            setFieldMappings();
                            this.isLoading = false;
                        });
                } else {
                    setFieldMappings();
                    this.isLoading = false;
                    this.showSuccess('Loaded', 'Configuration loaded for editing.');
                }
            })
            .catch(error => {
                this.showError('Error loading configuration', error.body ? error.body.message : 'Unknown error');
                this.isLoading = false;
            });
    }

    // Cancel edit mode
    handleCancelEdit() {
        this.isEditMode = false;
        this.selectedConfigId = '';
        this.expressionValue = '';
        this.relatedExpressionValue = '';
        this.selectedRelatedObject = '';
        this.showRelatedExpressionBuilder = false;
        this.initializeFieldMappings();
    }

    // Load fields for selected object
    loadObjectFields(objectApiName) {
        this.isLoading = true;
        getObjectFields({ objectApiName })
            .then(result => {
                this.fieldOptions = result.map(field => ({
                    label: `${field.label} (${field.value})`,
                    value: field.value,
                    type: field.type
                }));
                this.isLoading = false;
            })
            .catch(error => {
                this.showError('Error loading fields', error.body.message);
                this.isLoading = false;
            });
    }

    // Load related objects
    loadRelatedObjects(objectApiName) {
        getRelatedObjects({ objectApiName })
            .then(result => {
                this.relatedObjectOptions = result.map(obj => ({
                    label: obj.label,
                    value: obj.value
                }));
            })
            .catch(error => {
                this.showError('Error loading related objects', error.body.message);
            });
    }

    // Handle field selection from dropdown - automatically add to expression
    handleFieldSelect(event) {
        const selectedField = event.detail.value;
        if (selectedField) {
            this.addFieldToExpression(selectedField);
            // Reset the dropdown
            this.template.querySelector('[data-id="primaryFieldSelect"]').value = '';
        }
    }

    // Add field to expression
    addFieldToExpression(fieldValue) {
        if (this.expressionValue && this.expressionValue.trim() !== '') {
            // Add space before appending if last character is not a space
            const lastChar = this.expressionValue.slice(-1);
            if (lastChar !== ' ') {
                this.expressionValue += ' ';
            }
            this.expressionValue += fieldValue;
        } else {
            this.expressionValue = fieldValue;
        }
    }

    // Handle manual expression input
    handleExpressionChange(event) {
        this.expressionValue = event.detail.value;
    }

    // Add AND operator
    addAndOperator() {
        if (this.expressionValue && this.expressionValue.trim() !== '') {
            const lastChar = this.expressionValue.slice(-1);
            if (lastChar !== ' ') {
                this.expressionValue += ' ';
            }
            this.expressionValue += '+ ';
        }
    }

    // Add OR operator
    addOrOperator() {
        if (this.expressionValue && this.expressionValue.trim() !== '') {
            const lastChar = this.expressionValue.slice(-1);
            if (lastChar !== ' ') {
                this.expressionValue += ' ';
            }
            this.expressionValue += 'OR ';
        }
    }

    // Clear primary expression
    clearExpression() {
        this.expressionValue = '';
    }

    // Handle related object selection
    handleRelatedObjectChange(event) {
        this.selectedRelatedObject = event.detail.value;
        this.relatedExpressionValue = '';
        this.showRelatedExpressionBuilder = false;
        
        // Reset field mappings when related object changes
        this.initializeFieldMappings();
        
        if (this.selectedRelatedObject) {
            this.loadRelatedObjectFields(this.selectedRelatedObject);
            this.showRelatedExpressionBuilder = true;
        }
    }

    // Clear related object selection
    clearRelatedObject() {
        this.selectedRelatedObject = '';
        this.relatedExpressionValue = '';
        this.relatedFieldOptions = [];
        this.showRelatedExpressionBuilder = false;
        
        // Reset field mappings
        this.initializeFieldMappings();
        
        // Reset the combobox
        const relatedObjCombobox = this.template.querySelector('[data-id="relatedObjectSelect"]');
        if (relatedObjCombobox) {
            relatedObjCombobox.value = '';
        }
        
        this.showSuccess('Cleared', 'Related object selection has been cleared');
    }

    // Load fields for selected related object (uses non-cacheable method to avoid LWC cache interference)
    loadRelatedObjectFields(objectApiName) {
        this.isLoading = true;
        return getRelatedObjectFieldsImperative({ objectApiName })
            .then(result => {
                this.relatedFieldOptions = result.map(field => ({
                    label: `${field.label} (${field.value})`,
                    value: field.value,
                    type: field.type
                }));
                this.isLoading = false;
            })
            .catch(error => {
                const errorMsg = error.body ? error.body.message : (error.message || 'Unknown error loading related object fields');
                this.showError('Error loading related object fields', errorMsg);
                this.isLoading = false;
            });
    }

    // Handle related field selection - automatically add to related expression
    handleRelatedFieldSelect(event) {
        const selectedField = event.detail.value;
        if (selectedField) {
            this.addRelatedFieldToExpression(selectedField);
            // Reset the dropdown
            this.template.querySelector('[data-id="relatedFieldSelect"]').value = '';
        }
    }

    // Add field to related expression
    addRelatedFieldToExpression(fieldValue) {
        if (this.relatedExpressionValue && this.relatedExpressionValue.trim() !== '') {
            const lastChar = this.relatedExpressionValue.slice(-1);
            if (lastChar !== ' ') {
                this.relatedExpressionValue += ' ';
            }
            this.relatedExpressionValue += fieldValue;
        } else {
            this.relatedExpressionValue = fieldValue;
        }
    }

    // Handle related expression manual input
    handleRelatedExpressionChange(event) {
        this.relatedExpressionValue = event.detail.value;
    }

    // Add AND operator to related expression
    addRelatedAndOperator() {
        if (this.relatedExpressionValue && this.relatedExpressionValue.trim() !== '') {
            const lastChar = this.relatedExpressionValue.slice(-1);
            if (lastChar !== ' ') {
                this.relatedExpressionValue += ' ';
            }
            this.relatedExpressionValue += '+ ';
        }
    }

    // Add OR operator to related expression
    addRelatedOrOperator() {
        if (this.relatedExpressionValue && this.relatedExpressionValue.trim() !== '') {
            const lastChar = this.relatedExpressionValue.slice(-1);
            if (lastChar !== ' ') {
                this.relatedExpressionValue += ' ';
            }
            this.relatedExpressionValue += 'OR ';
        }
    }

    // Clear related expression
    clearRelatedExpression() {
        this.relatedExpressionValue = '';
    }

    // ========== FIELD MAPPING HANDLERS ==========

    // Handle related field change in mapping
    handleMappingRelatedFieldChange(event) {
        const mappingId = event.target.dataset.id;
        const value = event.detail.value;
        
        this.fieldMappings = this.fieldMappings.map(mapping => {
            if (mapping.id === mappingId) {
                return { ...mapping, relatedField: value };
            }
            return mapping;
        });
    }

    // Handle mapping type change
    handleMappingTypeChange(event) {
        const mappingId = event.target.dataset.id;
        const value = event.detail.value;
        
        this.fieldMappings = this.fieldMappings.map(mapping => {
            if (mapping.id === mappingId) {
                return {
                    ...mapping,
                    mappingType: value,
                    sourceValue: '', // Reset source value when type changes
                    isFieldMapping: value === 'field',
                    isManualValue: value === 'manual',
                    showPlaceholder: !value
                };
            }
            return mapping;
        });
    }

    // Handle source value change
    handleMappingSourceValueChange(event) {
        const mappingId = event.target.dataset.id;
        const value = event.detail.value;
        
        this.fieldMappings = this.fieldMappings.map(mapping => {
            if (mapping.id === mappingId) {
                return { ...mapping, sourceValue: value };
            }
            return mapping;
        });
    }

    // Add new mapping row
    handleAddMapping() {
        this.fieldMappings = [
            ...this.fieldMappings,
            {
                id: this.generateMappingId(),
                relatedField: '',
                mappingType: '',
                sourceValue: '',
                isFieldMapping: false,
                isManualValue: false,
                showPlaceholder: true
            }
        ];
    }

    // Delete mapping row
    handleDeleteMapping(event) {
        const mappingId = event.target.dataset.id;
        
        // Don't allow deleting if only one mapping exists
        if (this.fieldMappings.length <= 1) {
            this.showError('Cannot Delete', 'At least one field mapping is required');
            return;
        }
        
        this.fieldMappings = this.fieldMappings.filter(mapping => mapping.id !== mappingId);
    }

    // ========== VALIDATION ==========

    // Validate if expression is open-ended (ends with operators)
    isExpressionOpenEnded(expression) {
        if (!expression || expression.trim() === '') {
            return false;
        }
        
        const trimmedExpression = expression.trim();
        const openEndedPatterns = ['+', 'OR', 'AND', '(', ','];
        
        // Check if expression ends with any operator
        for (let pattern of openEndedPatterns) {
            if (trimmedExpression.endsWith(pattern)) {
                return true;
            }
        }
        
        return false;
    }

    // Validate field mappings
    validateFieldMappings() {
        // No validation needed if section is not shown
        if (!this.showFieldMappingSection) {
            return true;
        }

        for (let mapping of this.fieldMappings) {
            // Check if related field is selected
            if (!mapping.relatedField || mapping.relatedField.trim() === '') {
                this.showError('Validation Error', 'Please select a Related Object Field for all mappings');
                return false;
            }

            // Check if mapping type is selected
            if (!mapping.mappingType || mapping.mappingType.trim() === '') {
                this.showError('Validation Error', 'Please select a Mapping Type for all mappings');
                return false;
            }

            // Check if source value is provided
            if (!mapping.sourceValue || mapping.sourceValue.trim() === '') {
                this.showError('Validation Error', 'Please provide a value for all field mappings');
                return false;
            }
        }

        return true;
    }

    // Save configuration
    handleSave() {
        if (!this.validateConfiguration()) {
            return;
        }

        if (!this.validateFieldMappings()) {
            return;
        }

        const configData = {
            primaryObject: this.selectedObject,
            primaryExpression: this.expressionValue,
            relatedObject: this.selectedRelatedObject,
            relatedExpression: this.relatedExpressionValue,
            fieldMappings: this.fieldMappings.map(mapping => ({
                relatedField: mapping.relatedField,
                mappingType: mapping.mappingType,
                sourceValue: mapping.sourceValue
            }))
        };

        // Include config ID when editing
        if (this.isEditMode && this.selectedConfigId) {
            configData.configId = this.selectedConfigId;
        }

        this.isLoading = true;
        saveConfiguration({ configData: JSON.stringify(configData) })
            .then(result => {
                this.showSuccess('Success', result);
                this.isLoading = false;
                // Auto-refresh the page after successful save
                setTimeout(() => {
                    window.location.reload();
                }, 1500);
            })
            .catch(error => {
                this.showError('Error saving configuration', error.body.message);
                this.isLoading = false;
            });
    }

    // Validate configuration
    validateConfiguration() {
        // Validate primary object
        if (!this.selectedObject) {
            this.showError('Validation Error', 'Please select an object');
            return false;
        }
        
        // Validate primary expression exists
        if (!this.expressionValue || this.expressionValue.trim() === '') {
            this.showError('Validation Error', 'Please define duplication logic');
            return false;
        }
        
        // Validate primary expression is not open-ended
        if (this.isExpressionOpenEnded(this.expressionValue)) {
            this.showError('Invalid Expression', 
                'Primary expression is incomplete. It ends with an operator (+, OR, AND). Please complete the expression by adding a field.');
            return false;
        }
        
        // Validate related object expression if related object is selected
        if (this.selectedRelatedObject) {
            if (!this.relatedExpressionValue || this.relatedExpressionValue.trim() === '') {
                this.showError('Validation Error', 
                    'Please define duplication logic for the related object or clear the related object selection');
                return false;
            }
            
            // Validate related expression is not open-ended
            if (this.isExpressionOpenEnded(this.relatedExpressionValue)) {
                this.showError('Invalid Expression', 
                    'Related object expression is incomplete. It ends with an operator (+, OR, AND). Please complete the expression by adding a field.');
                return false;
            }
        }
        
        return true;
    }

    // Show success toast
    showSuccess(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'success',
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }

    // Show error toast
    showError(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error',
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }

    // ========== GETTERS ==========

    get hasFieldOptions() {
        return this.fieldOptions.length > 0;
    }

    get hasRelatedFieldOptions() {
        return this.relatedFieldOptions.length > 0;
    }

    get hasSelectedObject() {
        return this.selectedObject !== '';
    }

    get hasSelectedRelatedObject() {
        return this.selectedRelatedObject !== '';
    }

    get hasExpression() {
        return this.expressionValue && this.expressionValue.trim() !== '';
    }

    get hasRelatedExpression() {
        return this.relatedExpressionValue && this.relatedExpressionValue.trim() !== '';
    }

    // Check if primary expression is valid (not open-ended)
    get isPrimaryExpressionValid() {
        if (!this.hasExpression) return true;
        return !this.isExpressionOpenEnded(this.expressionValue);
    }

    // Check if related expression is valid (not open-ended)
    get isRelatedExpressionValid() {
        if (!this.hasRelatedExpression) return true;
        return !this.isExpressionOpenEnded(this.relatedExpressionValue);
    }

    // Get CSS class for primary expression textarea
    get primaryExpressionClass() {
        return this.isPrimaryExpressionValid ? '' : 'invalid-expression';
    }

    // Get CSS class for related expression textarea
    get relatedExpressionClass() {
        return this.isRelatedExpressionValid ? '' : 'invalid-expression';
    }

    // Get CSS class for primary expression preview
    get primaryPreviewClass() {
        return this.isPrimaryExpressionValid 
            ? 'expression-preview slds-box slds-box_x-small slds-theme_success' 
            : 'expression-preview slds-box slds-box_x-small slds-theme_error';
    }

    // Get CSS class for related expression preview
    get relatedPreviewClass() {
        return this.isRelatedExpressionValid 
            ? 'expression-preview slds-box slds-box_x-small slds-theme_info' 
            : 'expression-preview slds-box slds-box_x-small slds-theme_error';
    }

    // Check if clear related object button should be disabled
    get isClearRelatedObjectDisabled() {
        return !this.hasSelectedRelatedObject;
    }

    // Check if there's only one mapping (disable delete)
    get isSingleMapping() {
        return this.fieldMappings.length <= 1;
    }

    get hasExistingConfigs() {
        return this.existingConfigs.length > 0;
    }

    // Show field mapping section when related object is selected AND related expression is valid
    get showFieldMappingSection() {
        return this.hasSelectedRelatedObject && 
               this.hasRelatedExpression && 
               this.isRelatedExpressionValid;
    }
}