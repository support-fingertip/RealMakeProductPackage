import { LightningElement, api, track } from 'lwc';
import getPicklistValues from '@salesforce/apex/FormulaBuilderController.getPicklistValues';

export default class StepBuilder extends LightningElement {
    @api step;
    @api availableFields;
    @api bookingFields;
    @api existingVariables;

    
    @track isLoading = false;
    @track picklistFieldsMap = {}; // Store picklist values for fields
    @track showPicklistSelector = false;
    @track currentPicklistField = '';
    @track currentPicklistTarget = ''; // 'left', 'right', 'true', or 'false'
    @track picklistOptions = [];
    @track localStep = {};
    @track showIfConditionBuilder = false;
    @track ifCondition = {};
    
    // Calculator variables
    @track calculatorInputs = [];
    @track calculatorValues = {};
    @track calculatorResult = null;
    @track calculatorError = null;

    numberButtons = ['7', '8', '9', '4', '5', '6', '1', '2', '3', '0', '.'];
    
    comparisonOperators = [
        { label: 'Equal (==)', value: '==' },
        { label: 'Not Equal (!=)', value: '!=' },
        { label: 'Greater Than (>)', value: '>' },
        { label: 'Less Than (<)', value: '<' },
        { label: 'Greater or Equal (>=)', value: '>=' },
        { label: 'Less or Equal (<=)', value: '<=' }
    ];

    connectedCallback() {
        this.isLoading = true;
        this.localStep = { ...this.step };
        if(!this.localStep.formula) {
            this.localStep.formula = '';
        }
        this.updateVariableNameFromLabel();
        this.resetIfCondition();
        this.loadPicklistValues();
        this.isLoading = false;
    }

    get formulaPreview() {
        return this.localStep.formula || 'No formula yet...';
    }

    get variableNamePreview() {
        return this.localStep.variableName || 'stepVariable';
    }

    get hasExistingVariables() {
        return this.existingVariables && this.existingVariables.length > 0;
    }

    get conditionFieldOptions() {
        const combined = [
            ...this.availableFields,
            ...(this.existingVariables || []).map(v => ({ label: v, value: v }))
        ];
        return combined;
    }

    get ifConditionPreview() {
        if(this.ifCondition.leftValue && this.ifCondition.operator && 
           this.ifCondition.rightValue && this.ifCondition.trueValue && 
           this.ifCondition.falseValue) {
            return `IF(${this.ifCondition.leftValue} ${this.ifCondition.operator} ${this.ifCondition.rightValue}, ${this.ifCondition.trueValue}, ${this.ifCondition.falseValue})`;
        }
        return 'Fill all fields to see preview';
    }

    // Calculator getters
    get hasFormulaToTest() {
        return this.localStep.formula && this.localStep.formula.trim() !== '';
    }

    handleStepLabelChange(event) {
        this.localStep.stepLabel = event.detail.value;
        this.updateVariableNameFromLabel();
    }

    loadPicklistValues() {
        // Check which fields are picklists and load their values
        if(this.availableFields && this.availableFields.length > 0) {
            this.availableFields.forEach(field => {
                if(field.type === 'PICKLIST') {
                    // Extract object and field API from label or store separately
                    // For now, we'll load on-demand when user selects a picklist field
                }
            });
        }
    }

    updateVariableNameFromLabel() {
        if(this.localStep.stepLabel) {
            // Convert "Basic Price" to "basicPrice"
            // Convert "Total With GST" to "totalWithGST"
            let varName = this.localStep.stepLabel
                .trim()
                .split(/\s+/) // Split by spaces
                .map((word, index) => {
                    word = word.replace(/[^a-zA-Z0-9]/g, ''); // Remove special chars
                    if(index === 0) {
                        return word.charAt(0).toLowerCase() + word.slice(1);
                    }
                    return word.charAt(0).toUpperCase() + word.slice(1);
                })
                .join('');
            
            this.localStep.variableName = varName || 'stepVariable';
        } else {
            this.localStep.variableName = '';
        }
    }

    handleDescriptionChange(event) {
        this.localStep.description = event.detail.value;
    }

    handleStoreFieldChange(event) {
        this.localStep.storeInField = event.detail.value;
    }

    handleFieldSelect(event) {
        const fieldName = event.detail.value;
        if(fieldName) {
            this.appendToFormula(fieldName);
            this.updateCalculatorInputs();
        }
    }

    handleOperatorClick(event) {
        const operator = event.target.dataset.value;
        this.appendToFormula(' ' + operator + ' ');
    }

    handleNumberClick(event) {
        const number = event.target.dataset.value;
        this.appendToFormula(number);
    }

    handleVariableClick(event) {
        const variable = event.target.dataset.value;
        this.appendToFormula(variable);
        this.updateCalculatorInputs();
    }

    appendToFormula(text) {
        this.localStep.formula = (this.localStep.formula || '') + text;
        this.updateCalculatorInputs();
    }

    handleClearFormula() {
        this.localStep.formula = '';
        this.calculatorInputs = [];
        this.calculatorValues = {};
        this.calculatorResult = null;
        this.calculatorError = null;
    }

    handleToggleIfCondition() {
        this.showIfConditionBuilder = !this.showIfConditionBuilder;
        if(this.showIfConditionBuilder) {
            this.resetIfCondition();
        }
    }

    resetIfCondition() {
        this.ifCondition = {
            leftValue: '',
            operator: '==',
            rightValue: '',
            trueValue: '',
            falseValue: ''
        };
    }

    handleIfLeftChange(event) {
        this.ifCondition.leftValue = event.detail.value;
        
        // Check if selected field is a picklist
        const selectedField = this.conditionFieldOptions.find(f => f.value === event.detail.value);
        if(selectedField && selectedField.type === 'PICKLIST') {
            // Load picklist values for Right Value dropdown
            this.loadPicklistForField(event.detail.value, 'right');
        }
    }

    loadPicklistForField(fieldAPI, target) {
        // Determine which object this field belongs to
        // For now, we'll try target object first, then source
        const targetObjectAPI = this.localStep.targetObject || '';
        
        getPicklistValues({ 
            objectAPI: targetObjectAPI, 
            fieldAPI: fieldAPI 
        })
            .then(result => {
                this.picklistFieldsMap[fieldAPI] = result;
                
                // Show picklist selector modal or update dropdown
                if(target === 'right') {
                    this.currentPicklistField = fieldAPI;
                    this.currentPicklistTarget = 'right';
                    this.picklistOptions = result.map(pv => ({
                        label: pv.label,
                        value: '"' + pv.value + '"' // Wrap in quotes for formula
                    }));
                }
            })
            .catch(error => {
                console.error('Error loading picklist values:', error);
            });
    }

    get showPicklistForRight() {
        return this.picklistOptions && this.picklistOptions.length > 0;
    }

    handleIfOperatorChange(event) {
        this.ifCondition.operator = event.detail.value;
    }

    handleIfRightChange(event) {
        this.ifCondition.rightValue = event.detail.value;
    }

    handleIfTrueChange(event) {
        this.ifCondition.trueValue = event.detail.value;
    }

    handleIfFalseChange(event) {
        this.ifCondition.falseValue = event.detail.value;
    }

    handleInsertTrueVariable(event) {
        const variable = event.target.dataset.value;
        this.ifCondition.trueValue = variable;
    }

    handleInsertFalseVariable(event) {
        const variable = event.target.dataset.value;
        this.ifCondition.falseValue = variable;
    }

    handleInsertIfCondition() {
        const ifStatement = this.ifConditionPreview;
        if(ifStatement !== 'Fill all fields to see preview') {
            this.appendToFormula(ifStatement);
            this.showIfConditionBuilder = false;
            this.resetIfCondition();
        } else {
            alert('Please fill all IF condition fields');
        }
    }

    handleCancelIfCondition() {
        this.showIfConditionBuilder = false;
        this.resetIfCondition();
    }

    // ============ CALCULATOR METHODS ============
    
    updateCalculatorInputs() {
        // Extract all field names and variables from formula
        const formula = this.localStep.formula || '';
        const fieldPattern = /\b([A-Za-z][A-Za-z0-9_]*(__c)?)\b/g;
        const matches = formula.match(fieldPattern) || [];
        
        // Filter out operators, numbers, and duplicates
        const operators = ['IF', 'AND', 'OR', 'NOT'];
        const uniqueFields = [...new Set(matches)].filter(field => {
            return !operators.includes(field) && 
                   isNaN(field) && 
                   field !== 'true' && 
                   field !== 'false';
        });
        
        // Create input fields for each unique field/variable
        this.calculatorInputs = uniqueFields.map(field => {
            // Get friendly label from availableFields or use field name
            let label = field;
            const fieldOption = this.availableFields.find(f => f.value === field);
            if(fieldOption) {
                label = fieldOption.label;
            } else if(this.existingVariables && this.existingVariables.includes(field)) {
                label = field + ' (Previous Step)';
            }
            
            return {
                name: field,
                label: label,
                value: this.calculatorValues[field] || ''
            };
        });
    }

    handleCalculatorInputChange(event) {
        const fieldName = event.target.dataset.field;
        const value = event.target.value;
        this.calculatorValues[fieldName] = value;
        
        // Clear previous result/error
        this.calculatorResult = null;
        this.calculatorError = null;
    }

    handleCalculateTest() {
        try {
            // Reset result and error
            this.calculatorResult = null;
            this.calculatorError = null;
            
            // Get formula
            let formula = this.localStep.formula;
            
            if(!formula || formula.trim() === '') {
                this.calculatorError = 'No formula to calculate';
                return;
            }
            
            // Replace all field names with their values
            for(const field of this.calculatorInputs) {
                const value = this.calculatorValues[field.name];
                
                if(!value || value.trim() === '') {
                    this.calculatorError = `Please enter a value for ${field.label}`;
                    return;
                }
                
                // Replace field with its numeric value
                // Use word boundary to avoid partial replacements
                const regex = new RegExp('\\b' + field.name + '\\b', 'g');
                formula = formula.replace(regex, value);
            }
            
            // Evaluate the formula
            const result = this.evaluateFormula(formula);
            
            // Format result
            this.calculatorResult = this.formatNumber(result);
            
        } catch(error) {
            this.calculatorError = 'Calculation error: ' + error.message;
        }
    }

    evaluateFormula(formula) {
        // Clean up formula for evaluation
        formula = formula.trim();
        
        // Handle IF conditions
        formula = this.handleIfConditions(formula);
        
        // Replace operators for JavaScript evaluation
        formula = formula.replace(/×/g, '*');
        formula = formula.replace(/÷/g, '/');
        formula = formula.replace(/−/g, '-');
        
        // Evaluate using Function constructor (safer than eval)
        try {
            const result = new Function('return ' + formula)();
            return result;
        } catch(error) {
            throw new Error('Invalid formula: ' + error.message);
        }
    }

    handleIfConditions(formula) {
        // Simple IF condition handler
        // IF(condition, trueValue, falseValue)
        const ifPattern = /IF\s*\((.*?)\s*,\s*(.*?)\s*,\s*(.*?)\)/gi;
        let maxIterations = 10; // Prevent infinite loops for deeply nested IFs

        while(ifPattern.test(formula) && maxIterations > 0) {
            ifPattern.lastIndex = 0; // Reset lastIndex after test()
            formula = formula.replace(ifPattern, (match, condition, trueVal, falseVal) => {
                const conditionResult = this.evaluateCondition(condition);
                return conditionResult ? trueVal : falseVal;
            });
            ifPattern.lastIndex = 0; // Reset for next test()
            maxIterations--;
        }

        return formula;
    }

    evaluateCondition(condition) {
        // Handle comparison operators
        condition = condition.replace(/×/g, '*');
        condition = condition.replace(/÷/g, '/');
        condition = condition.replace(/−/g, '-');
        
        try {
            return new Function('return ' + condition)();
        } catch(error) {
            throw new Error('Invalid condition: ' + error.message);
        }
    }

    formatNumber(num) {
        if(num === null || num === undefined) {
            return '0';
        }
        
        // Round to 2 decimal places and format with commas
        const rounded = Math.round(num * 100) / 100;
        return rounded.toLocaleString('en-IN', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    // ============ END CALCULATOR METHODS ============

    handleSave() {
        if(!this.localStep.stepLabel || !this.localStep.formula) {
            alert('Step Label and Formula are required');
            return;
        }

        this.dispatchEvent(new CustomEvent('save', {
            detail: this.localStep
        }));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
}