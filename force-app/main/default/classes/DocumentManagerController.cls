public with sharing class DocumentManagerController {
    
    // ============ WRAPPER CLASSES ============
    
    public class CategoryWrapper {
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String icon { get; set; }
        @AuraEnabled public List<DocumentTypeWrapper> documentTypes { get; set; }
        @AuraEnabled public String tabLabel { get; set; }
        @AuraEnabled public Integer uploadedCount { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        
        public CategoryWrapper() {
            this.documentTypes = new List<DocumentTypeWrapper>();
            this.uploadedCount = 0;
            this.totalCount = 0;
        }
    }
    
    public class DocumentTypeWrapper {
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public List<DocumentWrapper> files { get; set; }
        @AuraEnabled public Boolean hasFiles { get; set; }
        @AuraEnabled public Integer fileCount { get; set; }
        @AuraEnabled public String thumbnailUrl { get; set; }
        @AuraEnabled public Boolean isImage { get; set; }
        @AuraEnabled public Boolean multipleFiles { get; set; }
        
        public DocumentTypeWrapper() {
            this.files = new List<DocumentWrapper>();
            this.hasFiles = false;
            this.fileCount = 0;
            this.isImage = false;
            this.multipleFiles = false;
        }
    }
    
    public class DocumentWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String contentDocumentId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String fileExtension { get; set; }
        @AuraEnabled public Long contentSize { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String documentType { get; set; }
        @AuraEnabled public String uploadedBy { get; set; }
        @AuraEnabled public Datetime uploadedDate { get; set; }
        @AuraEnabled public Boolean isImage { get; set; }
        @AuraEnabled public String thumbnailUrl { get; set; }
        @AuraEnabled public String downloadUrl { get; set; }
    }
    
    // ============ ICON LIST FOR RANDOM SELECTION ============
    
    private static List<String> getIconList() {
        return new List<String>{
            'standard:folder',
            'standard:home',
            'standard:contract',  
            'standard:account',  
            'standard:task',    
            'standard:file',
            'standard:document',
            'standard:identity',
            'standard:currency',
            'standard:contact',
            'standard:note',
            'standard:record',
            'standard:approval',
            'standard:customer'
        };
    }
    
    /**
     * @description Image file extensions
     */
    private static Set<String> getImageExtensions() {
        return new Set<String>{'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'};
    }
    
    // ============ GET DEPENDENT PICKLIST VALUES ============

    /**
     * @description Get valid categories for a given Object API Name
     *              by reading the Object_API_Name__c → Document_Category__c dependency
     * @param objectApiName The object API name to filter by (e.g. 'Booking__c')
     * @return Set of valid category values for this object (empty set = all categories)
     */
    /**
     * @description Get valid categories for a given Object API Name.
     *              Returns null when no filtering should be applied (blank objectApiName
     *              or object not in picklist). Returns a Set (possibly empty) when
     *              filtering is active.
     */
    private static Set<String> getValidCategoriesForObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null; // null = no filtering, show all
        }

        Schema.DescribeFieldResult objectFieldDescribe = ContentVersion.Object_API_Name__c.getDescribe();
        Schema.DescribeFieldResult categoryFieldDescribe = ContentVersion.Document_Category__c.getDescribe();

        List<Schema.PicklistEntry> objectEntries = objectFieldDescribe.getPicklistValues();
        List<PicklistEntryWrapper> categoryEntries = wrapPicklistEntries(categoryFieldDescribe.getPicklistValues());

        // Find the index of the matching Object_API_Name__c picklist value
        Integer objectIndex = -1;
        Integer idx = 0;
        for (Schema.PicklistEntry objEntry : objectEntries) {
            if (objEntry.getValue() == objectApiName) {
                objectIndex = idx;
                break;
            }
            idx++;
        }

        if (objectIndex == -1) {
            return null; // object not in picklist, no filtering
        }

        // Check if dependency is configured (at least one entry has validFor)
        Boolean hasDependency = false;
        for (PicklistEntryWrapper catEntry : categoryEntries) {
            if (String.isNotBlank(catEntry.validFor)) {
                hasDependency = true;
                break;
            }
        }

        if (!hasDependency) {
            return null; // no dependency configured, show all
        }

        // Filter categories based on dependency
        Set<String> validCategories = new Set<String>();
        for (PicklistEntryWrapper catEntry : categoryEntries) {
            if (!catEntry.active) continue;

            String validForBits = catEntry.validFor;
            if (String.isNotBlank(validForBits)) {
                List<Integer> controllingIndexes = getControllingIndexes(validForBits);
                if (controllingIndexes.contains(objectIndex)) {
                    validCategories.add(catEntry.value);
                }
            }
        }

        return validCategories;
    }

    /**
     * @description Get Document Types grouped by Category from dependent picklist
     * @return Map of Category value to List of Document Type values
     */
    private static Map<String, List<String>> getDocumentTypesByCategory() {
        Map<String, List<String>> categoryToDocTypes = new Map<String, List<String>>();
        
        Schema.DescribeFieldResult categoryFieldDescribe = ContentVersion.Document_Category__c.getDescribe();
        Schema.DescribeFieldResult docTypeFieldDescribe = ContentVersion.Document_Type__c.getDescribe();
        
        List<Schema.PicklistEntry> categoryEntries = categoryFieldDescribe.getPicklistValues();
        List<PicklistEntryWrapper> docTypeEntries = wrapPicklistEntries(docTypeFieldDescribe.getPicklistValues());
        
        // Initialize map with all categories
        for (Schema.PicklistEntry catEntry : categoryEntries) {
            if (catEntry.isActive()) {
                categoryToDocTypes.put(catEntry.getValue(), new List<String>());
            }
        }
        
        // Check if dependency is configured
        Boolean hasDependency = false;
        for (PicklistEntryWrapper docTypeEntry : docTypeEntries) {
            if (String.isNotBlank(docTypeEntry.validFor)) {
                hasDependency = true;
                break;
            }
        }

        // Map document types to their controlling categories
        for (PicklistEntryWrapper docTypeEntry : docTypeEntries) {
            if (!docTypeEntry.active) continue;

            String validForBits = docTypeEntry.validFor;
            if (!hasDependency || String.isBlank(validForBits)) {
                if (!hasDependency) {
                    // No dependency configured at all - add to all categories
                    for (String catValue : categoryToDocTypes.keySet()) {
                        categoryToDocTypes.get(catValue).add(docTypeEntry.value);
                    }
                }
                // If dependency exists but this entry has no mapping, skip it
            } else {
                // Decode the validFor to find controlling values
                List<Integer> controllingIndexes = getControllingIndexes(validForBits);
                Integer catIndex = 0;
                for (Schema.PicklistEntry catEntry : categoryEntries) {
                    if (catEntry.isActive()) {
                        if (controllingIndexes.contains(catIndex)) {
                            if (categoryToDocTypes.containsKey(catEntry.getValue())) {
                                categoryToDocTypes.get(catEntry.getValue()).add(docTypeEntry.value);
                            }
                        }
                    }
                    catIndex++;
                }
            }
        }
        
        return categoryToDocTypes;
    }
    
    /**
     * @description Wrapper class for picklist entries with validFor
     */
    private class PicklistEntryWrapper {
        public String value { get; set; }
        public String label { get; set; }
        public Boolean active { get; set; }
        public String validFor { get; set; }
    }
    
    /**
     * @description Wrap picklist entries to access validFor attribute
     */
    private static List<PicklistEntryWrapper> wrapPicklistEntries(List<Schema.PicklistEntry> entries) {
        String entriesJson = JSON.serialize(entries);
        List<PicklistEntryWrapper> deserializedEntries = (List<PicklistEntryWrapper>) JSON.deserialize(
            entriesJson, 
            List<PicklistEntryWrapper>.class
        );
        return deserializedEntries;
    }
    
    /**
     * @description Decode validFor Base64 string to get controlling field indexes
     */
    private static List<Integer> getControllingIndexes(String validFor) {
        List<Integer> indexes = new List<Integer>();
        
        if (String.isBlank(validFor)) {
            return indexes;
        }
        
        String base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        
        Integer bitIndex = 0;
        for (Integer i = 0; i < validFor.length(); i++) {
            String char1 = validFor.substring(i, i + 1);
            Integer charIndex = base64Chars.indexOf(char1);
            
            if (charIndex >= 0) {
                for (Integer bit = 5; bit >= 0; bit--) {
                    if ((charIndex & (1 << bit)) != 0) {
                        indexes.add(bitIndex);
                    }
                    bitIndex++;
                }
            }
        }
        
        return indexes;
    }
    
    /**
     * @description Get category order from picklist
     */
    private static List<String> getCategoryOrder() {
        List<String> categoryOrder = new List<String>();
        Schema.DescribeFieldResult categoryFieldDescribe = ContentVersion.Document_Category__c.getDescribe();
        
        for (Schema.PicklistEntry entry : categoryFieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                categoryOrder.add(entry.getValue());
            }
        }
        
        return categoryOrder;
    }
    
    /**
     * @description Get random icon for a category based on its index
     */
    private static String getIconForCategory(Integer index) {
        List<String> icons = getIconList();
        Integer iconIndex = Math.mod(index, icons.size());
        return icons[iconIndex];
    }
    
    // ============ MAIN METHOD:  Get Documents With Config ============
    
    @AuraEnabled
    public static List<CategoryWrapper> getDocumentsWithConfig(String bookingId, String objectApiName) {
        List<CategoryWrapper> categories = new List<CategoryWrapper>();

        try {
            // Get dynamic configuration from picklists
            Map<String, List<String>> docTypesByCategory = getDocumentTypesByCategory();
            List<String> categoryOrder = getCategoryOrder();

            // Get valid categories for the specified object (null = show all)
            Set<String> validCategories = getValidCategoriesForObject(objectApiName);

            // Get uploaded documents map
            Map<String, List<DocumentWrapper>> uploadedDocsMap = new Map<String, List<DocumentWrapper>>();
            if (String.isNotBlank(bookingId)) {
                uploadedDocsMap = getUploadedDocumentsMap(bookingId);
            }

            // Build categories in picklist order
            Integer catIndex = 0;
            for (String catValue : categoryOrder) {
                // Skip categories not valid for this object (null = no filtering)
                if (validCategories != null && !validCategories.contains(catValue)) {
                    continue;
                }

                CategoryWrapper cat = new CategoryWrapper();
                cat.value = catValue;
                cat.label = catValue;
                cat.icon = getIconForCategory(catIndex);

                List<String> docTypes = docTypesByCategory.get(catValue);
                Integer uploadedCount = 0;

                if (docTypes != null && !docTypes.isEmpty()) {
                    for (String docTypeName : docTypes) {
                        DocumentTypeWrapper dt = new DocumentTypeWrapper();
                        dt.value = docTypeName;
                        dt.label = docTypeName;
                        dt.category = catValue;

                        // Check if documents exist for this type
                        String key = catValue + '|' + docTypeName;
                        if (uploadedDocsMap.containsKey(key)) {
                            List<DocumentWrapper> files = uploadedDocsMap.get(key);
                            dt.files = files;
                            dt.hasFiles = true;
                            dt.fileCount = files.size();
                            dt.multipleFiles = files.size() > 1;
                            dt.isImage = files[0].isImage;
                            dt.thumbnailUrl = files[0].thumbnailUrl;
                            uploadedCount++;
                        }

                        cat.documentTypes.add(dt);
                    }
                }

                cat.uploadedCount = uploadedCount;
                cat.totalCount = cat.documentTypes.size();
                cat.tabLabel = catValue + ' (' + uploadedCount + '/' + cat.totalCount + ')';

                categories.add(cat);
                catIndex++;
            }

        } catch (Exception e) {
            throw new AuraHandledException('Error loading documents:  ' + e.getMessage());
        }

        return categories;
    }
    
    // ============ Get Uploaded Documents Map ============
    
    private static Map<String, List<DocumentWrapper>> getUploadedDocumentsMap(String bookingId) {
        Map<String, List<DocumentWrapper>> docMap = new Map<String, List<DocumentWrapper>>();
        
        if (String.isBlank(bookingId)) {
            return docMap;
        }
        
        // Get all ContentDocumentLinks for this booking
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :bookingId
        ];
        
        if (links.isEmpty()) {
            return docMap;
        }
        
        Set<Id> contentDocIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            contentDocIds.add(link.ContentDocumentId);
        }
        
        // Get ContentVersions with custom fields
        List<ContentVersion> versions = [
            SELECT Id, Title, ContentDocumentId, FileExtension, ContentSize,
                   CreatedDate, CreatedBy.Name,
                   Document_Category__c, Document_Type__c, Object_API_Name__c
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds
            AND IsLatest = true
            AND Document_Category__c != null
            AND Document_Type__c != null
            ORDER BY CreatedDate DESC
        ];
        
        Set<String> imageExts = getImageExtensions();
        
        for (ContentVersion cv : versions) {
            DocumentWrapper doc = new DocumentWrapper();
            doc.id = cv.Id;
            doc.contentDocumentId = cv.ContentDocumentId;
            doc.title = cv.Title;
            doc.fileExtension = cv.FileExtension;
            doc.contentSize = cv.ContentSize;
            doc.category = cv.Document_Category__c;
            doc.documentType = cv.Document_Type__c;
            doc.uploadedBy = cv.CreatedBy.Name;
            doc.uploadedDate = cv.CreatedDate;
            
            String ext = cv.FileExtension != null ? cv.FileExtension.toLowerCase() : '';
            doc.isImage = imageExts.contains(ext);
            
            // Set thumbnail URL
            if (doc.isImage) {
                doc.thumbnailUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
            } else {
                doc.thumbnailUrl = null;
            }
            doc.downloadUrl = '/sfc/servlet.shepherd/document/download/' + cv.ContentDocumentId;
            
            String key = cv.Document_Category__c + '|' + cv.Document_Type__c;
            if (! docMap.containsKey(key)) {
                docMap.put(key, new List<DocumentWrapper>());
            }
            docMap.get(key).add(doc);
        }
        
        return docMap;
    }
    
    // ============ GET PICKLIST VALUES ============
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPicklistValues() {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Get Categories
            List<Map<String, String>> categoryOptions = new List<Map<String, String>>();
            Schema.DescribeFieldResult catField = ContentVersion.Document_Category__c.getDescribe();
            for (Schema.PicklistEntry entry : catField.getPicklistValues()) {
                if (entry.isActive()) {
                    categoryOptions.add(new Map<String, String>{
                        'label' => entry.getLabel(),
                        'value' => entry.getValue()
                    });
                }
            }
            result.put('categories', categoryOptions);
            
            // Get Document Types grouped by Category
            Map<String, List<Map<String, String>>> docTypesByCategory = new Map<String, List<Map<String, String>>>();
            Map<String, List<String>> dependencyMap = getDocumentTypesByCategory();
            
            for (String category : dependencyMap.keySet()) {
                List<Map<String, String>> typeOptions = new List<Map<String, String>>();
                for (String docType : dependencyMap.get(category)) {
                    typeOptions.add(new Map<String, String>{
                        'label' => docType,
                        'value' => docType
                    });
                }
                docTypesByCategory.put(category, typeOptions);
            }
            result.put('documentTypesByCategory', docTypesByCategory);
            
        } catch (Exception e) {
            throw new AuraHandledException('Error getting picklist values: ' + e.getMessage());
        }
        
        return result;
    }
    
    // ============ UPDATE DOCUMENT METADATA ============
    
    @AuraEnabled
    public static void updateDocumentMetadata(String contentDocumentId, String bookingId,
                                               String category, String documentType, String objectApiName) {
        try {
            if (String.isBlank(contentDocumentId)) {
                throw new AuraHandledException('Content Document ID is required');
            }
            if (String.isBlank(category)) {
                throw new AuraHandledException('Category is required');
            }
            if (String.isBlank(documentType)) {
                throw new AuraHandledException('Document Type is required');
            }

            List<ContentVersion> versions = [
                SELECT Id, Document_Category__c, Document_Type__c, Object_API_Name__c
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];

            if (versions.isEmpty()) {
                throw new AuraHandledException('Content Version not found');
            }

            ContentVersion cv = versions[0];
            cv.Document_Category__c = category;
            cv.Document_Type__c = documentType;
            if (String.isNotBlank(objectApiName)) {
                cv.Object_API_Name__c = objectApiName;
            }
            update cv;
            
            // Ensure ContentDocumentLink exists
            List<ContentDocumentLink> existingLinks = [
                SELECT Id 
                FROM ContentDocumentLink
                WHERE ContentDocumentId = : contentDocumentId
                AND LinkedEntityId = :bookingId
                LIMIT 1
            ];
            
            if (existingLinks.isEmpty()) {
                ContentDocumentLink link = new ContentDocumentLink();
                link.ContentDocumentId = contentDocumentId;
                link.LinkedEntityId = bookingId;
                link.ShareType = 'V';
                link.Visibility = 'AllUsers';
                insert link;
            }
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating document:  ' + e.getMessage());
        }
    }
    
    // ============ DELETE DOCUMENT ============
    
    @AuraEnabled
    public static void deleteDocument(String contentDocumentId) {
        try {
            if (String.isBlank(contentDocumentId)) {
                throw new AuraHandledException('Content Document ID is required');
            }
            
            List<ContentDocument> docs = [
                SELECT Id 
                FROM ContentDocument 
                WHERE Id = :contentDocumentId 
                LIMIT 1
            ];
            
            if (docs.isEmpty()) {
                throw new AuraHandledException('Document not found');
            }
            
            delete docs[0];
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting document: ' + e.getMessage());
        }
    }
    
    // ============ GET DOCUMENT STATISTICS ============
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getDocumentStats(String bookingId) {
        Map<String, Integer> stats = new Map<String, Integer>{
            'uploaded' => 0,
            'total' => 0
        };
        
        try {
            if (String.isBlank(bookingId)) {
                return stats;
            }
            
            // Get document types by category (dynamic)
            Map<String, List<String>> docTypesByCategory = getDocumentTypesByCategory();
            
            // Calculate total
            Integer totalCount = 0;
            for (String category : docTypesByCategory.keySet()) {
                totalCount += docTypesByCategory.get(category).size();
            }
            stats.put('total', totalCount);
            
            // Get uploaded documents
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :bookingId
            ];
            
            if (! links.isEmpty()) {
                Set<Id> docIds = new Set<Id>();
                for (ContentDocumentLink l : links) {
                    docIds.add(l.ContentDocumentId);
                }
                
                // Get unique document types uploaded
                List<AggregateResult> results = [
                    SELECT Document_Category__c cat, Document_Type__c docType
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :docIds
                    AND IsLatest = true
                    AND Document_Category__c != null
                    AND Document_Type__c != null
                    GROUP BY Document_Category__c, Document_Type__c
                ];
                
                stats.put('uploaded', results.size());
            }
            
        } catch (Exception e) {
            System.debug('Error getting document stats: ' + e.getMessage());
        }
        
        return stats;
    }
   
    /**
	* @description Get all document IDs for download
	* @param bookingId The Booking record Id
	* @return List of ContentVersion IDs
	*/
    @AuraEnabled
    public static List<Id> getDocumentIdsForDownload(String bookingId) {
        List<Id> contentVersionIds = new List<Id>();
        
        try {
            if (String.isBlank(bookingId)) {
                throw new AuraHandledException('Booking ID is required');
            }
            
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :bookingId
            ];
            
            if (links.isEmpty()) {
                return contentVersionIds;
            }
            
            Set<Id> contentDocIds = new Set<Id>();
            for (ContentDocumentLink link : links) {
                contentDocIds.add(link.ContentDocumentId);
            }
            
            // Get ContentVersion IDs
            List<ContentVersion> versions = [
                SELECT Id
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocIds
                AND IsLatest = true
                AND Document_Category__c != null
                AND Document_Type__c != null
                ORDER BY Document_Category__c, Document_Type__c
            ];
            
            for (ContentVersion cv : versions) {
                contentVersionIds.add(cv.Id);
            }
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting documents:  ' + e.getMessage());
        }
        
        return contentVersionIds;
    }
    
    /**
	* @description Get all document download URLs for a booking
	* @param bookingId The Booking record Id
	* @return List of document info with download URLs
	*/
    @AuraEnabled
    public static List<Map<String, String>> getDocumentDownloadUrls(String bookingId) {
        List<Map<String, String>> documents = new List<Map<String, String>>();
        
        try {
            if (String.isBlank(bookingId)) {
                throw new AuraHandledException('Booking ID is required');
            }
            
            // Get all ContentDocumentLinks for this booking
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :bookingId
            ];
            
            if (links.isEmpty()) {
                return documents;
            }
            
            Set<Id> contentDocIds = new Set<Id>();
            for (ContentDocumentLink link : links) {
                contentDocIds.add(link.ContentDocumentId);
            }
            
            // Get ContentVersions
            List<ContentVersion> versions = [
                SELECT Id, Title, ContentDocumentId, FileExtension,
                Document_Category__c, Document_Type__c
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocIds
                AND IsLatest = true
                AND Document_Category__c != null
                AND Document_Type__c != null
                ORDER BY Document_Category__c, Document_Type__c
            ];
            
            for (ContentVersion cv : versions) {
                Map<String, String> docInfo = new Map<String, String>();
                docInfo.put('id', cv.Id);
                docInfo.put('contentDocumentId', cv.ContentDocumentId);
                docInfo.put('title', cv.Title);
                docInfo.put('extension', cv.FileExtension);
                docInfo.put('category', cv.Document_Category__c);
                docInfo.put('documentType', cv.Document_Type__c);
                docInfo.put('downloadUrl', '/sfc/servlet.shepherd/document/download/' + cv.ContentDocumentId);
                documents.add(docInfo);
            }
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting documents:  ' + e.getMessage());
        }
        
        return documents;
    }
}