@IsTest
private class ComplaintEscalationServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create project
        Project__c project = new Project__c(
            Name = 'Test Project',
            Project_Head__c = UserInfo.getUserId(),
            Property_Types__c = 'Apartment;Villa',
            Allowed_BHK_Types__c = '2BHK;3BHK',
            Min_Booking_Amount__c = 100000,
            Max_Block_Days__c = 7
        );
        insert project;

        Tower__c tower = new Tower__c(
            Project__c = project.Id,
            Tower_Status__c = 'Under Construction',
            Sales_Active__c = true,
            Booking_Allowed__c = true,
            Total_Floors__c = 10,
            Total_Units__c = 40
        );
        insert tower;

        // Create unit
        Unit__c unit = new Unit__c(
            Project__c = project.Id,
            Tower__c = tower.Id,
            Status__c = 'Booked',
            Unit_Type__c = 'Apartment',
            Unit_Number__c = 'CE-101',
            BHK_Type__c = '2BHK',
            Super_Builtup_Area__c = 1100,
            Base_Rate_Sqft__c = 5000
        );
        insert unit;

        // Create booking
        Booking__c booking = new Booking__c(
            Unit__c = unit.Id,
            Project__c = project.Id,
            Booking_Date__c = Date.today().addDays(-60),
            Status__c = 'Approved, Active'
        );
        insert booking;

        // Create escalation matrix rules
        List<Complaint_Escalation_Matrix__c> rules = new List<Complaint_Escalation_Matrix__c>();

        // Rule 1: High priority - tight SLAs
        rules.add(new Complaint_Escalation_Matrix__c(
            Priority__c = 'High',
            Level_1_Days__c = 1,
            Level_1_Notify__c = 'Assigned To',
            Level_2_Days__c = 3,
            Level_2_Notify__c = 'Project Head',
            Level_3_Days__c = 5,
            Level_3_Notify__c = 'Owner',
            Auto_Reassign__c = true,
            Active__c = true
        ));

        // Rule 2: Medium priority
        rules.add(new Complaint_Escalation_Matrix__c(
            Priority__c = 'Medium',
            Level_1_Days__c = 3,
            Level_1_Notify__c = 'Assigned To',
            Level_2_Days__c = 7,
            Level_2_Notify__c = 'Project Head',
            Active__c = true
        ));

        // Rule 3: Default (no filters)
        rules.add(new Complaint_Escalation_Matrix__c(
            Level_1_Days__c = 5,
            Level_1_Notify__c = 'Owner',
            Level_2_Days__c = 10,
            Level_2_Notify__c = 'Project Head',
            Level_3_Days__c = 15,
            Level_3_Notify__c = 'Project Head',
            Active__c = true
        ));

        // Rule 4: Specific category + project
        rules.add(new Complaint_Escalation_Matrix__c(
            Category__c = 'Construction Delay',
            Project__c = project.Id,
            Level_1_Days__c = 2,
            Level_1_Notify__c = 'Project Head',
            Level_2_Days__c = 5,
            Level_2_Notify__c = 'Custom User',
            Level_2_User__c = UserInfo.getUserId(),
            Active__c = true
        ));

        // Rule 5: Inactive rule (should be ignored)
        rules.add(new Complaint_Escalation_Matrix__c(
            Priority__c = 'Low',
            Level_1_Days__c = 1,
            Level_1_Notify__c = 'Owner',
            Active__c = false
        ));

        insert rules;

        // Create complaints
        List<Complaint__c> complaints = new List<Complaint__c>();

        // Complaint 1: High priority, 6 days overdue -> should hit L3
        complaints.add(new Complaint__c(
            Subject__c = 'Critical plumbing issue',
            Category__c = 'Property Issue',
            Priority__c = 'High',
            Status__c = 'In Progress',
            Complaint_Date__c = Date.today().addDays(-10),
            Expected_Resolution_Date__c = Date.today().addDays(-6),
            Booking__c = booking.Id,
            Project__c = project.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Customer_Name__c = 'Test Customer',
            Source__c = 'Phone',
            Customer_Email__c = 'test@example.com'
        ));

        // Complaint 2: Medium priority, 4 days overdue -> should hit L1
        complaints.add(new Complaint__c(
            Subject__c = 'Parking allocation issue',
            Category__c = 'Booking Issue',
            Priority__c = 'Medium',
            Status__c = 'Assigned',
            Complaint_Date__c = Date.today().addDays(-8),
            Expected_Resolution_Date__c = Date.today().addDays(-4),
            Booking__c = booking.Id,
            Project__c = project.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Customer_Name__c = 'Test Customer 2',
            Customer_Email__c = 'test2@example.com',
            Source__c = 'Phone'
        ));

        // Complaint 3: Construction delay in project, 3 days overdue -> specific rule
        complaints.add(new Complaint__c(
            Subject__c = 'Construction behind schedule',
            Category__c = 'Construction Delay',
            Priority__c = 'Low',
            Status__c = 'New',
            Complaint_Date__c = Date.today().addDays(-7),
            Expected_Resolution_Date__c = Date.today().addDays(-3),
            Booking__c = booking.Id,
            Project__c = project.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Customer_Name__c = 'Test Customer 3',
            Customer_Email__c = 'test3@example.com',
            Source__c = 'Phone'
        ));

        // Complaint 4: Already resolved (should be skipped)
        complaints.add(new Complaint__c(
            Subject__c = 'Already fixed',
            Category__c = 'General Complaint',
            Priority__c = 'Low',
            Status__c = 'Resolved',
            Complaint_Date__c = Date.today().addDays(-10),
            Expected_Resolution_Date__c = Date.today().addDays(-5),
            Booking__c = booking.Id,
            Project__c = project.Id,
            Customer_Name__c = 'Test Customer 4',
            Source__c = 'Phone'
        ));

        // Complaint 5: Not yet overdue (should be skipped)
        complaints.add(new Complaint__c(
            Subject__c = 'New complaint',
            Category__c = 'General Complaint',
            Priority__c = 'Low',
            Status__c = 'New',
            Complaint_Date__c = Date.today(),
            Expected_Resolution_Date__c = Date.today().addDays(5),
            Booking__c = booking.Id,
            Project__c = project.Id,
            Customer_Name__c = 'Test Customer 5',
            Source__c = 'Phone'
        ));

        insert complaints;
    }

    @IsTest
    static void testProcessEscalations() {
        Test.startTest();
        ComplaintEscalationService.EscalationResult result =
            ComplaintEscalationService.processEscalations();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.totalProcessed > 0, 'Should have processed overdue complaints');
        System.assert(result.escalatedCount > 0, 'Should have escalated at least one complaint');

        // Verify high priority complaint hit L3
        Complaint__c highPriority = [
            SELECT Escalation_Level__c, Status__c, Last_Escalation_Date__c
            FROM Complaint__c WHERE Subject__c = 'Critical plumbing issue' LIMIT 1
        ];
        System.assertEquals(3, highPriority.Escalation_Level__c,
            'High priority complaint 6 days overdue should be at Level 3');
        System.assertEquals('Escalated', highPriority.Status__c,
            'Status should be updated to Escalated');
        System.assertNotEquals(null, highPriority.Last_Escalation_Date__c,
            'Last escalation date should be set');

        // Verify medium priority complaint hit L1
        Complaint__c medPriority = [
            SELECT Escalation_Level__c FROM Complaint__c
            WHERE Subject__c = 'Parking allocation issue' LIMIT 1
        ];
        System.assertEquals(1, medPriority.Escalation_Level__c,
            'Medium priority 4 days overdue should be at Level 1');

        // Verify resolved complaint was not escalated
        Complaint__c resolved = [
            SELECT Escalation_Level__c FROM Complaint__c
            WHERE Subject__c = 'Already fixed' LIMIT 1
        ];
        System.assertEquals(0, resolved.Escalation_Level__c,
            'Resolved complaint should not be escalated');
    }

    @IsTest
    static void testProcessEscalationsNoRules() {
        // Delete all rules
        delete [SELECT Id FROM Complaint_Escalation_Matrix__c];

        Test.startTest();
        ComplaintEscalationService.EscalationResult result =
            ComplaintEscalationService.processEscalations();
        Test.stopTest();

        System.assertEquals('No active escalation rules found.', result.message);
        System.assertEquals(0, result.escalatedCount);
    }

    @IsTest
    static void testSchedulable() {
        Test.startTest();
        ComplaintEscalationSchedulable schedulable = new ComplaintEscalationSchedulable();
        String jobId = System.schedule(
            'Test Complaint Escalation',
            '0 0 10 * * ?',
            schedulable
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Scheduled job should be created');
    }

    @IsTest
    static void testGetEscalationRules() {
        Test.startTest();
        List<Complaint_Escalation_Matrix__c> rules =
            ComplaintEscalationService.getEscalationRules();
        Test.stopTest();

        System.assert(rules.size() >= 4, 'Should return all escalation rules');
    }

    @IsTest
    static void testSaveEscalationRule() {
        Map<String, Object> ruleData = new Map<String, Object>{
            'priority' => 'High',
            'category' => 'Payment Issue',
            'description' => 'Test rule',
            'level1Days' => 1,
            'level1Notify' => 'Assigned To',
            'level2Days' => 3,
            'level2Notify' => 'Project Head',
            'autoReassign' => true,
            'active' => true
        };

        Test.startTest();
        Id ruleId = ComplaintEscalationService.saveEscalationRule(JSON.serialize(ruleData));
        Test.stopTest();

        System.assertNotEquals(null, ruleId, 'Should return new rule ID');
        Complaint_Escalation_Matrix__c saved = [
            SELECT Priority__c, Category__c, Level_1_Days__c, Auto_Reassign__c
            FROM Complaint_Escalation_Matrix__c WHERE Id = :ruleId
        ];
        System.assertEquals('High', saved.Priority__c);
        System.assertEquals('Payment Issue', saved.Category__c);
        System.assertEquals(1, saved.Level_1_Days__c);
        System.assertEquals(true, saved.Auto_Reassign__c);
    }

    @IsTest
    static void testToggleAndDeleteRule() {
        Complaint_Escalation_Matrix__c rule = [
            SELECT Id, Active__c FROM Complaint_Escalation_Matrix__c
            WHERE Active__c = true LIMIT 1
        ];

        Test.startTest();
        ComplaintEscalationService.toggleEscalationRule(rule.Id, false);
        Test.stopTest();

        rule = [SELECT Active__c FROM Complaint_Escalation_Matrix__c WHERE Id = :rule.Id];
        System.assertEquals(false, rule.Active__c, 'Rule should be deactivated');

        ComplaintEscalationService.deleteEscalationRule(rule.Id);
        List<Complaint_Escalation_Matrix__c> deleted = [
            SELECT Id FROM Complaint_Escalation_Matrix__c WHERE Id = :rule.Id
        ];
        System.assertEquals(0, deleted.size(), 'Rule should be deleted');
    }

    @IsTest
    static void testGetEscalationSummary() {
        // First escalate some complaints
        ComplaintEscalationService.processEscalations();

        Test.startTest();
        List<Map<String, String>> summary =
            ComplaintEscalationService.getEscalationSummary();
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should not be null');
    }

    @IsTest
    static void testDetermineEscalationLevel() {
        Complaint_Escalation_Matrix__c rule = new Complaint_Escalation_Matrix__c(
            Level_1_Days__c = 2,
            Level_2_Days__c = 5,
            Level_3_Days__c = 10
        );

        System.assertEquals(0, ComplaintEscalationService.determineEscalationLevel(rule, 1));
        System.assertEquals(1, ComplaintEscalationService.determineEscalationLevel(rule, 2));
        System.assertEquals(1, ComplaintEscalationService.determineEscalationLevel(rule, 4));
        System.assertEquals(2, ComplaintEscalationService.determineEscalationLevel(rule, 5));
        System.assertEquals(2, ComplaintEscalationService.determineEscalationLevel(rule, 9));
        System.assertEquals(3, ComplaintEscalationService.determineEscalationLevel(rule, 10));
        System.assertEquals(3, ComplaintEscalationService.determineEscalationLevel(rule, 20));
    }
}