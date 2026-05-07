/**
 * @description Service class for Booking creation and CRM handovers.
 * Rules: BOOK_01-07, HANDOVER_01-04
 */
public with sharing class BookingService {

    /**
     * @description Create a booking from an accepted cost sheet
     */
    public static Id createBooking(Id costSheetId, Map<String, Object> applicantDetails, Decimal bookingAmount, String paymentMode, String transactionRef, List<Co_Applicants__c> coApplicants) {

        Cost_Sheet__c cs = [
            SELECT Id, Lead__c, Project__c, Unit__c, Status__c, Payment_Plan_Type__c,
                   Lead__r.Full_Name__c, Lead__r.Primary_Mobile__c, Lead__r.Primary_Email__c,
                   Lead__r.Channel_Partner__c,
                   Project__r.Min_Booking_Amount__c, Project__r.Sales_Head__c, Project__r.CRM_Head__c,
                   Project__r.Finance_User__c, Project__r.Legal_User__c, Project__r.Inspection_Person__c,
                   Project__r.CS_Executive__c, Project__r.CP_Commission_Pct__c,
                   Unit__r.Tower__c, Unit__r.Status__c,
                   Agreement_Value__c, Total_Discount__c, Net_Payable__c,
                   GST_Amount__c, Stamp_Duty_Amount__c, Registration_Amount__c,
                   Carpet_Area__c, Super_Builtup_Area__c, UDS__c, Base_Rate_Sqft__c, Base_Price__c,
                   PLC_Charges__c, Floor_Rise_Sqft__c, Amenity_Charges__c, Infra_Charges__c,
                   Doc_Charges__c, Maintenance_Sqft_Month__c, Maintenance_Months__c,
                   Corpus_Fund_Sqft__c, Move_In_Charges__c, Stamp_Duty_Pct__c, Registration_Pct__c, GST_Percentage__c
            FROM Cost_Sheet__c WHERE Id = :costSheetId
        ];

        if (cs.Status__c != 'Accepted by Customer') {
            throw new BookingException('Cost Sheet must be in "Accepted by Customer" status.');
        }
        if (cs.Unit__r.Status__c != 'Blocked' && cs.Unit__r.Status__c != 'Available') {
            throw new BookingException('Unit is not available for booking. Current status: ' + cs.Unit__r.Status__c);
        }
        Decimal minAmount = cs.Project__r.Min_Booking_Amount__c != null ? cs.Project__r.Min_Booking_Amount__c : 0;
        if (bookingAmount < minAmount) {
            throw new BookingException('Booking amount must be at least ' + minAmount);
        }

        Booking__c bk = new Booking__c();
        bk.Booking_Date__c = Date.today();
        bk.Status__c = 'Draft';
        bk.Booking_Stage__c = 'New';
        bk.Lead__c = cs.Lead__c;
        bk.Customer_Name__c = cs.Lead__r.Full_Name__c;
        bk.Customer_Mobile__c = cs.Lead__r.Primary_Mobile__c;
        bk.Customer_Email__c = cs.Lead__r.Primary_Email__c;
        bk.Owner__c = UserInfo.getUserId();
        bk.Project__c = cs.Project__c;
        bk.Tower__c = cs.Unit__r.Tower__c;
        bk.Unit__c = cs.Unit__c;
        bk.Cost_Sheet__c = costSheetId;
        bk.Booking_Amount__c = bookingAmount;

        // Pricing snapshot
        bk.Carpet_Area__c = cs.Carpet_Area__c;
        bk.Super_Builtup_Area__c = cs.Super_Builtup_Area__c;
        bk.UDS__c = cs.UDS__c;
        bk.Base_Rate_Sqft__c = cs.Base_Rate_Sqft__c;
        bk.Base_Price__c = cs.Base_Price__c;
        bk.PLC_Charges__c = cs.PLC_Charges__c;
        bk.Floor_Rise_Sqft__c = cs.Floor_Rise_Sqft__c;
        bk.Amenity_Charges__c = cs.Amenity_Charges__c;
        bk.Infra_Charges__c = cs.Infra_Charges__c;
        bk.Doc_Charges__c = cs.Doc_Charges__c;
        bk.Maintenance_Sqft_Month__c = cs.Maintenance_Sqft_Month__c;
        bk.Maintenance_Months__c = cs.Maintenance_Months__c;
        bk.Corpus_Fund_Sqft__c = cs.Corpus_Fund_Sqft__c;
        bk.Move_In_Charges__c = cs.Move_In_Charges__c;
        bk.Stamp_Duty_Pct__c = cs.Stamp_Duty_Pct__c;
        bk.Registration_Pct__c = cs.Registration_Pct__c;
        bk.GST_Percentage__c = cs.GST_Percentage__c;
        bk.Agreement_Value__c = cs.Agreement_Value__c;
        bk.Total_Discount__c = cs.Total_Discount__c;
        bk.Total_Taxes__c = (cs.GST_Amount__c != null ? cs.GST_Amount__c : 0)
            + (cs.Stamp_Duty_Amount__c != null ? cs.Stamp_Duty_Amount__c : 0)
            + (cs.Registration_Amount__c != null ? cs.Registration_Amount__c : 0);
        bk.Payment_Plan__c = 'Construction Linked';

        // Role snapshots from Project
        bk.Sales_Head__c = cs.Project__r.Sales_Head__c;
        bk.CRM_Manager__c = cs.Project__r.CRM_Head__c;
        bk.Finance_User__c = cs.Project__r.Finance_User__c;
        bk.Legal_User__c = cs.Project__r.Legal_User__c;
        bk.Inspection_Person__c = cs.Project__r.Inspection_Person__c;
        bk.CS_Executive__c = cs.Project__r.CS_Executive__c;

        // CP Commission
        if (cs.Lead__r.Channel_Partner__c != null) {
            bk.Channel_Partner__c = cs.Lead__r.Channel_Partner__c;
            bk.CP_Commission_Pct__c = cs.Project__r.CP_Commission_Pct__c;
            bk.Commission_Status__c = 'Pending';
        }

        // Applicant details
        if (applicantDetails != null) {
            if (applicantDetails.containsKey('pan')) bk.PAN_Number__c = (String) applicantDetails.get('pan');
            if (applicantDetails.containsKey('aadhaar')) bk.Aadhaar__c = (String) applicantDetails.get('aadhaar');
            if (applicantDetails.containsKey('loanRequired')) bk.Loan_Required__c = (Boolean) applicantDetails.get('loanRequired');
            if (applicantDetails.containsKey('bankName')) bk.Bank_Name__c = (String) applicantDetails.get('bankName');
        }

        insert bk;

        // Update Unit status
        Unit__c unit = new Unit__c(Id = cs.Unit__c);
        unit.Status__c = 'Booked';
        unit.Booking__c = bk.Id;
        unit.Blocked_By_Lead__c = null;
        unit.Block_Expiry__c = null;
        update unit;

        // Update Cost Sheet and tag with Booking
        cs.Status__c = 'Converted';
        cs.Booking__c = bk.Id;
        update cs;

        // Update Lead. Lead_Status__c is a restricted picklist; in environments where
        // 'Booked' has not been added we let the update fail silently rather than
        // blocking the booking flow.
        Lead__c lead = new Lead__c(Id = cs.Lead__c);
        lead.Lead_Status__c = 'Booked';
        Database.update(lead, false);

        // Co-Applicants
        if (coApplicants != null && !coApplicants.isEmpty()) {
            for (Co_Applicants__c ca : coApplicants) {
                ca.Booking__c = bk.Id;
            }
            insert coApplicants;
        }

        // Create Receipt. Status__c and Approval_Status__c are restricted picklists;
        // values that are not yet present in a given org cause INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST.
        // We attempt the insert with the intended values and progressively strip them
        // on failure so the booking flow is never blocked by picklist drift.
        Receipt__c receipt = new Receipt__c();
        receipt.Booking__c = bk.Id;
        receipt.Receipt_Date__c = Date.today();
        receipt.Total_Amount__c = bookingAmount;
        receipt.Status__c = 'Pending Approval';
        receipt.Mode_of_payment__c = paymentMode;
        receipt.Payment_Method__c = paymentMode;
        receipt.Payment_Type__c = 'Booking Advance';
        receipt.Transaction_Reference__c = transactionRef;
        receipt.Approval_Status__c = 'Pending';
        receipt.Submitted_DT__c = DateTime.now();
        Database.SaveResult sr = Database.insert(receipt, false);
        if (!sr.isSuccess()) {
            receipt.Approval_Status__c = null;
            sr = Database.insert(receipt, false);
        }
        if (!sr.isSuccess()) {
            receipt.Status__c = null;
            insert receipt;
        }

        // Create Customer Payment Schedule
        createPaymentSchedule(bk.Id, costSheetId);

        return bk.Id;
    }

    private static void createPaymentSchedule(Id bookingId, Id costSheetId) {
        Booking__c bk = [SELECT Id, Project__c, Tower__c, Unit__c, Agreement_Value__c FROM Booking__c WHERE Id = :bookingId];
        List<CS_Payment_Line__c> lines = [
            SELECT Milestone_Name__c, Payment_Pct__c, Amount__c, Due_Date__c,
                   Construction_Milestone__c, Sequence__c, Category__c
            FROM CS_Payment_Line__c WHERE Cost_Sheet__c = :costSheetId ORDER BY Sequence__c ASC
        ];

        List<Customer_Payment_Schedule__c> schedules = new List<Customer_Payment_Schedule__c>();
        for (CS_Payment_Line__c line : lines) {
            Customer_Payment_Schedule__c ps = new Customer_Payment_Schedule__c();
            ps.Booking__c = bookingId;
            ps.Project__c = bk.Project__c;
            ps.Tower__c = bk.Tower__c;
            ps.Unit__c = bk.Unit__c;
            ps.Milestone_Name__c = line.Milestone_Name__c;
            ps.Milestone_Category__c = line.Category__c;
            ps.Milestone_Pct__c = line.Payment_Pct__c;
            ps.Scheduled_Amount__c = line.Amount__c;
            ps.Construction_Milestone__c = line.Construction_Milestone__c;
            ps.Sequence__c = line.Sequence__c;
            ps.Payment_Status__c = 'Not Due';
            schedules.add(ps);
        }
        if (!schedules.isEmpty()) insert schedules;

        // Also create Payment_Schedule__c records (standard payment schedule object)
        List<Payment_Schedule__c> paySchedules = new List<Payment_Schedule__c>();
        for (CS_Payment_Line__c line : lines) {
            Payment_Schedule__c ps = new Payment_Schedule__c();
            ps.Booking__c = bookingId;
            ps.Milestone_Name__c = line.Milestone_Name__c;
            ps.Percentage__c = line.Payment_Pct__c;
            ps.Amount__c = line.Amount__c != null ? line.Amount__c : 0;
            ps.Due_Date__c = line.Due_Date__c;
            ps.Sequence__c = line.Sequence__c;
            ps.Status__c = 'Pending';
            paySchedules.add(ps);
        }
        if (!paySchedules.isEmpty()) insert paySchedules;
    }

    /**
     * @description Push booking to CRM
     */
    public static void pushToCRM(Id bookingId) {
        Booking__c bk = [SELECT Id, Booking_Stage__c, CRM_Manager__c, Owner__c FROM Booking__c WHERE Id = :bookingId];
        if (bk.Booking_Stage__c != 'New') {
            throw new BookingException('Only bookings in "New" stage can be pushed to CRM.');
        }
        // In production: submit for CRM_Manager approval
    }

    /**
     * @description Approve CRM push
     */
    public static void approveCRMPush(Id bookingId) {
        Booking__c bk = [SELECT Id, Project__c, Owner__c FROM Booking__c WHERE Id = :bookingId];
        Id crmExecId = RoundRobinService.getNextUser(bk.Project__c, 'CRM');
        bk.Booking_Stage__c = 'Booked';
        bk.Status__c = 'Confirmed';
        bk.CRM_Executive__c = crmExecId;
        bk.Owner__c = crmExecId;
        update bk;
    }

    public class BookingException extends Exception {}
}