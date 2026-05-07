import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

// List Apex methods
import getAllTemplates from '@salesforce/apex/EmailTemplateConfigController.getAllTemplates';
import deleteTemplate from '@salesforce/apex/EmailTemplateConfigController.deleteTemplate';
import toggleActiveStatus from '@salesforce/apex/EmailTemplateConfigController.toggleActiveStatus';
import cloneTemplate from '@salesforce/apex/EmailTemplateConfigController.cloneTemplate';

// Builder Apex methods
import getAllObjects from '@salesforce/apex/EmailFieldPickerController.getAllObjects';
import getOrgWideEmailAddresses from '@salesforce/apex/EmailFieldPickerController.getOrgWideEmailAddresses';
import searchRecords from '@salesforce/apex/EmailFieldPickerController.searchRecords';
import getTemplateById from '@salesforce/apex/EmailTemplateConfigController.getTemplateById';
import saveTemplate from '@salesforce/apex/EmailTemplateConfigController.saveTemplate';
import prepareEmailFromTemplate from '@salesforce/apex/EmailSenderController.prepareEmailFromTemplate';
import getAllDocTemplates from '@salesforce/apex/DocumentDesignerController.getAllTemplates';

export default class EmailTemplateList extends NavigationMixin(LightningElement) {
    
    // ============ LIST VIEW PROPERTIES ============
    @track isLoading = true;
    @track templates = [];
    @track filteredTemplates = [];
    @track searchTerm = '';
    @track selectedObjectFilter = '';
    @track objectOptions = [];
    
    // Delete confirmation
    @track showDeleteModal = false;
    @track deleteTemplateId = null;
    @track deleteTemplateName = '';
    
    // ============ BUILDER VIEW PROPERTIES ============
    @track showBuilder = false;
    @track isBuilderLoading = false;
    @track isSaving = false;
    @track editTemplateId = null;
    
    // Builder Data
    @track objects = [];
    @track orgWideEmails = [];
    
    // Template fields
    @track templateName = '';
    @track selectedObject = '';
    @track description = '';
    @track isActive = true;
    @track isDefault = false;
    @track subject = '';
    @track emailBody = '';
    @track fromAddress = '';
    @track replyTo = '';
    @track allowAdditionalRecipients = true;
    @track allowFileUpload = true;
    @track selectedDocumentTemplateId = '';
    @track documentTemplateOptions = [];
    @track selectedMergeField = '';
    
    // Recipients & Attachments
    @track recipients = [];
    @track attachments = [];
    
    // Preview
    @track showPreviewModal = false;
    @track previewRecordId = '';
    @track previewRecordOptions = [];
    @track previewSearchTerm = '';
    @track previewData = null;
    @track isPreviewLoading = false;
    
    // Current step
    @track currentStep = '1';
    
    // Step 5: Actions & Matching
    @track actionBinding = '';
    @track matchingCriteria = '';

    steps = [
        { label: 'Basic Info', value: '1' },
        { label: 'Recipients', value: '2' },
        { label: 'Content', value: '3' },
        { label: 'Attachments', value: '4' },
        { label: 'Actions & Matching', value: '5' }
    ];

    actionBindingOptions = [
        { label: 'Demand Raiser', value: 'Demand Raiser' }
    ];
    
    // Columns for data table
    columns = [
        { 
            label: 'Template Name', 
            fieldName: 'name', 
            type: 'text',
            sortable: true,
            cellAttributes: { class: 'slds-text-title_bold' }
        },
        { 
            label: 'Object', 
            fieldName: 'objectApiName', 
            type: 'text',
            sortable: true
        },
        { 
            label:  'Active', 
            fieldName: 'isActive', 
            type: 'boolean',
            cellAttributes: { alignment: 'center' }
        },
        { 
            label: 'Default', 
            fieldName: 'isDefault', 
            type: 'boolean',
            cellAttributes: { alignment: 'center' }
        },
        { 
            label:  'Created Date', 
            fieldName: 'createdDate', 
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month:  'short',
                day:  '2-digit'
            }
        },
        {
            type: 'action',
            typeAttributes: { rowActions: this.getRowActions }
        }
    ];
    
    // ============ LIFECYCLE ============
    
    connectedCallback() {
        this.loadTemplates();
    }

    @api
    refresh() {
        this.loadTemplates();
    }

    // ============ LIST VIEW METHODS ============
    
    async loadTemplates() {
        try {
            this.isLoading = true;
            const data = await getAllTemplates();
            this.templates = data.map(t => ({
                ...t,
                createdDateFormatted: t.createdDate ? new Date(t.createdDate).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: '2-digit' }) : ''
            }));
            this.filteredTemplates = [...this.templates];
            this.buildObjectOptions();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    buildObjectOptions() {
        const objectSet = new Set();
        this.templates.forEach(t => {
            if (t.objectApiName) {
                objectSet.add(t.objectApiName);
            }
        });
        
        this.objectOptions = [
            { label:  'All Objects', value: '' },
            ... Array.from(objectSet).sort().map(obj => ({
                label: obj,
                value: obj
            }))
        ];
    }
    
    getRowActions(row, doneCallback) {
        const actions = [
            { label: 'Edit', name: 'edit', iconName: 'utility:edit' },
            { label: 'Clone', name: 'clone', iconName:  'utility:copy' },
            { label: 'Preview', name: 'preview', iconName:  'utility:preview' }
        ];
        
        if (row.isActive) {
            actions.push({ label: 'Deactivate', name: 'deactivate', iconName: 'utility:clear' });
        } else {
            actions.push({ label: 'Activate', name: 'activate', iconName: 'utility:check' });
        }
        
        actions.push({ label: 'Delete', name: 'delete', iconName: 'utility:delete' });
        
        doneCallback(actions);
    }
    
    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        
        switch (action.name) {
            case 'edit':
                this.handleEdit(row.id);
                break;
            case 'clone':
                this.handleClone(row.id);
                break;
            case 'preview': 
                this.handlePreview(row.id);
                break;
            case 'activate':
                this.handleToggleActive(row.id, true);
                break;
            case 'deactivate': 
                this.handleToggleActive(row.id, false);
                break;
            case 'delete':
                this.handleDelete(row.id, row.name);
                break;
        }
    }
    
    handleEditRow(event) {
        var templateId = event.currentTarget.dataset.id;
        this.handleEdit(templateId);
    }

    handleCloneRow(event) {
        var templateId = event.currentTarget.dataset.id;
        this.handleClone(templateId);
    }

    handleDeleteRow(event) {
        var templateId = event.currentTarget.dataset.id;
        var templateName = event.currentTarget.dataset.name;
        this.handleDelete(templateId, templateName);
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value.toLowerCase();
        this.filterTemplates();
    }
    
    handleObjectFilter(event) {
        this.selectedObjectFilter = event.detail.value;
        this.filterTemplates();
    }
    
    filterTemplates() {
        this.filteredTemplates = this.templates.filter(template => {
            const matchesSearch = !this.searchTerm ||
                template.name.toLowerCase().includes(this.searchTerm) ||
                (template.objectApiName || '').toLowerCase().includes(this.searchTerm);
            
            const matchesObject = !this.selectedObjectFilter || 
                template.objectApiName === this.selectedObjectFilter;
            
            return matchesSearch && matchesObject;
        });
    }
    
    handleNewTemplate() {
        this.editTemplateId = null;
        this.resetBuilderForm();
        this.showBuilder = true;
        this.loadBuilderData();
    }

    handleEdit(templateId) {
        this.editTemplateId = templateId;
        this.resetBuilderForm();
        this.showBuilder = true;
        this.loadBuilderData();
    }
    
    async handleClone(templateId) {
        try {
            this.isLoading = true;
            await cloneTemplate({ templateId });
            this.showToast('Success', 'Template cloned successfully', 'success');
            await this.loadTemplates();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handlePreview(templateId) {
        this.handleEdit(templateId);
    }
    
    async handleToggleActive(templateId, isActive) {
        try {
            this.isLoading = true;
            await toggleActiveStatus({ templateId, isActive });
            this.showToast('Success', `Template ${isActive ? 'activated' : 'deactivated'}`, 'success');
            await this.loadTemplates();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleDelete(templateId, templateName) {
        this.deleteTemplateId = templateId;
        this.deleteTemplateName = templateName;
        this.showDeleteModal = true;
    }
    
    closeDeleteModal() {
        this.showDeleteModal = false;
        this.deleteTemplateId = null;
        this.deleteTemplateName = '';
    }
    
    async confirmDelete() {
        try {
            this.isLoading = true;
            await deleteTemplate({ templateId: this.deleteTemplateId });
            this.showToast('Success', 'Template deleted successfully', 'success');
            this.closeDeleteModal();
            await this.loadTemplates();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // ============ BUILDER METHODS ============
    
    async loadBuilderData() {
        try {
            this.isBuilderLoading = true;
            
            const [objectsData, emailsData, docTemplates] = await Promise.all([
                getAllObjects(),
                getOrgWideEmailAddresses(),
                getAllDocTemplates()
            ]);
            
            this.objects = objectsData.map(obj => ({
                label: obj.label,
                value: obj.value
            }));
            
            this.orgWideEmails = [
                { label: '-- None --', value: '' },
                ...emailsData.map(email => ({
                    label: email.label,
                    value: email.value
                }))
            ];

            this.documentTemplateOptions = [
                { label: '-- None --', value: '' },
                ...(docTemplates || []).filter(t => t.isActive).map(t => ({
                    label: t.name,
                    value: t.id
                }))
            ];
            
            if (this.editTemplateId) {
                await this.loadTemplate();
            } else {
                this.addRecipientRow();
            }
            
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isBuilderLoading = false;
        }
    }
    
    async loadTemplate() {
        try {
            const template = await getTemplateById({ templateId: this.editTemplateId });
            
            this.templateName = template.name || '';
            this.selectedObject = template.objectApiName || '';
            this.description = template.description || '';
            this.isActive = template.isActive !== false;
            this.isDefault = template.isDefault === true;
            this.subject = template.subject || '';
            this.emailBody = template.emailBody || '';
            this.fromAddress = template.fromAddress || '';
            this.replyTo = template.replyTo || '';
            this.allowAdditionalRecipients = template.allowAdditionalRecipients !== false;
            this.allowFileUpload = template.allowFileUpload !== false;
            this.selectedDocumentTemplateId = template.documentTemplateId || '';
            this.actionBinding = template.actionBinding || '';
            this.matchingCriteria = template.matchingCriteria || '';

            if (template.recipientsConfig) {
                this.parseRecipientsConfig(template.recipientsConfig);
            }
            
            if (template.attachmentsConfig) {
                this.parseAttachmentsConfig(template.attachmentsConfig);
            }
            
            if (this.recipients.length === 0) {
                this.addRecipientRow();
            }
            
        } catch (error) {
            this.showToast('Error', 'Failed to load template:  ' + this.reduceErrors(error), 'error');
        }
    }
    
    parseRecipientsConfig(configJson) {
        try {
            const config = JSON.parse(configJson);
            this.recipients = [];
            let index = 0;
            
            ['to', 'cc', 'bcc'].forEach(type => {
                if (config[type] && Array.isArray(config[type])) {
                    config[type].forEach(rec => {
                        this.recipients.push({
                            id: rec.id || this.generateId(),
                            index: index++,
                            type:  type,
                            sourceType: rec.sourceType || 'Field',
                            fieldApiName: rec.fieldApiName || '',
                            staticEmail: rec.staticEmail || '',
                            label: rec.label || '',
                            isRequired: rec.isRequired === true,
                            isEditable: rec.isEditable !== false
                        });
                    });
                }
            });
        } catch (e) {
            console.error('Error parsing recipients config:', e);
        }
    }
    
    parseAttachmentsConfig(configJson) {
        try {
            const config = JSON.parse(configJson);
            this.attachments = [];

            if (config.attachments && Array.isArray(config.attachments)) {
                config.attachments.forEach((att, index) => {
                    this.attachments.push({
                        id:  att.id || this.generateId(),
                        index: index,
                        name: att.name || '',
                        type: att.type || 'VFPage',
                        vfPageName: att.vfPageName || '',
                        vfPageParam: att.vfPageParam || 'id',
                        documentId: att.documentId || '',
                        documentTemplateId: att.documentTemplateId || '',
                        fileNamePattern: att.fileNamePattern || '',
                        isDefaultChecked: att.isDefaultChecked === true,
                        isRequired: att.isRequired === true,
                        recordSourceType: att.recordSourceType || 'Direct',
                        selectedRelationship: att.selectedRelationship || '',
                        relationshipType: att.relationshipType || '',
                        relationshipName: att.relationshipName || '',
                        relatedObjectApi: att.relatedObjectApi || '',
                        childRecordType: att.childRecordType || 'All',
                        filterConditionsJson: att.filterConditionsJson || '[]',
                        maxChildRecords: att.maxChildRecords || 10,
                        orderByField: att.orderByField || '',
                        orderByDirection: att.orderByDirection || 'ASC',
                        singleChildLimit: att.singleChildLimit || 1
                    });
                });
            }
        } catch (e) {
            console.error('Error parsing attachments config:', e);
        }
    }
    
    resetBuilderForm() {
        this.currentStep = '1';
        this.templateName = '';
        this.selectedObject = '';
        this.description = '';
        this.isActive = true;
        this.isDefault = false;
        this.subject = '';
        this.emailBody = '';
        this.fromAddress = '';
        this.replyTo = '';
        this.allowAdditionalRecipients = true;
        this.allowFileUpload = true;
        this.selectedDocumentTemplateId = '';
        this.selectedMergeField = '';
        this.actionBinding = '';
        this.matchingCriteria = '';
        this.recipients = [];
        this.attachments = [];
        this.previewData = null;
        this.previewRecordId = '';
        this.previewRecordOptions = [];
        this.previewSearchTerm = '';
    }

    handleBuilderCancel() {
        this.showBuilder = false;
        this.editTemplateId = null;
        this.resetBuilderForm();
    }
    
    // ============ STEP NAVIGATION ============
    
    handleStepClick(event) {
        const step = event.currentTarget.dataset.step;
        if (this.canNavigateToStep(step)) {
            this.currentStep = step;
        }
    }
    
    canNavigateToStep(step) {
        if (parseInt(step) < parseInt(this.currentStep)) {
            return true;
        }
        return this.validateCurrentStep();
    }
    
    handleNext() {
        if (this.validateCurrentStep()) {
            const nextStep = String(parseInt(this.currentStep) + 1);
            if (nextStep <= '5') {
                this.currentStep = nextStep;
            }
        }
    }
    
    handlePrevious() {
        const prevStep = String(parseInt(this.currentStep) - 1);
        if (prevStep >= '1') {
            this.currentStep = prevStep;
        }
    }
    
    validateCurrentStep() {
        switch (this.currentStep) {
            case '1':
                return this.validateBasicInfo();
            case '2': 
                return this.validateRecipients();
            case '3': 
                return this.validateContent();
            case '4':
                return true;
            case '5':
                return true;
            default:
                return true;
        }
    }
    
    validateBasicInfo() {
        if (!this.templateName || !this.templateName.trim()) {
            this.showToast('Validation Error', 'Template Name is required', 'error');
            return false;
        }
        if (!this.selectedObject) {
            this.showToast('Validation Error', 'Object is required', 'error');
            return false;
        }
        return true;
    }
    
    validateRecipients() {
        const hasTo = this.recipients.some(r => r.type === 'to' && (r.fieldApiName || r.staticEmail || ['CurrentUser', 'RecordOwner', 'OwnerManager'].includes(r.sourceType)));
        if (!hasTo) {
            this.showToast('Validation Error', 'At least one TO recipient is required', 'error');
            return false;
        }
        return true;
    }
    
    validateContent() {
        if (!this.subject || !this.subject.trim()) {
            this.showToast('Validation Error', 'Subject is required', 'error');
            return false;
        }
        if (!this.emailBody || !this.emailBody.trim()) {
            this.showToast('Validation Error', 'Email body is required', 'error');
            return false;
        }
        return true;
    }
    
    // ============ BASIC INFO HANDLERS ============
    
    handleTemplateNameChange(event) {
        this.templateName = event.target.value;
    }
    
    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.recipients = [];
        this.addRecipientRow();
    }
    
    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleActiveChange(event) {
        this.isActive = event.target.checked;
    }
    
    handleDefaultChange(event) {
        this.isDefault = event.target.checked;
    }
    
    // ============ RECIPIENT HANDLERS ============
    
    addRecipientRow() {
        this.recipients = [
            ...this.recipients,
            {
                id: this.generateId(),
                index: this.recipients.length,
                type: 'to',
                sourceType: 'Field',
                fieldApiName: '',
                staticEmail:  '',
                label:  '',
                isRequired: false,
                isEditable: true
            }
        ];
    }
    
    handleRecipientChange(event) {
        const { index, data } = event.detail;
        this.recipients = this.recipients.map((rec, i) => {
            if (i === index) {
                return { ...rec, ...data };
            }
            return rec;
        });
    }
    
    handleRecipientDelete(event) {
        const { index } = event.detail;
        this.recipients = this.recipients
            .filter((_, i) => i !== index)
            .map((rec, i) => ({ ...rec, index: i }));
    }
    
    handleAllowAdditionalRecipientsChange(event) {
        this.allowAdditionalRecipients = event.target.checked;
    }
    
    // ============ CONTENT HANDLERS ============
    
    handleFromAddressChange(event) {
        this.fromAddress = event.detail.value;
    }
    
    handleReplyToChange(event) {
        this.replyTo = event.target.value;
    }
    
    handleSubjectChange(event) {
        this.subject = event.target.value;
    }
    
    handleBodyChange(event) {
        this.emailBody = event.target.value;
    }
    
    handleInsertMergeField(event) {
        const mergeField = event.detail.mergeField;
        this.selectedMergeField = mergeField;
    }
    
    // ============ ATTACHMENT HANDLERS ============
    
    addAttachmentRow() {
        this.attachments = [
            ... this.attachments,
            {
                id: this.generateId(),
                index: this.attachments.length,
                name: '',
                type: 'VFPage',
                vfPageName:  '',
                vfPageParam: 'id',
                documentId: '',
                documentTemplateId: '',
                fileNamePattern: '',
                isDefaultChecked: true,
                isRequired: false,
                recordSourceType: 'Direct',
                selectedRelationship: '',
                relationshipType: '',
                relationshipName: '',
                relatedObjectApi: '',
                childRecordType: 'All',
                filterConditionsJson: '[]',
                maxChildRecords: 10,
                orderByField: '',
                orderByDirection: 'ASC',
                singleChildLimit: 1
            }
        ];
    }
    
    handleAttachmentChange(event) {
        const { index, data } = event.detail;
        this.attachments = this.attachments.map((att, i) => {
            if (i === index) {
                return { ...att, ...data };
            }
            return att;
        });
    }
    
    handleAttachmentDelete(event) {
        const { index } = event.detail;
        this.attachments = this.attachments
            .filter((_, i) => i !== index)
            .map((att, i) => ({ ...att, index: i }));
    }
    
    handleAllowFileUploadChange(event) {
        this.allowFileUpload = event.target.checked;
    }

    // ============ STEP 5: ACTIONS & MATCHING ============

    handleActionBindingChange(event) {
        const selected = event.detail.value;
        this.actionBinding = Array.isArray(selected) ? selected.join(';') : selected;
    }

    handleMatchingCriteriaChange(event) {
        this.matchingCriteria = event.detail.criteriaJson;
    }

    get actionBindingValues() {
        if (!this.actionBinding) return [];
        return this.actionBinding.split(';').filter(v => v);
    }

    // ============ PREVIEW ============
    
    handlePreview() {
        if (!this.validateAllSteps()) {
            return;
        }
        this.previewData = null;
        this.previewRecordId = '';
        this.previewRecordOptions = [];
        this.showPreviewModal = true;
    }
    
    validateAllSteps() {
        return this.validateBasicInfo() && this.validateRecipients() && this.validateContent();
    }
    
    closePreviewModal() {
        this.showPreviewModal = false;
        this.previewData = null;
    }
    
    async handlePreviewRecordSearch(event) {
        const searchTerm = event.target.value;
        this.previewSearchTerm = searchTerm;
        
        if (searchTerm.length < 2) {
            this.previewRecordOptions = [];
            return;
        }
        
        try {
            const records = await searchRecords({
                objectApiName: this.selectedObject,
                searchTerm: searchTerm
            });
            
            this.previewRecordOptions = records.map(rec => ({
                label: rec.label,
                value:  rec.value
            }));
        } catch (error) {
            console.error('Error searching records:', error);
        }
    }
    
    handlePreviewRecordSelect(event) {
        this.previewRecordId = event.detail.value;
    }
    
    async handleLoadPreview() {
        if (!this.previewRecordId) {
            this.showToast('Error', 'Please select a record', 'error');
            return;
        }
        
        try {
            this.isPreviewLoading = true;
            
            const templateData = this.buildTemplateData();
            
            const savedTemplateId = await saveTemplate({
                templateJson: JSON.stringify(templateData)
            });
            
            const previewResult = await prepareEmailFromTemplate({
                templateId:  savedTemplateId,
                recordId: this.previewRecordId
            });
            
            this.previewData = previewResult;
            
            if (!this.editTemplateId) {
                this.editTemplateId = savedTemplateId;
            }
            
        } catch (error) {
            this.showToast('Error', 'Failed to load preview:  ' + this.reduceErrors(error), 'error');
        } finally {
            this.isPreviewLoading = false;
        }
    }
    
    // ============ SAVE ============
    
    async handleSave() {
        if (!this.validateAllSteps()) {
            return;
        }
        
        try {
            this.isSaving = true;
            
            const templateData = this.buildTemplateData();
            await saveTemplate({ templateJson: JSON.stringify(templateData) });
            
            this.showToast('Success', 'Template saved successfully', 'success');
            this.showBuilder = false;
            this.editTemplateId = null;
            this.resetBuilderForm();
            await this.loadTemplates();

        } catch (error) {
            this.showToast('Error', 'Failed to save template: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }
    
    buildTemplateData() {
        return {
            id: this.editTemplateId || null,
            name:  this.templateName,
            objectApiName: this.selectedObject,
            description: this.description,
            isActive: this.isActive,
            isDefault: this.isDefault,
            subject:  this.subject,
            emailBody: this.emailBody,
            fromAddress: this.fromAddress,
            replyTo:  this.replyTo,
            recipientsConfig: this.buildRecipientsConfig(),
            attachmentsConfig: this.buildAttachmentsConfig(),
            allowAdditionalRecipients: this.allowAdditionalRecipients,
            allowFileUpload: this.allowFileUpload,
            documentTemplateId: this.selectedDocumentTemplateId || null,
            actionBinding: this.actionBinding || null,
            matchingCriteria: this.matchingCriteria || null
        };
    }
    
    buildRecipientsConfig() {
        const config = {
            to: [],
            cc: [],
            bcc:  []
        };
        
        this.recipients.forEach(rec => {
            const recipientData = {
                id: rec.id,
                sourceType: rec.sourceType,
                fieldApiName: rec.fieldApiName,
                staticEmail: rec.staticEmail,
                label: rec.label,
                isRequired: rec.isRequired,
                isEditable: rec.isEditable
            };
            
            if (config[rec.type]) {
                config[rec.type].push(recipientData);
            }
        });
        
        return JSON.stringify(config);
    }
    
    buildAttachmentsConfig() {
        const config = {
            attachments: this.attachments.map(att => ({
                id: att.id,
                name: att.name,
                type:  att.type,
                vfPageName: att.vfPageName,
                vfPageParam:  att.vfPageParam,
                documentId: att.documentId,
                documentTemplateId: att.documentTemplateId || '',
                fileNamePattern: att.fileNamePattern,
                isDefaultChecked: att.isDefaultChecked,
                isRequired: att.isRequired,
                recordSourceType: att.recordSourceType || 'Direct',
                selectedRelationship: att.selectedRelationship || '',
                relationshipType: att.relationshipType || '',
                relationshipName: att.relationshipName || '',
                relatedObjectApi: att.relatedObjectApi || '',
                childRecordType: att.childRecordType || 'All',
                filterConditionsJson: att.filterConditionsJson || '[]',
                maxChildRecords: att.maxChildRecords || 10,
                orderByField: att.orderByField || '',
                orderByDirection: att.orderByDirection || 'ASC',
                singleChildLimit: att.singleChildLimit || 1
            }))
        };

        return JSON.stringify(config);
    }
    
    // ============ UTILITIES ============
    
    generateId() {
        return 'id_' + Math.random().toString(36).substr(2, 9);
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    
    reduceErrors(errors) {
        if (!Array.isArray(errors)) errors = [errors];
        return errors
            .filter(e => !!e)
            .map(e => e.body?.message || e.message || JSON.stringify(e))
            .join(', ');
    }
    
    // ============ GETTERS ============
    
    // List View Getters
    get hasTemplates() {
        return this.filteredTemplates.length > 0;
    }
    
    get templateCount() {
        return this.filteredTemplates.length;
    }
    
    // Builder View Getters
    get builderTitle() {
        return this.editTemplateId ? 'Edit Email Template' : 'Create Email Template';
    }
    
    get isStep1() { return this.currentStep === '1'; }
    get isStep2() { return this.currentStep === '2'; }
    get isStep3() { return this.currentStep === '3'; }
    get isStep4() { return this.currentStep === '4'; }
    get isStep5() { return this.currentStep === '5'; }

    get showPrevious() { return this.currentStep !== '1'; }
    get showNext() { return this.currentStep !== '5'; }
    
    get hasRecipients() { return this.recipients.length > 0; }
    get hasAttachments() { return this.attachments.length > 0; }
    
    get recipientCount() { return this.recipients.length; }
    get attachmentCount() { return this.attachments.length; }
    
    get stepsWithStatus() {
        return this.steps.map(step => ({
            ... step,
            class: this.getStepClass(step.value),
            isActive: step.value === this.currentStep,
            isCompleted: parseInt(step.value) < parseInt(this.currentStep)
        }));
    }
    
    getStepClass(stepValue) {
        if (stepValue === this.currentStep) {
            return 'slds-path__item slds-is-current slds-is-active';
        } else if (parseInt(stepValue) < parseInt(this.currentStep)) {
            return 'slds-path__item slds-is-complete';
        }
        return 'slds-path__item slds-is-incomplete';
    }
    
    get hasPreviewData() {
        return this.previewData !== null;
    }
    
    get hasPreviewAttachments() {
        return this.previewData?.attachments?.length > 0;
    }
    
    get previewToAddresses() {
        if (!this.previewData?.toRecipients) return '';
        return this.previewData.toRecipients
            .filter(r => r.email)
            .map(r => r.email)
            .join(', ');
    }
    
    get previewCcAddresses() {
        if (!this.previewData?.ccRecipients) return '';
        return this.previewData.ccRecipients
            .filter(r => r.email)
            .map(r => r.email)
            .join(', ');
    }
    
    get previewBccAddresses() {
        if (!this.previewData?.bccRecipients) return '';
        return this.previewData.bccRecipients
            .filter(r => r.email)
            .map(r => r.email)
            .join(', ');
    }
}