/**
 * @description Trigger on Cost_Sheet__c to evaluate discount limits,
 *              prevent manipulation of locked records, and manage
 *              unit blocking/unblocking on cost sheet lifecycle.
 */
trigger CostSheetTrigger on Cost_Sheet__c (before update, after insert, after update, after delete) {

    if (Trigger.isBefore && Trigger.isUpdate) {
        CostSheetTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }

    // When a Cost Sheet is created, block the mapped unit
    if (Trigger.isAfter && Trigger.isInsert) {
        Set<Id> unitIdsToBlock = new Set<Id>();
        for (Cost_Sheet__c cs : Trigger.new) {
            if (cs.Unit__c != null) {
                unitIdsToBlock.add(cs.Unit__c);
            }
        }
        if (!unitIdsToBlock.isEmpty()) {
            List<Unit__c> units = [
                SELECT Id FROM Unit__c WHERE Id IN :unitIdsToBlock AND Status__c = 'Available'
            ];
            for (Unit__c u : units) {
                u.Status__c = 'Blocked';
            }
            if (!units.isEmpty()) {
                update units;
            }
        }
    }

    // When a Cost Sheet status changes to Closed Lost, release unit back to Available
    if (Trigger.isAfter && Trigger.isUpdate) {
        Set<Id> unitIdsToRelease = new Set<Id>();
        for (Cost_Sheet__c cs : Trigger.new) {
            Cost_Sheet__c oldCs = Trigger.oldMap.get(cs.Id);
            if (cs.Status__c == 'Closed Lost' && oldCs.Status__c != 'Closed Lost' && cs.Unit__c != null) {
                unitIdsToRelease.add(cs.Unit__c);
            }
        }
        if (!unitIdsToRelease.isEmpty()) {
            List<Unit__c> units = [
                SELECT Id FROM Unit__c WHERE Id IN :unitIdsToRelease AND Status__c = 'Blocked'
            ];
            for (Unit__c u : units) {
                u.Status__c = 'Available';
            }
            if (!units.isEmpty()) {
                update units;
            }
        }

        // When discount values change on an unlocked record (rejected/recalled),
        // recalculate derived fields via template steps
        Set<Id> csIdsToRecalc = new Set<Id>();
        for (Cost_Sheet__c cs : Trigger.new) {
            Cost_Sheet__c oldCs = Trigger.oldMap.get(cs.Id);
            if (cs.Is_Locked__c == true) continue;
            Boolean discountChanged = false;
            for (Integer i = 1; i <= 6; i++) {
                String fld = NamespaceUtil.qualify('Discount_' + i + '__c');
                if (cs.get(fld) != oldCs.get(fld)) {
                    discountChanged = true;
                    break;
                }
            }
            if (discountChanged) csIdsToRecalc.add(cs.Id);
        }
        if (!csIdsToRecalc.isEmpty()) {
            for (Id csId : csIdsToRecalc) {
                CostSheetCalculationService.runPostSaveCalculation(csId);
            }
        }
    }

    // When a Cost Sheet is deleted, release the unit back to Available
    if (Trigger.isAfter && Trigger.isDelete) {
        Set<Id> unitIds = new Set<Id>();
        for (Cost_Sheet__c cs : Trigger.old) {
            if (cs.Unit__c != null) {
                unitIds.add(cs.Unit__c);
            }
        }

        if (!unitIds.isEmpty()) {
            // Only unblock units that are currently BLOCKED (don't change Booked/Sold units)
            List<Unit__c> unitsToRelease = [
                SELECT Id, Status__c FROM Unit__c
                WHERE Id IN :unitIds AND Status__c = 'Blocked'
            ];
            for (Unit__c u : unitsToRelease) {
                u.Status__c = 'Available';
            }
            if (!unitsToRelease.isEmpty()) {
                update unitsToRelease;
            }
        }
    }
}