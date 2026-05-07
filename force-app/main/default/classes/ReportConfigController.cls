public with sharing class ReportConfigController {

    @AuraEnabled(cacheable=true)
    public static List<Report_Configuration__c> getAllReportConfigs() {
        return [SELECT Id, Name, Description__c, Active__c, LastModifiedDate
                FROM Report_Configuration__c
                ORDER BY LastModifiedDate DESC];
    }

    @AuraEnabled(cacheable=true)
    public static Report_Configuration__c getReportConfig(String configId) {
        return [SELECT Id, Name, Description__c, Active__c, Configuration_JSON__c
                FROM Report_Configuration__c
                WHERE Id = :configId LIMIT 1];
    }

    @AuraEnabled
    public static String saveReportConfig(String configId, String configName,
                                           String description, Boolean active,
                                           String configJson) {
        try {
            Report_Configuration__c config;
            if (String.isNotBlank(configId)) {
                config = [SELECT Id FROM Report_Configuration__c WHERE Id = :configId LIMIT 1];
            } else {
                config = new Report_Configuration__c();
            }
            config.Name = configName;
            config.Description__c = description;
            config.Active__c = active;
            config.Configuration_JSON__c = configJson;
            upsert config;
            return config.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving report: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteReportConfig(String configId) {
        try {
            delete [SELECT Id FROM Report_Configuration__c WHERE Id = :configId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting report: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String cloneReportConfig(String configId) {
        try {
            Report_Configuration__c original = [
                SELECT Name, Description__c, Configuration_JSON__c
                FROM Report_Configuration__c WHERE Id = :configId LIMIT 1
            ];
            Report_Configuration__c cloneRec = original.clone(false, true);
            cloneRec.Name = original.Name + ' (Copy)';
            cloneRec.Active__c = false;
            insert cloneRec;
            return cloneRec.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error cloning report: ' + e.getMessage());
        }
    }

    // ── Visibility-based report access (for Report Viewer) ──

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAvailableReports() {
        List<Report_Configuration__c> configs = [
            SELECT Id, Name, Description__c, Configuration_JSON__c
            FROM Report_Configuration__c
            WHERE Active__c = true
            ORDER BY Name
        ];

        User currentUser = [SELECT Profile.Name, UserRole.Name
                             FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String currentProfile = currentUser.Profile.Name;
        String currentRole = currentUser.UserRole != null ? currentUser.UserRole.Name : '';
        String currentUserId = UserInfo.getUserId();

        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Report_Configuration__c config : configs) {
            if (isVisibleToUser(config.Configuration_JSON__c, currentProfile, currentRole, currentUserId)) {
                Map<String, String> item = new Map<String, String>();
                item.put('id', config.Id);
                item.put('name', config.Name);
                item.put('description', config.Description__c != null ? config.Description__c : '');
                result.add(item);
            }
        }
        return result;
    }

    private static Boolean isVisibleToUser(String configJson, String profileName, String roleName, String userId) {
        // System Administrators always see all reports
        if (profileName == 'System Administrator') return true;

        if (String.isBlank(configJson)) return true;

        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);
        List<Object> rules = (List<Object>) config.get('visibilityRules');

        // If no visibility rules defined, report is visible to all authenticated users
        if (rules == null || rules.isEmpty()) return true;

        for (Object ruleObj : rules) {
            Map<String, Object> rule = (Map<String, Object>) ruleObj;
            String ruleType = (String) rule.get('ruleType');
            String operator = (String) rule.get('operator');
            String value = (String) rule.get('value');

            String compareValue = '';
            if (ruleType == 'Profile') compareValue = profileName;
            else if (ruleType == 'Role') compareValue = roleName;
            else if (ruleType == 'User') compareValue = userId;

            Boolean matches = false;
            if (operator == 'equals') matches = compareValue == value;
            else if (operator == 'notEquals') matches = compareValue != value;
            else if (operator == 'contains') matches = compareValue != null && compareValue.contains(value);

            if (matches) return true;
        }
        return false;
    }

    // ── Metadata methods ──

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllObjects() {
        List<Map<String, String>> objects = new List<Map<String, String>>();
        // Suffixes for system/sharing/history objects to exclude
        Set<String> excludeSuffixes = new Set<String>{
            'Share', 'History', 'Feed', 'Tag', 'ChangeEvent', 'ViewStat', 'FieldHistory'
        };
        for (Schema.SObjectType objType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult od = objType.getDescribe();
            if (!od.isAccessible() || !od.isQueryable() || !od.isCreateable()) {
                continue;
            }
            String objName = od.getName();
            // Skip system/sharing/history objects
            Boolean skip = false;
            for (String suffix : excludeSuffixes) {
                if (objName.endsWith(suffix)) {
                    skip = true;
                    break;
                }
            }
            if (skip) continue;
            Map<String, String> o = new Map<String, String>();
            o.put('label', od.getLabel());
            o.put('value', objName);
            objects.add(o);
        }
        // Sort alphabetically by label
        objects.sort(new ObjectLabelComparator());
        return objects;
    }

    // Comparator to sort objects by label alphabetically
    private class ObjectLabelComparator implements Comparator<Map<String, String>> {
        public Integer compare(Map<String, String> a, Map<String, String> b) {
            String labelA = a.get('label') != null ? a.get('label').toLowerCase() : '';
            String labelB = b.get('label') != null ? b.get('label').toLowerCase() : '';
            return labelA.compareTo(labelB);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getObjectFields(String objectApiName) {
        List<Map<String, String>> fields = new List<Map<String, String>>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return fields;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
            if (fd.isAccessible()) {
                Map<String, String> f = new Map<String, String>();
                f.put('label', fd.getLabel());
                f.put('value', fd.getName());
                f.put('type', String.valueOf(fd.getType()));
                fields.add(f);

                // For lookup/reference fields, also add RelationshipName.Name as an option
                if (fd.getType() == Schema.DisplayType.REFERENCE && fd.getRelationshipName() != null) {
                    String relName = fd.getRelationshipName();
                    // Check if the referenced object has a Name field
                    List<Schema.SObjectType> refs = fd.getReferenceTo();
                    if (!refs.isEmpty()) {
                        Schema.DescribeSObjectResult refDesc = refs[0].getDescribe();
                        Map<String, Schema.SObjectField> refFields = refDesc.fields.getMap();
                        if (refFields.containsKey('name')) {
                            Map<String, String> relField = new Map<String, String>();
                            relField.put('label', fd.getLabel().replace(' ID', '').replace(' Id', '') + ' Name');
                            relField.put('value', relName + '.Name');
                            relField.put('type', 'REFERENCE_NAME');
                            fields.add(relField);
                        }
                    }
                }
            }
        }
        return fields;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLookupObjectFields(String objectApiName, String lookupFieldApiName) {
        List<Map<String, String>> fields = new List<Map<String, String>>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return fields;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        String lookupKey = lookupFieldApiName.toLowerCase();
        if (!fieldMap.containsKey(lookupKey)) return fields;

        Schema.DescribeFieldResult lookupFd = fieldMap.get(lookupKey).getDescribe();
        if (lookupFd.getType() != Schema.DisplayType.REFERENCE || lookupFd.getRelationshipName() == null) return fields;

        String relName = lookupFd.getRelationshipName();
        List<Schema.SObjectType> refs = lookupFd.getReferenceTo();
        if (refs.isEmpty()) return fields;

        Map<String, Schema.SObjectField> refFieldMap = refs[0].getDescribe().fields.getMap();
        for (String refFieldName : refFieldMap.keySet()) {
            Schema.DescribeFieldResult rfd = refFieldMap.get(refFieldName).getDescribe();
            if (rfd.isAccessible()) {
                Map<String, String> f = new Map<String, String>();
                f.put('label', rfd.getLabel() + ' (' + relName + '.' + rfd.getName() + ')');
                f.put('value', relName + '.' + rfd.getName());
                f.put('type', String.valueOf(rfd.getType()));
                fields.add(f);
            }
        }
        return fields;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getChildRelationships(String objectApiName) {
        List<Map<String, String>> relationships = new List<Map<String, String>>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return relationships;

        for (Schema.ChildRelationship cr : objType.getDescribe().getChildRelationships()) {
            if (cr.getRelationshipName() != null) {
                Schema.DescribeSObjectResult childDesc = cr.getChildSObject().getDescribe();
                if (childDesc.isAccessible() && childDesc.isQueryable()) {
                    Map<String, String> rel = new Map<String, String>();
                    rel.put('relationshipName', cr.getRelationshipName());
                    rel.put('childObject', childDesc.getName());
                    rel.put('childLabel', childDesc.getLabel());
                    rel.put('fieldName', cr.getField().getDescribe().getName());
                    relationships.add(rel);
                }
            }
        }
        return relationships;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPicklistValues(String objectApiName, String fieldApiName) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return options;

        Schema.DescribeFieldResult fd = objType.getDescribe().fields.getMap().get(fieldApiName).getDescribe();
        for (Schema.PicklistEntry pe : fd.getPicklistValues()) {
            if (pe.isActive()) {
                Map<String, String> opt = new Map<String, String>();
                opt.put('label', pe.getLabel());
                opt.put('value', pe.getValue());
                options.add(opt);
            }
        }
        return options;
    }

    // ── Visibility helpers (Profile, Role, User search) ──

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllProfiles() {
        List<Map<String, String>> profiles = new List<Map<String, String>>();
        for (Profile p : [SELECT Id, Name FROM Profile ORDER BY Name]) {
            Map<String, String> m = new Map<String, String>();
            m.put('label', p.Name);
            m.put('value', p.Name);
            profiles.add(m);
        }
        return profiles;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllRoles() {
        List<Map<String, String>> roles = new List<Map<String, String>>();
        for (UserRole r : [SELECT Id, Name FROM UserRole ORDER BY Name]) {
            Map<String, String> m = new Map<String, String>();
            m.put('label', r.Name);
            m.put('value', r.Name);
            roles.add(m);
        }
        return roles;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> searchUsers(String searchTerm) {
        List<Map<String, String>> users = new List<Map<String, String>>();
        String searchKey = '%' + searchTerm + '%';
        for (User u : [SELECT Id, Name, Email FROM User
                        WHERE Name LIKE :searchKey OR Email LIKE :searchKey LIMIT 20]) {
            Map<String, String> m = new Map<String, String>();
            m.put('label', u.Name + ' (' + u.Email + ')');
            m.put('value', u.Id);
            users.add(m);
        }
        return users;
    }
}