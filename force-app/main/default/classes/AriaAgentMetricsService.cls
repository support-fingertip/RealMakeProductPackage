/**
 * @description Agent-centric metrics for Aria.
 *
 * All queries are scoped to the running user (OwnerId / Assigned_To / Created_By)
 * so a sales exec sees only their own numbers.
 *
 * Tools:
 *   - myPerformance(rangeDays)   — leads / visits / sheets / bookings + conv rate
 *   - getOverdueFollowups()      — follow-ups past due
 *   - getStaleLeads(days)        — leads with no child activity in N days
 *   - explainLeadScore(leadId)   — which Lead_Score_Rule__c rules fired
 *   - getWelcomeMetrics()        — compact dashboard for the chat welcome screen
 */
public with sharing class AriaAgentMetricsService {

    private static final Id ME = UserInfo.getUserId();

    // ════════════════════════════════════════════════════════════
    // MY PERFORMANCE
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> myPerformance(Integer rangeDays) {
        if (rangeDays == null || rangeDays <= 0) rangeDays = 30;
        DateTime since = DateTime.now().addDays(-rangeDays);

        Integer leads = [
            SELECT COUNT() FROM Lead__c
            WHERE (Owner__c = :ME OR OwnerId = :ME) AND CreatedDate >= :since
        ];
        Integer visits = [
            SELECT COUNT() FROM Site_Visit__c
            WHERE (Assigned_To__c = :ME
                   OR OwnerId = :ME
                   OR Lead__r.Owner__c = :ME
                   OR Lead__r.OwnerId = :ME)
              AND CreatedDate >= :since
        ];
        Integer costSheets = [
            SELECT COUNT() FROM Cost_Sheet__c
            WHERE Created_By__c = :ME AND CreatedDate >= :since
        ];
        Integer bookings = [
            SELECT COUNT() FROM Booking__c
            WHERE (Owner__c = :ME OR OwnerId = :ME) AND CreatedDate >= :since
        ];

        Decimal convRate = leads > 0
            ? Decimal.valueOf(bookings).divide(leads, 4) * 100
            : 0;

        return new Map<String, Object>{
            'range_days'     => rangeDays,
            'since'          => since,
            'leads_created'  => leads,
            'site_visits'    => visits,
            'cost_sheets'    => costSheets,
            'bookings'       => bookings,
            'conversion_rate_pct' => convRate.setScale(1),
            'user_name'      => UserInfo.getName()
        };
    }

    // ════════════════════════════════════════════════════════════
    // OVERDUE FOLLOW-UPS
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> getOverdueFollowups() {
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        for (Followup__c f : [
            SELECT Id, Name, Subject__c, Due_Date__c, Lead__c, Lead__r.Name,
                   Lead__r.Full_Name__c, Lead__r.Primary_Mobile__c
            FROM Followup__c
            WHERE (Assigned_To__c = :ME
                   OR Lead__r.Owner__c = :ME
                   OR Lead__r.OwnerId = :ME)
              AND Status__c = 'Pending'
              AND Due_Date__c < :DateTime.now()
            ORDER BY Due_Date__c ASC
            LIMIT 20
        ]) {
            items.add(new Map<String, Object>{
                'id'          => f.Id,
                'subject'     => f.Subject__c,
                'due_date'    => f.Due_Date__c,
                'lead_id'     => f.Lead__c,
                'lead_name'   => f.Lead__r != null ? f.Lead__r.Name : null,
                'customer'    => f.Lead__r != null ? f.Lead__r.Full_Name__c : null,
                'mobile'      => f.Lead__r != null ? f.Lead__r.Primary_Mobile__c : null
            });
        }
        return new Map<String, Object>{
            'count' => items.size(),
            'items' => items
        };
    }

    // ════════════════════════════════════════════════════════════
    // STALE LEADS (no recent child activity)
    // ════════════════════════════════════════════════════════════

    public static Map<String, Object> getStaleLeads(Integer days) {
        if (days == null || days <= 0) days = 7;
        DateTime cutoff = DateTime.now().addDays(-days);

        List<Map<String, Object>> items = new List<Map<String, Object>>();
        for (Lead__c l : [
            SELECT Id, Name, Full_Name__c, Primary_Mobile__c,
                   Lead_Status__c, Lead_Score_Tier__c, LastModifiedDate
            FROM Lead__c
            WHERE (Owner__c = :ME OR OwnerId = :ME)
              AND LastModifiedDate < :cutoff
              AND Lead_Status__c NOT IN ('Booked', 'Closed Lost', 'Unqualified', 'Rejected')
            ORDER BY LastModifiedDate ASC
            LIMIT 20
        ]) {
            items.add(new Map<String, Object>{
                'id'              => l.Id,
                'lead_name'       => l.Name,
                'customer'        => l.Full_Name__c,
                'mobile'          => l.Primary_Mobile__c,
                'status'          => l.Lead_Status__c,
                'tier'            => l.Lead_Score_Tier__c,
                'last_modified'   => l.LastModifiedDate
            });
        }
        return new Map<String, Object>{
            'days'  => days,
            'count' => items.size(),
            'items' => items
        };
    }

    // ════════════════════════════════════════════════════════════
    // EXPLAIN LEAD SCORE
    // ════════════════════════════════════════════════════════════

    /**
     * @description Shows the lead's current score, tier and which scoring rules
     *              exist in the org so the exec can understand why the lead
     *              scored low/high. The scoring engine evaluates rules in the
     *              trigger — this method is read-only.
     */
    public static Map<String, Object> explainLeadScore(Id leadId) {
        if (leadId == null) {
            return new Map<String, Object>{ 'error' => 'lead_id is required' };
        }
        List<Lead__c> leads = [
            SELECT Id, Name, Full_Name__c, Lead_Score__c, Lead_Score_Tier__c,
                   Last_Score_Date__c
            FROM Lead__c WHERE Id = :leadId LIMIT 1
        ];
        if (leads.isEmpty()) {
            return new Map<String, Object>{ 'error' => 'Lead not found' };
        }
        Lead__c l = leads[0];

        List<Map<String, Object>> rules = new List<Map<String, Object>>();
        for (Lead_Score_Rule__c r : [
            SELECT Id, Name, Rule_Type__c, Field_API_Name__c, Operator__c,
                   Field_Value__c, Points__c
            FROM Lead_Score_Rule__c
            WHERE Is_Active__c = true
            ORDER BY Points__c DESC
            LIMIT 30
        ]) {
            rules.add(new Map<String, Object>{
                'rule'         => r.Name,
                'type'         => r.Rule_Type__c,
                'field'        => r.Field_API_Name__c,
                'operator'     => r.Operator__c,
                'value'        => r.Field_Value__c,
                'points'       => r.Points__c
            });
        }

        List<Map<String, Object>> tiers = new List<Map<String, Object>>();
        for (Lead_Score_Tier__c t : [
            SELECT Id, Name, Min_Score__c, Max_Score__c
            FROM Lead_Score_Tier__c
            ORDER BY Min_Score__c ASC
        ]) {
            tiers.add(new Map<String, Object>{
                'tier'      => t.Name,
                'min_score' => t.Min_Score__c,
                'max_score' => t.Max_Score__c
            });
        }

        return new Map<String, Object>{
            'lead_id'    => l.Id,
            'lead_name'  => l.Name,
            'full_name'  => l.Full_Name__c,
            'score'      => l.Lead_Score__c,
            'tier'       => l.Lead_Score_Tier__c,
            'scored_on'  => l.Last_Score_Date__c,
            'rules'      => rules,
            'tiers'      => tiers
        };
    }

    // ════════════════════════════════════════════════════════════
    // WELCOME METRICS (compact dashboard for chat opening)
    // ════════════════════════════════════════════════════════════

    @AuraEnabled
    public static Map<String, Object> getWelcomeMetrics() {
        DateTime today = DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
        DateTime tomorrow = today.addDays(1);

        // Ownership in this CRM is tracked on the custom Owner__c / Assigned_To__c
        // lookup, but data imported via standard paths often only populates the
        // built-in OwnerId. Match both so the dashboard reflects real workload.
        Integer overdueFollowups = [
            SELECT COUNT() FROM Followup__c
            WHERE (Assigned_To__c = :ME
                   OR Lead__r.Owner__c = :ME
                   OR Lead__r.OwnerId = :ME)
              AND Status__c = 'Pending'
              AND Due_Date__c < :DateTime.now()
        ];
        Integer todaySiteVisits = [
            SELECT COUNT() FROM Site_Visit__c
            WHERE (Assigned_To__c = :ME
                   OR OwnerId = :ME
                   OR Lead__r.Owner__c = :ME
                   OR Lead__r.OwnerId = :ME)
              AND Scheduled_Date__c >= :today
              AND Scheduled_Date__c < :tomorrow
              AND Status__c IN ('Scheduled', 'Re-Scheduled')
        ];
        Integer newLeadsToday = [
            SELECT COUNT() FROM Lead__c
            WHERE (Owner__c = :ME OR OwnerId = :ME)
              AND CreatedDate >= :today
        ];
        Integer staleSeven = [
            SELECT COUNT() FROM Lead__c
            WHERE (Owner__c = :ME OR OwnerId = :ME)
              AND LastModifiedDate < :DateTime.now().addDays(-7)
              AND Lead_Status__c NOT IN ('Booked', 'Closed Lost', 'Unqualified', 'Rejected')
        ];

        return new Map<String, Object>{
            'overdue_followups' => overdueFollowups,
            'site_visits_today' => todaySiteVisits,
            'new_leads_today'   => newLeadsToday,
            'stale_leads_7d'    => staleSeven
        };
    }

    // ════════════════════════════════════════════════════════════
    // LEAD METRICS (dashboard when Aria is on a Lead record page)
    // ════════════════════════════════════════════════════════════

    /**
     * @description Per-lead counts for the chat welcome dashboard when Aria
     *              is placed on a Lead record page. Shows follow-ups, site
     *              visits, cost sheets (quotes) and bookings for THIS lead.
     */
    @AuraEnabled
    public static Map<String, Object> getLeadMetrics(Id leadId) {
        if (leadId == null) return null;
        // Only apply on Lead__c pages — LWC is exposed on other objects too
        if (leadId.getSObjectType() != Lead__c.SObjectType) return null;

        Integer followups = [
            SELECT COUNT() FROM Followup__c WHERE Lead__c = :leadId
        ];
        Integer pendingFollowups = [
            SELECT COUNT() FROM Followup__c
            WHERE Lead__c = :leadId AND Status__c = 'Pending'
        ];
        Integer siteVisits = [
            SELECT COUNT() FROM Site_Visit__c WHERE Lead__c = :leadId
        ];
        Integer costSheets = [
            SELECT COUNT() FROM Cost_Sheet__c WHERE Lead__c = :leadId
        ];
        Integer bookings = [
            SELECT COUNT() FROM Booking__c WHERE Lead__c = :leadId
        ];

        // Lead display fields + booking-readiness suggestion so the LWC can
        // show a proactive greeting instead of the generic welcome text.
        String leadName = null;
        String fullName = null;
        for (Lead__c l : [
            SELECT Name, Full_Name__c FROM Lead__c WHERE Id = :leadId LIMIT 1
        ]) {
            leadName = l.Name;
            fullName = l.Full_Name__c;
        }

        Map<String, Object> readiness = null;
        try {
            readiness = AriaKnowledgeService.getBookingReadiness(leadId);
        } catch (Exception e) {
            // Fall back silently — greeting is best-effort.
        }

        return new Map<String, Object>{
            'lead_id'           => leadId,
            'lead_name'         => leadName,
            'full_name'         => fullName,
            'followups'         => followups,
            'pending_followups' => pendingFollowups,
            'site_visits'       => siteVisits,
            'cost_sheets'       => costSheets,
            'bookings'          => bookings,
            'readiness'         => readiness
        };
    }
}