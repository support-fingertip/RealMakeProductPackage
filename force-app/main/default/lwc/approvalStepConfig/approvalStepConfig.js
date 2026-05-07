import { LightningElement, api, track } from 'lwc';

export default class ApprovalStepConfig extends LightningElement {
    
    @api userLookupOptions = [];
    
    @track steps = [];
    
    _stepsJson = '';
    
    // Approver type options
    approverTypeOptions = [
        { label: 'Field Path (Dynamic)', value: 'field' },
        { label: 'Specific User (Static)', value: 'user' }
    ];
    
    @api
    get stepsJson() {
        return this._stepsJson;
    }
    set stepsJson(value) {
        this._stepsJson = value;
        this.parseStepsJson(value);
    }
    
    get hasSteps() {
        return this.steps && this.steps.length > 0;
    }
    
    get stepCount() {
        return this.steps.length;
    }
    
    get isMaxSteps() {
        return this.steps.length >= 6;
    }
    
    parseStepsJson(jsonString) {
        var stepsList = [];
        var parsed;
        var i;
        var step;
        var approverType;
        var showFieldSelection;
        var showUserSelection;
        var selectionSummary;
        
        if (! jsonString) {
            this.steps = [];
            return;
        }
        
        try {
            parsed = JSON.parse(jsonString);
            
            if (parsed.steps && parsed.steps.length > 0) {
                for (i = 0; i < parsed.steps.length; i++) {
                    step = parsed.steps[i];
                    
                    // Determine approver type
                    approverType = step.approverType || 'field';
                    if (step.specificUserId && step.specificUserId.length > 0) {
                        approverType = 'user';
                    }
                    
                    showFieldSelection = (approverType === 'field');
                    showUserSelection = (approverType === 'user');
                    
                    // Build selection summary
                    selectionSummary = '';
                    if (approverType === 'field' && step.fieldLabel) {
                        selectionSummary = step.fieldLabel;
                    } else if (approverType === 'user' && step.specificUserName) {
                        selectionSummary = step.specificUserName;
                    }
                    
                    stepsList.push({
                        stepNumber: step.stepNumber || (i + 1),
                        stepName: step.stepName || '',
                        approverType: approverType,
                        fieldPath: step.fieldPath || '',
                        fieldLabel: step.fieldLabel || '',
                        specificUserId: step.specificUserId || '',
                        specificUserName: step.specificUserName || '',
                        showFieldSelection: showFieldSelection,
                        showUserSelection: showUserSelection,
                        selectionSummary: selectionSummary,
                        id: 'step-' + i,
                        index: i
                    });
                }
            }
            
            this.steps = stepsList;
        } catch (e) {
            this.steps = [];
        }
    }
    
    handleAddStep() {
        var newIndex;
        var newStep;
        var newSteps = [];
        var i;
        
        if (this.steps.length >= 6) {
            return;
        }
        
        newIndex = this.steps.length;
        
        newStep = {
            stepNumber:  newIndex + 1,
            stepName: '',
            approverType: 'field',
            fieldPath: '',
            fieldLabel: '',
            specificUserId:  '',
            specificUserName: '',
            showFieldSelection: true,
            showUserSelection: false,
            selectionSummary: '',
            id: 'step-' + newIndex,
            index: newIndex
        };
        
        for (i = 0; i < this.steps.length; i++) {
            newSteps.push(this.steps[i]);
        }
        newSteps.push(newStep);
        
        this.steps = newSteps;
        this.fireChangeEvent();
    }
    
    handleRemoveStep(event) {
        var indexToRemove = parseInt(event.target.dataset.index, 10);
        var newSteps = [];
        var newIndex = 0;
        var i;
        var step;
        
        for (i = 0; i < this.steps.length; i++) {
            if (i !== indexToRemove) {
                step = this.steps[i];
                newSteps.push({
                    stepNumber: newIndex + 1,
                    stepName: step.stepName,
                    approverType: step.approverType,
                    fieldPath: step.fieldPath,
                    fieldLabel: step.fieldLabel,
                    specificUserId: step.specificUserId,
                    specificUserName: step.specificUserName,
                    showFieldSelection: step.showFieldSelection,
                    showUserSelection: step.showUserSelection,
                    selectionSummary: step.selectionSummary,
                    id: 'step-' + newIndex,
                    index: newIndex
                });
                newIndex++;
            }
        }
        
        this.steps = newSteps;
        this.fireChangeEvent();
    }
    
    handleStepNameChange(event) {
        var index = parseInt(event.target.dataset.index, 10);
        var value = event.target.value;
        
        this.updateStepProperty(index, 'stepName', value);
        this.fireChangeEvent();
    }
    
    handleApproverTypeChange(event) {
        var index = parseInt(event.target.dataset.index, 10);
        var value = event.detail.value;
        var showFieldSelection = (value === 'field');
        var showUserSelection = (value === 'user');
        
        var newSteps = [];
        var i;
        var step;
        
        for (i = 0; i < this.steps.length; i++) {
            step = this.steps[i];
            if (i === index) {
                newSteps.push({
                    stepNumber: step.stepNumber,
                    stepName: step.stepName,
                    approverType: value,
                    fieldPath: showFieldSelection ? step.fieldPath :  '',
                    fieldLabel: showFieldSelection ? step.fieldLabel :  '',
                    specificUserId:  showUserSelection ? step.specificUserId : '',
                    specificUserName: showUserSelection ? step.specificUserName : '',
                    showFieldSelection: showFieldSelection,
                    showUserSelection: showUserSelection,
                    selectionSummary: '',
                    id: step.id,
                    index: step.index
                });
            } else {
                newSteps.push(step);
            }
        }

        this.steps = newSteps;
        this.fireChangeEvent();
    }

    handleFieldPathChange(event) {
        var index = parseInt(event.target.dataset.index, 10);
        var value = event.detail.value;
        var label = this.findFieldLabel(value);
        
        var newSteps = [];
        var i;
        var step;
        
        for (i = 0; i < this.steps.length; i++) {
            step = this.steps[i];
            if (i === index) {
                newSteps.push({
                    stepNumber: step.stepNumber,
                    stepName: step.stepName,
                    approverType: step.approverType,
                    fieldPath: value,
                    fieldLabel: label,
                    specificUserId: '',
                    specificUserName: '',
                    showFieldSelection: step.showFieldSelection,
                    showUserSelection: step.showUserSelection,
                    selectionSummary: label,
                    id: step.id,
                    index: step.index
                });
            } else {
                newSteps.push(step);
            }
        }

        this.steps = newSteps;
        this.fireChangeEvent();
    }

    handleUserChange(event) {
        var index = parseInt(event.target.dataset.index, 10);
        var recordId = event.detail.recordId;
        var self = this;
        
        // If user cleared the selection
        if (! recordId) {
            this.updateUserSelection(index, '', '');
            return;
        }
        
        // Get user name - we'll update the display after
        // For now, just set the ID and a placeholder name
        this.updateUserSelection(index, recordId, 'Loading...');
        
        // The record-picker doesn't give us the name directly
        // We need to query it or handle it differently
        // For simplicity, we'll just use the ID as display for now
        // In production, you might want to add an Apex call to get the user name
        this.updateUserSelection(index, recordId, 'User Selected');
    }
    
    updateUserSelection(index, userId, userName) {
        var newSteps = [];
        var i;
        var step;
        
        for (i = 0; i < this.steps.length; i++) {
            step = this.steps[i];
            if (i === index) {
                newSteps.push({
                    stepNumber: step.stepNumber,
                    stepName:  step.stepName,
                    approverType: step.approverType,
                    fieldPath:  '',
                    fieldLabel: '',
                    specificUserId: userId,
                    specificUserName: userName,
                    showFieldSelection:  step.showFieldSelection,
                    showUserSelection: step.showUserSelection,
                    selectionSummary: userName,
                    id: step.id,
                    index: step.index
                });
            } else {
                newSteps.push(step);
            }
        }

        this.steps = newSteps;
        this.fireChangeEvent();
    }

    updateStepProperty(index, propertyName, value) {
        var newSteps = [];
        var i;
        var step;
        var newStep;
        
        for (i = 0; i < this.steps.length; i++) {
            step = this.steps[i];
            if (i === index) {
                newStep = {
                    stepNumber: step.stepNumber,
                    stepName: step.stepName,
                    approverType: step.approverType,
                    fieldPath: step.fieldPath,
                    fieldLabel: step.fieldLabel,
                    specificUserId:  step.specificUserId,
                    specificUserName: step.specificUserName,
                    showFieldSelection: step.showFieldSelection,
                    showUserSelection: step.showUserSelection,
                    selectionSummary: step.selectionSummary,
                    id: step.id,
                    index: step.index
                };
                newStep[propertyName] = value;
                newSteps.push(newStep);
            } else {
                newSteps.push(step);
            }
        }
        
        this.steps = newSteps;
    }
    
    findFieldLabel(fieldPath) {
        var i;
        var opt;
        
        for (i = 0; i < this.userLookupOptions.length; i++) {
            opt = this.userLookupOptions[i];
            if (opt.value === fieldPath) {
                return opt.label;
            }
        }
        
        return fieldPath;
    }
    
    fireChangeEvent() {
        var stepsData = [];
        var i;
        var step;
        
        for (i = 0; i < this.steps.length; i++) {
            step = this.steps[i];
            stepsData.push({
                stepNumber: step.stepNumber,
                stepName: step.stepName,
                approverType: step.approverType,
                fieldPath: step.fieldPath,
                fieldLabel: step.fieldLabel,
                specificUserId: step.specificUserId,
                specificUserName:  step.specificUserName
            });
        }
        
        var stepsJson = JSON.stringify({
            numberOfSteps: this.steps.length,
            steps: stepsData
        });
        
        this.dispatchEvent(new CustomEvent('stepschange', {
            detail: { stepsJson: stepsJson }
        }));
    }
}