import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { createRecord, updateRecord, deleteRecord } from 'lightning/uiRecordApi';
import getEndpointHealth from '@salesforce/apex/IntegrationDashboardController.getEndpointHealth';

const FIELD_MAPPING_OBJECT = 'Integration_Field_Mapping__c';

let clientIdCounter = 0;

function generateClientId() {
    clientIdCounter += 1;
    return 'client_' + clientIdCounter + '_' + Date.now();
}

export default class IntegrationFieldMappingGrid extends LightningElement {
    @track mappings = [];
    @track filteredMappings = [];
    @track endpointOptions = [];
    @track selectedEndpointId = '';
    @track selectedDirection = '';
    @track selectedActiveFilter = '';
    @track isLoading = false;
    @track isSaving = false;
    @track hasUnsavedChanges = false;
    @track allRowsSelected = false;

    wiredEndpointResult;
    wiredMappingResult;

    get directionOptions() {
        return [
            { label: 'Inbound', value: 'Inbound' },
            { label: 'Outbound', value: 'Outbound' },
            { label: 'Both', value: 'Both' }
        ];
    }

    get directionFilterOptions() {
        return [
            { label: 'All Directions', value: '' },
            { label: 'Inbound', value: 'Inbound' },
            { label: 'Outbound', value: 'Outbound' },
            { label: 'Both', value: 'Both' }
        ];
    }

    get activeFilterOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Active', value: 'active' },
            { label: 'Inactive', value: 'inactive' }
        ];
    }

    get hasEndpointSelected() {
        return !!this.selectedEndpointId;
    }

    get hasMappings() {
        return this.filteredMappings && this.filteredMappings.length > 0;
    }

    get filteredMappingCount() {
        return this.filteredMappings ? this.filteredMappings.length : 0;
    }

    get noRowsSelected() {
        return !this.mappings.some(m => m.isSelected);
    }

    @wire(getEndpointHealth)
    wiredEndpoints(result) {
        this.wiredEndpointResult = result;
        if (result.data) {
            this.endpointOptions = [
                { label: '-- Select Endpoint --', value: '' },
                ...result.data.map(ep => ({
                    label: `${ep.Integration_Key__c || ep.Name} (${ep.HTTP_Method__c || 'N/A'})`,
                    value: ep.Id
                }))
            ];
        } else if (result.error) {
            this.handleError(result.error);
        }
    }

    handleEndpointChange(event) {
        if (this.hasUnsavedChanges) {
            if (!confirm('You have unsaved changes. Are you sure you want to switch endpoints?')) {
                return;
            }
        }
        this.selectedEndpointId = event.detail.value;
        if (this.selectedEndpointId) {
            this.loadMappings();
        } else {
            this.mappings = [];
            this.filteredMappings = [];
        }
    }

    handleDirectionFilterChange(event) {
        this.selectedDirection = event.detail.value;
        this.applyFilters();
    }

    handleActiveFilterChange(event) {
        this.selectedActiveFilter = event.detail.value;
        this.applyFilters();
    }

    loadMappings() {
        this.isLoading = true;
        // In production, this would call an Apex method to get mappings for the endpoint
        // For now, we initialize with empty state
        // A real implementation would be:
        // getMappingsForEndpoint({ endpointId: this.selectedEndpointId })
        //   .then(data => { ... })
        //   .catch(error => { ... });

        // Simulated empty load for now - the actual data would come from Apex
        this.mappings = [];
        this.filteredMappings = [];
        this.hasUnsavedChanges = false;
        this.isLoading = false;
    }

    applyFilters() {
        if (!this.mappings) {
            this.filteredMappings = [];
            return;
        }

        let result = [...this.mappings];

        if (this.selectedDirection) {
            result = result.filter(m => m.Direction__c === this.selectedDirection);
        }

        if (this.selectedActiveFilter) {
            const isActive = this.selectedActiveFilter === 'active';
            result = result.filter(m => m.Active__c === isActive);
        }

        // Sort by order
        result.sort((a, b) => (a.Order__c || 0) - (b.Order__c || 0));

        this.filteredMappings = result;
    }

    handleAddRow() {
        const newOrder = this.mappings.length > 0
            ? Math.max(...this.mappings.map(m => m.Order__c || 0)) + 1
            : 1;

        const newMapping = {
            clientId: generateClientId(),
            isNew: true,
            isSelected: false,
            isDirty: true,
            rowClass: 'slds-hint-parent',
            Integration_Endpoint__c: this.selectedEndpointId,
            Mapping_Name__c: '',
            Source_Field__c: '',
            Target_Field__c: '',
            Target_Object__c: '',
            Direction__c: 'Outbound',
            Active__c: true,
            Order__c: newOrder
        };

        this.mappings = [...this.mappings, newMapping];
        this.hasUnsavedChanges = true;
        this.applyFilters();
    }

    handleInlineEdit(event) {
        const clientId = event.target.dataset.clientId;
        const field = event.target.dataset.field;
        const value = event.detail ? event.detail.value : event.target.value;

        this.mappings = this.mappings.map(m => {
            if (m.clientId === clientId) {
                return { ...m, [field]: value, isDirty: true };
            }
            return m;
        });

        this.hasUnsavedChanges = true;
        this.applyFilters();
    }

    handleInlineCheckbox(event) {
        const clientId = event.target.dataset.clientId;
        const field = event.target.dataset.field;
        const value = event.target.checked;

        this.mappings = this.mappings.map(m => {
            if (m.clientId === clientId) {
                return { ...m, [field]: value, isDirty: true };
            }
            return m;
        });

        this.hasUnsavedChanges = true;
        this.applyFilters();
    }

    handleRowSelect(event) {
        const clientId = event.target.dataset.clientId;
        const isChecked = event.target.checked;

        this.mappings = this.mappings.map(m => {
            if (m.clientId === clientId) {
                return { ...m, isSelected: isChecked };
            }
            return m;
        });

        this.allRowsSelected = this.mappings.every(m => m.isSelected);
        this.applyFilters();
    }

    handleSelectAll(event) {
        const isChecked = event.target.checked;
        this.allRowsSelected = isChecked;
        this.mappings = this.mappings.map(m => ({
            ...m,
            isSelected: isChecked
        }));
        this.applyFilters();
    }

    handleMoveRow(event) {
        const clientId = event.target.dataset.clientId;
        const action = event.target.dataset.action;
        const index = this.mappings.findIndex(m => m.clientId === clientId);

        if (index === -1) return;

        const newMappings = [...this.mappings];

        if (action === 'move-up' && index > 0) {
            // Swap order values
            const currentOrder = newMappings[index].Order__c;
            newMappings[index] = { ...newMappings[index], Order__c: newMappings[index - 1].Order__c, isDirty: true };
            newMappings[index - 1] = { ...newMappings[index - 1], Order__c: currentOrder, isDirty: true };
            // Swap positions
            [newMappings[index], newMappings[index - 1]] = [newMappings[index - 1], newMappings[index]];
        } else if (action === 'move-down' && index < newMappings.length - 1) {
            const currentOrder = newMappings[index].Order__c;
            newMappings[index] = { ...newMappings[index], Order__c: newMappings[index + 1].Order__c, isDirty: true };
            newMappings[index + 1] = { ...newMappings[index + 1], Order__c: currentOrder, isDirty: true };
            [newMappings[index], newMappings[index + 1]] = [newMappings[index + 1], newMappings[index]];
        }

        this.mappings = newMappings;
        this.hasUnsavedChanges = true;
        this.applyFilters();
    }

    handleDeleteRow(event) {
        const clientId = event.currentTarget.dataset.clientId;
        const mapping = this.mappings.find(m => m.clientId === clientId);

        if (!mapping) return;

        if (mapping.Id) {
            // Existing record - delete from server
            this.isLoading = true;
            deleteRecord(mapping.Id)
                .then(() => {
                    this.mappings = this.mappings.filter(m => m.clientId !== clientId);
                    this.applyFilters();
                    this.showToast('Success', 'Field mapping deleted.', 'success');
                })
                .catch(error => {
                    this.handleError(error);
                })
                .finally(() => {
                    this.isLoading = false;
                });
        } else {
            // New unsaved record - just remove from list
            this.mappings = this.mappings.filter(m => m.clientId !== clientId);
            this.applyFilters();
        }
    }

    handleDeleteSelected() {
        const selectedMappings = this.mappings.filter(m => m.isSelected);
        if (selectedMappings.length === 0) return;

        const existingIds = selectedMappings.filter(m => m.Id).map(m => m.Id);
        const clientIds = selectedMappings.map(m => m.clientId);

        this.isLoading = true;

        // Delete existing records from server
        const deletePromises = existingIds.map(id => deleteRecord(id));

        Promise.all(deletePromises)
            .then(() => {
                this.mappings = this.mappings.filter(m => !clientIds.includes(m.clientId));
                this.allRowsSelected = false;
                this.applyFilters();
                this.showToast('Success', `${selectedMappings.length} mapping(s) deleted.`, 'success');
            })
            .catch(error => {
                this.handleError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSaveAll() {
        // Validate all rows
        const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox');
        let isValid = true;
        inputs.forEach(input => {
            if (!input.reportValidity()) {
                isValid = false;
            }
        });

        if (!isValid) {
            this.showToast('Validation Error', 'Please correct all errors before saving.', 'error');
            return;
        }

        const dirtyMappings = this.mappings.filter(m => m.isDirty);
        if (dirtyMappings.length === 0) {
            this.showToast('Info', 'No changes to save.', 'info');
            return;
        }

        this.isSaving = true;
        this.isLoading = true;

        const savePromises = dirtyMappings.map(mapping => {
            const fields = {
                Integration_Endpoint__c: mapping.Integration_Endpoint__c,
                Mapping_Name__c: mapping.Mapping_Name__c,
                Source_Field__c: mapping.Source_Field__c,
                Target_Field__c: mapping.Target_Field__c,
                Target_Object__c: mapping.Target_Object__c,
                Direction__c: mapping.Direction__c,
                Active__c: mapping.Active__c,
                Order__c: mapping.Order__c
            };

            if (mapping.Id && !mapping.isNew) {
                // Update
                fields.Id = mapping.Id;
                return updateRecord({ fields });
            }
            // Create
            return createRecord({
                apiName: FIELD_MAPPING_OBJECT,
                fields: fields
            });
        });

        Promise.all(savePromises)
            .then(results => {
                // Update local data with server IDs for new records
                let resultIndex = 0;
                this.mappings = this.mappings.map(m => {
                    if (m.isDirty) {
                        const result = results[resultIndex];
                        resultIndex++;
                        return {
                            ...m,
                            Id: result.id || m.Id,
                            isNew: false,
                            isDirty: false
                        };
                    }
                    return m;
                });

                this.hasUnsavedChanges = false;
                this.applyFilters();
                this.showToast('Success', `${dirtyMappings.length} mapping(s) saved successfully.`, 'success');
            })
            .catch(error => {
                this.handleError(error);
            })
            .finally(() => {
                this.isSaving = false;
                this.isLoading = false;
            });
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