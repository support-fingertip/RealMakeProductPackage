import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getConfigurations from '@salesforce/apex/PostSalesAdminController.getConfigurations';
import saveConfiguration from '@salesforce/apex/PostSalesAdminController.saveConfiguration';
import deleteConfiguration from '@salesforce/apex/PostSalesAdminController.deleteConfiguration';
import getAvailableVFPages from '@salesforce/apex/PostSalesAdminController.getAvailableVFPages';
import getEmailTemplateOptions from '@salesforce/apex/PostSalesAdminController.getEmailTemplateOptions';
import getDocumentTemplateOptions from '@salesforce/apex/PostSalesAdminController.getDocumentTemplateOptions';
import getApprovalConfigOptions from '@salesforce/apex/PostSalesAdminController.getApprovalConfigOptions';
import getAllObjects from '@salesforce/apex/DynamicFormConfigController.getAllObjects';
import getAllObjectFields from '@salesforce/apex/DynamicFormConfigController.getAllObjectFields';

export default class PostSalesAdmin extends LightningElement {
    @track activeTab = 'postSalesConfig';
    @track isLoading = false;

    // Post Sales Configuration tab state
    @track configurations = [];
    @track showConfigForm = false;
    @track editingConfig = {};
    @track isEditMode = false;

    // Lookup options
    @track vfPageOptions = [];
    @track emailTemplateOptions = [];
    @track documentTemplateOptions = [];
    @track approvalConfigOptions = [];

    wiredConfigResult;

    configurationTypeOptions = [
        { label: 'Demand', value: 'Demand' },
        { label: 'Payment Schedule', value: 'Payment Schedule' },
        { label: 'Receipt', value: 'Receipt' },
        { label: 'Credit Note', value: 'Credit Note' },
        { label: 'Debit Note', value: 'Debit Note' },
        { label: 'Advance Payment', value: 'Advance Payment' },
        { label: 'Cancellation', value: 'Cancellation' },
        { label: 'Transfer', value: 'Transfer' }
    ];

    scheduleModeOptions = [
        { label: 'Standard (Auto from Master Payment Schedules - Not Editable)', value: 'Standard' },
        { label: 'Custom (Editable via Payment Schedule Editor)', value: 'Custom' }
    ];

    @wire(getConfigurations)
    wiredConfigs(result) {
        this.wiredConfigResult = result;
        if (result.data) {
            this.configurations = result.data.map(c => ({
                ...c,
                displayEmailTemplate: c.emailTemplateName || 'Not Applicable',
                displayVfPage: c.vfPageName || 'Not Applicable',
                displayDocTemplate: c.documentTemplateName || 'Not Applicable',
                displayApprovalConfig: c.approvalConfigurationName || 'Not Applicable'
            }));
        } else if (result.error) {
            this.showToast('Error', this.getErrorMessage(result.error), 'error');
        }
    }

    @wire(getAvailableVFPages)
    wiredVFPages({ data, error }) {
        if (data) {
            this.vfPageOptions = [
                { label: '-- Not Applicable --', value: '' },
                ...data.map(p => ({ label: p.label, value: p.value }))
            ];
        }
    }

    @wire(getEmailTemplateOptions)
    wiredEmailTemplates({ data, error }) {
        if (data) {
            this.emailTemplateOptions = [
                { label: '-- Not Applicable --', value: '' },
                ...data.map(t => ({ label: t.label, value: t.value }))
            ];
        }
    }

    @wire(getDocumentTemplateOptions)
    wiredDocTemplates({ data, error }) {
        if (data) {
            this.documentTemplateOptions = [
                { label: '-- Not Applicable --', value: '' },
                ...data.map(t => ({ label: t.label, value: t.value }))
            ];
        }
    }

    @wire(getApprovalConfigOptions)
    wiredApprovalConfigs({ data, error }) {
        if (data) {
            this.approvalConfigOptions = [
                { label: '-- Not Applicable --', value: '' },
                ...data.map(c => ({ label: c.label, value: c.value }))
            ];
        }
    }

    // Tab navigation
    get tabItems() {
        return [
            { label: 'Post Sales Config', value: 'postSalesConfig', icon: 'utility:settings' },
            { label: 'Approval Config', value: 'approvalConfig', icon: 'utility:approval' },
            { label: 'Email Templates', value: 'emailTemplates', icon: 'utility:email' },
            { label: 'Field Mapper', value: 'fieldMapper', icon: 'utility:connected_apps' },
            { label: 'Dynamic Forms', value: 'formConfig', icon: 'utility:form' },
            { label: 'Reports', value: 'reportConfig', icon: 'utility:table' },
            { label: 'Dashboards', value: 'dashboardConfig', icon: 'utility:chart' },
            { label: 'Document Designer', value: 'documentDesigner', icon: 'utility:document_preview' },
            { label: 'Integrations', value: 'integrationConfig', icon: 'utility:connected_apps' }
        ];
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    // Computed tab visibility
    get isPostSalesConfigTab() { return this.activeTab === 'postSalesConfig'; }
    get isApprovalConfigTab() { return this.activeTab === 'approvalConfig'; }
    get isEmailTemplatesTab() { return this.activeTab === 'emailTemplates'; }
    get isFieldMapperTab() { return this.activeTab === 'fieldMapper'; }
    get isFormConfigTab() { return this.activeTab === 'formConfig'; }
    get isReportConfigTab() { return this.activeTab === 'reportConfig'; }
    get isDashboardConfigTab() { return this.activeTab === 'dashboardConfig'; }
    get isDocumentDesignerTab() { return this.activeTab === 'documentDesigner'; }
    get isIntegrationConfigTab() { return this.activeTab === 'integrationConfig'; }

    get hasConfigurations() {
        return this.configurations && this.configurations.length > 0;
    }

    get isDemandConfig() {
        return this.editingConfig.configurationType === 'Demand';
    }

    get isPaymentScheduleConfig() {
        return this.editingConfig.configurationType === 'Payment Schedule';
    }

    get isStandardMode() {
        return this.editingConfig.scheduleMode !== 'Custom';
    }

    // Payment Schedule config dropdowns
    @track allObjectOptions = [];
    @track sourceFieldOptions = [];
    @track targetFieldOptions = [];
    @track bookingFieldOptions = [];

    // Field mapping for Payment Schedule
    @track newMappingSource = '';
    @track newMappingTarget = '';

    get hasFieldMappings() {
        return this.editingConfig.fieldMappings && this.editingConfig.fieldMappings.length > 0;
    }

    get addMappingDisabled() {
        return !this.newMappingSource || !this.newMappingTarget;
    }

    loadAllObjects() {
        if (this.allObjectOptions.length > 0) return;
        getAllObjects()
            .then(result => {
                this.allObjectOptions = result.map(o => ({ label: o.label + ' (' + o.value + ')', value: o.value }));
            })
            .catch(() => {});
    }

    loadSourceFields() {
        const obj = this.editingConfig.sourceObject;
        if (!obj) { this.sourceFieldOptions = []; return; }
        getAllObjectFields({ objectApiName: obj })
            .then(result => {
                this.sourceFieldOptions = result.map(f => ({ label: f.label + ' (' + f.value + ')', value: f.value }));
            })
            .catch(() => { this.sourceFieldOptions = []; });
    }

    loadTargetFields() {
        const obj = this.editingConfig.targetObject;
        if (!obj) { this.targetFieldOptions = []; return; }
        getAllObjectFields({ objectApiName: obj })
            .then(result => {
                this.targetFieldOptions = result.map(f => ({ label: f.label + ' (' + f.value + ')', value: f.value }));
            })
            .catch(() => { this.targetFieldOptions = []; });
    }

    loadBookingFields() {
        if (this.bookingFieldOptions.length > 0) return;
        getAllObjectFields({ objectApiName: 'Booking__c' })
            .then(result => {
                this.bookingFieldOptions = result.map(f => ({ label: f.label + ' (' + f.value + ')', value: f.value }));
            })
            .catch(() => {});
    }

    handleSourceObjectChange(event) {
        this.editingConfig = { ...this.editingConfig, sourceObject: event.detail.value };
        this.loadSourceFields();
    }

    handleTargetObjectChange(event) {
        this.editingConfig = { ...this.editingConfig, targetObject: event.detail.value };
        this.loadTargetFields();
    }

    handleMappingInputChange(event) {
        const field = event.target.dataset.field;
        if (field === 'newMappingSource') this.newMappingSource = event.detail.value;
        if (field === 'newMappingTarget') this.newMappingTarget = event.detail.value;
    }

    handleAddFieldMapping() {
        if (!this.newMappingSource || !this.newMappingTarget) return;
        const mappings = [...(this.editingConfig.fieldMappings || [])];
        mappings.push({
            key: 'map-' + Date.now(),
            sourceField: this.newMappingSource,
            targetField: this.newMappingTarget
        });
        this.editingConfig = { ...this.editingConfig, fieldMappings: mappings };
        this.newMappingSource = '';
        this.newMappingTarget = '';
    }

    handleRemoveFieldMapping(event) {
        const key = event.currentTarget.dataset.key;
        const mappings = (this.editingConfig.fieldMappings || []).filter(m => m.key !== key);
        this.editingConfig = { ...this.editingConfig, fieldMappings: mappings };
    }

    get notesSectionNumber() {
        if (this.isDemandConfig) return 7;
        if (this.isPaymentScheduleConfig) return 4;
        return 6;
    }

    get reminderObjectOptions() {
        return [
            { label: 'Booking', value: 'Booking__c' },
            { label: 'Demand', value: 'Demands__c' }
        ];
    }

    get reminderCards() {
        const labels = ['1st Reminder', '2nd Reminder', '3rd Reminder', '4th Reminder'];
        const headerClasses = [
            'reminder-header reminder-header-1',
            'reminder-header reminder-header-2',
            'reminder-header reminder-header-3',
            'reminder-header reminder-header-4'
        ];
        const defaults = [7, 14, 21, 30];
        const reminders = this.editingConfig.reminders || [];

        return labels.map((label, i) => {
            const r = reminders[i] || {};
            return {
                key: 'rem-' + i,
                index: i,
                label,
                headerClass: headerClasses[i],
                isNA: r.isNA === true,
                daysAfterDue: r.daysAfterDue != null ? r.daysAfterDue : defaults[i],
                againstObject: r.againstObject || 'Booking__c',
                documentTemplateId: r.documentTemplateId || ''
            };
        });
    }

    handleReminderNAChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const reminders = [...(this.editingConfig.reminders || this._defaultReminders())];
        reminders[index] = { ...reminders[index], isNA: event.target.checked };
        this.editingConfig = { ...this.editingConfig, reminders };
    }

    handleReminderFieldChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const field = event.currentTarget.dataset.field;
        const value = event.detail ? event.detail.value : event.target.value;
        const reminders = [...(this.editingConfig.reminders || this._defaultReminders())];
        reminders[index] = { ...reminders[index], [field]: field === 'daysAfterDue' ? parseInt(value, 10) : value };
        this.editingConfig = { ...this.editingConfig, reminders };
    }

    _defaultFieldMappings() {
        return [
            { key: 'map-1', sourceField: 'Sequence__c', targetField: 'Sequence__c' },
            { key: 'map-2', sourceField: 'Sequence__c', targetField: 'S_No__c' },
            { key: 'map-3', sourceField: 'Percentage__c', targetField: 'Percentage__c' },
            { key: 'map-4', sourceField: 'Payment_Type__c', targetField: 'Milestone_Name__c' },
            { key: 'map-5', sourceField: 'Description__c', targetField: 'Description__c' }
        ];
    }

    _defaultReminders() {
        return [
            { isNA: false, daysAfterDue: 7, againstObject: 'Booking__c', documentTemplateId: '' },
            { isNA: false, daysAfterDue: 14, againstObject: 'Booking__c', documentTemplateId: '' },
            { isNA: false, daysAfterDue: 21, againstObject: 'Booking__c', documentTemplateId: '' },
            { isNA: false, daysAfterDue: 30, againstObject: 'Booking__c', documentTemplateId: '' }
        ];
    }

    // ============ POST SALES CONFIG CRUD ============

    handleNewConfig() {
        this.editingConfig = {
            configurationType: '',
            emailTemplateId: '',
            vfPageName: '',
            documentTemplateId: '',
            approvalConfigurationId: '',
            gracePeriodDays: 15,
            includeInterest: false,
            includePreviousDues: false,
            autoSendEmail: false,
            dueDateOffsetDays: 15,
            isActive: true,
            enableReminders: false,
            reminders: this._defaultReminders(),
            scheduleMode: 'Standard',
            sourceObject: 'Master_Payment_Schedule__c',
            targetObject: 'Payment_Schedule__c',
            sourceParentField: 'Project__c',
            bookingParentField: 'Project__c',
            targetBookingField: 'Booking__c',
            fieldMappings: this._defaultFieldMappings(),
            notes: ''
        };
        this.isEditMode = false;
        this.showConfigForm = true;
    }

    handleEditConfig(event) {
        const configId = event.currentTarget.dataset.id;
        const config = this.configurations.find(c => c.id === configId);
        if (config) {
            let reminders = this._defaultReminders();
            let sourceObject = 'Master_Payment_Schedule__c';
            let targetObject = 'Payment_Schedule__c';
            let sourceParentField = 'Project__c';
            let bookingParentField = 'Project__c';
            let targetBookingField = 'Booking__c';

            let fieldMappings = this._defaultFieldMappings();

            if (config.reminderConfig) {
                try {
                    const parsed = JSON.parse(config.reminderConfig);
                    if (config.configurationType === 'Payment Schedule' && parsed.sourceObject) {
                        sourceObject = parsed.sourceObject || sourceObject;
                        targetObject = parsed.targetObject || targetObject;
                        sourceParentField = parsed.sourceParentField || sourceParentField;
                        bookingParentField = parsed.bookingParentField || bookingParentField;
                        targetBookingField = parsed.targetBookingField || targetBookingField;
                        if (parsed.fieldMappings && parsed.fieldMappings.length > 0) {
                            fieldMappings = parsed.fieldMappings.map((m, i) => ({
                                key: 'map-' + i,
                                sourceField: m.sourceField,
                                targetField: m.targetField
                            }));
                        }
                    } else if (Array.isArray(parsed)) {
                        reminders = parsed;
                    }
                } catch (e) { /* use defaults */ }
            }

            this.editingConfig = {
                ...config,
                enableReminders: config.enableReminders || false,
                reminders,
                sourceObject,
                targetObject,
                sourceParentField,
                bookingParentField,
                targetBookingField,
                fieldMappings
            };
            this.isEditMode = true;
            this.showConfigForm = true;

            // Load dropdowns for Payment Schedule config
            if (config.configurationType === 'Payment Schedule') {
                this.loadAllObjects();
                this.loadBookingFields();
                this.loadSourceFields();
                this.loadTargetFields();
            }
        }
    }

    handleDeleteConfig(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        deleteConfiguration({ configId })
            .then(() => {
                this.showToast('Success', 'Configuration deleted', 'success');
                return refreshApex(this.wiredConfigResult);
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    handleConfigFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.editingConfig = { ...this.editingConfig, [field]: value };

        // Load dropdowns when Payment Schedule type is selected
        if (field === 'configurationType' && value === 'Payment Schedule') {
            this.loadAllObjects();
            this.loadBookingFields();
            this.loadSourceFields();
            this.loadTargetFields();
        }
    }

    handleMatchingCriteriaChange(event) {
        this.editingConfig = { ...this.editingConfig, matchingCriteria: event.detail.criteriaJson };
    }

    handleSaveConfig() {
        if (!this.editingConfig.configurationType) {
            this.showToast('Error', 'Configuration Type is required', 'error');
            return;
        }

        this.isLoading = true;
        // Serialize config-type-specific data to JSON for storage
        const payload = { ...this.editingConfig };
        if (payload.reminders) {
            payload.reminderConfig = JSON.stringify(payload.reminders);
            delete payload.reminders;
        }
        // For Payment Schedule, store creation config + field mappings in reminderConfig
        if (payload.configurationType === 'Payment Schedule') {
            const mappings = (payload.fieldMappings || []).map(m => ({
                sourceField: m.sourceField,
                targetField: m.targetField
            }));
            payload.reminderConfig = JSON.stringify({
                sourceObject: payload.sourceObject || '',
                targetObject: payload.targetObject || '',
                sourceParentField: payload.sourceParentField || '',
                bookingParentField: payload.bookingParentField || '',
                targetBookingField: payload.targetBookingField || '',
                fieldMappings: mappings
            });
        }
        // Clean up temp fields not in wrapper
        delete payload.sourceObject;
        delete payload.targetObject;
        delete payload.sourceParentField;
        delete payload.bookingParentField;
        delete payload.targetBookingField;
        delete payload.fieldMappings;
        const configJson = JSON.stringify(payload);

        saveConfiguration({ configJson })
            .then(() => {
                this.showToast('Success', 'Configuration saved successfully', 'success');
                this.showConfigForm = false;
                this.editingConfig = {};
                return refreshApex(this.wiredConfigResult);
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    handleCancelConfig() {
        this.showConfigForm = false;
        this.editingConfig = {};
    }

    handleRefreshConfigs() {
        return refreshApex(this.wiredConfigResult);
    }

    handleRefreshApprovalConfig() {
        const child = this.template.querySelector('c-dynamic-approval-config');
        if (child) child.refresh();
    }

    handleRefreshEmailTemplates() {
        const child = this.template.querySelector('c-email-template-list');
        if (child) child.refresh();
    }

    handleRefreshFieldMapper() {
        const child = this.template.querySelector('c-field-mapper');
        if (child) child.refresh();
    }

    handleRefreshFormConfig() {
        const child = this.template.querySelector('c-form-configurator-builder');
        if (child) child.refresh();
    }

    handleRefreshReports() {
        const child = this.template.querySelector('c-report-configurator');
        if (child) child.refresh();
    }

    handleRefreshDashboards() {
        const child = this.template.querySelector('c-dashboard-configurator');
        if (child) child.refresh();
    }

    handleRefreshDocDesigner() {
        const child = this.template.querySelector('c-document-designer');
        if (child) child.refresh();
    }

    handleRefreshIntegrations() {
        const child = this.template.querySelector('c-integration-dashboard');
        if (child) child.refresh();
    }

    // ============ UTILITIES ============

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        } else if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}