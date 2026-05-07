/**
 * @description The BookingTrigger.
 * @author : Arun Kumar N
 * @createdDate : 21/12/2025
 * @status : Active trigger
 */
trigger BookingTrigger on Booking__c (before insert, before update) {
    if(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        
    }
}