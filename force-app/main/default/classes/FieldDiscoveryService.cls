/**
 * @description Service to discover User lookup fields on any object
 * Traverses relationships up to 2 levels deep
 */
public with sharing class FieldDiscoveryService {

    private static final Integer MAX_DEPTH = 2;
    private static final String USER_OBJECT_NAME = 'User';
    
    /**
     * @description Discover all field paths that resolve to a User lookup
     * @param objectApiName The object to analyze
     * @return List of field path options
     */
    public static List<DynamicApprovalController.FieldPathOption> discoverUserLookups(String objectApiName) {
        List<DynamicApprovalController.FieldPathOption> allPaths = new List<DynamicApprovalController.FieldPathOption>();
        
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            return allPaths;
        }
        
        // Discover fields recursively
        discoverFieldsRecursive(
            objectType,
            '',
            '',
            0,
            allPaths,
            new Set<String>()
        );
        
        return allPaths;
    }
    
    /**
     * @description Recursive method to discover User lookups
     */
    private static void discoverFieldsRecursive(
        Schema.SObjectType objectType,
        String pathPrefix,
        String labelPrefix,
        Integer currentDepth,
        List<DynamicApprovalController.FieldPathOption> results,
        Set<String> visitedObjects
    ) {
        if (currentDepth > MAX_DEPTH) {
            return;
        }
        
        String objectName = objectType.getDescribe().getName();
        
        // Prevent infinite loops
        if (visitedObjects.contains(objectName + '_' + currentDepth)) {
            return;
        }
        visitedObjects.add(objectName + '_' + currentDepth);
        
        Map<String, Schema.SObjectField> fieldsMap = objectType.getDescribe().fields.getMap();
        
        for (String fieldName : fieldsMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
            
            // Skip non-accessible fields
            if (! fieldDescribe.isAccessible()) {
                continue;
            }
            
            // Check if it's a lookup/reference field
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();
                
                for (Schema.SObjectType refType : referenceTo) {
                    String refObjectName = refType.getDescribe().getName();
                    
                    // If it references User, add to results
                    if (refObjectName == USER_OBJECT_NAME) {
                        String fullPath = String.isBlank(pathPrefix)
                            ? fieldDescribe.getName()
                            : pathPrefix + '.' + fieldDescribe.getName();
                        String fullLabel = String.isBlank(labelPrefix)
                            ? fieldDescribe.getLabel()
                            : labelPrefix + ' → ' + fieldDescribe.getLabel();

                        results.add(new DynamicApprovalController.FieldPathOption(
                            fullLabel,
                            fullPath,
                            currentDepth,
                            USER_OBJECT_NAME
                        ));
                    }
                    // If it's another object, recurse into it
                    else if (currentDepth < MAX_DEPTH && isTraversableObject(refObjectName)) {
                        String relationshipName = fieldDescribe.getRelationshipName();
                        if (String.isNotBlank(relationshipName)) {
                            String newPathPrefix = String.isBlank(pathPrefix)
                                ? relationshipName
                                : pathPrefix + '.' + relationshipName;
                            String newLabelPrefix = String.isBlank(labelPrefix)
                                ? fieldDescribe.getLabel()
                                : labelPrefix + ' → ' + fieldDescribe.getLabel();
                            
                            discoverFieldsRecursive(
                                refType,
                                newPathPrefix,
                                newLabelPrefix,
                                currentDepth + 1,
                                results,
                                visitedObjects
                            );
                        }
                    }
                }
            }
        }
    }
    
    /**
     * @description Check if an object should be traversed
     */
    private static final Set<String> NON_TRAVERSABLE_OBJECTS = new Set<String>{
        'RecordType', 'BusinessHours', 'Organization', 'Profile',
        'UserRole', 'Group', 'ProcessInstance'
    };

    private static Boolean isTraversableObject(String objectName) {
        return !NON_TRAVERSABLE_OBJECTS.contains(objectName);
    }
}