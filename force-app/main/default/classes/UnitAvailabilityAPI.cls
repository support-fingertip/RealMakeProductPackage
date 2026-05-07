/**
 * @description REST API for querying unit availability.
 * Endpoint: GET /services/apexrest/unit/availability
 */
@RestResource(urlMapping='/unit/availability')
global with sharing class UnitAvailabilityAPI {

    @HttpGet
    global static List<UnitDTO> getAvailableUnits() {
        RestRequest req = RestContext.request;
        String projectId = req.params.get('projectId');
        String towerId = req.params.get('towerId');
        String unitType = req.params.get('unitType');
        String bhkType = req.params.get('bhkType');

        String query = 'SELECT Id, Name, Unit_Number__c, Floor__c, Unit_Type__c, BHK_Type__c, ' +
            'Carpet_Area__c, Super_Builtup_Area__c, Base_Rate_Sqft__c, Base_Price__c, ' +
            'Facing__c, Tower__c, Tower__r.Name, Project__c, Project__r.Name ' +
            'FROM Unit__c WHERE Status__c = \'Available\'';

        if (String.isNotBlank(projectId)) query += ' AND Project__c = \'' + String.escapeSingleQuotes(projectId) + '\'';
        if (String.isNotBlank(towerId)) query += ' AND Tower__c = \'' + String.escapeSingleQuotes(towerId) + '\'';
        if (String.isNotBlank(unitType)) query += ' AND Unit_Type__c = \'' + String.escapeSingleQuotes(unitType) + '\'';
        if (String.isNotBlank(bhkType)) query += ' AND BHK_Type__c = \'' + String.escapeSingleQuotes(bhkType) + '\'';

        query += ' ORDER BY Tower__r.Name, Floor__c, Unit_Number__c LIMIT 200';

        List<Unit__c> units = Database.query(query);
        List<UnitDTO> results = new List<UnitDTO>();
        for (Unit__c u : units) {
            UnitDTO dto = new UnitDTO();
            dto.unitId = u.Id;
            dto.unitNumber = u.Unit_Number__c;
            dto.floor = u.Floor__c;
            dto.unitType = u.Unit_Type__c;
            dto.bhkType = u.BHK_Type__c;
            dto.carpetArea = u.Carpet_Area__c;
            dto.superBuiltup = u.Super_Builtup_Area__c;
            dto.baseRateSqft = u.Base_Rate_Sqft__c;
            dto.basePrice = u.Base_Price__c;
            dto.facing = u.Facing__c;
            dto.towerName = u.Tower__r.Name;
            dto.projectName = u.Project__r.Name;
            results.add(dto);
        }
        return results;
    }

    global class UnitDTO {
        public Id unitId;
        public String unitNumber;
        public Decimal floor;
        public String unitType;
        public String bhkType;
        public Decimal carpetArea;
        public Decimal superBuiltup;
        public Decimal baseRateSqft;
        public Decimal basePrice;
        public String facing;
        public String towerName;
        public String projectName;
    }
}