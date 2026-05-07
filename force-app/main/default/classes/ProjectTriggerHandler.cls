/**
 * @description Trigger handler for Project__c validation rules.
 * Rules: PROJECT_R04, PROJECT_R05
 */
public with sharing class ProjectTriggerHandler {

    public static void handleBeforeDelete(List<Project__c> projects) {
        Set<Id> projectIds = new Set<Id>();
        for (Project__c p : projects) {
            projectIds.add(p.Id);
        }

        // PROJECT_R04: Prevent deletion if children exist
        Map<Id, Integer> towerCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Project__c, COUNT(Id) cnt FROM Tower__c WHERE Project__c IN :projectIds GROUP BY Project__c
        ]) {
            towerCounts.put((Id) ar.get('Project__c'), (Integer) ar.get('cnt'));
        }

        for (Project__c p : projects) {
            if (towerCounts.containsKey(p.Id) && towerCounts.get(p.Id) > 0) {
                p.addError('Cannot delete project. Towers exist under this project.');
            }
        }
    }

    public static void handleBeforeUpdate(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        Set<Id> completingProjects = new Set<Id>();
        for (Project__c p : newList) {
            if (p.Project_Status__c == 'Completed' && oldMap.get(p.Id).Project_Status__c != 'Completed') {
                completingProjects.add(p.Id);
            }
        }

        if (!completingProjects.isEmpty()) {
            // PROJECT_R05: Cannot complete if Available/Blocked units exist
            Map<Id, Integer> unitCounts = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Project__c, COUNT(Id) cnt FROM Unit__c
                WHERE Project__c IN :completingProjects
                AND Status__c IN ('Available', 'Blocked')
                GROUP BY Project__c
            ]) {
                unitCounts.put((Id) ar.get('Project__c'), (Integer) ar.get('cnt'));
            }

            for (Project__c p : newList) {
                if (completingProjects.contains(p.Id) && unitCounts.containsKey(p.Id) && unitCounts.get(p.Id) > 0) {
                    p.addError('Cannot mark project as Completed. There are still Available or Blocked units.');
                }
            }
        }
    }
}