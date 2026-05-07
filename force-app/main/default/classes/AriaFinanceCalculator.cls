/**
 * @description Pure-math financial calculators for Aria.
 *
 * Three tools:
 *   1. EMI calculator — standard reducing-balance loan formula
 *   2. Loan eligibility — max loan from monthly income (FOIR 50%)
 *   3. Cost breakdown — itemised unit pricing from Unit__c fields
 *
 * No external callouts, no DML. 100% deterministic.
 */
public with sharing class AriaFinanceCalculator {

    // ════════════════════════════════════════════════════════════
    // EMI
    // ════════════════════════════════════════════════════════════

    /**
     * @description Standard reducing-balance EMI formula:
     *              EMI = P × r × (1+r)^n / ((1+r)^n - 1)
     *              where r = annual rate / 12 / 100
     */
    public static Map<String, Object> calculateEmi(
        Decimal principal, Decimal annualRatePct, Integer tenureMonths
    ) {
        if (principal == null || principal <= 0) {
            return error('principal must be > 0');
        }
        if (annualRatePct == null || annualRatePct <= 0) {
            return error('annual_rate_pct must be > 0');
        }
        if (tenureMonths == null || tenureMonths <= 0) {
            return error('tenure_months must be > 0');
        }

        Double p = principal.doubleValue();
        Double r = annualRatePct.doubleValue() / 12.0 / 100.0;
        Double n = (Double) tenureMonths;

        Double powRn = Math.pow(1 + r, n);
        Double emi = p * r * powRn / (powRn - 1);
        Double totalPayable = emi * n;
        Double totalInterest = totalPayable - p;

        return new Map<String, Object>{
            'monthly_emi'    => roundTwo(emi),
            'total_interest' => roundTwo(totalInterest),
            'total_payable'  => roundTwo(totalPayable),
            'principal'      => principal,
            'annual_rate_pct'=> annualRatePct,
            'tenure_months'  => tenureMonths,
            'tenure_years'   => Decimal.valueOf(tenureMonths).divide(12, 1)
        };
    }

    // ════════════════════════════════════════════════════════════
    // LOAN ELIGIBILITY
    // ════════════════════════════════════════════════════════════

    /**
     * @description Max home loan amount given income, existing EMIs, tenure
     *              and interest rate. Uses FOIR (Fixed Obligation to Income
     *              Ratio) cap of 50 % — standard Indian banking norm.
     *
     *              maxEmi = monthlyIncome × 0.5 - existingEmi
     *              maxLoan = maxEmi × ((1+r)^n - 1) / (r × (1+r)^n)
     */
    public static Map<String, Object> calculateLoanEligibility(
        Decimal monthlyIncome, Decimal existingEmi,
        Decimal annualRatePct, Integer tenureMonths
    ) {
        if (monthlyIncome == null || monthlyIncome <= 0) {
            return error('monthly_income must be > 0');
        }
        Decimal safeExisting = existingEmi != null ? existingEmi : 0;
        Decimal maxEmi = monthlyIncome * 0.5 - safeExisting;
        if (maxEmi <= 0) {
            return new Map<String, Object>{
                'eligible_amount' => 0,
                'max_emi'         => 0,
                'reason'          => 'Existing EMIs consume the full FOIR cap of 50%'
            };
        }

        Double r = (annualRatePct != null ? annualRatePct.doubleValue() : 8.5) / 12.0 / 100.0;
        Double n = tenureMonths != null ? (Double) tenureMonths : 240.0; // default 20y
        Double powRn = Math.pow(1 + r, n);
        Double maxLoan = maxEmi.doubleValue() * (powRn - 1) / (r * powRn);

        return new Map<String, Object>{
            'eligible_amount'  => roundTwo(maxLoan),
            'max_emi'          => roundTwo(maxEmi.doubleValue()),
            'monthly_income'   => monthlyIncome,
            'existing_emi'     => safeExisting,
            'foir_pct'         => 50,
            'annual_rate_pct'  => annualRatePct != null ? annualRatePct : 8.5,
            'tenure_months'    => tenureMonths != null ? tenureMonths : 240
        };
    }

    // ════════════════════════════════════════════════════════════
    // COST BREAKDOWN (from Unit__c fields)
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> getCostBreakdown(Id unitId) {
        if (unitId == null) {
            return error('unit_id is required');
        }
        List<Unit__c> rows = [
            SELECT Id, Name, Unit_Number__c, BHK_Type__c,
                   Carpet_Area__c, Super_Builtup_Area__c, Base_Rate_Sqft__c,
                   Base_Price__c, Floor_Rise_Sqft__c, PLC_Charges__c,
                   Amenity_Charges__c, Infra_Charges__c, Doc_Charges__c,
                   Move_In_Charges__c, Car_Parking_Charges__c,
                   Maintenance_Sqft_Month__c, Maintenance_Months__c,
                   GST_Percentage__c, Stamp_Duty_Pct__c, Registration_Pct__c,
                   Project__r.Name
            FROM Unit__c
            WHERE Id = :unitId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return error('Unit not found');
        }

        Unit__c u = rows[0];
        Decimal base      = safe(u.Base_Price__c);
        Decimal floorRise = safe(u.Floor_Rise_Sqft__c) * safe(u.Super_Builtup_Area__c);
        Decimal plc       = safe(u.PLC_Charges__c);
        Decimal amenity   = safe(u.Amenity_Charges__c);
        Decimal infra     = safe(u.Infra_Charges__c);
        Decimal doc       = safe(u.Doc_Charges__c);
        Decimal moveIn    = safe(u.Move_In_Charges__c);
        Decimal parking   = safe(u.Car_Parking_Charges__c);
        Decimal maintenance = safe(u.Maintenance_Sqft_Month__c) * safe(u.Super_Builtup_Area__c) * safe(u.Maintenance_Months__c);

        Decimal subtotal  = base + floorRise + plc + amenity + infra + doc + moveIn + parking + maintenance;
        Decimal gst       = subtotal * safe(u.GST_Percentage__c) / 100;
        Decimal stampDuty = subtotal * safe(u.Stamp_Duty_Pct__c) / 100;
        Decimal regn      = subtotal * safe(u.Registration_Pct__c) / 100;
        Decimal grandTotal = subtotal + gst + stampDuty + regn;

        return new Map<String, Object>{
            'unit_id'         => u.Id,
            'unit_number'     => u.Unit_Number__c,
            'bhk'             => u.BHK_Type__c,
            'project'         => u.Project__r != null ? u.Project__r.Name : null,
            'carpet_area'     => u.Carpet_Area__c,
            'saleable_area'   => u.Super_Builtup_Area__c,
            'base_price'      => base,
            'floor_rise'      => floorRise,
            'plc_charges'     => plc,
            'amenity_charges' => amenity,
            'infra_charges'   => infra,
            'doc_charges'     => doc,
            'move_in_charges' => moveIn,
            'parking_charges' => parking,
            'maintenance'     => maintenance,
            'subtotal'        => subtotal,
            'gst_pct'         => u.GST_Percentage__c,
            'gst_amount'      => gst,
            'stamp_duty_pct'  => u.Stamp_Duty_Pct__c,
            'stamp_duty'      => stampDuty,
            'registration_pct'=> u.Registration_Pct__c,
            'registration'    => regn,
            'grand_total'     => grandTotal
        };
    }

    // ════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════

    private static Decimal safe(Decimal v) { return v != null ? v : 0; }

    private static Decimal roundTwo(Double v) {
        return Decimal.valueOf(v).setScale(2, RoundingMode.HALF_UP);
    }

    private static Map<String, Object> error(String msg) {
        return new Map<String, Object>{ 'error' => msg };
    }
}