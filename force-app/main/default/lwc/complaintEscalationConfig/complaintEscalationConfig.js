import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getEscalationRules from '@salesforce/apex/ComplaintEscalationService.getEscalationRules';
import saveEscalationRule from '@salesforce/apex/ComplaintEscalationService.saveEscalationRule';
import deleteEscalationRule from '@salesforce/apex/ComplaintEscalationService.deleteEscalationRule';
import toggleEscalationRule from '@salesforce/apex/ComplaintEscalationService.toggleEscalationRule';
import getEscalationSummary from '@salesforce/apex/ComplaintEscalationService.getEscalationSummary';

const EMPTY_RULE = {
    id: '',
    priority: '',
    category: '',
    description: '',
    level1Days: 2,
    level1Notify: 'Assigned To',
    level1UserId: '',
    level2Days: 5,
    level2Notify: 'Project Head',
    level2UserId: '',
    level3Days: 10,
    level3Notify: 'Custom User',
    level3UserId: '',
    autoReassign: false,
    active: true
};

export default class ComplaintEscalationConfig extends LightningElement {
    @track rules = [];
    @track editRule = { ...EMPTY_RULE };
    @track showModal = false;
    @track isLoading = false;
    @track escalationSummary = [];

    wiredRulesResult;
    wiredSummaryResult;

    priorityOptions = [
        { label: '-- All Priorities --', value: '' },
        { label: 'Low', value: 'Low' },
        { label: 'Medium', value: 'Medium' },
        { label: 'High', value: 'High' }
    ];

    categoryOptions = [
        { label: '-- All Categories --', value: '' },
        { label: 'Construction Delay', value: 'Construction Delay' },
        { label: 'Property Issue', value: 'Property Issue' },
        { label: 'Booking Issue', value: 'Booking Issue' },
        { label: 'Payment Issue', value: 'Payment Issue' },
        { label: 'Agreement Issue', value: 'Agreement Issue' },
        { label: 'Invoice Issue', value: 'Invoice Issue' },
        { label: 'Possession Delay', value: 'Possession Delay' },
        { label: 'Maintenance Issue', value: 'Maintenance Issue' },
        { label: 'Amenity Issue', value: 'Amenity Issue' },
        { label: 'Staff Issue', value: 'Staff Issue' },
        { label: 'Technical Issue', value: 'Technical Issue' },
        { label: 'General Complaint', value: 'General Complaint' },
        { label: 'Other', value: 'Other' }
    ];

    notifyOptions = [
        { label: 'Assigned To', value: 'Assigned To' },
        { label: 'Owner', value: 'Owner' },
        { label: 'Project Head', value: 'Project Head' },
        { label: 'Custom User', value: 'Custom User' }
    ];

    @wire(getEscalationRules)
    wiredRules(result) {
        this.wiredRulesResult = result;
        if (result.data) {
            this.rules = result.data.map(rule => ({
                ...rule,
                projectName: rule.Project__r ? rule.Project__r.Name : null,
                level1UserName: rule.Level_1_User__r ? rule.Level_1_User__r.Name : null,
                level2UserName: rule.Level_2_User__r ? rule.Level_2_User__r.Name : null,
                level3UserName: rule.Level_3_User__r ? rule.Level_3_User__r.Name : null,
                cardClass: rule.Active__c ? 'rule-card rule-card-active' : 'rule-card rule-card-inactive',
                toggleLabel: rule.Active__c ? 'Deactivate' : 'Activate',
                toggleIcon: rule.Active__c ? 'utility:ban' : 'utility:check',
                priorityBadgeClass: 'filter-tag priority priority-' + (rule.Priority__c || '').toLowerCase()
            }));
        } else if (result.error) {
            this.showToast('Error', 'Failed to load escalation rules', 'error');
        }
    }

    @wire(getEscalationSummary)
    wiredSummary(result) {
        this.wiredSummaryResult = result;
        if (result.data) {
            const badgeClasses = { '1': 'summary-badge level-1-bg', '2': 'summary-badge level-2-bg', '3': 'summary-badge level-3-bg' };
            this.escalationSummary = result.data.map(item => ({
                ...item,
                badgeClass: badgeClasses[item.level] || 'summary-badge'
            }));
        }
    }

    get hasRules() {
        return this.rules && this.rules.length > 0;
    }

    get hasSummary() {
        return this.escalationSummary && this.escalationSummary.length > 0;
    }

    get modalTitle() {
        return this.editRule.id ? 'Edit Escalation Rule' : 'New Escalation Rule';
    }

    get showLevel1UserLookup() {
        return this.editRule.level1Notify === 'Custom User';
    }

    get showLevel2UserLookup() {
        return this.editRule.level2Notify === 'Custom User';
    }

    get showLevel3UserLookup() {
        return this.editRule.level3Notify === 'Custom User';
    }

    handleNewRule() {
        this.editRule = { ...EMPTY_RULE };
        this.showModal = true;
    }

    handleCloseModal() {
        this.showModal = false;
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.editRule = { ...this.editRule, [field]: event.target.value };
    }

    handleAutoReassignChange(event) {
        this.editRule = { ...this.editRule, autoReassign: event.target.checked };
    }

    handleActiveChange(event) {
        this.editRule = { ...this.editRule, active: event.target.checked };
    }

    handleRuleAction(event) {
        const action = event.detail.value;
        const ruleId = event.target.dataset.id;
        const rule = this.rules.find(r => r.Id === ruleId);

        if (action === 'edit') {
            this.editRule = {
                id: rule.Id,
                priority: rule.Priority__c || '',
                category: rule.Category__c || '',
                description: rule.Description__c || '',
                projectId: rule.Project__c || '',
                level1Days: rule.Level_1_Days__c,
                level1Notify: rule.Level_1_Notify__c || 'Assigned To',
                level1UserId: rule.Level_1_User__c || '',
                level2Days: rule.Level_2_Days__c,
                level2Notify: rule.Level_2_Notify__c || '',
                level2UserId: rule.Level_2_User__c || '',
                level3Days: rule.Level_3_Days__c,
                level3Notify: rule.Level_3_Notify__c || '',
                level3UserId: rule.Level_3_User__c || '',
                autoReassign: rule.Auto_Reassign__c || false,
                active: rule.Active__c
            };
            this.showModal = true;
        } else if (action === 'toggle') {
            this.handleToggle(ruleId, !rule.Active__c);
        } else if (action === 'delete') {
            this.handleDelete(ruleId);
        }
    }

    async handleSave() {
        if (!this.editRule.level1Days || this.editRule.level1Days < 1) {
            this.showToast('Validation Error', 'Level 1 Days Overdue is required and must be at least 1.', 'error');
            return;
        }

        if (this.editRule.level2Days && this.editRule.level2Days <= this.editRule.level1Days) {
            this.showToast('Validation Error', 'Level 2 days must be greater than Level 1 days.', 'error');
            return;
        }

        if (this.editRule.level3Days && this.editRule.level2Days && this.editRule.level3Days <= this.editRule.level2Days) {
            this.showToast('Validation Error', 'Level 3 days must be greater than Level 2 days.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            await saveEscalationRule({ ruleJson: JSON.stringify(this.editRule) });
            this.showToast('Success', 'Escalation rule saved successfully.', 'success');
            this.showModal = false;
            await Promise.all([
                refreshApex(this.wiredRulesResult),
                refreshApex(this.wiredSummaryResult)
            ]);
        } catch (error) {
            this.showToast('Error', error.body ? error.body.message : error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleToggle(ruleId, active) {
        try {
            await toggleEscalationRule({ ruleId, active });
            this.showToast('Success', `Rule ${active ? 'activated' : 'deactivated'}.`, 'success');
            await refreshApex(this.wiredRulesResult);
        } catch (error) {
            this.showToast('Error', error.body ? error.body.message : error.message, 'error');
        }
    }

    async handleDelete(ruleId) {
        try {
            await deleteEscalationRule({ ruleId });
            this.showToast('Success', 'Rule deleted.', 'success');
            await refreshApex(this.wiredRulesResult);
        } catch (error) {
            this.showToast('Error', error.body ? error.body.message : error.message, 'error');
        }
    }

    handleRefresh() {
        refreshApex(this.wiredRulesResult);
        refreshApex(this.wiredSummaryResult);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}