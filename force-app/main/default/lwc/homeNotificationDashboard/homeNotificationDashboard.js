import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getDashboardConfig from '@salesforce/apex/NotificationDashboardController.getDashboardConfig';
import getTabData from '@salesforce/apex/NotificationDashboardController.getTabData';
import updateRecordStatus from '@salesforce/apex/NotificationDashboardController.updateRecordStatus';
import moveLeadToFollowUp from '@salesforce/apex/NotificationDashboardController.moveLeadToFollowUp';

const SOBJECT_META = {
    'Followup__c': { label: 'Follow-ups', icon: 'standard:task', color: '#0176d3', gradient: 'linear-gradient(135deg, #e8f4fd 0%, #d4ecfc 100%)' },
    'Site_Visit__c': { label: 'Site Visits', icon: 'standard:visit', color: '#0d9dda', gradient: 'linear-gradient(135deg, #e3f5f9 0%, #cdf0f8 100%)' },
    'Lead__c': { label: 'Leads', icon: 'standard:lead', color: '#f88962', gradient: 'linear-gradient(135deg, #fff3ed 0%, #ffe8db 100%)' }
};

export default class HomeNotificationDashboard extends NavigationMixin(LightningElement) {

    // Config State
    @track tabs = [];
    @track fieldConfigs = [];
    currentProfile = '';
    @track activeTabKey = '';
    hasLoaded = false;

    // Tab Data State
    @track tabDataMap = {};
    @track isLoading = false;

    // Pagination State (TODAY_LEADS only)
    pageSize = 10;
    @track currentPage = 1;
    @track totalRecords = 0;

    // Modal State
    @track showStatusModal = false;
    @track modalRecord = null;
    @track modalTransition = null;
    @track modalAdditionalValue = '';
    @track modalRemarks = '';
    @track followUpSubject = 'Follow-up Call';
    @track followUpDueDate = '';
    @track followUpNotes = '';
    @track isProcessing = false;

    // Section collapse state
    @track collapsedSections = {};

    // Section "View All" state — tracks which sections show all records
    @track expandedSections = {};
    SECTION_PREVIEW_COUNT = 6;

    // Auto-Refresh
    _refreshIntervalId;
    REFRESH_INTERVAL_MS = 300000;

    // ═══════════════════════════════════════════════════════════════
    //  LIFECYCLE
    // ═══════════════════════════════════════════════════════════════

    connectedCallback() {
        this.loadDashboard();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._refreshIntervalId = setInterval(() => {
            this.refreshActiveTab();
        }, this.REFRESH_INTERVAL_MS);
    }

    disconnectedCallback() {
        if (this._refreshIntervalId) {
            clearInterval(this._refreshIntervalId);
        }
    }

    async loadDashboard() {
        this.isLoading = true;
        try {
            const config = await getDashboardConfig();
            this.tabs = config.tabs || [];
            this.fieldConfigs = config.fields || [];
            this.currentProfile = config.currentProfile;

            if (this.tabs.length > 0) {
                this.activeTabKey = this.tabs[0].tabKey;
            }

            await this.loadAllTabs();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
            this.hasLoaded = true;
        }
    }

    async loadAllTabs() {
        const promises = this.tabs.map(tab => {
            const isLeadsTab = tab.tabKey === 'TODAY_LEADS';
            return getTabData({
                tabKey: tab.tabKey,
                pageSize: isLeadsTab ? this.pageSize : 200,
                offset: isLeadsTab ? this.offset : 0
            }).then(result => ({ tabKey: tab.tabKey, result }));
        });

        const results = await Promise.allSettled(promises);
        const newDataMap = {};
        for (const r of results) {
            if (r.status === 'fulfilled') {
                newDataMap[r.value.tabKey] = r.value.result;
            }
        }
        this.tabDataMap = newDataMap;

        if (this.tabDataMap['TODAY_LEADS']) {
            this.totalRecords = this.tabDataMap['TODAY_LEADS'].totalCount;
        }
    }

    async loadSingleTab(tabKey) {
        try {
            const isLeadsTab = tabKey === 'TODAY_LEADS';
            const result = await getTabData({
                tabKey: tabKey,
                pageSize: isLeadsTab ? this.pageSize : 200,
                offset: isLeadsTab ? this.offset : 0
            });
            this.tabDataMap = { ...this.tabDataMap, [tabKey]: result };

            if (isLeadsTab) {
                this.totalRecords = result.totalCount;
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  COMPUTED GETTERS — Tabs
    // ═══════════════════════════════════════════════════════════════

    get processedTabs() {
        return this.tabs.map(tab => {
            const data = this.tabDataMap[tab.tabKey];
            const count = data ? data.totalCount : 0;
            const isActive = tab.tabKey === this.activeTabKey;
            return {
                ...tab,
                isActive,
                tabClass: 'tab-item' + (isActive ? ' tab-item--active' : ''),
                badgeLabel: String(count),
                contentClass: isActive
                    ? 'tab-content tab-content--active'
                    : 'tab-content'
            };
        });
    }

    get activeTabData() {
        return this.tabDataMap[this.activeTabKey] || { records: [], totalCount: 0, countsByObject: {}, recordsByObject: {} };
    }

    get activeTabConfig() {
        return this.tabs.find(t => t.tabKey === this.activeTabKey) || {};
    }

    get activeStatusActions() {
        const config = this.activeTabConfig;
        if (!config || !config.statusActions) return {};
        return config.statusActions;
    }

    get cardFieldConfigs() {
        return this.fieldConfigs.filter(f =>
            f.context === 'CARD' || f.context === 'BOTH'
        );
    }

    get emptyStateText() {
        return this.activeTabConfig.emptyStateText || 'No records found.';
    }

    // ═══════════════════════════════════════════════════════════════
    //  COMPUTED GETTERS — Summary Stats
    // ═══════════════════════════════════════════════════════════════

    get summaryStats() {
        const stats = [];
        for (const tab of this.tabs) {
            const data = this.tabDataMap[tab.tabKey];
            const count = data ? data.totalCount : 0;
            stats.push({
                key: tab.tabKey,
                label: tab.tabName,
                count: count,
                icon: tab.iconName
            });
        }
        return stats;
    }

    get totalAllRecords() {
        let total = 0;
        for (const tab of this.tabs) {
            const data = this.tabDataMap[tab.tabKey];
            if (data) total += data.totalCount;
        }
        return total;
    }

    // ═══════════════════════════════════════════════════════════════
    //  COMPUTED GETTERS — Grouped Sections (Key change)
    // ═══════════════════════════════════════════════════════════════

    get objectSections() {
        const data = this.activeTabData;
        const recordsByObj = data.recordsByObject || {};
        const countsByObj = data.countsByObject || {};
        const sObjectNames = this.activeTabConfig.sObjectNames || [];

        const sections = [];
        for (const objName of sObjectNames) {
            const meta = SOBJECT_META[objName] || { label: objName, icon: 'standard:record', color: '#706e6b', gradient: '#f3f3f3' };
            const allRecords = recordsByObj[objName] || [];
            const count = countsByObj[objName] || 0;
            const isCollapsed = this.collapsedSections[objName] === true;
            const isShowingAll = this.expandedSections[objName] === true;
            const hasMore = allRecords.length > this.SECTION_PREVIEW_COUNT;
            const visibleRecords = isShowingAll ? allRecords : allRecords.slice(0, this.SECTION_PREVIEW_COUNT);
            const hiddenCount = allRecords.length - this.SECTION_PREVIEW_COUNT;

            sections.push({
                sObjectName: objName,
                label: meta.label,
                icon: meta.icon,
                color: meta.color,
                gradient: meta.gradient,
                count: count,
                countLabel: String(count),
                records: visibleRecords,
                hasRecords: allRecords.length > 0,
                isCollapsed,
                isExpanded: !isCollapsed,
                chevronIcon: isCollapsed ? 'utility:chevronright' : 'utility:chevrondown',
                sectionStyle: `border-left: 4px solid ${meta.color};`,
                hasMore: hasMore,
                isShowingAll: isShowingAll,
                viewAllLabel: isShowingAll ? 'Show Less' : `View All ${hiddenCount > 0 ? '(' + allRecords.length + ')' : ''}`,
                viewAllIcon: isShowingAll ? 'utility:chevronup' : 'utility:chevrondown'
            });
        }
        return sections;
    }

    get hasAnySections() {
        return this.objectSections.length > 0;
    }

    get hasNoRecordsAtAll() {
        if (!this.hasLoaded) return false;
        const data = this.activeTabData;
        return data.totalCount === 0;
    }

    // ═══════════════════════════════════════════════════════════════
    //  COMPUTED GETTERS — Pagination (Leads tab)
    // ═══════════════════════════════════════════════════════════════

    get isLeadsTab() {
        return this.activeTabKey === 'TODAY_LEADS';
    }

    get showPagination() {
        return this.isLeadsTab && this.totalRecords > this.pageSize;
    }

    get offset() {
        return (this.currentPage - 1) * this.pageSize;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalRecords / this.pageSize));
    }

    get pageInfo() {
        return `Page ${this.currentPage} of ${this.totalPages}`;
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    // ═══════════════════════════════════════════════════════════════
    //  COMPUTED GETTERS — Modal
    // ═══════════════════════════════════════════════════════════════

    get modalTitle() {
        if (!this.modalTransition) return 'Update Status';
        return this.modalTransition.label;
    }

    get modalRecordTitle() {
        return this.modalRecord ? this.modalRecord.title : '';
    }

    get modalHasRequiredField() {
        return this.modalTransition && this.modalTransition.requiresField;
    }

    get modalRequiredFieldLabel() {
        if (!this.modalTransition || !this.modalTransition.requiresField) return '';
        return this.modalTransition.requiresField
            .replace(/__c$/, '')
            .replace(/_/g, ' ');
    }

    get modalRequiredFieldType() {
        if (!this.modalTransition) return 'text';
        const ft = this.modalTransition.fieldType;
        if (ft === 'datetime') return 'datetime-local';
        if (ft === 'date') return 'date';
        return 'text';
    }

    get modalHasRemarksField() {
        return this.modalTransition && this.modalTransition.remarksField;
    }

    get modalRemarksRequired() {
        return this.modalTransition && this.modalTransition.remarksRequired === true;
    }

    get modalConfirmVariant() {
        if (!this.modalTransition) return 'brand';
        return this.modalTransition.variant || 'brand';
    }

    get modalRequiresFollowUp() {
        return this.modalTransition && this.modalTransition.requiresFollowUp === true;
    }

    // ═══════════════════════════════════════════════════════════════
    //  TAB HANDLERS
    // ═══════════════════════════════════════════════════════════════

    handleTabClick(event) {
        this.activeTabKey = event.currentTarget.dataset.tabKey;
        if (this.isLeadsTab) {
            this.currentPage = 1;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  SECTION TOGGLE
    // ═══════════════════════════════════════════════════════════════

    handleSectionToggle(event) {
        const objName = event.currentTarget.dataset.section;
        this.collapsedSections = {
            ...this.collapsedSections,
            [objName]: !this.collapsedSections[objName]
        };
    }

    handleViewAll(event) {
        const objName = event.currentTarget.dataset.section;
        this.expandedSections = {
            ...this.expandedSections,
            [objName]: !this.expandedSections[objName]
        };
    }

    // ═══════════════════════════════════════════════════════════════
    //  PAGINATION HANDLERS
    // ═══════════════════════════════════════════════════════════════

    handleFirst() {
        this.currentPage = 1;
        this.loadSingleTab('TODAY_LEADS');
    }

    handlePrevious() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.loadSingleTab('TODAY_LEADS');
        }
    }

    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.loadSingleTab('TODAY_LEADS');
        }
    }

    handleLast() {
        this.currentPage = this.totalPages;
        this.loadSingleTab('TODAY_LEADS');
    }

    // ═══════════════════════════════════════════════════════════════
    //  STATUS CHANGE
    // ═══════════════════════════════════════════════════════════════

    handleStatusChange(event) {
        const { record, transition } = event.detail;
        this.modalRecord = record;
        this.modalTransition = transition;
        this.modalAdditionalValue = '';
        this.modalRemarks = '';
        this.followUpSubject = 'Follow-up Call';
        this.followUpDueDate = '';
        this.followUpNotes = '';
        this.showStatusModal = true;
    }

    closeStatusModal() {
        this.showStatusModal = false;
        this.modalRecord = null;
        this.modalTransition = null;
        this.modalAdditionalValue = '';
        this.modalRemarks = '';
        this.followUpSubject = 'Follow-up Call';
        this.followUpDueDate = '';
        this.followUpNotes = '';
    }

    handleModalFieldChange(event) {
        this.modalAdditionalValue = event.target.value;
    }

    handleModalRemarksChange(event) {
        this.modalRemarks = event.target.value;
    }

    handleFollowUpSubjectChange(event) {
        this.followUpSubject = event.target.value;
    }

    handleFollowUpDueDateChange(event) {
        this.followUpDueDate = event.target.value;
    }

    handleFollowUpNotesChange(event) {
        this.followUpNotes = event.target.value;
    }

    async confirmStatusChange() {
        // Follow-up specific validation
        if (this.modalRequiresFollowUp) {
            if (!this.followUpSubject) {
                this.showToast('Error', 'Follow-up Subject is required.', 'error');
                return;
            }
            if (!this.followUpDueDate) {
                this.showToast('Error', 'Follow-up Due Date is required.', 'error');
                return;
            }
            const selectedDate = new Date(this.followUpDueDate);
            if (selectedDate <= new Date()) {
                this.showToast('Error', 'Follow-up Due Date must be in the future.', 'error');
                return;
            }
        }

        if (this.modalHasRequiredField && !this.modalAdditionalValue) {
            const fieldLabel = this.modalRequiredFieldLabel || 'Required field';
            this.showToast('Error', fieldLabel + ' is required.', 'error');
            return;
        }
        // Validate date fields are not in the future (present or past only)
        if (this.modalHasRequiredField && this.modalAdditionalValue
            && (this.modalRequiredFieldType === 'datetime-local' || this.modalRequiredFieldType === 'date')) {
            const selectedDate = new Date(this.modalAdditionalValue);
            const now = new Date();
            if (selectedDate > now) {
                const fieldLabel = this.modalRequiredFieldLabel || 'Date';
                this.showToast('Error', fieldLabel + ' cannot be in the future. Please select a present or past date.', 'error');
                return;
            }
        }
        if (this.modalRemarksRequired && !this.modalRemarks) {
            const remarksLabel = this.modalTransition.remarksField
                ? this.modalTransition.remarksField.replace(/__c$/, '').replace(/_/g, ' ')
                : 'Remarks';
            this.showToast('Error', remarksLabel + ' is required.', 'error');
            return;
        }

        this.isProcessing = true;
        try {
            // Follow-up path: call dedicated method
            if (this.modalRequiresFollowUp) {
                await moveLeadToFollowUp({
                    recordId: this.modalRecord.recordId,
                    subject: this.followUpSubject,
                    dueDate: new Date(this.followUpDueDate).toISOString(),
                    notes: this.followUpNotes || null
                });

                this.showToast('Success', 'Lead moved to Follow-up and follow-up created.', 'success');
            } else {
                // Generic status update path
                let additionalFields = {};
                if (this.modalTransition.requiresField && this.modalAdditionalValue) {
                    if (this.modalTransition.fieldType === 'datetime') {
                        additionalFields[this.modalTransition.requiresField] = new Date(this.modalAdditionalValue).toISOString();
                    } else {
                        additionalFields[this.modalTransition.requiresField] = this.modalAdditionalValue;
                    }
                }
                // Add remarks to the appropriate field
                if (this.modalTransition.remarksField && this.modalRemarks) {
                    additionalFields[this.modalTransition.remarksField] = this.modalRemarks;
                }

                const statusField = this._getStatusFieldForObject(this.modalRecord.sObjectName);

                await updateRecordStatus({
                    recordId: this.modalRecord.recordId,
                    sObjectName: this.modalRecord.sObjectName,
                    statusField: statusField,
                    newStatus: this.modalTransition.to,
                    additionalFieldsJson: JSON.stringify(additionalFields)
                });

                this.showToast('Success', 'Status updated successfully.', 'success');
            }
            this.closeStatusModal();
            await this.refreshActiveTab();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  REFRESH
    // ═══════════════════════════════════════════════════════════════

    handleRefresh() {
        this.refreshActiveTab();
    }

    async refreshActiveTab() {
        this.isLoading = true;
        try {
            await this.loadSingleTab(this.activeTabKey);
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  NAVIGATION
    // ═══════════════════════════════════════════════════════════════

    handleCallClick(event) {
        const { recordId, sObjectName, title } = event.detail;
        // Placeholder for 3rd party call integration
        this.showToast('Call', `Initiating call for ${title}...`, 'info');
    }

    handleRecordNavigate(event) {
        const { recordId, sObjectName } = event.detail;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: sObjectName,
                actionName: 'view'
            }
        });
    }

    // ═══════════════════════════════════════════════════════════════
    //  UTILITIES
    // ═══════════════════════════════════════════════════════════════

    _getStatusFieldForObject(sObjectName) {
        const actions = this.activeStatusActions;
        if (actions[sObjectName]) {
            return actions[sObjectName].statusField;
        }
        return 'Status__c';
    }

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
        if (Array.isArray(error)) {
            return error.map(e => this.reduceErrors(e)).join(', ');
        }
        return 'An unexpected error occurred. Please try again.';
    }
}