import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import getCostSheetContext from '@salesforce/apex/BookingCreationController.getCostSheetContext';
import createBooking from '@salesforce/apex/BookingCreationController.createBooking';

export default class CreateBookingFromCostSheet extends NavigationMixin(LightningElement) {
    _recordId;
    _hasLoaded = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._hasLoaded) {
            this._hasLoaded = true;
            this.loadContext();
        }
    }

    @track isLoading = true;
    @track isSaving = false;
    @track currentStep = '1';

    // Cost Sheet context
    @track costSheetName = '';
    @track projectName = '';
    @track unitName = '';
    @track towerName = '';
    @track agreementValue = null;
    @track hasMappingConfig = false;
    @track mappedFieldCount = 0;

    // Booking form data
    @track bookingData = {
        Salutation__c: '',
        Customer_Name__c: '',
        Customer_Mobile__c: '',
        Email__c: '',
        Son_Daughter_Wife_of__c: '',
        Date_of_Birth__c: null,
        PAN_Number__c: '',
        Aadhaar__c: '',
        Nationality__c: 'Indian',
        Residential_Status__c: '',
        Booking_Date__c: null,
        Booking_Stage__c: 'New',
        Payment_Plan__c: '',
        Funding_Type__c: '',
        Booking_Source__c: '',
        Remarks__c: ''
    };

    // Co-Applicants
    @track coApplicants = [];
    _coAppKeyCounter = 0;

    // ── Lifecycle ────────────────────────────────────────────

    connectedCallback() {
        this.bookingData.Booking_Date__c = new Date().toISOString().split('T')[0];
        // If recordId is already set (e.g. from record page), load immediately
        if (this._recordId && !this._hasLoaded) {
            this._hasLoaded = true;
            this.loadContext();
        }
    }

    async loadContext() {
        this.isLoading = true;
        try {
            const ctx = await getCostSheetContext({ costSheetId: this.recordId });
            this.costSheetName = ctx.costSheetName;
            this.projectName = ctx.projectName || '';
            this.unitName = ctx.unitName || '';
            this.towerName = ctx.towerName || '';
            this.agreementValue = ctx.agreementValue;
            this.hasMappingConfig = ctx.hasMappingConfig;

            if (ctx.mappingDetails) {
                this.mappedFieldCount = ctx.mappingDetails.length;
            }

            // Pre-populate from Lead info
            if (ctx.leadInfo) {
                if (ctx.leadInfo.leadName) {
                    this.bookingData = { ...this.bookingData, Customer_Name__c: ctx.leadInfo.leadName };
                }
                if (ctx.leadInfo.email) {
                    this.bookingData = { ...this.bookingData, Email__c: ctx.leadInfo.email };
                }
                if (ctx.leadInfo.mobile) {
                    this.bookingData = { ...this.bookingData, Customer_Mobile__c: ctx.leadInfo.mobile };
                } else if (ctx.leadInfo.phone) {
                    this.bookingData = { ...this.bookingData, Customer_Mobile__c: ctx.leadInfo.phone };
                }
            }
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isLoading = false;
        }
    }

    // ── Step navigation getters ─────────────────────────────

    get isStep1() { return this.currentStep === '1'; }
    get isStep2() { return this.currentStep === '2'; }
    get isStep3() { return this.currentStep === '3'; }
    get isStep4() { return this.currentStep === '4'; }

    get formattedAgreementValue() {
        if (this.agreementValue == null) return '-';
        return Number(this.agreementValue).toLocaleString('en-IN', {
            style: 'currency', currency: 'INR',
            minimumFractionDigits: 2, maximumFractionDigits: 2
        });
    }

    get hasProjectInfo() { return this.projectName || this.unitName || this.towerName; }

    get hasCoApplicants() {
        return this.coApplicants.length > 0;
    }

    get coApplicantCount() {
        return this.coApplicants.length;
    }

    // ── Picklist Options ────────────────────────────────────

    get salutationOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Mr.', value: 'Mr.' },
            { label: 'Mrs.', value: 'Mrs.' },
            { label: 'Ms.', value: 'Ms.' }
        ];
    }

    get nationalityOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Indian', value: 'Indian' },
            { label: 'NRI', value: 'NRI' }
        ];
    }

    get residentialStatusOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Resident', value: 'Resident' },
            { label: 'Non-Resident', value: 'Non-Resident' }
        ];
    }

    get bookingStageOptions() {
        return [
            { label: 'New', value: 'New' },
            { label: 'Booked', value: 'Booked' }
        ];
    }

    get paymentPlanOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Construction Linked', value: 'Construction Linked' },
            { label: 'Time Linked', value: 'Time Linked' },
            { label: 'Down Payment', value: 'Down Payment' }
        ];
    }

    get fundingTypeOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Self-Funded', value: 'Self-Funded' },
            { label: 'Bank Loan', value: 'Bank Loan' },
            { label: 'Mixed Funding', value: 'Mixed Funding' },
            { label: 'NBFC Loan', value: 'NBFC Loan' }
        ];
    }

    get bookingSourceOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Walk-In', value: 'Walk-In' },
            { label: 'Referral', value: 'Referral' },
            { label: 'Online Portal', value: 'Online Portal' },
            { label: 'Broker', value: 'Broker' },
            { label: 'Direct Call', value: 'Direct Call' },
            { label: 'Advertisement', value: 'Advertisement' },
            { label: 'Event', value: 'Event' }
        ];
    }

    get relationshipOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Spouse', value: 'Spouse' },
            { label: 'Father', value: 'Father' },
            { label: 'Mother', value: 'Mother' },
            { label: 'Son', value: 'Son' },
            { label: 'Daughter', value: 'Daughter' },
            { label: 'Brother', value: 'Brother' },
            { label: 'Sister', value: 'Sister' },
            { label: 'Other Family Member', value: 'Other Family Member' },
            { label: 'Business Partner', value: 'Business Partner' },
            { label: 'Friend', value: 'Friend' },
            { label: 'Other', value: 'Other' }
        ];
    }

    get occupationOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Salaried', value: 'Salaried' },
            { label: 'Self-Employed', value: 'Self-Employed' },
            { label: 'Business', value: 'Business' },
            { label: 'Professional', value: 'Professional' },
            { label: 'Retired', value: 'Retired' },
            { label: 'Student', value: 'Student' },
            { label: 'Homemaker', value: 'Homemaker' },
            { label: 'Other', value: 'Other' }
        ];
    }

    // ── Event Handlers ──────────────────────────────────────

    handleBookingFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.bookingData = { ...this.bookingData, [field]: value };
    }

    handleAddCoApplicant() {
        this._coAppKeyCounter++;
        this.coApplicants = [
            ...this.coApplicants,
            {
                key: 'ca-' + this._coAppKeyCounter,
                index: this.coApplicants.length + 1,
                Applicant_Name__c: '',
                Relationship__c: '',
                Applicant_Mobile__c: '',
                Applicant_Email__c: '',
                Date_of_Birth__c: null,
                PAN_Number__c: '',
                Aadhar_Number__c: '',
                Occupation__c: '',
                Address__c: ''
            }
        ];
    }

    handleRemoveCoApplicant(event) {
        const key = event.currentTarget.dataset.key;
        this.coApplicants = this.coApplicants
            .filter(c => c.key !== key)
            .map((c, idx) => ({ ...c, index: idx + 1 }));
    }

    handleCoAppFieldChange(event) {
        const key = event.currentTarget.dataset.key;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value !== undefined ? event.detail.value : event.target.value;

        this.coApplicants = this.coApplicants.map(c => {
            if (c.key === key) {
                return { ...c, [field]: value };
            }
            return c;
        });
    }

    // ── Navigation ──────────────────────────────────────────

    handleNext() {
        if (!this.validateCurrentStep()) return;
        const step = parseInt(this.currentStep, 10);
        this.currentStep = String(step + 1);
    }

    handlePrevious() {
        const step = parseInt(this.currentStep, 10);
        if (step > 1) {
            this.currentStep = String(step - 1);
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    validateCurrentStep() {
        if (this.currentStep === '1') {
            if (!this.bookingData.Customer_Name__c || !this.bookingData.Customer_Mobile__c) {
                this.showError('Customer Name and Mobile are required.');
                return false;
            }
            if (!this.bookingData.PAN_Number__c || !this.bookingData.PAN_Number__c.trim()) {
                this.showError('PAN Number is required.');
                return false;
            }
            if (!this.bookingData.Aadhaar__c || !this.bookingData.Aadhaar__c.trim()) {
                this.showError('Aadhaar Number is required.');
                return false;
            }
        }
        if (this.currentStep === '2') {
            for (const coApp of this.coApplicants) {
                if (!coApp.Applicant_Name__c || !coApp.Relationship__c) {
                    this.showError('Each co-applicant must have a Name and Relationship.');
                    return false;
                }
            }
        }
        if (this.currentStep === '3') {
            if (!this.bookingData.Booking_Date__c || !this.bookingData.Payment_Plan__c) {
                this.showError('Booking Date and Payment Plan are required.');
                return false;
            }
        }
        return true;
    }

    // ── Create Booking ──────────────────────────────────────

    async handleCreateBooking() {
        this.isSaving = true;
        try {
            // Prepare co-applicants data (strip out UI-only keys)
            const coAppData = this.coApplicants.map(c => {
                const data = {};
                for (const key of Object.keys(c)) {
                    if (key !== 'key' && key !== 'index' && c[key]) {
                        data[key] = c[key];
                    }
                }
                return data;
            });

            const bookingId = await createBooking({
                costSheetId: this.recordId,
                bookingDataJson: JSON.stringify(this.bookingData),
                coApplicantsJson: JSON.stringify(coAppData)
            });

            this.showSuccess('Booking created successfully!');

            // Navigate to the new Booking record
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: bookingId,
                    objectApiName: 'Booking__c',
                    actionName: 'view'
                }
            });

            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isSaving = false;
        }
    }

    // ── Helpers ──────────────────────────────────────────────

    showSuccess(msg) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success', message: msg, variant: 'success'
        }));
    }

    showError(msg) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error', message: msg, variant: 'error', mode: 'sticky'
        }));
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