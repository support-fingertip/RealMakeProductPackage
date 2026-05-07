/**
 * @description Universal Site Visit creation service.
 * Handles both same-project and cross-project scenarios transparently.
 *
 * Decision matrix:
 * ┌──────────────────────────────────────┬──────────────────────┬─────────────────────────────────┐
 * │ Scenario                             │ SV Assignment        │ Sharing                         │
 * ├──────────────────────────────────────┼──────────────────────┼─────────────────────────────────┤
 * │ SAME PROJECT                         │ Lead Owner           │ None needed                     │
 * │ CROSS PROJECT + owner in RR pool     │ Lead Owner           │ None extra needed               │
 * │ CROSS PROJECT + owner NOT in RR pool │ RR assignment (Sales)│ Lead→SV assignee, SV→lead owner │
 * └──────────────────────────────────────┴──────────────────────┴─────────────────────────────────┘
 */
public with sharing class SiteVisitCreationService {

    private static final String CROSS_PROJECT_ASSIGNMENT_TYPE = 'Sales';

    /**
     * @description Create a site visit for a lead on the specified project.
     * Backend auto-detects same vs cross-project and applies the correct logic.
     */
    public static SiteVisitResult createSiteVisit(
        Id leadId, Id selectedProjectId, DateTime scheduledDate,
        String visitType, String sourceType, Boolean needPickUp
    ) {
        if (leadId == null || selectedProjectId == null || scheduledDate == null) {
            throw new SiteVisitCreationException('Lead, Project, and Scheduled Date are required.');
        }

        // Step 1: Query lead
        Lead__c lead = [
            SELECT Id, Project__c, Owner__c, Name
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        Boolean isCrossProject = (selectedProjectId != lead.Project__c);
        Id assignedTo = lead.Owner__c;
        Boolean wasRoundRobinUsed = false;

        // Step 2: Determine assignment
        if (isCrossProject) {
            Boolean ownerInPool = isUserInProjectRRPool(lead.Owner__c, selectedProjectId);

            if (!ownerInPool) {
                // RR assignment for cross-project
                Id rrAssignee = RoundRobinService.getNextUser(selectedProjectId, CROSS_PROJECT_ASSIGNMENT_TYPE);
                if (rrAssignee != null) {
                    assignedTo = rrAssignee;
                    wasRoundRobinUsed = true;
                }
                // If RR returns null (no matching bucket), fall back to lead owner
            }
        }

        // Step 3: Insert Site Visit
        Site_Visit__c sv = new Site_Visit__c();
        sv.Lead__c = leadId;
        sv.Project__c = selectedProjectId;
        sv.Scheduled_Date__c = scheduledDate;
        sv.Status__c = 'Scheduled';
        String modeOfVisit = String.isNotBlank(visitType) ? visitType : 'On Site';
        sv.Mode_Of_Visit__c = modeOfVisit;
        sv.Source_Type__c = String.isNotBlank(sourceType) ? sourceType : 'Digital (Own)';
        sv.Need_Pick_Up_Assistance__c = needPickUp == true;
        sv.Assigned_To__c = assignedTo;
        sv.Is_Cross_Project__c = isCrossProject;
        insert sv;

        // Step 4: Apply sharing (only for cross-project with RR assignment)
        if (isCrossProject && wasRoundRobinUsed && assignedTo != lead.Owner__c) {
            // Share Lead with SV assignee (Read) so they can see the customer
            SharingUtility.shareLeadsWithUser(
                new List<Id>{ leadId }, assignedTo, 'Read'
            );
            // Share SV with lead owner (Read) so they can track the visit
            SharingUtility.shareSiteVisitsWithUser(
                new List<Id>{ sv.Id }, lead.Owner__c, 'Read'
            );
        }

        // Step 5: Build result
        SiteVisitResult result = new SiteVisitResult();
        result.siteVisitId = sv.Id;
        result.assignedToUserId = assignedTo;
        result.isCrossProject = isCrossProject;
        result.wasRoundRobinUsed = wasRoundRobinUsed;

        // Resolve assignee name
        List<User> assigneeUsers = [SELECT Name FROM User WHERE Id = :assignedTo LIMIT 1];
        result.assignedToName = assigneeUsers.isEmpty() ? 'Unknown' : assigneeUsers[0].Name;

        if (!isCrossProject) {
            result.message = 'Site Visit scheduled';
        } else if (wasRoundRobinUsed) {
            result.message = 'Cross-project Site Visit scheduled';
        } else {
            result.message = 'Cross-project Site Visit scheduled.(in project pool).';
        }

        return result;
    }

    /**
     * @description Check if a user is in the Round Robin pool for a specific project.
     * Uses RoundRobinSelector to load all active buckets and checks if any bucket
     * with a Project__c filter matching the target project has this user as a member.
     */
    public static Boolean isUserInProjectRRPool(Id userId, Id targetProjectId) {
        if (userId == null || targetProjectId == null) return false;

        List<Round_Robin__c> buckets = RoundRobinSelector.getActiveBucketsWithChildren();

        for (Round_Robin__c bucket : buckets) {
            // Check if this bucket has a filter for the target project
            Boolean matchesProject = false;
            if (bucket.Round_Robin_Filters__r != null) {
                for (Round_Robin_Filter__c f : bucket.Round_Robin_Filters__r) {
                    if (f.Field_API_Name__c == 'Project__c'
                        && f.Field_Value__c == String.valueOf(targetProjectId)) {
                        matchesProject = true;
                        break;
                    }
                }
            }

            if (!matchesProject) continue;

            // Check if user is an active member of this bucket
            if (bucket.Round_Robin_Members__r != null) {
                for (Round_Robin_Member__c m : bucket.Round_Robin_Members__r) {
                    if (m.User__c == userId) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    // ════════════════════════════════════════════════════════════
    // RESULT DTO
    // ════════════════════════════════════════════════════════════

    public class SiteVisitResult {
        @AuraEnabled public Id siteVisitId;
        @AuraEnabled public Id assignedToUserId;
        @AuraEnabled public String assignedToName;
        @AuraEnabled public Boolean isCrossProject;
        @AuraEnabled public Boolean wasRoundRobinUsed;
        @AuraEnabled public String message;
    }

    public class SiteVisitCreationException extends Exception {}
}