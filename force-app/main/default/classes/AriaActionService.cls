/**
 * @description Action dispatcher for Aria. One public method per Gemini
 *              function/tool the model can call. Each method:
 *               1. Validates inbound args (originating from the LLM),
 *               2. Delegates to an existing service (no reimplementation),
 *               3. Returns a flat, JSON-serialisable result that Aria can
 *                  feed back to the model as a functionResponse.
 *
 * Keeping this layer thin is deliberate — business rules stay in the existing
 * services (LeadDeduplicationService, SiteVisitCreationService, etc.) so the
 * bot benefits automatically from future fixes there.
 */
public with sharing class AriaActionService {

    public class AriaActionException extends Exception {}

    // ════════════════════════════════════════════════════════════
    // ROUTER
    // ════════════════════════════════════════════════════════════

    /**
     * @description Single entry point — the orchestrator hands (toolName, args)
     *              straight from Gemini's functionCall. Unknown tools throw.
     */
    public static Map<String, Object> dispatch(String toolName, Map<String, Object> args) {
        if (String.isBlank(toolName)) {
            throw new AriaActionException('Tool name is required.');
        }
        Map<String, Object> safeArgs = args == null ? new Map<String, Object>() : args;

        switch on toolName {
            // Search / lookup
            when 'search_everything'        { return searchEverything(safeArgs); }
            when 'find_lead'                { return findLead(safeArgs); }
            when 'search_projects'          { return searchProjects(safeArgs); }
            when 'get_project_details'      { return getProjectDetails(safeArgs); }
            when 'check_unit_availability'  { return checkUnitAvailability(safeArgs); }
            when 'get_lead_history'         { return getLeadHistory(safeArgs); }
            when 'get_next_best_action'     { return getNextBestAction(safeArgs); }
            when 'get_hot_leads'            { return getHotLeads(safeArgs); }
            // Write actions
            when 'create_lead'              { return createLead(safeArgs); }
            when 'schedule_site_visit'      { return scheduleSiteVisit(safeArgs); }
            when 'generate_cost_sheet'      { return generateCostSheet(safeArgs); }
            when 'schedule_followup'        { return scheduleFollowup(safeArgs); }
            // Booking flow
            when 'get_booking_status'       { return getBookingStatus(safeArgs); }
            when 'initiate_booking'         { return initiateBooking(safeArgs); }
            when 'get_payment_schedule'     { return getPaymentSchedule(safeArgs); }
            when 'block_unit'               { return blockUnit(safeArgs); }
            // Finance calculators
            when 'calculate_emi'            { return calculateEmi(safeArgs); }
            when 'calculate_loan_eligibility' { return calculateLoanEligibility(safeArgs); }
            when 'get_cost_breakdown'       { return getCostBreakdown(safeArgs); }
            // Agent metrics
            when 'my_performance'           { return myPerformance(safeArgs); }
            when 'get_overdue_followups'    { return getOverdueFollowups(safeArgs); }
            when 'get_stale_leads'          { return getStaleLeads(safeArgs); }
            when 'explain_lead_score'       { return explainLeadScore(safeArgs); }
            // Org wrappers
            when 'get_funnel_analysis'      { return getFunnelAnalysis(safeArgs); }
            when 'cancel_booking'           { return cancelBooking(safeArgs); }
            when 'raise_complaint'          { return raiseComplaint(safeArgs); }
            when 'get_demand_aging'         { return getDemandAging(safeArgs); }
            when 'get_snag_aging'           { return getSnagAging(safeArgs); }
            when 'preview_lead_assignment'  { return previewLeadAssignment(safeArgs); }
            when else {
                throw new AriaActionException('Unknown Aria tool: ' + toolName);
            }
        }
    }

    // ════════════════════════════════════════════════════════════
    // UNIVERSAL SEARCH / FIND
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> searchEverything(Map<String, Object> args) {
        String query = asString(args.get('query'));
        if (String.isBlank(query)) {
            throw new AriaActionException('query is required.');
        }
        List<Map<String, Object>> results = AriaKnowledgeService.universalSearch(query);
        return new Map<String, Object>{
            'query'   => query,
            'count'   => results.size(),
            'results' => results
        };
    }

    public static Map<String, Object> findLead(Map<String, Object> args) {
        String query = asString(args.get('query'));
        if (String.isBlank(query)) {
            throw new AriaActionException('query is required.');
        }
        List<Map<String, Object>> leads = AriaKnowledgeService.findLead(query);
        return new Map<String, Object>{
            'query' => query,
            'count' => leads.size(),
            'leads' => leads
        };
    }

    // ════════════════════════════════════════════════════════════
    // BOOKING FLOW
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> getBookingStatus(Map<String, Object> args) {
        Id leadId = (Id) args.get('lead_id');
        if (leadId == null) {
            throw new AriaActionException('lead_id is required.');
        }
        return AriaKnowledgeService.getBookingReadiness(leadId);
    }

    /**
     * @description Create a Booking__c from an accepted cost sheet. Thin wrapper
     *              around BookingService.createBooking — no business logic here.
     *              Caller must provide booking_amount (>= project's Min_Booking_Amount__c)
     *              and payment_mode. Cost sheet must be in "Accepted by Customer".
     */
    public static Map<String, Object> initiateBooking(Map<String, Object> args) {
        Id costSheetId = (Id) args.get('cost_sheet_id');
        if (costSheetId == null) {
            throw new AriaActionException('cost_sheet_id is required.');
        }
        Decimal bookingAmount = toDecimal(args.get('booking_amount'));
        if (bookingAmount == null || bookingAmount <= 0) {
            throw new AriaActionException('booking_amount is required and must be > 0.');
        }
        String paymentMode = asString(args.get('payment_mode'));
        if (String.isBlank(paymentMode)) {
            paymentMode = 'Online';
        }
        String transactionRef = asString(args.get('transaction_ref'));

        // Applicant details default to the lead's own contact info — BookingService
        // will fill them in from the cost sheet's lead reference.
        Map<String, Object> applicantDetails = new Map<String, Object>();

        try {
            Id bookingId = BookingService.createBooking(
                costSheetId, applicantDetails, bookingAmount,
                paymentMode, transactionRef, new List<Co_Applicants__c>()
            );
            return new Map<String, Object>{
                'booking_id'    => bookingId,
                'cost_sheet_id' => costSheetId,
                'booking_amount'=> bookingAmount,
                'payment_mode'  => paymentMode,
                'message'       => 'Booking created in Draft status. Unit is now marked Booked, cost sheet marked Converted, lead status set to Booked.'
            };
        } catch (Exception ex) {
            throw new AriaActionException(ex.getMessage());
        }
    }

    public static Map<String, Object> getPaymentSchedule(Map<String, Object> args) {
        Id bookingId = (Id) args.get('booking_id');
        if (bookingId == null) {
            throw new AriaActionException('booking_id is required.');
        }
        List<Map<String, Object>> rows = AriaKnowledgeService.getPaymentSchedule(bookingId);
        return new Map<String, Object>{
            'booking_id' => bookingId,
            'count'      => rows.size(),
            'schedule'   => rows
        };
    }

    /**
     * @description Block a unit for a lead via the existing UnitBlockingService.
     *              Defaults to 7-day block. `reason` is required per service contract.
     */
    public static Map<String, Object> blockUnit(Map<String, Object> args) {
        Id leadId = (Id) args.get('lead_id');
        Id unitId = (Id) args.get('unit_id');
        if (leadId == null || unitId == null) {
            throw new AriaActionException('lead_id and unit_id are required.');
        }
        Integer blockDays = args.get('block_days') != null
            ? Integer.valueOf(args.get('block_days'))
            : 7;
        String reason = asString(args.get('reason'));
        if (String.isBlank(reason)) {
            reason = 'Blocked via Aria — customer considering booking';
        }

        try {
            UnitBlockingService.BlockResult r = UnitBlockingService.blockUnits(
                new List<Id>{ unitId }, blockDays, reason, false, UserInfo.getUserId(), leadId
            );
            return new Map<String, Object>{
                'unit_id'    => unitId,
                'lead_id'    => leadId,
                'block_days' => blockDays,
                'reason'     => reason,
                'success'    => r != null && r.successCount != null && r.successCount > 0,
                'message'    => 'Unit blocked for ' + blockDays + ' day(s).'
            };
        } catch (Exception ex) {
            throw new AriaActionException(ex.getMessage());
        }
    }

    // ════════════════════════════════════════════════════════════
    // READ ACTIONS (pass-through to AriaKnowledgeService)
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> searchProjects(Map<String, Object> args) {
        // All filters optional — digest returns active projects only
        return new Map<String, Object>{
            'projects' => AriaKnowledgeService.getProjectsDigest()
        };
    }

    public static Map<String, Object> getProjectDetails(Map<String, Object> args) {
        Id projectId = resolveProjectId(args);
        Map<String, Object> details = AriaKnowledgeService.getProjectDetails(projectId);
        return details == null
            ? new Map<String, Object>{ 'error' => 'Project not found' }
            : details;
    }

    public static Map<String, Object> checkUnitAvailability(Map<String, Object> args) {
        Id projectId = resolveProjectId(args);
        String bhkType = (String) args.get('bhk_type');
        Decimal budgetMin = toDecimal(args.get('budget_min'));
        Decimal budgetMax = toDecimal(args.get('budget_max'));

        List<Map<String, Object>> units = AriaKnowledgeService.getUnitAvailability(
            projectId, bhkType, budgetMin, budgetMax
        );
        return new Map<String, Object>{
            'count' => units.size(),
            'units' => units
        };
    }

    public static Map<String, Object> getLeadHistory(Map<String, Object> args) {
        Id leadId = (Id) args.get('lead_id');
        if (leadId == null) {
            throw new AriaActionException('lead_id is required.');
        }
        Map<String, Object> ctx = AriaKnowledgeService.getLeadContext(leadId);
        return ctx == null
            ? new Map<String, Object>{ 'error' => 'Lead not found' }
            : ctx;
    }

    public static Map<String, Object> getNextBestAction(Map<String, Object> args) {
        Id leadId = (Id) args.get('lead_id');
        if (leadId == null) {
            throw new AriaActionException('lead_id is required.');
        }
        return AriaKnowledgeService.getNextBestAction(leadId);
    }

    /**
     * @description Returns the current user's top N leads ranked by how close
     *              they are to booking — so Aria can tell an exec which leads
     *              to push to booking fast.
     */
    public static Map<String, Object> getHotLeads(Map<String, Object> args) {
        Integer topN = args.get('top_n') != null ? Integer.valueOf(args.get('top_n')) : 5;
        return new Map<String, Object>{
            'leads' => AriaKnowledgeService.getHotLeads(topN)
        };
    }

    // ════════════════════════════════════════════════════════════
    // WRITE ACTIONS
    // ════════════════════════════════════════════════════════════

    /**
     * @description Creates a lead via LeadDeduplicationService (full dedup
     *              matrix, round-robin, CP credit). If the required
     *              LEAD_CREATION integration config doesn't exist yet, this
     *              method auto-seeds it so the Integration Mapping Designer
     *              picks it up — admins can then customise mappings via the
     *              Designer UI without touching code.
     */
    public static Map<String, Object> createLead(Map<String, Object> args) {
        String firstName    = asString(args.get('first_name'));
        String lastName     = asString(args.get('last_name'));
        String mobile       = asString(args.get('mobile'));
        String email        = asString(args.get('email'));
        String projectCode  = asString(args.get('project_code'));
        String bhk          = asString(args.get('bhk_preference'));
        String budget       = asString(args.get('budget_range'));
        String purpose      = asString(args.get('purchase_purpose'));
        String timeline     = asString(args.get('purchase_timeline'));
        String source       = asString(args.get('source'));
        String subSource    = asString(args.get('sub_source'));
        String lang         = asString(args.get('preferred_language'));

        if (String.isBlank(mobile)) {
            throw new AriaActionException('mobile is required to create a lead.');
        }
        if (String.isBlank(projectCode)) {
            throw new AriaActionException('project_code is required to create a lead.');
        }
        if (String.isBlank(lastName) && String.isBlank(firstName)) {
            throw new AriaActionException('At least a first or last name is required.');
        }

        // Auto-seed integration configs + CP module config if missing
        ensureIntegrationConfigs();
        ensureCPModuleConfig();

        Map<String, String> payload = new Map<String, String>{
            'first_name'         => firstName,
            'last_name'          => String.isNotBlank(lastName) ? lastName : firstName,
            'primary_mobile'     => mobile,
            'primary_email'      => email,
            'project_code'       => projectCode,
            'bhk_type'           => bhk,
            'budget_range'       => budget,
            'purchase_purpose'   => purpose,
            'purchase_timeline'  => timeline,
            'source'             => String.isNotBlank(source) ? source : 'Aria AI',
            'sub_source'         => String.isNotBlank(subSource) ? subSource : 'Aria Chat',
            'preferred_language' => lang
        };

        LeadDeduplicationService.LeadResult result = LeadDeduplicationService.processIncomingLead(payload);
        if (result != null && 'ERROR'.equalsIgnoreCase(result.action)) {
            throw new AriaActionException(
                String.isNotBlank(result.message) ? result.message : 'Lead creation failed.'
            );
        }
        return new Map<String, Object>{
            'lead_id' => result.leadId,
            'action'  => result.action,
            'message' => result.message
        };
    }

    /**
     * @description Seeds the integration mapping configs required by
     *              LeadDeduplicationService (LEAD_CREATION + ENQUIRY_SOURCE_CREATION).
     *              Admins can customise mappings via the Integration Mapping
     *              Designer after first run.
     */
    private static void ensureIntegrationConfigs() {
        seedConfig(
            'LEAD_CREATION',
            'Lead__c',
            new String[][]{
                new String[]{ 'first_name',         'First_Name__c',        'Text' },
                new String[]{ 'last_name',          'Last_Name__c',         'Text' },
                new String[]{ 'primary_mobile',     'Primary_Mobile__c',    'Text' },
                new String[]{ 'primary_email',      'Primary_Email__c',     'Text' },
                new String[]{ 'bhk_type',           'BHK_Type__c',          'Text' },
                new String[]{ 'budget_range',       'Budget_Range__c',      'Text' },
                new String[]{ 'purchase_purpose',   'Purchase_Purpose__c',  'Text' },
                new String[]{ 'purchase_timeline',  'Purchase_Timeline__c', 'Text' },
                new String[]{ 'preferred_language', 'Preferred_Language__c','Text' }
            }
        );
        seedConfig(
            'ENQUIRY_SOURCE_CREATION',
            'Enquiry_Source__c',
            new String[][]{
                new String[]{ 'first_name',     'Contact_First_Name__c', 'Text' },
                new String[]{ 'last_name',      'Contact_Last_Name__c',  'Text' },
                new String[]{ 'primary_mobile', 'Contact_Mobile__c',     'Text' },
                new String[]{ 'primary_email',  'Contact_Email__c',      'Text' },
                new String[]{ 'primary_mobile', 'Primary_Mobile__c',     'Text' },
                new String[]{ 'primary_email',  'Primary_Email__c',      'Text' },
                new String[]{ 'source',         'Source__c',             'Text' },
                new String[]{ 'sub_source',     'Sub_Source__c',         'Text' },
                new String[]{ 'enquiry_type',   'Enquiry_Type__c',       'Text' }
            }
        );
    }

    private static void seedConfig(String sourceName, String targetObject, String[][] mappings) {
        if (IntegrationFieldMappingEngine.hasActiveConfig(sourceName)) return;

        Integration_Source_Config__c cfg = new Integration_Source_Config__c();
        cfg.Source_Name__c   = sourceName;
        cfg.Target_Object__c = targetObject;
        cfg.Is_Active__c     = true;
        cfg.Description__c   = 'Auto-created by Aria. Customise via Integration Mapping Designer.';
        insert cfg;

        List<Integration_Field_Rule__c> rules = new List<Integration_Field_Rule__c>();
        Integer seq = 0;
        for (String[] mapping : mappings) {
            seq++;
            Integration_Field_Rule__c r = new Integration_Field_Rule__c();
            r.Integration_Source_Config__c = cfg.Id;
            r.API_Field_Name__c    = mapping[0];
            r.SF_Field_API_Name__c = mapping[1];
            r.Data_Type__c         = mapping[2];
            r.Sequence__c          = seq;
            r.Is_Active__c         = true;
            r.Is_Required__c       = false;
            rules.add(r);
        }
        insert rules;
    }

    /**
     * @description Ensures at least one active CP_Module_Config__c exists. If
     *              none is present, LeadDeduplicationService.processIncomingLead
     *              throws before the lead can be inserted. This seeds conservative
     *              defaults so the chatbot works out-of-the-box.
     */
    private static void ensureCPModuleConfig() {
        List<CP_Module_Config__c> existing = [
            SELECT Id FROM CP_Module_Config__c WHERE Is_Active__c = true LIMIT 1
        ];
        if (!existing.isEmpty()) return;

        CP_Module_Config__c cfg = new CP_Module_Config__c();
        cfg.Is_Active__c               = true;
        cfg.CP_Source_Name__c          = 'Channel Partner';
        cfg.Assignment_Type__c         = 'Pre-Sales';
        cfg.Lead_Default_Status__c     = 'New Enquiry';
        cfg.Lead_Reengaged_Type__c     = 'Re-engaged';
        cfg.Lead_Reopened_Type__c      = 'Re-opened';
        cfg.Lead_Inactive_Statuses__c  = '["Unqualified","Closed Lost","Booked"]';
        cfg.CP_Active_Statuses__c      = '["Active"]';
        cfg.Credit_Active_Status__c    = 'Active';
        cfg.Credit_Expired_Status__c   = 'Expired';
        cfg.Credit_Expiry_Days__c      = 90;
        insert cfg;
    }

    /**
     * @description Delegates to SiteVisitCreationService. Handles same-project
     *              and cross-project routing automatically via that service.
     */
    public static Map<String, Object> scheduleSiteVisit(Map<String, Object> args) {
        Id leadId = (Id) args.get('lead_id');
        if (leadId == null) {
            throw new AriaActionException('lead_id is required.');
        }
        Id projectId = resolveProjectId(args);
        if (projectId == null) {
            // Default to the lead's project if caller didn't specify
            for (Lead__c l : [SELECT Project__c FROM Lead__c WHERE Id = :leadId LIMIT 1]) {
                projectId = l.Project__c;
            }
        }
        if (projectId == null) {
            throw new AriaActionException('Unable to determine project for the site visit.');
        }

        DateTime scheduled = parseDateTime(args.get('scheduled_at'));
        if (scheduled == null) {
            throw new AriaActionException('scheduled_at (ISO datetime) is required.');
        }
        rejectIfPast(scheduled, 'site visit');

        String mode = String.valueOf(args.get('mode'));
        if (String.isBlank(mode) || 'null'.equalsIgnoreCase(mode)) {
            mode = 'On Site';
        }

        SiteVisitCreationService.SiteVisitResult r = SiteVisitCreationService.createSiteVisit(
            leadId, projectId, scheduled, mode, 'Digital (Own)', false
        );

        return new Map<String, Object>{
            'site_visit_id'    => r.siteVisitId,
            'assigned_to_id'   => r.assignedToUserId,
            'assigned_to_name' => r.assignedToName,
            'is_cross_project' => r.isCrossProject,
            'message'          => r.message
        };
    }

    /**
     * @description Delegates to CostSheetController.saveCostSheet — the same
     *              path the existing LWC uses. Discounts arrive as a simple
     *              percentage from the bot; we translate into the discount
     *              payload the service expects.
     */
    public static Map<String, Object> generateCostSheet(Map<String, Object> args) {
        Id leadId = (Id) args.get('lead_id');
        Id unitId = (Id) args.get('unit_id');
        if (leadId == null || unitId == null) {
            throw new AriaActionException('lead_id and unit_id are required.');
        }

        // Resolve the unit's project (Cost Sheet must be project-scoped)
        Id projectId;
        for (Unit__c u : [SELECT Project__c FROM Unit__c WHERE Id = :unitId LIMIT 1]) {
            projectId = u.Project__c;
        }
        if (projectId == null) {
            throw new AriaActionException('Unit not found or has no project.');
        }

        String paymentPlan = asString(args.get('payment_plan_type'));
        if (String.isBlank(paymentPlan)) {
            paymentPlan = 'Standard';
        }

        Decimal discountPct = toDecimal(args.get('discount_percent'));
        String discountsJson = null;
        if (discountPct != null && discountPct > 0) {
            // CostSheet service expects a per-field discount list; "Base_Price__c"
            // is the canonical target in the calculation engine.
            discountsJson = JSON.serialize(new List<Object>{
                new Map<String, Object>{
                    'field' => 'Base_Price__c',
                    'type'  => 'Percentage',
                    'value' => discountPct
                }
            });
        }

        Id costSheetId = CostSheetController.saveCostSheet(
            leadId, unitId, projectId, paymentPlan, null, discountsJson
        );

        return new Map<String, Object>{
            'cost_sheet_id'    => costSheetId,
            'lead_id'          => leadId,
            'unit_id'          => unitId,
            'project_id'       => projectId,
            'payment_plan'     => paymentPlan,
            'discount_percent' => discountPct,
            'message'          => 'Cost sheet created in Draft status.'
        };
    }

    /**
     * @description Creates a Followup__c linked to the lead. Leaves assignment
     *              to the existing FollowupTriggerHandler.
     */
    public static Map<String, Object> scheduleFollowup(Map<String, Object> args) {
        Id leadId = (Id) args.get('lead_id');
        if (leadId == null) {
            throw new AriaActionException('lead_id is required.');
        }

        DateTime due = parseDateTime(args.get('due_date'));
        if (due == null) {
            // Accept plain date as well (YYYY-MM-DD) — treat as 10am that day
            Date d = parseDate(args.get('due_date'));
            if (d != null) {
                due = DateTime.newInstance(d, Time.newInstance(10, 0, 0, 0));
            }
        }
        if (due == null) {
            throw new AriaActionException('due_date is required.');
        }
        rejectIfPast(due, 'follow-up');

        Followup__c f = new Followup__c();
        f.Lead__c    = leadId;
        f.Subject__c = asString(args.get('subject'));
        if (String.isBlank(f.Subject__c)) {
            f.Subject__c = 'Aria-scheduled follow-up';
        }
        f.Notes__c   = asString(args.get('notes'));
        f.Due_Date__c = due;
        f.Status__c  = 'Pending';
        insert f;

        return new Map<String, Object>{
            'followup_id' => f.Id,
            'lead_id'     => leadId,
            'due_date'    => due,
            'message'     => 'Follow-up scheduled.'
        };
    }

    // ════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════

    /**
     * @description Accept either a project Id OR a project code in args and
     *              resolve to an Id.
     */
    // ════════════════════════════════════════════════════════════
    // FINANCE CALCULATORS (Phase 2)
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> calculateEmi(Map<String, Object> args) {
        return AriaFinanceCalculator.calculateEmi(
            toDecimal(args.get('principal')),
            toDecimal(args.get('annual_rate_pct')),
            args.get('tenure_months') != null ? Integer.valueOf(args.get('tenure_months')) : null
        );
    }

    public static Map<String, Object> calculateLoanEligibility(Map<String, Object> args) {
        return AriaFinanceCalculator.calculateLoanEligibility(
            toDecimal(args.get('monthly_income')),
            toDecimal(args.get('existing_emi')),
            toDecimal(args.get('annual_rate_pct')),
            args.get('tenure_months') != null ? Integer.valueOf(args.get('tenure_months')) : null
        );
    }

    public static Map<String, Object> getCostBreakdown(Map<String, Object> args) {
        Id unitId = (Id) args.get('unit_id');
        if (unitId == null) throw new AriaActionException('unit_id is required.');
        return AriaFinanceCalculator.getCostBreakdown(unitId);
    }

    // ════════════════════════════════════════════════════════════
    // AGENT METRICS (Phase 2)
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> myPerformance(Map<String, Object> args) {
        Integer days = args.get('range_days') != null
            ? Integer.valueOf(args.get('range_days')) : 30;
        return AriaAgentMetricsService.myPerformance(days);
    }

    public static Map<String, Object> getOverdueFollowups(Map<String, Object> args) {
        return AriaAgentMetricsService.getOverdueFollowups();
    }

    public static Map<String, Object> getStaleLeads(Map<String, Object> args) {
        Integer days = args.get('days') != null
            ? Integer.valueOf(args.get('days')) : 7;
        return AriaAgentMetricsService.getStaleLeads(days);
    }

    public static Map<String, Object> explainLeadScore(Map<String, Object> args) {
        Id leadId = (Id) args.get('lead_id');
        if (leadId == null) throw new AriaActionException('lead_id is required.');
        return AriaAgentMetricsService.explainLeadScore(leadId);
    }

    // ════════════════════════════════════════════════════════════
    // ORG-WRAPPER TOOLS (Phase 3)
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> getFunnelAnalysis(Map<String, Object> args) {
        ForecastingService.ForecastFilter filter = new ForecastingService.ForecastFilter();
        if (args.get('project_id') != null) {
            filter.projectId = (Id) args.get('project_id');
        }
        if (args.get('range_days') != null) {
            filter.startDate = Date.today().addDays(-Integer.valueOf(args.get('range_days')));
            filter.endDate = Date.today();
        }
        ForecastingService.FunnelAnalysis funnel = ForecastingService.analyzeFunnel(filter);
        return new Map<String, Object>{
            'total_leads'             => funnel.totalLeads,
            'total_bookings'          => funnel.totalBookings,
            'overall_conversion_pct'  => funnel.overallConversionRate,
            'stages'                  => funnel.stages
        };
    }

    public static Map<String, Object> cancelBooking(Map<String, Object> args) {
        Id bookingId = (Id) args.get('booking_id');
        if (bookingId == null) throw new AriaActionException('booking_id is required.');

        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = bookingId;

        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(
                new List<BookingCancellationHandler.CancellationRequest>{ req }
            );

        BookingCancellationHandler.CancellationResult r = results[0];
        if (r.success != true) {
            throw new AriaActionException(r.message != null ? r.message : 'Booking cancellation failed.');
        }
        return new Map<String, Object>{
            'booking_id' => bookingId,
            'success'    => true,
            'message'    => r.message != null ? r.message : 'Booking cancelled. Unit released to Available.'
        };
    }

    public static Map<String, Object> raiseComplaint(Map<String, Object> args) {
        Id bookingId = (Id) args.get('booking_id');
        if (bookingId == null) throw new AriaActionException('booking_id is required (complaints are linked to bookings).');

        Complaint__c c = new Complaint__c();
        c.Booking__c      = bookingId;
        c.Category__c     = asString(args.get('category'));
        c.Priority__c     = asString(args.get('priority'));
        if (String.isBlank(c.Priority__c)) c.Priority__c = 'Medium';
        c.Description__c  = asString(args.get('description'));
        c.Subject__c      = asString(args.get('subject'));
        if (String.isBlank(c.Subject__c)) c.Subject__c = 'Complaint via Aria';
        c.Status__c       = 'Open';
        insert c;

        return new Map<String, Object>{
            'complaint_id' => c.Id,
            'booking_id'   => bookingId,
            'message'      => 'Complaint raised in Open status. The escalation matrix will apply automatically.'
        };
    }

    public static Map<String, Object> getDemandAging(Map<String, Object> args) {
        String projectId = asString(args.get('project_id'));
        if (String.isBlank(projectId)) throw new AriaActionException('project_id is required.');
        AgingAnalysisService.AgingReport report = AgingAnalysisService.getDemandAgingReport(projectId);
        return new Map<String, Object>{
            'report' => report
        };
    }

    public static Map<String, Object> getSnagAging(Map<String, Object> args) {
        String projectId = asString(args.get('project_id'));
        if (String.isBlank(projectId)) throw new AriaActionException('project_id is required.');
        AgingAnalysisService.AgingReport report = AgingAnalysisService.getSnagAgingReport(projectId);
        return new Map<String, Object>{
            'report' => report
        };
    }

    public static Map<String, Object> previewLeadAssignment(Map<String, Object> args) {
        Id projectId = resolveProjectId(args);
        if (projectId == null) throw new AriaActionException('project_id or project_code is required.');
        String assignmentType = asString(args.get('assignment_type'));
        if (String.isBlank(assignmentType)) assignmentType = 'Pre Sales';

        Id nextUser = RoundRobinService.getNextUser(projectId, assignmentType);
        String userName = 'Unknown';
        if (nextUser != null) {
            List<User> users = [SELECT Name FROM User WHERE Id = :nextUser LIMIT 1];
            if (!users.isEmpty()) userName = users[0].Name;
        }
        return new Map<String, Object>{
            'project_id'      => projectId,
            'assignment_type' => assignmentType,
            'next_user_id'    => nextUser,
            'next_user_name'  => userName,
            'message'         => nextUser != null
                ? 'Next lead will be assigned to ' + userName
                : 'No available user in the round-robin pool for this project.'
        };
    }

    // ════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════

    private static Id resolveProjectId(Map<String, Object> args) {
        Object raw = args.get('project_id');
        if (raw != null && String.isNotBlank(String.valueOf(raw))) {
            try {
                return (Id) String.valueOf(raw);
            } catch (Exception ignored) { }
        }
        String code = asString(args.get('project_code'));
        if (String.isNotBlank(code)) {
            for (Project__c p : [SELECT Id FROM Project__c WHERE Project_Code__c = :code LIMIT 1]) {
                return p.Id;
            }
        }
        return null;
    }

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    private static Decimal toDecimal(Object o) {
        if (o == null) return null;
        if (o instanceof Decimal) return (Decimal) o;
        if (o instanceof Integer) return Decimal.valueOf((Integer) o);
        if (o instanceof Double)  return Decimal.valueOf((Double) o);
        String s = String.valueOf(o).trim();
        if (String.isBlank(s)) return null;
        try {
            return Decimal.valueOf(s);
        } catch (Exception e) {
            return null;
        }
    }

    // Guard against scheduling in the past. A 1-minute tolerance absorbs
    // clock skew and the lag between Gemini picking a time and this code
    // running. Caller passes a friendly label for the error message.
    private static void rejectIfPast(DateTime scheduled, String label) {
        if (scheduled == null) return;
        DateTime floor = DateTime.now().addMinutes(-1);
        if (scheduled < floor) {
            String whenStr = scheduled.format('d MMM yyyy, h:mm a', UserInfo.getTimeZone().getID());
            throw new AriaActionException(
                'Cannot schedule a ' + label + ' for ' + whenStr +
                ' — that time is in the past. Please pick a future time.'
            );
        }
    }

    private static DateTime parseDateTime(Object o) {
        if (o == null) return null;
        if (o instanceof DateTime) return (DateTime) o;
        String s = String.valueOf(o).trim();
        if (String.isBlank(s)) return null;

        // If the string carries an explicit timezone marker (Z or ±HH:MM),
        // honour it via JSON.deserialize which treats it as absolute time.
        // Without a marker, assume the user's LOCAL timezone — that is what
        // Gemini / the user means when they say "today at 4 pm". The old
        // implementation did the opposite (tzless → UTC) and turned 4 pm IST
        // into 9:30 pm IST.
        Boolean hasExplicitTz = Pattern.matches('.*([Zz]|[+-]\\d{2}:?\\d{2})$', s);

        if (hasExplicitTz) {
            try {
                return (DateTime) JSON.deserialize('"' + s + '"', DateTime.class);
            } catch (Exception ignored) { }
        }

        try {
            return DateTime.valueOf(s.replace('T', ' '));
        } catch (Exception ignored) { }

        // Last resort for already-tz-aware inputs that JSON couldn't handle
        try {
            return (DateTime) JSON.deserialize('"' + s + '"', DateTime.class);
        } catch (Exception ignored) { }

        return null;
    }

    private static Date parseDate(Object o) {
        if (o == null) return null;
        if (o instanceof Date) return (Date) o;
        String s = String.valueOf(o).trim();
        if (String.isBlank(s)) return null;
        try {
            return Date.valueOf(s);
        } catch (Exception ignored) { }
        return null;
    }
}