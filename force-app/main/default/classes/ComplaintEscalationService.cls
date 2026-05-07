/**
 * @description Service class that implements configurable multi-level complaint escalation
 *              using the Complaint_Escalation_Matrix__c object. Supports 3 escalation levels
 *              with configurable thresholds, notification targets, and auto-reassignment.
 *
 *              Escalation matching priority:
 *              1. Exact match (priority + category + project)
 *              2. Priority + category (any project)
 *              3. Priority only (any category)
 *              4. Category only (any priority)
 *              5. Default rule (no priority, no category, no project)
 *
 * @author System
 * @date 2026-03-31
 */
public with sharing class ComplaintEscalationService {

    private static final Set<String> CLOSED_STATUSES = new Set<String>{
        'Closed', 'Resolved', 'Cancelled'
    };

    /**
     * @description Process all overdue complaints against the escalation matrix.
     *              For each complaint, finds the best matching rule and escalates
     *              to the appropriate level based on days overdue.
     * @return EscalationResult containing counts and details
     */
    public static EscalationResult processEscalations() {
        EscalationResult result = new EscalationResult();
        Date today = Date.today();

        // Load active escalation rules
        List<Complaint_Escalation_Matrix__c> rules = [
            SELECT Id, Name, Priority__c, Category__c, Project__c,
                   Level_1_Days__c, Level_1_Notify__c, Level_1_User__c,
                   Level_2_Days__c, Level_2_Notify__c, Level_2_User__c,
                   Level_3_Days__c, Level_3_Notify__c, Level_3_User__c,
                   Auto_Reassign__c
            FROM Complaint_Escalation_Matrix__c
            WHERE Active__c = true
            ORDER BY Priority__c NULLS LAST, Category__c NULLS LAST
        ];

        if (rules.isEmpty()) {
            result.message = 'No active escalation rules found.';
            return result;
        }

        // Query overdue complaints
        List<Complaint__c> overdueComplaints = [
            SELECT Id, Name, Subject__c, Description__c, Category__c, Priority__c,
                   Expected_Resolution_Date__c, Status__c,
                   Customer_Name__c, Customer_Email__c,
                   Assigned_To__c, Assigned_To__r.Name, Assigned_To__r.Email,
                   OwnerId,
                   Escalation_Level__c,
                   Booking__c, Booking__r.Name, Booking__r.Unit__r.Name,
                   Project__c, Project__r.Name,
                   Project__r.Project_Head__c, Project__r.Project_Head__r.Email
            FROM Complaint__c
            WHERE Expected_Resolution_Date__c < :today
            AND Status__c NOT IN :CLOSED_STATUSES
            LIMIT 500
        ];

        if (overdueComplaints.isEmpty()) {
            result.message = 'No overdue complaints found.';
            return result;
        }

        // Collect user IDs we need emails for
        Set<Id> userIdsNeeded = new Set<Id>();
        for (Complaint__c c : overdueComplaints) {
            if (c.OwnerId != null) userIdsNeeded.add(c.OwnerId);
        }
        for (Complaint_Escalation_Matrix__c rule : rules) {
            if (rule.Level_1_User__c != null) userIdsNeeded.add(rule.Level_1_User__c);
            if (rule.Level_2_User__c != null) userIdsNeeded.add(rule.Level_2_User__c);
            if (rule.Level_3_User__c != null) userIdsNeeded.add(rule.Level_3_User__c);
        }
        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, Name, Email FROM User WHERE Id IN :userIdsNeeded
        ]);

        List<Complaint__c> complaintsToUpdate = new List<Complaint__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Complaint__c complaint : overdueComplaints) {
            Integer daysOverdue = complaint.Expected_Resolution_Date__c.daysBetween(today);
            Complaint_Escalation_Matrix__c matchedRule = findBestRule(rules, complaint);

            if (matchedRule == null) continue;

            Integer newLevel = determineEscalationLevel(matchedRule, daysOverdue);
            Integer currentLevel = complaint.Escalation_Level__c != null
                ? Integer.valueOf(complaint.Escalation_Level__c) : 0;

            if (newLevel <= currentLevel) continue;

            // Build escalation email
            String targetEmail = resolveNotifyEmail(
                matchedRule, newLevel, complaint, userMap
            );
            Id targetUserId = resolveNotifyUserId(
                matchedRule, newLevel, complaint
            );

            if (String.isBlank(targetEmail)) continue;

            // Update complaint
            Complaint__c updateRec = new Complaint__c(
                Id = complaint.Id,
                Escalation_Level__c = newLevel,
                Last_Escalation_Date__c = DateTime.now(),
                Escalated_To__c = targetUserId
            );

            if (matchedRule.Auto_Reassign__c && targetUserId != null) {
                updateRec.Assigned_To__c = targetUserId;
            }

            if (complaint.Status__c != 'Escalated') {
                updateRec.Status__c = 'Escalated';
            }

            complaintsToUpdate.add(updateRec);

            // Build email
            Messaging.SingleEmailMessage email = buildEscalationEmail(
                complaint, newLevel, daysOverdue, targetEmail, userMap
            );
            if (email != null) {
                emails.add(email);
            }

            result.escalatedCount++;
        }

        // DML updates
        if (!complaintsToUpdate.isEmpty()) {
            update complaintsToUpdate;
        }

        // Send emails
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false);
                result.emailsSent = emails.size();
            } catch (Exception e) {
                result.errors.add('Error sending escalation emails: ' + e.getMessage());
            }
        }

        result.totalProcessed = overdueComplaints.size();
        result.message = 'Escalation complete. ' + result.escalatedCount +
            ' complaint(s) escalated, ' + result.emailsSent + ' email(s) sent.';
        return result;
    }

    /**
     * @description Find the best matching escalation rule for a complaint.
     *              Uses specificity-based matching (most specific match wins).
     */
    @TestVisible
    private static Complaint_Escalation_Matrix__c findBestRule(
        List<Complaint_Escalation_Matrix__c> rules, Complaint__c complaint
    ) {
        Complaint_Escalation_Matrix__c bestRule = null;
        Integer bestScore = -1;

        for (Complaint_Escalation_Matrix__c rule : rules) {
            Integer score = calculateMatchScore(rule, complaint);
            if (score > bestScore) {
                bestScore = score;
                bestRule = rule;
            }
        }

        // Score of 0 means default rule (no filters), which is still valid
        return bestScore >= 0 ? bestRule : null;
    }

    /**
     * @description Calculate match score for a rule against a complaint.
     *              Higher score = more specific match.
     *              Returns -1 if the rule does not match.
     */
    private static Integer calculateMatchScore(
        Complaint_Escalation_Matrix__c rule, Complaint__c complaint
    ) {
        Integer score = 0;
        Boolean hasFilter = false;

        // Check priority match
        if (String.isNotBlank(rule.Priority__c)) {
            hasFilter = true;
            if (rule.Priority__c != complaint.Priority__c) return -1;
            score += 4;
        }

        // Check category match
        if (String.isNotBlank(rule.Category__c)) {
            hasFilter = true;
            if (rule.Category__c != complaint.Category__c) return -1;
            score += 2;
        }

        // Check project match
        if (rule.Project__c != null) {
            hasFilter = true;
            if (rule.Project__c != complaint.Project__c) return -1;
            score += 1;
        }

        return score;
    }

    /**
     * @description Determine escalation level based on days overdue and rule thresholds.
     */
    @TestVisible
    private static Integer determineEscalationLevel(
        Complaint_Escalation_Matrix__c rule, Integer daysOverdue
    ) {
        if (rule.Level_3_Days__c != null && daysOverdue >= rule.Level_3_Days__c) {
            return 3;
        }
        if (rule.Level_2_Days__c != null && daysOverdue >= rule.Level_2_Days__c) {
            return 2;
        }
        if (daysOverdue >= rule.Level_1_Days__c) {
            return 1;
        }
        return 0;
    }

    /**
     * @description Resolve the email address for the notification target at a given level.
     */
    private static String resolveNotifyEmail(
        Complaint_Escalation_Matrix__c rule, Integer level,
        Complaint__c complaint, Map<Id, User> userMap
    ) {
        String notifyType = getNotifyType(rule, level);
        return resolveEmailByType(notifyType, rule, level, complaint, userMap);
    }

    /**
     * @description Resolve the User ID for the notification target at a given level.
     */
    private static Id resolveNotifyUserId(
        Complaint_Escalation_Matrix__c rule, Integer level, Complaint__c complaint
    ) {
        String notifyType = getNotifyType(rule, level);
        if (notifyType == 'Assigned To') return complaint.Assigned_To__c;
        if (notifyType == 'Owner') return complaint.OwnerId;
        if (notifyType == 'Project Head') return complaint.Project__r.Project_Head__c;
        if (notifyType == 'Custom User') return getCustomUser(rule, level);
        return null;
    }

    private static String getNotifyType(Complaint_Escalation_Matrix__c rule, Integer level) {
        if (level == 1) return rule.Level_1_Notify__c;
        if (level == 2) return rule.Level_2_Notify__c;
        if (level == 3) return rule.Level_3_Notify__c;
        return null;
    }

    private static Id getCustomUser(Complaint_Escalation_Matrix__c rule, Integer level) {
        if (level == 1) return rule.Level_1_User__c;
        if (level == 2) return rule.Level_2_User__c;
        if (level == 3) return rule.Level_3_User__c;
        return null;
    }

    private static String resolveEmailByType(
        String notifyType, Complaint_Escalation_Matrix__c rule, Integer level,
        Complaint__c complaint, Map<Id, User> userMap
    ) {
        if (String.isBlank(notifyType)) return null;

        if (notifyType == 'Assigned To') {
            return complaint.Assigned_To__r != null ? complaint.Assigned_To__r.Email : null;
        }
        if (notifyType == 'Owner') {
            User owner = userMap.get(complaint.OwnerId);
            return owner != null ? owner.Email : null;
        }
        if (notifyType == 'Project Head') {
            return complaint.Project__r != null ? complaint.Project__r.Project_Head__r.Email : null;
        }
        if (notifyType == 'Custom User') {
            Id customUserId = getCustomUser(rule, level);
            User customUser = customUserId != null ? userMap.get(customUserId) : null;
            return customUser != null ? customUser.Email : null;
        }
        return null;
    }

    /**
     * @description Build an escalation email for a complaint at a given level.
     */
    private static Messaging.SingleEmailMessage buildEscalationEmail(
        Complaint__c complaint, Integer level, Integer daysOverdue,
        String targetEmail, Map<Id, User> userMap
    ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ targetEmail });

        // CC complaint owner and assigned to
        Set<String> ccEmails = new Set<String>();
        if (complaint.Assigned_To__r != null && String.isNotBlank(complaint.Assigned_To__r.Email)) {
            ccEmails.add(complaint.Assigned_To__r.Email);
        }
        User owner = userMap.get(complaint.OwnerId);
        if (owner != null && String.isNotBlank(owner.Email)) {
            ccEmails.add(owner.Email);
        }
        ccEmails.remove(targetEmail);
        if (!ccEmails.isEmpty()) {
            email.setCcAddresses(new List<String>(ccEmails));
        }

        String levelLabel = 'Level ' + level;
        String priorityColor = complaint.Priority__c == 'High' ? '#e74c3c' :
            (complaint.Priority__c == 'Medium' ? '#f39c12' : '#3498db');

        email.setSubject(levelLabel + ' Escalation: ' + complaint.Name + ' - ' +
            (complaint.Subject__c != null ? complaint.Subject__c : 'Complaint'));

        String body = '<div style="font-family:Arial,sans-serif;">';
        body += '<div style="background-color:' + priorityColor + ';color:white;padding:12px 20px;border-radius:4px 4px 0 0;">';
        body += '<h2 style="margin:0;">' + levelLabel + ' Escalation Alert</h2>';
        body += '</div>';

        body += '<div style="border:1px solid #ddd;padding:20px;border-radius:0 0 4px 4px;">';
        body += '<p>The following complaint requires immediate attention. It is <strong>' +
            daysOverdue + ' days overdue</strong> and has been escalated to <strong>' + levelLabel + '</strong>.</p>';

        body += '<table style="width:100%;border-collapse:collapse;margin:16px 0;">';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;width:35%;">Complaint</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;">' + complaint.Name + '</td></tr>';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Subject</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;">' + safe(complaint.Subject__c) + '</td></tr>';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Customer</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;">' + safe(complaint.Customer_Name__c) + '</td></tr>';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Category</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;">' + safe(complaint.Category__c) + '</td></tr>';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Priority</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;"><span style="background-color:' + priorityColor +
            ';color:white;padding:2px 8px;border-radius:3px;">' + safe(complaint.Priority__c) + '</span></td></tr>';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Project</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;">' +
            (complaint.Project__r != null ? safe(complaint.Project__r.Name) : '') + '</td></tr>';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Unit</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;">' +
            (complaint.Booking__r != null && complaint.Booking__r.Unit__r != null
                ? safe(complaint.Booking__r.Unit__r.Name) : '') + '</td></tr>';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Expected Resolution</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;">' +
            complaint.Expected_Resolution_Date__c.format() + '</td></tr>';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Days Overdue</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;color:red;font-weight:bold;">' + daysOverdue + '</td></tr>';
        body += '<tr><td style="padding:8px;border-bottom:1px solid #eee;font-weight:bold;">Assigned To</td>';
        body += '<td style="padding:8px;border-bottom:1px solid #eee;">' +
            (complaint.Assigned_To__r != null ? safe(complaint.Assigned_To__r.Name) : '') + '</td></tr>';
        body += '</table>';

        body += '<p style="color:#666;">Please take immediate action to resolve this complaint.</p>';
        body += '</div></div>';

        email.setHtmlBody(body);
        email.setSaveAsActivity(false);
        return email;
    }

    private static String safe(String val) {
        return String.isBlank(val) ? '' : val.escapeHtml4();
    }

    // ==================== CONTROLLER METHODS (for LWC) ====================

    @AuraEnabled(cacheable=true)
    public static List<Complaint_Escalation_Matrix__c> getEscalationRules() {
        return [
            SELECT Id, Name, Priority__c, Category__c, Project__c, Project__r.Name,
                   Level_1_Days__c, Level_1_Notify__c, Level_1_User__c, Level_1_User__r.Name,
                   Level_2_Days__c, Level_2_Notify__c, Level_2_User__c, Level_2_User__r.Name,
                   Level_3_Days__c, Level_3_Notify__c, Level_3_User__c, Level_3_User__r.Name,
                   Auto_Reassign__c, Active__c, Description__c,
                   CreatedDate, LastModifiedDate
            FROM Complaint_Escalation_Matrix__c
            ORDER BY Active__c DESC, Priority__c NULLS LAST, Category__c NULLS LAST
        ];
    }

    @AuraEnabled
    public static Id saveEscalationRule(String ruleJson) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(ruleJson);
            Complaint_Escalation_Matrix__c rule;
            String ruleId = (String) data.get('id');

            if (String.isNotBlank(ruleId)) {
                rule = [SELECT Id FROM Complaint_Escalation_Matrix__c WHERE Id = :ruleId LIMIT 1];
            } else {
                rule = new Complaint_Escalation_Matrix__c();
            }

            rule.Priority__c = (String) data.get('priority');
            rule.Category__c = (String) data.get('category');
            rule.Description__c = (String) data.get('description');
            rule.Active__c = data.get('active') != null ? (Boolean) data.get('active') : true;
            rule.Auto_Reassign__c = data.get('autoReassign') != null ? (Boolean) data.get('autoReassign') : false;

            String projectId = (String) data.get('projectId');
            rule.Project__c = String.isNotBlank(projectId) ? projectId : null;

            rule.Level_1_Days__c = getDecimalValue(data, 'level1Days');
            rule.Level_1_Notify__c = (String) data.get('level1Notify');
            String l1User = (String) data.get('level1UserId');
            rule.Level_1_User__c = String.isNotBlank(l1User) ? l1User : null;

            rule.Level_2_Days__c = getDecimalValue(data, 'level2Days');
            rule.Level_2_Notify__c = (String) data.get('level2Notify');
            String l2User = (String) data.get('level2UserId');
            rule.Level_2_User__c = String.isNotBlank(l2User) ? l2User : null;

            rule.Level_3_Days__c = getDecimalValue(data, 'level3Days');
            rule.Level_3_Notify__c = (String) data.get('level3Notify');
            String l3User = (String) data.get('level3UserId');
            rule.Level_3_User__c = String.isNotBlank(l3User) ? l3User : null;

            upsert rule;
            return rule.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving escalation rule: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteEscalationRule(String ruleId) {
        try {
            delete [SELECT Id FROM Complaint_Escalation_Matrix__c WHERE Id = :ruleId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting rule: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void toggleEscalationRule(String ruleId, Boolean active) {
        try {
            Complaint_Escalation_Matrix__c rule = [
                SELECT Id FROM Complaint_Escalation_Matrix__c WHERE Id = :ruleId LIMIT 1
            ];
            rule.Active__c = active;
            update rule;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating rule: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getEscalationSummary() {
        // Escalation_Level__c is a formula field which Salesforce won't allow in
        // a GROUP BY. Aggregate in Apex instead.
        Map<Decimal, Integer> counts = new Map<Decimal, Integer>();
        for (Complaint__c c : [
            SELECT Escalation_Level__c
            FROM Complaint__c
            WHERE Status__c NOT IN ('Closed', 'Resolved', 'Cancelled')
            AND Escalation_Level__c > 0
        ]) {
            Decimal lvl = c.Escalation_Level__c;
            counts.put(lvl, (counts.containsKey(lvl) ? counts.get(lvl) : 0) + 1);
        }
        List<Decimal> levels = new List<Decimal>(counts.keySet());
        levels.sort();
        List<Map<String, String>> summary = new List<Map<String, String>>();
        for (Decimal lvl : levels) {
            Map<String, String> item = new Map<String, String>();
            item.put('level', String.valueOf(lvl));
            item.put('count', String.valueOf(counts.get(lvl)));
            summary.add(item);
        }
        return summary;
    }

    private static Decimal getDecimalValue(Map<String, Object> data, String key) {
        Object val = data.get(key);
        if (val == null) return null;
        if (val instanceof Decimal) return (Decimal) val;
        return Decimal.valueOf(String.valueOf(val));
    }

    // ==================== RESULT CLASS ====================

    public class EscalationResult {
        public Integer totalProcessed = 0;
        public Integer escalatedCount = 0;
        public Integer emailsSent = 0;
        public String message = '';
        public List<String> errors = new List<String>();
    }
}