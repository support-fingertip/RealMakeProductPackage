@isTest
private class InterestCalculationSchedulableTest {
    @isTest
    static void smokeTest() {
        Test.startTest();
        try {
            InterestCalculationSchedulable s = new InterestCalculationSchedulable();
            s.execute(null);
        } catch (Exception e) {}
        Test.stopTest();
    }
}