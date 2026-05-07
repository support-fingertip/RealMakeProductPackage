/**
 * @description Read-only knowledge layer for Aria.
 *
 * Provides compact, LLM-friendly views of org data:
 *   - Active project digest (for initial system-prompt context)
 *   - Per-project details (features, pricing band, RERA)
 *   - Unit availability filtered by BHK/budget
 *   - Lead history (status, follow-ups, visits, cost sheets) for a recordId
 *   - Next-best-action suggestion based on lead stage + score tier
 *
 * All returns are plain Maps/Lists so they can be serialised directly into the
 * Gemini prompt. No DML, no callouts.
 */
public with sharing class AriaKnowledgeService {

    private static final Integer PROJECT_LIMIT = 20;
    private static final Integer UNIT_LIMIT = 10;
    private static final Integer HISTORY_LIMIT = 5;

    // ════════════════════════════════════════════════════════════
    // PROJECT DIGEST
    // ════════════════════════════════════════════════════════════

    /**
     * @description Summary of active projects for the system prompt.
     *              Keeps payload small — name, code, city, status, BHK types,
     *              available unit count.
     */
    public static List<Map<String, Object>> getProjectsDigest() {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Project__c p : [
            SELECT Id, Name, Project_Code__c, City__c, State__c, Project_Status__c,
                   Property_Types__c, Allowed_BHK_Types__c, RERA_Number__c,
                   Available_Units__c, Total_Units__c, Booked_Units__c,
                   Expected_Completion_Date__c
            FROM Project__c
            WHERE Is_Active__c = true
              AND Project_Status__c IN ('Pre-Launch', 'Launched', 'Ongoing')
            ORDER BY Name
            LIMIT :PROJECT_LIMIT
        ]) {
            out.add(new Map<String, Object>{
                'id'               => p.Id,
                'name'             => p.Name,
                'code'             => p.Project_Code__c,
                'city'             => p.City__c,
                'state'            => p.State__c,
                'status'           => p.Project_Status__c,
                'property_types'   => p.Property_Types__c,
                'allowed_bhk'      => p.Allowed_BHK_Types__c,
                'rera_number'      => p.RERA_Number__c,
                'available_units'  => p.Available_Units__c,
                'total_units'      => p.Total_Units__c,
                'booked_units'     => p.Booked_Units__c,
                'possession_date'  => p.Expected_Completion_Date__c
            });
        }
        return out;
    }

    /** Full detail card for one project — used for "tell me more about X". */
    public static Map<String, Object> getProjectDetails(Id projectId) {
        if (projectId == null) return null;
        List<Project__c> rows = [
            SELECT Id, Name, Project_Code__c, Description__c, City__c, State__c,
                   Street__c, Postal_Code__c, Address__c,
                   Project_Status__c, Project_Type__c, Property_Types__c,
                   Allowed_BHK_Types__c, Amenities__c, RERA_Number__c,
                   Total_Project_Value__c, Available_Units__c, Total_Units__c,
                   Booked_Units__c, Start_Date__c, Expected_Completion_Date__c
            FROM Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;

        Project__c p = rows[0];
        // Quick price band sample from available units
        Decimal minPrice, maxPrice;
        for (AggregateResult ar : [
            SELECT MIN(Base_Price__c) minP, MAX(Base_Price__c) maxP
            FROM Unit__c
            WHERE Project__c = :projectId AND Status__c = 'Available'
        ]) {
            minPrice = (Decimal) ar.get('minP');
            maxPrice = (Decimal) ar.get('maxP');
        }

        return new Map<String, Object>{
            'id'               => p.Id,
            'name'             => p.Name,
            'code'             => p.Project_Code__c,
            'description'      => p.Description__c,
            'city'             => p.City__c,
            'state'            => p.State__c,
            'address'          => p.Address__c,
            'status'           => p.Project_Status__c,
            'project_type'     => p.Project_Type__c,
            'property_types'   => p.Property_Types__c,
            'allowed_bhk'      => p.Allowed_BHK_Types__c,
            'amenities'        => p.Amenities__c,
            'rera_number'      => p.RERA_Number__c,
            'total_units'      => p.Total_Units__c,
            'available_units'  => p.Available_Units__c,
            'booked_units'     => p.Booked_Units__c,
            'start_date'       => p.Start_Date__c,
            'possession_date'  => p.Expected_Completion_Date__c,
            'price_range_min'  => minPrice,
            'price_range_max'  => maxPrice
        };
    }

    // ════════════════════════════════════════════════════════════
    // UNIT AVAILABILITY
    // ════════════════════════════════════════════════════════════

    /**
     * @description Find available units matching BHK + budget. Any parameter
     *              may be null to skip that filter.
     */
    public static List<Map<String, Object>> getUnitAvailability(
        Id projectId, String bhkType, Decimal budgetMin, Decimal budgetMax
    ) {
        List<String> whereParts = new List<String>{ 'Status__c = \'Available\'' };
        Map<String, Object> binds = new Map<String, Object>();

        if (projectId != null) {
            whereParts.add('Project__c = :projectId');
            binds.put('projectId', projectId);
        }
        if (String.isNotBlank(bhkType)) {
            whereParts.add('BHK_Type__c = :bhkType');
            binds.put('bhkType', bhkType);
        }
        if (budgetMin != null) {
            whereParts.add('Base_Price__c >= :budgetMin');
            binds.put('budgetMin', budgetMin);
        }
        if (budgetMax != null) {
            whereParts.add('Base_Price__c <= :budgetMax');
            binds.put('budgetMax', budgetMax);
        }

        String soql = 'SELECT Id, Name, Unit_Number__c, Unit_Code__c, Floor__c, Wing__c, Facing__c, '
                   + 'BHK_Type__c, Super_Builtup_Area__c, Carpet_Area__c, Base_Price__c, '
                   + 'Project__c, Project__r.Name, Tower__r.Name, Status__c '
                   + 'FROM Unit__c WHERE ' + String.join(whereParts, ' AND ')
                   + ' ORDER BY Base_Price__c ASC LIMIT ' + UNIT_LIMIT;

        List<Unit__c> units = Database.queryWithBinds(
            soql, binds, AccessLevel.USER_MODE
        );

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Unit__c u : units) {
            out.add(new Map<String, Object>{
                'id'                => u.Id,
                'unit_no'           => u.Unit_Number__c,
                'unit_code'         => u.Unit_Code__c,
                'tower'             => u.Tower__r != null ? u.Tower__r.Name : null,
                'floor'             => u.Floor__c,
                'wing'              => u.Wing__c,
                'facing'            => u.Facing__c,
                'bhk'               => u.BHK_Type__c,
                'saleable_area'     => u.Super_Builtup_Area__c,
                'carpet_area'       => u.Carpet_Area__c,
                'base_price'        => u.Base_Price__c,
                'project_id'        => u.Project__c,
                'project_name'      => u.Project__r != null ? u.Project__r.Name : null,
                'status'            => u.Status__c
            });
        }
        return out;
    }

    // ════════════════════════════════════════════════════════════
    // LEAD SEARCH
    // ════════════════════════════════════════════════════════════

    /**
     * @description Flexible lead search. Accepts ANY of:
     *              - Auto-number Name (e.g. "LD-000466") — exact match
     *              - Mobile number (8+ digits) — trailing-10-digit match on
     *                Primary_Mobile__c or Secondary_Mobile__c
     *              - Email address (contains @) — exact match
     *              - Otherwise treated as a name / partial name — LIKE on
     *                Full_Name__c, First_Name__c, Last_Name__c
     *
     *              Returns up to 10 matches with full lead context so Aria
     *              can answer the typical follow-up without a second query.
     */
    public static List<Map<String, Object>> findLead(String query) {
        if (String.isBlank(query)) return new List<Map<String, Object>>();
        String q = query.trim();
        List<Lead__c> rows;

        if (q.toUpperCase().startsWith('LD-') || q.toUpperCase().startsWith('L-')) {
            rows = [
                SELECT Id FROM Lead__c
                WHERE Name = :q
                LIMIT 1
            ];
        } else if (q.contains('@')) {
            rows = [
                SELECT Id FROM Lead__c
                WHERE Primary_Email__c = :q
                LIMIT 10
            ];
        } else {
            String digits = q.replaceAll('[^0-9]', '');
            if (String.isNotBlank(digits) && digits.length() >= 8) {
                String last10 = digits.length() >= 10 ? digits.substring(digits.length() - 10) : digits;
                String wildcard = '%' + last10;
                rows = [
                    SELECT Id FROM Lead__c
                    WHERE Primary_Mobile__c LIKE :wildcard
                       OR Secondary_Mobile__c LIKE :wildcard
                    LIMIT 10
                ];
            } else {
                String wildcard = '%' + q + '%';
                rows = [
                    SELECT Id FROM Lead__c
                    WHERE Full_Name__c LIKE :wildcard
                       OR First_Name__c LIKE :wildcard
                       OR Last_Name__c LIKE :wildcard
                    LIMIT 10
                ];
            }
        }

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Lead__c row : rows) {
            Map<String, Object> ctx = getLeadContext(row.Id);
            if (ctx != null) out.add(ctx);
        }
        return out;
    }

    // ════════════════════════════════════════════════════════════
    // UNIVERSAL SEARCH — any identifier, any record type
    // ════════════════════════════════════════════════════════════

    /**
     * @description Search across Lead, Booking, Cost Sheet, Unit and Project
     *              by any identifier the user supplies. Handles auto-number
     *              prefixes (LD-, BK-, CS- etc.), mobile numbers, emails,
     *              unit numbers, project codes and free-text name fragments.
     *
     *              Returns an array of `{type, id, name, summary, ...}` so
     *              Aria can present results uniformly.
     */
    public static List<Map<String, Object>> universalSearch(String query) {
        if (String.isBlank(query)) return new List<Map<String, Object>>();
        String q = query.trim();
        String upper = q.toUpperCase();
        List<Map<String, Object>> out = new List<Map<String, Object>>();

        // Prefix-based fast paths first
        if (upper.startsWith('LD-') || upper.startsWith('L-')) {
            for (Map<String, Object> m : findLead(q)) {
                out.add(leadDigest(m));
            }
            return out;
        }
        if (upper.startsWith('BK-') || upper.startsWith('B-')) {
            out.addAll(findBookingsByName(q));
            return out;
        }
        if (upper.startsWith('CS-')) {
            out.addAll(findCostSheetsByName(q));
            return out;
        }

        // Email → leads only
        if (q.contains('@')) {
            for (Map<String, Object> m : findLead(q)) out.add(leadDigest(m));
            return out;
        }

        // All-digits → mobile search on Lead first, then unit numbers
        String digits = q.replaceAll('[^0-9]', '');
        if (String.isNotBlank(digits) && digits.length() >= 8 && digits.length() == q.length()) {
            for (Map<String, Object> m : findLead(q)) out.add(leadDigest(m));
            return out;
        }

        // Otherwise fan out to all object types
        for (Map<String, Object> m : findLead(q)) out.add(leadDigest(m));
        out.addAll(findProjectsByNameOrCode(q));
        out.addAll(findUnitsByNumber(q));
        out.addAll(findBookingsByCustomer(q));
        return out;
    }

    // — Individual object searches ————————————————————————————————

    public static List<Map<String, Object>> findBookingsByName(String name) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Booking__c b : [
            SELECT Id, Name, Status__c, Booking_Stage__c, Booking_Amount__c,
                   Customer_Name__c, Customer_Mobile__c,
                   Unit__r.Unit_Number__c, Project__r.Name, Lead__c
            FROM Booking__c WHERE Name = :name LIMIT 5
        ]) {
            out.add(bookingDigest(b));
        }
        return out;
    }

    public static List<Map<String, Object>> findBookingsByCustomer(String text) {
        String wildcard = '%' + text + '%';
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Booking__c b : [
            SELECT Id, Name, Status__c, Booking_Stage__c, Booking_Amount__c,
                   Customer_Name__c, Customer_Mobile__c,
                   Unit__r.Unit_Number__c, Project__r.Name, Lead__c
            FROM Booking__c
            WHERE Customer_Name__c LIKE :wildcard
               OR Customer_Mobile__c LIKE :wildcard
            LIMIT 5
        ]) {
            out.add(bookingDigest(b));
        }
        return out;
    }

    public static List<Map<String, Object>> findCostSheetsByName(String name) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Cost_Sheet__c cs : [
            SELECT Id, Name, Status__c, Agreement_Value__c, Net_Payable__c,
                   Lead__c, Lead__r.Name, Lead__r.Full_Name__c,
                   Unit__r.Unit_Number__c, Project__r.Name
            FROM Cost_Sheet__c WHERE Name = :name LIMIT 5
        ]) {
            out.add(new Map<String, Object>{
                'type'            => 'cost_sheet',
                'id'              => cs.Id,
                'name'            => cs.Name,
                'summary'         => 'Cost Sheet ' + cs.Name + ' — ' + cs.Status__c,
                'status'          => cs.Status__c,
                'agreement_value' => cs.Agreement_Value__c,
                'net_payable'     => cs.Net_Payable__c,
                'unit_no'         => cs.Unit__r != null ? cs.Unit__r.Unit_Number__c : null,
                'project'         => cs.Project__r != null ? cs.Project__r.Name : null,
                'lead_id'         => cs.Lead__c,
                'lead_name'       => cs.Lead__r != null ? cs.Lead__r.Name : null,
                'customer_name'   => cs.Lead__r != null ? cs.Lead__r.Full_Name__c : null
            });
        }
        return out;
    }

    public static List<Map<String, Object>> findProjectsByNameOrCode(String text) {
        String wildcard = '%' + text + '%';
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Project__c p : [
            SELECT Id, Name, Project_Code__c, City__c, State__c, Project_Status__c,
                   Allowed_BHK_Types__c, Available_Units__c
            FROM Project__c
            WHERE (Name LIKE :wildcard OR Project_Code__c LIKE :wildcard)
              AND Is_Active__c = true
            LIMIT 5
        ]) {
            out.add(new Map<String, Object>{
                'type'            => 'project',
                'id'              => p.Id,
                'name'            => p.Name,
                'summary'         => p.Name + ' (' + p.Project_Code__c + ') — ' + p.City__c + ', ' + p.State__c,
                'code'            => p.Project_Code__c,
                'city'            => p.City__c,
                'state'           => p.State__c,
                'status'          => p.Project_Status__c,
                'allowed_bhk'     => p.Allowed_BHK_Types__c,
                'available_units' => p.Available_Units__c
            });
        }
        return out;
    }

    public static List<Map<String, Object>> findUnitsByNumber(String text) {
        String wildcard = '%' + text + '%';
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Unit__c u : [
            SELECT Id, Name, Unit_Number__c, Unit_Code__c, BHK_Type__c, Status__c,
                   Base_Price__c, Project__r.Name, Tower__r.Name
            FROM Unit__c
            WHERE Unit_Number__c LIKE :wildcard
               OR Unit_Code__c LIKE :wildcard
               OR Name = :text
            LIMIT 5
        ]) {
            out.add(new Map<String, Object>{
                'type'       => 'unit',
                'id'         => u.Id,
                'name'       => u.Unit_Number__c != null ? u.Unit_Number__c : u.Name,
                'summary'    => 'Unit ' + u.Unit_Number__c + ' — ' + u.BHK_Type__c + ' (' + u.Status__c + ') in ' + (u.Project__r != null ? u.Project__r.Name : ''),
                'unit_no'    => u.Unit_Number__c,
                'bhk'        => u.BHK_Type__c,
                'status'     => u.Status__c,
                'base_price' => u.Base_Price__c,
                'project'    => u.Project__r != null ? u.Project__r.Name : null,
                'tower'      => u.Tower__r != null ? u.Tower__r.Name : null
            });
        }
        return out;
    }

    private static Map<String, Object> leadDigest(Map<String, Object> ctx) {
        // Wrap a Lead's full context into the uniform universal-search shape
        return new Map<String, Object>{
            'type'       => 'lead',
            'id'         => ctx.get('id'),
            'name'       => ctx.get('display_id'),
            'summary'    => 'Lead ' + ctx.get('display_id') + ' — ' + ctx.get('full_name')
                          + ' (' + ctx.get('status') + ')',
            'lead_id'    => ctx.get('id'),
            'full_name'  => ctx.get('full_name'),
            'mobile'     => ctx.get('mobile'),
            'email'      => ctx.get('email'),
            'status'     => ctx.get('status'),
            'tier'       => ctx.get('tier'),
            'project'    => ctx.get('project_name'),
            'bhk'        => ctx.get('bhk_preference'),
            'budget'     => ctx.get('budget_range'),
            'purpose'    => ctx.get('purpose'),
            'context'    => ctx
        };
    }

    private static Map<String, Object> bookingDigest(Booking__c b) {
        return new Map<String, Object>{
            'type'           => 'booking',
            'id'             => b.Id,
            'name'           => b.Name,
            'summary'        => 'Booking ' + b.Name + ' — ' + b.Status__c + ' (' + b.Booking_Stage__c + ')',
            'status'         => b.Status__c,
            'stage'          => b.Booking_Stage__c,
            'amount'         => b.Booking_Amount__c,
            'customer_name'  => b.Customer_Name__c,
            'customer_mobile'=> b.Customer_Mobile__c,
            'unit_no'        => b.Unit__r != null ? b.Unit__r.Unit_Number__c : null,
            'project'        => b.Project__r != null ? b.Project__r.Name : null,
            'lead_id'        => b.Lead__c
        };
    }

    // ════════════════════════════════════════════════════════════
    // BOOKING READINESS
    // ════════════════════════════════════════════════════════════

    /**
     * @description Diagnose where the lead is in the booking funnel and what
     *              concrete step is needed next. Used by the booking-flow
     *              tools so Aria can explain "why can't I book yet" clearly.
     */
    public static Map<String, Object> getBookingReadiness(Id leadId) {
        if (leadId == null) return null;

        List<Lead__c> leads = [
            SELECT Id, Name, Full_Name__c, Lead_Status__c, Project__c,
                   Primary_Mobile__c, Primary_Email__c
            FROM Lead__c WHERE Id = :leadId LIMIT 1
        ];
        if (leads.isEmpty()) {
            return new Map<String, Object>{ 'error' => 'Lead not found.' };
        }
        Lead__c l = leads[0];

        // Already booked?
        List<Booking__c> bookings = [
            SELECT Id, Name, Status__c, Booking_Stage__c, Booking_Amount__c,
                   Unit__r.Unit_Number__c, Project__r.Name
            FROM Booking__c
            WHERE Lead__c = :leadId
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
        Map<String, Object> out = new Map<String, Object>{
            'lead_id'       => l.Id,
            'lead_name'     => l.Name,
            'full_name'     => l.Full_Name__c,
            'lead_status'   => l.Lead_Status__c,
            'bookings'      => bookingsToMaps(bookings)
        };
        if (!bookings.isEmpty() && 'Booked'.equalsIgnoreCase(l.Lead_Status__c)) {
            out.put('status', 'already_booked');
            out.put('next_action', null);
            out.put('suggestion', 'This lead already has a booking (' + bookings[0].Name + '). You can open the booking to track payment schedule.');
            return out;
        }

        // Find cost sheets
        List<Cost_Sheet__c> sheets = [
            SELECT Id, Name, Status__c, Unit__c, Unit__r.Unit_Number__c, Unit__r.Status__c,
                   Project__c, Project__r.Name, Project__r.Min_Booking_Amount__c,
                   Agreement_Value__c, Net_Payable__c
            FROM Cost_Sheet__c
            WHERE Lead__c = :leadId
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
        out.put('cost_sheets', costSheetsToMaps(sheets));

        if (sheets.isEmpty()) {
            out.put('status', 'needs_cost_sheet');
            out.put('next_action', 'generate_cost_sheet');
            out.put('suggestion', 'No cost sheet yet. Draft one for the lead\'s preferred unit to move toward booking.');
            return out;
        }

        // Find the furthest-along cost sheet
        Cost_Sheet__c ready = null;
        Cost_Sheet__c approved = null;
        Cost_Sheet__c pending = null;
        for (Cost_Sheet__c cs : sheets) {
            if ('Accepted by Customer'.equalsIgnoreCase(cs.Status__c) && ready == null) ready = cs;
            else if ('Approved'.equalsIgnoreCase(cs.Status__c) && approved == null) approved = cs;
            else if ('Pending Approval'.equalsIgnoreCase(cs.Status__c) && pending == null) pending = cs;
        }

        if (ready != null) {
            out.put('status', 'ready_to_book');
            out.put('ready_cost_sheet_id', ready.Id);
            out.put('ready_cost_sheet_name', ready.Name);
            out.put('unit_number', ready.Unit__r != null ? ready.Unit__r.Unit_Number__c : null);
            out.put('min_booking_amount', ready.Project__r != null ? ready.Project__r.Min_Booking_Amount__c : null);
            out.put('agreement_value', ready.Agreement_Value__c);
            out.put('next_action', 'initiate_booking');
            out.put('suggestion', 'Cost sheet ' + ready.Name + ' is accepted by the customer. Collect the booking amount and initiate the booking.');
            return out;
        }
        if (approved != null) {
            out.put('status', 'awaiting_customer_acceptance');
            out.put('cost_sheet_id', approved.Id);
            out.put('cost_sheet_name', approved.Name);
            out.put('next_action', 'customer_accept_cost_sheet');
            out.put('suggestion', 'Cost sheet ' + approved.Name + ' is internally approved but not yet accepted by the customer. Share it with the customer for acceptance.');
            return out;
        }
        if (pending != null) {
            out.put('status', 'awaiting_internal_approval');
            out.put('cost_sheet_id', pending.Id);
            out.put('cost_sheet_name', pending.Name);
            out.put('next_action', 'chase_approval');
            out.put('suggestion', 'Cost sheet ' + pending.Name + ' is pending internal approval. Chase the approver before booking.');
            return out;
        }

        out.put('status', 'cost_sheet_not_progressed');
        out.put('cost_sheet_id', sheets[0].Id);
        out.put('cost_sheet_name', sheets[0].Name);
        out.put('cost_sheet_status', sheets[0].Status__c);
        out.put('next_action', 'revise_or_submit_cost_sheet');
        out.put('suggestion', 'Latest cost sheet ' + sheets[0].Name + ' is in "' + sheets[0].Status__c + '". Submit for approval or draft a fresh one.');
        return out;
    }

    // ════════════════════════════════════════════════════════════
    // HOT LEADS (RANKED BY BOOKING READINESS)
    // ════════════════════════════════════════════════════════════

    /**
     * @description Returns the current user's leads ranked by how close they
     *              are to booking. Scoring is deterministic: cost-sheet stage
     *              is the dominant signal, with site-visit progress and the
     *              lead's score tier as secondary signals, and a decay penalty
     *              for leads untouched beyond 14 days.
     *
     *              Inactive leads (Booked / Closed Lost / Unqualified) are
     *              excluded via CPModuleConfigService.getLeadInactiveStatuses.
     *
     *              Returns up to topN entries; defaults to 5 when topN is null or <=0.
     */
    public static List<Map<String, Object>> getHotLeads(Integer topN) {
        Integer limitN = (topN == null || topN <= 0) ? 5 : topN;

        Set<String> inactive;
        try {
            inactive = CPModuleConfigService.getLeadInactiveStatuses();
        } catch (Exception e) {
            inactive = new Set<String>{ 'Unqualified', 'Closed Lost', 'Booked' };
        }
        if (inactive == null || inactive.isEmpty()) {
            inactive = new Set<String>{ 'Unqualified', 'Closed Lost', 'Booked' };
        }

        Id userId = UserInfo.getUserId();

        List<Lead__c> leads = [
            SELECT Id, Name, Full_Name__c, Lead_Status__c, Lead_Score__c,
                   Lead_Score_Tier__c, LastModifiedDate,
                   Project__c, Project__r.Name,
                   (SELECT Id, Name, Status__c FROM Cost_Sheets__r ORDER BY CreatedDate DESC LIMIT 5),
                   (SELECT Id, Status__c FROM Site_Visits__r ORDER BY CreatedDate DESC LIMIT 5)
            FROM Lead__c
            WHERE Owner__c = :userId
              AND Lead_Status__c NOT IN :inactive
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ];

        List<Map<String, Object>> scored = new List<Map<String, Object>>();
        for (Lead__c l : leads) {
            Map<String, Object> stage = classifyHotLead(l);
            Integer priority = (Integer) stage.get('priority');
            if (priority <= 0) continue;

            scored.add(new Map<String, Object>{
                'lead_id'     => l.Id,
                'lead_name'   => l.Name,
                'full_name'   => l.Full_Name__c,
                'project'     => l.Project__r != null ? l.Project__r.Name : null,
                'lead_status' => l.Lead_Status__c,
                'lead_score'  => l.Lead_Score__c,
                'tier'        => l.Lead_Score_Tier__c,
                'priority'    => priority,
                'status'      => stage.get('status'),
                'next_action' => stage.get('next_action'),
                'suggestion'  => stage.get('suggestion')
            });
        }

        scored.sort(new HotLeadComparator());

        if (scored.size() > limitN) {
            List<Map<String, Object>> trimmed = new List<Map<String, Object>>();
            for (Integer i = 0; i < limitN; i++) trimmed.add(scored[i]);
            return trimmed;
        }
        return scored;
    }

    /**
     * @description Classify a lead's booking-readiness stage and compute a
     *              priority score. Reuses the language used by
     *              getBookingReadiness so Aria stays consistent across tools.
     */
    private static Map<String, Object> classifyHotLead(Lead__c l) {
        Integer priority = 0;
        String status = null;
        String nextAction = null;
        String suggestion = null;

        Cost_Sheet__c accepted = null;
        Cost_Sheet__c approved = null;
        Cost_Sheet__c pending  = null;
        Cost_Sheet__c anySheet = null;
        if (l.Cost_Sheets__r != null) {
            for (Cost_Sheet__c cs : l.Cost_Sheets__r) {
                if (anySheet == null) anySheet = cs;
                if (accepted == null && 'Accepted by Customer'.equalsIgnoreCase(cs.Status__c)) accepted = cs;
                else if (approved == null && 'Approved'.equalsIgnoreCase(cs.Status__c)) approved = cs;
                else if (pending == null && 'Pending Approval'.equalsIgnoreCase(cs.Status__c)) pending = cs;
            }
        }

        if (accepted != null) {
            priority += 100;
            status = 'ready_to_book';
            nextAction = 'initiate_booking';
            suggestion = 'Cost sheet ' + accepted.Name + ' is accepted by the customer. Collect the booking amount and initiate the booking.';
        } else if (approved != null) {
            priority += 70;
            status = 'awaiting_customer_acceptance';
            nextAction = 'customer_accept_cost_sheet';
            suggestion = 'Cost sheet ' + approved.Name + ' is internally approved. Share it with the customer for acceptance.';
        } else if (pending != null) {
            priority += 50;
            status = 'awaiting_internal_approval';
            nextAction = 'chase_approval';
            suggestion = 'Cost sheet ' + pending.Name + ' is pending internal approval. Chase the approver before booking.';
        } else if (anySheet != null) {
            priority += 25;
            status = 'cost_sheet_not_progressed';
            nextAction = 'revise_or_submit_cost_sheet';
            suggestion = 'Latest cost sheet ' + anySheet.Name + ' is in "' + anySheet.Status__c + '". Submit for approval or draft a fresh one.';
        }

        Boolean svCompleted = false;
        Boolean svScheduled = false;
        if (l.Site_Visits__r != null) {
            for (Site_Visit__c sv : l.Site_Visits__r) {
                if ('Completed'.equalsIgnoreCase(sv.Status__c)) svCompleted = true;
                else if ('Scheduled'.equalsIgnoreCase(sv.Status__c)) svScheduled = true;
            }
        }
        if (svCompleted) priority += 30;
        else if (svScheduled) priority += 20;

        if (status == null) {
            if (svCompleted) {
                status = 'needs_cost_sheet';
                nextAction = 'generate_cost_sheet';
                suggestion = 'Site visit completed. Draft a cost sheet for the preferred unit to move toward booking.';
            } else if (svScheduled) {
                status = 'site_visit_scheduled';
                nextAction = 'prepare_for_site_visit';
                suggestion = 'Site visit is scheduled. Confirm the slot and prepare unit options.';
            } else {
                status = 'needs_site_visit';
                nextAction = 'schedule_site_visit';
                suggestion = 'No site visit yet. Scheduling one is the biggest conversion lever — set it up.';
            }
        }

        String tier = l.Lead_Score_Tier__c;
        if (String.isNotBlank(tier)) {
            if ('Hot'.equalsIgnoreCase(tier)) priority += 15;
            else if ('Warm'.equalsIgnoreCase(tier)) priority += 7;
        }

        if (l.LastModifiedDate != null) {
            Integer staleDays = (Integer) ((DateTime.now().getTime() - l.LastModifiedDate.getTime()) / (1000L * 60L * 60L * 24L));
            if (staleDays > 14) priority -= 10;
        }

        return new Map<String, Object>{
            'priority'    => priority,
            'status'      => status,
            'next_action' => nextAction,
            'suggestion'  => suggestion
        };
    }

    private class HotLeadComparator implements Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            Integer pa = (Integer) a.get('priority');
            Integer pb = (Integer) b.get('priority');
            if (pa == null) pa = 0;
            if (pb == null) pb = 0;
            if (pa > pb) return -1;
            if (pa < pb) return 1;
            Decimal sa = (Decimal) a.get('lead_score');
            Decimal sb = (Decimal) b.get('lead_score');
            if (sa == null) sa = 0;
            if (sb == null) sb = 0;
            if (sa > sb) return -1;
            if (sa < sb) return 1;
            return 0;
        }
    }

    // ════════════════════════════════════════════════════════════
    // PAYMENT SCHEDULE
    // ════════════════════════════════════════════════════════════

    public static List<Map<String, Object>> getPaymentSchedule(Id bookingId) {
        if (bookingId == null) return new List<Map<String, Object>>();
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Payment_Schedule__c ps : [
            SELECT Id, Name, Sequence__c, Percentage__c, Amount__c, Due_Date__c, Status__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :bookingId
            ORDER BY Sequence__c ASC
        ]) {
            out.add(new Map<String, Object>{
                'id'         => ps.Id,
                'name'       => ps.Name,
                'sequence'   => ps.Sequence__c,
                'percentage' => ps.Percentage__c,
                'amount'     => ps.Amount__c,
                'due_date'   => ps.Due_Date__c,
                'status'     => ps.Status__c
            });
        }
        return out;
    }

    // ════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════

    private static List<Map<String, Object>> bookingsToMaps(List<Booking__c> rows) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Booking__c b : rows) {
            out.add(new Map<String, Object>{
                'id'          => b.Id,
                'name'        => b.Name,
                'status'      => b.Status__c,
                'stage'       => b.Booking_Stage__c,
                'amount'      => b.Booking_Amount__c,
                'unit_no'     => b.Unit__r != null ? b.Unit__r.Unit_Number__c : null,
                'project'     => b.Project__r != null ? b.Project__r.Name : null
            });
        }
        return out;
    }

    private static List<Map<String, Object>> costSheetsToMaps(List<Cost_Sheet__c> rows) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Cost_Sheet__c cs : rows) {
            out.add(new Map<String, Object>{
                'id'              => cs.Id,
                'name'            => cs.Name,
                'status'          => cs.Status__c,
                'unit_no'         => cs.Unit__r != null ? cs.Unit__r.Unit_Number__c : null,
                'project'         => cs.Project__r != null ? cs.Project__r.Name : null,
                'agreement_value' => cs.Agreement_Value__c,
                'net_payable'     => cs.Net_Payable__c
            });
        }
        return out;
    }

    // ════════════════════════════════════════════════════════════
    // GENERIC RECORD CONTEXT
    // ════════════════════════════════════════════════════════════

    private static final Set<String> RECORD_CONTEXT_SKIP_FIELDS = new Set<String>{
        'createdbyid', 'lastmodifiedbyid', 'systemmodstamp', 'isdeleted',
        'currencyisocode', 'ownerid', 'recordtypeid', 'lastactivitydate',
        'lastvieweddate', 'lastreferenceddate'
    };
    private static final Integer RECORD_CONTEXT_FIELD_CAP = 40;

    /**
     * @description Dynamic, FLS-aware snapshot of any SObject record the user
     *              has opened Aria on. Returns null when recordId is null, so
     *              the caller can simply skip adding a context block on Home /
     *              App / Tab pages (preserves the "normal tab" behaviour).
     *
     *              Strips audit/system fields, encrypted/binary types, and
     *              empty values. Caps at RECORD_CONTEXT_FIELD_CAP fields so
     *              the LLM prompt stays compact.
     */
    public static Map<String, Object> getRecordContext(Id recordId) {
        if (recordId == null) return null;

        Schema.SObjectType sot = recordId.getSObjectType();
        if (sot == null) return null;

        Schema.DescribeSObjectResult describe = sot.getDescribe();
        if (!describe.isAccessible()) return null;

        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();

        List<String> selectParts = new List<String>();
        List<String> relationshipPairs = new List<String>();
        Integer count = 0;
        for (String fieldName : fieldMap.keySet()) {
            if (count >= RECORD_CONTEXT_FIELD_CAP) break;
            Schema.SObjectField f = fieldMap.get(fieldName);
            Schema.DescribeFieldResult d = f.getDescribe();

            if (!d.isAccessible()) continue;
            if (RECORD_CONTEXT_SKIP_FIELDS.contains(fieldName.toLowerCase())) continue;

            Schema.DisplayType t = d.getType();
            if (t == Schema.DisplayType.Base64
                || t == Schema.DisplayType.EncryptedString
                || t == Schema.DisplayType.Address
                || t == Schema.DisplayType.Location) continue;

            // Skip huge text areas that would blow up the prompt
            if (t == Schema.DisplayType.TextArea && d.getLength() > 4000) continue;

            selectParts.add(d.getName());
            count++;

            // For reference fields, also pull the parent Name when the
            // relationship is to a standard name-bearing object.
            if (t == Schema.DisplayType.Reference && !d.getReferenceTo().isEmpty()) {
                String relName = d.getRelationshipName();
                if (String.isNotBlank(relName)) {
                    Schema.SObjectType parent = d.getReferenceTo()[0];
                    Schema.DescribeSObjectResult pd = parent.getDescribe();
                    if (pd.isAccessible() && pd.fields.getMap().containsKey('name')) {
                        relationshipPairs.add(relName + '.Name');
                    }
                }
            }
        }

        if (selectParts.isEmpty()) return null;

        String selectClause = String.join(selectParts, ', ');
        if (!relationshipPairs.isEmpty()) {
            selectClause += ', ' + String.join(relationshipPairs, ', ');
        }
        String soql = 'SELECT ' + selectClause
            + ' FROM ' + describe.getName()
            + ' WHERE Id = :recordId LIMIT 1';

        List<SObject> rows;
        try {
            rows = Database.query(soql);
        } catch (Exception e) {
            return null;
        }
        if (rows.isEmpty()) return null;
        SObject row = rows[0];

        Map<String, Object> ctx = new Map<String, Object>{
            'id'             => recordId,
            'sobject_type'   => describe.getName(),
            'sobject_label'  => describe.getLabel()
        };

        for (String apiName : selectParts) {
            Object val = row.get(apiName);
            if (val == null) continue;
            if (val instanceof String && String.isBlank((String) val)) continue;
            ctx.put(apiName, val);
        }

        for (String pair : relationshipPairs) {
            String relName = pair.substringBefore('.');
            SObject parent = row.getSObject(relName);
            if (parent != null) {
                Object parentName = parent.get('Name');
                if (parentName != null && !(parentName instanceof String && String.isBlank((String) parentName))) {
                    ctx.put(relName + '__name', parentName);
                }
            }
        }

        return ctx;
    }

    // ════════════════════════════════════════════════════════════
    // LEAD CONTEXT
    // ════════════════════════════════════════════════════════════

    /**
     * @description Full lead context — used when Aria is pinned to a Lead page.
     *              Includes lead fields, recent follow-ups, site visits and
     *              draft cost sheets so the LLM can make personalised
     *              recommendations.
     */
    public static Map<String, Object> getLeadContext(Id leadId) {
        if (leadId == null) return null;
        List<Lead__c> leads = [
            SELECT Id, Name, Full_Name__c, First_Name__c, Last_Name__c,
                   Primary_Mobile__c, Primary_Email__c,
                   Project__c, Project__r.Name, Project__r.Project_Code__c,
                   BHK_Type__c, Budget_Range__c, Property_Type__c,
                   Purchase_Purpose__c, Purchase_Timeline__c,
                   Lead_Status__c, PreSales_Status__c, Lead_Type__c,
                   Lead_Score__c, Lead_Score_Tier__c, Lead_Source__c, Lead_Sub_Source__c,
                   Owner__c, Pre_Sale_User__c, Last_Notes__c, Preferred_Language__c,
                   CreatedDate, LastModifiedDate
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];
        if (leads.isEmpty()) return null;
        Lead__c l = leads[0];

        Map<String, Object> ctx = new Map<String, Object>{
            'id'                => l.Id,
            'display_id'        => l.Name,
            'full_name'         => l.Full_Name__c,
            'mobile'            => l.Primary_Mobile__c,
            'email'             => l.Primary_Email__c,
            'project_id'        => l.Project__c,
            'project_name'      => l.Project__r != null ? l.Project__r.Name : null,
            'project_code'      => l.Project__r != null ? l.Project__r.Project_Code__c : null,
            'bhk_preference'    => l.BHK_Type__c,
            'budget_range'      => l.Budget_Range__c,
            'property_type'     => l.Property_Type__c,
            'purpose'           => l.Purchase_Purpose__c,
            'timeline'          => l.Purchase_Timeline__c,
            'status'            => l.Lead_Status__c,
            'pre_sales_status'  => l.PreSales_Status__c,
            'lead_type'         => l.Lead_Type__c,
            'score'             => l.Lead_Score__c,
            'tier'              => l.Lead_Score_Tier__c,
            'source'            => l.Lead_Source__c,
            'sub_source'        => l.Lead_Sub_Source__c,
            'owner_id'          => l.Owner__c,
            'pre_sale_user_id'  => l.Pre_Sale_User__c,
            'last_notes'        => l.Last_Notes__c,
            'preferred_language'=> l.Preferred_Language__c,
            'created_date'      => l.CreatedDate,
            'last_modified_date'=> l.LastModifiedDate
        };

        // Recent follow-ups
        List<Map<String, Object>> followups = new List<Map<String, Object>>();
        for (Followup__c f : [
            SELECT Id, Subject__c, Status__c, Due_Date__c, Completed_Date__c, Notes__c
            FROM Followup__c
            WHERE Lead__c = :leadId
            ORDER BY CreatedDate DESC
            LIMIT :HISTORY_LIMIT
        ]) {
            followups.add(new Map<String, Object>{
                'id'           => f.Id,
                'subject'      => f.Subject__c,
                'status'       => f.Status__c,
                'due_date'     => f.Due_Date__c,
                'completed'    => f.Completed_Date__c,
                'notes'        => f.Notes__c
            });
        }
        ctx.put('recent_followups', followups);

        // Recent site visits
        List<Map<String, Object>> visits = new List<Map<String, Object>>();
        for (Site_Visit__c sv : [
            SELECT Id, Name, Scheduled_Date__c, Status__c, Visit_Status__c,
                   Project__r.Name, Mode_Of_Visit__c, FeedBack__c
            FROM Site_Visit__c
            WHERE Lead__c = :leadId
            ORDER BY Scheduled_Date__c DESC
            LIMIT :HISTORY_LIMIT
        ]) {
            visits.add(new Map<String, Object>{
                'id'           => sv.Id,
                'display_id'   => sv.Name,
                'scheduled_at' => sv.Scheduled_Date__c,
                'status'       => sv.Status__c,
                'visit_status' => sv.Visit_Status__c,
                'project'      => sv.Project__r != null ? sv.Project__r.Name : null,
                'mode'         => sv.Mode_Of_Visit__c,
                'feedback'     => sv.FeedBack__c
            });
        }
        ctx.put('recent_site_visits', visits);

        // Recent cost sheets
        List<Map<String, Object>> costSheets = new List<Map<String, Object>>();
        for (Cost_Sheet__c cs : [
            SELECT Id, Name, Status__c, Unit__r.Unit_Number__c, Unit__r.BHK_Type__c,
                   Base_Price__c, Total_Discount__c
            FROM Cost_Sheet__c
            WHERE Lead__c = :leadId
            ORDER BY CreatedDate DESC
            LIMIT :HISTORY_LIMIT
        ]) {
            costSheets.add(new Map<String, Object>{
                'id'              => cs.Id,
                'display_id'      => cs.Name,
                'status'          => cs.Status__c,
                'unit_no'         => cs.Unit__r != null ? cs.Unit__r.Unit_Number__c : null,
                'bhk'             => cs.Unit__r != null ? cs.Unit__r.BHK_Type__c : null,
                'base_price'      => cs.Base_Price__c,
                'total_discount'  => cs.Total_Discount__c
            });
        }
        ctx.put('recent_cost_sheets', costSheets);

        return ctx;
    }

    // ════════════════════════════════════════════════════════════
    // NEXT BEST ACTION
    // ════════════════════════════════════════════════════════════

    /**
     * @description Stage + score driven NBA suggestion. Returns a simple
     *              recommendation string plus structured action hint so Aria
     *              can both explain and offer a quick-action card in the UI.
     */
    public static Map<String, Object> getNextBestAction(Id leadId) {
        Map<String, Object> ctx = getLeadContext(leadId);
        if (ctx == null) {
            return new Map<String, Object>{
                'suggestion' => 'Lead not found.',
                'action'     => null
            };
        }

        String status = (String) ctx.get('status');
        List<Map<String, Object>> visits = (List<Map<String, Object>>) ctx.get('recent_site_visits');
        List<Map<String, Object>> sheets = (List<Map<String, Object>>) ctx.get('recent_cost_sheets');

        Map<String, Object> result = new Map<String, Object>{
            'lead_id' => leadId,
            'tier'    => ctx.get('tier')
        };

        if (visits == null || visits.isEmpty()) {
            result.put('suggestion',
                'No site visit on record. Offer to schedule one — this is the single biggest '
              + 'conversion driver for this lead stage.');
            result.put('action', 'schedule_site_visit');
            return result;
        }

        if (sheets == null || sheets.isEmpty()) {
            result.put('suggestion',
                'Site visit complete but no cost sheet shared. Draft a cost sheet for the '
              + 'lead\'s preferred BHK / budget range to move toward booking.');
            result.put('action', 'generate_cost_sheet');
            return result;
        }

        // Has cost sheet already — push toward booking / follow-up
        if ('Booked'.equalsIgnoreCase(status)) {
            result.put('suggestion', 'Lead is booked. Nothing else required.');
            result.put('action', null);
            return result;
        }

        result.put('suggestion',
            'Lead has received a cost sheet but has not booked. Schedule a follow-up call '
          + 'to understand objections (price, payment plan, timing) and apply the appropriate '
          + 'handling from the Aria playbook.');
        result.put('action', 'schedule_followup');
        return result;
    }
}