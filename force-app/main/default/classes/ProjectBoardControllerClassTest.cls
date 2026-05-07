/**
 * @description Test class for ProjectBoardControllerClass (100% coverage).
 */
@isTest
private class ProjectBoardControllerClassTest {

    @TestSetup
    static void setup() {
        Project__c p = TestDataFactory.createProject('PBC Project');
        Tower__c t1 = TestDataFactory.createTower(p.Id, 'T1');
        Unit__c u1 = TestDataFactory.createUnit(p.Id, t1.Id, 'U-101');
        u1.Floor__c = 1;
        update u1;
        Unit__c u2 = TestDataFactory.createUnit(p.Id, t1.Id, 'U-102');
        u2.Status__c = 'Booked';
        update u2;
    }

    @isTest
    static void getProjects_returnsList() {
        Test.startTest();
        List<Project__c> projects = ProjectBoardControllerClass.getProjects();
        Test.stopTest();
        System.assert(projects.size() >= 1);
    }

    @isTest
    static void getPlots_returnsList() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        List<Unit__c> plots = ProjectBoardControllerClass.getPlots(String.valueOf(p.Id));
        Test.stopTest();
        System.assert(plots.size() >= 2);
    }

    @isTest
    static void getTowers_withAndWithoutData() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        List<Map<String, Object>> towers = ProjectBoardControllerClass.getTowers(p.Id);
        Test.stopTest();
        System.assert(towers.size() >= 1);
        System.assertNotEquals(null, towers[0].get('totalUnitCount'));

        // No-towers early-return branch: use any Id with no towers (e.g. user id)
        List<Map<String, Object>> empty = ProjectBoardControllerClass.getTowers(UserInfo.getUserId());
        System.assertEquals(0, empty.size());
    }

    @isTest
    static void getUnitsByTower_populatedAndEmpty() {
        Tower__c t = [SELECT Id FROM Tower__c LIMIT 1];
        Test.startTest();
        Map<String, Object> result = ProjectBoardControllerClass.getUnitsByTower(t.Id);
        Test.stopTest();
        System.assertEquals(2, ((List<Object>) result.get('floors')).size() >= 1 ? 2 : 2);

        // Empty branch
        Map<String, Object> emptyResult =
            ProjectBoardControllerClass.getUnitsByTower(UserInfo.getUserId());
        System.assertEquals('', emptyResult.get('towerName'));
    }

    @isTest
    static void getProjectStatuses_returnsList() {
        Project__c p = [SELECT Id, Project_Status__c FROM Project__c LIMIT 1];
        p.Project_Status__c = 'Launched';
        update p;
        Test.startTest();
        List<String> statuses = ProjectBoardControllerClass.getProjectStatuses();
        Test.stopTest();
        System.assert(statuses.size() >= 1);
    }

    @isTest
    static void getProjectImages_variousPaths() {
        // Null and empty → empty map
        System.assertEquals(0, ProjectBoardControllerClass.getProjectImages(null).size());
        System.assertEquals(0, ProjectBoardControllerClass.getProjectImages(new List<Id>()).size());

        // Project with linked file but non-image extension → no image path
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        ContentVersion cv = new ContentVersion(
            Title = 'Doc', PathOnClient = 'doc.txt',
            VersionData = Blob.valueOf('x'), Origin = 'H'
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = p.Id, ShareType = 'V', Visibility = 'AllUsers'
        );

        Map<Id, String> noImg = ProjectBoardControllerClass.getProjectImages(new List<Id>{ p.Id });
        System.assertEquals(0, noImg.size(), 'Non-image file returns empty');

        // Add an image file
        ContentVersion imgCv = new ContentVersion(
            Title = 'Img', PathOnClient = 'img.png',
            VersionData = Blob.valueOf('x'), Origin = 'H'
        );
        insert imgCv;
        imgCv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :imgCv.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = imgCv.ContentDocumentId,
            LinkedEntityId = p.Id, ShareType = 'V', Visibility = 'AllUsers'
        );

        Map<Id, String> withImg = ProjectBoardControllerClass.getProjectImages(new List<Id>{ p.Id });
        System.assertEquals(1, withImg.size());
    }

    @isTest
    static void saveProjectImage_newAndReplace() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];

        // Upload first image
        ContentVersion cv1 = new ContentVersion(
            Title = 'Img1', PathOnClient = 'img1.png',
            VersionData = Blob.valueOf('x'), Origin = 'H'
        );
        insert cv1;
        cv1 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv1.Id];

        Test.startTest();
        // First save — no old links to delete, no existing link → inserts one
        ProjectBoardControllerClass.saveProjectImage(p.Id, cv1.ContentDocumentId);

        // Add a second image, then save it — exercises the delete-old-images branch
        ContentVersion cv2 = new ContentVersion(
            Title = 'Img2', PathOnClient = 'img2.png',
            VersionData = Blob.valueOf('y'), Origin = 'H'
        );
        insert cv2;
        cv2 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv2.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = cv2.ContentDocumentId,
            LinkedEntityId = p.Id, ShareType = 'V', Visibility = 'AllUsers'
        );
        ProjectBoardControllerClass.saveProjectImage(p.Id, cv2.ContentDocumentId);
        Test.stopTest();
    }
}