import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchLeads from '@salesforce/apex/BulkLeadReassignmentController.searchLeads';
import reassignLeads from '@salesforce/apex/BulkLeadReassignmentController.reassignLeads';
import reassignLeadsRoundRobin from '@salesforce/apex/BulkLeadReassignmentController.reassignLeadsRoundRobin';
import searchActiveUsers from '@salesforce/apex/BulkLeadReassignmentController.searchActiveUsers';
import tempAssignLeads from '@salesforce/apex/BulkLeadReassignmentController.tempAssignLeads';
import revokeTempAssignment from '@salesforce/apex/BulkLeadReassignmentController.revokeTempAssignment';
import searchUnits from '@salesforce/apex/BulkLeadReassignmentController.searchUnits';
import blockUnits from '@salesforce/apex/BulkLeadReassignmentController.blockUnits';
import unblockUnits from '@salesforce/apex/BulkLeadReassignmentController.unblockUnits';
import getProjects from '@salesforce/apex/BulkLeadReassignmentController.getProjects';
import searchTempSharedRecords from '@salesforce/apex/BulkLeadReassignmentController.searchTempSharedRecords';
import searchBlockedUnits from '@salesforce/apex/BulkLeadReassignmentController.searchBlockedUnits';
import createBlockRequest from '@salesforce/apex/BulkLeadReassignmentController.createBlockRequest';
import approveBlockRequest from '@salesforce/apex/BulkLeadReassignmentController.approveBlockRequest';
import rejectBlockRequest from '@salesforce/apex/BulkLeadReassignmentController.rejectBlockRequest';
import getPendingBlockRequests from '@salesforce/apex/BulkLeadReassignmentController.getPendingBlockRequests';
import getMyBlockRequests from '@salesforce/apex/BulkLeadReassignmentController.getMyBlockRequests';
import getCurrentUserManager from '@salesforce/apex/BulkLeadReassignmentController.getCurrentUserManager';
import searchLeadsForLookup from '@salesforce/apex/BulkLeadReassignmentController.searchLeadsForLookup';

export default class BulkLeadReassignment extends LightningElement {

    // ─── Tab State ────────────────────────────────────────────────────
    @track activeTab = 'reassignment';

    // ─── General State ────────────────────────────────────────────────
    @track isLoading = false;

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 1: REASSIGNMENT STATE
    // ═══════════════════════════════════════════════════════════════════
    @track hasSearched = false;
    @track searchResults = [];
    @track selectedLeadIds = [];

    @track filterOwnerId = null;
    @track filterProjectId = null;
    @track filterProjectName = '';
    @track projectSearchTerm = '';
    @track projectSearchResults = [];
    @track showProjectDropdown = false;
    _projectSearchTimeout;
    @track filterLeadStatus = '';
    @track filterLeadSource = '';
    @track filterLeadId = '';
    @track filterMobile = '';
    @track filterBucket = '';

    @track ownerSearchTerm = '';
    @track ownerLookupResults = [];
    @track showOwnerDropdown = false;
    @track selectedOwnerName = '';
    @track isOwnerSearching = false;
    _ownerSearchTimeout;

    @track targetUserId = null;
    @track targetUserName = '';
    @track targetUserSearchTerm = '';
    @track targetUserResults = [];
    @track showTargetUserDropdown = false;
    @track isTargetUserSearching = false;
    @track targetBucket = '';
    @track suppressNotifications = false;
    _targetUserSearchTimeout;

    @track isRoundRobin = false;
    @track rrSlots = [];
    _rrSearchTimeouts = {};
    _rrNextIndex = 0;

    @track showResultSummary = false;
    @track reassignResult = {};

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 2: TEMPORARY OWNERSHIP STATE
    // ═══════════════════════════════════════════════════════════════════
    @track tempFilterOwnerId = null;
    @track tempSelectedOwnerName = '';
    @track tempOwnerSearchTerm = '';
    @track tempOwnerFilterResults = [];
    @track showTempOwnerFilterDropdown = false;
    @track isTempOwnerFilterSearching = false;
    _tempOwnerFilterTimeout;

    @track tempFilterProjectId = '';
    @track tempFilterLeadId = '';

    @track tempHasSearched = false;
    @track tempSearchResults = [];
    @track tempSelectedLeadIds = [];

    @track tempTargetUserId = null;
    @track tempTargetUserName = '';
    @track tempTargetSearchTerm = '';
    @track tempTargetResults = [];
    @track showTempTargetDropdown = false;
    @track isTempTargetSearching = false;
    _tempTargetSearchTimeout;

    @track tempStartDate = '';
    @track tempEndDate = '';
    @track tempReason = '';
    @track tempLeadAccessLevel = 'Edit';
    @track tempShareFollowups = false;
    @track tempShareSiteVisits = false;

    @track showTempResultSummary = false;
    @track tempResult = {};

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 3: UNIT BLOCKING STATE
    // ═══════════════════════════════════════════════════════════════════
    @track unitFilterProject = '';
    @track unitFilterStatus = '';
    @track unitFilterNumber = '';
    @track unitHasSearched = false;
    @track unitSearchResults = [];
    @track selectedUnitIds = [];
    @track blockDays = null;
    @track blockReason = '';
    @track showUnitResultSummary = false;
    @track unitResult = {};
    @track projectOptions = [];
    @track isManagementBlock = false;

    // Blocking For user lookup
    @track blockingForUserId = null;
    @track blockingForUserName = '';
    @track blockingForSearchTerm = '';
    @track blockingForResults = [];
    @track showBlockingForDropdown = false;
    @track isBlockingForSearching = false;
    _blockingForSearchTimeout;

    // Lead lookup for blocking
    @track blockLeadId = null;
    @track blockLeadName = '';
    @track blockLeadSearchTerm = '';
    @track blockLeadResults = [];
    @track showBlockLeadDropdown = false;
    @track isBlockLeadSearching = false;
    _blockLeadSearchTimeout;

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 4: TEMPORARY SHARED RECORDS STATE
    // ═══════════════════════════════════════════════════════════════════
    @track tab4UserId = null;
    @track tab4UserName = '';
    @track tab4SearchTerm = '';
    @track tab4Results = [];
    @track tab4LookupResults = [];
    @track showTab4Dropdown = false;
    @track isTab4Searching = false;
    @track tab4HasSearched = false;
    @track tab4SelectedLeadIds = [];
    _tab4SearchTimeout;

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 5: BLOCKED UNITS VIEWER STATE
    // ═══════════════════════════════════════════════════════════════════
    @track tab5BlockedById = null;
    @track tab5BlockedByName = '';
    @track tab5BlockedBySearchTerm = '';
    @track tab5BlockedByResults = [];
    @track showTab5BlockedByDropdown = false;
    @track isTab5BlockedBySearching = false;
    _tab5BlockedByTimeout;

    @track tab5BlockingForId = null;
    @track tab5BlockingForName = '';
    @track tab5BlockingForSearchTerm = '';
    @track tab5BlockingForResults = [];
    @track showTab5BlockingForDropdown = false;
    @track isTab5BlockingForSearching = false;
    _tab5BlockingForTimeout;

    @track tab5ManagementOnly = false;
    @track tab5Results = [];
    @track tab5HasSearched = false;
    @track tab5SelectedUnitIds = [];

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 6: BLOCK REQUESTS STATE
    // ═══════════════════════════════════════════════════════════════════
    @track reqProject = '';
    @track reqUnitSearchTerm = '';
    @track reqUnitResults = [];
    @track showReqUnitDropdown = false;
    @track isReqUnitSearching = false;
    @track reqUnitId = null;
    @track reqUnitName = '';
    _reqUnitSearchTimeout;

    @track reqLeadSearchTerm = '';
    @track reqLeadResults = [];
    @track showReqLeadDropdown = false;
    @track isReqLeadSearching = false;
    @track reqLeadId = null;
    @track reqLeadName = '';
    _reqLeadSearchTimeout;

    @track reqBlockDays = null;
    @track reqReason = '';

    @track reqApproverId = null;
    @track reqApproverName = '';
    @track reqApproverSearchTerm = '';
    @track reqApproverResults = [];
    @track showReqApproverDropdown = false;
    @track isReqApproverSearching = false;
    _reqApproverSearchTimeout;

    @track defaultManagerName = '';
    @track defaultManagerId = null;

    @track pendingRequests = [];
    @track myRequests = [];
    @track showRejectModal = false;
    @track rejectNotes = '';
    @track rejectingRequestId = null;

    // ═══════════════════════════════════════════════════════════════════
    //  LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════

    connectedCallback() {
        this.initRoundRobinSlots();
        this.loadProjects();
        this.loadManagerAndRequests();
    }

    async loadProjects() {
        try {
            const projects = await getProjects();
            this.projectOptions = [
                { label: '-- All --', value: '' },
                ...projects.map(p => ({ label: p.Name, value: p.Id, maxDays: p.Max_Block_Days__c }))
            ];
        } catch (e) {
            this.projectOptions = [{ label: '-- All --', value: '' }];
        }
    }

    async loadManagerAndRequests() {
        try {
            const mgr = await getCurrentUserManager();
            if (mgr) {
                this.defaultManagerId = mgr.Id;
                this.defaultManagerName = mgr.Name;
                this.reqApproverId = mgr.Id;
                this.reqApproverName = mgr.Name;
            }
        } catch (e) { /* no manager */ }
        this.refreshBlockRequests();
    }

    async refreshBlockRequests() {
        try {
            this.pendingRequests = await getPendingBlockRequests();
        } catch (e) { this.pendingRequests = []; }
        try {
            this.myRequests = await getMyBlockRequests();
        } catch (e) { this.myRequests = []; }
    }

    initRoundRobinSlots() {
        this._rrNextIndex = 1;
        this.rrSlots = [this.createRRSlot(0)];
    }

    createRRSlot(index) {
        return {
            index: index,
            key: 'rr-slot-' + index,
            label: 'User ' + (this.rrSlots ? this.rrSlots.length + 1 : 1),
            userId: null, userName: '', searchTerm: '', results: [],
            showDropdown: false, isSearching: false, hasResults: false,
            hasSelected: false, canRemove: this.rrSlots ? this.rrSlots.length > 0 : false
        };
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    // ─── Columns ─────────────────────────────────────────────────────
    get columns() {
        return [
            { label: 'Lead ID', fieldName: 'leadIdName', type: 'text', sortable: true },
            { label: 'Lead Name', fieldName: 'leadName', type: 'text', sortable: true },
            { label: 'Owner', fieldName: 'ownerName', type: 'text', sortable: true },
            { label: 'Project', fieldName: 'project', type: 'text', sortable: true },
            { label: 'Lead Status', fieldName: 'leadStatus', type: 'text', sortable: true },
            { label: 'Primary Mobile', fieldName: 'primaryMobile', type: 'phone' },
            { label: 'Lead Bucket', fieldName: 'recordTypeName', type: 'text', sortable: true }
        ];
    }

    get failureColumns() {
        return [
            { label: 'Lead Name', fieldName: 'leadName', type: 'text' },
            { label: 'Reason', fieldName: 'reason', type: 'text', wrapText: true }
        ];
    }

    get unitColumns() {
        return [
            { label: 'Unit Number', fieldName: 'unitNumber', type: 'text', sortable: true },
            { label: 'Project', fieldName: 'projectName', type: 'text', sortable: true },
            { label: 'Tower', fieldName: 'towerName', type: 'text', sortable: true },
            { label: 'Floor', fieldName: 'floor', type: 'text' },
            { label: 'Type', fieldName: 'unitType', type: 'text' },
            { label: 'BHK', fieldName: 'bhkType', type: 'text' },
            { label: 'Status', fieldName: 'unitStatus', type: 'text', sortable: true },
            { label: 'Blocked By', fieldName: 'blockedByUser', type: 'text' },
            { label: 'Blocking For', fieldName: 'blockingForUser', type: 'text' },
            { label: 'Lead', fieldName: 'blockedByLead', type: 'text' },
            { label: 'Mgmt', fieldName: 'isManagementBlock', type: 'boolean' },
            { label: 'Block Reason', fieldName: 'blockReason', type: 'text' },
            { label: 'Block Expiry', fieldName: 'blockExpiry', type: 'date' }
        ];
    }

    get unitFailureColumns() {
        return [
            { label: 'Unit Number', fieldName: 'unitNumber', type: 'text' },
            { label: 'Reason', fieldName: 'reason', type: 'text', wrapText: true }
        ];
    }

    get tempShareColumns() {
        return [
            { label: 'Record ID', fieldName: 'historyName', type: 'text' },
            { label: 'Lead', fieldName: 'leadUrl', type: 'url', typeAttributes: { label: { fieldName: 'leadName' }, target: '_blank' } },
            { label: 'Project', fieldName: 'projectName', type: 'text' },
            { label: 'Owner', fieldName: 'ownerName', type: 'text' },
            { label: 'Temp Owner', fieldName: 'tempOwnerName', type: 'text' },
            { label: 'Start', fieldName: 'startDate', type: 'date' },
            { label: 'Expiry', fieldName: 'expiryDate', type: 'date' },
            { label: 'Access', fieldName: 'accessLevel', type: 'text' },
            { label: 'Followups', fieldName: 'shareFollowups', type: 'boolean' },
            { label: 'Site Visits', fieldName: 'shareSiteVisits', type: 'boolean' },
            { label: 'Reason', fieldName: 'reason', type: 'text' },
            { label: 'Assigned By', fieldName: 'assignedByName', type: 'text' }
        ];
    }

    get blockedUnitColumns() {
        return [
            { label: 'Unit Number', fieldName: 'unitUrl', type: 'url', typeAttributes: { label: { fieldName: 'unitNumber' }, target: '_blank' }, sortable: true },
            { label: 'Project', fieldName: 'projectName', type: 'text', sortable: true },
            { label: 'Tower', fieldName: 'towerName', type: 'text' },
            { label: 'Floor', fieldName: 'floor', type: 'text' },
            { label: 'BHK', fieldName: 'bhkType', type: 'text' },
            { label: 'Blocked By', fieldName: 'blockedByUser', type: 'text' },
            { label: 'Blocking For', fieldName: 'blockingForUser', type: 'text' },
            { label: 'Lead', fieldName: 'blockedByLead', type: 'text' },
            { label: 'Mgmt', fieldName: 'isManagementBlock', type: 'boolean' },
            { label: 'Reason', fieldName: 'blockReason', type: 'text' },
            { label: 'Expiry', fieldName: 'blockExpiry', type: 'date' }
        ];
    }

    get blockRequestColumns() {
        return [
            { label: 'Request ID', fieldName: 'requestName', type: 'text' },
            { label: 'Unit', fieldName: 'unitNumber', type: 'text' },
            { label: 'Project', fieldName: 'projectName', type: 'text' },
            { label: 'Lead', fieldName: 'leadName', type: 'text' },
            { label: 'Requested By', fieldName: 'requestedByName', type: 'text' },
            { label: 'Days', fieldName: 'blockDays', type: 'number' },
            { label: 'Reason', fieldName: 'reason', type: 'text' },
            { label: 'Mgmt', fieldName: 'isManagement', type: 'boolean' },
            { label: 'Status', fieldName: 'status', type: 'text' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'Approve', name: 'approve' },
                        { label: 'Reject', name: 'reject' }
                    ]
                }
            }
        ];
    }

    get myRequestColumns() {
        return [
            { label: 'Request ID', fieldName: 'requestName', type: 'text' },
            { label: 'Unit', fieldName: 'unitNumber', type: 'text' },
            { label: 'Project', fieldName: 'projectName', type: 'text' },
            { label: 'Lead', fieldName: 'leadName', type: 'text' },
            { label: 'Approver', fieldName: 'approverName', type: 'text' },
            { label: 'Days', fieldName: 'blockDays', type: 'number' },
            { label: 'Reason', fieldName: 'reason', type: 'text' },
            { label: 'Status', fieldName: 'status', type: 'text' },
            { label: 'Response Notes', fieldName: 'responseNotes', type: 'text' }
        ];
    }

    // ─── Picklist Options ────────────────────────────────────────────
    get leadStatusOptions() {
        return [
            { label: '-- All --', value: '' },
            { label: 'New Enquiry', value: 'New Enquiry' },
            { label: 'Follow-up', value: 'Follow-up' },
            { label: 'Site Visit Scheduled', value: 'Site Visit Scheduled' },
            { label: 'Site Visit Completed', value: 'Site Visit Completed' },
            { label: 'RNR', value: 'RNR' },
            { label: 'Unqualified', value: 'Unqualified' },
            { label: 'Rejected', value: 'Rejected' },
            { label: 'Request for Rejection', value: 'Request for Rejection' },
            { label: 'Closed Lost', value: 'Closed Lost' }
        ];
    }

    get leadSourceOptions() {
        return [
            { label: '-- All --', value: '' },
            { label: 'Walk-in', value: 'Walk-in' },
            { label: 'Digital', value: 'Digital' },
            { label: 'Channel Partner', value: 'Channel Partner' },
            { label: 'Referral', value: 'Referral' },
            { label: 'Event', value: 'Event' }
        ];
    }

    get bucketOptions() {
        return [
            { label: '-- All --', value: '' },
            { label: 'Pre Sales', value: 'Pre Sales' },
            { label: 'Sales', value: 'Sales' },
            { label: 'Channel Partners', value: 'Channel Partners' }
        ];
    }

    get targetBucketOptions() {
        return [
            { label: 'Pre Sales', value: 'Pre Sales' },
            { label: 'Sales', value: 'Sales' },
            { label: 'Channel Partners', value: 'Channel Partners' }
        ];
    }

    get unitStatusOptions() {
        return [
            { label: '-- All --', value: '' },
            { label: 'Available', value: 'Available' },
            { label: 'Blocked', value: 'Blocked' },
            { label: 'Booking In Progress', value: 'Booking In Progress' },
            { label: 'Booked', value: 'Booked' },
            { label: 'Sold', value: 'Sold' },
            { label: 'Not for Sale', value: 'Not for Sale' }
        ];
    }

    get tempAccessLevelOptions() {
        return [
            { label: 'Edit', value: 'Edit' },
            { label: 'Read', value: 'Read' }
        ];
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 1 COMPUTED GETTERS
    // ═══════════════════════════════════════════════════════════════════

    get isSearchDisabled() {
        return this.filterOwnerId == null && this.filterProjectId == null && !this.filterLeadStatus
            && !this.filterLeadSource && !this.filterLeadId && !this.filterMobile && !this.filterBucket;
    }

    get hasProjectResults() { return this.projectSearchResults && this.projectSearchResults.length > 0; }
    get hasResults()       { return this.searchResults && this.searchResults.length > 0; }
    get resultCount()      { return this.searchResults ? this.searchResults.length : 0; }
    get hasSelectedRows()  { return this.selectedLeadIds.length > 0; }
    get selectedCount()    { return this.selectedLeadIds.length; }
    get hasOwnerResults()  { return this.ownerLookupResults && this.ownerLookupResults.length > 0; }
    get hasTargetUserResults() { return this.targetUserResults && this.targetUserResults.length > 0; }
    get hasFailures()      { return this.reassignResult.failures && this.reassignResult.failures.length > 0; }
    get isNotRoundRobin()  { return !this.isRoundRobin; }

    get selectedRRUserIds() { return this.rrSlots.filter(s => s.userId).map(s => s.userId); }
    get selectedRRCount()   { return this.selectedRRUserIds.length; }

    get isReassignDisabled() {
        if (this.selectedLeadIds.length === 0 || !this.targetBucket) return true;
        if (this.isRoundRobin) return this.selectedRRUserIds.length === 0;
        return !this.targetUserId;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 2 COMPUTED GETTERS
    // ═══════════════════════════════════════════════════════════════════

    get todayDate() { return new Date().toISOString().split('T')[0]; }

    get isTempSearchDisabled() {
        return this.tempFilterOwnerId == null && !this.tempFilterProjectId && !this.tempFilterLeadId;
    }

    get tempHasResults()       { return this.tempSearchResults && this.tempSearchResults.length > 0; }
    get tempResultCount()      { return this.tempSearchResults ? this.tempSearchResults.length : 0; }
    get tempHasSelectedRows()  { return this.tempSelectedLeadIds.length > 0; }
    get tempSelectedCount()    { return this.tempSelectedLeadIds.length; }
    get hasTempOwnerFilterResults() { return this.tempOwnerFilterResults && this.tempOwnerFilterResults.length > 0; }
    get hasTempTargetResults() { return this.tempTargetResults && this.tempTargetResults.length > 0; }
    get hasTempFailures()      { return this.tempResult.failures && this.tempResult.failures.length > 0; }

    get isTempAssignDisabled() {
        return this.tempSelectedLeadIds.length === 0 || !this.tempTargetUserId || !this.tempStartDate || !this.tempEndDate;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 3 COMPUTED GETTERS
    // ═══════════════════════════════════════════════════════════════════

    get isUnitSearchDisabled() { return !this.unitFilterProject && !this.unitFilterNumber; }
    get unitHasResults()       { return this.unitSearchResults && this.unitSearchResults.length > 0; }
    get unitResultCount()      { return this.unitSearchResults ? this.unitSearchResults.length : 0; }
    get unitHasSelectedRows()  { return this.selectedUnitIds.length > 0; }
    get unitSelectedCount()    { return this.selectedUnitIds.length; }
    get hasUnitFailures()      { return this.unitResult.failures && this.unitResult.failures.length > 0; }

    get isBlockDisabled() {
        if (this.selectedUnitIds.length === 0 || !this.blockReason) return true;
        if (this.isManagementBlock) return false;
        return !this.blockDays || this.blockDays < 1;
    }

    get hasBlockingForResults() { return this.blockingForResults && this.blockingForResults.length > 0; }
    get hasBlockLeadResults() { return this.blockLeadResults && this.blockLeadResults.length > 0; }

    get selectedUnitMaxBlockDays() {
        if (this.unitFilterProject) {
            const opt = this.projectOptions.find(p => p.value === this.unitFilterProject);
            if (opt && opt.maxDays) return opt.maxDays;
        }
        return null;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 4 COMPUTED GETTERS
    // ═══════════════════════════════════════════════════════════════════
    get isTab4SearchDisabled() { return this.tab4UserId == null; }
    get tab4HasResults() { return this.tab4Results && this.tab4Results.length > 0; }
    get tab4ResultCount() { return this.tab4Results ? this.tab4Results.length : 0; }
    get hasTab4LookupResults() { return this.tab4LookupResults && this.tab4LookupResults.length > 0; }
    get tab4HasSelectedRows() { return this.tab4SelectedLeadIds.length > 0; }
    get tab4SelectedCount() { return this.tab4SelectedLeadIds.length; }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 5 COMPUTED GETTERS
    // ═══════════════════════════════════════════════════════════════════
    get tab5HasResults() { return this.tab5Results && this.tab5Results.length > 0; }
    get tab5ResultCount() { return this.tab5Results ? this.tab5Results.length : 0; }
    get hasTab5BlockedByResults() { return this.tab5BlockedByResults && this.tab5BlockedByResults.length > 0; }
    get hasTab5BlockingForResults() { return this.tab5BlockingForResults && this.tab5BlockingForResults.length > 0; }
    get tab5HasSelectedRows() { return this.tab5SelectedUnitIds.length > 0; }
    get tab5SelectedCount() { return this.tab5SelectedUnitIds.length; }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 6 COMPUTED GETTERS
    // ═══════════════════════════════════════════════════════════════════
    get hasPendingRequests() { return this.pendingRequests && this.pendingRequests.length > 0; }
    get hasMyRequests() { return this.myRequests && this.myRequests.length > 0; }
    get hasReqUnitResults() { return this.reqUnitResults && this.reqUnitResults.length > 0; }
    get hasReqLeadResults() { return this.reqLeadResults && this.reqLeadResults.length > 0; }
    get hasReqApproverResults() { return this.reqApproverResults && this.reqApproverResults.length > 0; }

    get isSubmitRequestDisabled() {
        return !this.reqUnitId || !this.reqReason || !this.reqApproverId;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 1: FILTER & OWNER LOOKUP HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        if (field === 'leadStatus')  this.filterLeadStatus = value;
        if (field === 'leadSource')  this.filterLeadSource = value;
        if (field === 'leadId')      this.filterLeadId = value;
        if (field === 'mobileNumber') {
            this.filterMobile = value.replace(/[^0-9]/g, '');
            event.target.value = this.filterMobile;
        }
        if (field === 'leadBucket')  this.filterBucket = value;
    }

    // ── Project Lookup (Tab 1) ───────────────────────────────────────
    handleProjectSearch(event) {
        this.projectSearchTerm = event.target.value;
        clearTimeout(this._projectSearchTimeout);
        if (this.projectSearchTerm.length < 1) {
            this.projectSearchResults = [];
            this.showProjectDropdown = false;
            return;
        }
        this.showProjectDropdown = true;
        this._projectSearchTimeout = setTimeout(() => {
            const term = this.projectSearchTerm.toLowerCase();
            this.projectSearchResults = this.projectOptions.filter(
                p => p.value && p.label !== '-- All --' && p.label.toLowerCase().includes(term)
            );
        }, 150);
    }
    handleProjectFocus() { if (!this.filterProjectName && this.projectSearchResults.length > 0) this.showProjectDropdown = true; }
    handleProjectBlur() { setTimeout(() => { this.showProjectDropdown = false; }, 200); }
    handleProjectSelect(event) {
        this.filterProjectId = event.currentTarget.dataset.recordId;
        this.filterProjectName = event.currentTarget.dataset.recordName;
        this.projectSearchTerm = '';
        this.showProjectDropdown = false;
        this.projectSearchResults = [];
    }
    handleClearProject() {
        this.filterProjectId = null;
        this.filterProjectName = '';
        this.projectSearchTerm = '';
        this.projectSearchResults = [];
    }

    handleClearFilters() {
        this.filterOwnerId = null;
        this.filterProjectId = null;
        this.filterProjectName = '';
        this.projectSearchTerm = '';
        this.projectSearchResults = [];
        this.filterLeadStatus = '';
        this.filterLeadSource = '';
        this.filterLeadId = '';
        this.filterMobile = '';
        this.filterBucket = '';
        this.selectedOwnerName = '';
        this.ownerSearchTerm = '';
        this.ownerLookupResults = [];
        this.hasSearched = false;
        this.searchResults = [];
        this.selectedLeadIds = [];
        this.resetReassignment();
    }

    handleOwnerSearch(event) {
        this.ownerSearchTerm = event.detail.value;
        if (this._ownerSearchTimeout) clearTimeout(this._ownerSearchTimeout);
        this._ownerSearchTimeout = setTimeout(() => { this.performOwnerSearch(this.ownerSearchTerm); }, 300);
    }
    handleOwnerFocus() { if (!this.selectedOwnerName) this.showOwnerDropdown = true; }
    handleOwnerBlur() { setTimeout(() => { this.showOwnerDropdown = false; }, 300); }

    async performOwnerSearch(term) {
        if (!term || term.length < 2) { this.ownerLookupResults = []; return; }
        this.isOwnerSearching = true; this.showOwnerDropdown = true;
        try { this.ownerLookupResults = await searchActiveUsers({ searchTerm: term }); }
        catch (e) { this.ownerLookupResults = []; }
        finally { this.isOwnerSearching = false; }
    }

    handleOwnerSelect(event) {
        this.filterOwnerId = event.currentTarget.dataset.recordId;
        this.selectedOwnerName = event.currentTarget.dataset.recordName;
        this.ownerSearchTerm = ''; this.showOwnerDropdown = false; this.ownerLookupResults = [];
    }

    handleClearOwner() {
        this.filterOwnerId = null; this.selectedOwnerName = '';
        this.ownerSearchTerm = ''; this.ownerLookupResults = [];
    }

    // ─── Target User Lookup (Single Mode) ─────────────────────────────
    handleTargetUserSearch(event) {
        this.targetUserSearchTerm = event.detail.value;
        if (this._targetUserSearchTimeout) clearTimeout(this._targetUserSearchTimeout);
        this._targetUserSearchTimeout = setTimeout(() => { this.performTargetUserSearch(this.targetUserSearchTerm); }, 300);
    }
    handleTargetUserFocus() { if (!this.targetUserName) this.showTargetUserDropdown = true; }
    handleTargetUserBlur() { setTimeout(() => { this.showTargetUserDropdown = false; }, 300); }

    async performTargetUserSearch(term) {
        if (!term || term.length < 2) { this.targetUserResults = []; return; }
        this.isTargetUserSearching = true; this.showTargetUserDropdown = true;
        try { this.targetUserResults = await searchActiveUsers({ searchTerm: term }); }
        catch (e) { this.targetUserResults = []; }
        finally { this.isTargetUserSearching = false; }
    }

    handleTargetUserSelect(event) {
        this.targetUserId = event.currentTarget.dataset.recordId;
        this.targetUserName = event.currentTarget.dataset.recordName;
        this.targetUserSearchTerm = ''; this.showTargetUserDropdown = false; this.targetUserResults = [];
    }
    handleClearTargetUser() {
        this.targetUserId = null; this.targetUserName = '';
        this.targetUserSearchTerm = ''; this.targetUserResults = [];
    }

    // ─── Round Robin Toggle ───────────────────────────────────────────
    handleRoundRobinToggle(event) {
        this.isRoundRobin = event.target.checked;
        if (!this.isRoundRobin) { this.initRoundRobinSlots(); }
        else { this.targetUserId = null; this.targetUserName = ''; this.targetUserSearchTerm = ''; this.targetUserResults = []; }
    }

    handleAddRRSlot() {
        const newSlot = {
            index: this._rrNextIndex, key: 'rr-slot-' + this._rrNextIndex,
            label: 'User ' + (this.rrSlots.length + 1),
            userId: null, userName: '', searchTerm: '', results: [],
            showDropdown: false, isSearching: false, hasResults: false, hasSelected: false, canRemove: true
        };
        this._rrNextIndex++;
        const updated = [...this.rrSlots, newSlot];
        this.rrSlots = updated.map((s, i) => ({ ...s, label: 'User ' + (i + 1), canRemove: updated.length > 1 }));
    }

    handleRemoveRRSlot(event) {
        const idx = parseInt(event.currentTarget.dataset.slotIndex, 10);
        let updated = this.rrSlots.filter(s => s.index !== idx);
        this.rrSlots = updated.map((s, i) => ({ ...s, label: 'User ' + (i + 1), canRemove: updated.length > 1 }));
    }

    handleRRUserSearch(event) {
        const idx = parseInt(event.currentTarget.dataset.slotIndex, 10);
        const term = event.detail.value;
        this.rrSlots = this.rrSlots.map((s, i) => i === idx ? { ...s, searchTerm: term } : s);
        if (this._rrSearchTimeouts[idx]) clearTimeout(this._rrSearchTimeouts[idx]);
        this._rrSearchTimeouts[idx] = setTimeout(() => { this.performRRUserSearch(idx, term); }, 300);
    }

    handleRRUserFocus(event) {
        const idx = parseInt(event.currentTarget.dataset.slotIndex, 10);
        const slot = this.rrSlots[idx];
        if (!slot.userName) this.rrSlots = this.rrSlots.map((s, i) => i === idx ? { ...s, showDropdown: true } : s);
    }

    handleRRUserBlur(event) {
        const idx = parseInt(event.currentTarget.dataset.slotIndex, 10);
        setTimeout(() => { this.rrSlots = this.rrSlots.map((s, i) => i === idx ? { ...s, showDropdown: false } : s); }, 300);
    }

    async performRRUserSearch(idx, term) {
        if (!term || term.length < 2) { this.rrSlots = this.rrSlots.map((s, i) => i === idx ? { ...s, results: [], hasResults: false } : s); return; }
        this.rrSlots = this.rrSlots.map((s, i) => i === idx ? { ...s, isSearching: true, showDropdown: true } : s);
        try {
            const users = await searchActiveUsers({ searchTerm: term });
            this.rrSlots = this.rrSlots.map((s, i) => i === idx ? { ...s, results: users, hasResults: users.length > 0, isSearching: false } : s);
        } catch (e) {
            this.rrSlots = this.rrSlots.map((s, i) => i === idx ? { ...s, results: [], hasResults: false, isSearching: false } : s);
        }
    }

    handleRRUserSelect(event) {
        const idx = parseInt(event.currentTarget.dataset.slotIndex, 10);
        const userId = event.currentTarget.dataset.recordId;
        const userName = event.currentTarget.dataset.recordName;
        this.rrSlots = this.rrSlots.map((s, i) => i === idx ? { ...s, userId, userName, searchTerm: '', showDropdown: false, results: [], hasResults: false, hasSelected: true } : s);
    }

    handleRRUserClear(event) {
        const idx = parseInt(event.currentTarget.dataset.slotIndex, 10);
        this.rrSlots = this.rrSlots.map((s, i) => i === idx ? { ...s, userId: null, userName: '', searchTerm: '', showDropdown: false, results: [], hasResults: false, hasSelected: false } : s);
    }

    // ─── Reassignment Handlers ───────────────────────────────────────
    handleTargetBucketChange(event) { this.targetBucket = event.detail.value; }
    handleSuppressChange(event) { this.suppressNotifications = event.target.checked; }
    handleRowSelection(event) { this.selectedLeadIds = event.detail.selectedRows.map(r => r.leadId); }

    async handleSearch() {
        this.isLoading = true; this.hasSearched = false; this.selectedLeadIds = []; this.showResultSummary = false; this.resetReassignment();
        try {
            this.searchResults = await searchLeads({
                ownerId: this.filterOwnerId, project: null,
                projectId: this.filterProjectId || null,
                leadStatus: this.filterLeadStatus || null, leadSource: this.filterLeadSource || null,
                leadId: this.filterLeadId || null, mobileNumber: this.filterMobile || null,
                leadBucket: this.filterBucket || null
            });
            this.hasSearched = true;
            if (this.searchResults.length === 0) this.showToast('Info', 'No leads found matching your filters.', 'info');
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    async handleReassign() {
        if (this.selectedLeadIds.length === 0) { this.showToast('Warning', 'Please select at least one lead.', 'warning'); return; }
        if (!this.targetBucket) { this.showToast('Warning', 'Please select a target bucket.', 'warning'); return; }
        if (this.isRoundRobin) {
            const rrUserIds = this.selectedRRUserIds;
            if (rrUserIds.length === 0) { this.showToast('Warning', 'Please select at least one user for round robin.', 'warning'); return; }
            await this.executeRoundRobinReassign(rrUserIds);
        } else {
            if (!this.targetUserId) { this.showToast('Warning', 'Please select a target user.', 'warning'); return; }
            await this.executeSingleReassign();
        }
    }

    async executeSingleReassign() {
        this.isLoading = true; this.showResultSummary = false;
        try {
            this.reassignResult = await reassignLeads({ leadIds: this.selectedLeadIds, targetUserId: this.targetUserId, targetBucket: this.targetBucket, suppressNotifications: this.suppressNotifications });
            this.showResultSummary = true; this.showReassignToast();
            this.selectedLeadIds = [];
            this.handleSearch();
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    async executeRoundRobinReassign(rrUserIds) {
        this.isLoading = true; this.showResultSummary = false;
        try {
            this.reassignResult = await reassignLeadsRoundRobin({ leadIds: this.selectedLeadIds, targetUserIds: rrUserIds, targetBucket: this.targetBucket, suppressNotifications: this.suppressNotifications });
            this.showResultSummary = true; this.showReassignToast();
            this.selectedLeadIds = [];
            this.handleSearch();
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    showReassignToast() {
        if (this.reassignResult.failureCount === 0) this.showToast('Success', this.reassignResult.successCount + ' lead(s) reassigned successfully.', 'success');
        else if (this.reassignResult.successCount > 0) this.showToast('Warning', this.reassignResult.successCount + ' succeeded, ' + this.reassignResult.failureCount + ' failed.', 'warning');
        else this.showToast('Error', 'All ' + this.reassignResult.failureCount + ' reassignment(s) failed.', 'error');
    }

    handleDismissResult() { this.showResultSummary = false; this.selectedLeadIds = []; this.resetReassignment(); this.handleSearch(); }

    resetReassignment() {
        this.targetUserId = null; this.targetUserName = ''; this.targetUserSearchTerm = ''; this.targetUserResults = [];
        this.targetBucket = ''; this.suppressNotifications = false; this.isRoundRobin = false; this.initRoundRobinSlots();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 2: TEMPORARY OWNERSHIP HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    handleTempFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        if (field === 'tempProject') this.tempFilterProjectId = value;
        if (field === 'leadId') this.tempFilterLeadId = value;
    }

    handleTempOwnerFilterSearch(event) {
        this.tempOwnerSearchTerm = event.detail.value;
        if (this._tempOwnerFilterTimeout) clearTimeout(this._tempOwnerFilterTimeout);
        this._tempOwnerFilterTimeout = setTimeout(() => { this.performTempOwnerFilterSearch(this.tempOwnerSearchTerm); }, 300);
    }
    handleTempOwnerFilterFocus() { if (!this.tempSelectedOwnerName) this.showTempOwnerFilterDropdown = true; }
    handleTempOwnerFilterBlur() { setTimeout(() => { this.showTempOwnerFilterDropdown = false; }, 300); }

    async performTempOwnerFilterSearch(term) {
        if (!term || term.length < 2) { this.tempOwnerFilterResults = []; return; }
        this.isTempOwnerFilterSearching = true; this.showTempOwnerFilterDropdown = true;
        try { this.tempOwnerFilterResults = await searchActiveUsers({ searchTerm: term }); }
        catch (e) { this.tempOwnerFilterResults = []; }
        finally { this.isTempOwnerFilterSearching = false; }
    }

    handleTempOwnerFilterSelect(event) {
        this.tempFilterOwnerId = event.currentTarget.dataset.recordId;
        this.tempSelectedOwnerName = event.currentTarget.dataset.recordName;
        this.tempOwnerSearchTerm = ''; this.showTempOwnerFilterDropdown = false; this.tempOwnerFilterResults = [];
    }
    handleClearTempFilterOwner() {
        this.tempFilterOwnerId = null; this.tempSelectedOwnerName = '';
        this.tempOwnerSearchTerm = ''; this.tempOwnerFilterResults = [];
    }

    handleClearTempFilters() {
        this.tempFilterOwnerId = null; this.tempSelectedOwnerName = ''; this.tempOwnerSearchTerm = ''; this.tempOwnerFilterResults = [];
        this.tempFilterProjectId = ''; this.tempFilterLeadId = '';
        this.tempHasSearched = false; this.tempSearchResults = []; this.tempSelectedLeadIds = [];
        this.resetTempAssignment();
    }

    handleTempTargetUserSearch(event) {
        this.tempTargetSearchTerm = event.detail.value;
        if (this._tempTargetSearchTimeout) clearTimeout(this._tempTargetSearchTimeout);
        this._tempTargetSearchTimeout = setTimeout(() => { this.performTempTargetSearch(this.tempTargetSearchTerm); }, 300);
    }
    handleTempTargetUserFocus() { if (!this.tempTargetUserName) this.showTempTargetDropdown = true; }
    handleTempTargetUserBlur() { setTimeout(() => { this.showTempTargetDropdown = false; }, 300); }

    async performTempTargetSearch(term) {
        if (!term || term.length < 2) { this.tempTargetResults = []; return; }
        this.isTempTargetSearching = true; this.showTempTargetDropdown = true;
        try { this.tempTargetResults = await searchActiveUsers({ searchTerm: term }); }
        catch (e) { this.tempTargetResults = []; }
        finally { this.isTempTargetSearching = false; }
    }

    handleTempTargetUserSelect(event) {
        this.tempTargetUserId = event.currentTarget.dataset.recordId;
        this.tempTargetUserName = event.currentTarget.dataset.recordName;
        this.tempTargetSearchTerm = ''; this.showTempTargetDropdown = false; this.tempTargetResults = [];
    }
    handleClearTempTargetUser() {
        this.tempTargetUserId = null; this.tempTargetUserName = '';
        this.tempTargetSearchTerm = ''; this.tempTargetResults = [];
    }

    handleTempStartDateChange(event) {
        const val = event.detail.value;
        if (val && val < this.todayDate) {
            this.showToast('Error', 'Start Date cannot be in the past.', 'error');
            this.tempStartDate = '';
            return;
        }
        this.tempStartDate = val;
    }
    handleTempEndDateChange(event) {
        const val = event.detail.value;
        if (val && val < this.todayDate) {
            this.showToast('Error', 'End Date cannot be in the past.', 'error');
            this.tempEndDate = '';
            return;
        }
        this.tempEndDate = val;
    }
    handleTempReasonChange(event) { this.tempReason = event.detail.value; }
    handleTempAccessLevelChange(event) { this.tempLeadAccessLevel = event.detail.value; }
    handleTempShareFollowupsChange(event) { this.tempShareFollowups = event.target.checked; }
    handleTempShareSiteVisitsChange(event) { this.tempShareSiteVisits = event.target.checked; }
    handleTempRowSelection(event) { this.tempSelectedLeadIds = event.detail.selectedRows.map(r => r.leadId); }

    async handleTempSearch() {
        this.isLoading = true; this.tempHasSearched = false; this.tempSelectedLeadIds = [];
        this.showTempResultSummary = false; this.resetTempAssignment();
        // Resolve project name from combobox
        let projectName = null;
        if (this.tempFilterProjectId) {
            const opt = this.projectOptions.find(p => p.value === this.tempFilterProjectId);
            if (opt) projectName = opt.label === '-- All --' ? null : opt.label;
        }
        try {
            this.tempSearchResults = await searchLeads({
                ownerId: this.tempFilterOwnerId, project: projectName,
                leadStatus: null, leadSource: null,
                leadId: this.tempFilterLeadId || null, mobileNumber: null, leadBucket: null
            });
            this.tempHasSearched = true;
            if (this.tempSearchResults.length === 0) this.showToast('Info', 'No leads found.', 'info');
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    async handleTempAssign() {
        if (this.tempSelectedLeadIds.length === 0) { this.showToast('Warning', 'Please select leads.', 'warning'); return; }
        if (!this.tempTargetUserId) { this.showToast('Warning', 'Please select a temporary owner.', 'warning'); return; }
        if (!this.tempStartDate || !this.tempEndDate) { this.showToast('Warning', 'Please provide start and end dates.', 'warning'); return; }
        const today = new Date().toISOString().split('T')[0];
        if (this.tempStartDate < today) { this.showToast('Warning', 'Start Date cannot be in the past.', 'warning'); return; }
        if (this.tempEndDate < today) { this.showToast('Warning', 'End Date cannot be in the past.', 'warning'); return; }
        if (this.tempEndDate < this.tempStartDate) { this.showToast('Warning', 'End Date must be on or after Start Date.', 'warning'); return; }

        this.isLoading = true; this.showTempResultSummary = false;
        try {
            this.tempResult = await tempAssignLeads({
                leadIds: this.tempSelectedLeadIds,
                tempOwnerId: this.tempTargetUserId,
                startDate: this.tempStartDate,
                endDate: this.tempEndDate,
                reason: this.tempReason || '',
                leadAccessLevel: this.tempLeadAccessLevel,
                shareFollowups: this.tempShareFollowups,
                shareSiteVisits: this.tempShareSiteVisits
            });
            this.showTempResultSummary = true;
            if (this.tempResult.failureCount === 0) this.showToast('Success', this.tempResult.successCount + ' lead(s) assigned temporarily.', 'success');
            else if (this.tempResult.successCount > 0) this.showToast('Warning', this.tempResult.successCount + ' succeeded, ' + this.tempResult.failureCount + ' failed.', 'warning');
            else this.showToast('Error', 'All assignments failed.', 'error');
            // Clear filters and reset after save
            this.handleClearTempFilters();
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    async handleRevokeTempAssign() {
        if (this.tempSelectedLeadIds.length === 0) { this.showToast('Warning', 'Please select leads to revoke.', 'warning'); return; }
        this.isLoading = true; this.showTempResultSummary = false;
        try {
            this.tempResult = await revokeTempAssignment({ leadIds: this.tempSelectedLeadIds });
            this.showTempResultSummary = true;
            if (this.tempResult.failureCount === 0) this.showToast('Success', this.tempResult.successCount + ' temp assignment(s) revoked.', 'success');
            else this.showToast('Warning', this.tempResult.successCount + ' revoked, ' + this.tempResult.failureCount + ' failed.', 'warning');
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    handleDismissTempResult() { this.showTempResultSummary = false; this.tempSelectedLeadIds = []; this.resetTempAssignment(); this.handleTempSearch(); }

    resetTempAssignment() {
        this.tempTargetUserId = null; this.tempTargetUserName = ''; this.tempTargetSearchTerm = ''; this.tempTargetResults = [];
        this.tempStartDate = ''; this.tempEndDate = ''; this.tempReason = '';
        this.tempLeadAccessLevel = 'Edit'; this.tempShareFollowups = false; this.tempShareSiteVisits = false;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 3: UNIT BLOCKING HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    handleUnitFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        if (field === 'project')    this.unitFilterProject = value;
        if (field === 'unitStatus') this.unitFilterStatus = value;
        if (field === 'unitNumber') this.unitFilterNumber = value;
    }

    handleClearUnitFilters() {
        this.unitFilterProject = ''; this.unitFilterStatus = ''; this.unitFilterNumber = '';
        this.unitHasSearched = false; this.unitSearchResults = []; this.selectedUnitIds = [];
        this.blockDays = null; this.blockReason = ''; this.showUnitResultSummary = false;
        this.isManagementBlock = false;
        this.blockingForUserId = null; this.blockingForUserName = ''; this.blockingForSearchTerm = ''; this.blockingForResults = [];
        this.blockLeadId = null; this.blockLeadName = ''; this.blockLeadSearchTerm = ''; this.blockLeadResults = [];
    }

    handleManagementBlockToggle(event) { this.isManagementBlock = event.target.checked; }
    handleBlockDaysChange(event) { this.blockDays = event.detail.value; }
    handleBlockReasonChange(event) { this.blockReason = event.detail.value; }
    handleUnitRowSelection(event) { this.selectedUnitIds = event.detail.selectedRows.map(r => r.unitId); }

    // Blocking For user lookup
    handleBlockingForSearch(event) {
        this.blockingForSearchTerm = event.detail.value;
        if (this._blockingForSearchTimeout) clearTimeout(this._blockingForSearchTimeout);
        this._blockingForSearchTimeout = setTimeout(() => { this.performBlockingForSearch(this.blockingForSearchTerm); }, 300);
    }
    handleBlockingForFocus() { if (!this.blockingForUserName) this.showBlockingForDropdown = true; }
    handleBlockingForBlur() { setTimeout(() => { this.showBlockingForDropdown = false; }, 300); }

    async performBlockingForSearch(term) {
        if (!term || term.length < 2) { this.blockingForResults = []; return; }
        this.isBlockingForSearching = true; this.showBlockingForDropdown = true;
        try { this.blockingForResults = await searchActiveUsers({ searchTerm: term }); }
        catch (e) { this.blockingForResults = []; }
        finally { this.isBlockingForSearching = false; }
    }

    handleBlockingForSelect(event) {
        this.blockingForUserId = event.currentTarget.dataset.recordId;
        this.blockingForUserName = event.currentTarget.dataset.recordName;
        this.blockingForSearchTerm = ''; this.showBlockingForDropdown = false; this.blockingForResults = [];
    }
    handleClearBlockingFor() {
        this.blockingForUserId = null; this.blockingForUserName = '';
        this.blockingForSearchTerm = ''; this.blockingForResults = [];
    }

    // Lead lookup for blocking
    handleBlockLeadSearch(event) {
        this.blockLeadSearchTerm = event.detail.value;
        if (this._blockLeadSearchTimeout) clearTimeout(this._blockLeadSearchTimeout);
        this._blockLeadSearchTimeout = setTimeout(() => { this.performBlockLeadSearch(this.blockLeadSearchTerm); }, 300);
    }
    handleBlockLeadFocus() { if (!this.blockLeadName) this.showBlockLeadDropdown = true; }
    handleBlockLeadBlur() { setTimeout(() => { this.showBlockLeadDropdown = false; }, 300); }

    async performBlockLeadSearch(term) {
        if (!term || term.length < 2) { this.blockLeadResults = []; return; }
        this.isBlockLeadSearching = true; this.showBlockLeadDropdown = true;
        try { this.blockLeadResults = await searchLeadsForLookup({ searchTerm: term }); }
        catch (e) { this.blockLeadResults = []; }
        finally { this.isBlockLeadSearching = false; }
    }

    handleBlockLeadSelect(event) {
        this.blockLeadId = event.currentTarget.dataset.recordId;
        this.blockLeadName = event.currentTarget.dataset.recordName;
        this.blockLeadSearchTerm = ''; this.showBlockLeadDropdown = false; this.blockLeadResults = [];
    }
    handleClearBlockLead() {
        this.blockLeadId = null; this.blockLeadName = '';
        this.blockLeadSearchTerm = ''; this.blockLeadResults = [];
    }

    async handleUnitSearch() {
        this.isLoading = true; this.unitHasSearched = false; this.selectedUnitIds = [];
        this.showUnitResultSummary = false; this.blockDays = null; this.blockReason = '';
        try {
            this.unitSearchResults = await searchUnits({
                projectId: this.unitFilterProject || null,
                unitStatus: this.unitFilterStatus || null,
                unitNumber: this.unitFilterNumber || null
            });
            this.unitHasSearched = true;
            if (this.unitSearchResults.length === 0) this.showToast('Info', 'No units found.', 'info');
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    async handleBlockUnits() {
        if (this.selectedUnitIds.length === 0) { this.showToast('Warning', 'Please select units.', 'warning'); return; }
        if (!this.blockReason) { this.showToast('Warning', 'Block reason is mandatory.', 'warning'); return; }
        if (!this.isManagementBlock && (!this.blockDays || this.blockDays < 1)) {
            this.showToast('Warning', 'Please enter a valid block duration.', 'warning'); return;
        }

        this.isLoading = true; this.showUnitResultSummary = false;
        try {
            this.unitResult = await blockUnits({
                unitIds: this.selectedUnitIds,
                blockDays: this.blockDays ? parseInt(this.blockDays, 10) : null,
                reason: this.blockReason,
                isManagement: this.isManagementBlock,
                blockingForUserId: this.blockingForUserId,
                leadId: this.blockLeadId
            });
            this.showUnitResultSummary = true;
            if (this.unitResult.failureCount === 0) this.showToast('Success', this.unitResult.successCount + ' unit(s) blocked.', 'success');
            else if (this.unitResult.successCount > 0) this.showToast('Warning', this.unitResult.successCount + ' blocked, ' + this.unitResult.failureCount + ' failed.', 'warning');
            else this.showToast('Error', 'All blocking operations failed.', 'error');
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    async handleUnblockUnits() {
        if (this.selectedUnitIds.length === 0) { this.showToast('Warning', 'Please select units to unblock.', 'warning'); return; }
        this.isLoading = true; this.showUnitResultSummary = false;
        try {
            this.unitResult = await unblockUnits({ unitIds: this.selectedUnitIds });
            this.showUnitResultSummary = true;
            if (this.unitResult.failureCount === 0) this.showToast('Success', this.unitResult.successCount + ' unit(s) unblocked.', 'success');
            else this.showToast('Warning', this.unitResult.successCount + ' unblocked, ' + this.unitResult.failureCount + ' failed.', 'warning');
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    handleDismissUnitResult() {
        this.showUnitResultSummary = false; this.selectedUnitIds = [];
        this.blockDays = null; this.blockReason = '';
        this.isManagementBlock = false; this.blockingForUserId = null; this.blockingForUserName = '';
        this.blockLeadId = null; this.blockLeadName = '';
        this.handleUnitSearch();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 4: TEMPORARY SHARED RECORDS HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    handleTab4UserSearch(event) {
        this.tab4SearchTerm = event.detail.value;
        if (this._tab4SearchTimeout) clearTimeout(this._tab4SearchTimeout);
        this._tab4SearchTimeout = setTimeout(() => { this.performTab4UserSearch(this.tab4SearchTerm); }, 300);
    }
    handleTab4UserFocus() { if (!this.tab4UserName) this.showTab4Dropdown = true; }
    handleTab4UserBlur() { setTimeout(() => { this.showTab4Dropdown = false; }, 300); }

    async performTab4UserSearch(term) {
        if (!term || term.length < 2) { this.tab4LookupResults = []; return; }
        this.isTab4Searching = true; this.showTab4Dropdown = true;
        try { this.tab4LookupResults = await searchActiveUsers({ searchTerm: term }); }
        catch (e) { this.tab4LookupResults = []; }
        finally { this.isTab4Searching = false; }
    }

    handleTab4UserSelect(event) {
        this.tab4UserId = event.currentTarget.dataset.recordId;
        this.tab4UserName = event.currentTarget.dataset.recordName;
        this.tab4SearchTerm = ''; this.showTab4Dropdown = false; this.tab4LookupResults = [];
    }
    handleClearTab4User() {
        this.tab4UserId = null; this.tab4UserName = '';
        this.tab4SearchTerm = ''; this.tab4LookupResults = [];
        this.tab4HasSearched = false; this.tab4Results = [];
    }

    handleTab4RowSelection(event) {
        this.tab4SelectedLeadIds = event.detail.selectedRows.map(r => r.leadId).filter(id => id != null);
    }

    async handleTab4Search() {
        if (!this.tab4UserId) { this.showToast('Warning', 'Please select a user.', 'warning'); return; }
        this.isLoading = true; this.tab4HasSearched = false; this.tab4SelectedLeadIds = [];
        try {
            this.tab4Results = await searchTempSharedRecords({ tempOwnerId: this.tab4UserId });
            this.tab4HasSearched = true;
            if (this.tab4Results.length === 0) this.showToast('Info', 'No temporary shared records found.', 'info');
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    async handleRevokeTab4Sharing() {
        if (this.tab4SelectedLeadIds.length === 0) { this.showToast('Warning', 'Please select records to revoke.', 'warning'); return; }
        this.isLoading = true;
        try {
            const result = await revokeTempAssignment({ leadIds: this.tab4SelectedLeadIds });
            if (result.failureCount === 0) this.showToast('Success', result.successCount + ' temp sharing(s) revoked.', 'success');
            else if (result.successCount > 0) this.showToast('Warning', result.successCount + ' revoked, ' + result.failureCount + ' failed.', 'warning');
            else this.showToast('Error', 'All revocations failed.', 'error');
            this.tab4SelectedLeadIds = [];
            this.handleTab4Search();
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 5: BLOCKED UNITS VIEWER HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    // Blocked By user lookup
    handleTab5BlockedBySearch(event) {
        this.tab5BlockedBySearchTerm = event.detail.value;
        if (this._tab5BlockedByTimeout) clearTimeout(this._tab5BlockedByTimeout);
        this._tab5BlockedByTimeout = setTimeout(() => { this.performTab5BlockedBySearch(this.tab5BlockedBySearchTerm); }, 300);
    }
    handleTab5BlockedByFocus() { if (!this.tab5BlockedByName) this.showTab5BlockedByDropdown = true; }
    handleTab5BlockedByBlur() { setTimeout(() => { this.showTab5BlockedByDropdown = false; }, 300); }

    async performTab5BlockedBySearch(term) {
        if (!term || term.length < 2) { this.tab5BlockedByResults = []; return; }
        this.isTab5BlockedBySearching = true; this.showTab5BlockedByDropdown = true;
        try { this.tab5BlockedByResults = await searchActiveUsers({ searchTerm: term }); }
        catch (e) { this.tab5BlockedByResults = []; }
        finally { this.isTab5BlockedBySearching = false; }
    }

    handleTab5BlockedBySelect(event) {
        this.tab5BlockedById = event.currentTarget.dataset.recordId;
        this.tab5BlockedByName = event.currentTarget.dataset.recordName;
        this.tab5BlockedBySearchTerm = ''; this.showTab5BlockedByDropdown = false; this.tab5BlockedByResults = [];
    }
    handleClearTab5BlockedBy() {
        this.tab5BlockedById = null; this.tab5BlockedByName = '';
        this.tab5BlockedBySearchTerm = ''; this.tab5BlockedByResults = [];
    }

    // Blocking For user lookup
    handleTab5BlockingForSearch(event) {
        this.tab5BlockingForSearchTerm = event.detail.value;
        if (this._tab5BlockingForTimeout) clearTimeout(this._tab5BlockingForTimeout);
        this._tab5BlockingForTimeout = setTimeout(() => { this.performTab5BlockingForSearch(this.tab5BlockingForSearchTerm); }, 300);
    }
    handleTab5BlockingForFocus() { if (!this.tab5BlockingForName) this.showTab5BlockingForDropdown = true; }
    handleTab5BlockingForBlur() { setTimeout(() => { this.showTab5BlockingForDropdown = false; }, 300); }

    async performTab5BlockingForSearch(term) {
        if (!term || term.length < 2) { this.tab5BlockingForResults = []; return; }
        this.isTab5BlockingForSearching = true; this.showTab5BlockingForDropdown = true;
        try { this.tab5BlockingForResults = await searchActiveUsers({ searchTerm: term }); }
        catch (e) { this.tab5BlockingForResults = []; }
        finally { this.isTab5BlockingForSearching = false; }
    }

    handleTab5BlockingForSelect(event) {
        this.tab5BlockingForId = event.currentTarget.dataset.recordId;
        this.tab5BlockingForName = event.currentTarget.dataset.recordName;
        this.tab5BlockingForSearchTerm = ''; this.showTab5BlockingForDropdown = false; this.tab5BlockingForResults = [];
    }
    handleClearTab5BlockingFor() {
        this.tab5BlockingForId = null; this.tab5BlockingForName = '';
        this.tab5BlockingForSearchTerm = ''; this.tab5BlockingForResults = [];
    }

    handleTab5ManagementToggle(event) { this.tab5ManagementOnly = event.target.checked; }
    handleTab5RowSelection(event) { this.tab5SelectedUnitIds = event.detail.selectedRows.map(r => r.unitId); }

    async handleTab5Search() {
        this.isLoading = true; this.tab5HasSearched = false; this.tab5SelectedUnitIds = [];
        try {
            this.tab5Results = await searchBlockedUnits({
                blockedByUserId: this.tab5BlockedById,
                isManagement: this.tab5ManagementOnly ? true : null,
                blockingForUserId: this.tab5BlockingForId
            });
            this.tab5HasSearched = true;
            if (this.tab5Results.length === 0) this.showToast('Info', 'No blocked units found.', 'info');
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    async handleTab5Unblock() {
        if (this.tab5SelectedUnitIds.length === 0) { this.showToast('Warning', 'Please select units to unblock.', 'warning'); return; }
        this.isLoading = true;
        try {
            const result = await unblockUnits({ unitIds: this.tab5SelectedUnitIds });
            if (result.failureCount === 0) this.showToast('Success', result.successCount + ' unit(s) unblocked.', 'success');
            else if (result.successCount > 0) this.showToast('Warning', result.successCount + ' unblocked, ' + result.failureCount + ' failed.', 'warning');
            else this.showToast('Error', 'All unblocking operations failed.', 'error');
            this.tab5SelectedUnitIds = [];
            this.handleTab5Search();
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB 6: BLOCK REQUESTS HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    handleReqProjectChange(event) { this.reqProject = event.detail.value; }

    // Unit lookup for request
    handleReqUnitSearch(event) {
        this.reqUnitSearchTerm = event.detail.value;
        if (this._reqUnitSearchTimeout) clearTimeout(this._reqUnitSearchTimeout);
        this._reqUnitSearchTimeout = setTimeout(() => { this.performReqUnitSearch(this.reqUnitSearchTerm); }, 300);
    }
    handleReqUnitFocus() { if (!this.reqUnitName) this.showReqUnitDropdown = true; }
    handleReqUnitBlur() { setTimeout(() => { this.showReqUnitDropdown = false; }, 300); }

    async performReqUnitSearch(term) {
        if (!term || term.length < 2) { this.reqUnitResults = []; return; }
        this.isReqUnitSearching = true; this.showReqUnitDropdown = true;
        try {
            this.reqUnitResults = await searchUnits({
                projectId: this.reqProject || null,
                unitStatus: 'Available',
                unitNumber: term
            });
        } catch (e) { this.reqUnitResults = []; }
        finally { this.isReqUnitSearching = false; }
    }

    handleReqUnitSelect(event) {
        this.reqUnitId = event.currentTarget.dataset.recordId;
        this.reqUnitName = event.currentTarget.dataset.recordName;
        this.reqUnitSearchTerm = ''; this.showReqUnitDropdown = false; this.reqUnitResults = [];
    }
    handleClearReqUnit() {
        this.reqUnitId = null; this.reqUnitName = '';
        this.reqUnitSearchTerm = ''; this.reqUnitResults = [];
    }

    // Lead lookup for request
    handleReqLeadSearch(event) {
        this.reqLeadSearchTerm = event.detail.value;
        if (this._reqLeadSearchTimeout) clearTimeout(this._reqLeadSearchTimeout);
        this._reqLeadSearchTimeout = setTimeout(() => { this.performReqLeadSearch(this.reqLeadSearchTerm); }, 300);
    }
    handleReqLeadFocus() { if (!this.reqLeadName) this.showReqLeadDropdown = true; }
    handleReqLeadBlur() { setTimeout(() => { this.showReqLeadDropdown = false; }, 300); }

    async performReqLeadSearch(term) {
        if (!term || term.length < 2) { this.reqLeadResults = []; return; }
        this.isReqLeadSearching = true; this.showReqLeadDropdown = true;
        try { this.reqLeadResults = await searchLeadsForLookup({ searchTerm: term }); }
        catch (e) { this.reqLeadResults = []; }
        finally { this.isReqLeadSearching = false; }
    }

    handleReqLeadSelect(event) {
        this.reqLeadId = event.currentTarget.dataset.recordId;
        this.reqLeadName = event.currentTarget.dataset.recordName;
        this.reqLeadSearchTerm = ''; this.showReqLeadDropdown = false; this.reqLeadResults = [];
    }
    handleClearReqLead() {
        this.reqLeadId = null; this.reqLeadName = '';
        this.reqLeadSearchTerm = ''; this.reqLeadResults = [];
    }

    handleReqBlockDaysChange(event) { this.reqBlockDays = event.detail.value; }
    handleReqReasonChange(event) { this.reqReason = event.detail.value; }

    // Approver lookup for request
    handleReqApproverSearch(event) {
        this.reqApproverSearchTerm = event.detail.value;
        if (this._reqApproverSearchTimeout) clearTimeout(this._reqApproverSearchTimeout);
        this._reqApproverSearchTimeout = setTimeout(() => { this.performReqApproverSearch(this.reqApproverSearchTerm); }, 300);
    }
    handleReqApproverFocus() { if (!this.reqApproverName) this.showReqApproverDropdown = true; }
    handleReqApproverBlur() { setTimeout(() => { this.showReqApproverDropdown = false; }, 300); }

    async performReqApproverSearch(term) {
        if (!term || term.length < 2) { this.reqApproverResults = []; return; }
        this.isReqApproverSearching = true; this.showReqApproverDropdown = true;
        try { this.reqApproverResults = await searchActiveUsers({ searchTerm: term }); }
        catch (e) { this.reqApproverResults = []; }
        finally { this.isReqApproverSearching = false; }
    }

    handleReqApproverSelect(event) {
        this.reqApproverId = event.currentTarget.dataset.recordId;
        this.reqApproverName = event.currentTarget.dataset.recordName;
        this.reqApproverSearchTerm = ''; this.showReqApproverDropdown = false; this.reqApproverResults = [];
    }
    handleClearReqApprover() {
        this.reqApproverId = null; this.reqApproverName = '';
        this.reqApproverSearchTerm = ''; this.reqApproverResults = [];
    }

    async handleSubmitBlockRequest() {
        if (!this.reqUnitId) { this.showToast('Warning', 'Please select a unit.', 'warning'); return; }
        if (!this.reqReason) { this.showToast('Warning', 'Please provide a reason.', 'warning'); return; }
        if (!this.reqApproverId) { this.showToast('Warning', 'Please select an approver.', 'warning'); return; }

        this.isLoading = true;
        try {
            await createBlockRequest({
                unitId: this.reqUnitId,
                projectId: this.reqProject || null,
                leadId: this.reqLeadId,
                approverId: this.reqApproverId,
                blockDays: this.reqBlockDays ? parseInt(this.reqBlockDays, 10) : null,
                reason: this.reqReason,
                isManagement: false
            });
            this.showToast('Success', 'Block request submitted for approval.', 'success');
            // Reset form
            this.reqUnitId = null; this.reqUnitName = ''; this.reqUnitSearchTerm = '';
            this.reqLeadId = null; this.reqLeadName = ''; this.reqLeadSearchTerm = '';
            this.reqBlockDays = null; this.reqReason = '';
            this.refreshBlockRequests();
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    handleRequestRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'approve') {
            this.handleApproveRequest(row.requestId);
        } else if (action.name === 'reject') {
            this.rejectingRequestId = row.requestId;
            this.rejectNotes = '';
            this.showRejectModal = true;
        }
    }

    async handleApproveRequest(requestId) {
        this.isLoading = true;
        try {
            await approveBlockRequest({ requestId: requestId });
            this.showToast('Success', 'Request approved and unit blocked.', 'success');
            this.refreshBlockRequests();
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    handleRejectNotesChange(event) { this.rejectNotes = event.detail.value; }

    async handleConfirmReject() {
        this.isLoading = true; this.showRejectModal = false;
        try {
            await rejectBlockRequest({ requestId: this.rejectingRequestId, notes: this.rejectNotes });
            this.showToast('Success', 'Request rejected.', 'success');
            this.rejectingRequestId = null; this.rejectNotes = '';
            this.refreshBlockRequests();
        } catch (error) { this.showToast('Error', this.reduceErrors(error), 'error'); }
        finally { this.isLoading = false; }
    }

    handleCancelReject() {
        this.showRejectModal = false;
        this.rejectingRequestId = null;
        this.rejectNotes = '';
    }

    // ═══════════════════════════════════════════════════════════════════
    //  UTILITIES
    // ═══════════════════════════════════════════════════════════════════

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