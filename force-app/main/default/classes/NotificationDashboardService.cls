/**
 * @description Service class for the Notification Dashboard.
 *              Handles configuration caching, dynamic SOQL building,
 *              profile-based filtering, and status updates.
 *              Follows patterns from CPModuleConfigService (caching)
 *              and UserAvailabilityController (profile-based filtering).
 */
public with sharing class NotificationDashboardService {

    // ── Static Config Cache (single SOQL per transaction) ──────────
    // @TestVisible so tests can pre-populate these caches (CMDT can't be inserted via DML).
    @TestVisible private static List<Dashboard_Tab_Config__mdt> cachedTabConfigs;
    @TestVisible private static List<Dashboard_Field_Config__mdt> cachedFieldConfigs;
    private static String cachedProfileName;
    private static Set<String> cachedHeadProfiles;

    // ═══════════════════════════════════════════════════════════════════
    //  INNER CLASSES (Wrapper Types)
    // ═══════════════════════════════════════════════════════════════════

    public class TabConfig implements Comparable {
        @AuraEnabled public String tabKey;
        @AuraEnabled public String tabName;
        @AuraEnabled public Integer sortOrder;
        @AuraEnabled public String iconName;
        @AuraEnabled public List<String> sObjectNames;
        @AuraEnabled public String emptyStateText;
        @AuraEnabled public Boolean showBadgeCount;
        @AuraEnabled public Map<String, Object> statusActions;

        public Integer compareTo(Object other) {
            TabConfig otherTab = (TabConfig) other;
            return this.sortOrder - otherTab.sortOrder;
        }
    }

    public class FieldConfig {
        @AuraEnabled public String sObjectName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String displayLabel;
        @AuraEnabled public Integer displayOrder;
        @AuraEnabled public String context;
        @AuraEnabled public String fieldType;
        @AuraEnabled public Boolean isTitleField;
        @AuraEnabled public String badgeVariant;
        @AuraEnabled public String cssClass;
    }

    public class TabDataResult {
        @AuraEnabled public List<RecordCard> records;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Map<String, Integer> countsByObject;
        @AuraEnabled public Map<String, List<RecordCard>> recordsByObject;
    }

    public class RecordCard {
        @AuraEnabled public String recordId;
        @AuraEnabled public String sObjectName;
        @AuraEnabled public String title;
        @AuraEnabled public String currentStatus;
        @AuraEnabled public List<FieldValue> fields;
        @AuraEnabled public String recordUrl;
    }

    public class FieldValue {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String fieldType;
        @AuraEnabled public String badgeVariant;
        @AuraEnabled public String cssClass;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  CONFIG LOADING
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Returns all dashboard config in one call.
     *              Pattern: load once, cache statically (like CPModuleConfigService).
     */
    public static Map<String, Object> getDashboardConfig() {
        String profileName = getCurrentProfileName();

        List<Dashboard_Tab_Config__mdt> tabMdts = getTabConfigs();
        List<Dashboard_Field_Config__mdt> fieldMdts = getFieldConfigs();

        // Filter tabs by profile
        List<TabConfig> visibleTabs = new List<TabConfig>();
        for (Dashboard_Tab_Config__mdt mdt : tabMdts) {
            if (isProfileAllowed(mdt.Allowed_Profiles__c, profileName)) {
                TabConfig tc = new TabConfig();
                tc.tabKey = mdt.Tab_Key__c;
                tc.tabName = mdt.Tab_Name__c;
                tc.sortOrder = mdt.Sort_Order__c != null ? mdt.Sort_Order__c.intValue() : 0;
                tc.iconName = mdt.Icon_Name__c;
                tc.sObjectNames = parseCsv(mdt.SObject_Names__c);
                tc.emptyStateText = mdt.Empty_State_Text__c;
                tc.showBadgeCount = mdt.Show_Badge_Count__c;
                tc.statusActions = parseStatusActions(mdt.Status_Actions_JSON__c);
                visibleTabs.add(tc);
            }
        }
        visibleTabs.sort();

        // Transform field configs
        List<FieldConfig> fieldList = new List<FieldConfig>();
        for (Dashboard_Field_Config__mdt fmdt : fieldMdts) {
            FieldConfig fc = new FieldConfig();
            fc.sObjectName = fmdt.SObject_Name__c;
            fc.fieldApiName = fmdt.Field_API_Name__c;
            fc.displayLabel = fmdt.Display_Label__c;
            fc.displayOrder = fmdt.Display_Order__c != null ? fmdt.Display_Order__c.intValue() : 0;
            fc.context = fmdt.Context__c;
            fc.fieldType = fmdt.Field_Type__c;
            fc.isTitleField = fmdt.Is_Title_Field__c;
            fc.badgeVariant = fmdt.Badge_Variant__c;
            fc.cssClass = fmdt.CSS_Class__c;
            fieldList.add(fc);
        }

        return new Map<String, Object>{
            'tabs' => visibleTabs,
            'fields' => fieldList,
            'currentProfile' => profileName
        };
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB DATA LOADING
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Loads records for a given tab. Uses dynamic SOQL with bind variables.
     *              Profile-aware: Executives see only their records. Heads see all.
     */
    public static TabDataResult getTabData(String tabKey, Integer pageSize, Integer offset) {
        Dashboard_Tab_Config__mdt tabConfig = getTabConfigByKey(tabKey);
        if (tabConfig == null) {
            throw new AuraHandledException('Invalid tab key: ' + String.escapeSingleQuotes(tabKey));
        }

        String profileName = getCurrentProfileName();
        Id currentUserId = UserInfo.getUserId();
        Boolean isHead = isHeadProfile(profileName);

        List<String> sObjectNames = parseCsv(tabConfig.SObject_Names__c);
        List<Dashboard_Field_Config__mdt> fieldMdts = getFieldConfigs();

        TabDataResult result = new TabDataResult();
        result.records = new List<RecordCard>();
        result.totalCount = 0;
        result.countsByObject = new Map<String, Integer>();
        result.recordsByObject = new Map<String, List<RecordCard>>();

        Date todayDate = Date.today();
        DateTime todayStart = DateTime.newInstance(todayDate, Time.newInstance(0, 0, 0, 0));
        DateTime todayEnd = DateTime.newInstance(todayDate, Time.newInstance(23, 59, 59, 0));
        List<String> excludedStatuses = new List<String>{ 'Completed', 'Cancelled' };

        for (String objName : sObjectNames) {
            // Build field list for CARD context
            Set<String> queryFields = new Set<String>{ 'Id', 'Name' };
            List<Dashboard_Field_Config__mdt> cardFields = getFieldsForObjectAndContext(fieldMdts, objName, 'CARD');

            for (Dashboard_Field_Config__mdt fmdt : cardFields) {
                queryFields.add(fmdt.Field_API_Name__c);
            }

            // Add the status field from statusActions JSON
            String statusField = getStatusFieldForObject(tabConfig.Status_Actions_JSON__c, objName);
            if (String.isNotBlank(statusField)) {
                queryFields.add(statusField);
            }

            // Build WHERE conditions
            List<String> conditions = new List<String>();

            // Ownership filter (profile-aware)
            if (!isHead) {
                String ownerField = getOwnerField(objName);
                conditions.add(ownerField + ' = :currentUserId');
            }

            // Date/status conditions based on tab type
            String dateField = getDateField(objName);
            DateTime nowDT = DateTime.now();

            if (tabKey == 'TODAY_AGENDAS') {
                conditions.add(dateField + ' >= :nowDT');
                conditions.add(dateField + ' <= :todayEnd');
                if (String.isNotBlank(statusField)) {
                    conditions.add(statusField + ' NOT IN :excludedStatuses');
                }
            } else if (tabKey == 'PENDING_ITEMS') {
             conditions.add(dateField + ' < :nowDT');
                if (String.isNotBlank(statusField)) {
                    conditions.add(statusField + ' NOT IN :excludedStatuses');
                }
            } else if (tabKey == 'TODAY_LEADS') {
                conditions.add('CreatedDate >= :todayStart');
                conditions.add('CreatedDate <= :todayEnd');
            }

            // Build SOQL
            String soql = 'SELECT ' + String.join(new List<String>(queryFields), ', ')
                + ' FROM ' + String.escapeSingleQuotes(objName)
                + ' WHERE ' + String.join(conditions, ' AND ')
                + ' ORDER BY ' + getOrderByField(objName) + ' ASC';

            // For TODAY_LEADS, add pagination
            if (tabKey == 'TODAY_LEADS') {
                String countSoql = 'SELECT COUNT() FROM ' + String.escapeSingleQuotes(objName)
                    + ' WHERE ' + String.join(conditions, ' AND ');
                Integer totalForObj = Database.countQuery(countSoql);
                result.totalCount += totalForObj;
                result.countsByObject.put(objName, totalForObj);

                soql += ' LIMIT :pageSize OFFSET :offset';
            }

            List<SObject> records = Database.query(soql);

            // For non-paginated tabs, set counts
            if (tabKey != 'TODAY_LEADS') {
                result.totalCount += records.size();
                result.countsByObject.put(objName, records.size());
            }

            // Transform to RecordCard wrappers
            for (SObject rec : records) {
                RecordCard card = new RecordCard();
                card.recordId = rec.Id;
                card.sObjectName = objName;
                card.recordUrl = '/lightning/r/' + String.escapeSingleQuotes(objName) + '/' + rec.Id + '/view';

                card.fields = new List<FieldValue>();
                for (Dashboard_Field_Config__mdt fmdt : cardFields) {
                    FieldValue fv = new FieldValue();
                    fv.label = fmdt.Display_Label__c;
                    fv.value = resolveFieldValue(rec, fmdt.Field_API_Name__c);
                    fv.fieldType = fmdt.Field_Type__c;
                    fv.badgeVariant = fmdt.Badge_Variant__c;
                    fv.cssClass = fmdt.CSS_Class__c;

                    if (fmdt.Is_Title_Field__c) {
                        card.title = fv.value;
                    }
                    card.fields.add(fv);
                }

                // Current status
                if (String.isNotBlank(statusField)) {
                    Object statusVal = rec.get(statusField);
                    card.currentStatus = statusVal != null ? String.valueOf(statusVal) : '';
                }

                result.records.add(card);
                if (!result.recordsByObject.containsKey(objName)) {
                    result.recordsByObject.put(objName, new List<RecordCard>());
                }
                result.recordsByObject.get(objName).add(card);
            }
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  STATUS UPDATE
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Updates record status with validation.
     *              Uses safe dynamic SObject update with Schema validation.
     */
    public static void updateRecordStatus(
        Id recordId,
        String sObjectName,
        String statusField,
        String newStatus,
        String additionalFieldsJson
    ) {
        if (recordId == null || String.isBlank(sObjectName)
            || String.isBlank(statusField) || String.isBlank(newStatus)) {
            throw new AuraHandledException('Record ID, object name, status field, and new status are required.');
        }

        // Validate the sObject and field exist
        String safeName = String.escapeSingleQuotes(sObjectName);
        Schema.SObjectType objType = NamespaceUtil.describeObject(safeName);
        if (objType == null) {
            throw new AuraHandledException('Invalid object: ' + safeName);
        }

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey(statusField.toLowerCase())) {
            throw new AuraHandledException('Invalid field: ' + statusField);
        }

        // Build SObject for update
        SObject record = objType.newSObject(recordId);
        record.put(statusField, newStatus);

        // Parse and apply additional fields
        if (String.isNotBlank(additionalFieldsJson)) {
            Map<String, Object> extras = (Map<String, Object>) JSON.deserializeUntyped(additionalFieldsJson);
            for (String fieldName : extras.keySet()) {
                String safeFieldName = String.escapeSingleQuotes(fieldName);
                if (!fieldMap.containsKey(safeFieldName.toLowerCase())) {
                    continue;
                }
                Schema.DescribeFieldResult fd = fieldMap.get(safeFieldName.toLowerCase()).getDescribe();
                Object val = extras.get(fieldName);

                if (val == null) {
                    record.put(safeFieldName, null);
                } else if (fd.getType() == Schema.DisplayType.DATETIME && val instanceof String) {
                    String dtStr = ((String) val).replace('T', ' ').replace('Z', '').replace('.000', '');
                    record.put(safeFieldName, DateTime.valueOfGmt(dtStr));
                } else if (fd.getType() == Schema.DisplayType.DATE && val instanceof String) {
                    record.put(safeFieldName, Date.valueOf((String) val));
                } else {
                    record.put(safeFieldName, val);
                }
            }
        }

        try {
            update record;
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to update status: ' + e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  MOVE LEAD TO FOLLOW-UP (with Followup__c creation)
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Updates a Lead's status to 'Follow-up' and creates an associated
     *              Followup__c record. Both operations are atomic (savepoint rollback on failure).
     * @param leadId  The Lead to move to Follow-up
     * @param subject Follow-up subject (required)
     * @param dueDate Follow-up due date as ISO string (required, must be in the future)
     * @param notes   Optional follow-up notes
     */
    public static void moveLeadToFollowUp(Id leadId, String subject, String dueDate, String notes) {
        if (leadId == null) {
            throw new AuraHandledException('Lead ID is required.');
        }
        if (String.isBlank(subject)) {
            throw new AuraHandledException('Follow-up Subject is required.');
        }
        if (String.isBlank(dueDate)) {
            throw new AuraHandledException('Follow-up Due Date is required.');
        }

        // Parse due date
        DateTime dueDateParsed = parseDateTimeValue(dueDate);
        if (dueDateParsed < DateTime.now()) {
            throw new AuraHandledException('Follow-up Due Date must be in the future.');
        }

        // Check for existing pending followup
        List<Followup__c> existingPending = [
            SELECT Id FROM Followup__c
            WHERE Lead__c = :leadId
              AND Assigned_To__c = :UserInfo.getUserId()
              AND Status__c = 'Pending'
            LIMIT 1
        ];
        if (!existingPending.isEmpty()) {
            throw new AuraHandledException(
                'You already have a pending follow-up for this lead. '
                + 'Please complete or cancel it before creating a new one.'
            );
        }

        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Update Lead status
            Lead__c lead = new Lead__c(Id = leadId);
            lead.Lead_Status__c = 'Follow-up';
            update lead;

            // 2. Create Followup__c
            Followup__c fu = new Followup__c();
            fu.Lead__c = leadId;
            fu.Subject__c = subject;
            fu.Due_Date__c = dueDateParsed;
            fu.Status__c = 'Pending';
            fu.Assigned_To__c = UserInfo.getUserId();
            if (String.isNotBlank(notes)) {
                fu.Notes__c = notes;
            }
            insert fu;
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Failed to move lead to Follow-up: ' + e.getMessage());
        }
    }

    /**
     * @description Parses datetime strings from LWC (ISO 8601 or legacy format).
     */
    private static DateTime parseDateTimeValue(String dtStr) {
        if (String.isBlank(dtStr)) return null;
        if (dtStr.contains('.') || dtStr.endsWith('Z')) {
            return (DateTime) JSON.deserialize('"' + dtStr + '"', DateTime.class);
        }
        return DateTime.valueOf(dtStr.replace('T', ' '));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PRIVATE HELPERS — Config Access
    // ═══════════════════════════════════════════════════════════════════

    private static String getCurrentProfileName() {
        if (cachedProfileName != null) return cachedProfileName;
        cachedProfileName = [
            SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ].Profile.Name;
        return cachedProfileName;
    }

    private static List<Dashboard_Tab_Config__mdt> getTabConfigs() {
        if (cachedTabConfigs != null) return cachedTabConfigs;
        cachedTabConfigs = [
            SELECT Tab_Name__c, Tab_Key__c, Sort_Order__c, Icon_Name__c,
                   SObject_Names__c, Allowed_Profiles__c, Empty_State_Text__c,
                   Show_Badge_Count__c, Status_Actions_JSON__c, Is_Active__c
            FROM Dashboard_Tab_Config__mdt
            WHERE Is_Active__c = true
            ORDER BY Sort_Order__c ASC
        ];
        return cachedTabConfigs;
    }

    private static List<Dashboard_Field_Config__mdt> getFieldConfigs() {
        if (cachedFieldConfigs != null) return cachedFieldConfigs;
        cachedFieldConfigs = [
            SELECT SObject_Name__c, Field_API_Name__c, Display_Label__c,
                   Display_Order__c, Context__c, Field_Type__c,
                   Is_Title_Field__c, Badge_Variant__c, CSS_Class__c, Is_Active__c
            FROM Dashboard_Field_Config__mdt
            WHERE Is_Active__c = true
            ORDER BY Display_Order__c ASC
        ];
        return cachedFieldConfigs;
    }

    private static Dashboard_Tab_Config__mdt getTabConfigByKey(String tabKey) {
        for (Dashboard_Tab_Config__mdt t : getTabConfigs()) {
            if (t.Tab_Key__c == tabKey) return t;
        }
        return null;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PRIVATE HELPERS — Profile & Ownership
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Profile check: matches Visible_Profiles__c pattern.
     *              Empty allowed list = visible to all. System Administrator always sees all.
     */
    private static Boolean isProfileAllowed(String allowedProfilesCsv, String currentProfile) {
        if (currentProfile == 'System Administrator') return true;
        if (String.isBlank(allowedProfilesCsv)) return true;
        Set<String> allowed = new Set<String>();
        for (String p : allowedProfilesCsv.split(',')) {
            allowed.add(p.trim());
        }
        return allowed.contains(currentProfile);
    }

    /**
     * @description Determines if a profile is a "head" profile (sees all records).
     *              Uses User_Availability_Profile_Config__mdt: profiles with a config
     *              record are considered heads. System Administrator always sees all.
     */
    private static Boolean isHeadProfile(String profileName) {
        if (profileName == 'System Administrator') return true;
        if (cachedHeadProfiles == null) {
            cachedHeadProfiles = new Set<String>();
            List<User_Availability_Profile_Config__mdt> configs = [
                SELECT Profile_Name__c
                FROM User_Availability_Profile_Config__mdt
                WHERE Is_Active__c = true
            ];
            for (User_Availability_Profile_Config__mdt cfg : configs) {
                cachedHeadProfiles.add(cfg.Profile_Name__c);
            }
        }
        return cachedHeadProfiles.contains(profileName);
    }

    /**
     * @description Returns the owner/assignment field per sObject.
     *              Followup__c and Site_Visit__c use Assigned_To__c.
     *              Lead__c uses Owner__c.
     */
    private static String getOwnerField(String sObjectName) {
        if (sObjectName == 'Lead__c') return 'Owner__c';
        return 'Assigned_To__c';
    }

    /**
     * @description Returns the date field used for today/overdue filtering.
     */
    private static String getDateField(String sObjectName) {
        if (sObjectName == 'Followup__c') return 'Due_Date__c';
        if (sObjectName == 'Site_Visit__c') return 'Scheduled_Date__c';
        return 'CreatedDate';
    }

    private static String getOrderByField(String sObjectName) {
        if (sObjectName == 'Followup__c') return 'Due_Date__c';
        if (sObjectName == 'Site_Visit__c') return 'Scheduled_Date__c';
        return 'CreatedDate';
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PRIVATE HELPERS — Field Resolution & Parsing
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Resolves a possibly-dotted field path (e.g., Lead__r.Full_Name__c).
     */
    private static String resolveFieldValue(SObject rec, String fieldPath) {
        if (rec == null || String.isBlank(fieldPath)) return '';
        try {
            if (fieldPath.contains('.')) {
                List<String> parts = fieldPath.split('\\.');
                SObject current = rec;
                for (Integer i = 0; i < parts.size() - 1; i++) {
                    current = current.getSObject(parts[i]);
                    if (current == null) return '';
                }
                Object val = current.get(parts[parts.size() - 1]);
                return formatFieldValue(val);
            } else {
                Object val = rec.get(fieldPath);
                return formatFieldValue(val);
            }
        } catch (Exception e) {
            return '';
        }
    }

    /**
     * @description Formats a field value for LWC consumption.
     *              DateTime/Date values are formatted as ISO 8601 strings
     *              so lightning-formatted-date-time can render them correctly.
     */
    private static String formatFieldValue(Object val) {
        if (val == null) return '';
        if (val instanceof DateTime) {
            return ((DateTime) val).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }
        if (val instanceof Date) {
            Date d = (Date) val;
            DateTime dt = DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0));
            return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }
        return String.valueOf(val);
    }

    private static List<String> parseCsv(String csv) {
        List<String> result = new List<String>();
        if (String.isBlank(csv)) return result;
        for (String s : csv.split(',')) {
            String trimmed = s.trim();
            if (String.isNotBlank(trimmed)) result.add(trimmed);
        }
        return result;
    }

    private static Map<String, Object> parseStatusActions(String jsonStr) {
        if (String.isBlank(jsonStr)) return new Map<String, Object>();
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    private static String getStatusFieldForObject(String jsonStr, String objName) {
        Map<String, Object> actions = parseStatusActions(jsonStr);
        if (actions.containsKey(objName)) {
            Map<String, Object> objActions = (Map<String, Object>) actions.get(objName);
            return (String) objActions.get('statusField');
        }
        return null;
    }

    private static List<Dashboard_Field_Config__mdt> getFieldsForObjectAndContext(
        List<Dashboard_Field_Config__mdt> allFields,
        String sObjectName,
        String context
    ) {
        List<Dashboard_Field_Config__mdt> result = new List<Dashboard_Field_Config__mdt>();
        for (Dashboard_Field_Config__mdt f : allFields) {
            if (f.SObject_Name__c != sObjectName) continue;
            if (f.Context__c != context && f.Context__c != 'BOTH') continue;
            result.add(f);
        }
        return result;
    }

    @TestVisible
    private static void clearCache() {
        cachedTabConfigs = null;
        cachedFieldConfigs = null;
        cachedProfileName = null;
        cachedHeadProfiles = null;
    }
}