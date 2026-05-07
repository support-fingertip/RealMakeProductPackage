import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFilterOptions from '@salesforce/apex/PerformanceTargetController.getFilterOptions';
import saveTarget from '@salesforce/apex/PerformanceTargetController.saveTarget';
import bulkCreateTargets from '@salesforce/apex/PerformanceTargetController.bulkCreateTargets';
import cloneTargets from '@salesforce/apex/PerformanceTargetController.cloneTargets';

export default class PerformanceTargetForm extends LightningElement {
    @api mode = 'create';
    @api editTarget = null;
    @api sourceFilter = null;

    @track metric = '';
    @track periodType = 'Monthly';
    @track periodStart = '';
    @track periodEnd = '';
    @track targetLevel = 'User';
    @track projectId = '';
    @track parentTargetId = '';
    @track description = '';
    @track targetValue = 0;
    @track assigneeId = '';
    @track teamRole = '';
    @track bulkAssignments = [];
    @track filterOptions = {};
    @track isLoading = false;
    @track showUserPicker = false;

    // Bulk mode temp fields
    _bulkUserId = '';
    _bulkUserName = '';
    _bulkValue = 0;
    _uniformValue = 0;

    // Clone mode
    @track clonePeriodStart = '';
    @track clonePeriodEnd = '';

    // Period selectors
    @track selectedMonth = '';
    @track selectedQuarter = '';
    @track selectedYear = '';

    connectedCallback() {
        this.loadFilterOptions();
        if (this.mode === 'edit' && this.editTarget) {
            this.populateFromEditTarget();
        }
    }

    async loadFilterOptions() {
        this.isLoading = true;
        try {
            const result = await getFilterOptions();
            this.filterOptions = result;
        } catch (error) {
            this.showToast('Error', 'Failed to load filter options: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    populateFromEditTarget() {
        if (!this.editTarget) return;
        this.metric = this.editTarget.Metric__c || '';
        this.periodType = this.editTarget.Period_Type__c || 'Monthly';
        this.periodStart = this.editTarget.Period_Start__c || '';
        this.periodEnd = this.editTarget.Period_End__c || '';
        this.targetLevel = this.editTarget.Target_Level__c || 'User';
        this.projectId = this.editTarget.Project__c || '';
        this.parentTargetId = this.editTarget.Parent_Target__c || '';
        this.description = this.editTarget.Description__c || '';
        this.targetValue = this.editTarget.Target_Value__c || 0;
        this.assigneeId = this.editTarget.Assignee__c || '';
        this.teamRole = this.editTarget.Team_Role__c || '';
    }

    // --- Computed getters ---

    get isCreateMode() {
        return this.mode === 'create';
    }

    get isEditMode() {
        return this.mode === 'edit';
    }

    get isCloneMode() {
        return this.mode === 'clone';
    }

    get isBulkMode() {
        return this.mode === 'bulk';
    }

    get isNotBulkMode() {
        return !this.isBulkMode;
    }

    get formTitle() {
        switch (this.mode) {
            case 'edit':
                return 'Edit Performance Target';
            case 'clone':
                return 'Clone Performance Targets';
            case 'bulk':
                return 'Bulk Assign Targets';
            default:
                return 'Create Performance Target';
        }
    }

    get isCustomPeriod() {
        return this.periodType === 'Custom';
    }

    get isMonthlyPeriod() {
        return this.periodType === 'Monthly';
    }

    get isQuarterlyPeriod() {
        return this.periodType === 'Quarterly';
    }

    get isYearlyPeriod() {
        return this.periodType === 'Yearly';
    }

    get showStandardPeriodSelector() {
        return !this.isCustomPeriod;
    }

    get showAssigneePicker() {
        return this.targetLevel === 'User' && !this.isBulkMode;
    }

    get showTeamPicker() {
        return this.targetLevel === 'Team';
    }

    get showOrganizationInfo() {
        return this.targetLevel === 'Organization';
    }

    get hasTeamOptions() {
        return this.teamOptions && this.teamOptions.length > 0;
    }

    get teamOptions() {
        if (!this.filterOptions.teams) return [];
        return this.filterOptions.teams.map(t => ({ label: t.label, value: t.value }));
    }

    get metricOptions() {
        if (!this.filterOptions.metrics) return [];
        return this.filterOptions.metrics.map(m => ({ label: m.label, value: m.value }));
    }

    get periodTypeOptions() {
        if (this.filterOptions.periods && this.filterOptions.periods.length > 0) {
            return this.filterOptions.periods.map(p => ({ label: p.label, value: p.value }));
        }
        return [];
    }

    get targetLevelOptions() {
        if (this.filterOptions.targetLevels && this.filterOptions.targetLevels.length > 0) {
            return this.filterOptions.targetLevels.map(l => ({ label: l.label, value: l.value }));
        }
        return [];
    }

    get projectOptions() {
        if (!this.filterOptions.projects) return [];
        return [
            { label: '-- None --', value: '' },
            ...this.filterOptions.projects.map(p => ({ label: p.label, value: p.value }))
        ];
    }

    get userOptions() {
        if (!this.filterOptions.users) return [];
        return this.filterOptions.users.map(u => ({ label: u.label, value: u.value }));
    }

    get periodOptions() {
        if (this.isMonthlyPeriod) {
            return this.monthOptions;
        } else if (this.isQuarterlyPeriod) {
            return this.quarterOptions;
        } else if (this.isYearlyPeriod) {
            return this.yearOptions;
        }
        return [];
    }

    get monthOptions() {
        const options = [];
        const now = new Date();
        const currentYear = now.getFullYear();
        const months = [
            'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'
        ];
        for (let year = currentYear; year <= currentYear + 1; year++) {
            for (let m = 0; m < 12; m++) {
                const value = `${year}-${String(m + 1).padStart(2, '0')}`;
                options.push({ label: `${months[m]} ${year}`, value });
            }
        }
        return options;
    }

    get quarterOptions() {
        const now = new Date();
        const currentYear = now.getFullYear();
        const quarters = ['Q1 (Jan-Mar)', 'Q2 (Apr-Jun)', 'Q3 (Jul-Sep)', 'Q4 (Oct-Dec)'];
        const options = [];
        for (let year = currentYear; year <= currentYear + 1; year++) {
            quarters.forEach((q, idx) => {
                options.push({ label: `${q} ${year}`, value: `${year}-Q${idx + 1}` });
            });
        }
        return options;
    }

    get yearOptions() {
        const now = new Date();
        const currentYear = now.getFullYear();
        const options = [];
        for (let year = currentYear; year <= currentYear + 1; year++) {
            options.push({ label: `${year}`, value: `${year}` });
        }
        return options;
    }

    get periodSelectorLabel() {
        if (this.isMonthlyPeriod) return 'Month';
        if (this.isQuarterlyPeriod) return 'Quarter';
        if (this.isYearlyPeriod) return 'Year';
        return 'Period';
    }

    get selectedPeriodValue() {
        if (this.isMonthlyPeriod) return this.selectedMonth;
        if (this.isQuarterlyPeriod) return this.selectedQuarter;
        if (this.isYearlyPeriod) return this.selectedYear;
        return '';
    }

    get hasBulkAssignments() {
        return this.bulkAssignments.length > 0;
    }

    get saveButtonLabel() {
        if (this.isCloneMode) return 'Clone Targets';
        if (this.isBulkMode) return 'Create Targets';
        return 'Save';
    }

    get sourceFilterDisplay() {
        if (!this.sourceFilter) return '';
        const parts = [];
        if (this.sourceFilter.metric) parts.push(`Metric: ${this.sourceFilter.metric}`);
        if (this.sourceFilter.periodStart) parts.push(`From: ${this.sourceFilter.periodStart}`);
        if (this.sourceFilter.periodEnd) parts.push(`To: ${this.sourceFilter.periodEnd}`);
        return parts.join(' | ');
    }

    // --- Event handlers ---

    handleMetricChange(event) {
        this.metric = event.detail.value;
    }

    handlePeriodTypeChange(event) {
        this.periodType = event.detail.value;
        this.periodStart = '';
        this.periodEnd = '';
        this.selectedMonth = '';
        this.selectedQuarter = '';
        this.selectedYear = '';
    }

    handlePeriodChange(event) {
        const value = event.detail.value;
        if (this.isMonthlyPeriod) {
            this.selectedMonth = value;
            this.calculateMonthlyDates(value);
        } else if (this.isQuarterlyPeriod) {
            this.selectedQuarter = value;
            this.calculateQuarterlyDates(value);
        } else if (this.isYearlyPeriod) {
            this.selectedYear = value;
            this.calculateYearlyDates(value);
        }
    }

    handlePeriodStartChange(event) {
        this.periodStart = event.detail.value;
    }

    handlePeriodEndChange(event) {
        this.periodEnd = event.detail.value;
    }

    handleTargetLevelChange(event) {
        this.targetLevel = event.detail.value;
        // Reset assignee and team when level changes
        this.assigneeId = '';
        this.teamRole = '';
    }

    handleTeamRoleChange(event) {
        this.teamRole = event.detail.value;
    }

    handleTeamRoleInputChange(event) {
        this.teamRole = event.target.value;
    }

    handleProjectChange(event) {
        this.projectId = event.detail.value;
    }

    handleAssigneeChange(event) {
        this.assigneeId = event.detail.value;
    }

    handleTargetValueChange(event) {
        this.targetValue = parseFloat(event.detail.value) || 0;
    }

    handleDescriptionChange(event) {
        this.description = event.detail.value;
    }

    // --- Bulk mode handlers ---

    handleBulkUserChange(event) {
        this._bulkUserId = event.detail.value;
        const user = (this.filterOptions.users || []).find(u => u.value === this._bulkUserId);
        this._bulkUserName = user ? user.label : '';
    }

    handleBulkValueInput(event) {
        this._bulkValue = parseFloat(event.detail.value) || 0;
    }

    handleAddUser() {
        if (!this._bulkUserId) {
            this.showToast('Warning', 'Please select a user.', 'warning');
            return;
        }
        const exists = this.bulkAssignments.find(a => a.userId === this._bulkUserId);
        if (exists) {
            this.showToast('Warning', 'User already added.', 'warning');
            return;
        }
        this.bulkAssignments = [
            ...this.bulkAssignments,
            {
                userId: this._bulkUserId,
                userName: this._bulkUserName,
                targetValue: this._bulkValue
            }
        ];
        this._bulkUserId = '';
        this._bulkUserName = '';
        this._bulkValue = 0;
    }

    handleRemoveUser(event) {
        const userId = event.currentTarget.dataset.userid;
        this.bulkAssignments = this.bulkAssignments.filter(a => a.userId !== userId);
    }

    handleBulkValueChange(event) {
        const userId = event.currentTarget.dataset.userid;
        const newValue = parseFloat(event.detail.value) || 0;
        this.bulkAssignments = this.bulkAssignments.map(a => {
            if (a.userId === userId) {
                return { ...a, targetValue: newValue };
            }
            return a;
        });
    }

    handleUniformValueChange(event) {
        this._uniformValue = parseFloat(event.detail.value) || 0;
    }

    handleApplyUniformValue() {
        if (this.bulkAssignments.length === 0) return;
        this.bulkAssignments = this.bulkAssignments.map(a => ({
            ...a,
            targetValue: this._uniformValue
        }));
    }

    // --- Clone mode handlers ---

    handleClonePeriodStartChange(event) {
        this.clonePeriodStart = event.detail.value;
    }

    handleClonePeriodEndChange(event) {
        this.clonePeriodEnd = event.detail.value;
    }

    // --- Period date calculations ---

    calculateMonthlyDates(value) {
        // value format: "YYYY-MM"
        const [year, month] = value.split('-').map(Number);
        const start = new Date(year, month - 1, 1);
        const end = new Date(year, month, 0);
        this.periodStart = this.formatDate(start);
        this.periodEnd = this.formatDate(end);
    }

    calculateQuarterlyDates(value) {
        // value format: "YYYY-Q1"
        const [year, q] = value.split('-Q');
        const quarter = parseInt(q, 10);
        const startMonth = (quarter - 1) * 3;
        const start = new Date(parseInt(year, 10), startMonth, 1);
        const end = new Date(parseInt(year, 10), startMonth + 3, 0);
        this.periodStart = this.formatDate(start);
        this.periodEnd = this.formatDate(end);
    }

    calculateYearlyDates(value) {
        // value format: "YYYY"
        const year = parseInt(value, 10);
        this.periodStart = `${year}-01-01`;
        this.periodEnd = `${year}-12-31`;
    }

    formatDate(d) {
        const year = d.getFullYear();
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    // --- Save ---

    async handleSave() {
        if (!this.validateForm()) return;

        this.isLoading = true;
        try {
            if (this.isCloneMode) {
                await this.handleCloneSave();
            } else if (this.isBulkMode) {
                await this.handleBulkSave();
            } else {
                await this.handleSingleSave();
            }
            this.dispatchEvent(new CustomEvent('targetsaved'));
        } catch (error) {
            this.showToast('Error', 'Failed to save: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleSingleSave() {
        const target = {
            Metric__c: this.metric,
            Period_Type__c: this.periodType,
            Period_Start__c: this.periodStart,
            Period_End__c: this.periodEnd,
            Target_Level__c: this.targetLevel,
            Target_Value__c: this.targetValue,
            Description__c: this.description
        };

        if (this.projectId) {
            target.Project__c = this.projectId;
        }
        if (this.assigneeId) {
            target.Assignee__c = this.assigneeId;
        }
        if (this.teamRole) {
            target.Team_Role__c = this.teamRole;
        }
        if (this.parentTargetId) {
            target.Parent_Target__c = this.parentTargetId;
        }
        if (this.isEditMode && this.editTarget) {
            target.Id = this.editTarget.Id;
        }

        await saveTarget({ targetJson: JSON.stringify(target) });
        const action = this.isEditMode ? 'updated' : 'created';
        this.showToast('Success', `Target ${action} successfully.`, 'success');
    }

    async handleBulkSave() {
        const bulkAssignment = {
            metric: this.metric,
            periodType: this.periodType,
            periodStart: this.periodStart,
            periodEnd: this.periodEnd,
            projectId: this.projectId || null,
            description: this.description || null,
            assignments: this.bulkAssignments.map(a => ({
                userId: a.userId,
                targetValue: a.targetValue
            }))
        };

        await bulkCreateTargets({ assignmentJson: JSON.stringify(bulkAssignment) });
        this.showToast('Success', `${this.bulkAssignments.length} targets created successfully.`, 'success');
    }

    async handleCloneSave() {
        const params = {
            sourceFilterJson: JSON.stringify(this.sourceFilter),
            newPeriodStart: this.clonePeriodStart,
            newPeriodEnd: this.clonePeriodEnd
        };

        await cloneTargets(params);
        this.showToast('Success', 'Targets cloned successfully.', 'success');
    }

    validateForm() {
        if (this.isCloneMode) {
            if (!this.clonePeriodStart || !this.clonePeriodEnd) {
                this.showToast('Validation Error', 'Please specify new period start and end dates.', 'error');
                return false;
            }
            return true;
        }

        if (!this.metric) {
            this.showToast('Validation Error', 'Please select a metric.', 'error');
            return false;
        }
        if (!this.periodStart || !this.periodEnd) {
            this.showToast('Validation Error', 'Please select a period.', 'error');
            return false;
        }

        if (this.isBulkMode) {
            if (this.bulkAssignments.length === 0) {
                this.showToast('Validation Error', 'Please add at least one user.', 'error');
                return false;
            }
        } else {
            if (this.targetValue <= 0) {
                this.showToast('Validation Error', 'Target value must be greater than zero.', 'error');
                return false;
            }
        }

        return true;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    // --- Utilities ---

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (!error) return 'An unexpected error occurred. Please try again.';
        if (typeof error === 'string') return error;
        if (error.body) {
            if (error.body.output && error.body.output.errors && error.body.output.errors.length > 0) {
                return error.body.output.errors.map(e => e.message).join(', ');
            }
            if (error.body.message) return error.body.message;
        }
        if (error.message) return error.message;
        return 'An unexpected error occurred. Please try again.';
    }
}