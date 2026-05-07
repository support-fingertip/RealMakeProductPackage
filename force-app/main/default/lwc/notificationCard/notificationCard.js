import { LightningElement, api } from 'lwc';

export default class NotificationCard extends LightningElement {

    @api record;
    @api fieldConfigs;
    @api statusActions;

    // ═══════════════════════════════════════════════════════════════
    //  COMPUTED GETTERS
    // ═══════════════════════════════════════════════════════════════

    get cardTitle() {
        return this.record ? this.record.title : '';
    }

    get displayFields() {
        if (!this.record || !this.record.fields) return [];
        return this.record.fields
            .filter(f => !this._isTitleField(f) && f.value && f.value.trim() !== '')
            .map((f, idx) => ({
                ...f,
                key: this.record.recordId + '-' + idx,
                isBadge: f.fieldType === 'BADGE',
                isPhone: f.fieldType === 'PHONE',
                isEmail: f.fieldType === 'EMAIL',
                isDateTime: f.fieldType === 'DATETIME' || f.fieldType === 'DATE',
                isText: f.fieldType === 'TEXT' || f.fieldType === 'RELATIONSHIP',
                computedBadgeClass: this._getBadgeClass(f.badgeVariant)
            }));
    }

    get availableTransitions() {
        if (!this.statusActions || !this.record) return [];
        const objActions = this.statusActions[this.record.sObjectName];
        if (!objActions || !objActions.transitions) return [];

        return objActions.transitions
            .filter(t => t.from === this.record.currentStatus)
            .map((t, idx) => ({
                ...t,
                index: String(idx),
                btnClass: 'action-btn action-btn--' + (t.variant || 'brand')
            }));
    }

    get hasTransitions() {
        return this.availableTransitions.length > 0;
    }

    get statusBadgeClass() {
        const status = (this.record?.currentStatus || '').toLowerCase();
        if (status === 'completed') return 'status-badge status-badge--success';
        if (status === 'cancelled' || status === 'no-show') return 'status-badge status-badge--error';
        if (status === 'pending' || status === 'scheduled') return 'status-badge status-badge--warning';
        if (status === 'new enquiry') return 'status-badge status-badge--info';
        return 'status-badge';
    }

    get hasStatus() {
        return this.record && this.record.currentStatus;
    }

    get showCallIcon() {
        if (!this.record) return false;
        const obj = this.record.sObjectName;
        return obj === 'Followup__c' || obj === 'Site_Visit__c';
    }

    // ═══════════════════════════════════════════════════════════════
    //  EVENT DISPATCHERS
    // ═══════════════════════════════════════════════════════════════

    handleTransitionClick(event) {
        const transitionIndex = parseInt(event.currentTarget.dataset.index, 10);
        const transition = this.availableTransitions[transitionIndex];
        this.dispatchEvent(new CustomEvent('statuschange', {
            detail: {
                record: this.record,
                transition: transition
            }
        }));
    }

    handleCallClick(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('callclick', {
            detail: {
                recordId: this.record.recordId,
                sObjectName: this.record.sObjectName,
                title: this.record.title
            }
        }));
    }

    handleNavigate() {
        this.dispatchEvent(new CustomEvent('recordnavigate', {
            detail: {
                recordId: this.record.recordId,
                sObjectName: this.record.sObjectName
            }
        }));
    }

    // ═══════════════════════════════════════════════════════════════
    //  PRIVATE HELPERS
    // ═══════════════════════════════════════════════════════════════

    _isTitleField(field) {
        if (!this.fieldConfigs) return false;
        const cfg = this.fieldConfigs.find(
            fc => fc.sObjectName === this.record.sObjectName
                && fc.displayLabel === field.label
                && fc.isTitleField
        );
        return !!cfg;
    }

    _getBadgeClass(variant) {
        const classMap = {
            success: 'field-badge field-badge--success',
            warning: 'field-badge field-badge--warning',
            error: 'field-badge field-badge--error',
            inverse: 'field-badge field-badge--inverse'
        };
        return classMap[variant] || 'field-badge';
    }
}