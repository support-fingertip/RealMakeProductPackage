public with sharing class DashboardConfigController {

    @AuraEnabled(cacheable=true)
    public static List<Dashboard_Configuration__c> getAllDashboardConfigs() {
        return [SELECT Id, Name, Description__c, Active__c, LastModifiedDate
                FROM Dashboard_Configuration__c
                ORDER BY LastModifiedDate DESC];
    }

    @AuraEnabled(cacheable=true)
    public static Dashboard_Configuration__c getDashboardConfig(String configId) {
        return [SELECT Id, Name, Description__c, Active__c, Configuration_JSON__c
                FROM Dashboard_Configuration__c
                WHERE Id = :configId LIMIT 1];
    }

    @AuraEnabled
    public static String saveDashboardConfig(String configId, String configName,
                                              String description, Boolean active,
                                              String configJson) {
        try {
            Dashboard_Configuration__c config;
            if (String.isNotBlank(configId)) {
                config = [SELECT Id FROM Dashboard_Configuration__c WHERE Id = :configId LIMIT 1];
            } else {
                config = new Dashboard_Configuration__c();
            }
            config.Name = configName;
            config.Description__c = description;
            config.Active__c = active;
            config.Configuration_JSON__c = configJson;
            upsert config;
            return config.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving dashboard: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteDashboardConfig(String configId) {
        try {
            delete [SELECT Id FROM Dashboard_Configuration__c WHERE Id = :configId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting dashboard: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String cloneDashboardConfig(String configId) {
        try {
            Dashboard_Configuration__c original = [
                SELECT Name, Description__c, Configuration_JSON__c
                FROM Dashboard_Configuration__c WHERE Id = :configId LIMIT 1
            ];
            Dashboard_Configuration__c cloneRec = original.clone(false, true);
            cloneRec.Name = original.Name + ' (Copy)';
            cloneRec.Active__c = false;
            insert cloneRec;
            return cloneRec.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error cloning dashboard: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAvailableDashboards() {
        List<Dashboard_Configuration__c> configs = [
            SELECT Id, Name, Description__c, Configuration_JSON__c
            FROM Dashboard_Configuration__c
            WHERE Active__c = true
            ORDER BY Name
        ];

        User currentUser = [SELECT Profile.Name, UserRole.Name
                             FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String currentProfile = currentUser.Profile.Name;
        String currentRole = currentUser.UserRole != null ? currentUser.UserRole.Name : '';
        String currentUserId = UserInfo.getUserId();

        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Dashboard_Configuration__c config : configs) {
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
        if (String.isBlank(configJson)) return true;

        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);
        List<Object> rules = (List<Object>) config.get('visibilityRules');

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
            }
        }
        return fields;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllObjects() {
        List<Map<String, String>> objects = new List<Map<String, String>>();
        for (Schema.SObjectType objType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult od = objType.getDescribe();
            if (od.isAccessible() && od.isQueryable()) {
                Map<String, String> o = new Map<String, String>();
                o.put('label', od.getLabel());
                o.put('value', od.getName());
                objects.add(o);
            }
        }
        return objects;
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

    // ── Cascading Hierarchy Filter ──

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getTopLevelUsers() {
        List<Map<String, String>> users = new List<Map<String, String>>();

        // Strategy 1: Users in top-level roles (ParentRoleId = null)
        Set<Id> topRoleIds = new Set<Id>();
        for (UserRole r : [SELECT Id FROM UserRole WHERE ParentRoleId = null]) {
            topRoleIds.add(r.Id);
        }

        if (!topRoleIds.isEmpty()) {
            for (User u : [SELECT Id, Name, UserRole.Name, Email
                            FROM User
                            WHERE UserRoleId IN :topRoleIds AND IsActive = true
                            ORDER BY Name]) {
                users.add(buildUserMap(u));
            }
        }

        // Strategy 2: If no top-level role users, try users in roles that have child roles (managers)
        if (users.isEmpty()) {
            Set<Id> parentRoleIds = new Set<Id>();
            for (UserRole r : [SELECT ParentRoleId FROM UserRole WHERE ParentRoleId != null]) {
                parentRoleIds.add(r.ParentRoleId);
            }
            if (!parentRoleIds.isEmpty()) {
                for (User u : [SELECT Id, Name, UserRole.Name, Email
                                FROM User
                                WHERE UserRoleId IN :parentRoleIds AND IsActive = true
                                ORDER BY Name]) {
                    users.add(buildUserMap(u));
                }
            }
        }

        // Strategy 3: If still empty, return all active users with roles
        if (users.isEmpty()) {
            for (User u : [SELECT Id, Name, UserRole.Name, Email
                            FROM User
                            WHERE UserRoleId != null AND IsActive = true
                            ORDER BY Name
                            LIMIT 200]) {
                users.add(buildUserMap(u));
            }
        }

        // Strategy 4: If still empty (no roles in org at all), return all active users
        if (users.isEmpty()) {
            for (User u : [SELECT Id, Name, Profile.Name, Email
                            FROM User
                            WHERE IsActive = true
                            ORDER BY Name
                            LIMIT 200]) {
                Map<String, String> m = new Map<String, String>();
                m.put('id', u.Id);
                m.put('name', u.Name);
                m.put('role', u.Profile != null ? u.Profile.Name : '');
                m.put('email', u.Email != null ? u.Email : '');
                users.add(m);
            }
        }

        return users;
    }

    private static Map<String, String> buildUserMap(User u) {
        Map<String, String> m = new Map<String, String>();
        m.put('id', u.Id);
        m.put('name', u.Name);
        m.put('role', u.UserRole != null ? u.UserRole.Name : '');
        m.put('email', u.Email != null ? u.Email : '');
        return m;
    }

    private static Map<String, String> buildUserMapWithTitle(User u) {
        Map<String, String> m = new Map<String, String>();
        m.put('id', u.Id);
        m.put('name', u.Name);
        m.put('role', u.Title != null ? u.Title : (u.UserRole != null ? u.UserRole.Name : ''));
        m.put('email', u.Email != null ? u.Email : '');
        return m;
    }

    // ── Role-based hierarchy methods ──

    @AuraEnabled
    public static Map<String, Object> getSubordinateUsers(String userId) {
        Map<String, Object> result = new Map<String, Object>();
        List<Map<String, String>> subordinates = new List<Map<String, String>>();

        User selectedUser = [SELECT Id, Name, UserRoleId, UserRole.Name
                              FROM User WHERE Id = :userId LIMIT 1];

        if (selectedUser.UserRoleId == null) {
            result.put('subordinates', subordinates);
            result.put('hasSubordinates', false);
            return result;
        }

        Set<Id> childRoleIds = new Set<Id>();
        for (UserRole r : [SELECT Id FROM UserRole WHERE ParentRoleId = :selectedUser.UserRoleId]) {
            childRoleIds.add(r.Id);
        }

        if (childRoleIds.isEmpty()) {
            result.put('subordinates', subordinates);
            result.put('hasSubordinates', false);
            return result;
        }

        for (User u : [SELECT Id, Name, UserRole.Name, Email
                        FROM User
                        WHERE UserRoleId IN :childRoleIds AND IsActive = true
                        ORDER BY Name]) {
            subordinates.add(buildUserMap(u));
        }

        result.put('subordinates', subordinates);
        result.put('hasSubordinates', !subordinates.isEmpty());
        return result;
    }

    public static Set<Id> getAllSubordinateUserIds(String userId) {
        Set<Id> allUserIds = new Set<Id>();
        allUserIds.add(userId);

        User selectedUser = [SELECT UserRoleId FROM User WHERE Id = :userId LIMIT 1];
        if (selectedUser.UserRoleId == null) return allUserIds;

        Set<Id> roleIds = new Set<Id>{ selectedUser.UserRoleId };
        Set<Id> allRoleIds = new Set<Id>{ selectedUser.UserRoleId };

        for (Integer i = 0; i < 6; i++) {
            Set<Id> childRoleIds = new Set<Id>();
            for (UserRole r : [SELECT Id FROM UserRole WHERE ParentRoleId IN :roleIds AND Id NOT IN :allRoleIds]) {
                childRoleIds.add(r.Id);
            }
            if (childRoleIds.isEmpty()) break;
            allRoleIds.addAll(childRoleIds);
            roleIds = childRoleIds;
        }

        for (User u : [SELECT Id FROM User WHERE UserRoleId IN :allRoleIds AND IsActive = true]) {
            allUserIds.add(u.Id);
        }

        return allUserIds;
    }

    // ── Manager-based hierarchy methods ──

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getTopLevelManagers() {
        List<Map<String, String>> users = new List<Map<String, String>>();

        // Strategy 1: Users who have direct reports but no manager themselves
        Set<Id> managerIds = new Set<Id>();
        for (User u : [SELECT ManagerId FROM User WHERE ManagerId != null AND IsActive = true]) {
            managerIds.add(u.ManagerId);
        }

        if (!managerIds.isEmpty()) {
            for (User u : [SELECT Id, Name, Title, UserRole.Name, Email
                            FROM User
                            WHERE Id IN :managerIds AND ManagerId = null AND IsActive = true
                            ORDER BY Name]) {
                users.add(buildUserMapWithTitle(u));
            }

            // Strategy 2: If no top-level managers (everyone has a manager), return all managers
            if (users.isEmpty()) {
                for (User u : [SELECT Id, Name, Title, UserRole.Name, Email
                                FROM User
                                WHERE Id IN :managerIds AND IsActive = true
                                ORDER BY Name
                                LIMIT 200]) {
                    users.add(buildUserMapWithTitle(u));
                }
            }
        }

        // Strategy 3: If no ManagerId usage in org, fall back to all active users
        if (users.isEmpty()) {
            for (User u : [SELECT Id, Name, Title, UserRole.Name, Email
                            FROM User
                            WHERE IsActive = true
                            ORDER BY Name
                            LIMIT 200]) {
                users.add(buildUserMapWithTitle(u));
            }
        }

        return users;
    }

    @AuraEnabled
    public static Map<String, Object> getDirectReports(String userId) {
        Map<String, Object> result = new Map<String, Object>();
        List<Map<String, String>> directReports = new List<Map<String, String>>();

        for (User u : [SELECT Id, Name, Title, UserRole.Name, Email
                        FROM User
                        WHERE ManagerId = :userId AND IsActive = true
                        ORDER BY Name]) {
            directReports.add(buildUserMapWithTitle(u));
        }

        result.put('subordinates', directReports);
        result.put('hasSubordinates', !directReports.isEmpty());
        return result;
    }

    public static Set<Id> getAllManagerSubordinateIds(String userId) {
        Set<Id> allUserIds = new Set<Id>();
        allUserIds.add(userId);

        Set<Id> currentLevelIds = new Set<Id>{ userId };

        // Walk down manager hierarchy (up to 6 levels)
        for (Integer i = 0; i < 6; i++) {
            Set<Id> nextLevelIds = new Set<Id>();
            for (User u : [SELECT Id FROM User WHERE ManagerId IN :currentLevelIds AND IsActive = true AND Id NOT IN :allUserIds]) {
                nextLevelIds.add(u.Id);
            }
            if (nextLevelIds.isEmpty()) break;
            allUserIds.addAll(nextLevelIds);
            currentLevelIds = nextLevelIds;
        }

        return allUserIds;
    }
}