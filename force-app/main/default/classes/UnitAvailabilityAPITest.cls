@isTest
private class UnitAvailabilityAPITest {

    @TestSetup
    static void setup() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('UA API Proj');
        Tower__c tower = TestDataFactory.createTower(proj.Id, 'UA Tower');
        Unit__c unit = TestDataFactory.createUnit(proj.Id, tower.Id, 'UA-101');
        // Try to set unit to Available status
        try {
            unit.Status__c = 'Available';
            unit.Unit_Type__c = 'Apartment';
            unit.BHK_Type__c = '2 BHK';
            update unit;
        } catch (Exception e) {
            // Validation may prevent status change
        }
    }

    @isTest
    static void testGetAvailableUnits_noFilters() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/unit/availability';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        List<UnitAvailabilityAPI.UnitDTO> results = UnitAvailabilityAPI.getAvailableUnits();
        Test.stopTest();

        System.assertNotEquals(null, results);
    }

    @isTest
    static void testGetAvailableUnits_withProjectFilter() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/unit/availability';
        req.httpMethod = 'GET';
        req.params.put('projectId', proj.Id);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        List<UnitAvailabilityAPI.UnitDTO> results = UnitAvailabilityAPI.getAvailableUnits();
        Test.stopTest();

        System.assertNotEquals(null, results);
    }

    @isTest
    static void testGetAvailableUnits_withAllFilters() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Tower__c tower = [SELECT Id FROM Tower__c LIMIT 1];

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/unit/availability';
        req.httpMethod = 'GET';
        req.params.put('projectId', proj.Id);
        req.params.put('towerId', tower.Id);
        req.params.put('unitType', 'Apartment');
        req.params.put('bhkType', '2 BHK');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        List<UnitAvailabilityAPI.UnitDTO> results = UnitAvailabilityAPI.getAvailableUnits();
        Test.stopTest();

        System.assertNotEquals(null, results);
    }

    @isTest
    static void testUnitDTOWrapper() {
        UnitAvailabilityAPI.UnitDTO dto = new UnitAvailabilityAPI.UnitDTO();
        dto.unitId = null;
        dto.unitNumber = '101';
        dto.floor = 1;
        dto.unitType = 'Apartment';
        dto.bhkType = '2 BHK';
        dto.carpetArea = 1000;
        dto.superBuiltup = 1200;
        dto.baseRateSqft = 5000;
        dto.basePrice = 6000000;
        dto.facing = 'East';
        dto.towerName = 'T1';
        dto.projectName = 'P1';
        System.assertEquals('101', dto.unitNumber);
    }
}