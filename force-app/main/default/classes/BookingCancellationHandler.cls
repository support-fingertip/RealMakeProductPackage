/**
 * @description Handles booking cancellation - releases the Unit back to Available status.
 * Called from Flow when Booking Status changes to 'Cancelled'.
 */
public with sharing class BookingCancellationHandler {

    // ==================== INPUT / OUTPUT WRAPPERS ====================

    public class CancellationRequest {
        @InvocableVariable(label='Booking ID' required=true)
        public Id bookingId;
    }

    public class CancellationResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;
    }

    // ==================== INVOCABLE METHOD ====================

    @InvocableMethod(label='Cancel Booking and Release Unit' description='Sets the Unit status to Available and clears Current Booking when a booking is cancelled')
    public static List<CancellationResult> cancelBookings(List<CancellationRequest> requests) {
        List<CancellationResult> results = new List<CancellationResult>();

        for (CancellationRequest request : requests) {
            results.add(processCancellation(request));
        }

        return results;
    }

    // ==================== CORE LOGIC ====================

    private static CancellationResult processCancellation(CancellationRequest request) {
        CancellationResult result = new CancellationResult();
        result.success = false;

        if (request.bookingId == null) {
            result.message = 'Booking ID is required';
            return result;
        }

        try {
            // Get the booking with its Unit
            Booking__c booking = [
                SELECT Id, Status__c, Unit__c, Cancellation_Date__c
                FROM Booking__c
                WHERE Id = :request.bookingId
                LIMIT 1
            ];

            if (booking.Unit__c == null) {
                result.message = 'No Unit linked to this booking';
                result.success = true;
                return result;
            }

            // Release the Unit - set status to Available and clear Current Booking
            Unit__c unit = new Unit__c(
                Id = booking.Unit__c,
                Status__c = PostSalesConstants.UNIT_STATUS_AVAILABLE,
                Current_Booking__c = null
            );
            update unit;

            result.success = true;
            result.message = 'Unit released successfully';

            // Apply Post Sales Configuration for Cancellation (auto-send email if configured)
            try {
                PostSalesAdminController.ConfigWrapper config = PostSalesAdminController.resolveConfigurationForRecord(
                    'Cancellation', request.bookingId, 'Booking__c'
                );
                if (config != null && config.autoSendEmail == true && config.emailTemplateId != null) {
                    String templateId = ConfigMatchingService.resolveEmailTemplateForAction(
                        'Cancellation', request.bookingId, 'Booking__c'
                    );
                    // Template resolution stores the email template ID for Flow to send
                    if (templateId != null) {
                        result.message += '. Email template resolved for auto-send.';
                    }
                }
            } catch (Exception configEx) {
                System.debug('Post Sales Config lookup for cancellation: ' + configEx.getMessage());
            }

        } catch (QueryException qe) {
            result.message = 'Booking not found: ' + qe.getMessage();
        } catch (DmlException de) {
            result.message = 'Error updating Unit: ' + de.getMessage();
        } catch (Exception e) {
            result.message = 'Unexpected error: ' + e.getMessage();
        }

        return result;
    }
}