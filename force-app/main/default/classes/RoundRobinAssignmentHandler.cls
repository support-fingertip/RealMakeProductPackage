/**
 * ════════════════════════════════════════════════════════════════════════════
 * RoundRobinAssignmentHandler
 * ════════════════════════════════════════════════════════════════════════════
 * Thin trigger handler that delegates ALL logic to RoundRobinService.
 *
 * This class exists solely to:
 *   1. Provide the trigger entry points (assignOwners / commitRotationUpdates)
 *   2. Define the default assignment type for trigger-based leads ('Pre Sales')
 *   3. Keep the LeadTrigger wiring unchanged
 *
 * ALL business logic (query, filter matching, member selection, rotation)
 * lives in RoundRobinService.  ALL SOQL lives in RoundRobinSelector.
 *
 * TRIGGER WIRING (unchanged):
 *   BEFORE INSERT:
 *     RoundRobinAssignmentHandler.assignOwners(Trigger.new);
 *   AFTER INSERT:
 *     RoundRobinAssignmentHandler.commitRotationUpdates();
 *
 * Governor cost: 1 SOQL (before) + 1 DML (after) — delegated to Service.
 * ════════════════════════════════════════════════════════════════════════════
 */
public without sharing class RoundRobinAssignmentHandler {

    /**
     * Default assignment type for leads created via triggers (web forms,
     * imports, API, etc.).  GRE leads use 'Sales' and are handled by
     * GREWalkInController → RoundRobinService.getNextUser() directly.
     */
    @TestVisible
    private static final String DEFAULT_ASSIGNMENT_TYPE = 'Pre Sales';

    /**
     * Profiles whose users create leads manually.  When the running user
     * belongs to one of these profiles the trigger-level Round Robin is
     * skipped so the lead stays assigned to its creator.
     */
    @TestVisible
    private static final Set<String> MANUAL_CREATOR_PROFILES = new Set<String>{
        'Sales Executive', 'Pre-Sales Executive'
    };

    /** Cached running-user profile name (queried at most once per txn). */
    @TestVisible
    private static String runningUserProfileName;

    @TestVisible
    private static String getRunningUserProfileName() {
        if (runningUserProfileName == null) {
            runningUserProfileName = [
                SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId()
            ].Profile.Name;
        }
        return runningUserProfileName;
    }

    // ════════════════════════════════════════════════════════════════════
    //  PHASE 1 — BEFORE INSERT  (sets OwnerId on Trigger.new)
    // ════════════════════════════════════════════════════════════════════

    /**
     * Called from LeadTrigger BEFORE INSERT.
     *
     * Delegates to RoundRobinService.assignLeads() which:
     *   1. Queries all active buckets (via RoundRobinSelector)
     *   2. Matches each lead to the best bucket via dynamic filters
     *   3. Filters members to 'Pre Sales' type in Apex code
     *   4. Rotates and sets ld.OwnerId
     *   5. Buffers member timestamp updates for Phase 2
     *
     * Leads with OwnerId already set (e.g. GRE pre-assigned) are skipped.
     * Round Robin is also skipped entirely when the running user is a
     * Sales or Pre-Sales user (manual lead creation keeps the creator).
     */
    public static void assignOwners(List<Lead__c> newLeads) {
        if (newLeads == null || newLeads.isEmpty()) return;

        // Manual creation: Sales / Pre-Sales users keep ownership
        if (MANUAL_CREATOR_PROFILES.contains(getRunningUserProfileName())) {
            return;
        }

        RoundRobinService.assignLeads(newLeads, DEFAULT_ASSIGNMENT_TYPE);
    }

    // ════════════════════════════════════════════════════════════════════
    //  PHASE 2 — AFTER INSERT  (persists rotation tracking)
    // ════════════════════════════════════════════════════════════════════

    /**
     * Called from LeadTrigger AFTER INSERT.
     * Flushes the member Last_Assigned__c updates buffered during Phase 1.
     */
    public static void commitRotationUpdates() {
        RoundRobinService.commitPendingUpdates();
    }
}