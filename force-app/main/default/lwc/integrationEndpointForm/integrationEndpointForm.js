import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import saveEndpoint from '@salesforce/apex/IntegrationDashboardController.saveEndpoint';

import INTEGRATION_KEY_FIELD from '@salesforce/schema/Integration_Endpoint__c.Integration_Key__c';
import BASE_URL_FIELD from '@salesforce/schema/Integration_Endpoint__c.Base_URL__c';
import PATH_FIELD from '@salesforce/schema/Integration_Endpoint__c.Path__c';
import HTTP_METHOD_FIELD from '@salesforce/schema/Integration_Endpoint__c.HTTP_Method__c';
import CONTENT_TYPE_FIELD from '@salesforce/schema/Integration_Endpoint__c.Content_Type__c';
import ACTIVE_FIELD from '@salesforce/schema/Integration_Endpoint__c.Active__c';
import CUSTOM_HEADERS_FIELD from '@salesforce/schema/Integration_Endpoint__c.Custom_Headers__c';
import QUERY_PARAMETERS_FIELD from '@salesforce/schema/Integration_Endpoint__c.Query_Parameters__c';
import EXECUTION_MODE_FIELD from '@salesforce/schema/Integration_Endpoint__c.Execution_Mode__c';
import AUTH_PROFILE_FIELD from '@salesforce/schema/Integration_Endpoint__c.Auth_Profile__c';
import RETRY_CONFIG_FIELD from '@salesforce/schema/Integration_Endpoint__c.Retry_Config__c';
import CATEGORY_FIELD from '@salesforce/schema/Integration_Endpoint__c.Category__c';
import OWNER_TEAM_FIELD from '@salesforce/schema/Integration_Endpoint__c.Owner_Team__c';
import DESCRIPTION_FIELD from '@salesforce/schema/Integration_Endpoint__c.Description__c';
import TIMEOUT_FIELD from '@salesforce/schema/Integration_Endpoint__c.Timeout__c';
import NAMED_CREDENTIAL_FIELD from '@salesforce/schema/Integration_Endpoint__c.Named_Credential__c';

const ENDPOINT_FIELDS = [
    INTEGRATION_KEY_FIELD,
    BASE_URL_FIELD,
    PATH_FIELD,
    HTTP_METHOD_FIELD,
    CONTENT_TYPE_FIELD,
    ACTIVE_FIELD,
    CUSTOM_HEADERS_FIELD,
    QUERY_PARAMETERS_FIELD,
    EXECUTION_MODE_FIELD,
    AUTH_PROFILE_FIELD,
    RETRY_CONFIG_FIELD,
    CATEGORY_FIELD,
    OWNER_TEAM_FIELD,
    DESCRIPTION_FIELD,
    TIMEOUT_FIELD,
    NAMED_CREDENTIAL_FIELD
];

const DEFAULT_ENDPOINT = {
    Integration_Key__c: '',
    Base_URL__c: '',
    Path__c: '',
    HTTP_Method__c: '',
    Content_Type__c: 'application/json',
    Active__c: true,
    Custom_Headers__c: '',
    Query_Parameters__c: '',
    Execution_Mode__c: '',
    Auth_Profile__c: '',
    Retry_Config__c: '',
    Category__c: '',
    Owner_Team__c: '',
    Description__c: '',
    Timeout__c: 30000,
    Named_Credential__c: ''
};

export default class IntegrationEndpointForm extends LightningElement {
    @api recordId;
    @api cloneMode = false;

    @track endpoint = { ...DEFAULT_ENDPOINT };
    @track isLoading = false;
    @track isSaving = false;
    @track headersJsonError = '';
    @track paramsJsonError = '';
    @track retryJsonError = '';

    activeSections = ['basic', 'url', 'headers', 'auth', 'retry'];

    get isEditMode() {
        return this.recordId && !this.cloneMode;
    }

    get modalTitle() {
        if (this.cloneMode) return 'Clone Integration Endpoint';
        if (this.recordId) return 'Edit Integration Endpoint';
        return 'New Integration Endpoint';
    }

    get saveButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Save';
    }

    get httpMethodOptions() {
        return [
            { label: 'GET', value: 'GET' },
            { label: 'POST', value: 'POST' },
            { label: 'PUT', value: 'PUT' },
            { label: 'PATCH', value: 'PATCH' },
            { label: 'DELETE', value: 'DELETE' },
            { label: 'HEAD', value: 'HEAD' },
            { label: 'OPTIONS', value: 'OPTIONS' }
        ];
    }

    get contentTypeOptions() {
        return [
            { label: 'application/json', value: 'application/json' },
            { label: 'application/xml', value: 'application/xml' },
            { label: 'application/x-www-form-urlencoded', value: 'application/x-www-form-urlencoded' },
            { label: 'multipart/form-data', value: 'multipart/form-data' },
            { label: 'text/plain', value: 'text/plain' },
            { label: 'text/xml', value: 'text/xml' }
        ];
    }

    get categoryOptions() {
        return [
            { label: 'Payment', value: 'Payment' },
            { label: 'CRM', value: 'CRM' },
            { label: 'ERP', value: 'ERP' },
            { label: 'Notification', value: 'Notification' },
            { label: 'Analytics', value: 'Analytics' },
            { label: 'Authentication', value: 'Authentication' },
            { label: 'Data Sync', value: 'Data Sync' },
            { label: 'Webhook', value: 'Webhook' },
            { label: 'Other', value: 'Other' }
        ];
    }

    get executionModeOptions() {
        return [
            { label: 'Synchronous', value: 'Synchronous' },
            { label: 'Asynchronous (Future)', value: 'Future' },
            { label: 'Asynchronous (Queueable)', value: 'Queueable' },
            { label: 'Batch', value: 'Batch' },
            { label: 'Scheduled', value: 'Scheduled' }
        ];
    }

    @wire(getRecord, { recordId: '$recordId', fields: ENDPOINT_FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.endpoint = {
                Integration_Key__c: getFieldValue(data, INTEGRATION_KEY_FIELD) || '',
                Base_URL__c: getFieldValue(data, BASE_URL_FIELD) || '',
                Path__c: getFieldValue(data, PATH_FIELD) || '',
                HTTP_Method__c: getFieldValue(data, HTTP_METHOD_FIELD) || '',
                Content_Type__c: getFieldValue(data, CONTENT_TYPE_FIELD) || 'application/json',
                Active__c: getFieldValue(data, ACTIVE_FIELD) !== false,
                Custom_Headers__c: getFieldValue(data, CUSTOM_HEADERS_FIELD) || '',
                Query_Parameters__c: getFieldValue(data, QUERY_PARAMETERS_FIELD) || '',
                Execution_Mode__c: getFieldValue(data, EXECUTION_MODE_FIELD) || '',
                Auth_Profile__c: getFieldValue(data, AUTH_PROFILE_FIELD) || '',
                Retry_Config__c: getFieldValue(data, RETRY_CONFIG_FIELD) || '',
                Category__c: getFieldValue(data, CATEGORY_FIELD) || '',
                Owner_Team__c: getFieldValue(data, OWNER_TEAM_FIELD) || '',
                Description__c: getFieldValue(data, DESCRIPTION_FIELD) || '',
                Timeout__c: getFieldValue(data, TIMEOUT_FIELD) || 30000,
                Named_Credential__c: getFieldValue(data, NAMED_CREDENTIAL_FIELD) || ''
            };
            this.isLoading = false;
        } else if (error) {
            this.handleError(error);
            this.isLoading = false;
        }
    }

    handleFieldChange(event) {
        const fieldName = event.target.fieldName || event.target.dataset.fieldName;
        if (fieldName) {
            this.endpoint = {
                ...this.endpoint,
                [fieldName]: event.detail ? event.detail.value : event.target.value
            };
        }
    }

    handleCheckboxChange(event) {
        const fieldName = event.target.fieldName || event.target.dataset.fieldName;
        if (fieldName) {
            this.endpoint = {
                ...this.endpoint,
                [fieldName]: event.target.checked
            };
        }
    }

    handleJsonValidation(event) {
        const fieldName = event.target.dataset.jsonField;
        const value = event.target.value;

        if (!value || value.trim() === '') {
            this.clearJsonError(fieldName);
            return;
        }

        try {
            JSON.parse(value);
            this.clearJsonError(fieldName);
        } catch (e) {
            this.setJsonError(fieldName, `Invalid JSON: ${e.message}`);
        }
    }

    clearJsonError(fieldName) {
        if (fieldName === 'Custom_Headers__c') this.headersJsonError = '';
        if (fieldName === 'Query_Parameters__c') this.paramsJsonError = '';
        if (fieldName === 'Retry_Config__c') this.retryJsonError = '';
    }

    setJsonError(fieldName, message) {
        if (fieldName === 'Custom_Headers__c') this.headersJsonError = message;
        if (fieldName === 'Query_Parameters__c') this.paramsJsonError = message;
        if (fieldName === 'Retry_Config__c') this.retryJsonError = message;
    }

    validateForm() {
        // Check required fields
        const inputFields = this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea');
        let isValid = true;

        inputFields.forEach(field => {
            if (!field.reportValidity()) {
                isValid = false;
            }
        });

        // Check required field values
        if (!this.endpoint.Integration_Key__c) {
            isValid = false;
            this.showToast('Validation Error', 'Integration Key is required.', 'error');
        }

        if (!this.endpoint.Base_URL__c) {
            isValid = false;
            this.showToast('Validation Error', 'Base URL is required.', 'error');
        }

        if (!this.endpoint.HTTP_Method__c) {
            isValid = false;
            this.showToast('Validation Error', 'HTTP Method is required.', 'error');
        }

        // Check JSON fields
        if (this.headersJsonError || this.paramsJsonError || this.retryJsonError) {
            isValid = false;
            this.showToast('Validation Error', 'Please fix JSON validation errors before saving.', 'error');
        }

        return isValid;
    }

    handleSave() {
        if (!this.validateForm()) {
            return;
        }

        this.isSaving = true;

        const endpointData = {};

        // Build the payload, removing empty/null/undefined values
        Object.keys(this.endpoint).forEach(key => {
            const value = this.endpoint[key];
            if (value !== '' && value !== null && value !== undefined) {
                endpointData[key] = value;
            }
        });

        saveEndpoint({
            endpointData: endpointData,
            recordId: this.isEditMode ? this.recordId : null
        })
            .then(result => {
                const message = this.isEditMode
                    ? 'Endpoint updated successfully.'
                    : 'Endpoint created successfully.';
                this.showToast('Success', message, 'success');
                this.dispatchEvent(new CustomEvent('save', { detail: { id: result } }));
            })
            .catch(error => {
                this.handleError(error);
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleTestConnection() {
        if (!this.endpoint.Base_URL__c) {
            this.showToast('Validation Error', 'Please enter a Base URL before testing.', 'error');
            return;
        }

        this.showToast(
            'Test Connection',
            `Testing connection to ${this.endpoint.Base_URL__c}${this.endpoint.Path__c || ''}...`,
            'info'
        );

        // In a real implementation, this would call an Apex method to test the connection
        // For now, we show a placeholder message
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showToast(
                'Test Connection',
                'Test connection functionality requires the IntegrationEngine Apex class. Use the Test Console tab for full testing.',
                'warning'
            );
        }, 1000);
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    handleError(error) {
        let message = 'An unexpected error occurred.';
        if (error) {
            if (error.body && error.body.message) {
                message = error.body.message;
            } else if (error.body && error.body.output && error.body.output.errors) {
                message = error.body.output.errors.map(e => e.message).join(', ');
            } else if (error.message) {
                message = error.message;
            }
        }
        this.showToast('Error', message, 'error');
    }
}