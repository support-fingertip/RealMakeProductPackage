public class ProjectBoardControllerClass {

    @AuraEnabled
    public static List<Project__c> getProjects() {
        return [
            SELECT Id, Name, Project_Code__c, Property_Types__c,
                   Address__c, City__c, State__c,
                   Total_Units__c, Available_Units__c, Booked_Units__c,
                   Project_Status__c
            FROM Project__c
            ORDER BY Name ASC
        ];
    }

    @AuraEnabled
    public static List<Unit__c> getPlots(String Project) {
        return [
            SELECT IsDeleted, Id, Name, Project__c, Amenity_Charges__c, Available_From__c,
                   BHK_Configuration__c, BHK_Type__c, Balcony_Area_Charges__c, Base_Price__c,
                   Base_Rate_Sqft__c, Block_Expiry__c, Blocked_By_Lead__c, Blocked_Until__c,
                   Booking__c, Built_up_Area__c, Car_Parking_Charges__c, Calculation_Summary__c,
                   Car_Parking__c, Carpet_Area__c, Clubhouse_Charges__c, Corpus_Fund_Sqft__c,
                   Description__c, Current_Booking__c, Facing__c, Doc_Charges__c,
                   Floor_Plan_Document__c, Floor_Rise_Rate__c, Floor_Raise_Charges__c,
                   Floor_Rise_Sqft__c, Furnishing_Status__c, Floor__c, GST_Amount__c,
                   GST_Other_Percentage__c, GST_Percentage__c, Generator_Charges__c,
                   Has_Pooja_Room__c, Has_Servant_Room__c, Infra_Charges__c,
                   Inspection_Completed__c, Is_Calculation_Ready__c, Labour_Cess__c,
                   Last_Calculated_Date__c, Maintenance_Charges__c, Maintenance_Sqft_Month__c,
                   Maintenance_Months__c, Move_In_Charges__c, Number_of_Bathrooms__c,
                   Number_of_Bedrooms__c, Number_of_Balconies__c, PLC_Charges__c, PLC_Rate__c,
                   Possession_Date__c, Plot_Area__c, Price_Per_Sq_Ft__c, Rate_Per_Sqft__c,
                   Registration_Date__c, Ready_for_Inspection__c, Registration_Pct__c,
                   Saleable_Area__c, Stamp_Duty_Pct__c, Stampduty_Charges__c,
                   Super_Built_Up_Area__c, Super_Builtup_Area__c, Total_Additional_Charges__c,
                   Tower__c, Tower__r.Name, Tower_Block__c,
                   Unit_Number__c, UDS__c, Unit_Code__c, Status__c, Unit_Total_Cost__c,
                   Unit_Type__c, Water_Charges__c, Total_Price__c, Wing__c
            FROM Unit__c
            WHERE Project__c = :Project
            ORDER BY Name ASC
        ];
    }

    @AuraEnabled
    public static List<Map<String, Object>> getTowers(Id projectId) {
        List<Tower__c> towers = [
            SELECT Id, Name, Tower_Status__c, Total_Floors__c, Total_Units__c,
                   Sales_Active__c, Booking_Allowed__c,
                   Construction_Start__c, Expected_Completion__c
            FROM Tower__c
            WHERE Project__c = :projectId
            ORDER BY Name ASC
        ];

        if (towers.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        Set<Id> towerIds = new Set<Id>();
        for (Tower__c t : towers) {
            towerIds.add(t.Id);
        }

        Map<Id, Map<String, Integer>> towerStatusCounts = new Map<Id, Map<String, Integer>>();
        for (AggregateResult ar : [
            SELECT Tower__c towerId, Status__c status, COUNT(Id) cnt
            FROM Unit__c
            WHERE Tower__c IN :towerIds
            GROUP BY Tower__c, Status__c
        ]) {
            Id towerId = (Id) ar.get('towerId');
            String status = (String) ar.get('status');
            Integer cnt = (Integer) ar.get('cnt');
            if (!towerStatusCounts.containsKey(towerId)) {
                towerStatusCounts.put(towerId, new Map<String, Integer>());
            }
            towerStatusCounts.get(towerId).put(status, cnt);
        }

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Tower__c t : towers) {
            Map<String, Object> tMap = new Map<String, Object>();
            tMap.put('Id', t.Id);
            tMap.put('Name', t.Name);
            tMap.put('Tower_Status__c', t.Tower_Status__c);
            tMap.put('Total_Floors__c', t.Total_Floors__c);
            tMap.put('Total_Units__c', t.Total_Units__c);
            tMap.put('Sales_Active__c', t.Sales_Active__c);
            tMap.put('Booking_Allowed__c', t.Booking_Allowed__c);

            Map<String, Integer> counts = towerStatusCounts.containsKey(t.Id)
                ? towerStatusCounts.get(t.Id)
                : new Map<String, Integer>();
            Integer available = counts.containsKey('Available') ? counts.get('Available') : 0;
            Integer booked = counts.containsKey('Booked') ? counts.get('Booked') : 0;
            Integer sold = counts.containsKey('Sold') ? counts.get('Sold') : 0;
            Integer notReleased = counts.containsKey('NOT RELEASE FOR SALE') ? counts.get('NOT RELEASE FOR SALE') : 0;
            Integer blocked = counts.containsKey('BLOCKED') ? counts.get('BLOCKED') : 0;
            Integer totalUnits = available + booked + sold + notReleased + blocked;

            tMap.put('availableCount', available);
            tMap.put('bookedCount', booked);
            tMap.put('soldCount', sold);
            tMap.put('notReleasedCount', notReleased);
            tMap.put('blockedCount', blocked);
            tMap.put('totalUnitCount', totalUnits);

            result.add(tMap);
        }

        return result;
    }

    @AuraEnabled
    public static Map<String, Object> getUnitsByTower(Id towerId) {
        List<Unit__c> units = [
            SELECT Id, Name, Unit_Type__c, BHK_Type__c, Status__c,
                   Floor__c, Wing__c, Facing__c,
                   Super_Builtup_Area__c, Carpet_Area__c, Plot_Area__c,
                   Price_Per_Sq_Ft__c, Base_Price__c, Base_Rate_Sqft__c,
                   Super_Built_Up_Area__c,
                   Tower__r.Name, Tower__r.Total_Floors__c
            FROM Unit__c
            WHERE Tower__c = :towerId
            ORDER BY Floor__c DESC, Name ASC
        ];

        Map<String, Object> result = new Map<String, Object>();
        if (units.isEmpty()) {
            result.put('towerName', '');
            result.put('totalFloors', 0);
            result.put('floors', new List<Map<String, Object>>());
            return result;
        }

        result.put('towerName', units[0].Tower__r.Name);
        result.put('totalFloors', units[0].Tower__r.Total_Floors__c);

        Map<Decimal, List<Map<String, Object>>> floorMap = new Map<Decimal, List<Map<String, Object>>>();
        List<Decimal> floorOrder = new List<Decimal>();

        for (Unit__c u : units) {
            Decimal floor = u.Floor__c != null ? u.Floor__c : 0;
            if (!floorMap.containsKey(floor)) {
                floorMap.put(floor, new List<Map<String, Object>>());
                floorOrder.add(floor);
            }

            Map<String, Object> uMap = new Map<String, Object>();
            uMap.put('Id', u.Id);
            uMap.put('Name', u.Name);
            uMap.put('Unit_Type__c', u.Unit_Type__c);
            uMap.put('BHK_Type__c', u.BHK_Type__c);
            uMap.put('Status__c', u.Status__c);
            uMap.put('Floor__c', u.Floor__c);
            uMap.put('Wing__c', u.Wing__c);
            uMap.put('Facing__c', u.Facing__c);
            uMap.put('Super_Builtup_Area__c', u.Super_Builtup_Area__c);
            uMap.put('Super_Built_Up_Area__c', u.Super_Built_Up_Area__c);
            uMap.put('Carpet_Area__c', u.Carpet_Area__c);
            uMap.put('Plot_Area__c', u.Plot_Area__c);
            uMap.put('Price_Per_Sq_Ft__c', u.Price_Per_Sq_Ft__c);
            uMap.put('Base_Price__c', u.Base_Price__c);
            uMap.put('Base_Rate_Sqft__c', u.Base_Rate_Sqft__c);

            floorMap.get(floor).add(uMap);
        }

        List<Map<String, Object>> floors = new List<Map<String, Object>>();
        for (Decimal fn : floorOrder) {
            Map<String, Object> floorObj = new Map<String, Object>();
            floorObj.put('floorNumber', fn);
            floorObj.put('units', floorMap.get(fn));
            floors.add(floorObj);
        }

        result.put('floors', floors);
        return result;
    }

    @AuraEnabled
    public static List<String> getProjectStatuses() {
        List<String> statuses = new List<String>();
        for (AggregateResult ar : [
            SELECT Project_Status__c status
            FROM Project__c
            WHERE Project_Status__c != null
            GROUP BY Project_Status__c
            ORDER BY Project_Status__c
        ]) {
            statuses.add((String) ar.get('status'));
        }
        return statuses;
    }

    // ══════════════════════════════════════════════════════════════
    // PROJECT IMAGE MANAGEMENT
    // ══════════════════════════════════════════════════════════════

    private static final Set<String> IMAGE_EXTENSIONS = new Set<String>{
        'jpg', 'jpeg', 'png', 'gif', 'webp'
    };

    @AuraEnabled
    public static Map<Id, String> getProjectImages(List<Id> projectIds) {
        Map<Id, String> projectImageMap = new Map<Id, String>();
        if (projectIds == null || projectIds.isEmpty()) {
            return projectImageMap;
        }

        // Get all ContentDocumentLinks for these projects
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :projectIds
        ];

        if (links.isEmpty()) {
            return projectImageMap;
        }

        // Map ContentDocumentId → LinkedEntityId (ProjectId)
        Map<Id, Id> docToProject = new Map<Id, Id>();
        Set<Id> contentDocIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            contentDocIds.add(link.ContentDocumentId);
            docToProject.put(link.ContentDocumentId, link.LinkedEntityId);
        }

        // Get latest ContentVersions that are images, ordered by most recent
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, FileExtension, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds
            AND IsLatest = true
            AND FileExtension IN :IMAGE_EXTENSIONS
            ORDER BY CreatedDate DESC
        ];

        // Pick the most recent image per project
        for (ContentVersion cv : versions) {
            Id projectId = docToProject.get(cv.ContentDocumentId);
            if (projectId != null && !projectImageMap.containsKey(projectId)) {
                projectImageMap.put(
                    projectId,
                    '/sfc/servlet.shepherd/version/download/' + cv.Id
                );
            }
        }

        return projectImageMap;
    }

    @AuraEnabled
    public static void saveProjectImage(Id projectId, String contentDocumentId) {
        // 1. Delete old image files linked to this project (exclude the new upload)
        List<ContentDocumentLink> oldLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :projectId
            AND ContentDocumentId != :contentDocumentId
        ];

        if (!oldLinks.isEmpty()) {
            Set<Id> oldDocIds = new Set<Id>();
            for (ContentDocumentLink cdl : oldLinks) {
                oldDocIds.add(cdl.ContentDocumentId);
            }

            // Only delete image files — preserve any non-image attachments
            List<ContentVersion> oldImageVersions = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN :oldDocIds
                AND IsLatest = true
                AND FileExtension IN :IMAGE_EXTENSIONS
            ];

            if (!oldImageVersions.isEmpty()) {
                Set<Id> imageDocIds = new Set<Id>();
                for (ContentVersion cv : oldImageVersions) {
                    imageDocIds.add(cv.ContentDocumentId);
                }
                // Use without sharing context to ensure delete succeeds
                // regardless of who uploaded the old image
                new ContentDocumentDeleter().deleteDocuments(imageDocIds);
            }
        }

        // 2. Verify the new ContentDocumentLink exists (safety net —
        //    lightning-file-upload auto-creates it via record-id binding)
        List<ContentDocumentLink> existing = [
            SELECT Id FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            AND LinkedEntityId = :projectId
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            ContentDocumentLink link = new ContentDocumentLink();
            link.ContentDocumentId = contentDocumentId;
            link.LinkedEntityId = projectId;
            link.ShareType = 'V';
            link.Visibility = 'AllUsers';
            insert link;
        }
    }

    // Runs without sharing so ContentDocument delete succeeds even when
    // the current user is not the owner of the old image file
    private without sharing class ContentDocumentDeleter {
        public void deleteDocuments(Set<Id> docIds) {
            delete [SELECT Id FROM ContentDocument WHERE Id IN :docIds];
        }
    }
}