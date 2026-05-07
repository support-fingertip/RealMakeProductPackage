import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTodayStatusSummary from '@salesforce/apex/UserAvailabilityController.getTodayStatusSummary';
import setMyAvailability from '@salesforce/apex/UserAvailabilityController.setMyAvailability';
import logoutSession from '@salesforce/apex/UserAvailabilityController.logoutSession';
import getShiftConfigurations from '@salesforce/apex/UserAvailabilityController.getShiftConfigurations';
import updateMyShift from '@salesforce/apex/UserAvailabilityController.updateMyShift';

const REASON_OPTIONS = [
    { label: 'Leave', value: 'Leave' },
    { label: 'Meeting', value: 'Meeting' },
    { label: 'Training', value: 'Training' },
    { label: 'Other', value: 'Other' }
];

export default class MyAvailabilityToggle extends LightningElement {

    @track isAvailable = false;
    @track isLoading = true;
    @track showReasonModal = false;
    @track selectedReason = '';
    @track userName = '';
    @track currentStatusDisplay = '00:00:00';
    @track totalAvailableDisplay = '00:00:00';
    @track totalOfflineDisplay = '00:00:00';
    @track totalSessionDisplay = '00:00:00';
    @track sessionStartDisplay = '';

    // Shift state
    @track currentShift = 'Day Shift';
    @track shiftStartTime = '09:00';
    @track shiftEndTime = '18:00';
    @track shiftOptions = [];
    @track showShiftModal = false;
    @track pendingShift = '';

    reasonOptions = REASON_OPTIONS;
    _timerIntervalId = null;
    _baseAvailableSeconds = 0;
    _baseOfflineSeconds = 0;
    _baseSessionSeconds = 0;
    _queryTimestamp = null;
    _currentStatusStartTime = null;
    _currentStatusIsAvailable = false;
    _boundBeforeUnload = null;
    _logoutSent = false;

    // ═══════════════════════════════════════════════════════════════
    //  LIFECYCLE
    //
    //  Multi-tab aware logout:
    //  - localStorage('__avail_tab_count') tracks how many tabs have this
    //    component mounted. Shared across all tabs of the same origin.
    //  - connectedCallback increments the counter.
    //  - beforeunload decrements the counter. Logout beacon fires ONLY
    //    when the counter reaches 0 (last tab closing).
    //  - sessionStorage('__avail_active') detects refresh vs close
    //    (per-tab, survives refresh, destroyed on tab close).
    //  - visibilitychange is NOT used — it fires on every tab switch,
    //    which is NOT a logout event.
    // ═══════════════════════════════════════════════════════════════

    static TAB_COUNT_KEY = '__avail_tab_count';

    connectedCallback() {
        // Only increment the cross-tab counter ONCE per tab.
        // sessionStorage is per-tab, so this prevents double-counting when
        // the component remounts during SPA navigation within the same tab.
        if (!sessionStorage.getItem('__avail_tab_counted')) {
            const count = parseInt(localStorage.getItem(MyAvailabilityToggle.TAB_COUNT_KEY) || '0', 10);
            localStorage.setItem(MyAvailabilityToggle.TAB_COUNT_KEY, String(count + 1));
            sessionStorage.setItem('__avail_tab_counted', 'true');
        }

        // sessionStorage survives page refresh but is destroyed on tab close.
        // Use this to detect refresh vs actual close.
        const wasRefresh = sessionStorage.getItem('__avail_active') === 'true';
        sessionStorage.setItem('__avail_active', 'true');
        this._wasRefresh = wasRefresh;

        this.initializeAvailability();

        // Only add the beforeunload listener once per tab.
        // IMPORTANT: Never remove this in disconnectedCallback — in Salesforce SPA,
        // navigating pages can unmount the component, but the tab is still open.
        // The listener must persist for the full tab lifecycle.
        if (!this._boundBeforeUnload) {
            this._boundBeforeUnload = this._handleBeforeUnload.bind(this);
            window.addEventListener('beforeunload', this._boundBeforeUnload);
        }
    }

    disconnectedCallback() {
        this.stopTimer();
        // Do NOT remove beforeunload listener here.
        // In Salesforce Lightning SPA, disconnectedCallback fires on page navigation,
        // not just tab close. The listener must stay active so that when the user
        // actually closes the tab, the logout beacon fires.
    }

    _handleBeforeUnload() {
        // Decrement the cross-tab counter
        const count = parseInt(localStorage.getItem(MyAvailabilityToggle.TAB_COUNT_KEY) || '1', 10);
        const newCount = Math.max(0, count - 1);
        localStorage.setItem(MyAvailabilityToggle.TAB_COUNT_KEY, String(newCount));

        // Only logout if this is the LAST tab being closed.
        // If other tabs are still open (newCount > 0), do nothing.
        if (newCount === 0) {
            this._sendLogoutBeacon();
        }
    }

    /**
     * Send a synchronous logout beacon via navigator.sendBeacon or fetch keepalive.
     * These APIs are designed to complete even after the page begins unloading,
     * unlike Promise-based imperative Apex calls.
     */
    _sendLogoutBeacon() {
        if (this._logoutSent) return;
        this._logoutSent = true;

        const endpoint = '/services/apexrest/availability/logout';

        try {
            if (navigator.sendBeacon) {
                const blob = new Blob([JSON.stringify({})], { type: 'application/json' });
                navigator.sendBeacon(endpoint, blob);
            } else {
                fetch(endpoint, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: '{}',
                    keepalive: true
                });
            }
        } catch (e) {
            // Last resort: try the imperative Apex call
            logoutSession().catch(() => {});
        }

        // Reset flag after short delay so refresh scenario can re-establish
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this._logoutSent = false; }, 500);
    }

    async initializeAvailability() {
        this.isLoading = true;
        try {
            // If this was a page refresh, the beforeunload handler already
            // called logoutSession which set us offline. Re-establish availability
            // so the user doesn't land on "Break" after every refresh.
            if (this._wasRefresh) {
                this._logoutSent = false;
                await setMyAvailability({ isAvailable: true, reason: null });
            }

            const [summary, shifts] = await Promise.all([
                getTodayStatusSummary(),
                getShiftConfigurations()
            ]);

            this.userName = summary.userName || '';
            this.isAvailable = summary.currentIsAvailable;
            this._currentStatusIsAvailable = summary.currentIsAvailable;
            this.currentShift = summary.shift || 'Day Shift';
            this.shiftStartTime = summary.shiftStartTime || '09:00';
            this.shiftEndTime = summary.shiftEndTime || '18:00';

            // Build shift options for the combobox
            this.shiftOptions = (shifts || []).map(s => ({
                label: s.shiftName + ' (' + s.startTime + ' - ' + s.endTime + ')',
                value: s.shiftName
            }));

            this._baseAvailableSeconds = summary.totalAvailableSeconds || 0;
            this._baseOfflineSeconds = summary.totalOfflineSeconds || 0;
            this._baseSessionSeconds = summary.totalSessionSeconds || 0;
            this._queryTimestamp = Date.now();

            if (summary.sessionStartTime) {
                const sessionDate = new Date(summary.sessionStartTime);
                this.sessionStartDisplay = sessionDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            }

            this._currentStatusStartTime = summary.currentStatusStartTime
                ? new Date(summary.currentStatusStartTime).getTime()
                : Date.now();

            this.startTimer();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  COMPUTED GETTERS
    // ═══════════════════════════════════════════════════════════════

    get statusText() {
        return this.isAvailable ? 'Available' : 'Offline';
    }

    get statusClass() {
        return this.isAvailable
            ? 'status-badge status-available'
            : 'status-badge status-offline';
    }

    get statusIcon() {
        return this.isAvailable ? 'utility:success' : 'utility:clock';
    }

    get statusIconVariant() {
        return this.isAvailable ? 'success' : 'warning';
    }

    get timerClass() {
        return this.isAvailable ? 'elapsed-timer timer-available' : 'elapsed-timer timer-offline';
    }

    get availableSummaryClass() {
        return 'summary-timer summary-available';
    }

    get offlineSummaryClass() {
        return 'summary-timer summary-offline';
    }

    get sessionSummaryClass() {
        return 'summary-timer summary-session';
    }

    get hasSessionStart() {
        return this.sessionStartDisplay !== '';
    }

    get shiftDisplay() {
        return this.currentShift + ' (' + this.shiftStartTime + ' - ' + this.shiftEndTime + ')';
    }

    get hasShiftOptions() {
        return this.shiftOptions.length > 1;
    }

    // ═══════════════════════════════════════════════════════════════
    //  TIMER
    // ═══════════════════════════════════════════════════════════════

    startTimer() {
        this.stopTimer();
        this._updateElapsed();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timerIntervalId = setInterval(() => {
            this._updateElapsed();
        }, 1000);
    }

    stopTimer() {
        if (this._timerIntervalId) {
            clearInterval(this._timerIntervalId);
            this._timerIntervalId = null;
        }
    }

    _updateElapsed() {
        const now = Date.now();
        const elapsedSinceQuery = Math.max(0, Math.floor((now - this._queryTimestamp) / 1000));

        let availableSeconds = this._baseAvailableSeconds;
        let offlineSeconds = this._baseOfflineSeconds;

        if (this._currentStatusIsAvailable) {
            availableSeconds += elapsedSinceQuery;
        } else {
            offlineSeconds += elapsedSinceQuery;
        }

        this.totalAvailableDisplay = this._formatTime(availableSeconds);
        this.totalOfflineDisplay = this._formatTime(offlineSeconds);
        this.totalSessionDisplay = this._formatTime(this._baseSessionSeconds + elapsedSinceQuery);

        const currentStatusSeconds = Math.max(0,
            Math.floor((now - this._currentStatusStartTime) / 1000));
        this.currentStatusDisplay = this._formatTime(currentStatusSeconds);
    }

    _formatTime(totalSeconds) {
        if (totalSeconds < 0) totalSeconds = 0;
        const hours = Math.floor(totalSeconds / 3600);
        const minutes = Math.floor((totalSeconds % 3600) / 60);
        const seconds = totalSeconds % 60;
        return String(hours).padStart(2, '0') + ':' +
            String(minutes).padStart(2, '0') + ':' +
            String(seconds).padStart(2, '0');
    }

    // ═══════════════════════════════════════════════════════════════
    //  TOGGLE HANDLER
    // ═══════════════════════════════════════════════════════════════

    handleToggle(event) {
        const newValue = event.target.checked;

        if (!newValue) {
            event.target.checked = true;
            this.selectedReason = '';
            this.showReasonModal = true;
        } else {
            this.setAvailable(true, null);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  REASON MODAL HANDLERS
    // ═══════════════════════════════════════════════════════════════

    handleReasonChange(event) {
        this.selectedReason = event.detail.value;
    }

    async handleConfirmOffline() {
        this.showReasonModal = false;
        await this.setAvailable(false, this.selectedReason || null);
    }

    handleCancelOffline() {
        this.showReasonModal = false;
        this.selectedReason = '';
    }

    // ═══════════════════════════════════════════════════════════════
    //  SHIFT HANDLERS
    // ═══════════════════════════════════════════════════════════════

    handleShiftClick() {
        if (this.hasShiftOptions) {
            this.pendingShift = this.currentShift;
            this.showShiftModal = true;
        }
    }

    handleShiftChange(event) {
        this.pendingShift = event.detail.value;
    }

    async handleConfirmShift() {
        this.showShiftModal = false;
        if (this.pendingShift && this.pendingShift !== this.currentShift) {
            this.isLoading = true;
            try {
                await updateMyShift({ shiftName: this.pendingShift });
                this.currentShift = this.pendingShift;

                // Update shift timing from options
                const matchedShift = this.shiftOptions.find(s => s.value === this.pendingShift);
                if (matchedShift) {
                    const timeMatch = matchedShift.label.match(/\((\d{2}:\d{2}) - (\d{2}:\d{2})\)/);
                    if (timeMatch) {
                        this.shiftStartTime = timeMatch[1];
                        this.shiftEndTime = timeMatch[2];
                    }
                }

                this.showToast('Success', 'Shift updated to ' + this.currentShift, 'success');
            } catch (error) {
                this.showToast('Error', this.reduceErrors(error), 'error');
            } finally {
                this.isLoading = false;
            }
        }
    }

    handleCancelShift() {
        this.showShiftModal = false;
        this.pendingShift = '';
    }

    // ═══════════════════════════════════════════════════════════════
    //  APEX CALLS
    // ═══════════════════════════════════════════════════════════════

    async setAvailable(isAvailable, reason) {
        this.isLoading = true;
        try {
            await setMyAvailability({ isAvailable, reason });

            // Bake elapsed time into base counters before switching
            const now = Date.now();
            const elapsedSinceQuery = Math.max(0,
                Math.floor((now - this._queryTimestamp) / 1000));

            if (this._currentStatusIsAvailable) {
                this._baseAvailableSeconds += elapsedSinceQuery;
            } else {
                this._baseOfflineSeconds += elapsedSinceQuery;
            }
            this._baseSessionSeconds += elapsedSinceQuery;

            // Reset baseline to now
            this._queryTimestamp = now;
            this._currentStatusStartTime = now;
            this._currentStatusIsAvailable = isAvailable;
            this.isAvailable = isAvailable;

            this._updateElapsed();

            this.showToast(
                'Success',
                isAvailable ? 'You are now Available.' : 'You are now Offline.',
                'success'
            );
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  UTILITIES
    // ═══════════════════════════════════════════════════════════════

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