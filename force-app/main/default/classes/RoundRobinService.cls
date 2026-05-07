/**
 * ════════════════════════════════════════════════════════════════════════════
 * RoundRobinService
 * ════════════════════════════════════════════════════════════════════════════
 * Enterprise Dynamic Round Robin Assignment Engine — business logic layer.
 *
 * Architecture (4-step pipeline):
 *   1. QUERY   — RoundRobinSelector loads ALL active buckets with ALL active
 *                members and ALL filters.  No Assignment_Type__c filter in SOQL.
 *   2. MATCH   — findBestMatchingBucket() evaluates each bucket's filters against
 *                the Lead via sObject.get().  ALL matching buckets are scored by
 *                sum of Field_Priority__c — highest score wins (most specific).
 *                Member pool is NOT considered during matching.
 *   3. FILTER  — filterMembersByType() narrows the matched bucket's members
 *                to the requested Assignment_Type__c in Apex code.
 *   4. ROTATE  — getNextRotationIndex() finds the member with the latest
 *                Last_Assigned__c and advances +1 (modular wrap).
 *                Assigns the selected User Id to Lead.OwnerId.
 *
 * Two entry modes:
 *   • getNextUser()          — single-lead, immediate DML  (GRE controller)
 *   • assignLeads()          — bulk, deferred DML          (trigger handler)
 *     commitPendingUpdates() — flushes deferred DML        (after-insert)
 *
 * Governor cost:
 *   • getNextUser:  1 SOQL (selector) + 1 DML (member update)
 *   • assignLeads:  1 SOQL (selector) + 0 DML (deferred)
 *   • commit:       0 SOQL + 1 DML (member updates)
 *
 * Dynamic priority via Field_Priority__c (no manual Total_Priority__c).
 * No hardcoded field names.
 * No Assignment_Type filter in SOQL.  Fully dynamic and bulk-safe.
 * ════════════════════════════════════════════════════════════════════════════
 */
public without sharing class RoundRobinService {

    // ════════════════════════════════════════════════════════════════════
    //  DEFERRED DML BUFFER (used by trigger path only)
    // ════════════════════════════════════════════════════════════════════

    @TestVisible
    private static List<Round_Robin_Member__c> pendingMemberUpdates = new List<Round_Robin_Member__c>();

    // ════════════════════════════════════════════════════════════════════
    //  PUBLIC: Single-lead entry (GRE controller path)
    // ════════════════════════════════════════════════════════════════════

    /**
     * Returns the next User Id from the best matching bucket for this lead.
     * Performs IMMEDIATE DML to update the member's Last_Assigned__c.
     *
     * Call this from imperative Apex controllers (NOT from triggers).
     *
     * @param leadRecord      Fully-populated Lead__c (Project__c, Lead_Source__c, etc.)
     *                        Does NOT need to be inserted yet.
     * @param assignmentType  Picklist value: 'Sales', 'Pre Sales', etc.
     * @return                User Id of the assigned member, or null if no match
     */
    public static Id getNextUser(Lead__c leadRecord, String assignmentType) {
        if (leadRecord == null || String.isBlank(assignmentType)) return null;

        // Step 1: Query
        List<Round_Robin__c> buckets = RoundRobinSelector.getActiveBucketsWithChildren();
        if (buckets.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'RoundRobinService.getNextUser: No active Round Robin buckets found.');
            return null;
        }

        // Step 2: Match bucket by filters (independent of member type)
        Round_Robin__c match = findBestMatchingBucket(leadRecord, buckets);
        if (match == null) {
            System.debug(LoggingLevel.WARN, 'RoundRobinService.getNextUser: No matching bucket for lead. Buckets evaluated: ' + buckets.size());
            return null;
        }

        // Step 3: Filter to requested member type
        List<Round_Robin_Member__c> pool = filterMembersByType(
            match.Round_Robin_Members__r, assignmentType
        );
        if (pool.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'RoundRobinService.getNextUser: Bucket "' + match.Name + '" matched but no active members for type "' + assignmentType + '".');
            return null;
        }

        // Step 4: Rotate
        Integer nextIdx = getNextRotationIndex(pool);
        Id assignedUserId = pool[nextIdx].User__c;

        System.debug(LoggingLevel.INFO, 'RoundRobinService.getNextUser: Assigned User ' + assignedUserId + ' from bucket "' + match.Name + '" (index ' + nextIdx + ')');

        // Immediate DML — safe because we are NOT in a trigger context
        update new Round_Robin_Member__c(
            Id = pool[nextIdx].Id,
            Last_Assigned__c = DateTime.now()
        );

        return assignedUserId;
    }

    /**
     * Backward-compatible overload: creates a temp Lead with just the projectId.
     * NOTE: This will only match buckets whose ONLY filter is Project__c.
     * For full filter matching, prefer the Lead__c overload.
     */
    public static Id getNextUser(Id projectId, String assignmentType) {
        Lead__c tempLead = new Lead__c(Project__c = projectId);
        return getNextUser(tempLead, assignmentType);
    }

    // ════════════════════════════════════════════════════════════════════
    //  PUBLIC: Bulk entry (trigger handler path)
    // ════════════════════════════════════════════════════════════════════

    /**
     * Assigns OwnerId on each Lead by matching against Round Robin buckets
     * and rotating through active members of the specified type.
     *
     * DEFERRED DML: member timestamp updates are buffered in
     * pendingMemberUpdates.  Call commitPendingUpdates() from AFTER INSERT.
     *
     * Leads with OwnerId already set to a user other than the running user
     * are SKIPPED (e.g. GRE pre-assigned).
     *
     * @param leads            List of Lead__c (will be mutated: OwnerId set)
     * @param assignmentType   'Pre Sales', 'Sales', etc.
     */
    public static void assignLeads(List<Lead__c> leads, String assignmentType) {
        if (leads == null || leads.isEmpty() || String.isBlank(assignmentType)) return;
        pendingMemberUpdates.clear();

        // Step 1: Query
        List<Round_Robin__c> buckets = RoundRobinSelector.getActiveBucketsWithChildren();
        if (buckets.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'RoundRobinService.assignLeads: No active Round Robin buckets found. Exiting.');
            return;
        }
        System.debug(LoggingLevel.INFO, 'RoundRobinService.assignLeads: Found ' + buckets.size() + ' active bucket(s). Assignment type: ' + assignmentType);

        // Per-bucket rotation pointers for batch fairness
        Map<Id, Integer> rotation = new Map<Id, Integer>();
        // Cache of filtered member pools per bucket (avoid re-filtering)
        Map<Id, List<Round_Robin_Member__c>> poolCache = new Map<Id, List<Round_Robin_Member__c>>();

        for (Lead__c ld : leads) {
            // Skip leads pre-assigned upstream (e.g. GRE sets OwnerId before insert).
            // In before-insert context, OwnerId defaults to the running user,
            // so only skip when explicitly set to a DIFFERENT user.
            if (ld.OwnerId != null && ld.OwnerId != UserInfo.getUserId()) continue;

            // Step 2: Match bucket by filters
            Round_Robin__c match = findBestMatchingBucket(ld, buckets);
            if (match == null) {
                System.debug(LoggingLevel.WARN, 'RoundRobinService.assignLeads: No matching bucket for lead. Project__c=' + ld.get('Project__c'));
                continue;
            }

            // Step 3: Filter to requested member type (cached per bucket)
            List<Round_Robin_Member__c> pool;
            if (poolCache.containsKey(match.Id)) {
                pool = poolCache.get(match.Id);
            } else {
                pool = filterMembersByType(match.Round_Robin_Members__r, assignmentType);
                poolCache.put(match.Id, pool);
            }
            if (pool.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'RoundRobinService.assignLeads: Bucket "' + match.Name + '" matched but no active members for type "' + assignmentType + '". Total members in bucket: ' + match.Round_Robin_Members__r.size());
                continue;
            }

            // Seed rotation for this bucket if first time
            if (!rotation.containsKey(match.Id)) {
                rotation.put(match.Id, getNextRotationIndex(pool));
            }

            Integer idx = rotation.get(match.Id);

            // Assign the lead to the next member in rotation
            ld.OwnerId = pool[idx].User__c;

            System.debug(LoggingLevel.INFO, 'RoundRobinService.assignLeads: Assigned Lead to User ' + pool[idx].User__c + ' from bucket "' + match.Name + '" (index ' + idx + ')');

            // Buffer member timestamp update (committed in after-insert)
            pendingMemberUpdates.add(new Round_Robin_Member__c(
                Id = pool[idx].Id,
                Last_Assigned__c = DateTime.now()
            ));

            // Advance rotation pointer for next lead in this batch
            rotation.put(match.Id, Math.mod(idx + 1, pool.size()));
        }
    }

    /**
     * Flushes the deferred member updates buffered by assignLeads().
     * Call from LeadTrigger AFTER INSERT.
     *
     * Deduplicates: if the same member was assigned multiple leads in one
     * batch, only the latest timestamp is persisted (last-one-wins).
     */
    public static void commitPendingUpdates() {
        if (pendingMemberUpdates.isEmpty()) return;

        Map<Id, Round_Robin_Member__c> deduped = new Map<Id, Round_Robin_Member__c>();
        for (Round_Robin_Member__c m : pendingMemberUpdates) {
            deduped.put(m.Id, m);
        }
        update deduped.values();
        pendingMemberUpdates.clear();
    }

    // ════════════════════════════════════════════════════════════════════
    //  PRIVATE: Dynamic Filter Matching  (Step 2)
    // ════════════════════════════════════════════════════════════════════

    /**
     * Evaluates EVERY bucket's filters against the Lead and returns the
     * best matching bucket.  This is the DYNAMIC PRIORITY engine.
     *
     * Algorithm — "Most Specific Rule First":
     *   1. For each bucket, count how many filters match the Lead via sObject.get()
     *   2. At least ONE filter must match for the bucket to be considered
     *   3. Primary sort:   match count (higher wins — more matching criteria)
     *   4. Secondary sort: fewer total filters wins (higher match % = tighter fit)
     *   5. Tertiary sort:  sum of matched Field_Priority__c (higher wins)
     *
     * Example 1 — Lead with Project + Zone (no Residency):
     *   Bucket A: Project__c=XYZ                                    → 1/1 match
     *   Bucket B: Project__c=XYZ + Zone__c=Chennai + Residency=NRI  → 2/3 match
     *   → B wins (2 matches > 1 match)
     *
     * Example 2 — Lead with Project only:
     *   Bucket A: Project__c=XYZ                                    → 1/1 match (100%)
     *   Bucket B: Project__c=XYZ + Zone__c=Chennai + Residency=NRI  → 1/3 match (33%)
     *   → A wins (same match count, but A has higher match % → fewer total filters)
     *
     * @return The best matching Round_Robin__c, or null if no filters match any bucket
     */
    @TestVisible
    private static Round_Robin__c findBestMatchingBucket(Lead__c ld, List<Round_Robin__c> buckets) {
        Round_Robin__c best = null;
        Integer bestMatchCount = 0;
        Integer bestFilterCount = 2147483647; // Start high so first match always wins
        Decimal bestScore = -1;

        for (Round_Robin__c b : buckets) {
            List<Round_Robin_Filter__c> filters = b.Round_Robin_Filters__r;
            if (filters == null || filters.isEmpty()) continue;

            Integer matchCount = 0;
            Decimal score = 0;

            for (Round_Robin_Filter__c f : filters) {
                Object rawVal = ld.get(f.Field_API_Name__c);
                String strVal = (rawVal != null) ? String.valueOf(rawVal) : null;

                if (strVal != null && strVal == f.Field_Value__c) {
                    matchCount++;
                    score += (f.Field_Priority__c != null) ? f.Field_Priority__c : 0;
                }
            }

            // At least one filter must match for the bucket to be considered
            if (matchCount == 0) continue;

            // Most specific match wins:
            //   1. More matching filters = better fit for this lead
            //   2. On tie: FEWER total filters = higher match % = tighter fit
            //      (1/1 = 100% match beats 1/3 = 33% match)
            //   3. On tie: higher priority score = configured tiebreaker
            if (matchCount > bestMatchCount
                || (matchCount == bestMatchCount && filters.size() < bestFilterCount)
                || (matchCount == bestMatchCount && filters.size() == bestFilterCount && score > bestScore)) {
                best = b;
                bestMatchCount = matchCount;
                bestFilterCount = filters.size();
                bestScore = score;
            }
        }

        return best;
    }

    // ════════════════════════════════════════════════════════════════════
    //  PRIVATE: Member Filtering  (Step 3)
    // ════════════════════════════════════════════════════════════════════

    /**
     * Filters the full member list to only those with the requested
     * Assignment_Type__c AND whose User is currently available and working.
     *
     * Availability check uses User.Availability__c and User.is_working__c
     * (set by the User Availability Manager component).  Members whose User
     * is not working or not available are skipped from the rotation pool.
     */
    @TestVisible
    private static List<Round_Robin_Member__c> filterMembersByType(
        List<Round_Robin_Member__c> allMembers, String assignmentType
    ) {
        List<Round_Robin_Member__c> available = new List<Round_Robin_Member__c>();
        List<Round_Robin_Member__c> allOfType = new List<Round_Robin_Member__c>();
        if (allMembers == null) return available;

        for (Round_Robin_Member__c m : allMembers) {
            if (m.Assignment_Type__c != assignmentType) continue;

            allOfType.add(m);

            // Skip users who are not working or not available
            if (m.User__r != null
                && (m.User__r.is_working__c == false || m.User__r.Availability__c == false)) {
                continue;
            }

            available.add(m);
        }

        // Fallback: if no available members, use all active members of this type
        // so leads never stay with admin as owner
        if (available.isEmpty() && !allOfType.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'filterMembersByType: No available members for type "' + assignmentType
                + '". Falling back to all ' + allOfType.size() + ' active member(s) regardless of availability.');
            return allOfType;
        }
        return available;
    }

    // ════════════════════════════════════════════════════════════════════
    //  PRIVATE: Rotation  (Step 4)
    // ════════════════════════════════════════════════════════════════════

    /**
     * True round-robin rotation via Last_Assigned__c timestamp.
     *
     * Algorithm:
     *   1. Scan pool for the member with the LATEST Last_Assigned__c
     *   2. The next member = (that index + 1) mod pool.size()
     *   3. If no member has ever been assigned, start at index 0
     *
     * Members are pre-sorted by Order__c ASC from the SOQL query,
     * so the rotation follows the configured member order.
     */
    @TestVisible
    private static Integer getNextRotationIndex(List<Round_Robin_Member__c> pool) {
        Integer lastIdx = -1;
        DateTime latest = null;

        for (Integer i = 0; i < pool.size(); i++) {
            DateTime ts = pool[i].Last_Assigned__c;
            if (ts != null && (latest == null || ts > latest)) {
                latest = ts;
                lastIdx = i;
            }
        }

        return (lastIdx < 0) ? 0 : Math.mod(lastIdx + 1, pool.size());
    }
}