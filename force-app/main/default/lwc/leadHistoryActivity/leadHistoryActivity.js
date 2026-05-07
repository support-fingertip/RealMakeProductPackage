import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import getData from '@salesforce/apex/LeadHistoryActivityLWCController.getData';
import getRecordingBase64 from '@salesforce/apex/LeadHistoryActivityLWCController.getRecordingBase64';
import getOwnershipTimeline from '@salesforce/apex/LeadHistoryActivityLWCController.getOwnershipTimeline';

const PAGE_SIZE = 50;

export default class LeadHistoryActivity extends LightningElement {
    @api recordId;

    @track allRecords = [];
    @track ownershipRecords = [];
    @track isLoading = false;
    @track loadingRecordingId = null;
    @track loadedRecordingIds = {}; // tracks which recordings have been loaded (play button hidden)

    selectedFilter = 'All';
    currentPage = 1;
    pageSize = PAGE_SIZE;
    _refreshHandlerId;

    connectedCallback() {
        this._refreshHandlerId = registerRefreshHandler(this, this.handlePlatformRefresh);
    }

    disconnectedCallback() {
        if (this._refreshHandlerId) {
            unregisterRefreshHandler(this._refreshHandlerId);
        }
    }

    handlePlatformRefresh() {
        return this.loadData();
    }

    @wire(getRecord, { recordId: '$recordId', fields: ['Lead__c.Id', 'Lead__c.LastModifiedDate'] })
    wiredRecord({ data }) {
        if (data) {
            this.loadData();
        }
    }

    async loadData() {
        this.isLoading = true;
        try {
            if (this.selectedFilter === 'Ownership History') {
                const result = await getOwnershipTimeline({
                    leadId: this.recordId
                });
                this.ownershipRecords = (result || []).map((rec, idx) => ({
                    ...rec,
                    key: 'ot-' + idx
                }));
                this.allRecords = [];
            } else {
                const result = await getData({
                    leadId: this.recordId,
                    filter: this.selectedFilter
                });
                this.allRecords = result || [];
                this.ownershipRecords = [];
            }
            this.currentPage = 1;
        } catch (error) {
            this.allRecords = [];
            this.ownershipRecords = [];
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Filter options
    get filterOptions() {
        return [
            { label: 'All', value: 'All' },
            { label: 'Field Updates', value: 'Field Updates' },
            { label: 'Calls', value: 'Calls' },
            { label: 'Activities (Notes)', value: 'Activities' },
            { label: 'Ownership History', value: 'Ownership History' }
        ];
    }

    handleFilterChange(event) {
        this.selectedFilter = event.detail.value;
        this.loadData();
    }

    // Ownership History view
    get isOwnershipView() {
        return this.selectedFilter === 'Ownership History';
    }

    get hasOwnershipRecords() {
        return this.ownershipRecords.length > 0;
    }

    // Pagination getters
    get totalRecords() {
        return this.allRecords.length;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalRecords / this.pageSize));
    }

    get paginatedRecords() {
        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        return this.allRecords.slice(start, end);
    }

    get displayRecords() {
        return this.paginatedRecords.map((record, index) => {
            const isHistory = record.recordType === 'History';
            const isActivity = record.recordType === 'Activity';
            const isCall = record.recordType === 'Call';
            const isCreated = isHistory && record.fieldLabel === 'created';
            const isFieldUpdate = isHistory && !isCreated && (record.oldValue != null || record.newValue != null);
            const hasOldValue = record.oldValue != null && record.oldValue !== '';

            return {
                ...record,
                key: record.recordId || ('rec-' + ((this.currentPage - 1) * this.pageSize + index)),
                isHistory,
                isActivity,
                isCall,
                isCreated,
                isFieldUpdate,
                hasOldValue,
                isLoadingRecording: this.loadingRecordingId === record.recordId,
                showPlayButton: this.loadingRecordingId !== record.recordId
                    && !this.loadedRecordingIds[record.recordId]
            };
        });
    }

    get pageInfo() {
        if (this.totalRecords === 0) {
            return 'No records';
        }
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalRecords);
        return `${start}-${end} of ${this.totalRecords}`;
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get hasRecords() {
        return this.allRecords.length > 0;
    }

    // Pagination handlers
    handleFirst() {
        this.currentPage = 1;
    }

    handlePrevious() {
        if (this.currentPage > 1) {
            this.currentPage--;
        }
    }

    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
        }
    }

    handleLast() {
        this.currentPage = this.totalPages;
    }

    // Recording playback — try direct URL first, fallback to Apex base64 proxy
    async handlePlayRecording(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const recordingUrl = event.currentTarget.dataset.url;

        if (!recordingUrl) {
            this.showToast('Error', 'No recording URL available', 'error');
            return;
        }

        const audioEl = this.template.querySelector(`audio[data-record-id="${recordId}"]`);
        if (!audioEl) {
            return;
        }

        // Mark as loaded — hide the play button
        this.loadedRecordingIds = { ...this.loadedRecordingIds, [recordId]: true };

        // Primary: set src directly — stays in user-gesture context so autoplay works
        audioEl.src = recordingUrl;
        audioEl.load();
        try {
            await audioEl.play();
            return; // Direct URL worked
        } catch (_directError) {
            // Direct URL failed (auth-protected, CORS, etc.) — try Apex fallback
        }

        // Fallback: fetch via Apex server-side proxy (handles auth-protected URLs)
        this.loadingRecordingId = recordId;
        try {
            const result = await getRecordingBase64({ recordingUrl });
            if (result && result.base64Data) {
                audioEl.src = 'data:' + result.contentType + ';base64,' + result.base64Data;
                audioEl.load();
                try {
                    await audioEl.play();
                } catch (_playErr) {
                    // Audio loaded but autoplay blocked — user can use native controls
                    this.showToast('Info', 'Recording loaded. Press play on the audio controls.', 'info');
                }
            } else {
                this.showToast('Error', result ? result.error : 'Unable to load recording', 'error');
            }
        } catch (apexError) {
            this.showToast('Error', this.reduceErrors(apexError), 'error');
        } finally {
            this.loadingRecordingId = null;
        }
    }

    // Audio ended — play button stays hidden until refresh
    handleAudioEnded() {
        // No action needed — button will reappear on refresh
    }

    // Refresh
    handleRefresh() {
        this.loadedRecordingIds = {};
        this.loadData();
    }

    // Utilities
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