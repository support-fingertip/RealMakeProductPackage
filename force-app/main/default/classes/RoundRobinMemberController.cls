public with sharing class RoundRobinMemberController {
    @AuraEnabled(cacheable=true)
    public static List<Round_Robin_Member__c> getMembers(Id roundRobinId) {
        return [
            SELECT Id, Name, User__r.Name, Is_Active__c, Assignment_Type__c
            FROM Round_Robin_Member__c
            WHERE Round_Robin__c = :roundRobinId
            ORDER BY Order__c ASC NULLS LAST, Name ASC
        ];
    }

    @AuraEnabled
    public static void toggleMemberStatus(Id memberId, Boolean isActive) {
        try {
            update new Round_Robin_Member__c(Id = memberId, Is_Active__c = isActive);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}