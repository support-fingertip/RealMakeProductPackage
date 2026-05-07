import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProfileConfig from '@salesforce/apex/UserAvailabilityController.getProfileConfig';
import getUsers from '@salesforce/apex/UserAvailabilityController.getUsers';
import getUserCount from '@salesforce/apex/UserAvailabilityController.getUserCount';
import updateWorkingStatus from '@salesforce/apex/UserAvailabilityController.updateWorkingStatus';
import updateAvailability from '@salesforce/apex/UserAvailabilityController.updateAvailability';
import getUserTimeSummaries from '@salesforce/apex/UserAvailabilityController.getUserTimeSummaries';
import getShiftConfigurations from '@salesforce/apex/UserAvailabilityController.getShiftConfigurations';
import updateUserShift from '@salesforce/apex/UserAvailabilityController.updateUserShift';
import Id from '@salesforce/user/Id';

export default class UserAvailabilityManager extends LightningElement {

    // ─── Profile Config State ─────────────────────────────────────────
    @track currentProfile = '';
    @track allVisibleProfiles = [];
    @track profileOptions = [];
    @track selectedProfile = '';

    // ─── User Data State ──────────────────────────────────────────────
    @track users = [];
    @track isLoading = false;
    @track hasLoaded = false;
    currentUserId = Id;

    // ─── Pagination State ─────────────────────────────────────────────
    pageSize = 10;
    @track currentPage = 1;
    @track totalRecords = 0;

    // ─── Time Tracking State ──────────────────────────────────────────
    @track showTimeTracking = false;
    @track selectedDate = '';
    @track timeSummaryMap = {};
    @track isLoadingTime = false;

    // ─── Shift State ──────────────────────────────────────────────────
    @track shiftOptions = [];
    @track shiftFilterOptions = [];
    @track selectedShiftFilter = '';
    @track showShiftEditModal = false;
    @track editShiftUserId = null;
    @track editShiftUserName = '';
    @track editShiftValue = '';

    // ─── Debounce ─────────────────────────────────────────────────────
    _filterDebounceTimer;

    // ═══════════════════════════════════════════════════════════════════
    //  LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════

    connectedCallback() {
        this.selectedDate = this._getTodayString();
        this.loadProfileConfig();
    }

    async loadProfileConfig() {
        this.isLoading = true;
        try {
            const [config, shifts] = await Promise.all([
                getProfileConfig(),
                getShiftConfigurations()
            ]);

            this.currentProfile = config.currentProfile;
            this.allVisibleProfiles = config.visibleProfiles || [];

            this.profileOptions = [
                { label: '-- All Profiles --', value: '' },
                ...this.allVisibleProfiles.map(p => ({ label: p, value: p }))
            ];

            // Build shift options for combobox and filter
            this.shiftOptions = (shifts || []).map(s => ({
                label: s.shiftName + ' (' + s.startTime + ' - ' + s.endTime + ')',
                value: s.shiftName
            }));

            this.shiftFilterOptions = [
                { label: '-- All Shifts --', value: '' },
                ...this.shiftOptions
            ];

            await this.loadUsers();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
            this.hasLoaded = true;
        }
    }

    async loadUsers() {
        this.isLoading = true;
        try {
            const profileFilter = this.activeProfileFilter;

            const [count, userData] = await Promise.all([
                getUserCount({ profileNames: profileFilter }),
                getUsers({
                    profileNames: profileFilter,
                    pageSize: this.pageSize,
                    offset: this.offset
                })
            ]);

            this.totalRecords = count;

            // Apply client-side shift filter if selected
            if (this.selectedShiftFilter) {
                this.users = userData.filter(u => u.shift === this.selectedShiftFilter);
            } else {
                this.users = userData;
            }

            if (this.showTimeTracking) {
                await this.loadTimeSummaries();
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  COMPUTED GETTERS
    // ═══════════════════════════════════════════════════════════════════

    get activeProfileFilter() {
        if (this.selectedProfile) {
            return [this.selectedProfile];
        }
        return this.allVisibleProfiles;
    }

    get offset() {
        return (this.currentPage - 1) * this.pageSize;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalRecords / this.pageSize));
    }

    get pageInfo() {
        return `Page ${this.currentPage} of ${this.totalPages} (${this.totalRecords} users)`;
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get hasUsers() {
        return this.users && this.users.length > 0;
    }

    get hasNoUsers() {
        return this.hasLoaded && (!this.users || this.users.length === 0);
    }

    get hasNoConfig() {
        return this.hasLoaded && this.allVisibleProfiles.length === 0;
    }

    get hasConfig() {
        return this.hasLoaded && this.allVisibleProfiles.length > 0;
    }

    get timeTrackingButtonVariant() {
        return this.showTimeTracking ? 'brand' : 'border-filled';
    }

    get maxDateValue() {
        return this._getTodayString();
    }

    get hasShiftFilter() {
        return this.shiftFilterOptions.length > 2;
    }

    get processedUsers() {
        return this.users.map(u => ({
            ...u,
            rowClass: u.isCurrentUser
                ? 'slds-line-height_reset current-user-row'
                : 'slds-line-height_reset',
            availabilityDisabled: !u.isWorking,
            shiftDisplay: u.shift || 'Day Shift',
            availableTime: this.timeSummaryMap[u.id]?.availableDisplay || '--:--:--',
            offlineTime: this.timeSummaryMap[u.id]?.offlineDisplay || '--:--:--',
            sessionTime: this.timeSummaryMap[u.id]?.sessionDisplay || '--:--:--'
        }));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  FILTER HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    handleProfileChange(event) {
        this.selectedProfile = event.detail.value;
        this.currentPage = 1;

        if (this._filterDebounceTimer) {
            clearTimeout(this._filterDebounceTimer);
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._filterDebounceTimer = setTimeout(() => {
            this.loadUsers();
        }, 300);
    }

    handleShiftFilterChange(event) {
        this.selectedShiftFilter = event.detail.value;
        this.currentPage = 1;

        if (this._filterDebounceTimer) {
            clearTimeout(this._filterDebounceTimer);
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._filterDebounceTimer = setTimeout(() => {
            this.loadUsers();
        }, 300);
    }

    handleRefresh() {
        this.currentPage = 1;
        this.loadUsers();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PAGINATION HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    handleFirst() {
        this.currentPage = 1;
        this.loadUsers();
    }

    handlePrevious() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.loadUsers();
        }
    }

    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.loadUsers();
        }
    }

    handleLast() {
        this.currentPage = this.totalPages;
        this.loadUsers();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TIME TRACKING HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    handleToggleTimeTracking() {
        this.showTimeTracking = !this.showTimeTracking;
        if (this.showTimeTracking && this.users.length > 0) {
            this.loadTimeSummaries();
        }
    }

    handleDateChange(event) {
        this.selectedDate = event.detail.value;
        if (this.showTimeTracking && this.users.length > 0) {
            this.loadTimeSummaries();
        }
    }

    async loadTimeSummaries() {
        if (!this.users || this.users.length === 0) return;

        this.isLoadingTime = true;
        try {
            const userIds = this.users.map(u => u.id);
            const results = await getUserTimeSummaries({
                userIds: userIds,
                targetDate: this.selectedDate || this._getTodayString()
            });

            const map = {};
            for (const item of results) {
                map[item.userId] = {
                    availableDisplay: this._formatTime(item.totalAvailableSeconds),
                    offlineDisplay: this._formatTime(item.totalOfflineSeconds),
                    sessionDisplay: this._formatTime(item.totalSessionSeconds)
                };
            }
            this.timeSummaryMap = map;
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoadingTime = false;
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TOGGLE HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    async handleWorkingToggle(event) {
        const userId = event.target.dataset.userId;
        const isWorking = event.target.checked;

        this.users = this.users.map(u => {
            if (u.id === userId) {
                const updated = { ...u, isWorking };
                if (!isWorking) {
                    updated.isAvailable = false;
                }
                return updated;
            }
            return u;
        });

        try {
            await updateWorkingStatus({ userId, isWorking });
            this.showToast(
                'Success',
                isWorking ? 'User marked as Working.' : 'User marked as On Leave.',
                'success'
            );
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.loadUsers();
        }
    }

    async handleAvailabilityToggle(event) {
        const userId = event.target.dataset.userId;
        const isAvailable = event.target.checked;

        this.users = this.users.map(u => {
            if (u.id === userId) {
                return { ...u, isAvailable };
            }
            return u;
        });

        try {
            await updateAvailability({ userId, isAvailable });
            this.showToast(
                'Success',
                isAvailable ? 'User marked as Available.' : 'User marked as Offline.',
                'success'
            );
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.loadUsers();
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SHIFT EDIT HANDLERS
    // ═══════════════════════════════════════════════════════════════════

    handleEditShift(event) {
        const userId = event.currentTarget.dataset.userId;
        const user = this.users.find(u => u.id === userId);
        if (user) {
            this.editShiftUserId = userId;
            this.editShiftUserName = user.name;
            this.editShiftValue = user.shift || 'Day Shift';
            this.showShiftEditModal = true;
        }
    }

    handleEditShiftChange(event) {
        this.editShiftValue = event.detail.value;
    }

    async handleConfirmShiftEdit() {
        this.showShiftEditModal = false;
        if (!this.editShiftUserId || !this.editShiftValue) return;

        this.isLoading = true;
        try {
            await updateUserShift({
                userId: this.editShiftUserId,
                shiftName: this.editShiftValue
            });

            // Update local state
            this.users = this.users.map(u => {
                if (u.id === this.editShiftUserId) {
                    return { ...u, shift: this.editShiftValue };
                }
                return u;
            });

            this.showToast('Success', 'Shift updated for ' + this.editShiftUserName, 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.loadUsers();
        } finally {
            this.isLoading = false;
            this.editShiftUserId = null;
            this.editShiftUserName = '';
            this.editShiftValue = '';
        }
    }

    handleCancelShiftEdit() {
        this.showShiftEditModal = false;
        this.editShiftUserId = null;
        this.editShiftUserName = '';
        this.editShiftValue = '';
    }

    // ═══════════════════════════════════════════════════════════════════
    //  UTILITIES
    // ═══════════════════════════════════════════════════════════════════

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _formatTime(totalSeconds) {
        if (!totalSeconds || totalSeconds < 0) totalSeconds = 0;
        const hours = Math.floor(totalSeconds / 3600);
        const minutes = Math.floor((totalSeconds % 3600) / 60);
        const seconds = Math.floor(totalSeconds % 60);
        return String(hours).padStart(2, '0') + ':' +
            String(minutes).padStart(2, '0') + ':' +
            String(seconds).padStart(2, '0');
    }

    _getTodayString() {
        const d = new Date();
        return d.getFullYear() + '-' +
            String(d.getMonth() + 1).padStart(2, '0') + '-' +
            String(d.getDate()).padStart(2, '0');
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