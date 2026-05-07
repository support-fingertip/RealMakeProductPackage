/**
 * @description Alerting service for the Integration Orchestration Platform.
 *              Evaluates error conditions and sends email notifications when critical
 *              failures, consecutive errors, or dead letter queue items are detected.
 *              Uses custom metadata (Integration_Alert_Config__mdt) for recipient
 *              configuration with fallback to a custom label (Integration_Alert_Recipients).
 * @author Integration Platform
 */
public class IntegrationAlertService {

    /** Number of consecutive failures that triggers an alert */
    private static final Integer CONSECUTIVE_FAILURE_THRESHOLD = 3;

    /** Maximum number of email invocations per transaction (Salesforce governor limit) */
    private static final Integer MAX_EMAILS_PER_TRANSACTION = 10;

    /** Counter to track emails sent in the current transaction */
    private static Integer emailsSentThisTransaction = 0;

    /**
     * @description Evaluates whether an alert should be sent based on the log and error context.
     *              Alert conditions:
     *              - Critical severity errors
     *              - Dead letter queue items
     *              - Consecutive failures (3 or more) for the same integration key
     * @param log The Integration_Log__c record for the failed call
     * @param errorLog The Integration_Error_Log__c record with error details (may be null)
     */
    public static void checkAndAlert(Integration_Log__c log, Integration_Error_Log__c errorLog) {
        if (log == null) {
            return;
        }

        List<String> recipients = getAlertRecipients();
        if (recipients.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'IntegrationAlertService: No alert recipients configured. Skipping alerts.');
            return;
        }

        // Condition 1: Critical severity error
        if (errorLog != null && errorLog.Severity__c == 'Critical') {
            String subject = buildSubject('CRITICAL', log.Integration_Key__c, 'Critical error detected');
            String body = buildCriticalErrorBody(log, errorLog);
            sendEmailAlert(subject, body, recipients);
            return;
        }

        // Condition 2: Dead letter queue item
        if (errorLog != null && errorLog.Is_Dead_Letter__c == true) {
            String subject = buildSubject('DEAD LETTER', log.Integration_Key__c, 'Message moved to dead letter queue');
            String body = buildDeadLetterBody(log, errorLog);
            sendEmailAlert(subject, body, recipients);
            return;
        }

        // Condition 3: Consecutive failures
        if (String.isNotBlank(log.Integration_Key__c) && log.Is_Success__c == false) {
            Integer consecutiveFailures = countConsecutiveFailures(log.Integration_Key__c);
            if (consecutiveFailures >= CONSECUTIVE_FAILURE_THRESHOLD) {
                String subject = buildSubject('CONSECUTIVE FAILURES', log.Integration_Key__c,
                    consecutiveFailures + ' consecutive failures');
                String body = buildConsecutiveFailureBody(log, errorLog, consecutiveFailures);
                sendEmailAlert(subject, body, recipients);
            }
        }
    }

    /**
     * @description Sends an email alert to the specified recipients.
     *              Governor-limit safe: tracks send count and respects Salesforce limits.
     * @param subject The email subject line
     * @param body The email body (HTML format)
     * @param recipients List of email addresses to send to
     */
    public static void sendEmailAlert(String subject, String body, List<String> recipients) {
        if (String.isBlank(subject) || String.isBlank(body) || recipients == null || recipients.isEmpty()) {
            return;
        }

        // Governor limit check
        if (emailsSentThisTransaction >= MAX_EMAILS_PER_TRANSACTION) {
            System.debug(LoggingLevel.WARN,
                'IntegrationAlertService: Email send limit reached (' + MAX_EMAILS_PER_TRANSACTION +
                '). Alert suppressed: ' + subject);
            return;
        }

        // Check remaining email invocations
        Integer emailLimit = Limits.getLimitEmailInvocations();
        Integer emailUsed = Limits.getEmailInvocations();
        if (emailUsed >= emailLimit) {
            System.debug(LoggingLevel.WARN,
                'IntegrationAlertService: Salesforce email invocation limit reached. Alert suppressed: ' + subject);
            return;
        }

        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(recipients);
            email.setSubject(truncateSubject(subject));
            email.setHtmlBody(body);
            email.setSaveAsActivity(false);
            email.setUseSignature(false);

            // Use OrgWideEmailAddress if available to avoid sender issues
            List<OrgWideEmailAddress> owea = [
                SELECT Id FROM OrgWideEmailAddress WHERE IsAllowAllProfiles = true LIMIT 1
            ];
            if (!owea.isEmpty()) {
                email.setOrgWideEmailAddressId(owea[0].Id);
            }

            Messaging.SendEmailResult[] results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ email }, false
            );

            emailsSentThisTransaction++;

            for (Messaging.SendEmailResult result : results) {
                if (!result.isSuccess()) {
                    for (Messaging.SendEmailError err : result.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'IntegrationAlertService: Email send failed - ' + err.getMessage());
                    }
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationAlertService: Exception sending alert email - ' + ex.getMessage());
        }
    }

    // ─── Private Helper Methods ──────────────────────────────────────────

    /**
     * @description Retrieves alert recipient email addresses from custom metadata
     *              (Integration_Alert_Config__mdt) with fallback to custom label
     *              (Integration_Alert_Recipients). The custom label should contain
     *              comma-separated email addresses.
     * @return List of recipient email addresses
     */
    @TestVisible
    private static List<String> getAlertRecipients() {
        List<String> recipients = new List<String>();

        // Try custom metadata first
        try {
            List<SObject> configs = Database.query(
                'SELECT Email__c FROM Integration_Alert_Config__mdt ' +
                'WHERE Is_Active__c = true AND Email__c != null'
            );
            for (SObject config : configs) {
                String email = (String) config.get('Email__c');
                if (String.isNotBlank(email)) {
                    recipients.add(email.trim());
                }
            }
        } catch (Exception ex) {
            // Custom metadata type may not exist yet; fall through to label
            System.debug(LoggingLevel.DEBUG,
                'IntegrationAlertService: Custom metadata not available, trying custom label.');
        }

        // Fallback to custom label
        if (recipients.isEmpty()) {
            try {
                String labelValue = System.Label.Integration_Alert_Recipients;
                if (String.isNotBlank(labelValue)) {
                    for (String email : labelValue.split(',')) {
                        String trimmed = email.trim();
                        if (String.isNotBlank(trimmed)) {
                            recipients.add(trimmed);
                        }
                    }
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN,
                    'IntegrationAlertService: Custom label Integration_Alert_Recipients not found.');
            }
        }

        return recipients;
    }

    /**
     * @description Counts recent consecutive failures for a given integration key.
     *              Queries the most recent log entries and counts how many failures
     *              occurred in sequence from the latest entry backwards.
     * @param integrationKey The integration key to check
     * @return Number of consecutive failures
     */
    private static Integer countConsecutiveFailures(String integrationKey) {
        if (String.isBlank(integrationKey)) {
            return 0;
        }

        try {
            List<Integration_Log__c> recentLogs = [
                SELECT Is_Success__c
                FROM Integration_Log__c
                WHERE Integration_Key__c = :integrationKey
                ORDER BY Execution_End__c DESC NULLS LAST
                LIMIT 10
            ];

            Integer count = 0;
            for (Integration_Log__c recentLog : recentLogs) {
                if (recentLog.Is_Success__c == false) {
                    count++;
                } else {
                    break;
                }
            }
            return count;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationAlertService: Error counting consecutive failures - ' + ex.getMessage());
            return 0;
        }
    }

    /**
     * @description Builds a standardized email subject line.
     */
    private static String buildSubject(String prefix, String integrationKey, String detail) {
        String key = String.isNotBlank(integrationKey) ? integrationKey : 'Unknown';
        return '[Integration Alert] [' + prefix + '] ' + key + ' - ' + detail;
    }

    /**
     * @description Truncates subject to 255 characters (email subject limit).
     */
    private static String truncateSubject(String subject) {
        if (subject != null && subject.length() > 255) {
            return subject.substring(0, 252) + '...';
        }
        return subject;
    }

    /**
     * @description Builds the HTML email body for a critical error alert.
     */
    private static String buildCriticalErrorBody(Integration_Log__c log, Integration_Error_Log__c errorLog) {
        String body = '<h2 style="color: #cc0000;">Critical Integration Error</h2>';
        body += buildLogSummaryHtml(log);

        if (errorLog != null) {
            body += '<h3>Error Details</h3>';
            body += '<table style="border-collapse: collapse; width: 100%;">';
            body += tableRow('Error Type', safe(errorLog.Error_Type__c));
            body += tableRow('Error Message', safe(errorLog.Error_Message__c));
            body += tableRow('Severity', safe(errorLog.Severity__c));
            if (String.isNotBlank(errorLog.Stack_Trace__c)) {
                body += tableRow('Stack Trace', '<pre style="font-size: 12px; white-space: pre-wrap;">' +
                    safe(errorLog.Stack_Trace__c) + '</pre>');
            }
            body += '</table>';
        }

        body += buildFooterHtml(log);
        return body;
    }

    /**
     * @description Builds the HTML email body for a dead letter queue alert.
     */
    private static String buildDeadLetterBody(Integration_Log__c log, Integration_Error_Log__c errorLog) {
        String body = '<h2 style="color: #cc6600;">Dead Letter Queue Item</h2>';
        body += '<p>A message has been moved to the dead letter queue after exhausting retry attempts.</p>';
        body += buildLogSummaryHtml(log);

        if (errorLog != null) {
            body += '<h3>Error Details</h3>';
            body += '<table style="border-collapse: collapse; width: 100%;">';
            body += tableRow('Error Type', safe(errorLog.Error_Type__c));
            body += tableRow('Error Message', safe(errorLog.Error_Message__c));
            body += tableRow('Retry Eligible', errorLog.Retry_Eligible__c == true ? 'Yes' : 'No');
            body += '</table>';
        }

        body += buildFooterHtml(log);
        return body;
    }

    /**
     * @description Builds the HTML email body for a consecutive failure alert.
     */
    private static String buildConsecutiveFailureBody(
        Integration_Log__c log, Integration_Error_Log__c errorLog, Integer consecutiveCount
    ) {
        String body = '<h2 style="color: #cc6600;">Consecutive Failure Alert</h2>';
        body += '<p><strong>' + consecutiveCount + '</strong> consecutive failures detected for integration: <strong>' +
            safe(log.Integration_Key__c) + '</strong></p>';
        body += buildLogSummaryHtml(log);

        if (errorLog != null) {
            body += '<h3>Latest Error</h3>';
            body += '<table style="border-collapse: collapse; width: 100%;">';
            body += tableRow('Error Type', safe(errorLog.Error_Type__c));
            body += tableRow('Error Message', safe(errorLog.Error_Message__c));
            body += '</table>';
        }

        body += buildFooterHtml(log);
        return body;
    }

    /**
     * @description Builds HTML summary table for a log record.
     */
    private static String buildLogSummaryHtml(Integration_Log__c log) {
        String html = '<h3>Integration Log Summary</h3>';
        html += '<table style="border-collapse: collapse; width: 100%;">';
        html += tableRow('Integration Key', safe(log.Integration_Key__c));
        html += tableRow('Correlation ID', safe(log.Correlation_Id__c));
        html += tableRow('Direction', safe(log.Direction__c));
        html += tableRow('HTTP Method', safe(log.HTTP_Method__c));
        html += tableRow('Request URL', safe(log.Request_URL__c));
        html += tableRow('Response Status', log.Response_Status_Code__c != null
            ? String.valueOf(log.Response_Status_Code__c) : 'N/A');
        html += tableRow('Execution Time', log.Execution_Time_ms__c != null
            ? String.valueOf(log.Execution_Time_ms__c) + ' ms' : 'N/A');
        html += tableRow('Execution End', log.Execution_End__c != null
            ? String.valueOf(log.Execution_End__c) : 'N/A');
        html += '</table>';
        return html;
    }

    /**
     * @description Builds the HTML footer with a link to the log record.
     */
    private static String buildFooterHtml(Integration_Log__c log) {
        String html = '<hr/>';
        html += '<p style="font-size: 12px; color: #666;">';
        html += 'This is an automated alert from the Integration Orchestration Platform.';
        if (log.Id != null) {
            String baseUrl = URL.getOrgDomainUrl() != null
                ? URL.getOrgDomainUrl().toExternalForm()
                : '';
            html += ' <a href="' + baseUrl + '/' + log.Id + '">View Log Record</a>';
        }
        html += '</p>';
        return html;
    }

    /**
     * @description Generates an HTML table row with label and value.
     */
    private static String tableRow(String label, String value) {
        return '<tr>' +
            '<td style="padding: 4px 8px; border: 1px solid #ddd; font-weight: bold; width: 30%; vertical-align: top;">' +
            safe(label) + '</td>' +
            '<td style="padding: 4px 8px; border: 1px solid #ddd;">' +
            (String.isNotBlank(value) ? value : 'N/A') + '</td>' +
            '</tr>';
    }

    /**
     * @description Null-safe string helper. Returns empty string for null input
     *              and escapes HTML entities for XSS prevention.
     */
    private static String safe(String input) {
        if (input == null) {
            return '';
        }
        return input.escapeHtml4();
    }
}