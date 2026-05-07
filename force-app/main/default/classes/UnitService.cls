/**
 * @description Service class for Unit operations.
 * Rules: UNIT_R01-R06
 */
public with sharing class UnitService {

    /**
     * @description Get available units for a project, optionally filtered by tower
     */
    public static List<Unit__c> getAvailableUnits(Id projectId, Id towerId) {
        String query = 'SELECT Id, Unit_Number__c, Floor__c, Unit_Type__c, BHK_Type__c, ' +
            'Carpet_Area__c, Super_Builtup_Area__c, Base_Rate_Sqft__c, Base_Price__c, ' +
            'Facing__c, Status__c, Tower__c, Tower__r.Name, Project__c ' +
            'FROM Unit__c WHERE Project__c = :projectId AND Status__c = \'Available\'';
        if (towerId != null) {
            query += ' AND Tower__c = :towerId';
        }
        query += ' ORDER BY Tower__r.Name, Floor__c, Unit_Number__c';
        return Database.query(query);
    }

    /**
     * @description Validate unit status transition
     */
    public static Boolean isValidTransition(String fromStatus, String toStatus) {
        Map<String, Set<String>> validTransitions = new Map<String, Set<String>>{
            'Available' => new Set<String>{'Blocked', 'Held'},
            'Blocked' => new Set<String>{'Available', 'Booked'},
            'Booked' => new Set<String>{'Sold', 'Available'},
            'Sold' => new Set<String>{'Mortgaged'},
            'Mortgaged' => new Set<String>{'Sold'},
            'Held' => new Set<String>{'Available'}
        };
        Set<String> allowed = validTransitions.get(fromStatus);
        return allowed != null && allowed.contains(toStatus);
    }

    /**
     * @description Bulk update unit statuses (used by scheduled jobs)
     */
    public static void unblockExpiredUnits() {
        List<Unit__c> expiredUnits = [
            SELECT Id, Unit_Number__c, Blocked_By_Lead__c, Block_Expiry__c
            FROM Unit__c
            WHERE Status__c = 'Blocked'
            AND Block_Expiry__c <= TODAY
        ];

        if (expiredUnits.isEmpty()) return;

        for (Unit__c u : expiredUnits) {
            u.Status__c = 'Available';
            u.Blocked_By_Lead__c = null;
            u.Block_Expiry__c = null;
        }
        update expiredUnits;
    }
}