/**
 * @description Handler for Campaign trigger operations.
 * Validates Campaign status transitions per business lifecycle rules.
 *
 * Valid transitions:
 *   Planned   → Started
 *   Started   → Hold, Completed, Cancelled
 *   Hold      → Started (resume)
 *   Completed → (terminal - no transitions allowed)
 *   Cancelled → (terminal - no transitions allowed)
 */
public with sharing class CampaignTriggerHandler {

    // Define allowed status transitions: key = current status, value = set of allowed next statuses
    private static final Map<String, Set<String>> VALID_TRANSITIONS = new Map<String, Set<String>>{
        'Planned'   => new Set<String>{ 'Started', 'Cancelled' },
        'Started'   => new Set<String>{ 'Hold', 'Completed', 'Cancelled' },
        'Hold'      => new Set<String>{ 'Started', 'Cancelled' },
        'Completed' => new Set<String>(),
        'Cancelled' => new Set<String>()
    };

    /**
     * @description Validate that status changes follow the defined lifecycle.
     * Adds error to the record if an invalid transition is attempted.
     */
    public static void validateStatusTransitions(List<Campaign__c> newRecords, Map<Id, Campaign__c> oldMap) {
        for (Campaign__c camp : newRecords) {
            Campaign__c oldCamp = oldMap.get(camp.Id);

            // Only validate if Status changed
            if (camp.Status__c == oldCamp.Status__c) {
                continue;
            }

            String oldStatus = oldCamp.Status__c;
            String newStatus = camp.Status__c;

            Set<String> allowed = VALID_TRANSITIONS.get(oldStatus);

            if (allowed == null || !allowed.contains(newStatus)) {
                camp.Status__c.addError(
                    'Invalid status transition: ' + oldStatus + ' → ' + newStatus +
                    '. Allowed transitions from ' + oldStatus + ': ' +
                    (allowed != null && !allowed.isEmpty() ? String.join(new List<String>(allowed), ', ') : 'None (terminal state)')
                );
            }
        }
    }
}