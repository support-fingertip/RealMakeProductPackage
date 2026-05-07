/**
 * @description LWC controller for the New Cost Sheet screen action on Lead.
 */
public with sharing class CostSheetController {

    // ─── Unit fields needed for calculation ────────────────────────
    private static final List<String> UNIT_FIELDS = new List<String>{
        'Id', 'Name', 'Unit_Number__c', 'Unit_Code__c',
        'Floor__c', 'Wing__c', 'BHK_Type__c', 'Unit_Type__c',
        'Facing__c', 'Status__c',
        'Carpet_Area__c', 'Saleable_Area__c', 'Super_Builtup_Area__c',
        'UDS__c', 'Base_Rate_Sqft__c', 'Price_Per_Sq_Ft__c',
        'Floor_Rise_Sqft__c', 'Corpus_Fund_Sqft__c',
        'PLC_Charges__c', 'Amenity_Charges__c', 'Infra_Charges__c',
        'Doc_Charges__c', 'Move_In_Charges__c',
        'Maintenance_Sqft_Month__c', 'Maintenance_Months__c',
        'GST_Percentage__c', 'Registration_Pct__c', 'Stamp_Duty_Pct__c',
        'Tower__c', 'Tower__r.Name', 'Project__c', 'Project__r.Name'
    };

    /**
     * @description Get the Lead's project so we can scope the unit search.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLeadContext(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead ID is required.');
        }
        List<Lead__c> leads = [
            SELECT Id, Name, Full_Name__c, Project__c, Project__r.Name
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            throw new AuraHandledException('Lead not found.');
        }
        Lead__c lead = leads[0];
        Map<String, Object> ctx = new Map<String, Object>();
        ctx.put('leadId',      lead.Id);
        ctx.put('leadName',    lead.Full_Name__c);
        ctx.put('leadIdName',  lead.Name);
        ctx.put('projectId',   lead.Project__c);
        ctx.put('projectName', lead.Project__r != null ? lead.Project__r.Name : '');
        ctx.put('crossProjectAllowed', ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed());
        return ctx;
    }

    /**
     * @description Search available units for the lead's project.
     */
    @AuraEnabled
    public static List<Map<String, Object>> searchUnits(Id projectId, String searchTerm) {
        system.debug('projectId '+  projectId);
        system.debug('searchTerm '+  searchTerm);
        if (projectId == null) {
            throw new AuraHandledException('Project is required to search units.');
        }
        String likeVal = '%' + String.escapeSingleQuotes(searchTerm == null ? '' : searchTerm.trim()) + '%';

        List<Unit__c> units = [
            SELECT Id, Name, Unit_Number__c, Unit_Code__c,
                   BHK_Type__c, Floor__c, Wing__c, Tower__r.Name,
                   Super_Builtup_Area__c, Base_Rate_Sqft__c
            FROM Unit__c
            WHERE Project__c = :projectId
              AND Status__c = 'Available'
              AND (Unit_Number__c LIKE :likeVal
                   OR Unit_Code__c LIKE :likeVal
                   OR Name LIKE :likeVal)
            ORDER BY Unit_Number__c ASC
            LIMIT 20
        ];

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Unit__c u : units) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('id',       u.Id);
            row.put('name',     u.Name);
            row.put('unitNo',   u.Unit_Number__c);
            row.put('unitCode', u.Unit_Code__c);
            row.put('bhk',      u.BHK_Type__c);
            row.put('floor',    u.Floor__c);
            row.put('wing',     u.Wing__c);
            row.put('tower',    u.Tower__r != null ? u.Tower__r.Name : '');
            row.put('area',     u.Super_Builtup_Area__c);
            row.put('rate',     u.Base_Rate_Sqft__c);
            results.add(row);
        }
        system.debug('results' + results);
        return results;
    }

    /**
     * @description Fetch full unit details and run the cost-sheet calculation.
     */
    @AuraEnabled
    public static Map<String, Object> getUnitCalculation(Id unitId) {
        if (unitId == null) {
            throw new AuraHandledException('Unit ID is required.');
        }
        String soql = 'SELECT ' + String.join(UNIT_FIELDS, ', ')
                     + ' FROM Unit__c WHERE Id = :unitId LIMIT 1';
        List<Unit__c> units = Database.query(soql);
        if (units.isEmpty()) {
            throw new AuraHandledException('Unit not found.');
        }
        Unit__c unit = units[0];

        Map<String, Object> calc = CostSheetCalculationService.calculateFromUnit(unit);

        // Add unit metadata the LWC needs for display
        calc.put('unitId',      unit.Id);
        calc.put('unitName',    unit.Name);
        calc.put('unitNumber',  unit.Unit_Number__c);
        calc.put('unitCode',    unit.Unit_Code__c);
        calc.put('bhkType',     unit.BHK_Type__c);
        calc.put('unitType',    unit.Unit_Type__c);
        calc.put('floor',       unit.Floor__c);
        calc.put('wing',        unit.Wing__c);
        calc.put('facing',      unit.Facing__c);
        calc.put('towerId',     unit.Tower__c);
        calc.put('towerName',   unit.Tower__r != null ? unit.Tower__r.Name : '');
        calc.put('projectId',   unit.Project__c);
        calc.put('projectName', unit.Project__r != null ? unit.Project__r.Name : '');
        return calc;
    }

    /**
     * @description Recalculate with per-field discounts applied.
     *              Re-fetches the unit, reruns the full template pipeline,
     *              then applies each discount to its tagged field and re-derives.
     */
    @AuraEnabled
    public static Map<String, Object> recalculate(Id unitId, String additionalDiscountsJson) {
        if (unitId == null) {
            throw new AuraHandledException('Unit ID is required for recalculation.');
        }
        String soql = 'SELECT ' + String.join(UNIT_FIELDS, ', ')
                     + ' FROM Unit__c WHERE Id = :unitId LIMIT 1';
        List<Unit__c> units = Database.query(soql);
        if (units.isEmpty()) {
            throw new AuraHandledException('Unit not found.');
        }
        Unit__c unit = units[0];

        Map<String, Object> calc = CostSheetCalculationService.recalculateWithTemplate(unit);

        // Apply per-field discounts
        if (String.isNotBlank(additionalDiscountsJson)) {
            List<Object> rawList = (List<Object>) JSON.deserializeUntyped(additionalDiscountsJson);
            List<Map<String, Object>> discounts = new List<Map<String, Object>>();
            for (Object item : rawList) {
                discounts.add((Map<String, Object>) item);
            }
            CostSheetCalculationService.applyPerFieldDiscounts(calc, discounts);
        }

        // Re-attach UI metadata
        calc.put('unitId',      unit.Id);
        calc.put('unitName',    unit.Name);
        calc.put('unitNumber',  unit.Unit_Number__c);
        calc.put('unitCode',    unit.Unit_Code__c);
        calc.put('bhkType',     unit.BHK_Type__c);
        calc.put('unitType',    unit.Unit_Type__c);
        calc.put('floor',       unit.Floor__c);
        calc.put('wing',        unit.Wing__c);
        calc.put('facing',      unit.Facing__c);
        calc.put('towerId',     unit.Tower__c);
        calc.put('towerName',   unit.Tower__r != null ? unit.Tower__r.Name : '');
        calc.put('projectId',   unit.Project__c);
        calc.put('projectName', unit.Project__r != null ? unit.Project__r.Name : '');
        return calc;
    }

    /**
     * @description Fetch standard payment milestones.
     *              Tries Tower-level first; falls back to Project-level if none found.
     */
    @AuraEnabled
    public static List<Map<String, Object>> getStandardMilestones(Id towerId, Id projectId) {
        // Load standard milestones from Master_Payment_Schedule__c (project-level).
        // Master_Payment_Schedule__c has no Tower field — filtered by project only.
        if (projectId == null) {
            return new List<Map<String, Object>>();
        }

        List<Master_Payment_Schedule__c> milestones = [
            SELECT Id, Name, Percentage__c, Payment_Type__c, Sequence__c,
                   Description__c, Milestone_Description__c,
                   Days_After_Booking__c, Days_After_Previous__c
            FROM Master_Payment_Schedule__c
            WHERE Project__c = :projectId
            AND Is_Active__c = true
            ORDER BY Sequence__c ASC
        ];

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Master_Payment_Schedule__c m : milestones) {
            Map<String, Object> r = new Map<String, Object>();
            r.put('name',          m.Name);
            r.put('category',      m.Payment_Type__c);
            r.put('paymentPct',    m.Percentage__c);
            r.put('sequence',      m.Sequence__c);
            r.put('constructionMilestoneId',   null);
            r.put('constructionMilestoneName', '');
            rows.add(r);
        }
        return rows;
    }

    /**
     * @description Save the cost sheet and its payment lines.
     *              Sets status to "Pending Approval" when there is any discount
     *              or the payment type is Custom.
     */
    @AuraEnabled
    public static Id saveCostSheet(
        Id leadId,
        Id unitId,
        Id projectId,
        String paymentPlanType,
        String paymentLinesJson,
        String additionalDiscountsJson
    ) {
        
        // ── Gate cross-project quotes on the active General Setup ──
        if (!ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed()) {
            Lead__c leadForGate = [SELECT Id, Project__c FROM Lead__c WHERE Id = :leadId LIMIT 1];
            if (leadForGate.Project__c != projectId) {
                throw new AuraHandledException(
                    'Cross-project quotes are not allowed by the current General Setup. ' +
                    'Please contact your administrator.'
                );
            }
        }

        // ── 1. Build Cost Sheet record ──────────────────────────────
        String soql = 'SELECT ' + String.join(UNIT_FIELDS, ', ')
                     + ' FROM Unit__c WHERE Id = :unitId LIMIT 1';
        List<Unit__c> units = Database.query(soql);
        if (units.isEmpty()) {
            throw new AuraHandledException('Unit not found.');
        }
        Unit__c unit = units[0];

        Map<String, Object> calc = CostSheetCalculationService.calculateFromUnit(unit);

        // Apply per-field discounts (each discount reduces its tagged field)
        Boolean hasDiscounts = false;
        if (String.isNotBlank(additionalDiscountsJson)) {
            List<Object> rawList = (List<Object>) JSON.deserializeUntyped(additionalDiscountsJson);
            List<Map<String, Object>> discounts = new List<Map<String, Object>>();
            for (Object item : rawList) {
                Map<String, Object> d = (Map<String, Object>) item;
                discounts.add(d);
                Decimal dv = d.get('value') != null ? Decimal.valueOf(String.valueOf(d.get('value'))) : 0;
                if (dv > 0) hasDiscounts = true;
            }
            CostSheetCalculationService.applyPerFieldDiscounts(calc, discounts);
        }

        Boolean needsApproval = hasDiscounts || paymentPlanType == 'Custom';

        Cost_Sheet__c cs = new Cost_Sheet__c();
        cs.Lead__c               = leadId;
        cs.Unit__c               = unitId;
        cs.Project__c            = projectId;
        cs.Payment_Plan_Type__c  = paymentPlanType;
        //cs.Status__c             = needsApproval ? 'Pending Approval' : 'Approved';
        cs.Status__c             = 'Draft';
        cs.Created_By__c         = UserInfo.getUserId();

        // Editable currency / number fields (values include per-field discount reductions)
        cs.Base_Price__c           = dec(calc, 'Base_Price__c');
        cs.Base_Rate_Sqft__c       = dec(calc, 'Base_Rate_Sqft__c');
        cs.Super_Builtup_Area__c   = dec(calc, 'Super_Builtup_Area__c');
        cs.Super_Builtup_Area__c        = dec(calc, 'Super_Builtup_Area__c');
        cs.Carpet_Area__c          = dec(calc, 'Carpet_Area__c');
        cs.UDS__c                  = dec(calc, 'UDS__c');
        cs.PLC_Charges__c          = dec(calc, 'PLC_Charges__c');
        cs.Amenity_Charges__c      = dec(calc, 'Amenity_Charges__c');
        cs.Infra_Charges__c        = dec(calc, 'Infra_Charges__c');
        cs.Doc_Charges__c          = dec(calc, 'Doc_Charges__c');
        cs.Move_In_Charges__c      = dec(calc, 'Move_In_Charges__c');
        cs.Floor_Rise_Sqft__c      = dec(calc, 'Floor_Rise_Sqft__c');
        cs.Corpus_Fund_Sqft__c     = dec(calc, 'Corpus_Fund_Sqft__c');
        cs.Maintenance_Sqft_Month__c = dec(calc, 'Maintenance_Sqft_Month__c');
        cs.Maintenance_Months__c   = dec(calc, 'Maintenance_Months__c');
        cs.GST_Percentage__c       = dec(calc, 'GST_Percentage__c');
        cs.Registration_Pct__c     = dec(calc, 'Registration_Pct__c');
        cs.Stamp_Duty_Pct__c       = dec(calc, 'Stamp_Duty_Pct__c');

        // Derived fields (Apex-computed)
        cs.Floor_Rise_Total__c     = dec(calc, 'Floor_Rise_Total__c');
        cs.Corpus_Total__c         = dec(calc, 'Corpus_Total__c');
        cs.Maintenance_Total__c    = dec(calc, 'Maintenance_Total__c');
        cs.Total_Discount__c       = dec(calc, 'Total_Discount__c');
        cs.Agreement_Value__c      = dec(calc, 'Agreement_Value__c');
        cs.GST_Amount__c           = dec(calc, 'GST_Amount__c');
        cs.Stamp_Duty_Amount__c    = dec(calc, 'Stamp_Duty_Amount__c');
        cs.Registration_Amount__c  = dec(calc, 'Registration_Amount__c');
        cs.Net_Payable__c          = dec(calc, 'Net_Payable__c');

        // Discount amount, value, and label fields (1-6)
        for (Integer i = 1; i <= 6; i++) {
            cs.put('Discount_' + i + '__c', dec(calc, 'Discount_' + i + '__c'));
            cs.put('Discount_' + i + '_Value__c', dec(calc, 'Discount_' + i + '_Value__c'));
        }
        // Labels from the additionalDiscounts data
        if (String.isNotBlank(additionalDiscountsJson)) {
            List<Object> labelList = (List<Object>) JSON.deserializeUntyped(additionalDiscountsJson);
            for (Object item : labelList) {
                Map<String, Object> d = (Map<String, Object>) item;
                Object fnObj = d.get('fieldNumber');
                String lbl = (String) d.get('label');
                if (fnObj != null && String.isNotBlank(lbl)) {
                    Integer fn = Integer.valueOf(String.valueOf(fnObj));
                    cs.put('Discount_' + fn + '_Label__c', lbl);
                }
            }
        }

        // ── Approval metadata ─────────────────────────────────────
        /*if (!needsApproval) {
            cs.Approved_By__c = UserInfo.getUserId();
            cs.Approval_Date__c = DateTime.now();
        }*/

        insert cs;

        // ── 1b. Run template-based calculation (may override derived fields)
        try {
            CostSheetCalculationService.runPostSaveCalculation(cs.Id);
        } catch (Exception e) {
            System.debug('Post-save calc: ' + e.getMessage());
        }

        // ── 1c. Auto-evaluate and submit discount approval ──────────────────
        if (hasDiscounts) {
            try {
                DiscountApprovalEngine.ApprovalSummary summary =
                    DiscountApprovalEngine.evaluateDiscounts(cs.Id);
                if (summary.requiresApproval) {
                    // Auto-submit: locks record, sets statuses, sends notifications to approvers
                    DiscountApprovalEngine.submitForApproval(cs.Id, null);
                } else {
                    // No approval needed — just persist the evaluation statuses
                    Cost_Sheet__c csUpdate = new Cost_Sheet__c(Id = cs.Id);
                    for (DiscountApprovalEngine.DiscountEvaluation eval : summary.discounts) {
                        csUpdate.put('Discount_' + eval.fieldNumber + '_Status__c', eval.status);
                    }
                    csUpdate.Discount_Approval_Status__c = summary.overallStatus;
                    csUpdate.Highest_Approval_Level__c = summary.highestLevel;
                    update csUpdate;
                }
            } catch (Exception e) {
                System.debug('Discount auto-submit: ' + e.getMessage());
            }
        }

        // ── 2. Build payment lines ──────────────────────────────────
        List<PaymentLineInput> lineInputs =
            (List<PaymentLineInput>) JSON.deserialize(paymentLinesJson, List<PaymentLineInput>.class);

        Decimal agreementValue = dec(calc, 'Agreement_Value__c');

        List<CS_Payment_Line__c> lines = new List<CS_Payment_Line__c>();
        for (PaymentLineInput li : lineInputs) {
            CS_Payment_Line__c pl = new CS_Payment_Line__c();
            pl.Cost_Sheet__c             = cs.Id;
            pl.Name                      = li.milestoneName;
            pl.Milestone_Name__c         = li.milestoneName;
            //pl.Category__c               = li.category;
            pl.Payment_Pct__c            = li.paymentPct;
            pl.Amount__c                 = (li.amount != null)
                                            ? li.amount
                                            : (agreementValue * li.paymentPct / 100);
            pl.Sequence__c               = li.sequence;
            pl.Due_Date__c               = li.dueDate;
            pl.Status__c                 = li.status != null ? li.status : 'Planned';
            pl.Construction_Milestone__c = li.constructionMilestoneId;
            lines.add(pl);
        }
        if (!lines.isEmpty()) {
            insert lines;
        }

        // Unit blocking is handled by CostSheetTrigger (after insert)

        return cs.Id;
    }

    // ── Helpers ────────────────────────────────────────────────────
    private static Decimal safe(Decimal v) { return v == null ? 0 : v; }

    private static Decimal dec(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v == null) return 0;
        if (v instanceof Decimal) return (Decimal) v;
        return Decimal.valueOf(String.valueOf(v));
    }

    /**
     * @description Wrapper for payment line input from LWC.
     */
    public class PaymentLineInput {
        public String  milestoneName;
        public String  category;
        public Decimal paymentPct;
        public Decimal amount;
        public Integer sequence;
        public Date    dueDate;
        public String  status;
        public String  constructionMilestoneId;
    }

    /**
     * @description Get cost sheet field configuration from custom metadata.
     *              Controls which fields are visible, editable, and required
     *              in the Cost Sheet creation form.
     */
    @AuraEnabled(cacheable=true)
    public static List<Cost_Sheet_Field_Config__mdt> getCostSheetFieldConfig() {
        return [
            SELECT Field_API_Name__c, Field_Label__c, Field_Type__c, Section__c,
                   Display_Order__c, Is_Visible__c, Is_Editable__c, Is_Required__c,
                   Default_Value__c
            FROM Cost_Sheet_Field_Config__mdt
            WHERE Is_Visible__c = true
            ORDER BY Section__c ASC, Display_Order__c ASC
        ];
    }
}