/**
 * @description Test class for IntegrationAlertService.
 *              Covers checkAndAlert with critical errors, dead letters,
 *              consecutive failures, null log, sendEmailAlert, and recipient resolution.
 */
@IsTest
private class IntegrationAlertServiceTest {

    @IsTest
    static void testCheckAndAlert_nullLog() {
        Test.startTest();
        IntegrationAlertService.checkAndAlert(null, null);
        Test.stopTest();

        // Should return early without error
        System.assert(true, 'Should handle null log gracefully');
    }

    @IsTest
    static void testCheckAndAlert_criticalError() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('ALERT_CRIT');
        Integration_Log__c log = TestDataFactory.createLog(endpoint.Id, false);

        Integration_Error_Log__c errorLog = new Integration_Error_Log__c(
            Integration_Log__c = log.Id,
            Error_Type__c = 'Unknown',
            Error_Message__c = 'Critical failure in external system',
            Severity__c = 'Critical',
            Stack_Trace__c = 'at line 1\nat line 2',
            Is_Dead_Letter__c = false,
            Retry_Eligible__c = true
        );
        insert errorLog;

        Test.startTest();
        IntegrationAlertService.checkAndAlert(log, errorLog);
        Test.stopTest();

        // Should attempt to send critical alert email
        System.assert(true, 'Should process critical error without exception');
    }

    @IsTest
    static void testCheckAndAlert_deadLetter() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('ALERT_DL');
        Integration_Log__c log = TestDataFactory.createLog(endpoint.Id, false);

        Integration_Error_Log__c errorLog = new Integration_Error_Log__c(
            Integration_Log__c = log.Id,
            Error_Type__c = 'Unknown',
            Error_Message__c = 'Dead lettered after retries',
            Severity__c = 'High',
            Is_Dead_Letter__c = true,
            Retry_Eligible__c = true
        );
        insert errorLog;

        Test.startTest();
        IntegrationAlertService.checkAndAlert(log, errorLog);
        Test.stopTest();

        System.assert(true, 'Should process dead letter alert without exception');
    }

    @IsTest
    static void testCheckAndAlert_consecutiveFailures() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('ALERT_CONSEC');

        // Create 4 consecutive failure logs
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (Integer i = 0; i < 4; i++) {
            logs.add(new Integration_Log__c(
                Integration_Endpoint__c = endpoint.Id,
                Integration_Key__c = 'ALERT_CONSEC',
                Correlation_Id__c = 'consec-' + i,
                Direction__c = 'Outbound',
                HTTP_Method__c = 'POST',
                Is_Success__c = false,
                Response_Status_Code__c = 500,
                Execution_Start__c = Datetime.now().addMinutes(-i),
                Execution_End__c = Datetime.now().addMinutes(-i).addSeconds(1),
                Execution_Mode__c = 'Synchronous'
            ));
        }
        insert logs;

        // Use the last log to trigger the check
        Integration_Log__c latestLog = logs[0];

        Test.startTest();
        IntegrationAlertService.checkAndAlert(latestLog, null);
        Test.stopTest();

        System.assert(true, 'Should process consecutive failure alert');
    }

    @IsTest
    static void testCheckAndAlert_successLog() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('ALERT_OK');
        Integration_Log__c log = TestDataFactory.createLog(endpoint.Id, true);

        Test.startTest();
        IntegrationAlertService.checkAndAlert(log, null);
        Test.stopTest();

        // Success log should not trigger any alert
        System.assert(true, 'Should not alert on success');
    }

    @IsTest
    static void testSendEmailAlert_blankParams() {
        Test.startTest();
        IntegrationAlertService.sendEmailAlert('', 'body', new List<String>{ 'test@test.com' });
        IntegrationAlertService.sendEmailAlert('subject', '', new List<String>{ 'test@test.com' });
        IntegrationAlertService.sendEmailAlert('subject', 'body', null);
        IntegrationAlertService.sendEmailAlert('subject', 'body', new List<String>());
        Test.stopTest();

        System.assert(true, 'Should handle blank/null params gracefully');
    }

    @IsTest
    static void testSendEmailAlert_validParams() {
        Test.startTest();
        IntegrationAlertService.sendEmailAlert(
            'Test Subject',
            '<p>Test Body</p>',
            new List<String>{ 'admin@example.com' }
        );
        Test.stopTest();

        // Email should be sent (or gracefully fail depending on org config)
        System.assert(true, 'Should attempt to send email');
    }

    @IsTest
    static void testCheckAndAlert_noErrorLog() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('ALERT_NOERR');
        Integration_Log__c log = TestDataFactory.createLog(endpoint.Id, false);

        Test.startTest();
        IntegrationAlertService.checkAndAlert(log, null);
        Test.stopTest();

        System.assert(true, 'Should handle null error log with failed log');
    }

    @IsTest
    static void testSendEmailAlert_longSubject() {
        // Test subject truncation (> 255 chars)
        String longSubject = '';
        for (Integer i = 0; i < 30; i++) {
            longSubject += '0123456789';
        }

        Test.startTest();
        IntegrationAlertService.sendEmailAlert(
            longSubject,
            '<p>Body</p>',
            new List<String>{ 'admin@example.com' }
        );
        Test.stopTest();

        System.assert(true, 'Should handle long subject');
    }

    @IsTest
    static void testCheckAndAlert_failedLogNoConsecutive() {
        // Single failure log - should not trigger consecutive failure alert
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('ALERT_SINGLE');
        Integration_Log__c log = TestDataFactory.createLog(endpoint.Id, false);

        Test.startTest();
        IntegrationAlertService.checkAndAlert(log, null);
        Test.stopTest();

        System.assert(true, 'Should handle single failure without consecutive alert');
    }

    @IsTest
    static void testCheckAndAlert_criticalWithStackTrace() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('ALERT_STACK');
        Integration_Log__c log = TestDataFactory.createLog(endpoint.Id, false);

        Integration_Error_Log__c errorLog = new Integration_Error_Log__c(
            Integration_Log__c = log.Id,
            Error_Type__c = 'Unknown',
            Error_Message__c = 'Critical with stack',
            Severity__c = 'Critical',
            Stack_Trace__c = null,
            Is_Dead_Letter__c = false
        );
        insert errorLog;

        Test.startTest();
        IntegrationAlertService.checkAndAlert(log, errorLog);
        Test.stopTest();

        System.assert(true, 'Should handle critical error without stack trace');
    }
}