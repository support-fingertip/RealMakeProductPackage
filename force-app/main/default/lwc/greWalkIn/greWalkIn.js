import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import searchLeadsByMobile from '@salesforce/apex/GREWalkInController.searchLeadsByMobile';
import processNewLead from '@salesforce/apex/GREWalkInController.processNewLead';
import processExistingLead from '@salesforce/apex/GREWalkInController.processExistingLead';
import searchProjects from '@salesforce/apex/GREWalkInController.searchProjects';
import checkLeadDuplicate from '@salesforce/apex/GREWalkInController.checkLeadDuplicate';
import getSalesExecutives from '@salesforce/apex/GREWalkInController.getSalesExecutives';
import getSiteVisitsForLead from '@salesforce/apex/GREWalkInController.getSiteVisitsForLead';
import completeSiteVisit from '@salesforce/apex/GREWalkInController.completeSiteVisit';
import createAndCompleteSiteVisit from '@salesforce/apex/GREWalkInController.createAndCompleteSiteVisit';
import checkoutSiteVisit from '@salesforce/apex/GREWalkInController.checkoutSiteVisit';
import isCrossProjectSiteVisitAllowed from '@salesforce/apex/GREWalkInController.isCrossProjectSiteVisitAllowed';

export default class GreWalkIn extends NavigationMixin(LightningElement) {

    // ─── State ──────────────────────────────────────────────────────
    @track currentStep = 'CHECK';  // CHECK | LEAD_LIST | NEW_LEAD | EXISTING_LEAD | RESULT
    @track isLoading = false;

    // Step 1: Check inputs
    @track phone = '';
    @track selectedProjectId = '';
    @track selectedSource = 'Walk-in';

    // Project lookup state (shared between New Lead and New SV)
    @track projectSearchTerm = '';
    @track projectLookupResults = [];
    @track showProjectDropdown = false;
    @track selectedProjectName = '';
    @track isProjectSearching = false;
    _projectSearchTimeout;

    // Duplicate check state
    @track duplicateInfo = null;

    // Search results (lead list)
    @track searchResults = [];

    // Check result (selected lead info)
    @track checkResult = {};

    // Cross-project site visit policy driven by active General Setup
    @track crossProjectAllowed = false;

    // Step 2A: New Lead form
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track bhkType = '';
    @track propertyType = '';
    @track budgetRange = '';
    @track remarks = '';
    @track selectedExecutiveId = '';
    @track useRoundRobin = false;

    // Step 2B: Existing Lead – Site Visit cards
    @track siteVisitCards = [];
    @track selectedSiteVisit = null;  // SV card being checked in
    @track svOwnerId = '';
    @track showCompleteModal = false;

    // Walk-in processing form (for existing leads without scheduled SV)
    @track showWalkInForm = false;

    // GRE Check-in fields
    @track greSourceType = 'Digital (Own)';
    @track greChannelPartnerId = '';
    @track greRemarks = '';

    // GRE Check-out fields
    @track showCheckoutModal = false;
    @track checkoutSvId = '';
    @track checkoutRemarks = '';

    // New SV for different project
    @track showNewSvForm = false;
    @track newSvProjectId = '';
    @track newSvProjectName = '';
    @track newSvOwnerId = '';
    @track newSvCheckoutTime = '';
    @track newSvProjectSearchTerm = '';
    @track newSvProjectLookupResults = [];
    @track showNewSvProjectDropdown = false;
    @track isNewSvProjectSearching = false;
    _newSvProjectSearchTimeout;

    // Step 3: Process result
    @track processResult = {};

    // Lookup data
    @track executiveOptions = [];

    // ─── Lifecycle ─────────────────────────────────────────────────
    connectedCallback() {
        isCrossProjectSiteVisitAllowed()
            .then(allowed => { this.crossProjectAllowed = allowed === true; })
            .catch(() => { this.crossProjectAllowed = false; });
    }

    // ─── Block non-digit keys on mobile input ─────────────────────
    _phoneKeydownBound = false;

    renderedCallback() {
        if (!this._phoneKeydownBound) {
            const phoneInput = this.template.querySelector('.phone-number-input');
            if (phoneInput) {
                const nativeInput = phoneInput.shadowRoot
                    ? phoneInput.shadowRoot.querySelector('input')
                    : null;
                if (nativeInput) {
                    nativeInput.setAttribute('inputmode', 'numeric');
                    nativeInput.addEventListener('keydown', (e) => {
                        // Allow: backspace, delete, tab, escape, enter, arrows
                        const allowed = ['Backspace', 'Delete', 'Tab', 'Escape', 'Enter',
                            'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'];
                        if (allowed.includes(e.key)) return;
                        // Allow Ctrl/Cmd + A, C, V, X
                        if ((e.ctrlKey || e.metaKey) && ['a', 'c', 'v', 'x'].includes(e.key)) return;
                        // Block anything that is not a digit
                        if (!/^\d$/.test(e.key)) {
                            e.preventDefault();
                        }
                    });
                    this._phoneKeydownBound = true;
                }
            }
        }
    }

    // ─── Load Executives (imperative, project-scoped) ─────────────
    async loadExecutives(projectId) {
        try {
            const data = await getSalesExecutives({ projectId });
            this.executiveOptions = data.map(u => ({
                label: u.Name + (u.Email ? ' (' + u.Email + ')' : ''),
                value: u.Id
            }));
        } catch (error) {
            this.executiveOptions = [];
            this.showToast('Error', 'Failed to load executives.', 'error');
        }
    }

    // ─── Getters: Step Visibility ───────────────────────────────────
    get showCheckForm()    { return this.currentStep === 'CHECK'; }
    get showLeadList()     { return this.currentStep === 'LEAD_LIST'; }
    get showNewLeadForm()  { return this.currentStep === 'NEW_LEAD'; }
    get showExistingLead() { return this.currentStep === 'EXISTING_LEAD'; }
    get showResult()       { return this.currentStep === 'RESULT'; }

    get isCheckDisabled() {
        return !this.phone || this.phone.length !== 10;
    }

    get hasSelectedProject() {
        return !!this.selectedProjectName;
    }

    get hasProjectResults() {
        return this.projectLookupResults && this.projectLookupResults.length > 0;
    }

    get hasDuplicate() {
        return this.duplicateInfo != null;
    }

    get duplicateIsActive() {
        return this.duplicateInfo && this.duplicateInfo.isActive;
    }

    get duplicateMessage() {
        if (!this.duplicateInfo) return '';
        if (this.duplicateInfo.isActive) {
            return 'Active lead already exists: ' + this.duplicateInfo.leadName
                + ' (Owner: ' + this.duplicateInfo.ownerName + ', Status: ' + this.duplicateInfo.status + '). '
                + 'You cannot create a duplicate active lead for the same project.';
        }
        return 'Inactive lead found: ' + this.duplicateInfo.leadName
            + ' (Owner: ' + this.duplicateInfo.ownerName + ', Status: ' + this.duplicateInfo.status + '). '
            + 'A new lead will be created for this project.';
    }

    get isNewLeadDisabled() {
        return !this.firstName || !this.selectedProjectId
            || (!this.selectedExecutiveId && !this.useRoundRobin)
            || (this.duplicateInfo && this.duplicateInfo.isActive);
    }

    get isExecutiveDisabled() {
        return this.useRoundRobin;
    }

    get scenarioIsNewLead()    { return this.processResult.scenario === 'NEW_LEAD'; }
    get scenarioIsActive()     { return this.processResult.scenario === 'ACTIVE_LEAD'; }
    get scenarioIsInactive()   { return this.processResult.scenario === 'INACTIVE_LEAD'; }

    get resultVariant() {
        return this.processResult.success ? 'success' : 'error';
    }

    get resultIconName() {
        return this.processResult.success ? 'utility:success' : 'utility:error';
    }

    get hasSearchResults() {
        return this.searchResults && this.searchResults.length > 0;
    }

    // ─── Site Visit Card Getters ─────────────────────────────────────
    get hasSiteVisitCards() {
        return this.siteVisitCards && this.siteVisitCards.length > 0;
    }

    get isCompleteDisabled() {
        return !this.svOwnerId;
    }

    get greSourceTypeOptions() {
        return [
            { label: 'Digital (Own)', value: 'Digital (Own)' },
            { label: 'Channel Partner', value: 'Channel Partner' }
        ];
    }

    get showChannelPartnerPicker() {
        return this.greSourceType === 'Channel Partner';
    }

    get hasNewSvSelectedProject() {
        return !!this.newSvProjectName;
    }

    get hasNewSvProjectResults() {
        return this.newSvProjectLookupResults && this.newSvProjectLookupResults.length > 0;
    }

    get isCreateSvDisabled() {
        return !this.newSvProjectId || !this.newSvOwnerId;
    }

    get isPreSalesLead() {
        return this.checkResult && this.checkResult.recordTypeDev === 'Pre_Sales';
    }

    // ─── Datatable Columns ────────────────────────────────────────
    get leadColumns() {
        return [
            { label: 'Lead Name', fieldName: 'leadName', type: 'text' },
            { label: 'Mobile', fieldName: 'mobile', type: 'phone' },
            { label: 'Project', fieldName: 'projectName', type: 'text' },
            { label: 'Source', fieldName: 'source', type: 'text' },
            { label: 'Status', fieldName: 'status', type: 'text' },
            { label: 'Owner', fieldName: 'ownerName', type: 'text' },
            {
                type: 'button',
                typeAttributes: {
                    label: 'Select',
                    name: 'select',
                    variant: 'brand',
                    iconName: 'utility:chevronright',
                    iconPosition: 'right'
                }
            }
        ];
    }

    // ─── Picklist Options ───────────────────────────────────────────
    get sourceOptions() {
        return [
            { label: 'Walk-in', value: 'Walk-in' },
            { label: 'Digital', value: 'Digital' },
            { label: 'Channel Partner', value: 'Channel Partner' },
            { label: 'Referral', value: 'Referral' },
            { label: 'Event', value: 'Event' }
        ];
    }

    get bhkOptions() {
        return [
            { label: '--None--', value: '' },
            { label: '1 BHK', value: '1BHK' },
            { label: '2 BHK', value: '2BHK' },
            { label: '3 BHK', value: '3BHK' },
            { label: '4 BHK', value: '4BHK' },
            { label: '5 BHK', value: '5BHK' },
            { label: 'Studio', value: 'Studio' }
        ];
    }

    get propertyTypeOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Apartment', value: 'Apartment' },
            { label: 'Villa', value: 'Villa' },
            { label: 'Plot', value: 'Plot' },
            { label: 'Commercial', value: 'Commercial' },
            { label: 'Penthouse', value: 'Penthouse' }
        ];
    }

    get budgetOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Below 25L', value: 'Below 25L' },
            { label: '25L - 50L', value: '25L-50L' },
            { label: '50L - 75L', value: '50L-75L' },
            { label: '75L - 1Cr', value: '75L-1Cr' },
            { label: '1Cr - 1.5Cr', value: '1Cr-1.5Cr' },
            { label: '1.5Cr - 2Cr', value: '1.5Cr-2Cr' },
            { label: 'Above 2Cr', value: 'Above 2Cr' }
        ];
    }

    // ─── Event Handlers: Step 1 (Search by Mobile) ─────────────────
    handlePhoneChange(event) {
        const cleaned = event.detail.value.replace(/\D/g, '').substring(0, 10);
        this.phone = cleaned;
        // Force input value update when LWC skips re-render (same value after strip)
        const inputEl = this.template.querySelector('lightning-input[label="Mobile Number"]');
        if (inputEl) {
            inputEl.value = cleaned;
        }
    }
    handleClearPhone()         { this.phone = ''; }
    handleSourceChange(event)  { this.selectedSource = event.detail.value; }

    // ─── Project Lookup Handlers (New Lead form) ────────────────────
    handleProjectKeyup(event) {
        const searchTerm = event.target.value;
        this.projectSearchTerm = searchTerm;

        if (this._projectSearchTimeout) {
            clearTimeout(this._projectSearchTimeout);
        }

        this._projectSearchTimeout = setTimeout(() => {
            this.performProjectSearch(searchTerm);
        }, 250);
    }

    async performProjectSearch(searchTerm) {
        this.isProjectSearching = true;
        this.showProjectDropdown = true;
        try {
            const results = await searchProjects({ searchText: searchTerm || '' });
            this.projectLookupResults = results.map(p => ({
                id: p.Id,
                name: p.Name,
                code: p.Project_Code__c || ''
            }));
        } catch (e) {
            console.error('Project search error', e);
            this.projectLookupResults = [];
        } finally {
            this.isProjectSearching = false;
        }
    }

    handleProjectFocus() {
        if (!this.selectedProjectName) {
            this.showProjectDropdown = true;
            if (this.projectLookupResults.length === 0) {
                this.performProjectSearch('');
            }
        }
    }

    handleProjectBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showProjectDropdown = false;
        }, 300);
    }

    handleProjectSelect(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const recordName = event.currentTarget.dataset.recordName;
        this.selectedProjectId = recordId;
        this.selectedProjectName = recordName;
        this.projectSearchTerm = '';
        this.projectLookupResults = [];
        this.showProjectDropdown = false;
        this.duplicateInfo = null;
        this.loadExecutives(recordId);
        this.runDuplicateCheck();
    }

    handleClearProject() {
        this.selectedProjectId = '';
        this.selectedProjectName = '';
        this.projectSearchTerm = '';
        this.projectLookupResults = [];
        this.showProjectDropdown = false;
        this.duplicateInfo = null;
    }

    async runDuplicateCheck() {
        if (!this.phone || !this.selectedProjectId) {
            this.duplicateInfo = null;
            return;
        }
        try {
            const result = await checkLeadDuplicate({
                phone: this.phone,
                projectId: this.selectedProjectId
            });
            if (result.isDuplicate) {
                this.duplicateInfo = {
                    leadId: result.leadId,
                    leadName: result.leadName,
                    isActive: result.isActive,
                    ownerName: result.ownerName,
                    status: result.status
                };
            } else {
                this.duplicateInfo = null;
            }
        } catch (e) {
            console.error('Duplicate check error', e);
        }
    }

    async handleSearchLead() {
        this.isLoading = true;
        try {
            const results = await searchLeadsByMobile({ phone: this.phone });
            this.searchResults = results;

            if (results.length === 0) {
                this.currentStep = 'NEW_LEAD';
            } else {
                this.currentStep = 'LEAD_LIST';
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Event Handlers: Lead List Selection ──────────────────────
    async handleLeadRowAction(event) {
        const row = event.detail.row;
        this.checkResult = {
            leadId: row.leadId,
            leadName: row.leadName,
            ownerName: row.ownerName,
            leadStatus: row.leadStatus,
            projectName: row.projectName,
            projectId: row.projectId,
            recordTypeDev: row.recordTypeDev,
            scenario: row.isActive ? 'ACTIVE_LEAD' : 'INACTIVE_LEAD',
            message: row.isActive
                ? 'Active lead found: ' + row.leadName + ' (Owner: ' + row.ownerName + ')'
                : 'Inactive lead found: ' + row.leadName + '. Will create new enquiry source and site visit.'
        };

        // Load site visits for this lead
        await this.loadSiteVisits(row.leadId);
        this.currentStep = 'EXISTING_LEAD';
    }

    async loadSiteVisits(leadId) {
        this.isLoading = true;
        try {
            const cards = await getSiteVisitsForLead({ leadId });
            this.siteVisitCards = cards.map(sv => {
                let statusClass = 'sv-card';
                let badgeClass = 'sv-badge';
                if (sv.canComplete) {
                    statusClass += ' sv-card-scheduled';
                    badgeClass += ' sv-badge-scheduled';
                } else if (sv.isCompleted) {
                    statusClass += ' sv-card-completed';
                    badgeClass += ' sv-badge-completed';
                } else {
                    statusClass += ' sv-card-other';
                    badgeClass += ' sv-badge-other';
                }
                return {
                    ...sv,
                    formattedDate: sv.scheduledDate ? new Date(sv.scheduledDate).toLocaleString() : '',
                    formattedCompletedDate: sv.completedDate ? new Date(sv.completedDate).toLocaleString() : '',
                    statusClass,
                    badgeClass
                };
            });
        } catch (error) {
            console.error('Error loading site visits', error);
            this.siteVisitCards = [];
        } finally {
            this.isLoading = false;
        }
    }

    handleCreateNewFromList() {
        this.currentStep = 'NEW_LEAD';
    }

    // ─── Event Handlers: Step 2A (New Lead Form) ────────────────────
    handleFirstNameChange(event)  { this.firstName = event.detail.value; }
    handleLastNameChange(event)   { this.lastName = event.detail.value; }
    handleEmailChange(event)      { this.email = event.detail.value; }
    handleBhkChange(event)        { this.bhkType = event.detail.value; }
    handlePropertyChange(event)   { this.propertyType = event.detail.value; }
    handleBudgetChange(event)     { this.budgetRange = event.detail.value; }
    handleRemarksChange(event)    { this.remarks = event.detail.value; }
    handleExecutiveChange(event)  { this.selectedExecutiveId = event.detail.value; }

    handleRoundRobinChange(event) {
        this.useRoundRobin = event.target.checked;
        if (this.useRoundRobin) {
            this.selectedExecutiveId = '';
        }
    }

    async handleCreateLead() {
        this.isLoading = true;
        try {
            const result = await processNewLead({
                firstName: this.firstName,
                lastName: this.lastName,
                phone: this.phone,
                email: this.email,
                projectId: this.selectedProjectId,
                source: this.selectedSource,
                bhkType: this.bhkType,
                propertyType: this.propertyType,
                budgetRange: this.budgetRange,
                remarks: this.remarks,
                salesExecId: this.selectedExecutiveId || null,
                useRoundRobin: this.useRoundRobin,
                greSourceType: this.greSourceType || null,
                channelPartnerId: this.greChannelPartnerId || null,
                greRemarks: this.greRemarks || null
            });
            this.processResult = result;
            this.currentStep = 'RESULT';
            this.showToast('Success', result.message, 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Event Handlers: Step 2B (Existing Lead – Site Visit Cards) ──

    // Click on a scheduled SV card to complete it
    handleSvCardClick(event) {
        const svId = event.currentTarget.dataset.svId;
        const card = this.siteVisitCards.find(c => c.siteVisitId === svId);
        if (!card || !card.canComplete) return;

        this.selectedSiteVisit = card;
        this.svOwnerId = card.assignedToId || '';
        this.svCheckoutTime = '';
        this.showCompleteModal = true;
        this.showNewSvForm = false;
        if (card.projectId) {
            this.loadExecutives(card.projectId);
        }
    }

    handleSvOwnerChange(event) {
        this.svOwnerId = event.detail.value;
    }

    handleGreSourceTypeChange(event) {
        this.greSourceType = event.detail.value;
        if (this.greSourceType !== 'Channel Partner') {
            this.greChannelPartnerId = '';
        }
    }

    handleGreChannelPartnerChange(event) {
        this.greChannelPartnerId = event.detail.recordId || '';
    }

    handleGreRemarksChange(event) {
        this.greRemarks = event.detail.value;
    }

    handleCancelComplete() {
        this.showCompleteModal = false;
        this.selectedSiteVisit = null;
        this.svOwnerId = '';
        this.greSourceType = 'Digital (Own)';
        this.greChannelPartnerId = '';
        this.greRemarks = '';
    }

    async handleConfirmComplete() {
        this.isLoading = true;
        try {
            const result = await completeSiteVisit({
                siteVisitId: this.selectedSiteVisit.siteVisitId,
                ownerId: this.svOwnerId || null,
                greSourceType: this.greSourceType || null,
                channelPartnerId: this.greChannelPartnerId || null,
                greRemarks: this.greRemarks || null
            });
            this.processResult = result;
            this.showCompleteModal = false;
            this.selectedSiteVisit = null;
            this.greSourceType = 'Digital (Own)';
            this.greChannelPartnerId = '';
            this.greRemarks = '';
            this.currentStep = 'RESULT';
            this.showToast('Success', result.message, 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Process Walk-In – show form first to collect details
    handleProcessExisting() {
        this.showWalkInForm = true;
        this.showCompleteModal = false;
        this.showNewSvForm = false;
        this.greSourceType = 'Digital (Own)';
        this.greChannelPartnerId = '';
        this.greRemarks = '';
    }

    handleCancelWalkIn() {
        this.showWalkInForm = false;
        this.greSourceType = 'Digital (Own)';
        this.greChannelPartnerId = '';
        this.greRemarks = '';
    }

    async handleConfirmWalkIn() {
        this.isLoading = true;
        try {
            const result = await processExistingLead({
                leadId: this.checkResult.leadId,
                greSourceType: this.greSourceType || null,
                channelPartnerId: this.greChannelPartnerId || null,
                greRemarks: this.greRemarks || null
            });
            this.processResult = result;
            this.showWalkInForm = false;
            this.currentStep = 'RESULT';
            this.showToast('Success', result.message, 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ─── New Site Visit for Different Project ────────────────────────
    handleShowNewSvForm() {
        this.showNewSvForm = true;
        this.showCompleteModal = false;
        this.newSvProjectId = '';
        this.newSvProjectName = '';
        this.newSvOwnerId = '';
        this.newSvProjectSearchTerm = '';
        this.newSvProjectLookupResults = [];
        this.showNewSvProjectDropdown = false;
    }

    handleCancelNewSv() {
        this.showNewSvForm = false;
        this.newSvProjectId = '';
        this.newSvProjectName = '';
        this.newSvOwnerId = '';
    }

    // New SV project lookup handlers
    handleNewSvProjectKeyup(event) {
        const searchTerm = event.target.value;
        this.newSvProjectSearchTerm = searchTerm;

        if (this._newSvProjectSearchTimeout) {
            clearTimeout(this._newSvProjectSearchTimeout);
        }

        this._newSvProjectSearchTimeout = setTimeout(() => {
            this.performNewSvProjectSearch(searchTerm);
        }, 250);
    }

    async performNewSvProjectSearch(searchTerm) {
        this.isNewSvProjectSearching = true;
        this.showNewSvProjectDropdown = true;
        try {
            const results = await searchProjects({ searchText: searchTerm || '' });
            this.newSvProjectLookupResults = results.map(p => ({
                id: p.Id,
                name: p.Name,
                code: p.Project_Code__c || ''
            }));
        } catch (e) {
            console.error('New SV project search error', e);
            this.newSvProjectLookupResults = [];
        } finally {
            this.isNewSvProjectSearching = false;
        }
    }

    handleNewSvProjectFocus() {
        if (!this.newSvProjectName) {
            this.showNewSvProjectDropdown = true;
            if (this.newSvProjectLookupResults.length === 0) {
                this.performNewSvProjectSearch('');
            }
        }
    }

    handleNewSvProjectBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showNewSvProjectDropdown = false;
        }, 300);
    }

    handleNewSvProjectSelect(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const recordName = event.currentTarget.dataset.recordName;
        this.newSvProjectId = recordId;
        this.newSvProjectName = recordName;
        this.newSvProjectSearchTerm = '';
        this.newSvProjectLookupResults = [];
        this.showNewSvProjectDropdown = false;
        this.loadExecutives(recordId);
    }

    handleClearNewSvProject() {
        this.newSvProjectId = '';
        this.newSvProjectName = '';
        this.newSvProjectSearchTerm = '';
        this.newSvProjectLookupResults = [];
        this.showNewSvProjectDropdown = false;
    }

    handleNewSvOwnerChange(event) {
        this.newSvOwnerId = event.detail.value;
    }

    handleNewSvCheckoutChange(event) {
        this.newSvCheckoutTime = event.detail.value;
    }

    async handleCreateNewSv() {
        this.isLoading = true;
        try {
            const result = await createAndCompleteSiteVisit({
                leadId: this.checkResult.leadId,
                projectId: this.newSvProjectId,
                ownerId: this.newSvOwnerId || null,
                greSourceType: this.greSourceType || null,
                channelPartnerId: this.greChannelPartnerId || null,
                greRemarks: this.greRemarks || null
            });
            this.processResult = result;
            this.showNewSvForm = false;
            this.currentStep = 'RESULT';
            this.showToast('Success', result.message, 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Check-Out Handlers ────────────────────────────────────────
    handleSvCheckoutClick(event) {
        const svId = event.currentTarget.dataset.svId;
        this.checkoutSvId = svId;
        this.checkoutRemarks = '';
        this.showCheckoutModal = true;
    }

    handleCheckoutRemarksChange(event) {
        this.checkoutRemarks = event.detail.value;
    }

    handleCancelCheckout() {
        this.showCheckoutModal = false;
        this.checkoutSvId = '';
        this.checkoutRemarks = '';
    }

    async handleConfirmCheckout() {
        this.isLoading = true;
        try {
            await checkoutSiteVisit({
                siteVisitId: this.checkoutSvId,
                feedback: this.checkoutRemarks || null
            });
            this.showCheckoutModal = false;
            this.checkoutSvId = '';
            this.checkoutRemarks = '';
            this.showToast('Success', 'Customer checked out successfully.', 'success');
            // Reload SV cards to reflect updated state
            await this.loadSiteVisits(this.checkResult.leadId);
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Navigation & Reset ─────────────────────────────────────────
    handleBackToCheck() {
        this.currentStep = 'CHECK';
    }

    handleBackToList() {
        this.showCompleteModal = false;
        this.showNewSvForm = false;
        this.selectedSiteVisit = null;
        this.currentStep = 'LEAD_LIST';
    }

    handleReset() {
        this.currentStep = 'CHECK';
        this.phone = '';
        this.selectedProjectId = '';
        this.selectedProjectName = '';
        this.projectSearchTerm = '';
        this.projectLookupResults = [];
        this.showProjectDropdown = false;
        this.isProjectSearching = false;
        this.duplicateInfo = null;
        this.selectedSource = 'Walk-in';
        this.searchResults = [];
        this.checkResult = {};
        this.processResult = {};
        this.firstName = '';
        this.lastName = '';
        this.email = '';
        this.bhkType = '';
        this.propertyType = '';
        this.budgetRange = '';
        this.remarks = '';
        this.selectedExecutiveId = '';
        this.useRoundRobin = false;
        // Reset SV state
        this.siteVisitCards = [];
        this.selectedSiteVisit = null;
        this.showCompleteModal = false;
        this.showNewSvForm = false;
        this.showWalkInForm = false;
        this.svOwnerId = '';
        this.newSvProjectId = '';
        this.newSvProjectName = '';
        this.newSvOwnerId = '';
        // Reset GRE check-in/check-out state
        this.greSourceType = 'Digital (Own)';
        this.greChannelPartnerId = '';
        this.greRemarks = '';
        this.showCheckoutModal = false;
        this.checkoutSvId = '';
        this.checkoutRemarks = '';
    }

    handleViewLead() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.processResult.leadId,
                objectApiName: 'Lead__c',
                actionName: 'view'
            }
        });
    }

    // ─── Utilities ──────────────────────────────────────────────────
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