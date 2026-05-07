import { LightningElement, wire, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEndpointHealth from '@salesforce/apex/IntegrationDashboardController.getEndpointHealth';

const MAX_HISTORY_ITEMS = 20;

const HISTORY_COLUMNS = [
    {
        label: 'Endpoint',
        fieldName: 'endpointKey',
        type: 'text',
        initialWidth: 180
    },
    {
        label: 'Status',
        fieldName: 'statusCode',
        type: 'number',
        initialWidth: 80,
        cellAttributes: {
            class: { fieldName: 'statusClass' }
        }
    },
    {
        label: 'Time (ms)',
        fieldName: 'executionTime',
        type: 'number',
        initialWidth: 100
    },
    {
        label: 'Timestamp',
        fieldName: 'timestamp',
        type: 'date',
        typeAttributes: {
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        },
        initialWidth: 140
    },
    {
        label: 'Success',
        fieldName: 'isSuccess',
        type: 'boolean',
        initialWidth: 80
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Load Payload', name: 'load_payload' },
                { label: 'View Response', name: 'view_response' }
            ]
        }
    }
];

let historyIdCounter = 0;

export default class IntegrationTestConsole extends LightningElement {
    @track endpointOptions = [];
    @track endpoints = [];
    @track selectedEndpointId = '';
    @track selectedEndpointInfo = {};
    @track testRecordId = '';
    @track testPayload = '{\n  \n}';
    @track payloadJsonError = '';
    @track isExecuting = false;
    @track hasResponse = false;
    @track lastResponse = {};
    @track lastExecutionTime = 0;
    @track testHistory = [];

    historyColumns = HISTORY_COLUMNS;

    get hasEndpointSelected() {
        return !!this.selectedEndpointId;
    }

    get isExecuteDisabled() {
        return !this.selectedEndpointId || this.isExecuting || !!this.payloadJsonError;
    }

    get executeButtonLabel() {
        return this.isExecuting ? 'Executing...' : 'Execute';
    }

    get showEmptyState() {
        return !this.isExecuting && !this.hasResponse;
    }

    get hasTestHistory() {
        return this.testHistory && this.testHistory.length > 0;
    }

    get responseStatusLabel() {
        if (!this.lastResponse) return '';
        return `${this.lastResponse.statusCode} ${this.lastResponse.statusText || ''}`;
    }

    get responseStatusClass() {
        if (!this.lastResponse) return '';
        const code = this.lastResponse.statusCode;
        if (code >= 200 && code < 300) return 'slds-theme_success';
        if (code >= 400) return 'slds-theme_error';
        return 'slds-theme_warning';
    }

    get formattedResponseBody() {
        if (!this.lastResponse || !this.lastResponse.body) return '(empty)';
        try {
            const parsed = JSON.parse(this.lastResponse.body);
            return JSON.stringify(parsed, null, 2);
        } catch (e) {
            return this.lastResponse.body;
        }
    }

    get formattedResponseHeaders() {
        if (!this.lastResponse || !this.lastResponse.headers) return '(no headers)';
        if (typeof this.lastResponse.headers === 'string') {
            try {
                const parsed = JSON.parse(this.lastResponse.headers);
                return JSON.stringify(parsed, null, 2);
            } catch (e) {
                return this.lastResponse.headers;
            }
        }
        return JSON.stringify(this.lastResponse.headers, null, 2);
    }

    get rawResponse() {
        if (!this.lastResponse) return '(no response)';
        return JSON.stringify(this.lastResponse, null, 2);
    }

    @wire(getEndpointHealth)
    wiredEndpoints(result) {
        if (result.data) {
            this.endpoints = result.data;
            this.endpointOptions = [
                { label: '-- Select Endpoint --', value: '' },
                ...result.data.map(ep => ({
                    label: `${ep.Integration_Key__c || ep.Name} [${ep.HTTP_Method__c || 'N/A'}] - ${ep.Base_URL__c || ''}`,
                    value: ep.Id
                }))
            ];
        } else if (result.error) {
            this.handleError(result.error);
        }
    }

    handleEndpointChange(event) {
        this.selectedEndpointId = event.detail.value;
        if (this.selectedEndpointId) {
            const endpoint = this.endpoints.find(ep => ep.Id === this.selectedEndpointId);
            if (endpoint) {
                this.selectedEndpointInfo = {
                    ...endpoint,
                    fullUrl: (endpoint.Base_URL__c || '') + (endpoint.Path__c || '')
                };

                // Pre-populate payload based on content type
                if (!this.testPayload || this.testPayload.trim() === '{\n  \n}') {
                    this.testPayload = this.generateSamplePayload(endpoint);
                }
            }
        } else {
            this.selectedEndpointInfo = {};
        }
    }

    generateSamplePayload(endpoint) {
        if (endpoint.HTTP_Method__c === 'GET' || endpoint.HTTP_Method__c === 'DELETE') {
            return '{}';
        }
        return '{\n  "key": "value"\n}';
    }

    handleRecordIdChange(event) {
        this.testRecordId = event.target.value;
    }

    handlePayloadChange(event) {
        this.testPayload = event.target.value;
    }

    handlePayloadValidation() {
        if (!this.testPayload || this.testPayload.trim() === '') {
            this.payloadJsonError = '';
            return;
        }
        try {
            JSON.parse(this.testPayload);
            this.payloadJsonError = '';
        } catch (e) {
            this.payloadJsonError = `Invalid JSON: ${e.message}`;
        }
    }

    handleFormatPayload() {
        if (!this.testPayload || this.testPayload.trim() === '') return;
        try {
            const parsed = JSON.parse(this.testPayload);
            this.testPayload = JSON.stringify(parsed, null, 2);
            this.payloadJsonError = '';
        } catch (e) {
            this.payloadJsonError = `Cannot format - Invalid JSON: ${e.message}`;
        }
    }

    handleExecute() {
        if (!this.selectedEndpointId) {
            this.showToast('Error', 'Please select an endpoint.', 'error');
            return;
        }

        // Validate payload JSON
        if (this.testPayload && this.testPayload.trim() !== '') {
            try {
                JSON.parse(this.testPayload);
            } catch (e) {
                this.payloadJsonError = `Invalid JSON: ${e.message}`;
                this.showToast('Validation Error', 'Please fix the JSON payload before executing.', 'error');
                return;
            }
        }

        this.isExecuting = true;
        this.hasResponse = false;
        const startTime = Date.now();

        // In production, this would call IntegrationInvocable or IntegrationEngine
        // For demonstration, we simulate a response after a delay
        // Real implementation:
        // executeIntegration({ endpointId: this.selectedEndpointId, payload: this.testPayload, recordId: this.testRecordId })
        //   .then(result => { ... })
        //   .catch(error => { ... });

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const executionTime = Date.now() - startTime;
            this.lastExecutionTime = executionTime;

            // Simulated response - replace with actual Apex call result
            this.lastResponse = {
                statusCode: 200,
                statusText: 'OK',
                body: JSON.stringify({
                    message: 'Test execution simulated. Connect IntegrationEngine Apex class for live testing.',
                    endpoint: this.selectedEndpointInfo.fullUrl,
                    method: this.selectedEndpointInfo.HTTP_Method__c,
                    recordId: this.testRecordId || null,
                    timestamp: new Date().toISOString()
                }),
                headers: JSON.stringify({
                    'Content-Type': 'application/json',
                    'X-Request-Id': this.generateRequestId()
                })
            };

            this.hasResponse = true;
            this.isExecuting = false;

            // Add to history
            this.addToHistory(executionTime);

            this.showToast(
                'Test Complete',
                `Integration test executed in ${executionTime}ms. Note: Connect IntegrationEngine for live testing.`,
                'info'
            );
        }, 1500);
    }

    addToHistory(executionTime) {
        historyIdCounter += 1;
        const historyItem = {
            id: 'hist_' + historyIdCounter,
            endpointKey: this.selectedEndpointInfo.Integration_Key__c || this.selectedEndpointInfo.Name,
            endpointId: this.selectedEndpointId,
            statusCode: this.lastResponse.statusCode,
            executionTime: executionTime,
            isSuccess: this.lastResponse.statusCode >= 200 && this.lastResponse.statusCode < 300,
            timestamp: new Date().toISOString(),
            payload: this.testPayload,
            recordId: this.testRecordId,
            response: this.lastResponse,
            statusClass: this.lastResponse.statusCode >= 200 && this.lastResponse.statusCode < 300
                ? 'slds-text-color_success'
                : 'slds-text-color_error'
        };

        this.testHistory = [historyItem, ...this.testHistory].slice(0, MAX_HISTORY_ITEMS);
    }

    generateRequestId() {
        return 'test-' + Date.now().toString(36) + '-' + Math.random().toString(36).substring(2, 8);
    }

    handleHistoryRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'load_payload':
                this.selectedEndpointId = row.endpointId;
                this.handleEndpointChange({ detail: { value: row.endpointId } });
                this.testPayload = row.payload;
                this.testRecordId = row.recordId || '';
                this.showToast('Loaded', 'Previous test configuration loaded.', 'success');
                break;
            case 'view_response':
                this.lastResponse = row.response;
                this.lastExecutionTime = row.executionTime;
                this.hasResponse = true;
                break;
            default:
                break;
        }
    }

    handleClear() {
        this.testPayload = '{\n  \n}';
        this.testRecordId = '';
        this.payloadJsonError = '';
        this.hasResponse = false;
        this.lastResponse = {};
        this.lastExecutionTime = 0;
    }

    handleClearHistory() {
        this.testHistory = [];
    }

    @api
    setEndpoint(endpointId) {
        this.selectedEndpointId = endpointId;
        this.handleEndpointChange({ detail: { value: endpointId } });
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
            } else if (error.message) {
                message = error.message;
            }
        }
        this.showToast('Error', message, 'error');
    }
}