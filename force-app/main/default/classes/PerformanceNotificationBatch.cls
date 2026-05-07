/**
 * @description Scheduled + Batchable Apex job for sending performance target notifications.
 *              Evaluates achievement milestones, at-risk targets, and missed targets,
 *              then sends custom notifications to assigned users.
 *
 *              Typically chained from PerformanceActualsRecalcBatch.
 */
public with sharing class PerformanceNotificationBatch implements Database.Batchable<SObject>, Schedulable {

    private static final Integer AT_RISK_DAYS_THRESHOLD = 3;
    private static final Decimal AT_RISK_ACHIEVEMENT_THRESHOLD = 0.75;

    // ── Schedulable entry point ──────────────────────────────────

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PerformanceNotificationBatch(), 200);
    }

    // ── Batchable methods ────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, Metric__c, Target_Value__c, Actual_Value__c,
                   Last_Calculated__c, Period_Start__c, Period_End__c,
                   Assignee__c, Is_Active__c, Target_Level__c
            FROM Performance_Target__c
            WHERE Is_Active__c = true
            AND Target_Level__c = 'User'
            AND Assignee__c != null
            AND Period_End__c >= TODAY
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Performance_Target__c> scope) {
        // Query notification type once for the batch chunk
        List<CustomNotificationType> notifTypes = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = 'Performance_Target_Notification'
            LIMIT 1
        ];
        if (notifTypes.isEmpty()) {
            System.debug('Performance_Target_Notification type not found. Skipping notifications.');
            return;
        }
        Id notifTypeId = notifTypes[0].Id;

        for (Performance_Target__c target : scope) {
            Decimal achievementPct = 0;
            if (target.Target_Value__c != null && target.Target_Value__c != 0) {
                achievementPct = target.Actual_Value__c / target.Target_Value__c;
            }

            Integer daysUntilEnd = Date.today().daysBetween(target.Period_End__c);
            String metricLabel = String.isNotBlank(target.Metric__c)
                ? target.Metric__c : target.Name;
            Integer achievementDisplay = (Integer)(achievementPct * 100);

            // Check: Target Achieved (achievement >= 100%)
            if (achievementPct >= 1.0) {
                sendNotification(
                    notifTypeId,
                    target.Id,
                    target.Assignee__c,
                    'Target Achieved: ' + metricLabel,
                    'Congratulations! You have achieved ' + achievementDisplay
                        + '% of your target for ' + metricLabel + '.'
                );
                continue;
            }

            // Check: Target At Risk (period ends within threshold days and achievement below threshold)
            if (daysUntilEnd <= AT_RISK_DAYS_THRESHOLD && achievementPct < AT_RISK_ACHIEVEMENT_THRESHOLD) {
                sendNotification(
                    notifTypeId,
                    target.Id,
                    target.Assignee__c,
                    'At Risk: ' + metricLabel,
                    'Your target for ' + metricLabel + ' is at risk. Current achievement is '
                        + achievementDisplay + '% with ' + daysUntilEnd + ' day(s) remaining.'
                );
                continue;
            }

            // Check: Target Missed (period ended and achievement below 100%)
            if (target.Period_End__c < Date.today() && achievementPct < 1.0) {
                sendNotification(
                    notifTypeId,
                    target.Id,
                    target.Assignee__c,
                    'Target Missed: ' + metricLabel,
                    'The period for ' + metricLabel + ' has ended with ' + achievementDisplay
                        + '% achievement. Target was not met.'
                );
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        // No follow-up processing needed
    }

    // ── Notification helper ──────────────────────────────────────

    private void sendNotification(Id notifTypeId, Id targetId, Id recipientId, String title, String body) {
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(notifTypeId);
            notification.setTargetId(targetId);

            Set<String> recipients = new Set<String>{ String.valueOf(recipientId) };
            notification.send(recipients);
        } catch (Exception e) {
            System.debug('Performance notification failed for target ' + targetId + ': ' + e.getMessage());
        }
    }
}