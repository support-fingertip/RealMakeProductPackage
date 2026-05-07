import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getPendingApprovals from '@salesforce/apex/BulkApprovalController.getPendingApprovals';
import processApprovals from '@salesforce/apex/BulkApprovalController.processApprovals';
import delegateApprovals from '@salesforce/apex/BulkApprovalController.delegateApprovals';

export default class BulkApprovalManager extends LightningElement {

    @track approvals = [];
    @track filteredApprovals = [];
    @track selectedRows = [];

    searchTerm = '';
    selectedType = '';
    selectedStatus = 'Pending';
    isLoading = false;

    wiredResult;

    columns = [
        { label: 'Record Name', fieldName: 'recordName', sortable: true },
        { label: 'Type', fieldName: 'recordType', sortable: true },
        { label: 'Submitted By', fieldName: 'submittedBy', sortable: true },
        {
            label: 'Submitted Date',
            fieldName: 'submittedDate',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            }
        },
        {
            label: 'Status',
            fieldName: 'status',
            cellAttributes: {
                class: { fieldName: 'statusClass' }
            }
        }
    ];

    get statusOptions() {
        return [
            { label: 'All Statuses', value: '' },
            { label: 'Pending', value: 'Pending' },
            { label: 'Approved', value: 'Approved' },
            { label: 'Rejected', value: 'Rejected' }
        ];
    }

    get typeOptions() {
        const uniqueTypes = [...new Set(this.approvals.map(a => a.recordType))];
        return [
            { label: 'All Types', value: '' },
            ...uniqueTypes
                .filter(type => type)
                .map(type => ({ label: type, value: type }))
        ];
    }

    get hasRecords() {
        return this.filteredApprovals.length > 0;
    }

    get hasNoSelection() {
        return this.selectedRows.length === 0;
    }

    get totalRecords() {
        return this.approvals.length;
    }

    get filteredCount() {
        return this.filteredApprovals.length;
    }

    @wire(getPendingApprovals)
    wiredApprovals(result) {
        this.wiredResult = result;

        if (result.data) {
            this.approvals = result.data.map(item => ({
                ...item,
                statusClass: this.getStatusClass(item.status)
            }));
            this.filterApprovals();
        } else if (result.error) {
            this.showToast('Error', this.getError(result.error), 'error');
        }
    }

    getStatusClass(status) {
        if (status === 'Pending') return 'slds-text-color_warning';
        if (status === 'Approved') return 'slds-text-color_success';
        if (status === 'Rejected') return 'slds-text-color_error';
        return '';
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.filterApprovals();
    }

    handleTypeChange(event) {
        this.selectedType = event.detail.value;
        this.filterApprovals();
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
        this.filterApprovals();
    }

    filterApprovals() {
        let filtered = [...this.approvals];

        if (this.searchTerm) {
            const search = this.searchTerm.toLowerCase();
            filtered = filtered.filter(item =>
                (item.recordName && item.recordName.toLowerCase().includes(search)) ||
                (item.submittedBy && item.submittedBy.toLowerCase().includes(search))
            );
        }

        if (this.selectedType) {
            filtered = filtered.filter(item => item.recordType === this.selectedType);
        }

        if (this.selectedStatus) {
            filtered = filtered.filter(item => item.status === this.selectedStatus);
        }

        this.filteredApprovals = filtered;
    }

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows.map(row => row.workItemId);
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredResult)
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleApproveClick() {
        this.executeAction('Approve');
    }

    handleRejectClick() {
        this.executeAction('Reject');
    }

    handleDelegateClick() {
        const delegateUserId = prompt('Enter User Id to delegate to:');
        if (!delegateUserId) return;

        delegateApprovals({
            recordIds: this.selectedRows,
            delegateToUserId: delegateUserId
        })
        .then(result => {
            this.showToast('Success', result.message, 'success');
            this.handleRefresh();
        })
        .catch(error => {
            this.showToast('Error', this.getError(error), 'error');
        });
    }

    executeAction(action) {
        const comments = prompt(`Enter comments for ${action}:`);

        processApprovals({
            recordIds: this.selectedRows,
            action: action,
            comments: comments
        })
        .then(result => {
            this.showToast('Success', result.message, 'success');
            this.selectedRows = [];
            this.handleRefresh();
        })
        .catch(error => {
            this.showToast('Error', this.getError(error), 'error');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    getError(error) {
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return 'Unknown error';
    }
}