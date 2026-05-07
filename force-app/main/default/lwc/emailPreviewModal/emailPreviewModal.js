import { LightningElement, api, track } from 'lwc';

export default class EmailPreviewModal extends LightningElement {
    @api isLoading = false;

    @track _ccList = [];
    @track _bccList = [];
    @track _initialized = false;

    _emailData;

    @api
    get emailData() {
        return this._emailData;
    }
    set emailData(value) {
        const previousData = this._emailData;
        this._emailData = value;

        // Initialize local CC/BCC lists from emailData when first set
        // or when the underlying data reference changes (modal reopened with new data)
        if (value && (!this._initialized || previousData !== value)) {
            this._ccList = this._toArray(value.ccAddresses).map((email, idx) => ({
                id: 'cc_' + idx,
                email: email,
                key: 'cc_' + idx
            }));
            this._bccList = this._toArray(value.bccAddresses).map((email, idx) => ({
                id: 'bcc_' + idx,
                email: email,
                key: 'bcc_' + idx
            }));
            this._initialized = true;
        }
    }

    // ============ EVENT HANDLERS ============

    handleClose() {
        this._dispatchCcBccChange();
        this._initialized = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleEdit() {
        this._dispatchCcBccChange();
        this._initialized = false;
        this.dispatchEvent(new CustomEvent('edit'));
    }

    handleSend() {
        this._dispatchCcBccChange();
        this.dispatchEvent(new CustomEvent('send'));
    }

    // ============ CC HANDLERS ============

    handleAddCc() {
        const input = this.template.querySelector('[data-id="preview-new-cc"]');
        if (input && input.value && this._isValidEmail(input.value)) {
            // Check for duplicates
            if (this._isDuplicateEmail(input.value, this._ccList)) {
                input.setCustomValidity('This email is already in the CC list');
                input.reportValidity();
                return;
            }
            const uniqueId = 'cc_new_' + Date.now();
            this._ccList = [
                ...this._ccList,
                {
                    id: uniqueId,
                    email: input.value.trim(),
                    key: uniqueId
                }
            ];
            input.value = '';
            input.setCustomValidity('');
            input.reportValidity();
            this._dispatchCcBccChange();
        } else if (input) {
            input.setCustomValidity('Please enter a valid email address');
            input.reportValidity();
        }
    }

    handleRemoveCc(event) {
        const removeId = event.target.name;
        this._ccList = this._ccList.filter(item => item.id !== removeId);
        this._dispatchCcBccChange();
    }

    handleCcKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleAddCc();
        }
        // Clear custom validity when user types
        const input = event.target;
        if (input) {
            input.setCustomValidity('');
            input.reportValidity();
        }
    }

    // ============ BCC HANDLERS ============

    handleAddBcc() {
        const input = this.template.querySelector('[data-id="preview-new-bcc"]');
        if (input && input.value && this._isValidEmail(input.value)) {
            // Check for duplicates
            if (this._isDuplicateEmail(input.value, this._bccList)) {
                input.setCustomValidity('This email is already in the BCC list');
                input.reportValidity();
                return;
            }
            const uniqueId = 'bcc_new_' + Date.now();
            this._bccList = [
                ...this._bccList,
                {
                    id: uniqueId,
                    email: input.value.trim(),
                    key: uniqueId
                }
            ];
            input.value = '';
            input.setCustomValidity('');
            input.reportValidity();
            this._dispatchCcBccChange();
        } else if (input) {
            input.setCustomValidity('Please enter a valid email address');
            input.reportValidity();
        }
    }

    handleRemoveBcc(event) {
        const removeId = event.target.name;
        this._bccList = this._bccList.filter(item => item.id !== removeId);
        this._dispatchCcBccChange();
    }

    handleBccKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleAddBcc();
        }
        // Clear custom validity when user types
        const input = event.target;
        if (input) {
            input.setCustomValidity('');
            input.reportValidity();
        }
    }

    // ============ PRIVATE HELPERS ============

    _toArray(value) {
        if (!value) return [];
        if (Array.isArray(value)) return [...value];
        if (typeof value === 'string' && value.trim()) return [value];
        return [];
    }

    _isValidEmail(email) {
        if (!email) return false;
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email.trim());
    }

    _isDuplicateEmail(email, list) {
        const normalizedEmail = email.trim().toLowerCase();
        return list.some(item => item.email.toLowerCase() === normalizedEmail);
    }

    _dispatchCcBccChange() {
        this.dispatchEvent(new CustomEvent('ccbccchange', {
            detail: {
                ccAddresses: this._ccList.map(item => item.email),
                bccAddresses: this._bccList.map(item => item.email)
            }
        }));
    }

    // ============ GETTERS ============

    get hasEmailData() {
        return this._emailData !== null && this._emailData !== undefined;
    }

    get fromAddress() {
        return this._emailData?.fromAddressLabel || 'Default';
    }

    get toAddresses() {
        if (!this._emailData?.toAddresses) return '';
        return Array.isArray(this._emailData.toAddresses)
            ? this._emailData.toAddresses.join(', ')
            : this._emailData.toAddresses;
    }

    get ccPills() {
        return this._ccList;
    }

    get bccPills() {
        return this._bccList;
    }

    get hasCcAddresses() {
        return this._ccList.length > 0;
    }

    get hasBccAddresses() {
        return this._bccList.length > 0;
    }

    get subject() {
        return this._emailData?.subject || '';
    }

    get body() {
        return this._emailData?.body || '';
    }

    get attachments() {
        return this._emailData?.attachments || [];
    }

    get hasAttachments() {
        return this.attachments.length > 0;
    }

    get attachmentCount() {
        return this.attachments.length;
    }

    get uploadedFiles() {
        return this._emailData?.uploadedFiles || [];
    }

    get hasUploadedFiles() {
        return this.uploadedFiles.length > 0;
    }
}