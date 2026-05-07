import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getUniversalConfig from '@salesforce/apex/RoundRobinConfiguratorController.getUniversalConfig';
import getFieldPriorities from '@salesforce/apex/RoundRobinConfiguratorController.getFieldPriorities';
import saveFieldPriority from '@salesforce/apex/RoundRobinConfiguratorController.saveFieldPriority';
import deleteFieldPriority from '@salesforce/apex/RoundRobinConfiguratorController.deleteFieldPriority';

export default class RrFieldPrioritySetup extends LightningElement {
    @track priorities = [];
    @track leadFields = [];
    @track showAddForm = false;
    @track newEntry = { fieldApiName: '', fieldLabel: '', priority: 0, active: true };

    isSaving = false;
    wiredPrioritiesResult;
    wiredConfigResult;

    // ─── Wire ───────────────────────────────────────────────────────
    @wire(getUniversalConfig)
    wiredConfig(result) {
        this.wiredConfigResult = result;
        if (result.data) {
            this.leadFields = result.data.leadFields || [];
        }
    }

    @wire(getFieldPriorities)
    wiredPriorities(result) {
        this.wiredPrioritiesResult = result;
        if (result.data) {
            this.priorities = result.data.map(p => ({
                ...p,
                statusLabel: p.active ? 'Active' : 'Inactive',
                statusVariant: p.active ? 'success' : 'warning'
            }));
        } else if (result.error) {
            this.showToast('Error', 'Failed to load field priorities', 'error');
        }
    }

    // ─── Getters ────────────────────────────────────────────────────
    get addButtonLabel() {
        return this.showAddForm ? 'Cancel' : 'Add Field';
    }

    get hasPriorities() {
        return this.priorities && this.priorities.length > 0;
    }

    get fieldOptions() {
        const existingApis = new Set(this.priorities.map(p => p.fieldApiName));
        return this.leadFields
            .filter(f => !existingApis.has(f.apiName))
            .map(f => ({
                label: `${f.label} (${f.apiName})`,
                value: f.apiName
            }))
            .sort((a, b) => a.label.localeCompare(b.label));
    }

    get totalConfiguredWeight() {
        return this.priorities
            .filter(p => p.active)
            .reduce((sum, p) => sum + (p.priority || 0), 0);
    }

    // ─── Handlers ───────────────────────────────────────────────────
    handleToggleAdd() {
        this.showAddForm = !this.showAddForm;
        this.newEntry = { fieldApiName: '', fieldLabel: '', priority: 0, active: true };
    }

    handleNewFieldChange(event) {
        const apiName = event.detail.value;
        const fieldDef = this.leadFields.find(f => f.apiName === apiName);
        this.newEntry = {
            ...this.newEntry,
            fieldApiName: apiName,
            fieldLabel: fieldDef ? fieldDef.label : apiName
        };
    }

    handleNewPriorityChange(event) {
        this.newEntry = { ...this.newEntry, priority: parseInt(event.target.value, 10) || 0 };
    }

    handleNewActiveChange(event) {
        this.newEntry = { ...this.newEntry, active: event.target.checked };
    }

    async handleSaveNew() {
        if (!this.newEntry.fieldApiName) {
            this.showToast('Required', 'Select a Lead field', 'warning');
            return;
        }
        if (this.newEntry.priority <= 0) {
            this.showToast('Required', 'Priority must be greater than 0', 'warning');
            return;
        }

        this.isSaving = true;
        try {
            await saveFieldPriority({
                fieldApiName: this.newEntry.fieldApiName,
                fieldLabel: this.newEntry.fieldLabel,
                priority: this.newEntry.priority,
                active: this.newEntry.active
            });
            this.showToast('Success', 'Field priority saved', 'success');
            this.showAddForm = false;
            this.newEntry = { fieldApiName: '', fieldLabel: '', priority: 0, active: true };
            await refreshApex(this.wiredPrioritiesResult);
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Error saving', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleInlineUpdate(event) {
        const fieldApi = event.target.dataset.fieldApi;
        const field = event.target.dataset.field;
        const entry = this.priorities.find(p => p.fieldApiName === fieldApi);
        if (!entry) return;

        let value;
        if (field === 'priority') {
            value = parseInt(event.target.value, 10) || 0;
        } else if (field === 'active') {
            value = event.target.checked;
        }

        this.isSaving = true;
        try {
            await saveFieldPriority({
                fieldApiName: entry.fieldApiName,
                fieldLabel: entry.fieldLabel,
                priority: field === 'priority' ? value : entry.priority,
                active: field === 'active' ? value : entry.active
            });
            this.showToast('Saved', `${entry.fieldLabel} updated`, 'success');
            await refreshApex(this.wiredPrioritiesResult);
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Error updating', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDelete(event) {
        const priorityId = event.target.dataset.id;
        this.isSaving = true;
        try {
            await deleteFieldPriority({ priorityId });
            this.showToast('Deleted', 'Field priority removed', 'success');
            await refreshApex(this.wiredPrioritiesResult);
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Error deleting', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}