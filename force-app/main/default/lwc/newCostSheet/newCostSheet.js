import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getLeadContext from '@salesforce/apex/CostSheetController.getLeadContext';
import searchUnits from '@salesforce/apex/CostSheetController.searchUnits';
import getUnitCalculation from '@salesforce/apex/CostSheetController.getUnitCalculation';
import recalculate from '@salesforce/apex/CostSheetController.recalculate';
import getStandardMilestones from '@salesforce/apex/CostSheetController.getStandardMilestones';
import saveCostSheet from '@salesforce/apex/CostSheetController.saveCostSheet';
import getDiscountLabels from '@salesforce/apex/DiscountApprovalController.getDiscountLabels';
import getConfiguredDiscountFields from '@salesforce/apex/DiscountApprovalController.getConfiguredDiscountFields';
import previewDiscountApproval from '@salesforce/apex/DiscountApprovalController.previewDiscountApproval';
import getCostSheetFieldConfig from '@salesforce/apex/CostSheetController.getCostSheetFieldConfig';

export default class NewCostSheet extends NavigationMixin(LightningElement) {
    _recordId;
    _loaded = false;

    @track isLoading = true;
    @track isSaving = false;
    @track leadCtx = {};
    @track hasProject = false;
    @track errorMsg = '';
     @track crossProjectAllowed = false;

    // ── Step tracking ─────────────────────────────────────────
    @track currentStep = 'unit'; // unit | costsheet | milestones

    // ── Unit search ───────────────────────────────────────────
    @track searchTerm = '';
    @track unitOptions = [];
    @track isSearching = false;
    @track selectedUnit = null;

    // ── Calculation results ───────────────────────────────────
    @track calc = {};
    @track isRecalculating = false;

    // ── Additional discounts (dynamic based on configured matrix) ──
    @track discountValues = [];
    @track discountLabels = {};
    @track configuredDiscountFields = []; // [{fieldNumber, label, unitFieldAPI}]

    // ── Metadata-driven field config ─────────────────────────────
    @track fieldConfig = [];      // raw metadata records
    @track fieldConfigMap = {};   // API name -> config
    @track fieldSections = [];    // [{section, fields: [...]}]

    // ── Payment milestones ────────────────────────────────────
    @track paymentPlanType = 'Standard';
    @track milestones = [];
    @track isMilestonesLoading = false;

    // ── Category / status options ─────────────────────────────
    get categoryOptions() {
        return [
            { label: 'Booking', value: 'Booking' },
            { label: 'Agreement', value: 'Agreement' },
            { label: 'Construction', value: 'Construction' },
            { label: 'Registration', value: 'Registration' },
            { label: 'Possession', value: 'Possession' }
        ];
    }

    get statusOptions() {
        return [
            { label: 'Planned', value: 'Planned' },
            { label: 'Demanded', value: 'Demanded' },
            { label: 'Partial Received', value: 'Partial Received' },
            { label: 'Received', value: 'Received' }
        ];
    }

    get paymentPlanOptions() {
        return [
            { label: 'Standard', value: 'Standard' },
            { label: 'Custom', value: 'Custom' }
        ];
    }

    // ── Computed getters ──────────────────────────────────────
    get isUnitStep() { return this.currentStep === 'unit'; }
    get isCostSheetStep() { return this.currentStep === 'costsheet'; }
    get isMilestonesStep() { return this.currentStep === 'milestones'; }
    get isStandard() { return this.paymentPlanType === 'Standard'; }
    get isCustom() { return this.paymentPlanType === 'Custom'; }
      get canGoToCostSheet() { return this.selectedUnit !== null && !!this.leadCtx.projectId; }
    get disableGoToCostSheet() { return !this.canGoToCostSheet; }
    get canGoToMilestones() { return this.calc.Agreement_Value__c > 0; }
    get todayDate() { return new Date().toISOString().split('T')[0]; }
    get showUnitResults() { return this.unitOptions.length > 0; }
    get hasMilestones() { return this.milestones.length > 0; }
    get needsApproval() {
        return this.paymentPlanType === 'Custom' ||
               this.discountValues.some(v => v > 0);
    }


      get showProjectPicker() {
        return this.crossProjectAllowed;
    }

    get selectedProjectId() {
        return this.leadCtx.projectId || '';
    }

    get canSearchUnits() {
        return !!this.leadCtx.projectId;
    }

    get discountFieldsList() {
        return this.configuredDiscountFields.map((cfg, idx) => ({
            key: 'df-' + cfg.fieldNumber,
            index: idx,
            fieldNumber: cfg.fieldNumber,
            label: cfg.label || ('Discount ' + cfg.fieldNumber),
            unitFieldAPI: cfg.unitFieldAPI,
            value: this.discountValues[idx] || 0
        }));
    }

    get hasConfiguredDiscounts() {
        return this.configuredDiscountFields.length > 0;
    }

    get totalMilestonePct() {
        let total = 0;
        for (const m of this.milestones) {
            total += m.paymentPct || 0;
        }
        return Math.round(total * 100) / 100;
    }

    get milestonePctValid() {
        return Math.abs(this.totalMilestonePct - 100) < 0.01;
    }

    get milestonePctClass() {
        return this.milestonePctValid ? '' : 'slds-text-color_error';
    }

    get canSave() {
        return this.hasMilestones && this.milestonePctValid && !this.isSaving;
    }

    get disableSave() { return !this.canSave; }

    get approvalBadge() {
        return this.needsApproval ? 'Pending Approval' : 'Auto-Approved';
    }

    // ── Formatted currency getters for preview ─────────────────
    get fmtBaseRate()       { return this.formatCurrency(this.calc.Base_Rate_Sqft__c); }
    get fmtBasePrice()      { return this.formatCurrency(this.calc.Base_Price__c); }
    get fmtFloorRiseSqft()  { return this.formatCurrency(this.calc.Floor_Rise_Sqft__c); }
    get fmtFloorRiseTotal() { return this.formatCurrency(this.calc.Floor_Rise_Total__c); }
    get fmtPLC()            { return this.formatCurrency(this.calc.PLC_Charges__c); }
    get fmtAmenity()        { return this.formatCurrency(this.calc.Amenity_Charges__c); }
    get fmtInfra()          { return this.formatCurrency(this.calc.Infra_Charges__c); }
    get fmtDoc()            { return this.formatCurrency(this.calc.Doc_Charges__c); }
    get fmtMoveIn()         { return this.formatCurrency(this.calc.Move_In_Charges__c); }
    get fmtMaintSqft()      { return this.formatCurrency(this.calc.Maintenance_Sqft_Month__c); }
    get fmtMaintTotal()     { return this.formatCurrency(this.calc.Maintenance_Total__c); }
    get fmtCorpusSqft()     { return this.formatCurrency(this.calc.Corpus_Fund_Sqft__c); }
    get fmtCorpusTotal()    { return this.formatCurrency(this.calc.Corpus_Total__c); }
    get fmtTotalDiscount()  { return this.formatCurrency(this.calc.Total_Discount__c); }
    get fmtGstAmount()      { return this.formatCurrency(this.calc.GST_Amount__c); }
    get fmtStampDuty()      { return this.formatCurrency(this.calc.Stamp_Duty_Amount__c); }
    get fmtRegistration()   { return this.formatCurrency(this.calc.Registration_Amount__c); }
    get fmtAgreementValue() { return this.formatCurrency(this.calc.Agreement_Value__c); }
    get fmtNetPayable()     { return this.formatCurrency(this.calc.Net_Payable__c); }

    get fmtGstPct()   { return this.calc.GST_Percentage__c || 0; }
    get fmtStampPct() { return this.calc.Stamp_Duty_Pct__c || 0; }
    get fmtRegPct()   { return this.calc.Registration_Pct__c || 0; }

    formatCurrency(val) {
        if (val == null || val === undefined) return '0.00';
        return Number(val).toLocaleString('en-IN', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    // ── recordId setter (LWC Quick Action pattern) ────────────
    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._loaded) {
            this._loaded = true;
            this.loadLeadContext();
        }
    }

    // ── Init ──────────────────────────────────────────────────
    async loadLeadContext() {
        this.isLoading = true;
        try {
            this.leadCtx = await getLeadContext({ leadId: this._recordId });
            this.hasProject = !!this.leadCtx.projectId;
            this.crossProjectAllowed = this.leadCtx.crossProjectAllowed === true;   // ← NEW
            // Block only when the lead has no project AND the user can't pick one
            if (!this.hasProject && !this.crossProjectAllowed) {
                this.errorMsg = 'This lead does not have a Project assigned. Please assign a Project before creating a Cost Sheet.';
            }
            // Load configured discount fields (dynamic count based on matrix)
            try {
                const configFields = await getConfiguredDiscountFields({ projectId: this.leadCtx.projectId });
                this.configuredDiscountFields = configFields || [];
                this.discountValues = new Array(this.configuredDiscountFields.length).fill(0);
                // Also build labels map for backward compatibility
                const labels = {};
                for (const cfg of this.configuredDiscountFields) {
                    labels[cfg.fieldNumber] = cfg.label;
                }
                this.discountLabels = labels;
            } catch (e) {
                // Non-fatal: fall back to getDiscountLabels
                try {
                    this.discountLabels = await getDiscountLabels({ projectId: this.leadCtx.projectId });
                } catch (e2) {
                    // Labels will default
                }
            }

            // Load cost sheet field configuration metadata
            try {
                const configs = await getCostSheetFieldConfig();
                this.fieldConfig = configs || [];
                // Build lookup map: API name -> config record
                const cfgMap = {};
                for (const cfg of this.fieldConfig) {
                    cfgMap[cfg.Field_API_Name__c] = cfg;
                }
                this.fieldConfigMap = cfgMap;
                // Group by section for dynamic rendering
                this.fieldSections = this._groupFieldsBySection(this.fieldConfig);
            } catch (e) {
                // Non-fatal: fields will show with default layout
            }
        } catch (error) {
            this.errorMsg = this.reduceErrors(error);
        } finally {
            this.isLoading = false;
        }
    }
     async handleProjectChange(event) {
        const newProjectId = event.detail.recordId || '';
        // Update the working project on leadCtx (used by search + save)
        this.leadCtx = { ...this.leadCtx, projectId: newProjectId, projectName: '' };
        this.hasProject = !!newProjectId;

        // Reset unit selection and search results — they were scoped to the old project
        this.selectedUnit = null;
        this.calc = {};
        this.unitOptions = [];
        this.searchTerm = '';
        this.milestones = [];

        // Reload configured discount fields for the new project
        if (newProjectId) {
            try {
                const configFields = await getConfiguredDiscountFields({ projectId: newProjectId });
                this.configuredDiscountFields = configFields || [];
                this.discountValues = new Array(this.configuredDiscountFields.length).fill(0);
                const labels = {};
                for (const cfg of this.configuredDiscountFields) {
                    labels[cfg.fieldNumber] = cfg.label;
                }
                this.discountLabels = labels;
            } catch (e) {
                // Non-fatal
            }
        }
    }

    // ── Unit search ───────────────────────────────────────────
    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        if (this.searchTerm.length >= 1) {
            this.doSearch();
        } else {
            this.unitOptions = [];
        }
    }

    async doSearch() {
        this.isSearching = true;
        try {
            this.unitOptions = await searchUnits({
                projectId: this.leadCtx.projectId,
                searchTerm: this.searchTerm
            });
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isSearching = false;
        }
    }

    async handleUnitSelect(event) {
        const unitId = event.currentTarget.dataset.id;
        this.isLoading = true;
        try {
            this.calc = await getUnitCalculation({ unitId });
            this.selectedUnit = {
                id: this.calc.unitId,
                name: this.calc.unitName,
                unitNumber: this.calc.unitNumber,
                bhkType: this.calc.bhkType,
                floor: this.calc.floor,
                towerName: this.calc.towerName
            };
            this.unitOptions = [];
            this.searchTerm = '';
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isLoading = false;
        }
    }

    handleClearUnit() {
        this.selectedUnit = null;
        this.calc = {};
        this.discountPerSqft = 0;
        this.milestones = [];
    }

    // ── Navigation ────────────────────────────────────────────
    goToCostSheet() {
        this.currentStep = 'costsheet';
    }

    goToMilestones() {
        this.currentStep = 'milestones';
        if (this.paymentPlanType === 'Standard' && this.milestones.length === 0) {
            this.loadStandardMilestones();
        }
    }

    goBackToUnit() {
        this.currentStep = 'unit';
    }

    goBackToCostSheet() {
        this.currentStep = 'costsheet';
    }

    // ── Discount handling ─────────────────────────────────────
    handleAdditionalDiscountChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const val = parseFloat(event.target.value) || 0;
        const cfg = this.configuredDiscountFields[idx];

        // Track if this discount exceeds its unit field value (for approval toast message)
        if (cfg && cfg.unitFieldAPI && this.calc) {
            const maxVal = this.calc[cfg.unitFieldAPI] || 0;
            if (maxVal > 0 && val > maxVal) {
                this._exceededDiscountInfo = {
                    label: cfg.label || 'Discount',
                    unitFieldLabel: cfg.unitFieldAPI.replace(/__c$/i, '').replace(/_/g, ' '),
                    maxVal: maxVal
                };
            } else {
                this._exceededDiscountInfo = null;
            }
        }

        const updated = [...this.discountValues];
        updated[idx] = val;
        this.discountValues = updated;

        // Trigger full recalculation with per-field discounts applied
        this._recalculateAll();
    }

    async _recalculateAll() {
        if (!this.selectedUnit) return;
        this.isRecalculating = true;
        try {
            const additionalDiscounts = this.configuredDiscountFields.map((cfg, idx) => ({
                fieldNumber: cfg.fieldNumber,
                unitFieldAPI: cfg.unitFieldAPI || '',
                label: cfg.label || '',
                value: this.discountValues[idx] || 0
            }));
            const updated = await recalculate({
                unitId: this.selectedUnit.id,
                additionalDiscountsJson: JSON.stringify(additionalDiscounts)
            });
            this.calc = { ...updated };
            if (this.milestones.length > 0) {
                this.recalcMilestoneAmounts();
            }

            // Preview discount approval to show approver info
            const hasAnyDiscount = this.discountValues.some(v => v > 0);
            if (hasAnyDiscount) {
                try {
                    const discountsForPreview = this.configuredDiscountFields.map((cfg, i) => ({
                        fieldNumber: cfg.fieldNumber,
                        value: this.discountValues[i] || 0
                    }));
                    const summary = await previewDiscountApproval({
                        projectId: this.leadCtx.projectId,
                        discountsJson: JSON.stringify(discountsForPreview),
                        agreementValue: this.calc.Agreement_Value__c || 0
                    });
                    if (summary && summary.requiresApproval) {
                        const approverName = summary.nextApproverName || 'the designated approver';
                        let msg;
                        if (this._exceededDiscountInfo) {
                            const info = this._exceededDiscountInfo;
                            msg = info.label + ' exceeds ' + info.unitFieldLabel +
                                ' value (' + this.formatCurrency(info.maxVal) +
                                '). Approval will be sent to ' + approverName + '.';
                            this._exceededDiscountInfo = null;
                        } else {
                            msg = 'Discount exceeds the approval threshold. Approval will be sent to ' + approverName + '.';
                        }
                        this.dispatchEvent(new ShowToastEvent({
                            title: 'Approval Required',
                            message: msg,
                            variant: 'info'
                        }));
                    }
                } catch (previewError) {
                    // Non-fatal: preview failure should not block the workflow
                }
            }
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isRecalculating = false;
        }
    }

    // ── Payment plan type ─────────────────────────────────────
    handlePlanTypeChange(event) {
        this.paymentPlanType = event.detail.value;
        this.milestones = [];
        if (this.paymentPlanType === 'Standard') {
            this.loadStandardMilestones();
        } else {
            this.addCustomMilestone();
        }
    }

    async loadStandardMilestones() {
        this.isMilestonesLoading = true;
        try {
            const raw = await getStandardMilestones({
                towerId: this.calc.towerId,
                projectId: this.leadCtx.projectId
            });
            const agreementVal = this.calc.Agreement_Value__c || 0;
            this.milestones = raw.map((m, idx) => {
                const rawAmt = Math.round(agreementVal * m.paymentPct / 100 * 100) / 100;
                return {
                    key: Date.now() + idx,
                    milestoneName: m.name,
                    category: m.category,
                    paymentPct: m.paymentPct,
                    amount: rawAmt,
                    fmtAmount: this.formatCurrency(rawAmt),
                    sequence: m.sequence,
                    dueDate: null,
                    status: 'Planned',
                    constructionMilestoneId: m.constructionMilestoneId,
                    constructionMilestoneName: m.constructionMilestoneName,
                    isStandard: true
                };
            });
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isMilestonesLoading = false;
        }
    }

    // ── Custom milestone CRUD ─────────────────────────────────
    addCustomMilestone() {
        const nextSeq = this.milestones.length + 1;
        this.milestones = [
            ...this.milestones,
            {
                key: Date.now(),
                milestoneName: '',
                category: 'Booking',
                paymentPct: 0,
                amount: 0,
                fmtAmount: '0.00',
                sequence: nextSeq,
                dueDate: null,
                status: 'Planned',
                constructionMilestoneId: null,
                constructionMilestoneName: '',
                isStandard: false
            }
        ];
    }

    handleRemoveMilestone(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.milestones = this.milestones.filter((_, i) => i !== idx);
    }

    handleMilestoneChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const field = event.currentTarget.dataset.field;
        let value = event.target.value !== undefined ? event.target.value : event.detail.value;

        // Validate due date is not in the past
        if (field === 'dueDate' && value) {
            const today = new Date().toISOString().split('T')[0];
            if (value < today) {
                this.showError('Due Date cannot be in the past. Please select today or a future date.');
                // Reset the input to the previous value
                event.target.value = this.milestones[idx].dueDate || '';
                return;
            }
        }

        const updated = [...this.milestones];
        updated[idx] = { ...updated[idx], [field]: field === 'paymentPct' ? (parseFloat(value) || 0) : value };

        if (field === 'paymentPct') {
            const pct = parseFloat(value) || 0;
            const agreementVal = this.calc.Agreement_Value__c || 0;
            const rawAmt = Math.round(agreementVal * pct / 100 * 100) / 100;
            updated[idx].amount = rawAmt;
            updated[idx].fmtAmount = this.formatCurrency(rawAmt);
        }

        this.milestones = updated;
    }

    recalcMilestoneAmounts() {
        const agreementVal = this.calc.Agreement_Value__c || 0;
        this.milestones = this.milestones.map(m => {
            const rawAmt = Math.round(agreementVal * (m.paymentPct || 0) / 100 * 100) / 100;
            return {
                ...m,
                amount: rawAmt,
                fmtAmount: this.formatCurrency(rawAmt)
            };
        });
    }

    // ── Save ──────────────────────────────────────────────────
    async handleSave() {
        if (!this.milestonePctValid) {
            this.showError('Total milestone percentage must equal 100%. Current: ' + this.totalMilestonePct + '%');
            return;
        }

        // Validate custom milestone names
        if (this.isCustom) {
            for (const m of this.milestones) {
                if (!m.milestoneName || m.milestoneName.trim() === '') {
                    this.showError('All milestones must have a name.');
                    return;
                }
            }
        }

        // Validate due dates: required and not in the past
        const today = new Date().toISOString().split('T')[0];
        for (const m of this.milestones) {
            if (!m.dueDate) {
                this.showError('Milestone "' + (m.milestoneName || '#' + m.sequence) + '" is missing a due date.');
                return;
            }
            if (m.dueDate < today) {
                this.showError('Milestone "' + (m.milestoneName || '#' + m.sequence) + '" has a past due date. Please select today or a future date.');
                return;
            }
        }

        this.isSaving = true;
        try {
            const paymentLines = this.milestones.map(m => ({
                milestoneName: m.milestoneName,
                category: m.category,
                paymentPct: m.paymentPct,
                amount: m.amount,
                sequence: m.sequence,
                dueDate: m.dueDate,
                status: m.status,
                constructionMilestoneId: m.constructionMilestoneId
            }));

            const additionalDiscounts = this.configuredDiscountFields.map((cfg, idx) => ({
                fieldNumber: cfg.fieldNumber,
                unitFieldAPI: cfg.unitFieldAPI || '',
                label: cfg.label || '',
                value: this.discountValues[idx] || 0
            }));
            const costSheetId = await saveCostSheet({
                leadId: this._recordId,
                unitId: this.selectedUnit.id,
                projectId: this.leadCtx.projectId,
                paymentPlanType: this.paymentPlanType,
                paymentLinesJson: JSON.stringify(paymentLines),
                additionalDiscountsJson: JSON.stringify(additionalDiscounts)
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Cost Sheet created successfully.' +
                    (this.needsApproval ? ' Submitted for approval.' : ''),
                variant: 'success'
            }));

            // Navigate to the new Cost Sheet record
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: costSheetId,
                    objectApiName: 'Cost_Sheet__c',
                    actionName: 'view'
                }
            });

            this.handleClose();
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isSaving = false;
        }
    }

    /**
     * Check if a field should be visible based on metadata config.
     * Returns true if no metadata is configured (backward-compatible).
     */
    isFieldVisible(fieldApiName) {
        if (!this.fieldConfigMap || Object.keys(this.fieldConfigMap).length === 0) return true;
        const cfg = this.fieldConfigMap[fieldApiName];
        return cfg ? cfg.Is_Visible__c : true;
    }

    /**
     * Group field configs by section for dynamic rendering.
     */
    _groupFieldsBySection(configs) {
        const sectionMap = {};
        for (const cfg of configs) {
            const section = cfg.Section__c || 'Other';
            if (!sectionMap[section]) {
                sectionMap[section] = { section, fields: [] };
            }
            sectionMap[section].fields.push({
                key: cfg.Field_API_Name__c,
                apiName: cfg.Field_API_Name__c,
                label: cfg.Field_Label__c,
                type: cfg.Field_Type__c,
                isEditable: cfg.Is_Editable__c,
                isRequired: cfg.Is_Required__c,
                defaultValue: cfg.Default_Value__c
            });
        }
        return Object.values(sectionMap);
    }

    /**
     * Build a 6-element array mapping discount values to their correct field positions.
     * configuredDiscountFields may have non-sequential field numbers (e.g., 1, 3, 5).
     * The save method expects index 0 = Discount_1__c, index 1 = Discount_2__c, etc.
     */
    buildDiscountValuesForSave() {
        const result = [0, 0, 0, 0, 0, 0];
        this.configuredDiscountFields.forEach((cfg, idx) => {
            const fieldIdx = cfg.fieldNumber - 1; // fieldNumber is 1-based
            if (fieldIdx >= 0 && fieldIdx < 6) {
                result[fieldIdx] = this.discountValues[idx] || 0;
            }
        });
        return result;
    }

    // ── Utilities ─────────────────────────────────────────────
    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showError(msg) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: msg,
            variant: 'error',
            mode: 'sticky'
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