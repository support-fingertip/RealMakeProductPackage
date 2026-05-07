public with sharing class RoundRobinController {
    
    @AuraEnabled
    public static Map<String, Object> getConfigurationData() {
        Map<String, Object> data = new Map<String, Object>();
        data.put('sources', getPicklists(Lead__c.Lead_Source__c));
        data.put('zones', getPicklists(Lead__c.Zone__c));
        
        List<Map<String, String>> users = new List<Map<String, String>>();
        for(User u : [SELECT Id, Name FROM User WHERE IsActive = true ORDER BY Name ASC LIMIT 1000]) {
            users.add(new Map<String, String>{'label' => u.Name, 'value' => u.Id});
        }
        data.put('users', users);
        return data;
    }

    @AuraEnabled
    public static List<Round_Robin__c> getExistingBuckets() {
        return [SELECT Id, Name, Project__c, Project__r.Name, Zone__c, Source__c, Customer_Type__c, Is_Active__c,
                (SELECT Id, User__c, Assignment_Type__c FROM Round_Robin_Members__r WHERE Is_Active__c = true) 
                FROM Round_Robin__c ORDER BY CreatedDate DESC];
    }

@AuraEnabled(cacheable=true)
public static List<User> getActiveUsers() {
    return [SELECT Id, Name, Email, Profile.Name FROM User WHERE IsActive = TRUE ORDER BY Name LIMIT 2000];
}
    @AuraEnabled
    public static void saveBucket(Round_Robin__c bucket, Map<String, List<String>> categorizedUsers) {
        try {
            upsert bucket;
            delete [SELECT Id FROM Round_Robin_Member__c WHERE Round_Robin__c = :bucket.Id];
            
            List<Round_Robin_Member__c> members = new List<Round_Robin_Member__c>();
            for(String type : categorizedUsers.keySet()) {
                if(categorizedUsers.get(type) == null) continue;
                for(String uId : categorizedUsers.get(type)) {
                    members.add(new Round_Robin_Member__c(
                        Round_Robin__c = bucket.Id, User__c = uId, Assignment_Type__c = type, Is_Active__c = true
                    ));
                }
            }
            insert members;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    private static List<Map<String, String>> getPicklists(Schema.SObjectField field) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Schema.PicklistEntry pe : field.getDescribe().getPicklistValues()) {
            options.add(new Map<String, String>{'label' => pe.getLabel(), 'value' => pe.getValue()});
        }
        return options;
    }
}