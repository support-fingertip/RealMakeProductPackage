public with sharing class BulkDemandController {

    // ============ WRAPPER CLASSES ============

    public class ProjectContextWrapper {
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public String projectType { get; set; }
        @AuraEnabled public Decimal interestRate { get; set; }
        @AuraEnabled public Decimal reminderDays { get; set; }
    }

    public class MasterMilestoneWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Decimal sequence { get; set; }
        @AuraEnabled public Decimal percentage { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String paymentType { get; set; }
        @AuraEnabled public Boolean isCompleted { get; set; }
        @AuraEnabled public Boolean demandAlreadyRaised { get; set; }
        @AuraEnabled public Decimal cumulativePercentage { get; set; }
    }

    public class BookingDemandWrapper {
        @AuraEnabled public Id bookingId { get; set; }
        @AuraEnabled public String bookingName { get; set; }
        @AuraEnabled public String unitName { get; set; }
        @AuraEnabled public String applicantName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public Decimal totalPending { get; set; }
        @AuraEnabled public Decimal totalInterest { get; set; }
        @AuraEnabled public Decimal netDemandAmount { get; set; }
        @AuraEnabled public String formattedPending { get; set; }
        @AuraEnabled public String formattedInterest { get; set; }
        @AuraEnabled public String formattedNet { get; set; }
        @AuraEnabled public List<PaymentScheduleLineItem> scheduleItems { get; set; }
        @AuraEnabled public Boolean isSelected { get; set; }
        @AuraEnabled public Decimal currentMilestoneAmount { get; set; }
        @AuraEnabled public Decimal previousMilestonesAmount { get; set; }
        @AuraEnabled public String formattedCurrentAmount { get; set; }
        @AuraEnabled public String formattedPreviousAmount { get; set; }
    }

    public class PaymentScheduleLineItem {
        @AuraEnabled public Id scheduleId { get; set; }
        @AuraEnabled public String scheduleName { get; set; }
        @AuraEnabled public String milestoneName { get; set; }
        @AuraEnabled public Decimal pendingAmount { get; set; }
        @AuraEnabled public Decimal basePending { get; set; }
        @AuraEnabled public Decimal gstPending { get; set; }
        @AuraEnabled public Decimal interestAmount { get; set; }
        @AuraEnabled public Decimal sequence { get; set; }
        @AuraEnabled public String formattedPending { get; set; }
        @AuraEnabled public String formattedInterest { get; set; }
        @AuraEnabled public Boolean isSelected { get; set; }
    }

    public class BulkDemandRequest {
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public Id masterPaymentScheduleId { get; set; }
        @AuraEnabled public List<BookingDemandItem> bookings { get; set; }
        @AuraEnabled public Decimal gracePeriodDays { get; set; }
        @AuraEnabled public Decimal dueDateOffsetDays { get; set; }
        @AuraEnabled public Boolean includeInterest { get; set; }
        @AuraEnabled public Boolean includePreviousDues { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public String demandType { get; set; }
    }

    public class BookingDemandItem {
        @AuraEnabled public Id bookingId { get; set; }
        @AuraEnabled public Decimal demandAmount { get; set; }
        @AuraEnabled public Decimal interestAmount { get; set; }
        @AuraEnabled public Decimal previousDues { get; set; }
        @AuraEnabled public List<Id> scheduleIds { get; set; }
    }

    public class BulkDemandResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Integer totalProcessed { get; set; }
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failureCount { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public List<DemandResultItem> results { get; set; }
    }

    public class DemandResultItem {
        @AuraEnabled public Id bookingId { get; set; }
        @AuraEnabled public String bookingName { get; set; }
        @AuraEnabled public Id demandId { get; set; }
        @AuraEnabled public String demandName { get; set; }
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Boolean emailSent { get; set; }
    }

    // ============ READ METHODS ============

    @AuraEnabled(cacheable=true)
    public static ProjectContextWrapper getProjectContext(Id projectId) {
        List<Project__c> projects = [
            SELECT Id, Name, Project_Type__c, Interest_Rate__c, Reminder_Days__c
            FROM Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];

        if (projects.isEmpty()) {
            throw new AuraHandledException('Project not found');
        }

        Project__c project = projects[0];
        ProjectContextWrapper wrapper = new ProjectContextWrapper();
        wrapper.projectId = project.Id;
        wrapper.projectName = project.Name;
        wrapper.projectType = project.Project_Type__c;
        wrapper.interestRate = project.Interest_Rate__c;
        wrapper.reminderDays = project.Reminder_Days__c;
        return wrapper;
    }

    @AuraEnabled(cacheable=true)
    public static List<MasterMilestoneWrapper> getCompletedMilestones(Id projectId) {
        List<MasterMilestoneWrapper> wrappers = new List<MasterMilestoneWrapper>();

        // Get ALL active milestones (not just completed)
        List<Master_Payment_Schedule__c> milestones = [
            SELECT Id, Name, Sequence__c, Percentage__c, Status__c, Payment_Type__c
            FROM Master_Payment_Schedule__c
            WHERE Project__c = :projectId
            AND Is_Active__c = true
            ORDER BY Sequence__c ASC
        ];

        // Check which milestones already have demands raised for all bookings
        Set<Id> milestoneIds = new Set<Id>();
        for (Master_Payment_Schedule__c ms : milestones) {
            milestoneIds.add(ms.Id);
        }

        // Count payment schedules with demand raised per milestone using two queries
        Map<Id, Integer> totalByMilestone = new Map<Id, Integer>();
        Map<Id, Integer> demandedByMilestone = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT Master_Payment_Schedule__c msId, COUNT(Id) cnt
            FROM Payment_Schedule__c
            WHERE Master_Payment_Schedule__c IN :milestoneIds
            AND Booking__r.Is_Cancelled__c = false
            GROUP BY Master_Payment_Schedule__c
        ]) {
            totalByMilestone.put((Id) ar.get('msId'), (Integer) ar.get('cnt'));
        }

        for (AggregateResult ar : [
            SELECT Master_Payment_Schedule__c msId, COUNT(Id) cnt
            FROM Payment_Schedule__c
            WHERE Master_Payment_Schedule__c IN :milestoneIds
            AND Booking__r.Is_Cancelled__c = false
            AND Demand_Raised__c = true
            GROUP BY Master_Payment_Schedule__c
        ]) {
            demandedByMilestone.put((Id) ar.get('msId'), (Integer) ar.get('cnt'));
        }

        Map<Id, Boolean> milestoneFullyDemanded = new Map<Id, Boolean>();
        for (Id msId : milestoneIds) {
            Integer total = totalByMilestone.containsKey(msId) ? totalByMilestone.get(msId) : 0;
            Integer demanded = demandedByMilestone.containsKey(msId) ? demandedByMilestone.get(msId) : 0;
            milestoneFullyDemanded.put(msId, demanded >= total && total > 0);
        }

        Decimal cumPct = 0;
        for (Master_Payment_Schedule__c ms : milestones) {
            MasterMilestoneWrapper w = new MasterMilestoneWrapper();
            w.id = ms.Id;
            w.name = ms.Name;
            w.sequence = ms.Sequence__c;
            w.percentage = ms.Percentage__c;
            w.status = ms.Status__c;
            w.paymentType = ms.Payment_Type__c;
            w.isCompleted = (ms.Status__c == PostSalesConstants.MILESTONE_STATUS_COMPLETED);
            w.demandAlreadyRaised = milestoneFullyDemanded.containsKey(ms.Id)
                ? milestoneFullyDemanded.get(ms.Id) : false;
            cumPct += (ms.Percentage__c != null ? ms.Percentage__c : 0);
            w.cumulativePercentage = cumPct;
            wrappers.add(w);
        }

        return wrappers;
    }

    @AuraEnabled
    public static List<BookingDemandWrapper> getBookingsForMilestone(Id projectId, Id masterPaymentScheduleId) {
        // Get the selected milestone's sequence
        Master_Payment_Schedule__c selectedMilestone = [
            SELECT Id, Sequence__c, Payment_Type__c
            FROM Master_Payment_Schedule__c
            WHERE Id = :masterPaymentScheduleId
            LIMIT 1
        ];

        Decimal milestoneSequence = selectedMilestone.Sequence__c;

        // Get active bookings for this project
        List<Booking__c> bookings = [
            SELECT Id, Name, Unit__r.Name, First_Applicant_Name__c, Email__c
            FROM Booking__c
            WHERE Project__c = :projectId
            AND Is_Cancelled__c = false
            ORDER BY Name ASC
        ];

        if (bookings.isEmpty()) {
            return new List<BookingDemandWrapper>();
        }

        Set<Id> bookingIds = new Set<Id>();
        Map<Id, Booking__c> bookingMap = new Map<Id, Booking__c>();
        for (Booking__c b : bookings) {
            bookingIds.add(b.Id);
            bookingMap.put(b.Id, b);
        }

        // Query ALL payment schedules up to and including the selected milestone
        // (both demand-raised and not) for cumulative calculation
        List<Payment_Schedule__c> allSchedules = [
            SELECT Id, Name, Booking__c, Milestone_Name__c,
                   Amount__c, Pending_Amount__c, Interest_Pending__c,
                   Sequence__c, S_No__c, Demand_Raised__c,
                   Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c,
                   Master_Payment_Schedule__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookingIds
            AND S_No__c <= :milestoneSequence
            ORDER BY Sequence__c ASC
        ];

        // Group schedules by booking
        Map<Id, List<Payment_Schedule__c>> allByBooking = new Map<Id, List<Payment_Schedule__c>>();
        for (Payment_Schedule__c ps : allSchedules) {
            if (!allByBooking.containsKey(ps.Booking__c)) {
                allByBooking.put(ps.Booking__c, new List<Payment_Schedule__c>());
            }
            allByBooking.get(ps.Booking__c).add(ps);
        }

        // Build wrappers with cumulative breakdown
        List<BookingDemandWrapper> wrappers = new List<BookingDemandWrapper>();
        for (Id bookingId : bookingIds) {
            List<Payment_Schedule__c> bookingSchedules = allByBooking.get(bookingId);
            if (bookingSchedules == null || bookingSchedules.isEmpty()) continue;

            Booking__c booking = bookingMap.get(bookingId);
            BookingDemandWrapper w = new BookingDemandWrapper();
            w.bookingId = booking.Id;
            w.bookingName = booking.Name;
            w.unitName = booking.Unit__r != null ? booking.Unit__r.Name : '';
            w.applicantName = booking.First_Applicant_Name__c;
            w.email = booking.Email__c;
            w.totalPending = 0;
            w.totalInterest = 0;
            w.currentMilestoneAmount = 0;
            w.previousMilestonesAmount = 0;
            w.scheduleItems = new List<PaymentScheduleLineItem>();
            w.isSelected = true;

            Boolean hasUnraisedDemand = false;

            for (Payment_Schedule__c ps : bookingSchedules) {
                Decimal pending = ps.Pending_Amount__c != null ? ps.Pending_Amount__c : 0;
                Decimal interest = ps.Interest_Pending__c != null ? ps.Interest_Pending__c : 0;
                Decimal amount = ps.Amount__c != null ? ps.Amount__c : 0;
                Boolean isCurrentMilestone = (ps.Master_Payment_Schedule__c == masterPaymentScheduleId);
                Boolean isDemandNotRaised = (ps.Demand_Raised__c != true && pending > 0);

                // Separate current milestone vs previous milestones
                if (isCurrentMilestone) {
                    w.currentMilestoneAmount += pending;
                } else {
                    w.previousMilestonesAmount += pending;
                }

                // Only include schedules where demand hasn't been raised
                if (isDemandNotRaised) {
                    hasUnraisedDemand = true;
                    w.totalPending += pending;
                    w.totalInterest += interest;

                    PaymentScheduleLineItem item = new PaymentScheduleLineItem();
                    item.scheduleId = ps.Id;
                    item.scheduleName = ps.Name;
                    item.milestoneName = ps.Milestone_Name__c;
                    item.pendingAmount = pending;
                    item.basePending = ps.Payment_Schedule_Amount_Pending__c;
                    item.gstPending = ps.GST_Amount_Pending__c;
                    item.interestAmount = interest;
                    item.sequence = ps.Sequence__c;
                    item.formattedPending = formatCurrency(pending);
                    item.formattedInterest = formatCurrency(interest);
                    item.isSelected = true;
                    w.scheduleItems.add(item);
                }
            }

            // Skip bookings with no unraised demand schedules
            if (!hasUnraisedDemand) continue;

            w.netDemandAmount = w.totalPending + w.totalInterest;
            w.formattedPending = formatCurrency(w.totalPending);
            w.formattedInterest = formatCurrency(w.totalInterest);
            w.formattedNet = formatCurrency(w.netDemandAmount);
            w.formattedCurrentAmount = formatCurrency(w.currentMilestoneAmount);
            w.formattedPreviousAmount = formatCurrency(w.previousMilestonesAmount);
            wrappers.add(w);
        }

        return wrappers;
    }

    @AuraEnabled
    public static List<BookingDemandWrapper> getIndividualCompletedSchedules(Id projectId) {
        // Query payment schedules where master milestone is completed and has pending amounts
        List<Payment_Schedule__c> schedules = [
            SELECT Id, Name, Booking__c, Booking__r.Name, Booking__r.Unit__r.Name,
                   Booking__r.First_Applicant_Name__c, Booking__r.Email__c,
                   Milestone_Name__c, Pending_Amount__c, Interest_Pending__c,
                   Sequence__c, Master_Payment_Schedule__r.Status__c,
                   Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c
            FROM Payment_Schedule__c
            WHERE Booking__r.Project__c = :projectId
            AND Booking__r.Is_Cancelled__c = false
            AND Master_Payment_Schedule__r.Status__c = :PostSalesConstants.MILESTONE_STATUS_COMPLETED
            AND Pending_Amount__c > 0
            AND (Demand_Raised__c = false OR Demand_Raised__c = null)
            ORDER BY Booking__r.Name ASC, Sequence__c ASC
        ];

        // Group by booking
        Map<Id, BookingDemandWrapper> wrapperMap = new Map<Id, BookingDemandWrapper>();

        for (Payment_Schedule__c ps : schedules) {
            Id bookingId = ps.Booking__c;

            if (!wrapperMap.containsKey(bookingId)) {
                BookingDemandWrapper w = new BookingDemandWrapper();
                w.bookingId = bookingId;
                w.bookingName = ps.Booking__r.Name;
                w.unitName = ps.Booking__r.Unit__r != null ? ps.Booking__r.Unit__r.Name : '';
                w.applicantName = ps.Booking__r.First_Applicant_Name__c;
                w.email = ps.Booking__r.Email__c;
                w.totalPending = 0;
                w.totalInterest = 0;
                w.scheduleItems = new List<PaymentScheduleLineItem>();
                w.isSelected = false;
                wrapperMap.put(bookingId, w);
            }

            BookingDemandWrapper w = wrapperMap.get(bookingId);
            Decimal pending = ps.Pending_Amount__c != null ? ps.Pending_Amount__c : 0;
            Decimal interest = ps.Interest_Pending__c != null ? ps.Interest_Pending__c : 0;

            w.totalPending += pending;
            w.totalInterest += interest;

            PaymentScheduleLineItem item = new PaymentScheduleLineItem();
            item.scheduleId = ps.Id;
            item.scheduleName = ps.Name;
            item.milestoneName = ps.Milestone_Name__c;
            item.pendingAmount = pending;
            item.basePending = ps.Payment_Schedule_Amount_Pending__c;
            item.gstPending = ps.GST_Amount_Pending__c;
            item.interestAmount = interest;
            item.sequence = ps.Sequence__c;
            item.formattedPending = formatCurrency(pending);
            item.formattedInterest = formatCurrency(interest);
            item.isSelected = false;
            w.scheduleItems.add(item);
        }

        // Calculate net amounts
        List<BookingDemandWrapper> wrappers = new List<BookingDemandWrapper>();
        for (BookingDemandWrapper w : wrapperMap.values()) {
            w.netDemandAmount = w.totalPending + w.totalInterest;
            w.formattedPending = formatCurrency(w.totalPending);
            w.formattedInterest = formatCurrency(w.totalInterest);
            w.formattedNet = formatCurrency(w.netDemandAmount);
            wrappers.add(w);
        }

        return wrappers;
    }

    // ============ WRITE METHODS ============

    @AuraEnabled
    public static BulkDemandResult createBulkDemands(String requestJson) {
        BulkDemandResult result = new BulkDemandResult();
        result.results = new List<DemandResultItem>();
        result.successCount = 0;
        result.failureCount = 0;

        Savepoint sp = Database.setSavepoint();

        try {
            BulkDemandRequest request = (BulkDemandRequest) JSON.deserialize(requestJson, BulkDemandRequest.class);

            if (request.bookings == null || request.bookings.isEmpty()) {
                throw new AuraHandledException('No bookings provided for demand creation');
            }

            // Collect all booking IDs for name lookup
            Set<Id> bookingIds = new Set<Id>();
            for (BookingDemandItem item : request.bookings) {
                bookingIds.add(item.bookingId);
            }

            Map<Id, Booking__c> bookingMap = new Map<Id, Booking__c>([
                SELECT Id, Name FROM Booking__c WHERE Id IN :bookingIds
            ]);

            // Calculate due date
            Date dueDate = Date.today();
            if (request.gracePeriodDays != null && request.gracePeriodDays > 0) {
                dueDate = dueDate.addDays(Integer.valueOf(request.gracePeriodDays));
            } else {
                dueDate = dueDate.addDays(PostSalesConstants.DEFAULT_GRACE_PERIOD_DAYS);
            }

            String demandType = String.isNotBlank(request.demandType) ? request.demandType : PostSalesConstants.DEMAND_TYPE_BULK;

            // Create Demands
            List<Demands__c> demandsToInsert = new List<Demands__c>();
            Map<Integer, BookingDemandItem> indexToItem = new Map<Integer, BookingDemandItem>();
            Integer idx = 0;

            for (BookingDemandItem item : request.bookings) {
                Demands__c demand = new Demands__c();
                demand.Booking__c = item.bookingId;
                demand.Demand_Amount__c = item.demandAmount;
                demand.Interest_Amount__c = request.includeInterest == true ? item.interestAmount : 0;
                demand.Previous_Dues__c = item.previousDues;
                demand.Status__c = PostSalesConstants.DEMAND_STATUS_RAISED;
                demand.Demand_Type__c = demandType;
                demand.Demand_Date__c = Date.today();
                demand.Due_Date__c = dueDate;
                demand.Grace_Period_Days__c = request.gracePeriodDays;
                demand.Notes__c = request.notes;
                demand.Reminder_Date__c = dueDate;

                demandsToInsert.add(demand);
                indexToItem.put(idx, item);
                idx++;
            }

            Database.SaveResult[] insertResults = Database.insert(demandsToInsert, false);

            // Process results and update payment schedules
            List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();

            for (Integer i = 0; i < insertResults.size(); i++) {
                DemandResultItem resultItem = new DemandResultItem();
                BookingDemandItem requestItem = indexToItem.get(i);
                resultItem.bookingId = requestItem.bookingId;
                resultItem.bookingName = bookingMap.containsKey(requestItem.bookingId)
                    ? bookingMap.get(requestItem.bookingId).Name : '';

                if (insertResults[i].isSuccess()) {
                    resultItem.demandId = insertResults[i].getId();
                    resultItem.success = true;
                    result.successCount++;

                    // Mark payment schedules as demand raised
                    if (requestItem.scheduleIds != null) {
                        for (Id schedId : requestItem.scheduleIds) {
                            Payment_Schedule__c ps = new Payment_Schedule__c();
                            ps.Id = schedId;
                            ps.Demand_Raised__c = true;
                            ps.Demand_Date__c = Date.today();
                            schedulesToUpdate.add(ps);
                        }
                    }
                } else {
                    resultItem.success = false;
                    resultItem.errorMessage = insertResults[i].getErrors()[0].getMessage();
                    result.failureCount++;
                }

                result.results.add(resultItem);
            }

            // Update payment schedules
            if (!schedulesToUpdate.isEmpty()) {
                Database.update(schedulesToUpdate, false);
            }

            // Query demand names
            Set<Id> demandIds = new Set<Id>();
            for (DemandResultItem ri : result.results) {
                if (ri.demandId != null) {
                    demandIds.add(ri.demandId);
                }
            }

            if (!demandIds.isEmpty()) {
                Map<Id, Demands__c> demandMap = new Map<Id, Demands__c>(
                    [SELECT Id, Name FROM Demands__c WHERE Id IN :demandIds]
                );
                for (DemandResultItem ri : result.results) {
                    if (ri.demandId != null && demandMap.containsKey(ri.demandId)) {
                        ri.demandName = demandMap.get(ri.demandId).Name;
                    }
                }
            }

            result.totalProcessed = request.bookings.size();
            result.success = result.failureCount == 0;

        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Error creating bulk demands: ' + e.getMessage());
        }

        return result;
    }

    @AuraEnabled
    public static void sendBulkDemandEmails(List<Id> demandIds, String templateId) {
        try {
            if (demandIds == null || demandIds.isEmpty()) {
                throw new AuraHandledException('No demand IDs provided');
            }

            List<Demands__c> demands = [
                SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.Name
                FROM Demands__c
                WHERE Id IN :demandIds
            ];

            if (String.isNotBlank(templateId)) {
                // Use existing email template system
                for (Demands__c demand : demands) {
                    if (String.isNotBlank(demand.Booking__r.Email__c)) {
                        try {
                            EmailSenderController.PreparedEmailData prepared =
                                EmailSenderController.prepareEmailFromTemplate(templateId, demand.Booking__c);

                            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                            email.setToAddresses(new List<String>{ demand.Booking__r.Email__c });
                            email.setSubject(prepared.subject);
                            email.setHtmlBody(prepared.body);
                            email.setSaveAsActivity(true);

                            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
                        } catch (Exception emailEx) {
                            System.debug('Error sending email for demand ' + demand.Name + ': ' + emailEx.getMessage());
                        }
                    }
                }
            }

            // Update demand records
            List<Demands__c> demandsToUpdate = new List<Demands__c>();
            for (Demands__c demand : demands) {
                Demands__c d = new Demands__c();
                d.Id = demand.Id;
                d.Email_Sent__c = true;
                d.Email_Sent_Date__c = DateTime.now();
                d.Email_Sent_To__c = demand.Booking__r.Email__c;
                d.Status__c = PostSalesConstants.DEMAND_STATUS_EMAILED;
                demandsToUpdate.add(d);
            }

            if (!demandsToUpdate.isEmpty()) {
                update demandsToUpdate;
            }

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error sending emails: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void sendDemandEmail(Id demandId, String emailTemplateId, String documentTemplateId) {
        try {
            if (demandId == null) {
                throw new AuraHandledException('Demand ID is required');
            }

            List<Demands__c> demands = [
                SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.Name
                FROM Demands__c
                WHERE Id = :demandId
                LIMIT 1
            ];

            if (demands.isEmpty()) {
                throw new AuraHandledException('Demand not found');
            }

            Demands__c demand = demands[0];
            String recipientEmail = demand.Booking__r != null ? demand.Booking__r.Email__c : null;

            if (String.isBlank(recipientEmail)) {
                throw new AuraHandledException('No email address found on the booking');
            }

            // Resolve email template: use provided ID or fall back to Post Sales Config default
            String resolvedEmailTemplateId = emailTemplateId;
            if (String.isBlank(resolvedEmailTemplateId)) {
                PostSalesAdminController.ConfigWrapper config =
                    PostSalesAdminController.getConfigurationByType('Demand');
                if (config != null && config.emailTemplateId != null) {
                    resolvedEmailTemplateId = config.emailTemplateId;
                }
            }

            if (String.isBlank(resolvedEmailTemplateId)) {
                throw new AuraHandledException('No email template configured. Please select one or configure a default in Post Sales Admin.');
            }

            // Prepare the email from the template against the booking record
            EmailSenderController.PreparedEmailData prepared =
                EmailSenderController.prepareEmailFromTemplate(resolvedEmailTemplateId, demand.Booking__c);

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ recipientEmail });
            email.setSubject(prepared.subject);
            email.setHtmlBody(prepared.body);
            email.setSaveAsActivity(true);
            email.setWhatId(demand.Id);

            Messaging.SendEmailResult[] results =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

            if (results != null && !results.isEmpty() && !results[0].isSuccess()) {
                String err = results[0].getErrors() != null && !results[0].getErrors().isEmpty()
                    ? results[0].getErrors()[0].getMessage() : 'Unknown error';
                throw new AuraHandledException('Email send failed: ' + err);
            }

            // Update demand email tracking fields
            Demands__c d = new Demands__c();
            d.Id = demand.Id;
            d.Email_Sent__c = true;
            d.Email_Sent_Date__c = DateTime.now();
            d.Email_Sent_To__c = recipientEmail;
            d.Status__c = PostSalesConstants.DEMAND_STATUS_EMAILED;
            update d;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error sending demand email: ' + e.getMessage());
        }
    }

    // ============ DEMAND LETTER CONFIG ============

    public class DemandLetterConfigWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public Id emailTemplateId { get; set; }
        @AuraEnabled public String emailTemplateName { get; set; }
        @AuraEnabled public Id documentTemplateId { get; set; }
        @AuraEnabled public String documentTemplateName { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal gracePeriodDays { get; set; }
        @AuraEnabled public Boolean includeInterest { get; set; }
        @AuraEnabled public Boolean autoSendEmail { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<DemandLetterConfigWrapper> getDemandLetterConfigs() {
        List<DemandLetterConfigWrapper> wrappers = new List<DemandLetterConfigWrapper>();
        List<Demand_Letter_Config__c> configs = [
            SELECT Id, Project__c, Project__r.Name,
                   Email_Template__c, Email_Template__r.Template_Name__c,
                   Document_Template__c, Document_Template__r.Name,
                   Is_Active__c, Description__c,
                   Grace_Period_Days__c, Include_Interest__c, Auto_Send_Email__c
            FROM Demand_Letter_Config__c
            ORDER BY Project__r.Name ASC
        ];

        for (Demand_Letter_Config__c c : configs) {
            DemandLetterConfigWrapper w = new DemandLetterConfigWrapper();
            w.id = c.Id;
            w.projectId = c.Project__c;
            w.projectName = c.Project__c != null ? c.Project__r.Name : null;
            w.emailTemplateId = c.Email_Template__c;
            w.emailTemplateName = c.Email_Template__c != null ? c.Email_Template__r.Template_Name__c : null;
            w.documentTemplateId = c.Document_Template__c;
            w.documentTemplateName = c.Document_Template__c != null ? c.Document_Template__r.Name : null;
            w.isActive = c.Is_Active__c;
            w.description = c.Description__c;
            w.gracePeriodDays = c.Grace_Period_Days__c;
            w.includeInterest = c.Include_Interest__c;
            w.autoSendEmail = c.Auto_Send_Email__c;
            wrappers.add(w);
        }
        return wrappers;
    }

    @AuraEnabled
    public static Id saveDemandLetterConfig(String configJson) {
        try {
            DemandLetterConfigWrapper w = (DemandLetterConfigWrapper) JSON.deserialize(configJson, DemandLetterConfigWrapper.class);

            Demand_Letter_Config__c config;
            if (w.id != null) {
                config = [SELECT Id FROM Demand_Letter_Config__c WHERE Id = :w.id LIMIT 1];
            } else {
                config = new Demand_Letter_Config__c();
            }

            config.Project__c = w.projectId;
            config.Email_Template__c = w.emailTemplateId;
            config.Document_Template__c = w.documentTemplateId;
            config.Is_Active__c = w.isActive == true;
            config.Description__c = w.description;
            config.Grace_Period_Days__c = w.gracePeriodDays;
            config.Include_Interest__c = w.includeInterest == true;
            config.Auto_Send_Email__c = w.autoSendEmail == true;

            upsert config;
            return config.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving demand letter config: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteDemandLetterConfig(Id configId) {
        try {
            delete [SELECT Id FROM Demand_Letter_Config__c WHERE Id = :configId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting demand letter config: ' + e.getMessage());
        }
    }

    // ============ UTILITY ============

    private static String formatCurrency(Decimal value) {
        return PostSalesConstants.formatCurrency(value);
    }
}