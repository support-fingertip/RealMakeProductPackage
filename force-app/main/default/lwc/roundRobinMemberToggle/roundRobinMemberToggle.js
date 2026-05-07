import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getMembers from '@salesforce/apex/RoundRobinMemberController.getMembers';
import toggleMemberStatus from '@salesforce/apex/RoundRobinMemberController.toggleMemberStatus';

const SECTION_LABELS = {
    'Pre-Sales': 'Pre Sale Users',
    'Sales': 'Sales Users',
    'Sales Manager': 'Sales Manager',
    'Post-Sales': 'Post Sale Users',
    'Channel Partner': 'Channel Partner Users'
};

export default class RoundRobinMemberToggle extends LightningElement {
    @api recordId;
    members = [];
    isLoading = true;
    wiredMembersResult;

    @wire(getMembers, { roundRobinId: '$recordId' })
    wiredMembers(result) {
        this.wiredMembersResult = result;
        const { data, error } = result;
        if (data) {
            this.members = data.map(m => ({
                id: m.Id,
                name: m.User__r ? m.User__r.Name : m.Name,
                isActive: m.Is_Active__c,
                assignmentType: m.Assignment_Type__c || '',
                activeLabel: m.Is_Active__c ? 'true' : 'false',
                buttonLabel: m.Is_Active__c ? 'Deactivate' : 'Activate',
                buttonCssClass: m.Is_Active__c ? 'action-btn deactivate-btn' : 'action-btn activate-btn'
            }));
            this.isLoading = false;
        } else if (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.isLoading = false;
        }
    }

    get groupedMembers() {
        const groups = {};
        this.members.forEach(member => {
            const type = member.assignmentType || 'Other';
            if (!groups[type]) {
                groups[type] = {
                    sectionTitle: SECTION_LABELS[type] || (type + ' Users'),
                    key: type,
                    members: []
                };
            }
            groups[type].members.push(member);
        });
        // Return in a consistent order based on SECTION_LABELS keys, then others
        const orderedKeys = Object.keys(SECTION_LABELS);
        const result = [];
        orderedKeys.forEach(key => {
            if (groups[key]) {
                result.push(groups[key]);
            }
        });
        // Add any remaining groups not in SECTION_LABELS
        Object.keys(groups).forEach(key => {
            if (!orderedKeys.includes(key)) {
                result.push(groups[key]);
            }
        });
        return result;
    }

    async handleToggle(event) {
        const memberId = event.target.dataset.id;
        const member = this.members.find(m => m.id === memberId);
        if (!member) return;

        const newIsActive = !member.isActive;

        // Optimistic UI update
        this.members = this.members.map(m => {
            if (m.id === memberId) {
                return {
                    ...m,
                    isActive: newIsActive,
                    activeLabel: newIsActive ? 'true' : 'false',
                    buttonLabel: newIsActive ? 'Deactivate' : 'Activate',
                    buttonCssClass: newIsActive ? 'action-btn deactivate-btn' : 'action-btn activate-btn'
                };
            }
            return m;
        });

        try {
            await toggleMemberStatus({ memberId, isActive: newIsActive });
            this.showToast(
                'Success',
                `Member ${newIsActive ? 'activated' : 'deactivated'} successfully`,
                'success'
            );
            await refreshApex(this.wiredMembersResult);
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            await refreshApex(this.wiredMembersResult);
        }
    }

    get hasMembers() {
        return this.members && this.members.length > 0;
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
        return 'An unexpected error occurred. Please try again.';
    }
}