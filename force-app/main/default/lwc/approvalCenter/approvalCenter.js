import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

import getAllPendingApprovals from '@salesforce/apex/ApprovalCenterController.getAllPendingApprovals';
import processAction from '@salesforce/apex/ApprovalCenterController.processAction';
import processBulkAction from '@salesforce/apex/ApprovalCenterController.processBulkAction';
import getRecordDetails from '@salesforce/apex/ApprovalCenterController.getRecordDetails';
import getApprovalHistory from '@salesforce/apex/ApprovalCenterController.getApprovalHistory';
import getChildObjects from '@salesforce/apex/ApprovalCenterController.getChildObjects';
import getRelatedRecords from '@salesforce/apex/ApprovalCenterController.getRelatedRecords';

export default class ApprovalCenter extends NavigationMixin(LightningElement) {

    // ── Data ──────────────────────────────────────────────────────
    @track allApprovals = [];
    @track filteredApprovals = [];
    @track selectedRows = [];
    @track stats = { total: 0, standard: 0, discount: 0, dynamic: 0 };
    @track objectOptions = [];
    showRecordDetails = true;   // open by default
    showRelatedRecords = true;
    showApprovalHistory = true;

    // ── Filters ───────────────────────────────────────────────────
    searchTerm = '';
    selectedObjectType = '';
    selectedApprovalType = '';

    // ── Loading ───────────────────────────────────────────────────
    isLoading = false;

    // ── Detail Modal ──────────────────────────────────────────────
    showDetailModal = false;
    @track detailItem = null;
    @track detailFields = [];
    @track detailHistory = [];
    @track childObjects = [];
    @track selectedChildRelated = [];
    @track selectedChildColumns = [];
    selectedChildLabel = '';
    isLoadingDetail = false;
    isLoadingRelated = false;

    // ── Action Modal ──────────────────────────────────────────────
    showActionModal = false;
    actionType = '';
    @track actionItem = null;
    actionComments = '';
    isBulkAction = false;
    isProcessing = false;

    // ── Datatable Columns ─────────────────────────────────────────
    columns = [
        {
            label: 'Record Name', fieldName: 'recordUrl', type: 'url',
            typeAttributes: { label: { fieldName: 'recordName' }, target: '_blank' },
            sortable: true
        },
        { label: 'Object', fieldName: 'objectLabel', sortable: true },
        { label: 'Type', fieldName: 'approvalType', sortable: true },
        { label: 'Sub-Type', fieldName: 'approvalSubType' },
        { label: 'Submitted By', fieldName: 'submittedBy', sortable: true },
        {
            label: 'Submitted Date', fieldName: 'submittedDate', type: 'date',
            typeAttributes: {
                year: 'numeric', month: 'short', day: '2-digit',
                hour: '2-digit', minute: '2-digit'
            },
            sortable: true
        },
        {
            label: 'Status', fieldName: 'status',
            cellAttributes: { class: 'slds-text-color_warning' }
        },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'View Details', name: 'view' },
                    { label: 'Approve', name: 'approve' },
                    { label: 'Reject', name: 'reject' }
                ]
            }
        }
    ];

    historyColumns = [
        { label: 'Step / Discount', fieldName: 'label', type: 'text' },
        { label: 'Action', fieldName: 'action', type: 'text' },
        { label: 'Approver', fieldName: 'approverName', type: 'text' },
        { label: 'Comments', fieldName: 'comments', type: 'text' },
        {
            label: 'Timestamp', fieldName: 'timestamp', type: 'date',
            typeAttributes: {
                year: 'numeric', month: 'short', day: 'numeric',
                hour: '2-digit', minute: '2-digit'
            }
        }
    ];

    // ── Getters ───────────────────────────────────────────────────

    get statsTotal() { return 'Total: ' + this.stats.total; }
    get statsStandard() { return 'Standard: ' + this.stats.standard; }
    get statsDiscount() { return 'Discount: ' + this.stats.discount; }
    get statsDynamic() { return 'Dynamic: ' + this.stats.dynamic; }

    get approvalTypeOptions() {
        return [
            { label: 'All Types', value: '' },
            { label: 'Standard', value: 'Standard' },
            { label: 'Discount', value: 'Discount' },
            { label: 'Dynamic', value: 'Dynamic' }
        ];
    }

    get hasRecords() {
        return this.filteredApprovals.length > 0;
    }

    get hasNoSelection() {
        return this.selectedRows.length === 0;
    }

    get totalRecords() {
        return this.allApprovals.length;
    }

    get filteredCount() {
        return this.filteredApprovals.length;
    }

    get actionModalTitle() {
        return this.actionType + ' Approval';
    }

    get actionModalTypeLower() {
        return this.actionType.toLowerCase();
    }

    get selectedCount() {
        return this.selectedRows.length;
    }

    get hasDetailHistory() {
        return this.detailHistory && this.detailHistory.length > 0;
    }

    get hasChildObjects() {
        return this.childObjects && this.childObjects.length > 0;
    }

    get hasSelectedChildRecords() {
        return this.selectedChildRelated && this.selectedChildRelated.length > 0;
    }

    get actionModalConfirmVariant() {
        return this.actionType === 'Reject' ? 'destructive' : 'success';
    }

    // ── Lifecycle ─────────────────────────────────────────────────

    connectedCallback() {
        this.loadApprovals();
    }

    // ── Data Loading ──────────────────────────────────────────────

    async loadApprovals() {
        this.isLoading = true;
        try {
            const result = await getAllPendingApprovals();
            this.allApprovals = result.items || [];
            this.stats = result.stats || { total: 0, standard: 0, discount: 0, dynamic: 0 };
            this.objectOptions = result.objectOptions || [];
            this.filterApprovals();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Filtering ─────────────────────────────────────────────────

    filterApprovals() {
        let filtered = [...this.allApprovals];

        if (this.searchTerm) {
            const search = this.searchTerm.toLowerCase();
            filtered = filtered.filter(item =>
                (item.recordName && item.recordName.toLowerCase().includes(search)) ||
                (item.submittedBy && item.submittedBy.toLowerCase().includes(search)) ||
                (item.objectLabel && item.objectLabel.toLowerCase().includes(search)) ||
                (item.approvalSubType && item.approvalSubType.toLowerCase().includes(search))
            );
        }

        if (this.selectedObjectType) {
            filtered = filtered.filter(item => item.objectApiName === this.selectedObjectType);
        }

        if (this.selectedApprovalType) {
            filtered = filtered.filter(item => item.approvalType === this.selectedApprovalType);
        }

        this.filteredApprovals = filtered;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.filterApprovals();
    }

    handleObjectTypeChange(event) {
        this.selectedObjectType = event.detail.value;
        this.filterApprovals();
    }

    handleApprovalTypeChange(event) {
        this.selectedApprovalType = event.detail.value;
        this.filterApprovals();
    }

    handleRefresh() {
        this.selectedRows = [];
        this.loadApprovals();
    }

    // ── Row Selection & Actions ───────────────────────────────────

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows;
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'view':
                this.openDetailModal(row);
                break;
            case 'approve':
                this.openActionModal('Approve', row, false);
                break;
            case 'reject':
                this.openActionModal('Reject', row, false);
                break;
            default:
                break;
        }
    }

    // ── Bulk Actions ──────────────────────────────────────────────

    handleBulkApprove() {
        this.openActionModal('Approve', null, true);
    }

    handleBulkReject() {
        this.openActionModal('Reject', null, true);
    }

    // ── Detail Modal ──────────────────────────────────────────────

    async openDetailModal(item) {
        this.detailItem = item;
        this.detailFields = [];
        this.detailHistory = [];
        this.childObjects = [];
        this.selectedChildRelated = [];
        this.selectedChildColumns = [];
        this.selectedChildLabel = '';
        this.showDetailModal = true;
        this.isLoadingDetail = true;


        try {
            const [detailsResult, historyResult, childrenResult] = await Promise.allSettled([
                getRecordDetails({ recordId: item.recordId }),
                getApprovalHistory({ recordId: item.recordId, approvalType: item.approvalType }),
                getChildObjects({ recordId: item.recordId })
            ]);

            // ✅ Log ALL results so we see exact errors in browser console
            console.log('Details result:', JSON.stringify(detailsResult));
            console.log('History result:', JSON.stringify(historyResult));
            console.log('Children result:', JSON.stringify(childrenResult));

            // Handle record details
            if (detailsResult.status === 'fulfilled' && detailsResult.value) {
                this.detailFields = detailsResult.value.fields || [];
            } else {
                // ✅ Show ACTUAL error message not generic one
                const errMsg = detailsResult.reason
                    ? this.reduceErrors(detailsResult.reason)
                    : 'Unknown error';
                console.error('Details failed:', errMsg);
                this.showToast('Warning', 'Record details error: ' + errMsg, 'warning');
            }

            // Handle history
            if (historyResult.status === 'fulfilled') {
                this.detailHistory = (historyResult.value || []).map((h, idx) => ({
                    ...h, id: String(idx)
                }));
            } else {
                console.error('History failed:', this.reduceErrors(historyResult.reason));
            }

            // Handle child objects
            if (childrenResult.status === 'fulfilled') {
                this.childObjects = (childrenResult.value || []).map(c => ({
                    ...c,
                    badgeLabel: c.childLabel + ' (' + c.recordCount + ')'
                }));
            } else {
                console.error('Children failed:', this.reduceErrors(childrenResult.reason));
            }

        } catch (error) {
            this.showToast('Error', 'Failed to load details: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoadingDetail = false;
        }
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
            return error.map(e => e.message || String(e)).join(', ');
        }
        return 'An unexpected error occurred. Please try again.';
    }

    closeDetailModal() {
        this.showDetailModal = false;
        this.detailItem = null;
    }

    handleDetailApprove() {
        this.closeDetailModal();
        this.openActionModal('Approve', this.detailItem, false);
    }

    handleDetailReject() {
        this.closeDetailModal();
        this.openActionModal('Reject', this.detailItem, false);
    }

    async handleChildClick(event) {
        const childObj = event.currentTarget.dataset.child;
        const lookupField = event.currentTarget.dataset.lookup;
        const childLabel = event.currentTarget.dataset.label;

        this.selectedChildLabel = childLabel;
        this.selectedChildRelated = [];
        this.selectedChildColumns = [];
        this.isLoadingRelated = true;

        try {
            const result = await getRelatedRecords({
                recordId: this.detailItem.recordId,
                childObject: childObj,
                lookupField: lookupField
            });
            this.selectedChildColumns = (result.columns || []).map(col => ({
                label: col.label,
                fieldName: col.fieldName,
                type: col.type || 'text'
            }));
            this.selectedChildRelated = result.records || [];
        } catch (error) {
            this.showToast('Error', 'Failed to load related records: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoadingRelated = false;
        }
    }

    // ── Action Modal ──────────────────────────────────────────────

    openActionModal(type, item, isBulk) {
        this.actionType = type;
        this.actionItem = isBulk ? null : item;
        this.isBulkAction = isBulk;
        this.actionComments = '';
        this.showActionModal = true;
    }

    closeActionModal() {
        this.showActionModal = false;
        this.actionItem = null;
        this.actionComments = '';
    }

    handleCommentsChange(event) {
        this.actionComments = event.target.value;
    }

    async confirmAction() {
        this.isProcessing = true;

        try {
            let result;
            if (this.isBulkAction) {
                const items = this.selectedRows.map(row => ({
                    id: row.id,
                    approvalType: row.approvalType,
                    recordId: row.recordId,
                    workItemId: row.workItemId || null,
                    discountFieldNumber: row.discountFieldNumber || null
                }));
                result = await processBulkAction({
                    itemsJson: JSON.stringify(items),
                    action: this.actionType,
                    comments: this.actionComments
                });
            } else {
                const item = this.actionItem;
                result = await processAction({
                    approvalType: item.approvalType,
                    action: this.actionType,
                    recordId: item.recordId,
                    comments: this.actionComments,
                    workItemId: item.workItemId || null,
                    discountFieldNumber: item.discountFieldNumber || null,
                    configId: item.configId || null
                });
            }

            this.showToast(
                result.success ? 'Success' : 'Warning',
                result.message,
                result.success ? 'success' : 'warning'
            );

            this.closeActionModal();
            this.selectedRows = [];
            await this.loadApprovals();

        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // ── Navigation ────────────────────────────────────────────────

    navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: objectApiName,
                actionName: 'view'
            }
        });
    }

    // ── Helpers ───────────────────────────────────────────────────

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

    get hasDetailFields() {
        return this.detailFields && this.detailFields.length > 0;
    }

    get recordDetailsChevron() {
        return this.showRecordDetails ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get relatedRecordsChevron() {
        return this.showRelatedRecords ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get approvalHistoryChevron() {
        return this.showApprovalHistory ? 'utility:chevrondown' : 'utility:chevronright';
    }

    toggleRecordDetails() {
        this.showRecordDetails = !this.showRecordDetails;
    }

    toggleRelatedRecords() {
        this.showRelatedRecords = !this.showRelatedRecords;
    }

    toggleApprovalHistory() {
        this.showApprovalHistory = !this.showApprovalHistory;
    }
}