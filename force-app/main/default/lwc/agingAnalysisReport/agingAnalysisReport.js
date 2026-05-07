import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAgingOverview from '@salesforce/apex/AgingAnalysisService.getAgingOverview';
import getProjectOptions from '@salesforce/apex/AgingAnalysisService.getProjectOptions';

const BUCKET_COLORS = ['#2e844a', '#f39c12', '#e67e22', '#e74c3c', '#c0392b'];
const CURRENCY_SYMBOL = '\u20B9';

const DEMAND_COLUMNS = [
    { label: 'Demand', fieldName: 'recordName', type: 'text' },
    { label: 'Booking', fieldName: 'bookingName', type: 'text' },
    { label: 'Customer', fieldName: 'customerName', type: 'text' },
    { label: 'Unit', fieldName: 'unitName', type: 'text' },
    { label: 'Pending Amount', fieldName: 'amount', type: 'currency',
        typeAttributes: { currencyCode: 'INR' } },
    { label: 'Due Date', fieldName: 'dueDate', type: 'date' },
    { label: 'Days Overdue', fieldName: 'daysOverdue', type: 'number',
        cellAttributes: { class: { fieldName: 'overdueClass' } } },
    { label: 'Status', fieldName: 'status', type: 'text' }
];

const COMPLAINT_COLUMNS = [
    { label: 'Complaint', fieldName: 'recordName', type: 'text' },
    { label: 'Customer', fieldName: 'customerName', type: 'text' },
    { label: 'Unit', fieldName: 'unitName', type: 'text' },
    { label: 'Category', fieldName: 'category', type: 'text' },
    { label: 'Priority', fieldName: 'priority', type: 'text' },
    { label: 'Days Open', fieldName: 'daysOverdue', type: 'number' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Escalation', fieldName: 'escalationLevel', type: 'number' }
];

const SNAG_COLUMNS = [
    { label: 'Snag', fieldName: 'recordName', type: 'text' },
    { label: 'Booking', fieldName: 'bookingName', type: 'text' },
    { label: 'Unit', fieldName: 'unitName', type: 'text' },
    { label: 'Category', fieldName: 'category', type: 'text' },
    { label: 'Priority', fieldName: 'priority', type: 'text' },
    { label: 'Days Open', fieldName: 'daysOverdue', type: 'number' },
    { label: 'Expected Date', fieldName: 'dueDate', type: 'date' },
    { label: 'Status', fieldName: 'status', type: 'text' }
];

export default class AgingAnalysisReport extends LightningElement {
    @track activeTab = 'demands';
    @track selectedProject = '';
    @track isLoading = false;
    @track demandReport = null;
    @track complaintReport = null;
    @track snagReport = null;
    @track projectOptions = [{ label: 'All Projects', value: '' }];

    // Track expanded state per type
    expandedProjects = {};

    demandColumns = DEMAND_COLUMNS;
    complaintColumns = COMPLAINT_COLUMNS;
    snagColumns = SNAG_COLUMNS;

    @wire(getProjectOptions)
    wiredProjects({ data }) {
        if (data) {
            this.projectOptions = [
                { label: 'All Projects', value: '' },
                ...data
            ];
        }
    }

    connectedCallback() {
        this.loadData();
    }

    get formattedDemandTotal() {
        if (!this.demandReport || !this.demandReport.totalAmount) return CURRENCY_SYMBOL + ' 0';
        return CURRENCY_SYMBOL + ' ' + Number(this.demandReport.totalAmount).toLocaleString('en-IN');
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    handleProjectChange(event) {
        this.selectedProject = event.detail.value;
        this.loadData();
    }

    handleRefresh() {
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        try {
            const result = await getAgingOverview({
                projectId: this.selectedProject || null
            });

            this.demandReport = this.enrichReport(result.demands, 'demands');
            this.complaintReport = this.enrichReport(result.complaints, 'complaints');
            this.snagReport = this.enrichReport(result.snags, 'snags');
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body ? error.body.message : error.message,
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    enrichReport(report, type) {
        if (!report) return null;

        const totalCount = report.totalRecords || 0;
        const hasDemandAmounts = type === 'demands';
        const totalAmount = report.totalAmount || 0;

        report.buckets = (report.buckets || []).map((bucket, idx) => {
            const pct = totalCount > 0 ? Math.round((bucket.count / totalCount) * 100) : 0;
            return {
                ...bucket,
                formattedAmount: hasDemandAmounts
                    ? CURRENCY_SYMBOL + ' ' + Number(bucket.amount || 0).toLocaleString('en-IN')
                    : null,
                percentage: pct,
                headerClass: 'bucket-header bucket-header-' + idx,
                barClass: 'bucket-bar bucket-bar-' + idx,
                barStyle: 'width:' + pct + '%'
            };
        });

        report.projectBreakdown = (report.projectBreakdown || []).map(project => {
            const isExpanded = this.expandedProjects[type + '_' + project.projectId] || false;
            return {
                ...project,
                expanded: isExpanded,
                expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                formattedTotal: hasDemandAmounts
                    ? CURRENCY_SYMBOL + ' ' + Number(project.totalAmount || 0).toLocaleString('en-IN')
                    : null,
                buckets: (project.buckets || []).map(pb => ({
                    ...pb,
                    formattedAmount: hasDemandAmounts
                        ? CURRENCY_SYMBOL + ' ' + Number(pb.amount || 0).toLocaleString('en-IN')
                        : null
                })),
                records: (project.records || []).map(rec => ({
                    ...rec,
                    overdueClass: rec.daysOverdue > 90 ? 'slds-text-color_error' :
                        (rec.daysOverdue > 30 ? 'slds-text-color_weak' : '')
                }))
            };
        });

        return report;
    }

    handleToggleProject(event) {
        const projectId = event.currentTarget.dataset.project;
        const type = event.currentTarget.dataset.type;
        const key = type + '_' + projectId;
        this.expandedProjects[key] = !this.expandedProjects[key];

        // Re-enrich the affected report to update UI
        if (type === 'demands' && this.demandReport) {
            this.demandReport = { ...this.enrichReport(this.demandReport, 'demands') };
        } else if (type === 'complaints' && this.complaintReport) {
            this.complaintReport = { ...this.enrichReport(this.complaintReport, 'complaints') };
        } else if (type === 'snags' && this.snagReport) {
            this.snagReport = { ...this.enrichReport(this.snagReport, 'snags') };
        }
    }
}