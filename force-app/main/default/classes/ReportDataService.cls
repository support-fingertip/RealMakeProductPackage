public with sharing class ReportDataService {

    private static final Pattern API_NAME_PATTERN = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]*(__[cre])?(\\.([a-zA-Z][a-zA-Z0-9_]*(__[cre])?))*$');

    @AuraEnabled
    public static ReportResult executeReport(String configJson, String filtersJson) {
        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            List<Object> filters = String.isNotBlank(filtersJson)
                ? (List<Object>) JSON.deserializeUntyped(filtersJson) : new List<Object>();

            List<Object> sections = (List<Object>) config.get('sections');
            if (sections == null || sections.isEmpty()) {
                throw new ReportException('No sections configured for this report.');
            }

            ReportResult result = new ReportResult();
            result.sections = new List<SectionResult>();

            for (Object secObj : sections) {
                Map<String, Object> section = (Map<String, Object>) secObj;
                String sectionType = (String) section.get('type');

                SectionResult secResult;
                if (sectionType == 'statusCount') {
                    secResult = executeStatusCountSection(section, filters);
                } else if (sectionType == 'childIteration') {
                    secResult = executeChildIterationSection(section, filters);
                } else if (sectionType == 'directFields') {
                    secResult = executeDirectFieldsSection(section, filters);
                } else if (sectionType == 'aggregation') {
                    secResult = executeAggregationSection(section, filters);
                } else if (sectionType == 'multiChild') {
                    secResult = executeMultiChildSection(section, filters);
                } else {
                    secResult = executeDirectFieldsSection(section, filters);
                }

                secResult.sectionId = (String) section.get('id');
                secResult.sectionTitle = (String) section.get('title');
                secResult.sectionType = sectionType;
                result.sections.add(secResult);
            }

            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error executing report: ' + e.getMessage());
        }
    }

    // ── Multi-Child Section (SFRB Model) ──
    // One parent object with multiple child objects shown side-by-side per row
    // Each child can be horizontal (side-by-side columns), aggregateOnly, or both
    private static SectionResult executeMultiChildSection(Map<String, Object> section, List<Object> filters) {
        String objectName = (String) section.get('object');
        validateApiName(objectName, 'object');

        SectionResult result = new SectionResult();
        result.columns = new List<ReportColumn>();
        result.rows = new List<Map<String, Object>>();

        // Parent columns
        List<String> parentFields = new List<String>();
        List<ReportColumn> parentCols = new List<ReportColumn>();
        List<Object> pFields = (List<Object>) section.get('parentColumns');
        if (pFields != null) {
            for (Object pf : pFields) {
                Map<String, Object> colConfig = (pf instanceof Map<String, Object>)
                    ? (Map<String, Object>) pf
                    : new Map<String, Object>{ 'field' => String.valueOf(pf) };
                String fieldName = (String) colConfig.get('field');
                validateApiName(fieldName, 'parent field');
                parentFields.add(fieldName);

                ReportColumn col = new ReportColumn();
                col.fieldName = fieldName;
                String customLabel = (String) colConfig.get('label');
                col.label = String.isNotBlank(customLabel) ? customLabel : getFieldLabel(objectName, fieldName);
                col.columnType = 'text';
                parentCols.add(col);
            }
        }
        if (parentFields.isEmpty()) {
            parentFields.add('Name');
            ReportColumn nameCol = new ReportColumn();
            nameCol.fieldName = 'Name';
            nameCol.label = 'Name';
            nameCol.columnType = 'text';
            parentCols.add(nameCol);
        }

        // Child objects configuration
        List<Object> childObjects = (List<Object>) section.get('childObjects');
        if (childObjects == null) childObjects = new List<Object>();

        // Build subqueries for each child (no LIMIT — fetch all)
        List<String> subqueries = new List<String>();
        List<ChildConfig> childConfigs = new List<ChildConfig>();

        for (Object cObj : childObjects) {
            if (!(cObj instanceof Map<String, Object>)) continue;
            Map<String, Object> child = (Map<String, Object>) cObj;
            ChildConfig cc = new ChildConfig();
            cc.objectApiName = (String) child.get('objectApiName');
            cc.relationshipName = (String) child.get('relationshipName');
            cc.displayLabel = (String) child.get('displayLabel');
            cc.displayMode = (String) child.get('displayMode');
            if (String.isBlank(cc.displayMode)) cc.displayMode = 'horizontal';

            cc.maxRecords = 0; // will be auto-detected

            // Child display columns
            cc.columns = new List<String>();
            List<Object> childCols = (List<Object>) child.get('columns');
            if (childCols != null) {
                for (Object colObj : childCols) {
                    if (colObj instanceof Map<String, Object>) {
                        cc.columns.add((String)((Map<String, Object>)colObj).get('field'));
                    } else {
                        cc.columns.add(String.valueOf(colObj));
                    }
                }
            }

            // Column labels map
            cc.columnLabels = new Map<String, String>();
            if (childCols != null) {
                for (Object colObj : childCols) {
                    if (colObj instanceof Map<String, Object>) {
                        Map<String, Object> colMap = (Map<String, Object>) colObj;
                        String fld = (String) colMap.get('field');
                        String lbl = (String) colMap.get('label');
                        if (String.isNotBlank(lbl)) cc.columnLabels.put(fld, lbl);
                    }
                }
            }

            // Aggregates
            cc.aggregates = new List<Map<String, Object>>();
            List<Object> aggs = (List<Object>) child.get('aggregates');
            if (aggs != null) {
                for (Object aggObj : aggs) {
                    if (!(aggObj instanceof Map<String, Object>)) continue;
                    cc.aggregates.add((Map<String, Object>) aggObj);
                }
            }

            // Child filters
            cc.filters = new List<Map<String, Object>>();
            List<Object> childFilters = (List<Object>) child.get('filters');
            if (childFilters != null) {
                for (Object fObj : childFilters) {
                    if (!(fObj instanceof Map<String, Object>)) continue;
                    cc.filters.add((Map<String, Object>) fObj);
                }
            }

            // Sort
            cc.sortField = (String) child.get('sortField');
            cc.sortDirection = (String) child.get('sortDirection');
            if (String.isBlank(cc.sortDirection)) cc.sortDirection = 'DESC';

            // Resolve lookup fields for child columns
            cc.lookupMap = resolveLookupFields(cc.objectApiName, cc.columns);

            childConfigs.add(cc);

            // Build subquery for horizontal/hybrid modes — NO LIMIT
            if (cc.displayMode == 'horizontal' || cc.displayMode == 'hybrid') {
                if (!cc.columns.isEmpty() && String.isNotBlank(cc.relationshipName)) {
                    Set<String> childSelectFields = new Set<String>();
                    for (String colField : cc.columns) {
                        validateApiName(colField, 'child column');
                        childSelectFields.add(colField);
                        // Also add the resolved relationship.Name for lookups
                        if (cc.lookupMap.containsKey(colField) && !colField.contains('.')) {
                            childSelectFields.add(cc.lookupMap.get(colField));
                        }
                    }
                    String subq = '(SELECT ' + String.join(new List<String>(childSelectFields), ', ')
                                + ' FROM ' + cc.relationshipName;
                    List<String> childConditions = new List<String>();
                    for (Map<String, Object> cf : cc.filters) {
                        String cond = buildStaticCondition(cf);
                        if (String.isNotBlank(cond)) childConditions.add(cond);
                    }
                    if (!childConditions.isEmpty()) {
                        subq += ' WHERE ' + String.join(childConditions, ' AND ');
                    }
                    if (String.isNotBlank(cc.sortField)) {
                        validateApiName(cc.sortField, 'child sort');
                        subq += ' ORDER BY ' + cc.sortField + ' ' + cc.sortDirection;
                    }
                    subq += ')';
                    subqueries.add(subq);
                }
            }
        }

        // Resolve lookup fields for parent columns (auto-add .Name for reference fields)
        Map<String, String> parentLookupMap = resolveLookupFields(objectName, parentFields);

        // Update parent column labels for lookups (show "Owner Name" not "Owner ID")
        Schema.SObjectType parentObjType = Schema.getGlobalDescribe().get(objectName);
        Map<String, Schema.SObjectField> parentFieldDescMap = parentObjType != null
            ? parentObjType.getDescribe().fields.getMap() : new Map<String, Schema.SObjectField>();
        for (ReportColumn pc : parentCols) {
            if (parentLookupMap.containsKey(pc.fieldName) && !pc.fieldName.contains('.')) {
                // Only update label if it wasn't custom-set by the user
                String defaultLabel = getFieldLabel(objectName, pc.fieldName);
                if (pc.label == defaultLabel) {
                    pc.label = defaultLabel.replace(' ID', '').replace(' Id', '') + ' Name';
                }
            } else if (pc.fieldName.contains('.')) {
                // Relationship traversal field — clean label
                if (pc.label == pc.fieldName) {
                    pc.label = pc.fieldName.replace('__r.', ' ').replace('.', ' ');
                }
            }
        }

        // Build parent query
        Set<String> parentFieldSet = new Set<String>{ 'Id' };
        for (String pf : parentFields) {
            if (pf.contains('.')) {
                // Already a relationship traversal — add directly
                parentFieldSet.add(pf);
            } else {
                parentFieldSet.add(pf);
                // Also add the resolved relationship.Name if it's a lookup
                if (parentLookupMap.containsKey(pf)) {
                    parentFieldSet.add(parentLookupMap.get(pf));
                }
            }
        }

        List<String> conditions = buildConditions(section, filters);

        String sortField = (String) section.get('sortField');
        String sortOrder = (String) section.get('sortOrder');
        if (String.isBlank(sortField)) sortField = 'CreatedDate';
        if (String.isBlank(sortOrder)) sortOrder = 'DESC';
        validateApiName(sortField, 'sort field');

        Integer recordLimit = 500;
        Object limitObj = section.get('recordLimit');
        if (limitObj != null) recordLimit = Integer.valueOf(String.valueOf(limitObj));

        String query = 'SELECT ' + String.join(new List<String>(parentFieldSet), ', ');
        for (String subq : subqueries) {
            query += ', ' + subq;
        }
        query += ' FROM ' + objectName;
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        query += ' ORDER BY ' + sortField + ' ' + sortOrder
               + ' LIMIT ' + recordLimit;

        List<SObject> records = Database.query(query);

        // Auto-detect max child count per relationship by scanning all records
        Map<String, Integer> maxChildCounts = new Map<String, Integer>();
        for (ChildConfig cc : childConfigs) {
            if (cc.displayMode == 'horizontal' || cc.displayMode == 'hybrid') {
                Integer maxCount = 0;
                for (SObject rec : records) {
                    List<SObject> children = rec.getSObjects(cc.relationshipName);
                    if (children != null && children.size() > maxCount) {
                        maxCount = children.size();
                    }
                }
                cc.maxRecords = maxCount;
                maxChildCounts.put(cc.relationshipName, maxCount);
            }
        }

        // Now build columns: parent first, then dynamic child columns
        result.columns.addAll(parentCols);

        for (ChildConfig cc : childConfigs) {
            if (cc.displayMode == 'horizontal' || cc.displayMode == 'hybrid') {
                if (!cc.columns.isEmpty() && cc.maxRecords > 0) {
                    String childLabel = String.isNotBlank(cc.displayLabel) ? cc.displayLabel : cc.objectApiName;
                    for (Integer i = 1; i <= cc.maxRecords; i++) {
                        for (String cf : cc.columns) {
                            ReportColumn col = new ReportColumn();
                            col.fieldName = cc.relationshipName + '_' + i + '_' + cf;
                            String baseLbl = cc.columnLabels.containsKey(cf)
                                ? cc.columnLabels.get(cf)
                                : getFieldLabel(cc.objectApiName, cf);
                            // If this child field is a lookup we auto-resolve, update label
                            if (cc.lookupMap != null && cc.lookupMap.containsKey(cf) && !cf.contains('.')
                                && !cc.columnLabels.containsKey(cf)) {
                                baseLbl = baseLbl.replace(' ID', '').replace(' Id', '') + ' Name';
                            }
                            // Clean label: "Label #1" instead of "ChildName 1: Label"
                            if (cc.maxRecords == 1) {
                                col.label = baseLbl;
                            } else {
                                col.label = baseLbl + ' #' + i;
                            }
                            col.columnType = 'text';
                            result.columns.add(col);
                        }
                    }
                }
            }

            // Aggregate columns
            if (cc.displayMode == 'aggregateOnly' || cc.displayMode == 'hybrid') {
                Integer aggIdx = 0;
                for (Map<String, Object> agg : cc.aggregates) {
                    ReportColumn col = new ReportColumn();
                    String aggLabel = (String) agg.get('label');
                    col.fieldName = cc.relationshipName + '_agg_' + aggIdx;
                    col.label = String.isNotBlank(aggLabel) ? aggLabel
                              : (String) agg.get('function') + '(' + (String) agg.get('fieldApiName') + ')';
                    col.columnType = 'number';
                    result.columns.add(col);
                    aggIdx++;
                }
            }
        }

        // Collect parent IDs for aggregate queries
        Set<Id> parentIds = new Set<Id>();
        for (SObject rec : records) {
            parentIds.add(rec.Id);
        }

        // Execute aggregate queries per child
        Map<String, Map<Id, List<Decimal>>> aggregateResults = new Map<String, Map<Id, List<Decimal>>>();
        for (ChildConfig cc : childConfigs) {
            if ((cc.displayMode == 'aggregateOnly' || cc.displayMode == 'hybrid') && !cc.aggregates.isEmpty()) {
                Map<Id, List<Decimal>> aggMap = executeChildAggregates(
                    cc.objectApiName, cc.relationshipName, parentIds, cc.aggregates, cc.filters, objectName
                );
                aggregateResults.put(cc.relationshipName, aggMap);
            }
        }

        // Build rows
        for (SObject rec : records) {
            Map<String, Object> row = new Map<String, Object>();

            // Parent fields (resolve lookups to Name)
            for (String pf : parentFields) {
                row.put(pf, readFieldValue(rec, pf, parentLookupMap));
            }

            // Child horizontal data
            for (ChildConfig cc : childConfigs) {
                if (cc.displayMode == 'horizontal' || cc.displayMode == 'hybrid') {
                    if (String.isNotBlank(cc.relationshipName) && !cc.columns.isEmpty()) {
                        List<SObject> children = rec.getSObjects(cc.relationshipName);
                        if (children != null) {
                            Integer childIdx = 1;
                            for (SObject child : children) {
                                for (String cf : cc.columns) {
                                    String val = readFieldValue(child, cf, cc.lookupMap);
                                    row.put(cc.relationshipName + '_' + childIdx + '_' + cf, val);
                                }
                                childIdx++;
                            }
                        }
                        // Fill empty slots for parents with fewer children
                        Integer actualCount = (children != null) ? children.size() : 0;
                        for (Integer i = actualCount + 1; i <= cc.maxRecords; i++) {
                            for (String cf : cc.columns) {
                                row.put(cc.relationshipName + '_' + i + '_' + cf, '');
                            }
                        }
                    }
                }

                // Aggregate values
                if (cc.displayMode == 'aggregateOnly' || cc.displayMode == 'hybrid') {
                    Map<Id, List<Decimal>> aggMap = aggregateResults.get(cc.relationshipName);
                    if (aggMap != null) {
                        List<Decimal> vals = aggMap.get(rec.Id);
                        Integer aggIdx = 0;
                        for (Map<String, Object> agg : cc.aggregates) {
                            Decimal aggVal = (vals != null && aggIdx < vals.size()) ? vals[aggIdx] : 0;
                            row.put(cc.relationshipName + '_agg_' + aggIdx, aggVal);
                            aggIdx++;
                        }
                    }
                }
            }

            result.rows.add(row);
        }

        result.totalRecords = records.size();
        return result;
    }

    // Execute aggregate queries for a child object grouped by parent ID
    private static Map<Id, List<Decimal>> executeChildAggregates(
        String childObjectName, String relationshipName, Set<Id> parentIds,
        List<Map<String, Object>> aggregates, List<Map<String, Object>> childFilters,
        String parentObjectName
    ) {
        Map<Id, List<Decimal>> resultMap = new Map<Id, List<Decimal>>();

        // Find the lookup field from child to parent
        String lookupField = findLookupField(childObjectName, parentObjectName);
        if (String.isBlank(lookupField)) return resultMap;

        // Build aggregate expressions
        List<String> aggExprs = new List<String>();
        Integer idx = 0;
        for (Map<String, Object> agg : aggregates) {
            String func = (String) agg.get('function');
            String field = (String) agg.get('fieldApiName');
            if (String.isBlank(func)) func = 'COUNT';
            if (String.isBlank(field)) field = 'Id';
            validateAggregation(func);
            validateApiName(field, 'aggregate field');

            aggExprs.add(func + '(' + field + ') agg' + idx);
            idx++;
        }

        // Build conditions
        List<String> conditions = new List<String>();
        conditions.add(lookupField + ' IN :parentIds');

        for (Map<String, Object> cf : childFilters) {
            String cond = buildStaticCondition(cf);
            if (String.isNotBlank(cond)) conditions.add(cond);
        }

        // Also add per-aggregate filters
        // Note: if individual aggregates have filters, we need separate queries
        // For simplicity, run one combined query first
        Boolean hasPerAggFilters = false;
        for (Map<String, Object> agg : aggregates) {
            Object aggFilterObj = agg.get('filterGroup');
            if (aggFilterObj instanceof Map<String, Object>) {
                hasPerAggFilters = true;
                break;
            }
        }

        if (!hasPerAggFilters) {
            // Single query for all aggregates
            validateApiName(childObjectName, 'child object');
            String query = 'SELECT ' + lookupField + ', ' + String.join(aggExprs, ', ')
                         + ' FROM ' + childObjectName
                         + ' WHERE ' + String.join(conditions, ' AND ')
                         + ' GROUP BY ' + lookupField;

            List<AggregateResult> aggResults = Database.query(query);
            for (AggregateResult ar : aggResults) {
                Id parentId = (Id) ar.get(lookupField);
                List<Decimal> vals = new List<Decimal>();
                for (Integer i = 0; i < aggregates.size(); i++) {
                    Object val = ar.get('agg' + i);
                    vals.add(val != null ? (Decimal) val : 0);
                }
                resultMap.put(parentId, vals);
            }
        } else {
            // Separate queries per aggregate with filters
            for (Integer i = 0; i < aggregates.size(); i++) {
                Map<String, Object> agg = aggregates[i];
                String func = (String) agg.get('function');
                String field = (String) agg.get('fieldApiName');
                if (String.isBlank(func)) func = 'COUNT';
                if (String.isBlank(field)) field = 'Id';

                List<String> aggConditions = new List<String>(conditions);

                // Per-aggregate filter
                Object aggFilterObj = agg.get('filterGroup');
                if (aggFilterObj instanceof Map<String, Object>) {
                    Map<String, Object> aggFilter = (Map<String, Object>) aggFilterObj;
                    String cond = buildStaticCondition(aggFilter);
                    if (String.isNotBlank(cond)) aggConditions.add(cond);
                }

                validateApiName(childObjectName, 'child object');
                String query = 'SELECT ' + lookupField + ', ' + func + '(' + field + ') aggVal'
                             + ' FROM ' + childObjectName
                             + ' WHERE ' + String.join(aggConditions, ' AND ')
                             + ' GROUP BY ' + lookupField;

                List<AggregateResult> aggResults = Database.query(query);
                for (AggregateResult ar : aggResults) {
                    Id parentId = (Id) ar.get(lookupField);
                    if (!resultMap.containsKey(parentId)) {
                        resultMap.put(parentId, new List<Decimal>());
                        for (Integer j = 0; j < aggregates.size(); j++) {
                            resultMap.get(parentId).add(0);
                        }
                    }
                    Decimal val = ar.get('aggVal') != null ? (Decimal) ar.get('aggVal') : 0;
                    resultMap.get(parentId)[i] = val;
                }
            }
        }

        return resultMap;
    }

    // Find the lookup field from child object back to parent
    private static String findLookupField(String childObjectName, String parentObjectName) {
        Schema.SObjectType childType = Schema.getGlobalDescribe().get(childObjectName);
        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(parentObjectName);
        if (childType == null || parentType == null) return null;

        for (Schema.SObjectField field : childType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fd = field.getDescribe();
            if (fd.getType() == Schema.DisplayType.REFERENCE) {
                for (Schema.SObjectType ref : fd.getReferenceTo()) {
                    if (ref == parentType) {
                        return fd.getName();
                    }
                }
            }
        }
        return null;
    }

    // ── Status Count Section ──
    private static SectionResult executeStatusCountSection(Map<String, Object> section, List<Object> filters) {
        String objectName = (String) section.get('object');
        String statusField = (String) section.get('statusField');
        String groupByField = (String) section.get('groupByField');

        validateApiName(objectName, 'object');
        validateApiName(statusField, 'status field');

        List<String> conditions = buildConditions(section, filters);

        SectionResult result = new SectionResult();
        result.columns = new List<ReportColumn>();
        result.rows = new List<Map<String, Object>>();

        if (String.isNotBlank(groupByField)) {
            validateApiName(groupByField, 'group by field');

            String query = 'SELECT ' + groupByField + ', ' + statusField + ', COUNT(Id) cnt'
                         + ' FROM ' + objectName;
            if (!conditions.isEmpty()) {
                query += ' WHERE ' + String.join(conditions, ' AND ');
            }
            query += ' GROUP BY ' + groupByField + ', ' + statusField
                   + ' ORDER BY ' + groupByField
                   + ' LIMIT 2000';

            List<AggregateResult> aggResults = Database.query(query);

            Set<String> statusValues = new Set<String>();
            Map<String, Map<String, Integer>> pivotData = new Map<String, Map<String, Integer>>();

            for (AggregateResult ar : aggResults) {
                String grpVal = String.valueOf(ar.get(groupByField));
                if (String.isBlank(grpVal)) grpVal = '(blank)';
                String statusVal = String.valueOf(ar.get(statusField));
                if (String.isBlank(statusVal)) statusVal = '(blank)';
                Integer cnt = (Integer) ar.get('cnt');

                statusValues.add(statusVal);

                if (!pivotData.containsKey(grpVal)) {
                    pivotData.put(grpVal, new Map<String, Integer>());
                }
                pivotData.get(grpVal).put(statusVal, cnt);
            }

            ReportColumn grpCol = new ReportColumn();
            grpCol.fieldName = groupByField;
            grpCol.label = getFieldLabel(objectName, groupByField);
            grpCol.columnType = 'text';
            result.columns.add(grpCol);

            List<String> sortedStatuses = new List<String>(statusValues);
            sortedStatuses.sort();
            for (String sv : sortedStatuses) {
                ReportColumn col = new ReportColumn();
                col.fieldName = 'status_' + sv.replaceAll('[^a-zA-Z0-9]', '_');
                col.label = sv;
                col.columnType = 'number';
                result.columns.add(col);
            }

            ReportColumn totalCol = new ReportColumn();
            totalCol.fieldName = 'total';
            totalCol.label = 'Total';
            totalCol.columnType = 'number';
            result.columns.add(totalCol);

            for (String grpVal : pivotData.keySet()) {
                Map<String, Object> row = new Map<String, Object>();
                row.put(groupByField, grpVal);
                Integer rowTotal = 0;
                for (String sv : sortedStatuses) {
                    String colKey = 'status_' + sv.replaceAll('[^a-zA-Z0-9]', '_');
                    Integer cnt = pivotData.get(grpVal).containsKey(sv) ? pivotData.get(grpVal).get(sv) : 0;
                    row.put(colKey, cnt);
                    rowTotal += cnt;
                }
                row.put('total', rowTotal);
                result.rows.add(row);
            }
        } else {
            String query = 'SELECT ' + statusField + ', COUNT(Id) cnt'
                         + ' FROM ' + objectName;
            if (!conditions.isEmpty()) {
                query += ' WHERE ' + String.join(conditions, ' AND ');
            }
            query += ' GROUP BY ' + statusField
                   + ' ORDER BY COUNT(Id) DESC'
                   + ' LIMIT 200';

            List<AggregateResult> aggResults = Database.query(query);

            ReportColumn statusCol = new ReportColumn();
            statusCol.fieldName = statusField;
            statusCol.label = getFieldLabel(objectName, statusField);
            statusCol.columnType = 'text';
            result.columns.add(statusCol);

            ReportColumn countCol = new ReportColumn();
            countCol.fieldName = 'count';
            countCol.label = 'Count';
            countCol.columnType = 'number';
            result.columns.add(countCol);

            for (AggregateResult ar : aggResults) {
                Map<String, Object> row = new Map<String, Object>();
                String statusVal = String.valueOf(ar.get(statusField));
                row.put(statusField, String.isNotBlank(statusVal) ? statusVal : '(blank)');
                row.put('count', (Integer) ar.get('cnt'));
                result.rows.add(row);
            }
        }

        result.totalRecords = result.rows.size();
        return result;
    }

    // ── Child Iteration Section ──
    private static SectionResult executeChildIterationSection(Map<String, Object> section, List<Object> filters) {
        String objectName = (String) section.get('object');
        String childRelationship = (String) section.get('childRelationship');
        String childObject = (String) section.get('childObject');

        validateApiName(objectName, 'object');

        SectionResult result = new SectionResult();
        result.columns = new List<ReportColumn>();
        result.rows = new List<Map<String, Object>>();

        List<String> parentFields = new List<String>();
        List<Object> pFields = (List<Object>) section.get('parentFields');
        if (pFields != null) {
            for (Object pf : pFields) {
                String fieldName = String.valueOf(pf);
                validateApiName(fieldName, 'parent field');
                parentFields.add(fieldName);
            }
        }
        if (parentFields.isEmpty()) parentFields.add('Name');

        List<String> childFields = new List<String>();
        List<Object> cFields = (List<Object>) section.get('childFields');
        if (cFields != null) {
            for (Object cf : cFields) {
                String fieldName = String.valueOf(cf);
                validateApiName(fieldName, 'child field');
                childFields.add(fieldName);
            }
        }

        Integer maxChildren = 10;
        Object maxChildObj = section.get('maxChildren');
        if (maxChildObj != null) maxChildren = Integer.valueOf(String.valueOf(maxChildObj));

        for (String pf : parentFields) {
            ReportColumn col = new ReportColumn();
            col.fieldName = pf;
            col.label = getFieldLabel(objectName, pf);
            col.columnType = 'text';
            result.columns.add(col);
        }

        String childObjForLabel = String.isNotBlank(childObject) ? childObject : objectName;
        for (Integer i = 1; i <= maxChildren; i++) {
            for (String cf : childFields) {
                ReportColumn col = new ReportColumn();
                col.fieldName = 'child_' + i + '_' + cf;
                col.label = getFieldLabel(childObjForLabel, cf) + ' #' + i;
                col.columnType = 'text';
                result.columns.add(col);
            }
        }

        Set<String> parentFieldSet = new Set<String>{ 'Id' };
        parentFieldSet.addAll(parentFields);

        String childSubquery = '';
        if (String.isNotBlank(childRelationship) && !childFields.isEmpty()) {
            childSubquery = ', (SELECT ' + String.join(childFields, ', ')
                          + ' FROM ' + childRelationship
                          + ' LIMIT ' + maxChildren + ')';
        }

        List<String> conditions = buildConditions(section, filters);

        String query = 'SELECT ' + String.join(new List<String>(parentFieldSet), ', ')
                     + childSubquery + ' FROM ' + objectName;
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        query += ' ORDER BY CreatedDate DESC LIMIT 500';

        List<SObject> records = Database.query(query);

        for (SObject rec : records) {
            Map<String, Object> row = new Map<String, Object>();
            for (String pf : parentFields) {
                Object val = rec.get(pf);
                row.put(pf, val != null ? String.valueOf(val) : '');
            }
            if (String.isNotBlank(childRelationship)) {
                List<SObject> children = rec.getSObjects(childRelationship);
                if (children != null) {
                    Integer childIdx = 1;
                    for (SObject child : children) {
                        if (childIdx > maxChildren) break;
                        for (String cf : childFields) {
                            Object val = child.get(cf);
                            row.put('child_' + childIdx + '_' + cf, val != null ? String.valueOf(val) : '');
                        }
                        childIdx++;
                    }
                }
            }
            result.rows.add(row);
        }

        result.totalRecords = records.size();
        return result;
    }

    // ── Direct Fields Section ──
    private static SectionResult executeDirectFieldsSection(Map<String, Object> section, List<Object> filters) {
        String objectName = (String) section.get('object');
        validateApiName(objectName, 'object');

        List<String> fieldNames = new List<String>();
        List<Object> fList = (List<Object>) section.get('fields');
        if (fList != null) {
            for (Object f : fList) {
                String fieldName = String.valueOf(f);
                validateApiName(fieldName, 'field');
                fieldNames.add(fieldName);
            }
        }
        if (fieldNames.isEmpty()) fieldNames.add('Name');

        // Resolve lookup fields to auto-show Name
        Map<String, String> lookupMap = resolveLookupFields(objectName, fieldNames);

        Set<String> fieldSet = new Set<String>{ 'Id' };
        for (String fn : fieldNames) {
            fieldSet.add(fn);
            // Also add the resolved relationship.Name for lookups
            if (lookupMap.containsKey(fn) && !fn.contains('.')) {
                fieldSet.add(lookupMap.get(fn));
            }
        }

        List<String> conditions = buildConditions(section, filters);

        String sortField = (String) section.get('sortField');
        String sortOrder = (String) section.get('sortOrder');
        if (String.isBlank(sortField)) sortField = 'CreatedDate';
        if (String.isBlank(sortOrder)) sortOrder = 'DESC';
        validateApiName(sortField, 'sort field');

        Integer recordLimit = 2000;
        Object limitObj = section.get('recordLimit');
        if (limitObj != null) recordLimit = Integer.valueOf(String.valueOf(limitObj));

        String query = 'SELECT ' + String.join(new List<String>(fieldSet), ', ')
                     + ' FROM ' + objectName;
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        query += ' ORDER BY ' + sortField + ' ' + sortOrder + ' LIMIT ' + recordLimit;

        List<SObject> records = Database.query(query);

        SectionResult result = new SectionResult();
        result.columns = new List<ReportColumn>();
        result.rows = new List<Map<String, Object>>();

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        Map<String, Schema.SObjectField> fieldDescMap = objType.getDescribe().fields.getMap();

        for (String fn : fieldNames) {
            ReportColumn col = new ReportColumn();
            col.fieldName = fn;
            col.label = fn;
            if (fn.contains('.')) {
                // Relationship traversal field — use clean label
                col.label = fn.replace('__r.', ' ').replace('.', ' ');
                col.columnType = 'text';
            } else if (fieldDescMap.containsKey(fn.toLowerCase())) {
                Schema.DescribeFieldResult fd = fieldDescMap.get(fn.toLowerCase()).getDescribe();
                // If it's a lookup that we auto-resolve, show the relationship label
                if (lookupMap.containsKey(fn)) {
                    col.label = fd.getLabel().replace(' ID', '').replace(' Id', '') + ' Name';
                } else {
                    col.label = fd.getLabel();
                }
                col.columnType = String.valueOf(fd.getType()).toLowerCase();
            }
            result.columns.add(col);
        }

        for (SObject rec : records) {
            Map<String, Object> row = new Map<String, Object>();
            for (String fn : fieldNames) {
                row.put(fn, readFieldValue(rec, fn, lookupMap));
            }
            result.rows.add(row);
        }

        result.totalRecords = records.size();
        return result;
    }

    // ── Aggregation Section ──
    private static SectionResult executeAggregationSection(Map<String, Object> section, List<Object> filters) {
        String objectName = (String) section.get('object');
        String groupByField = (String) section.get('groupByField');

        validateApiName(objectName, 'object');
        validateApiName(groupByField, 'group by field');

        SectionResult result = new SectionResult();
        result.columns = new List<ReportColumn>();
        result.rows = new List<Map<String, Object>>();

        List<String> aggExpressions = new List<String>();
        List<Object> metricsArray = (List<Object>) section.get('metrics');
        List<Map<String, Object>> metricConfigs = new List<Map<String, Object>>();

        if (metricsArray != null) {
            Integer idx = 0;
            for (Object mObj : metricsArray) {
                if (!(mObj instanceof Map<String, Object>)) continue;
                Map<String, Object> metric = (Map<String, Object>) mObj;
                String mAgg = (String) metric.get('aggregation');
                String mField = (String) metric.get('field');
                if (String.isNotBlank(mAgg) && String.isNotBlank(mField)) {
                    validateAggregation(mAgg);
                    validateApiName(mField, 'metric field');
                    aggExpressions.add(mAgg + '(' + mField + ') metric' + idx);
                    metricConfigs.add(metric);
                    idx++;
                }
            }
        }

        if (aggExpressions.isEmpty()) {
            aggExpressions.add('COUNT(Id) metric0');
            Map<String, Object> defaultMetric = new Map<String, Object>();
            defaultMetric.put('label', 'Count');
            defaultMetric.put('aggregation', 'COUNT');
            defaultMetric.put('field', 'Id');
            metricConfigs.add(defaultMetric);
        }

        List<String> conditions = buildConditions(section, filters);

        String query = 'SELECT ' + groupByField + ', ' + String.join(aggExpressions, ', ')
                     + ' FROM ' + objectName;
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        query += ' GROUP BY ' + groupByField + ' ORDER BY ' + groupByField + ' LIMIT 200';

        List<AggregateResult> aggResults = Database.query(query);

        ReportColumn grpCol = new ReportColumn();
        grpCol.fieldName = groupByField;
        grpCol.label = getFieldLabel(objectName, groupByField);
        grpCol.columnType = 'text';
        result.columns.add(grpCol);

        for (Integer i = 0; i < metricConfigs.size(); i++) {
            Map<String, Object> mc = metricConfigs[i];
            ReportColumn col = new ReportColumn();
            col.fieldName = 'metric' + i;
            String metricLabel = (String) mc.get('label');
            col.label = String.isNotBlank(metricLabel) ? metricLabel
                      : (String) mc.get('aggregation') + '(' + (String) mc.get('field') + ')';
            col.columnType = 'number';
            result.columns.add(col);
        }

        for (AggregateResult ar : aggResults) {
            Map<String, Object> row = new Map<String, Object>();
            String grpVal = String.valueOf(ar.get(groupByField));
            row.put(groupByField, String.isNotBlank(grpVal) ? grpVal : '(blank)');
            for (Integer i = 0; i < metricConfigs.size(); i++) {
                Object val = ar.get('metric' + i);
                row.put('metric' + i, val != null ? val : 0);
            }
            result.rows.add(row);
        }

        result.totalRecords = result.rows.size();
        return result;
    }

    // ── Shared Utilities ──

    private static List<String> buildConditions(Map<String, Object> section, List<Object> filters) {
        List<String> conditions = new List<String>();

        List<Object> staticFilters = (List<Object>) section.get('filters');
        if (staticFilters != null) {
            for (Object sf : staticFilters) {
                if (!(sf instanceof Map<String, Object>)) continue;
                Map<String, Object> filter = (Map<String, Object>) sf;
                String cond = buildStaticCondition(filter);
                if (String.isNotBlank(cond)) conditions.add(cond);
            }
        }

        for (Object af : filters) {
            if (!(af instanceof Map<String, Object>)) continue;
            Map<String, Object> filter = (Map<String, Object>) af;
            String filterField = (String) filter.get('field');
            String filterType = (String) filter.get('type');
            Object filterValue = filter.get('value');
            String filterObject = (String) filter.get('object');

            String sectionObject = (String) section.get('object');
            if (String.isNotBlank(filterObject) && filterObject != sectionObject) continue;

            if (filterValue == null || String.valueOf(filterValue) == '') continue;
            if (String.isNotBlank(filterField)) validateApiName(filterField, 'filter field');

            if (filterType == 'dateRange') {
                if (!(filterValue instanceof Map<String, Object>)) continue;
                Map<String, Object> dateRange = (Map<String, Object>) filterValue;
                String startDate = (String) dateRange.get('start');
                String endDate = (String) dateRange.get('end');
                if (String.isNotBlank(startDate)) conditions.add(filterField + ' >= ' + startDate);
                if (String.isNotBlank(endDate)) conditions.add(filterField + ' <= ' + endDate);
            } else if (filterType == 'dateLiteral') {
                String literal = String.valueOf(filterValue);
                if (isValidDateLiteral(literal)) conditions.add(filterField + ' = ' + literal);
            } else if (filterType == 'picklist' || filterType == 'text') {
                conditions.add(filterField + ' = \'' + String.escapeSingleQuotes(String.valueOf(filterValue)) + '\'');
            } else if (filterType == 'number') {
                String operator = (String) filter.get('operator');
                if (String.isBlank(operator)) operator = '=';
                conditions.add(filterField + ' ' + getOperatorSymbol(operator) + ' ' + String.valueOf(filterValue));
            }
        }

        return conditions;
    }

    private static String buildStaticCondition(Map<String, Object> filter) {
        String field = (String) filter.get('field');
        String operator = (String) filter.get('operator');
        String value = (String) filter.get('value');

        if (String.isBlank(field) || String.isBlank(value)) return null;
        validateApiName(field, 'static filter field');

        if (isValidDateLiteral(value)) {
            return field + ' ' + getOperatorSymbol(operator) + ' ' + value;
        }

        String escapedValue = String.escapeSingleQuotes(value);

        if (operator == 'contains') return field + ' LIKE \'%' + escapedValue + '%\'';
        if (operator == 'notContains') return '(NOT ' + field + ' LIKE \'%' + escapedValue + '%\')';

        return field + ' ' + getOperatorSymbol(operator) + ' \'' + escapedValue + '\'';
    }

    private static String getOperatorSymbol(String operator) {
        if (operator == 'equals' || operator == '=') return '=';
        if (operator == 'notEquals' || operator == '!=') return '!=';
        if (operator == 'greaterThan' || operator == '>') return '>';
        if (operator == 'lessThan' || operator == '<') return '<';
        if (operator == 'greaterOrEqual' || operator == '>=') return '>=';
        if (operator == 'lessOrEqual' || operator == '<=') return '<=';
        return '=';
    }

    // Resolve lookup fields: returns a map of fieldApiName -> RelationshipName.Name
    // Also detects fields already in dot notation (e.g., Owner.Name) and passes them through
    private static Map<String, String> resolveLookupFields(String objectName, List<String> fields) {
        Map<String, String> lookupMap = new Map<String, String>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) return lookupMap;

        Map<String, Schema.SObjectField> fieldDescMap = objType.getDescribe().fields.getMap();

        for (String field : fields) {
            // If field already contains a dot (e.g., Owner.Name, Project__r.Name), it's already a traversal
            if (field.contains('.')) {
                lookupMap.put(field, field);
                continue;
            }
            // Check if it's a reference field
            if (fieldDescMap.containsKey(field.toLowerCase())) {
                Schema.DescribeFieldResult fd = fieldDescMap.get(field.toLowerCase()).getDescribe();
                if (fd.getType() == Schema.DisplayType.REFERENCE) {
                    String relName = fd.getRelationshipName();
                    if (relName != null) {
                        // Check if referenced object has a Name field
                        List<Schema.SObjectType> refs = fd.getReferenceTo();
                        if (!refs.isEmpty()) {
                            Map<String, Schema.SObjectField> refFields = refs[0].getDescribe().fields.getMap();
                            if (refFields.containsKey('name')) {
                                lookupMap.put(field, relName + '.Name');
                            }
                        }
                    }
                }
            }
        }
        return lookupMap;
    }

    // Read a field value from an SObject, handling dot-notation relationship traversal
    private static String readFieldValue(SObject rec, String fieldName, Map<String, String> lookupMap) {
        // If this field has a lookup resolution
        if (lookupMap != null && lookupMap.containsKey(fieldName)) {
            String relPath = lookupMap.get(fieldName);
            // Handle dot notation: e.g., Owner.Name or Project__r.Name
            List<String> parts = relPath.split('\\.');
            SObject current = rec;
            for (Integer i = 0; i < parts.size() - 1; i++) {
                if (current == null) return '';
                current = current.getSObject(parts[i]);
            }
            if (current == null) return '';
            Object val = current.get(parts[parts.size() - 1]);
            return val != null ? String.valueOf(val) : '';
        }
        // If the fieldName itself contains a dot (already a traversal field)
        if (fieldName.contains('.')) {
            List<String> parts = fieldName.split('\\.');
            SObject current = rec;
            for (Integer i = 0; i < parts.size() - 1; i++) {
                if (current == null) return '';
                current = current.getSObject(parts[i]);
            }
            if (current == null) return '';
            Object val = current.get(parts[parts.size() - 1]);
            return val != null ? String.valueOf(val) : '';
        }
        Object val = rec.get(fieldName);
        return val != null ? String.valueOf(val) : '';
    }

    private static String getFieldLabel(String objectName, String fieldName) {
        try {
            // Handle dot-notation fields like Owner.Name, Project__r.Name
            if (fieldName.contains('.')) {
                return fieldName.replace('__r.', ' ').replace('.', ' ');
            }
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            if (objType != null) {
                Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
                if (fieldMap.containsKey(fieldName.toLowerCase())) {
                    return fieldMap.get(fieldName.toLowerCase()).getDescribe().getLabel();
                }
            }
        } catch (Exception e) { /* fall through */ }
        return fieldName;
    }

    private static void validateApiName(String name, String context) {
        if (String.isBlank(name) || !API_NAME_PATTERN.matcher(name).matches()) {
            throw new AuraHandledException('Invalid API name for ' + context + ': ' + name);
        }
    }

    private static void validateAggregation(String agg) {
        Set<String> validAggs = new Set<String>{ 'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COUNT_DISTINCT' };
        if (!validAggs.contains(agg.toUpperCase())) {
            throw new AuraHandledException('Invalid aggregation: ' + agg);
        }
    }

    private static Boolean isValidDateLiteral(String value) {
        if (String.isBlank(value)) return false;
        Set<String> literals = new Set<String>{
            'TODAY', 'YESTERDAY', 'TOMORROW', 'THIS_WEEK', 'LAST_WEEK', 'NEXT_WEEK',
            'THIS_MONTH', 'LAST_MONTH', 'NEXT_MONTH', 'THIS_QUARTER', 'LAST_QUARTER',
            'NEXT_QUARTER', 'THIS_YEAR', 'LAST_YEAR', 'NEXT_YEAR', 'THIS_FISCAL_QUARTER',
            'LAST_FISCAL_QUARTER', 'THIS_FISCAL_YEAR', 'LAST_FISCAL_YEAR'
        };
        if (literals.contains(value.toUpperCase())) return true;
        return Pattern.matches('LAST_N_DAYS:\\d+', value) ||
               Pattern.matches('NEXT_N_DAYS:\\d+', value) ||
               Pattern.matches('LAST_N_MONTHS:\\d+', value) ||
               Pattern.matches('LAST_N_YEARS:\\d+', value);
    }

    // ── Inner Classes ──

    private class ChildConfig {
        String objectApiName;
        String relationshipName;
        String displayLabel;
        String displayMode;
        Integer maxRecords;
        List<String> columns;
        Map<String, String> columnLabels;
        Map<String, String> lookupMap;
        List<Map<String, Object>> aggregates;
        List<Map<String, Object>> filters;
        String sortField;
        String sortDirection;
    }

    // ── Result Classes ──

    public class ReportResult {
        @AuraEnabled public List<SectionResult> sections;
    }

    public class SectionResult {
        @AuraEnabled public String sectionId;
        @AuraEnabled public String sectionTitle;
        @AuraEnabled public String sectionType;
        @AuraEnabled public List<ReportColumn> columns;
        @AuraEnabled public List<Map<String, Object>> rows;
        @AuraEnabled public Integer totalRecords;
    }

    public class ReportColumn {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String label;
        @AuraEnabled public String columnType;
    }

    public class ReportException extends Exception {}
}