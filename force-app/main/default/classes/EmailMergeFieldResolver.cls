/**
 * @description Resolves merge fields in email subject and body
 * @author Your Name
 * @date 2024
 */
public with sharing class EmailMergeFieldResolver {
    
    // Merge field pattern:  {! FieldName} or {! Relationship. FieldName}
    private static final Pattern MERGE_FIELD_PATTERN = Pattern.compile('\\{!([\\w\\.]+)\\}');
    
    /**
     * @description Resolve all merge fields in a text string
     * @param template Text with merge fields
     * @param recordId Record ID to get values from
     * @param objectApiName Object API name
     * @return Resolved text with actual values
     */
    @AuraEnabled
    public static String resolveMergeFields(String template, Id recordId, String objectApiName) {
        if (String.isBlank(template) || recordId == null) {
            return template;
        }
        
        try {
            // Extract all merge fields from template
            Set<String> fieldsToQuery = extractMergeFields(template);
            
            if (fieldsToQuery.isEmpty()) {
                return template;
            }
            
            // Query the record with required fields
            SObject record = queryRecord(recordId, objectApiName, fieldsToQuery);
            
            if (record == null) {
                return template;
            }
            
            // Replace merge fields with values
            return replaceMergeFields(template, record, objectApiName);
            
        } catch (Exception e) {
            System.debug('Error resolving merge fields: ' + e.getMessage());
            return template;
        }
    }
    
    /**
     * @description Extract all merge field names from template
     * @param template Text with merge fields
     * @return Set of field API names
     */
    public static Set<String> extractMergeFields(String template) {
        Set<String> fields = new Set<String>();
        
        if (String.isBlank(template)) {
            return fields;
        }
        
        Matcher matcher = MERGE_FIELD_PATTERN.matcher(template);
        
        while (matcher.find()) {
            String fieldPath = matcher.group(1);
            fields.add(fieldPath);
        }
        
        return fields;
    }
    
    /**
     * @description Query record with all required fields
     * @param recordId Record ID
     * @param objectApiName Object API name
     * @param fieldsToQuery Set of fields to query
     * @return SObject record
     */
    private static SObject queryRecord(Id recordId, String objectApiName, Set<String> fieldsToQuery) {
        // Build field list for query
        Set<String> queryFields = new Set<String>{'Id'};
        
        for (String fieldPath : fieldsToQuery) {
            queryFields.add(fieldPath);
        }
        
        String fieldList = String.join(new List<String>(queryFields), ', ');
        String query = 'SELECT ' + fieldList + ' FROM ' + objectApiName + ' WHERE Id = : recordId LIMIT 1';
        
        List<SObject> records = Database.query(query);
        
        return records.isEmpty() ? null : records[0];
    }
    
    /**
     * @description Replace merge fields with actual values
     * @param template Text with merge fields
     * @param record SObject record
     * @param objectApiName Object API name
     * @return Resolved text
     */
    private static String replaceMergeFields(String template, SObject record, String objectApiName) {
        String result = template;
        
        Matcher matcher = MERGE_FIELD_PATTERN.matcher(template);
        
        while (matcher.find()) {
            String fullMatch = matcher.group(0); // {!FieldName}
            String fieldPath = matcher.group(1); // FieldName
            
            String value = getFieldValue(record, fieldPath);
            
            // Replace the merge field with the value
            result = result.replace(fullMatch, value != null ? value : '');
        }
        
        return result;
    }
    
    /**
     * @description Get field value from record, supporting relationship fields
     * @param record SObject record
     * @param fieldPath Field path (e.g., "Name" or "Contact__r.Email")
     * @return String value
     */
    public static String getFieldValue(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) {
            return null;
        }
        
        try {
            // Split the field path by dots
            List<String> pathParts = fieldPath.split('\\.');
            
            SObject currentRecord = record;
            
            // Navigate through relationships
            for (Integer i = 0; i < pathParts.size() - 1; i++) {
                if (currentRecord == null) {
                    return null;
                }
                currentRecord = currentRecord.getSObject(pathParts[i]);
            }
            
            if (currentRecord == null) {
                return null;
            }
            
            // Get the final field value
            String finalField = pathParts[pathParts.size() - 1];
            Object value = currentRecord.get(finalField);
            
            return formatValue(value);
            
        } catch (Exception e) {
            System.debug('Error getting field value for ' + fieldPath + ': ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Format field value for display
     * @param value Object value
     * @return Formatted string
     */
    private static String formatValue(Object value) {
        if (value == null) {
            return '';
        }
        
        if (value instanceof Date) {
            return ((Date) value).format();
        } else if (value instanceof DateTime) {
            return ((DateTime) value).format('dd-MMM-yyyy hh:mm a');
        } else if (value instanceof Decimal) {
            Decimal decValue = (Decimal) value;
            // Format as currency if it looks like money
            if (decValue >= 1000) {
                return decValue.setScale(2).format();
            }
            return String.valueOf(decValue);
        } else if (value instanceof Boolean) {
            return (Boolean) value ? 'Yes' : 'No';
        }
        
        return String.valueOf(value);
    }
    
    /**
     * @description Resolve email addresses from field paths
     * @param fieldPath Field path (e.g., "Contact__r.Email")
     * @param recordId Record ID
     * @param objectApiName Object API name
     * @return Email address
     */
    @AuraEnabled
    public static String resolveEmailField(String fieldPath, Id recordId, String objectApiName) {
        if (String.isBlank(fieldPath) || recordId == null) {
            return null;
        }
        
        try {
            Set<String> fields = new Set<String>{fieldPath};
            SObject record = queryRecord(recordId, objectApiName, fields);
            
            if (record == null) {
                return null;
            }
            
            return getFieldValue(record, fieldPath);
            
        } catch (Exception e) {
            System.debug('Error resolving email field: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Resolve recipient emails based on source type
     * @param recipientConfig JSON config for recipient
     * @param recordId Record ID
     * @param objectApiName Object API name
     * @return Email address
     */
    @AuraEnabled
    public static String resolveRecipientEmail(String sourceType, String fieldApiName, String staticEmail, Id recordId, String objectApiName) {
        try {
            if (sourceType == 'Static') {
                return staticEmail;
            } else if (sourceType == 'CurrentUser') {
                return UserInfo.getUserEmail();
            } else if (sourceType == 'RecordOwner') {
                return resolveEmailField('Owner.Email', recordId, objectApiName);
            } else if (sourceType == 'OwnerManager') {
                return resolveEmailField('Owner.Manager.Email', recordId, objectApiName);
            } else if (sourceType == 'Field' && String.isNotBlank(fieldApiName)) {
                return resolveEmailField(fieldApiName, recordId, objectApiName);
            }
            
            return null;
            
        } catch (Exception e) {
            System.debug('Error resolving recipient email: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Resolve file name pattern with merge fields
     * @param fileNamePattern Pattern like "Invoice_{! Name}.pdf"
     * @param recordId Record ID
     * @param objectApiName Object API name
     * @return Resolved file name
     */
    @AuraEnabled
    public static String resolveFileName(String fileNamePattern, Id recordId, String objectApiName) {
        if (String.isBlank(fileNamePattern)) {
            return 'Attachment.pdf';
        }
        
        return resolveMergeFields(fileNamePattern, recordId, objectApiName);
    }
}