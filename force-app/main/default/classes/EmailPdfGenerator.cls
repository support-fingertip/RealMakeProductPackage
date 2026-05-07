/**
 * @description Generates PDF files from Visualforce pages for email attachments
 * @author Your Name
 * @date 2024
 */
public with sharing class EmailPdfGenerator {
    
    /**
     * @description Generate PDF from a Visualforce page
     * @param vfPageName Visualforce page API name
     * @param recordId Record ID to pass to the page
     * @param paramName Parameter name (default: 'id')
     * @return Blob PDF content
     */
    public static Blob generatePdfFromVfPage(String vfPageName, Id recordId, String paramName) {
        return generatePdfFromVfPage(vfPageName, recordId, paramName, null);
    }

    public static Blob generatePdfFromVfPage(String vfPageName, Id recordId, String paramName, Map<String, String> extraParams) {
        try {
            if (String.isBlank(vfPageName) || recordId == null) {
                throw new AuraHandledException('VF Page name and Record ID are required');
            }

            // Default param name to 'id'
            if (String.isBlank(paramName)) {
                paramName = 'id';
            }

            // Build page reference
            PageReference pageRef = new PageReference('/apex/' + vfPageName);
            pageRef.getParameters().put(paramName, recordId);

            // Add extra parameters (e.g., templateId for DynamicDocumentPDF)
            if (extraParams != null) {
                for (String key : extraParams.keySet()) {
                    if (String.isNotBlank(extraParams.get(key))) {
                        pageRef.getParameters().put(key, extraParams.get(key));
                    }
                }
            }

            // Generate PDF
            Blob pdfBlob;

            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Test PDF Content');
            } else {
                pdfBlob = pageRef.getContentAsPDF();
            }

            return pdfBlob;

        } catch (Exception e) {
            System.debug('Error generating PDF:  ' + e.getMessage());
            throw new AuraHandledException('Error generating PDF from ' + vfPageName + ': ' + e.getMessage());
        }
    }
    
    /**
     * @description Generate PDF and return as EmailFileAttachment
     * @param vfPageName Visualforce page API name
     * @param recordId Record ID
     * @param fileName File name for the attachment
     * @param paramName Parameter name (default: 'id')
     * @return Messaging. EmailFileAttachment
     */
    public static Messaging.EmailFileAttachment generatePdfAttachment(
        String vfPageName,
        Id recordId,
        String fileName,
        String paramName
    ) {
        return generatePdfAttachment(vfPageName, recordId, fileName, paramName, null);
    }

    public static Messaging.EmailFileAttachment generatePdfAttachment(
        String vfPageName,
        Id recordId,
        String fileName,
        String paramName,
        Map<String, String> extraParams
    ) {
        Blob pdfBlob = generatePdfFromVfPage(vfPageName, recordId, paramName, extraParams);

        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setFileName(fileName);
        attachment.setBody(pdfBlob);
        attachment.setContentType('application/pdf');

        return attachment;
    }
    
    /**
     * @description Get static document as attachment
     * @param documentId ContentDocument ID or Document ID
     * @return Messaging.EmailFileAttachment
     */
    public static Messaging.EmailFileAttachment getStaticDocumentAttachment(Id documentId) {
        try {
            // Check if it's a ContentDocument
            String objectType = documentId.getSObjectType().getDescribe().getName();
            
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            
            if (objectType == 'ContentDocument') {
                ContentVersion cv = [
                    SELECT Title, FileExtension, VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId = : documentId
                    AND IsLatest = true
                    LIMIT 1
                ];
                
                attachment.setFileName(cv.Title + '.' + cv.FileExtension);
                attachment.setBody(cv.VersionData);
                attachment.setContentType(getContentType(cv.FileExtension));
                
            } else if (objectType == 'Document') {
                Document doc = [
                    SELECT Name, Body, ContentType
                    FROM Document
                    WHERE Id = :documentId
                    LIMIT 1
                ];
                
                attachment.setFileName(doc.Name);
                attachment.setBody(doc.Body);
                attachment.setContentType(doc.ContentType);
            }
            
            return attachment;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error getting document:  ' + e.getMessage());
        }
    }
    
    /**
     * @description Get related files from a record as attachments
     * @param recordId Record ID
     * @return List of Messaging.EmailFileAttachment
     */
    public static List<Messaging.EmailFileAttachment> getRelatedFilesAttachments(Id recordId) {
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        
        try {
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :recordId
            ];
            
            if (links.isEmpty()) {
                return attachments;
            }
            
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink link : links) {
                docIds.add(link.ContentDocumentId);
            }
            
            List<ContentVersion> versions = [
                SELECT Title, FileExtension, VersionData
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
            ];
            
            for (ContentVersion cv : versions) {
                Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                attachment.setFileName(cv.Title + '.' + cv.FileExtension);
                attachment.setBody(cv.VersionData);
                attachment.setContentType(getContentType(cv.FileExtension));
                attachments.add(attachment);
            }
            
        } catch (Exception e) {
            System.debug('Error getting related files: ' + e.getMessage());
        }
        
        return attachments;
    }
    
    /**
     * @description Get content type from file extension
     */
    private static String getContentType(String extension) {
        if (String.isBlank(extension)) {
            return 'application/octet-stream';
        }
        
        extension = extension.toLowerCase();
        
        Map<String, String> contentTypes = new Map<String, String>{
            'pdf' => 'application/pdf',
            'doc' => 'application/msword',
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls' => 'application/vnd.ms-excel',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'ppt' => 'application/vnd.ms-powerpoint',
            'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'jpg' => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png' => 'image/png',
            'gif' => 'image/gif',
            'txt' => 'text/plain',
            'csv' => 'text/csv',
            'html' => 'text/html',
            'zip' => 'application/zip'
        };
        
        return contentTypes.containsKey(extension) 
            ? contentTypes.get(extension) 
            : 'application/octet-stream';
    }
    
    /**
     * @description Wrapper for attachment info (for LWC)
     */
    public class AttachmentInfo {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String VFPageName { get; set; }
        @AuraEnabled public String VFParamName { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String contentType { get; set; }
        @AuraEnabled public Long size { get; set; }
        @AuraEnabled public Boolean isRequired { get; set; }
        @AuraEnabled public Boolean isSelected { get; set; }
        @AuraEnabled public String previewUrl { get; set; }
        // Related record attachment fields
        @AuraEnabled public String recordSourceType { get; set; }
        @AuraEnabled public String selectedRelationship { get; set; }
        @AuraEnabled public String relationshipType { get; set; }
        @AuraEnabled public String relationshipName { get; set; }
        @AuraEnabled public String relatedObjectApi { get; set; }
        @AuraEnabled public String childRecordType { get; set; }
        @AuraEnabled public String filterConditionsJson { get; set; }
        @AuraEnabled public String orderByField { get; set; }
        @AuraEnabled public String orderByDirection { get; set; }
        @AuraEnabled public Integer singleChildLimit { get; set; }
        @AuraEnabled public Integer maxChildRecords { get; set; }
        @AuraEnabled public String fileNamePattern { get; set; }
        @AuraEnabled public String documentId { get; set; }
        @AuraEnabled public String documentTemplateId { get; set; }
    }
    
    /**
     * @description Get attachment info for display (without generating PDF yet)
     * @param attachmentsConfigJson Attachments config JSON
     * @param recordId Record ID
     * @param objectApiName Object API name
     * @return List of AttachmentInfo
     */
    @AuraEnabled
    public static List<AttachmentInfo> getAttachmentInfoList(
        String attachmentsConfigJson, 
        Id recordId, 
        String objectApiName
    ) {
        List<AttachmentInfo> attachmentList = new List<AttachmentInfo>();
        
        try {
            if (String.isBlank(attachmentsConfigJson)) {
                return attachmentList;
            }
            
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(attachmentsConfigJson);
            List<Object> attachments = (List<Object>) config.get('attachments');
            
            if (attachments == null) {
                return attachmentList;
            }
            
            for (Object att : attachments) {
                Map<String, Object> attMap = (Map<String, Object>) att;

                AttachmentInfo info = new AttachmentInfo();
                info.id = (String) attMap.get('id');
                info.name = (String) attMap.get('name');
                info.type = (String) attMap.get('type');
                info.isRequired = attMap.get('isRequired') == true;
                info.isSelected = attMap.get('isDefaultChecked') == true || info.isRequired;

                // Related record attachment fields
                info.recordSourceType = (String) attMap.get('recordSourceType');
                info.selectedRelationship = (String) attMap.get('selectedRelationship');
                info.relationshipType = (String) attMap.get('relationshipType');
                info.relationshipName = (String) attMap.get('relationshipName');
                info.relatedObjectApi = (String) attMap.get('relatedObjectApi');
                info.childRecordType = (String) attMap.get('childRecordType');
                info.filterConditionsJson = (String) attMap.get('filterConditionsJson');
                info.orderByField = (String) attMap.get('orderByField');
                info.orderByDirection = (String) attMap.get('orderByDirection');
                if (attMap.get('singleChildLimit') != null) {
                    info.singleChildLimit = Integer.valueOf(attMap.get('singleChildLimit'));
                }
                if (attMap.get('maxChildRecords') != null) {
                    info.maxChildRecords = Integer.valueOf(attMap.get('maxChildRecords'));
                }

                // Resolve file name with merge fields
                String fileNamePattern = (String) attMap.get('fileNamePattern');
                info.fileNamePattern = fileNamePattern;
                if (String.isNotBlank(fileNamePattern) && recordId != null) {
                    info.fileName = EmailMergeFieldResolver.resolveFileName(fileNamePattern, recordId, objectApiName);
                } else {
                    info.fileName = (String) attMap.get('fileName');
                    if (String.isBlank(info.fileName)) {
                        info.fileName = info.name + '.pdf';
                    }
                }

                // Set content type and preview URL based on type
                if (info.type == 'VFPage') {
                    info.contentType = 'application/pdf';
                    String vfPageName = (String) attMap.get('vfPageName');
                    String paramName = (String) attMap.get('vfPageParam');
                    String docTemplateId = (String) attMap.get('documentTemplateId');
                    if (String.isBlank(paramName)) paramName = 'id';
                    info.previewUrl = '/apex/' + vfPageName + '?' + paramName + '=' + recordId;
                    // Pass templateId for DynamicDocumentPDF
                    if (String.isNotBlank(docTemplateId)) {
                        info.previewUrl += '&templateId=' + docTemplateId;
                        info.documentTemplateId = docTemplateId;
                    }
                    info.VFPageName = vfPageName;
                    info.VFParamName = paramName;
                } else if (info.type == 'StaticDocument') {
                    String docId = (String) attMap.get('documentId');
                    info.documentId = docId;
                    info.previewUrl = '/sfc/servlet.shepherd/document/download/' + docId;
                }

                attachmentList.add(info);
            }
            
        } catch (Exception e) {
            System.debug('Error parsing attachments config: ' + e.getMessage());
        }
        
        return attachmentList;
    }
}