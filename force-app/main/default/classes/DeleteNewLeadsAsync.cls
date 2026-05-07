/**
 * @deprecated No longer enqueued from LeadTrigger. Duplicate lead deletion
 * is now handled by the leadDuplicateRedirector LWC (real-time) and the
 * CleanupDuplicateLeadsBatch scheduled job (safety net). This class is kept
 * to avoid breaking any existing references.
 */
public class DeleteNewLeadsAsync implements Queueable {

    private List<Id> newLeadIds;

    public DeleteNewLeadsAsync(List<Id> leadIds) {
        this.newLeadIds = leadIds;
    }

    public void execute(QueueableContext context) {

        if (newLeadIds == null || newLeadIds.isEmpty()) {
            return;
        }

        try {

            // First query the Leads
            List<Lead__c> leadsToDelete = [
                SELECT Id
                FROM Lead__c
                WHERE Id IN :newLeadIds
            ];

            if (!leadsToDelete.isEmpty()) {
                delete leadsToDelete;
            }

            System.debug('Successfully deleted ' + leadsToDelete.size() + ' new Lead records');

        } catch (Exception e) {

            System.debug('Error deleting new Lead records: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
    }
}