public class FieldMapperInvocable {
    
    @InvocableMethod(label='Map Fields Dynamically' description='Maps fields from source object to target object based on configuration')
    public static List<Result> mapFields(List<Request> requests) {
        List<Result> results = new List<Result>();
        
        for (Request req : requests) {
            Result res = new Result();
            res.success = false;
            
            try {
                if (String.isBlank(req.sourceRecordId) || String.isBlank(req.objectApiName)) {
                    res.errorMessage = 'Source Record Id and Object API Name are required';
                    results.add(res);
                    continue;
                }
                
                // Get active mapping configuration
                List<Field_Mapping_Configuration__c> configs = [
                    SELECT Id, From_Object__c, To_Object__c,
                           (SELECT From_Field_API_Name__c, To_Field_API_Name__c, From_Field_Type__c, To_Field_Type__c 
                            FROM Field_Mapping_Details__r 
                            ORDER BY Sequence__c NULLS LAST)
                    FROM Field_Mapping_Configuration__c
                    WHERE From_Object__c = :req.objectApiName
                    AND Is_Active__c = true
                    LIMIT 1
                ];
                
                if (configs.isEmpty()) {
                    res.success = true;
                    res.message = 'No active mapping configuration found';
                    results.add(res);
                    continue;
                }
                
                Field_Mapping_Configuration__c config = configs[0];
                
                processMappingForRecord(req.sourceRecordId,req.targetRecordId, config, req.isInsert);
                
                res.success = true;
                res.message = 'Mapping completed successfully';
                
            } catch (Exception e) {
                res.errorMessage = e.getMessage() + ' | ' + e.getStackTraceString();
                logError(req.sourceRecordId, null, res.errorMessage, null, req.isInsert ? 'Insert' : 'Update');
            }
            
            results.add(res);
        }
        
        return results;
    }
    
    private static void processMappingForRecord(String sourceRecordId, String targetRecordId, Field_Mapping_Configuration__c config, Boolean isInsert) {
        String fromObject = config.From_Object__c;
        String toObject = config.To_Object__c;
        
        Set<String> fieldsToQuery = new Set<String>{'Id'};
       
        for (Field_Mapping_Detail__c detail : config.Field_Mapping_Details__r) {
            fieldsToQuery.add(detail.From_Field_API_Name__c);
        }
        
        String soql = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') + 
                      ' FROM ' + fromObject + 
                      ' WHERE Id = \''+sourceRecordId+'\' LIMIT 1';
        system.debug('FormedQuery '+soql);
        List<SObject> sourceRecords = Database.query(soql);
        
        if (sourceRecords.isEmpty()) {
            return;
        }
        
        SObject sourceRecord = sourceRecords[0];
        
        SObject targetRecord;
        
        if (String.isNotBlank(targetRecordId)) {
            targetRecord = Schema.getGlobalDescribe().get(toObject).newSObject(targetRecordId);
        } else {
            targetRecord = Schema.getGlobalDescribe().get(toObject).newSObject();
        }
        
        Boolean hasChanges = false;
        for (Field_Mapping_Detail__c detail : config.Field_Mapping_Details__r) {
            try {
                Object fieldValue = sourceRecord.get(detail.From_Field_API_Name__c);
                targetRecord.put(detail.To_Field_API_Name__c, fieldValue);
                hasChanges = true;
            } catch (Exception e) {
                logError(sourceRecordId, targetRecordId, 
                        'Field mapping error for ' + detail.From_Field_API_Name__c + ' -> ' + detail.To_Field_API_Name__c + ': ' + e.getMessage(),
                        config.Id, isInsert ? 'Insert' : 'Update');
            }
        }
        
        if (hasChanges) {
            try {
                Database.SaveResult sr;
                if (String.isNotBlank(targetRecordId)) {
                    sr = Database.update(targetRecord, false);
                } else {
                    sr = Database.insert(targetRecord, false);
                }
                
                if (!sr.isSuccess()) {
                    String errors = '';
                    for (Database.Error err : sr.getErrors()) {
                        errors += err.getMessage() + '; ';
                    }
                    logError(sourceRecordId, targetRecordId, errors, config.Id, isInsert ? 'Insert' : 'Update');
                } else {
                    if (String.isBlank(targetRecordId)) {
                        SObject sourceUpdate = Schema.getGlobalDescribe().get(fromObject).newSObject(sourceRecordId);
                        Database.update(sourceUpdate, false);
                    }
                }
            } catch (Exception e) {
                logError(sourceRecordId, targetRecordId, e.getMessage(), config.Id, isInsert ? 'Insert' : 'Update');
            }
        }
    }
    
    @future
    private static void logError(String sourceRecordId, String targetRecordId, String errorMessage, Id configId, String operationType) {
        try {
            Field_Mapping_Error_Log__c errorLog = new Field_Mapping_Error_Log__c(
                Source_Record_Id__c = sourceRecordId,
                Target_Record_Id__c = targetRecordId,
                Error_Message__c = errorMessage,
                Field_Mapping_Configuration__c = configId,
                Error_Timestamp__c = System.now(),
                Operation_Type__c = operationType
            );
            insert errorLog;
        } catch (Exception e) {
            System.debug('Error logging failed: ' + e.getMessage());
        }
    }
    
    public class Request {
        @InvocableVariable(label='Source Record Id' required=true)
        public String sourceRecordId;
        
        @InvocableVariable(label='Object API Name' required=true)
        public String objectApiName;
        
        @InvocableVariable(label='Is Insert Operation' required=true)
        public Boolean isInsert;
        
        @InvocableVariable(label='Target Record Id' required=true)
        public String targetRecordId;
    }
    
    public class Result {
        @InvocableVariable
        public Boolean success;
        
        @InvocableVariable
        public String message;
        
        @InvocableVariable
        public String errorMessage;
    }
}