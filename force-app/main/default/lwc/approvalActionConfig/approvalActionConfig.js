import { LightningElement, api, track } from 'lwc';

export default class ApprovalActionConfig extends LightningElement {
    
    @api objectApiName = '';
    @api emailTemplates = [];
    @api emailConfigTemplates = [];

    // Email notification
    @track recipientOptions = [];
    @track emailEnabled = false;
    @track emailTemplateName = '';
    @track emailConfigTemplateId = '';
    @track selectedRecipients = [];
    @track additionalEmails = [];
    
    // Bell notification
    @track bellEnabled = false;
    @track bellTitle = '';
    @track bellBody = '';
    @track bellRecipientOptions = [];
    @track selectedBellRecipients = [];
    @track selectedMergeField = '';
    @track mergeFieldOptions = [];
    
    // Field updates
    @track fieldUpdateEnabled = false;
    @track fieldUpdates = [];
    
    // Chatter
    @track chatterEnabled = false;
    @track chatterMessage = '';
    
    _userLookupOptions = [];
    _allObjectFields = [];
    _actionJson = '';
    
    // ==================== API PROPERTIES ====================
    
    @api
    get userLookupOptions() {
        return this._userLookupOptions;
    }
    set userLookupOptions(value) {
        this._userLookupOptions = value || [];
        this.buildRecipientOptions();
        this.buildBellRecipientOptions();
    }
    
    @api
    get actionJson() {
        return this._actionJson;
    }
    set actionJson(value) {
        this._actionJson = value;
        this.parseActionJson(value);
    }
    
    @api
    get allObjectFields() {
        return this._allObjectFields;
    }
    set allObjectFields(value) {
        this._allObjectFields = value || [];
        this.buildMergeFieldOptions();
    }
    
    // ==================== GETTERS ====================
    
    get hasEmailConfigTemplates() {
        return this.emailConfigTemplates && this.emailConfigTemplates.length > 0;
    }

    get additionalEmailsString() {
        if (this.additionalEmails && this.additionalEmails.length > 0) {
            return this.additionalEmails.join(', ');
        }
        return '';
    }
    
    get hasFieldUpdates() {
        return this.fieldUpdates && this.fieldUpdates.length > 0;
    }
    
    get insertButtonDisabled() {
        return !this.selectedMergeField || this.selectedMergeField.length === 0;
    }
    
    // ==================== BUILD OPTIONS METHODS ====================
    
    buildRecipientOptions() {
        var options = [];
        var i;
        var opt;
        var isSelected;
        
        for (i = 0; i < this._userLookupOptions.length; i++) {
            opt = this._userLookupOptions[i];
            isSelected = this.isRecipientSelected(opt.value, this.selectedRecipients);
            
            options.push({
                label: opt.label,
                value: opt.value,
                selected: isSelected
            });
        }
        
        this.recipientOptions = options;
    }
    
    buildBellRecipientOptions() {
        var options = [];
        var i;
        var opt;
        var isSelected;
        
        for (i = 0; i < this._userLookupOptions.length; i++) {
            opt = this._userLookupOptions[i];
            isSelected = this.isRecipientSelected(opt.value, this.selectedBellRecipients);
            
            options.push({
                label: opt.label,
                value: opt.value,
                selected: isSelected
            });
        }
        
        this.bellRecipientOptions = options;
    }
    
    buildMergeFieldOptions() {
        var options = [];
        var i;
        var field;
        
        // Add standard fields header
        options.push({ label: '-- Standard Fields --', value: 'header_standard', disabled: true });
        options.push({ label: 'Record Name (Name)', value: 'Name' });
        options.push({ label: 'Record ID (Id)', value: 'Id' });
        options.push({ label: 'Created Date (CreatedDate)', value: 'CreatedDate' });
        options.push({ label: 'Last Modified Date (LastModifiedDate)', value: 'LastModifiedDate' });
        
        // Add custom fields from object
        if (this._allObjectFields && this._allObjectFields.length > 0) {
            options.push({ label: '-- Object Fields --', value: 'header_custom', disabled: true });
            
            for (i = 0; i < this._allObjectFields.length; i++) {
                field = this._allObjectFields[i];
                options.push({
                    label: field.label + ' (' + field.value + ')',
                    value:  field.value
                });
            }
        }
        
        this.mergeFieldOptions = options;
    }
    
    isRecipientSelected(value, recipientList) {
        var i;
        
        if (!recipientList || recipientList.length === 0) {
            return false;
        }
        
        for (i = 0; i < recipientList.length; i++) {
            if (recipientList[i] === value) {
                return true;
            }
        }
        
        return false;
    }
    
    // ==================== PARSE JSON ====================
    
    parseActionJson(jsonString) {
        var parsed;
        var i;
        var action;
        
        // Reset all values
        this.emailEnabled = false;
        this.emailTemplateName = '';
        this.emailConfigTemplateId = '';
        this.selectedRecipients = [];
        this.additionalEmails = [];
        
        this.bellEnabled = false;
        this.bellTitle = '';
        this.bellBody = '';
        this.selectedBellRecipients = [];
        
        this.fieldUpdateEnabled = false;
        this.fieldUpdates = [];
        
        this.chatterEnabled = false;
        this.chatterMessage = '';
        
        if (!jsonString) {
            this.buildRecipientOptions();
            this.buildBellRecipientOptions();
            return;
        }
        
        try {
            parsed = JSON.parse(jsonString);
            
            if (parsed.actions && parsed.actions.length > 0) {
                for (i = 0; i < parsed.actions.length; i++) {
                    action = parsed.actions[i];
                    
                    if (action.actionType === 'EMAIL_NOTIFICATION') {
                        this.parseEmailAction(action);
                    } else if (action.actionType === 'BELL_NOTIFICATION') {
                        this.parseBellAction(action);
                    } else if (action.actionType === 'FIELD_UPDATE') {
                        this.parseFieldUpdateAction(action);
                    } else if (action.actionType === 'CHATTER_POST') {
                        this.parseChatterAction(action);
                    }
                }
            }
        } catch (e) {
            console.error('Error parsing action JSON:', e);
        }
        
        this.buildRecipientOptions();
        this.buildBellRecipientOptions();
    }
    
    parseEmailAction(action) {
        this.emailEnabled = true;

        if (action.emailConfig) {
            this.emailTemplateName = action.emailConfig.templateDeveloperName || '';
            this.emailConfigTemplateId = action.emailConfig.emailConfigTemplateId || '';
            this.selectedRecipients = action.emailConfig.recipientFieldPaths || [];
            this.additionalEmails = action.emailConfig.additionalEmails || [];
        }
    }
    
    parseBellAction(action) {
        this.bellEnabled = true;
        
        if (action.bellConfig) {
            this.bellTitle = action.bellConfig.title || '';
            this.bellBody = action.bellConfig.body || '';
            this.selectedBellRecipients = action.bellConfig.recipientFieldPaths || [];
        }
    }
    
    parseFieldUpdateAction(action) {
        var updates = [];
        var i;
        var fu;
        
        this.fieldUpdateEnabled = true;
        
        if (action.fieldUpdates && action.fieldUpdates.length > 0) {
            for (i = 0; i < action.fieldUpdates.length; i++) {
                fu = action.fieldUpdates[i];
                updates.push({
                    fieldName: fu.fieldName || '',
                    value: fu.value !== undefined ? String(fu.value) : '',
                    id: 'field-' + i,
                    index: i
                });
            }
        }
        
        this.fieldUpdates = updates;
    }
    
    parseChatterAction(action) {
        this.chatterEnabled = true;
        this.chatterMessage = action.chatterMessage || '';
    }
    
    // ==================== EMAIL HANDLERS ====================
    
    handleEmailToggle(event) {
        this.emailEnabled = event.target.checked;

        if (! this.emailEnabled) {
            this.emailTemplateName = '';
            this.emailConfigTemplateId = '';
            this.selectedRecipients = [];
            this.additionalEmails = [];
            this.buildRecipientOptions();
        }

        this.fireChangeEvent();
    }
    
    handleEmailTemplateChange(event) {
        this.emailTemplateName = event.detail.value;
        this.fireChangeEvent();
    }

    handleEmailConfigTemplateChange(event) {
        this.emailConfigTemplateId = event.detail.value;
        this.fireChangeEvent();
    }
    
    handleRecipientToggle(event) {
        var value = event.target.dataset.value;
        var checked = event.target.checked;
        
        this.selectedRecipients = this.updateRecipientList(this.selectedRecipients, value, checked);
        this.buildRecipientOptions();
        this.fireChangeEvent();
    }
    
    handleAdditionalEmailsChange(event) {
        var value = event.target.value;
        var emails = [];
        var parts;
        var i;
        var trimmed;
        
        if (value) {
            parts = value.split(',');
            for (i = 0; i < parts.length; i++) {
                trimmed = parts[i].trim();
                if (trimmed) {
                    emails.push(trimmed);
                }
            }
        }
        
        this.additionalEmails = emails;
        this.fireChangeEvent();
    }
    
    // ==================== BELL NOTIFICATION HANDLERS ====================
    
    handleBellToggle(event) {
        this.bellEnabled = event.target.checked;
        
        if (!this.bellEnabled) {
            this.bellTitle = '';
            this.bellBody = '';
            this.selectedBellRecipients = [];
            this.selectedMergeField = '';
            this.buildBellRecipientOptions();
        }
        
        this.fireChangeEvent();
    }
    
    handleBellTitleChange(event) {
        this.bellTitle = event.target.value;
        this.fireChangeEvent();
    }
    
    handleBellBodyChange(event) {
        this.bellBody = event.target.value;
        this.fireChangeEvent();
    }
    
    handleBellRecipientToggle(event) {
        var value = event.target.dataset.value;
        var checked = event.target.checked;
        
        this.selectedBellRecipients = this.updateRecipientList(this.selectedBellRecipients, value, checked);
        this.buildBellRecipientOptions();
        this.fireChangeEvent();
    }
    
    // ==================== MERGE FIELD HANDLERS ====================
    
    handleMergeFieldChange(event) {
        this.selectedMergeField = event.detail.value;
    }
    
    handleInsertInTitle() {
        if (! this.selectedMergeField) {
            return;
        }
        
        // Skip if header option selected
        if (this.selectedMergeField.startsWith('header_')) {
            return;
        }
        
        var mergeText = '{' + this.selectedMergeField + '}';
        var currentTitle = this.bellTitle || '';
        this.bellTitle = currentTitle + mergeText;
        this.selectedMergeField = '';
        this.fireChangeEvent();
    }
    
    handleInsertInBody() {
        if (!this.selectedMergeField) {
            return;
        }
        
        // Skip if header option selected
        if (this.selectedMergeField.startsWith('header_')) {
            return;
        }
        
        var mergeText = '{' + this.selectedMergeField + '}';
        var currentBody = this.bellBody || '';
        this.bellBody = currentBody + mergeText;
        this.selectedMergeField = '';
        this.fireChangeEvent();
    }

    // ==================== FIELD UPDATE HANDLERS ====================
    
    handleFieldUpdateToggle(event) {
        this.fieldUpdateEnabled = event.target.checked;
        
        if (!this.fieldUpdateEnabled) {
            this.fieldUpdates = [];
        }
        
        this.fireChangeEvent();
    }
    
    handleAddFieldUpdate() {
        var newIndex = this.fieldUpdates.length;
        var newUpdates = [];
        var i;
        
        for (i = 0; i < this.fieldUpdates.length; i++) {
            newUpdates.push(this.fieldUpdates[i]);
        }
        
        newUpdates.push({
            fieldName: '',
            value: '',
            id: 'field-' + newIndex,
            index: newIndex
        });
        
        this.fieldUpdates = newUpdates;
        this.fireChangeEvent();
    }

    handleRemoveFieldUpdate(event) {
        var indexToRemove = parseInt(event.target.dataset.index, 10);
        var newUpdates = [];
        var newIndex = 0;
        var i;
        var fu;
        
        for (i = 0; i < this.fieldUpdates.length; i++) {
            if (i !== indexToRemove) {
                fu = this.fieldUpdates[i];
                newUpdates.push({
                    fieldName: fu.fieldName,
                    value: fu.value,
                    id: 'field-' + newIndex,
                    index: newIndex
                });
                newIndex++;
            }
        }
        
        this.fieldUpdates = newUpdates;
        this.fireChangeEvent();
    }
    
    handleFieldNameChange(event) {
        var index = parseInt(event.target.dataset.index, 10);
        var value = event.target.value;
        
        this.updateFieldUpdate(index, 'fieldName', value);
        this.fireChangeEvent();
    }
    
    handleFieldValueChange(event) {
        var index = parseInt(event.target.dataset.index, 10);
        var value = event.target.value;

        this.updateFieldUpdate(index, 'value', value);
        this.fireChangeEvent();
    }
    
    updateFieldUpdate(index, propertyName, value) {
        var newUpdates = [];
        var i;
        var fu;
        var newFu;
        
        for (i = 0; i < this.fieldUpdates.length; i++) {
            fu = this.fieldUpdates[i];
            if (i === index) {
                newFu = {
                    fieldName: fu.fieldName,
                    value: fu.value,
                    id: fu.id,
                    index: fu.index
                };
                newFu[propertyName] = value;
                newUpdates.push(newFu);
            } else {
                newUpdates.push(fu);
            }
        }
        
        this.fieldUpdates = newUpdates;
    }
    
    // ==================== CHATTER HANDLERS ====================
    
    handleChatterToggle(event) {
        this.chatterEnabled = event.target.checked;
        
        if (!this.chatterEnabled) {
            this.chatterMessage = '';
        }
        
        this.fireChangeEvent();
    }
    
    handleChatterMessageChange(event) {
        this.chatterMessage = event.target.value;
        this.fireChangeEvent();
    }
    
    // ==================== UTILITY METHODS ====================
    
    updateRecipientList(currentList, value, add) {
        var newList = [];
        var i;
        var found = false;
        
        for (i = 0; i < currentList.length; i++) {
            if (currentList[i] === value) {
                found = true;
                if (add) {
                    newList.push(currentList[i]);
                }
            } else {
                newList.push(currentList[i]);
            }
        }
        
        if (add && !found) {
            newList.push(value);
        }
        
        return newList;
    }
    
    // ==================== FIRE CHANGE EVENT ====================
    
    fireChangeEvent() {
        var actions = [];
        var i;
        var fu;
        var validUpdates;
        
        // Email action
        if (this.emailEnabled) {
            actions.push({
                actionType: 'EMAIL_NOTIFICATION',
                emailConfig: {
                    templateDeveloperName: this.emailTemplateName,
                    emailConfigTemplateId: this.emailConfigTemplateId,
                    recipientFieldPaths: this.selectedRecipients,
                    additionalEmails: this.additionalEmails
                }
            });
        }
        
        // Bell notification action
        if (this.bellEnabled) {
            actions.push({
                actionType: 'BELL_NOTIFICATION',
                bellConfig: {
                    title:  this.bellTitle,
                    body: this.bellBody,
                    recipientFieldPaths:  this.selectedBellRecipients
                }
            });
        }
        
        // Field update action
        if (this.fieldUpdateEnabled && this.fieldUpdates.length > 0) {
            validUpdates = [];
            
            for (i = 0; i < this.fieldUpdates.length; i++) {
                fu = this.fieldUpdates[i];
                if (fu.fieldName && fu.value) {
                    validUpdates.push({
                        fieldName: fu.fieldName,
                        value: fu.value
                    });
                }
            }
            
            if (validUpdates.length > 0) {
                actions.push({
                    actionType: 'FIELD_UPDATE',
                    fieldUpdates: validUpdates
                });
            }
        }
        
        // Chatter action
        if (this.chatterEnabled && this.chatterMessage) {
            actions.push({
                actionType: 'CHATTER_POST',
                chatterMessage:  this.chatterMessage
            });
        }
        
        var actionJson = JSON.stringify({ actions: actions });
        
        this.dispatchEvent(new CustomEvent('actionchange', {
            detail: { actionJson: actionJson }
        }));
    }
}