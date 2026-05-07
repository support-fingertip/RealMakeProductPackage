/**
 * @description Cost Sheet Calculation Service
 * Loads the active Project_Calculation_Template__c + Calculation_Step__c
 * for the project and runs those formulas in-memory so the LWC can show
 * live-calculated values BEFORE the record is saved.
 *
 * Uses FormulaCalculationService.evaluateFormulaPublic() for arithmetic
 * evaluation — does NOT modify FormulaCalculationService.
 *
 * Falls back to hardcoded defaults only when no template is configured.
 */
public with sharing class CostSheetCalculationService {

    private static final String TARGET_OBJECT = 'Cost_Sheet__c';
    private static final String SOURCE_OBJECT = 'Unit__c';

    /**
     * @description Build a full cost-sheet calculation from a Unit record.
     *              If a Project_Calculation_Template exists for the unit's
     *              project, its Calculation_Steps drive the output.
     *              Otherwise falls back to hardcoded formulas.
     */
    public static Map<String, Object> calculateFromUnit(Unit__c unit) {
        if (unit == null) {
            throw new CostSheetException('Unit is required for calculation.');
        }

        // 1. Seed the Cost_Sheet__c fields from the Unit
        Map<String, Object> result = seedFromUnit(unit);

        // 2. Try to find a template for this project
        Id projectId = unit.Project__c;
        Project_Calculation_Template__c template = findTemplate(projectId);

        if (template != null && !template.Calculation_Steps__r.isEmpty()) {
            // 3a. Run template-driven steps
            runTemplateSteps(template, result, unit);
        }

        // 3b. Always compute derived fields.
        //     Cost_Sheet__c fields (Agreement_Value__c, Net_Payable__c, etc.)
        //     are regular Currency fields populated by Apex calculations.
        //     This ensures both pre-save preview and saved records are consistent.
        ensureDerivedFields(result);

        return result;
    }

    /**
     * @description Recalculate after discount change (re-runs the full pipeline).
     */
    public static Map<String, Object> recalculateWithTemplate(Unit__c unit) {
        return calculateFromUnit(unit);
    }

    /**
     * @description Apply per-field discounts to the calc map.
     *              Each discount reduces the value of its tagged field.
     *              Then re-derives all formula fields.
     * @param calc    The in-memory cost sheet calculation map
     * @param discounts  List of maps with 'unitFieldAPI' and 'value' keys
     */
    public static void applyPerFieldDiscounts(Map<String, Object> calc, List<Map<String, Object>> discounts) {
        if (discounts == null || discounts.isEmpty()) return;
        Decimal area = dec(calc, 'Super_Builtup_Area__c');

        for (Integer i = 0; i < discounts.size(); i++) {
            Map<String, Object> d = discounts[i];
            String fieldAPI = (String) d.get('unitFieldAPI');
            Decimal discVal = d.get('value') != null ? Decimal.valueOf(String.valueOf(d.get('value'))) : 0;
            Integer fieldNum = d.get('fieldNumber') != null
                ? Integer.valueOf(String.valueOf(d.get('fieldNumber')))
                : (i + 1);

            if (discVal > 0) {
                // Store the raw discount amount
                calc.put('Discount_' + fieldNum + '__c', discVal);

                // Compute the discounted value (tagged field value - discount)
                if (String.isNotBlank(fieldAPI) && calc.containsKey(fieldAPI)) {
                    Decimal originalVal = dec(calc, fieldAPI);
                    if (!calc.containsKey('Discount_' + fieldNum + '_Value__c')) {
                        calc.put('Discount_' + fieldNum + '_Value__c', originalVal - discVal);
                    }
                }
            }

            // Do NOT modify the original tagged field value.
            // The discount is already accounted for via Total_Discount__c
            // in ensureDerivedFields(), so modifying the original field would
            // double-count the discount.
        }
        ensureDerivedFields(calc);
    }

    /**
     * @description Public wrapper to re-derive formula fields after external modification.
     */
    public static void ensureDerivedFieldsPublic(Map<String, Object> v) {
        ensureDerivedFields(v);
    }

    /**
     * @description Run FormulaCalculationService on a saved Cost_Sheet__c
     *              so the template steps update the persisted record.
     */
    public static void runPostSaveCalculation(Id costSheetId) {
        FormulaCalculationService.FlowInput input = new FormulaCalculationService.FlowInput();
        input.targetRecordId = costSheetId;
        List<FormulaCalculationService.FlowOutput> outputs =
            FormulaCalculationService.calculateFromFlow(
                new List<FormulaCalculationService.FlowInput>{ input }
            );
        if (!outputs.isEmpty() && !outputs[0].success) {
            System.debug('Post-save calculation note: ' + outputs[0].errorMessage);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  TEMPLATE LOOKUP
    // ═══════════════════════════════════════════════════════════════

    private static Project_Calculation_Template__c findTemplate(Id projectId) {
        if (projectId == null) return null;

        List<Project_Calculation_Template__c> templates = [
            SELECT Id, Source_Object_API_Name__c, Target_Object_API_Name__c,
                   Source_Lookup_Field__c, Project__c,
                   (SELECT Id, Step_Number__c, Variable_Name__c,
                           Formula_Expression__c, Store_In_Field__c, Is_Active__c
                    FROM Calculation_Steps__r
                    WHERE Is_Active__c = true
                    ORDER BY Step_Number__c ASC)
            FROM Project_Calculation_Template__c
            WHERE Project__c = :projectId
              AND Target_Object_API_Name__c = :TARGET_OBJECT
              AND Is_Active__c = true
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0];
    }

    // ═══════════════════════════════════════════════════════════════
    //  TEMPLATE STEP EXECUTION (mirrors FormulaCalculationService)
    // ═══════════════════════════════════════════════════════════════

    private static void runTemplateSteps(
        Project_Calculation_Template__c template,
        Map<String, Object> csValues,
        Unit__c unit
    ) {
        // Build field maps for both objects
        Map<String, Schema.SObjectField> targetFields =
            Schema.SObjectType.Cost_Sheet__c.fields.getMap();
        Map<String, Schema.SObjectField> sourceFields =
            Schema.SObjectType.Unit__c.fields.getMap();

        // Variable map for step-to-step chaining
        Map<String, Decimal> variableMap = new Map<String, Decimal>();

        for (Calculation_Step__c step : template.Calculation_Steps__r) {
            String formula = step.Formula_Expression__c;
            if (String.isBlank(formula)) continue;

            // Replace field references with actual values
            formula = replaceFields(formula, csValues, unit, targetFields, sourceFields);

            // Replace variables from previous steps
            for (String varName : variableMap.keySet()) {
                if (formula.contains(varName)) {
                    formula = formula.replaceAll(
                        '\\b' + Pattern.quote(varName) + '\\b',
                        String.valueOf(variableMap.get(varName))
                    );
                }
            }

            // Evaluate the formula using FormulaCalculationService's public evaluator
            Decimal result;
            try {
                result = FormulaCalculationService.evaluateFormulaPublic(formula);
            } catch (Exception e) {
                System.debug('Step ' + step.Step_Number__c + ' eval error: ' + e.getMessage());
                continue;
            }

            // Store in variable map
            if (String.isNotBlank(step.Variable_Name__c)) {
                variableMap.put(step.Variable_Name__c, result);
            }

            // Store in cost sheet values map
            if (String.isNotBlank(step.Store_In_Field__c)) {
                csValues.put(step.Store_In_Field__c, result);
            }
        }
    }

    /**
     * Replace __c field references in a formula with their numeric values.
     * Priority: Cost Sheet (target) values first, then Unit (source) fields.
     */
    private static String replaceFields(
        String formula,
        Map<String, Object> csValues,
        Unit__c unit,
        Map<String, Schema.SObjectField> targetFields,
        Map<String, Schema.SObjectField> sourceFields
    ) {
        Pattern fieldPattern = Pattern.compile('\\b([A-Za-z][A-Za-z0-9_]*)__c\\b');
        Matcher matcher = fieldPattern.matcher(formula);

        Map<String, String> replacements = new Map<String, String>();

        while (matcher.find()) {
            String fieldName = matcher.group(1) + '__c';
            if (replacements.containsKey(fieldName)) continue;

            Object value = null;

            // Check target (cost sheet in-memory values) first
            if (csValues.containsKey(fieldName)) {
                value = csValues.get(fieldName);
            }

            // If null, check source (unit record)
            if (value == null && sourceFields.containsKey(fieldName.toLowerCase())) {
                try {
                    value = unit.get(fieldName);
                } catch (Exception e) {
                    // Field not queried — treat as 0
                }
            }

            if (value != null && (value instanceof Decimal || value instanceof Double || value instanceof Integer)) {
                replacements.put(fieldName, String.valueOf(value));
            } else {
                replacements.put(fieldName, '0');
            }
        }

        for (String fieldName : replacements.keySet()) {
            formula = formula.replaceAll('\\b' + fieldName + '\\b', replacements.get(fieldName));
        }

        return formula;
    }

    // ═══════════════════════════════════════════════════════════════
    //  SEED: Copy Unit values → Cost Sheet field map
    // ═══════════════════════════════════════════════════════════════

    private static Map<String, Object> seedFromUnit(Unit__c unit) {
        Map<String, Object> v = new Map<String, Object>();

        // Areas — field names now match 1:1 between Unit and Cost Sheet
        v.put('Super_Builtup_Area__c', safe(unit.Super_Builtup_Area__c));
        v.put('Super_Builtup_Area__c',      safe(unit.Super_Builtup_Area__c));
        v.put('Carpet_Area__c',        safe(unit.Carpet_Area__c));
        v.put('UDS__c',                safe(unit.UDS__c));

        // Rates
        v.put('Base_Rate_Sqft__c', safe(unit.Base_Rate_Sqft__c));

        // Per-sqft charges
        v.put('Floor_Rise_Sqft__c',  safe(unit.Floor_Rise_Sqft__c));
        v.put('Corpus_Fund_Sqft__c', safe(unit.Corpus_Fund_Sqft__c));

        // Maintenance
        v.put('Maintenance_Sqft_Month__c', safe(unit.Maintenance_Sqft_Month__c));
        v.put('Maintenance_Months__c',     safe(unit.Maintenance_Months__c));

        // Flat charges
        v.put('PLC_Charges__c',     safe(unit.PLC_Charges__c));
        v.put('Amenity_Charges__c', safe(unit.Amenity_Charges__c));
        v.put('Infra_Charges__c',   safe(unit.Infra_Charges__c));
        v.put('Doc_Charges__c',     safe(unit.Doc_Charges__c));
        v.put('Move_In_Charges__c', safe(unit.Move_In_Charges__c));

        // Tax percentages — field names now match 1:1
        v.put('GST_Percentage__c',   safe(unit.GST_Percentage__c));
        v.put('Registration_Pct__c', safe(unit.Registration_Pct__c));
        v.put('Stamp_Duty_Pct__c',   safe(unit.Stamp_Duty_Pct__c));

        return v;
    }

    // ═══════════════════════════════════════════════════════════════
    //  DERIVED FIELD CALCULATION
    //  Computes derived Cost_Sheet__c fields (Agreement_Value__c,
    //  Net_Payable__c, GST_Amount__c, etc.) from their input fields.
    //  These are regular Currency fields populated by Apex — not
    //  Salesforce formula fields.  Values are computed both for
    //  pre-save preview and persisted on save via CostSheetController.
    //
    //  Base_Price__c is an editable field that template steps may
    //  legitimately set, so it uses putIfAbsent.
    // ═══════════════════════════════════════════════════════════════

    private static void ensureDerivedFields(Map<String, Object> v) {
        Decimal superBuiltup = dec(v, 'Super_Builtup_Area__c');

        // Base Price — editable field, keep template value if already set
        if (!v.containsKey('Base_Price__c')) {
            v.put('Base_Price__c', dec(v, 'Base_Rate_Sqft__c') * superBuiltup);
        }
        Decimal basePrice = dec(v, 'Base_Price__c');

        // ── Derived fields — always recompute from inputs ─────────

        Decimal floorRiseTotal = dec(v, 'Floor_Rise_Sqft__c') * superBuiltup;
        v.put('Floor_Rise_Total__c', floorRiseTotal);

        Decimal corpusTotal = dec(v, 'Corpus_Fund_Sqft__c') * superBuiltup;
        v.put('Corpus_Total__c', corpusTotal);

        Decimal maintTotal = dec(v, 'Maintenance_Sqft_Month__c')
                             * superBuiltup
                             * dec(v, 'Maintenance_Months__c');
        v.put('Maintenance_Total__c', maintTotal);

        // Total_Discount__c = sum of Discount_1 through Discount_6
        Decimal totalDiscount = 0;
        for (Integer i = 1; i <= 6; i++) {
            totalDiscount += dec(v, 'Discount_' + i + '__c');
        }
        v.put('Total_Discount__c', totalDiscount);

        // Agreement_Value__c (sum of all charges minus discount)
        Decimal agreementValue =
            basePrice
            + dec(v, 'PLC_Charges__c')
            + floorRiseTotal
            + dec(v, 'Amenity_Charges__c')
            + dec(v, 'Infra_Charges__c')
            + dec(v, 'Doc_Charges__c')
            + maintTotal
            + corpusTotal
            + dec(v, 'Move_In_Charges__c')
            - totalDiscount;
        v.put('Agreement_Value__c', agreementValue);

        // ── Tax calculations ──────────────────────────────────────
        Decimal gstPct   = dec(v, 'GST_Percentage__c');
        Decimal regPct   = dec(v, 'Registration_Pct__c');
        Decimal stampPct = dec(v, 'Stamp_Duty_Pct__c');

        // GST base = Base + PLC + FloorRise + Amenity + Infra – Discount
        Decimal gstBase = basePrice
                          + dec(v, 'PLC_Charges__c')
                          + floorRiseTotal
                          + dec(v, 'Amenity_Charges__c')
                          + dec(v, 'Infra_Charges__c')
                          - totalDiscount;
        Decimal gstAmount = gstBase * (gstPct / 100);
        v.put('GST_Amount__c', gstAmount);

        // Duty base = Base + PLC + FloorRise – Discount
        Decimal dutyBase = basePrice
                           + dec(v, 'PLC_Charges__c')
                           + floorRiseTotal
                           - totalDiscount;
        Decimal stampAmount = dutyBase * (stampPct / 100);
        Decimal regAmount   = dutyBase * (regPct / 100);
        v.put('Stamp_Duty_Amount__c', stampAmount);
        v.put('Registration_Amount__c', regAmount);

        // Net_Payable__c = Agreement + GST + Stamp Duty + Registration
        v.put('Net_Payable__c', agreementValue + gstAmount + stampAmount + regAmount);
    }

    // ── Helpers ────────────────────────────────────────────────────
    private static Decimal safe(Decimal val) {
        return val == null ? 0 : val;
    }

    private static Decimal dec(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v == null) return 0;
        if (v instanceof Decimal) return (Decimal) v;
        return Decimal.valueOf(String.valueOf(v));
    }

    public class CostSheetException extends Exception {}
}