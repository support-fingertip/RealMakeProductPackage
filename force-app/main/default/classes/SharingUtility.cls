/**
 * @description Utility for Apex managed sharing (manual sharing).
 * Shares Lead__c, Followup__c (via Lead master-detail), and Site_Visit__c
 * records with specified users at configurable access levels.
 */
public with sharing class SharingUtility {

    /**
     * @description Share a Lead record with a user (Read/Write access).
     */
    public static void shareLeadWithUser(Id leadId, Id userId) {
        if (leadId == null || userId == null) return;

        // Skip if user is the record owner (owner already has full access)
        List<Lead__c> ownerCheck = [SELECT OwnerId FROM Lead__c WHERE Id = :leadId LIMIT 1];
        if (!ownerCheck.isEmpty() && ownerCheck[0].OwnerId == userId) return;

        // Check if share already exists
        List<Lead__Share> existing = [
            SELECT Id FROM Lead__Share
            WHERE ParentId = :leadId
            AND UserOrGroupId = :userId
            AND RowCause = :Schema.Lead__Share.RowCause.Manual
            LIMIT 1
        ];
        if (!existing.isEmpty()) return;

        Lead__Share share = new Lead__Share();
        share.ParentId = leadId;
        share.UserOrGroupId = userId;
        share.AccessLevel = 'Edit';
        share.RowCause = Schema.Lead__Share.RowCause.Manual;
        insert share;
    }

    /**
     * @description Share multiple Lead records with a user (Read/Write access).
     */
    public static void shareLeadsWithUser(List<Id> leadIds, Id userId) {
        shareLeadsWithUser(leadIds, userId, 'Edit');
    }

    /**
     * @description Share multiple Lead records with a user at a specified access level.
     * @param accessLevel 'Read' or 'Edit'
     */
    public static void shareLeadsWithUser(List<Id> leadIds, Id userId, String accessLevel) {
        if (leadIds == null || leadIds.isEmpty() || userId == null) return;

        String level = (accessLevel == 'Read') ? 'Read' : 'Edit';

        // Skip leads owned by the target user (sharing would be trivial)
        Set<Id> ownedByUser = new Set<Id>();
        for (Lead__c l : [SELECT Id FROM Lead__c WHERE Id IN :leadIds AND OwnerId = :userId]) {
            ownedByUser.add(l.Id);
        }

        Set<Id> alreadyShared = new Set<Id>();
        for (Lead__Share s : [
            SELECT ParentId FROM Lead__Share
            WHERE ParentId IN :leadIds
            AND UserOrGroupId = :userId
            AND RowCause = :Schema.Lead__Share.RowCause.Manual
        ]) {
            alreadyShared.add(s.ParentId);
        }

        List<Lead__Share> toInsert = new List<Lead__Share>();
        for (Id lid : leadIds) {
            if (alreadyShared.contains(lid) || ownedByUser.contains(lid)) continue;

            Lead__Share share = new Lead__Share();
            share.ParentId = lid;
            share.UserOrGroupId = userId;
            share.AccessLevel = level;
            share.RowCause = Schema.Lead__Share.RowCause.Manual;
            toInsert.add(share);
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    /**
     * @description Remove manual sharing of a Lead record from a user.
     */
    public static void removeLeadShare(Id leadId, Id userId) {
        if (leadId == null || userId == null) return;

        List<Lead__Share> shares = [
            SELECT Id FROM Lead__Share
            WHERE ParentId = :leadId
            AND UserOrGroupId = :userId
            AND RowCause = :Schema.Lead__Share.RowCause.Manual
        ];
        if (!shares.isEmpty()) {
            delete shares;
        }
    }

    /**
     * @description Remove manual sharing of multiple Lead records from their temp owners.
     * @param leadIdToUserId Map of Lead Id to User Id to remove sharing for.
     */
    public static void removeLeadShares(Map<Id, Id> leadIdToUserId) {
        if (leadIdToUserId == null || leadIdToUserId.isEmpty()) return;

        Set<Id> leadIds = leadIdToUserId.keySet();
        List<Lead__Share> allShares = [
            SELECT Id, ParentId, UserOrGroupId FROM Lead__Share
            WHERE ParentId IN :leadIds
            AND RowCause = :Schema.Lead__Share.RowCause.Manual
        ];

        List<Lead__Share> toDelete = new List<Lead__Share>();
        for (Lead__Share s : allShares) {
            Id expectedUserId = leadIdToUserId.get(s.ParentId);
            if (expectedUserId != null && s.UserOrGroupId == expectedUserId) {
                toDelete.add(s);
            }
        }

        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SITE VISIT SHARING (per-status access levels)
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Share multiple Site Visit records with a user (Read/Write access).
     */
    public static void shareSiteVisitsWithUser(List<Id> siteVisitIds, Id userId) {
        shareSiteVisitsWithUser(siteVisitIds, userId, 'Edit');
    }

    /**
     * @description Share multiple Site Visit records with a user at a specified access level.
     */
    public static void shareSiteVisitsWithUser(List<Id> siteVisitIds, Id userId, String accessLevel) {
        if (siteVisitIds == null || siteVisitIds.isEmpty() || userId == null) return;

        String level = (accessLevel == 'Read') ? 'Read' : 'Edit';

        // Skip SVs owned by the target user (sharing would be trivial)
        Set<Id> ownedByUser = new Set<Id>();
        for (Site_Visit__c sv : [SELECT Id FROM Site_Visit__c WHERE Id IN :siteVisitIds AND OwnerId = :userId]) {
            ownedByUser.add(sv.Id);
        }

        // Find existing shares to avoid duplicates
        Set<Id> alreadyShared = new Set<Id>();
        for (Site_Visit__Share s : [
            SELECT ParentId FROM Site_Visit__Share
            WHERE ParentId IN :siteVisitIds
            AND UserOrGroupId = :userId
            AND RowCause = :Schema.Site_Visit__Share.RowCause.Manual
        ]) {
            alreadyShared.add(s.ParentId);
        }

        List<Site_Visit__Share> toInsert = new List<Site_Visit__Share>();
        for (Id svId : siteVisitIds) {
            if (alreadyShared.contains(svId) || ownedByUser.contains(svId)) continue;

            Site_Visit__Share share = new Site_Visit__Share();
            share.ParentId = svId;
            share.UserOrGroupId = userId;
            share.AccessLevel = level;
            share.RowCause = Schema.Site_Visit__Share.RowCause.Manual;
            toInsert.add(share);
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    /**
     * @description Share Site Visits for given leads with a user.
     * Completed & Cancelled → Read access; Scheduled & Re-Scheduled → Edit access.
     */
    public static void shareSiteVisitsForLeads(List<Id> leadIds, Id userId) {
        if (leadIds == null || leadIds.isEmpty() || userId == null) return;

        List<Site_Visit__c> siteVisits = [
            SELECT Id, Status__c, OwnerId FROM Site_Visit__c
            WHERE Lead__c IN :leadIds
            AND Status__c IN ('Scheduled', 'Re-Scheduled', 'Completed', 'Cancelled')
        ];

        List<Id> readAccessIds = new List<Id>();
        List<Id> editAccessIds = new List<Id>();

        for (Site_Visit__c sv : siteVisits) {
            if (sv.OwnerId == userId) continue; // Skip - owner already has full access
            if (sv.Status__c == 'Completed' || sv.Status__c == 'Cancelled') {
                readAccessIds.add(sv.Id);
            } else {
                editAccessIds.add(sv.Id);
            }
        }

        if (!readAccessIds.isEmpty()) {
            shareSiteVisitsWithUser(readAccessIds, userId, 'Read');
        }
        if (!editAccessIds.isEmpty()) {
            shareSiteVisitsWithUser(editAccessIds, userId, 'Edit');
        }
    }

    /**
     * @description Remove manual Site Visit shares for leads from a user.
     */
    public static void removeSiteVisitSharesForLeads(List<Id> leadIds, Id userId) {
        if (leadIds == null || leadIds.isEmpty() || userId == null) return;

        List<Site_Visit__c> siteVisits = [
            SELECT Id FROM Site_Visit__c WHERE Lead__c IN :leadIds
        ];
        if (siteVisits.isEmpty()) return;

        Set<Id> svIds = new Set<Id>();
        for (Site_Visit__c sv : siteVisits) {
            svIds.add(sv.Id);
        }

        List<Site_Visit__Share> toDelete = [
            SELECT Id FROM Site_Visit__Share
            WHERE ParentId IN :svIds
            AND UserOrGroupId = :userId
            AND RowCause = :Schema.Site_Visit__Share.RowCause.Manual
        ];

        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    /**
     * @description Remove manual Site Visit shares for multiple leads mapped to temp owners.
     */
    public static void removeSiteVisitSharesForLeads(Map<Id, Id> leadIdToUserId) {
        if (leadIdToUserId == null || leadIdToUserId.isEmpty()) return;

        Set<Id> leadIds = leadIdToUserId.keySet();
        List<Site_Visit__c> siteVisits = [
            SELECT Id, Lead__c FROM Site_Visit__c WHERE Lead__c IN :leadIds
        ];
        if (siteVisits.isEmpty()) return;

        // Build svId → userId map
        Map<Id, Id> svIdToUserId = new Map<Id, Id>();
        for (Site_Visit__c sv : siteVisits) {
            Id uid = leadIdToUserId.get(sv.Lead__c);
            if (uid != null) {
                svIdToUserId.put(sv.Id, uid);
            }
        }

        Set<Id> svIds = svIdToUserId.keySet();
        List<Site_Visit__Share> allShares = [
            SELECT Id, ParentId, UserOrGroupId FROM Site_Visit__Share
            WHERE ParentId IN :svIds
            AND RowCause = :Schema.Site_Visit__Share.RowCause.Manual
        ];

        List<Site_Visit__Share> toDelete = new List<Site_Visit__Share>();
        for (Site_Visit__Share s : allShares) {
            Id expectedUserId = svIdToUserId.get(s.ParentId);
            if (expectedUserId != null && s.UserOrGroupId == expectedUserId) {
                toDelete.add(s);
            }
        }

        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }
}