public with sharing class RoundRobinConfiguratorController {

    // ─── Wrapper Classes ────────────────────────────────────────────
    public class ConfigWrapper {
        @AuraEnabled public List<FieldDef> filterFields;
        @AuraEnabled public List<LeadFieldOption> leadFields;
        @AuraEnabled public List<String> assignmentTypes;
        @AuraEnabled public List<UserOption> activeUsers;
        @AuraEnabled public Map<String, Decimal> fieldPriorityMap;
    }

    public class FieldDef {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
    }

    public class LeadFieldOption {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public String referenceObjectName;
    }

    public class UserOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class LookupResult {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }

    public class BucketWrapper {
        @AuraEnabled public Round_Robin__c bucket;
        @AuraEnabled public List<Round_Robin_Filter__c> filters;
        @AuraEnabled public List<Round_Robin_Member__c> members;
    }

    public class FieldPriorityWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public Decimal priority;
        @AuraEnabled public Boolean active;
    }

    public class ConfigSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal totalPriority;
        @AuraEnabled public Integer filterCount;
        @AuraEnabled public Integer memberCount;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    // ─── Get All Configurations (List View) ───────────────────────
    @AuraEnabled
    public static List<ConfigSummary> getAllConfigurations() {
        List<ConfigSummary> results = new List<ConfigSummary>();
        for (Round_Robin__c rr : [
            SELECT Id, Name, Is_Active__c, Total_Priority__c, LastModifiedDate,
                   (SELECT Id FROM Round_Robin_Filters__r),
                   (SELECT Id FROM Round_Robin_Members__r WHERE Is_Active__c = true)
            FROM Round_Robin__c
            ORDER BY Is_Active__c DESC, Name ASC
        ]) {
            ConfigSummary cs = new ConfigSummary();
            cs.id = rr.Id;
            cs.name = rr.Name;
            cs.isActive = rr.Is_Active__c;
            cs.totalPriority = rr.Total_Priority__c;
            cs.filterCount = rr.Round_Robin_Filters__r.size();
            cs.memberCount = rr.Round_Robin_Members__r.size();
            cs.lastModifiedDate = rr.LastModifiedDate;
            results.add(cs);
        }
        return results;
    }

    // ─── Delete Configuration ─────────────────────────────────────
    @AuraEnabled
    public static void deleteConfiguration(Id bucketId) {
        try {
            delete [SELECT Id FROM Round_Robin__c WHERE Id = :bucketId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting configuration: ' + e.getMessage());
        }
    }

    // ─── Toggle Active Status ─────────────────────────────────────
    @AuraEnabled
    public static void toggleActive(Id bucketId, Boolean isActive) {
        try {
            update new Round_Robin__c(Id = bucketId, Is_Active__c = isActive);
        } catch (Exception e) {
            throw new AuraHandledException('Error toggling active status: ' + e.getMessage());
        }
    }

    // ─── Get Active Users ───────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<User> getActiveUsers() {
        return [SELECT Id, Name, Profile.Name FROM User WHERE IsActive = TRUE ORDER BY Name LIMIT 2000];
    }

    // ─── Universal Config ───────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static ConfigWrapper getUniversalConfig() {
        ConfigWrapper config = new ConfigWrapper();
        config.filterFields = new List<FieldDef>();
        config.leadFields = new List<LeadFieldOption>();
        config.assignmentTypes = new List<String>();
        config.activeUsers = new List<UserOption>();
        config.fieldPriorityMap = new Map<String, Decimal>();

        // 1. Legacy field set (backward compat)
        Schema.FieldSet fs = SObjectType.Round_Robin__c.FieldSets.RR_Filter_Fields;
        for (Schema.FieldSetMember f : fs.getFields()) {
            FieldDef fd = new FieldDef();
            fd.apiName = f.getFieldPath();
            fd.label = f.getLabel();
            fd.type = String.valueOf(f.getType());
            config.filterFields.add(fd);
        }

        // 2. All Lead__c fields via Describe with reference object detection
        Map<String, Schema.SObjectField> leadFieldMap = Schema.SObjectType.Lead__c.fields.getMap();
        for (String fieldName : leadFieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = leadFieldMap.get(fieldName).getDescribe();
            if (!dfr.isAccessible() || !dfr.isFilterable()) continue;
            LeadFieldOption lf = new LeadFieldOption();
            lf.apiName = dfr.getName();
            lf.label = dfr.getLabel();
            lf.type = String.valueOf(dfr.getType());

            // Detect reference object for lookup fields
            if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                List<Schema.SObjectType> refs = dfr.getReferenceTo();
                if (!refs.isEmpty()) {
                    lf.referenceObjectName = refs[0].getDescribe().getName();
                }
            }

            config.leadFields.add(lf);
        }

        // 3. Assignment types
        Schema.DescribeFieldResult fieldResult = Round_Robin_Member__c.Assignment_Type__c.getDescribe();
        for (Schema.PicklistEntry pe : fieldResult.getPicklistValues()) {
            if (pe.isActive()) {
                config.assignmentTypes.add(pe.getValue());
            }
        }

        // 4. Active Users
        for (User u : [SELECT Id, Name FROM User WHERE IsActive = TRUE ORDER BY Name LIMIT 2000]) {
            UserOption uo = new UserOption();
            uo.label = u.Name;
            uo.value = u.Id;
            config.activeUsers.add(uo);
        }

        // 5. Field Priority Map from master table
        for (Round_Robin_Field_Priority__c fp : [SELECT Field_API_Name__c, Priority__c
                                                  FROM Round_Robin_Field_Priority__c
                                                  WHERE Active__c = true]) {
            config.fieldPriorityMap.put(fp.Field_API_Name__c, fp.Priority__c);
        }

        return config;
    }

    // ─── Get Picklist Values for a Lead Field ───────────────────────
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getLeadFieldPicklistValues(String fieldApiName) {
        List<PicklistOption> options = new List<PicklistOption>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Lead__c.fields.getMap();

        String normalizedName = fieldApiName.toLowerCase();
        if (!fieldMap.containsKey(normalizedName)) {
            return options;
        }

        Schema.DescribeFieldResult dfr = fieldMap.get(normalizedName).getDescribe();
        if (dfr.getType() == Schema.DisplayType.PICKLIST || dfr.getType() == Schema.DisplayType.MULTIPICKLIST) {
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe.isActive()) {
                    PicklistOption po = new PicklistOption();
                    po.label = pe.getLabel();
                    po.value = pe.getValue();
                    options.add(po);
                }
            }
        }
        return options;
    }

    // ─── Dynamic Lookup Search ──────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchLookup(String objectName, String searchText) {
        List<LookupResult> results = new List<LookupResult>();
        if (String.isBlank(objectName) || String.isBlank(searchText)) return results;

        String safeSearch = String.escapeSingleQuotes(searchText.trim()) + '%';
        String safeObject = String.escapeSingleQuotes(objectName.trim());

        Schema.SObjectType targetType = Schema.getGlobalDescribe().get(safeObject);
        if (targetType == null) return results;

        String query = 'SELECT Id, Name FROM ' + safeObject +
                       ' WHERE Name LIKE :safeSearch ORDER BY Name LIMIT 10';
        for (SObject rec : Database.query(query)) {
            LookupResult lr = new LookupResult();
            lr.id = (String) rec.get('Id');
            lr.name = (String) rec.get('Name');
            results.add(lr);
        }
        return results;
    }

    // ─── Save Configuration with Dynamic Filters + Priority ─────────
    @AuraEnabled
    public static Id saveConfiguration(Round_Robin__c bucket, List<Round_Robin_Member__c> members, List<Round_Robin_Filter__c> filters) {
        try {
            // Calculate Total_Priority__c from filter Field_Priority__c values
            Decimal totalPriority = 0;
            if (filters != null) {
                for (Round_Robin_Filter__c f : filters) {
                    if (f.Field_Priority__c != null) {
                        totalPriority += f.Field_Priority__c;
                    }
                }
            }
            bucket.Total_Priority__c = totalPriority;

            // 1. Save Bucket
            upsert bucket;

            // 2. Prepare members
            for (Round_Robin_Member__c m : members) {
                m.Round_Robin__c = bucket.Id;
                m.Unique_Key__c = bucket.Id + '-' + m.User__c + '-' + m.Assignment_Type__c;
            }

            // 3. Match existing members
            Map<String, Id> existingMemberMap = new Map<String, Id>();
            for (Round_Robin_Member__c existing : [SELECT Id, Unique_Key__c
                                                    FROM Round_Robin_Member__c
                                                    WHERE Round_Robin__c = :bucket.Id]) {
                if (existing.Unique_Key__c != null) {
                    existingMemberMap.put(existing.Unique_Key__c, existing.Id);
                }
            }

            Set<String> incomingKeys = new Set<String>();
            for (Round_Robin_Member__c m : members) {
                if (existingMemberMap.containsKey(m.Unique_Key__c)) {
                    m.Id = existingMemberMap.get(m.Unique_Key__c);
                }
                incomingKeys.add(m.Unique_Key__c);
            }

            List<Round_Robin_Member__c> toDelete = new List<Round_Robin_Member__c>();
            for (String key : existingMemberMap.keySet()) {
                if (!incomingKeys.contains(key)) {
                    toDelete.add(new Round_Robin_Member__c(Id = existingMemberMap.get(key)));
                }
            }
            if (!toDelete.isEmpty()) {
                delete toDelete;
            }

            if (!members.isEmpty()) {
                upsert members;
            }

            // 4. Handle Filters: Delete old, insert new
            List<Round_Robin_Filter__c> existingFilters = [SELECT Id FROM Round_Robin_Filter__c WHERE Round_Robin__c = :bucket.Id];
            if (!existingFilters.isEmpty()) {
                delete existingFilters;
            }

            if (filters != null && !filters.isEmpty()) {
                for (Round_Robin_Filter__c f : filters) {
                    f.Round_Robin__c = bucket.Id;
                }
                insert filters;
            }

            return bucket.Id;

        } catch (Exception e) {
            throw new AuraHandledException('Error saving configuration: ' + e.getMessage());
        }
    }

    // ─── Load Existing Configuration for Edit ───────────────────────
    @AuraEnabled(cacheable=true)
    public static BucketWrapper getExistingConfiguration(Id bucketId) {
        BucketWrapper wrapper = new BucketWrapper();

        wrapper.bucket = [SELECT Id, Name, Is_Active__c, Total_Priority__c,
                                 Last_Index_Pre_Sales__c, Last_Index_Sales__c,
                                 Last_Index_CP__c, Last_Index_Post_Sales__c, Last_Reset__c
                          FROM Round_Robin__c
                          WHERE Id = :bucketId
                          LIMIT 1];

        wrapper.filters = [SELECT Id, Field_API_Name__c, Field_Label__c, Field_Value__c,
                                  Display_Value__c, Field_Type__c, Preference_Order__c, Field_Priority__c
                           FROM Round_Robin_Filter__c
                           WHERE Round_Robin__c = :bucketId
                           ORDER BY Preference_Order__c ASC];

        wrapper.members = [SELECT Id, User__c, Assignment_Type__c, Is_Active__c,
                                  Sequence__c, Weight__c, Order__c, Unique_Key__c
                           FROM Round_Robin_Member__c
                           WHERE Round_Robin__c = :bucketId
                           ORDER BY Assignment_Type__c, Order__c ASC];

        return wrapper;
    }

    // ─── Check for Duplicate Filter Combination ─────────────────────
    @AuraEnabled
    public static Boolean checkDuplicateFilters(Id excludeBucketId, List<Round_Robin_Filter__c> filters) {
        if (filters == null || filters.isEmpty()) return false;

        String incomingSignature = buildFilterSignature(filters);

        List<Round_Robin__c> activeBuckets;
        if (excludeBucketId != null) {
            activeBuckets = [SELECT Id FROM Round_Robin__c WHERE Is_Active__c = true AND Id != :excludeBucketId];
        } else {
            activeBuckets = [SELECT Id FROM Round_Robin__c WHERE Is_Active__c = true];
        }

        if (activeBuckets.isEmpty()) return false;

        Set<Id> bucketIds = new Set<Id>();
        for (Round_Robin__c b : activeBuckets) {
            bucketIds.add(b.Id);
        }

        Map<Id, List<Round_Robin_Filter__c>> bucketFiltersMap = new Map<Id, List<Round_Robin_Filter__c>>();
        for (Round_Robin_Filter__c f : [SELECT Id, Round_Robin__c, Field_API_Name__c, Field_Value__c
                                         FROM Round_Robin_Filter__c
                                         WHERE Round_Robin__c IN :bucketIds
                                         ORDER BY Field_API_Name__c, Field_Value__c]) {
            if (!bucketFiltersMap.containsKey(f.Round_Robin__c)) {
                bucketFiltersMap.put(f.Round_Robin__c, new List<Round_Robin_Filter__c>());
            }
            bucketFiltersMap.get(f.Round_Robin__c).add(f);
        }

        for (Id bId : bucketFiltersMap.keySet()) {
            String existingSignature = buildFilterSignature(bucketFiltersMap.get(bId));
            if (existingSignature == incomingSignature) {
                return true;
            }
        }
        return false;
    }

    private static String buildFilterSignature(List<Round_Robin_Filter__c> filters) {
        List<String> parts = new List<String>();
        for (Round_Robin_Filter__c f : filters) {
            parts.add(f.Field_API_Name__c + '=' + f.Field_Value__c);
        }
        parts.sort();
        return String.join(parts, '|');
    }

    // ═══════════════════════════════════════════════════════════════
    // FIELD PRIORITY MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    @AuraEnabled(cacheable=true)
    public static List<FieldPriorityWrapper> getFieldPriorities() {
        List<FieldPriorityWrapper> results = new List<FieldPriorityWrapper>();
        for (Round_Robin_Field_Priority__c fp : [SELECT Id, Field_API_Name__c, Field_Label__c,
                                                        Priority__c, Active__c
                                                 FROM Round_Robin_Field_Priority__c
                                                 ORDER BY Priority__c DESC]) {
            FieldPriorityWrapper w = new FieldPriorityWrapper();
            w.id = fp.Id;
            w.fieldApiName = fp.Field_API_Name__c;
            w.fieldLabel = fp.Field_Label__c;
            w.priority = fp.Priority__c;
            w.active = fp.Active__c;
            results.add(w);
        }
        return results;
    }

    @AuraEnabled
    public static Id saveFieldPriority(String fieldApiName, String fieldLabel, Decimal priority, Boolean active) {
        try {
            List<Round_Robin_Field_Priority__c> existing = [SELECT Id FROM Round_Robin_Field_Priority__c
                                                             WHERE Field_API_Name__c = :fieldApiName LIMIT 1];
            Round_Robin_Field_Priority__c fp;
            if (!existing.isEmpty()) {
                fp = existing[0];
            } else {
                fp = new Round_Robin_Field_Priority__c();
                fp.Field_API_Name__c = fieldApiName;
            }
            fp.Field_Label__c = fieldLabel;
            fp.Priority__c = priority;
            fp.Active__c = active;
            upsert fp;
            return fp.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving field priority: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteFieldPriority(Id priorityId) {
        try {
            delete [SELECT Id FROM Round_Robin_Field_Priority__c WHERE Id = :priorityId];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting field priority: ' + e.getMessage());
        }
    }
}