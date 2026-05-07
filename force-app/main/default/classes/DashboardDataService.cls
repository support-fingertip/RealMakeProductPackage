public with sharing class DashboardDataService {

    private static final Pattern API_NAME_PATTERN = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)?(__[cre])?$');
    private static final String FIELD_ID = 'Id';
    private static final String FIELD_NAME = 'Name';
    private static final String BLANK_GROUP_LABEL = '(blank)';
    private static final String FILTER_ALL = 'all';

    private static Set<String> MULTI_METRIC_TYPES {
        get {
            if (MULTI_METRIC_TYPES == null) {
                MULTI_METRIC_TYPES = new Set<String>{
                    'progressBar', 'rankedList', 'metricCards', 'rankedTable',
                    'achievementCard', 'targetProgress', 'statusCard'
                };
            }
            return MULTI_METRIC_TYPES;
        }
        set;
    }

    // @AuraEnabled wrapper — thin shell that delegates to the internal method
    @AuraEnabled
    public static ComponentResult getComponentData(String componentJson, String activeFiltersJson) {
        try {
            Map<String, Object> comp = (Map<String, Object>) JSON.deserializeUntyped(componentJson);
            List<Object> activeFilters = String.isNotBlank(activeFiltersJson)
                ? (List<Object>) JSON.deserializeUntyped(activeFiltersJson) : new List<Object>();
            return executeComponentQuery(comp, activeFilters);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching data: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<ComponentResult> getDashboardData(String configId, String activeFiltersJson) {
        try {
            Dashboard_Configuration__c config = [
                SELECT Configuration_JSON__c FROM Dashboard_Configuration__c
                WHERE Id = :configId LIMIT 1
            ];

            Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(config.Configuration_JSON__c);
            List<Object> components = (List<Object>) configMap.get('components');
            List<Object> activeFilters = String.isNotBlank(activeFiltersJson)
                ? (List<Object>) JSON.deserializeUntyped(activeFiltersJson) : new List<Object>();

            List<ComponentResult> results = new List<ComponentResult>();
            for (Object compObj : components) {
                if (!(compObj instanceof Map<String, Object>)) continue;
                Map<String, Object> comp = (Map<String, Object>) compObj;
                String compId = (String) comp.get('id');

                // Figure out which filters apply to this component
                List<Object> applicableFilters = getApplicableFilters(compId, activeFilters, configMap);

                try {
                    String compType = (String) comp.get('type');
                    ComponentResult cr;
                    if (MULTI_METRIC_TYPES.contains(compType)) {
                        // Call internal method directly (not the @AuraEnabled wrapper)
                        // so we get real error messages instead of "Script-thrown exception"
                        MultiMetricComponentResult mmResult = executeMultiAggregation(comp, applicableFilters);
                        cr = new ComponentResult();
                        cr.multiMetricData = mmResult.items;
                        cr.chartData = new List<ChartDataPoint>();
                        cr.value = 0;
                    } else {
                        cr = executeComponentQuery(comp, applicableFilters);
                    }
                    cr.componentId = compId;
                    results.add(cr);
                } catch (Exception e) {
                    ComponentResult errResult = new ComponentResult();
                    errResult.componentId = compId;
                    errResult.value = 0;
                    errResult.chartData = new List<ChartDataPoint>();
                    errResult.errorMessage = e.getMessage();
                    results.add(errResult);
                }
            }
            return results;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching dashboard data: ' + e.getMessage());
        }
    }

    private static List<Object> getApplicableFilters(String componentId, List<Object> activeFilters,
                                                       Map<String, Object> configMap) {
        List<Object> filterConfigs = (List<Object>) configMap.get('filters');
        if (filterConfigs == null) return activeFilters;

        // Build a map of filter id -> applies to
        Map<String, Object> filterAppliesMap = new Map<String, Object>();
        for (Object fc : filterConfigs) {
            if (!(fc instanceof Map<String, Object>)) continue;
            Map<String, Object> fcMap = (Map<String, Object>) fc;
            filterAppliesMap.put((String) fcMap.get('id'), fcMap.get('appliesTo'));
        }

        List<Object> applicable = new List<Object>();
        for (Object af : activeFilters) {
            if (!(af instanceof Map<String, Object>)) continue;
            Map<String, Object> afMap = (Map<String, Object>) af;
            String filterId = (String) afMap.get('filterId');
            Object appliesTo = filterAppliesMap.get(filterId);

            if (appliesTo == null || appliesTo == FILTER_ALL || String.valueOf(appliesTo) == FILTER_ALL) {
                applicable.add(af);
            } else if (appliesTo instanceof List<Object>) {
                List<Object> compIds = (List<Object>) appliesTo;
                for (Object cId : compIds) {
                    if (String.valueOf(cId) == componentId) {
                        applicable.add(af);
                        break;
                    }
                }
            }
        }
        return applicable;
    }

    @AuraEnabled
    public static ReportResult getReportData(String componentJson, String activeFiltersJson) {
        try {
            Map<String, Object> comp = (Map<String, Object>) JSON.deserializeUntyped(componentJson);
            List<Object> activeFilters = String.isNotBlank(activeFiltersJson)
                ? (List<Object>) JSON.deserializeUntyped(activeFiltersJson) : new List<Object>();

            String objectName = (String) comp.get('object');
            validateApiName(objectName, 'object');

            // Determine which fields to query
            List<String> reportFields = new List<String>();
            List<Object> rfList = (List<Object>) comp.get('reportFields');
            if (rfList != null) {
                for (Object rf : rfList) {
                    String fieldName = String.valueOf(rf);
                    validateApiName(fieldName, 'report field');
                    reportFields.add(fieldName);
                }
            }

            // If no report fields configured, fall back to Name + aggregation field + groupBy
            if (reportFields.isEmpty()) {
                reportFields.add(FIELD_NAME);
                String aggField = (String) comp.get('field');
                if (String.isNotBlank(aggField) && aggField != FIELD_ID && aggField != FIELD_NAME) {
                    reportFields.add(aggField);
                }
                String grpField = (String) comp.get('groupByField');
                if (String.isNotBlank(grpField) && !reportFields.contains(grpField)) {
                    reportFields.add(grpField);
                }
            }

            // Always include Id
            Set<String> fieldSet = new Set<String>{ FIELD_ID };
            fieldSet.addAll(reportFields);

            List<String> conditions = buildConditions(comp, activeFilters);

            String query = 'SELECT ' + String.join(new List<String>(fieldSet), ', ');
            query += ' FROM ' + objectName;
            if (!conditions.isEmpty()) {
                query += ' WHERE ' + String.join(conditions, ' AND ');
            }
            query += ' ORDER BY CreatedDate DESC LIMIT 2000';

            List<SObject> records = Database.query(query);

            // Build field labels from describe
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            Map<String, Schema.SObjectField> fieldDescMap = objType.getDescribe().fields.getMap();

            ReportResult result = new ReportResult();
            result.columns = new List<ReportColumn>();
            result.rows = new List<Map<String, String>>();

            for (String fn : reportFields) {
                ReportColumn col = new ReportColumn();
                col.fieldName = fn;
                col.label = fn;
                if (fieldDescMap.containsKey(fn.toLowerCase())) {
                    col.label = fieldDescMap.get(fn.toLowerCase()).getDescribe().getLabel();
                }
                result.columns.add(col);
            }

            for (SObject rec : records) {
                Map<String, String> row = new Map<String, String>();
                for (String fn : reportFields) {
                    Object val = rec.get(fn);
                    row.put(fn, val != null ? String.valueOf(val) : '');
                }
                result.rows.add(row);
            }

            result.totalRecords = records.size();
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching report data: ' + e.getMessage());
        }
    }

    private static String buildQuery(String compType, String objectName, String aggregation,
                                      String field, String groupByField, List<String> conditions) {
        return buildQuery(compType, objectName, aggregation, field, groupByField, conditions, null);
    }

    private static String buildQuery(String compType, String objectName, String aggregation,
                                      String field, String groupByField, List<String> conditions,
                                      Integer maxGroups) {
        String query = 'SELECT ';

        if (compType == 'kpi') {
            query += aggregation + '(' + field + ') val';
        } else {
            query += groupByField + ', ' + aggregation + '(' + field + ') val';
        }

        query += ' FROM ' + objectName;

        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }

        if (compType != 'kpi' && String.isNotBlank(groupByField)) {
            query += ' GROUP BY ' + groupByField;
            query += ' ORDER BY ' + aggregation + '(' + field + ') DESC';
            Integer limitVal = (maxGroups != null && maxGroups > 0) ? maxGroups : 20;
            query += ' LIMIT ' + limitVal;
        }

        return query;
    }

    private static List<String> buildConditions(Map<String, Object> comp, List<Object> activeFilters) {
        List<String> conditions = new List<String>();

        // Static filters from component config
        List<Object> staticFilters = (List<Object>) comp.get('staticFilters');
        if (staticFilters != null) {
            for (Object sf : staticFilters) {
                if (!(sf instanceof Map<String, Object>)) continue;
                Map<String, Object> filter = (Map<String, Object>) sf;
                String cond = buildStaticCondition(filter);
                if (String.isNotBlank(cond)) conditions.add(cond);
            }
        }

        // Active user-applied filters
        for (Object af : activeFilters) {
            if (!(af instanceof Map<String, Object>)) continue;
            Map<String, Object> filter = (Map<String, Object>) af;
            String filterField = (String) filter.get('field');
            String filterType = (String) filter.get('type');
            Object filterValue = filter.get('value');

            if (filterValue == null || String.valueOf(filterValue) == '') continue;
            if (String.isNotBlank(filterField)) validateApiName(filterField, 'filter field');

            if (filterType == 'dateRange') {
                if (!(filterValue instanceof Map<String, Object>)) continue;
                Map<String, Object> dateRange = (Map<String, Object>) filterValue;
                String startDate = (String) dateRange.get('start');
                String endDate = (String) dateRange.get('end');
                if (String.isNotBlank(startDate)) {
                    conditions.add(filterField + ' >= ' + startDate);
                }
                if (String.isNotBlank(endDate)) {
                    conditions.add(filterField + ' <= ' + endDate);
                }
            } else if (filterType == 'dateLiteral') {
                String literal = String.valueOf(filterValue);
                if (isValidDateLiteral(literal)) {
                    conditions.add(filterField + ' = ' + literal);
                }
            } else if (filterType == 'picklist' || filterType == 'text') {
                conditions.add(filterField + ' = \'' + String.escapeSingleQuotes(String.valueOf(filterValue)) + '\'');
            } else if (filterType == 'currentUser') {
                conditions.add(filterField + ' = \'' + UserInfo.getUserId() + '\'');
            } else if (filterType == 'userHierarchy') {
                Set<Id> subordinateIds = getSubordinateUserIds();
                if (!subordinateIds.isEmpty()) {
                    List<String> idStrings = new List<String>();
                    for (Id subId : subordinateIds) {
                        idStrings.add('\'' + subId + '\'');
                    }
                    conditions.add(filterField + ' IN (' + String.join(idStrings, ',') + ')');
                }
            } else if (filterType == 'lookup') {
                conditions.add(filterField + ' = \'' + String.escapeSingleQuotes(String.valueOf(filterValue)) + '\'');
            } else if (filterType == 'hierarchy') {
                String selectedUserId = String.valueOf(filterValue);
                String hierarchyMode = filter.get('hierarchyMode') != null ? String.valueOf(filter.get('hierarchyMode')) : 'role';
                Set<Id> hierarchyIds;
                if (hierarchyMode == 'manager') {
                    hierarchyIds = DashboardConfigController.getAllManagerSubordinateIds(selectedUserId);
                } else {
                    hierarchyIds = DashboardConfigController.getAllSubordinateUserIds(selectedUserId);
                }
                if (!hierarchyIds.isEmpty()) {
                    List<String> idStrings = new List<String>();
                    for (Id uid : hierarchyIds) {
                        idStrings.add('\'' + uid + '\'');
                    }
                    conditions.add(filterField + ' IN (' + String.join(idStrings, ',') + ')');
                }
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

        if (operator == 'contains') {
            return field + ' LIKE \'%' + escapedValue + '%\'';
        } else if (operator == 'notContains') {
            return '(NOT ' + field + ' LIKE \'%' + escapedValue + '%\')';
        }

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

    private static Set<Id> getSubordinateUserIds() {
        Set<Id> userIds = new Set<Id>();
        userIds.add(UserInfo.getUserId());

        User currentUser = [SELECT UserRoleId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (currentUser.UserRoleId == null) return userIds;

        Set<Id> roleIds = new Set<Id>{ currentUser.UserRoleId };
        Set<Id> processedRoleIds = new Set<Id>();

        // Walk down the role hierarchy (up to 5 levels)
        for (Integer i = 0; i < 5; i++) {
            Set<Id> childRoleIds = new Set<Id>();
            for (UserRole r : [SELECT Id FROM UserRole WHERE ParentRoleId IN :roleIds AND Id NOT IN :processedRoleIds]) {
                childRoleIds.add(r.Id);
            }
            if (childRoleIds.isEmpty()) break;
            processedRoleIds.addAll(roleIds);
            roleIds = childRoleIds;
        }

        roleIds.addAll(processedRoleIds);
        for (User u : [SELECT Id FROM User WHERE UserRoleId IN :roleIds AND IsActive = true]) {
            userIds.add(u.Id);
        }

        return userIds;
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

    // Internal validation methods that throw regular exceptions (not AuraHandledException)
    // so that getDashboardData's catch block can read .getMessage() properly
    private static void validateApiNameInternal(String name, String context) {
        if (String.isBlank(name) || !API_NAME_PATTERN.matcher(name).matches()) {
            throw new DashboardDataException('Invalid API name for ' + context + ': ' + name);
        }
    }

    private static void validateAggregationInternal(String agg) {
        Set<String> validAggs = new Set<String>{ 'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COUNT_DISTINCT' };
        if (!validAggs.contains(agg.toUpperCase())) {
            throw new DashboardDataException('Invalid aggregation: ' + agg);
        }
    }

    // ── Multi-Aggregation Data for New Widget Types ──

    // @AuraEnabled wrapper — thin shell that delegates to the internal method
    @AuraEnabled
    public static MultiMetricComponentResult getMultiAggregationData(String componentJson, String activeFiltersJson) {
        try {
            Map<String, Object> comp = (Map<String, Object>) JSON.deserializeUntyped(componentJson);
            List<Object> activeFilters = String.isNotBlank(activeFiltersJson)
                ? (List<Object>) JSON.deserializeUntyped(activeFiltersJson) : new List<Object>();
            return executeMultiAggregation(comp, activeFilters);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Internal methods called by getDashboardData (throw regular exceptions) ──

    private static MultiMetricComponentResult executeMultiAggregation(Map<String, Object> comp, List<Object> activeFilters) {
        String objectName = (String) comp.get('object');
        String compType = (String) comp.get('type');
        String groupByField = (String) comp.get('groupByField');
        String aggregation = (String) comp.get('aggregation');
        String field = (String) comp.get('field');

        validateApiNameInternal(objectName, 'object');
        validateApiNameInternal(field, 'field');
        validateAggregationInternal(aggregation);
        if (String.isBlank(groupByField)) {
            throw new DashboardDataException('groupByField is required for ' + compType + ' type. Please edit this component and set a Group By Field.');
        }
        validateApiNameInternal(groupByField, 'groupByField');

        // Collect extra fields for SELECT and GROUP BY
        List<String> extraSelectFields = new List<String>();
        List<String> extraGroupByFields = new List<String>();

        String subtitleField = (String) comp.get('subtitleField');
        String badgeField = (String) comp.get('badgeField');
        String nameField = (String) comp.get('nameField');
        String severityField = (String) comp.get('severityField');
        String textField = (String) comp.get('textField');
        String targetField = (String) comp.get('targetField');
        String typeField = (String) comp.get('typeField');

        // Add extra fields (skip duplicates of groupByField or already-added fields)
        Set<String> addedFields = new Set<String>{ groupByField.toLowerCase() };
        if (String.isNotBlank(subtitleField) && !addedFields.contains(subtitleField.toLowerCase())) { validateApiNameInternal(subtitleField, 'subtitleField'); extraSelectFields.add(subtitleField); extraGroupByFields.add(subtitleField); addedFields.add(subtitleField.toLowerCase()); }
        if (String.isNotBlank(badgeField) && !addedFields.contains(badgeField.toLowerCase())) { validateApiNameInternal(badgeField, 'badgeField'); extraSelectFields.add(badgeField); extraGroupByFields.add(badgeField); addedFields.add(badgeField.toLowerCase()); }
        if (String.isNotBlank(nameField) && !addedFields.contains(nameField.toLowerCase())) { validateApiNameInternal(nameField, 'nameField'); extraSelectFields.add(nameField); extraGroupByFields.add(nameField); addedFields.add(nameField.toLowerCase()); }
        if (String.isNotBlank(severityField) && !addedFields.contains(severityField.toLowerCase())) { validateApiNameInternal(severityField, 'severityField'); extraSelectFields.add(severityField); extraGroupByFields.add(severityField); addedFields.add(severityField.toLowerCase()); }
        if (String.isNotBlank(textField) && !addedFields.contains(textField.toLowerCase())) { validateApiNameInternal(textField, 'textField'); extraSelectFields.add(textField); extraGroupByFields.add(textField); addedFields.add(textField.toLowerCase()); }
        if (String.isNotBlank(typeField) && !addedFields.contains(typeField.toLowerCase())) { validateApiNameInternal(typeField, 'typeField'); extraSelectFields.add(typeField); extraGroupByFields.add(typeField); addedFields.add(typeField.toLowerCase()); }

        // Build aggregation expressions from metrics/columns arrays
        List<String> aggExpressions = new List<String>();
        // Primary aggregation
        aggExpressions.add(aggregation + '(' + field + ') val');

        // Secondary aggregation
        String secondaryAgg = (String) comp.get('secondaryAggregation');
        String secondaryField = (String) comp.get('secondaryField');
        if (String.isNotBlank(secondaryAgg) && String.isNotBlank(secondaryField)) {
            validateAggregationInternal(secondaryAgg);
            validateApiNameInternal(secondaryField, 'secondaryField');
            aggExpressions.add(secondaryAgg + '(' + secondaryField + ') secondaryVal');
        }

        // Target field aggregation
        if (String.isNotBlank(targetField)) {
            validateApiNameInternal(targetField, 'targetField');
            aggExpressions.add('SUM(' + targetField + ') targetVal');
        }

        // Metrics array (for metricCards, statusCard, achievementCard)
        List<Object> metricsArray = (List<Object>) comp.get('metrics');
        if (metricsArray != null) {
            Integer metricIdx = 0;
            for (Object mObj : metricsArray) {
                if (!(mObj instanceof Map<String, Object>)) continue;
                Map<String, Object> metric = (Map<String, Object>) mObj;
                String mAgg = (String) metric.get('aggregation');
                String mField = (String) metric.get('field');
                if (String.isNotBlank(mAgg) && String.isNotBlank(mField)) {
                    validateAggregationInternal(mAgg);
                    validateApiNameInternal(mField, 'metric field');
                    aggExpressions.add(mAgg + '(' + mField + ') metric' + metricIdx);
                    metricIdx++;
                }
            }
        }

        // Columns array (for rankedTable)
        List<Object> columnsArray = (List<Object>) comp.get('columns');
        if (columnsArray != null) {
            Integer colIdx = 0;
            for (Object cObj : columnsArray) {
                if (!(cObj instanceof Map<String, Object>)) continue;
                Map<String, Object> col = (Map<String, Object>) cObj;
                String cAgg = (String) col.get('aggregation');
                String cField = (String) col.get('field');
                if (String.isNotBlank(cAgg) && String.isNotBlank(cField)) {
                    validateAggregationInternal(cAgg);
                    validateApiNameInternal(cField, 'column field');
                    aggExpressions.add(cAgg + '(' + cField + ') col' + colIdx);
                    colIdx++;
                }
            }
        }

        // Build query
        List<String> conditions = buildConditionsInternal(comp, activeFilters);
        Integer maxItems = 20;
        Object maxItemsObj = comp.get('maxItems');
        if (maxItemsObj == null) maxItemsObj = comp.get('maxGroups');
        if (maxItemsObj != null && String.isNotBlank(String.valueOf(maxItemsObj))) {
            maxItems = Integer.valueOf(String.valueOf(maxItemsObj));
        }

        String query = 'SELECT ' + groupByField;
        for (String ef : extraSelectFields) {
            query += ', ' + ef;
        }
        query += ', ' + String.join(aggExpressions, ', ');
        query += ' FROM ' + objectName;
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        query += ' GROUP BY ' + groupByField;
        if (!extraGroupByFields.isEmpty()) {
            query += ', ' + String.join(extraGroupByFields, ', ');
        }
        query += ' ORDER BY ' + aggregation + '(' + field + ') DESC';
        query += ' LIMIT ' + maxItems;

        List<AggregateResult> aggResults = Database.query(query);

        MultiMetricComponentResult result = new MultiMetricComponentResult();
        result.items = new List<MultiMetricResult>();

        Decimal staticTarget = null;
        Object staticTargetObj = comp.get('staticTarget');
        if (staticTargetObj != null && String.isNotBlank(String.valueOf(staticTargetObj))) {
            staticTarget = Decimal.valueOf(String.valueOf(staticTargetObj));
        }

        for (AggregateResult ar : aggResults) {
            MultiMetricResult item = new MultiMetricResult();
            item.groupLabel = String.valueOf(ar.get(groupByField));
            if (String.isBlank(item.groupLabel)) item.groupLabel = BLANK_GROUP_LABEL;

            item.primaryValue = ar.get('val') != null ? (Decimal) ar.get('val') : 0;

            // Secondary value
            if (String.isNotBlank(secondaryAgg)) {
                item.secondaryValue = ar.get('secondaryVal') != null ? (Decimal) ar.get('secondaryVal') : 0;
            }

            // Target
            if (String.isNotBlank(targetField)) {
                item.target = ar.get('targetVal') != null ? (Decimal) ar.get('targetVal') : 0;
            } else if (staticTarget != null) {
                item.target = staticTarget;
            }

            // Calculate achievement percentage
            if (item.target != null && item.target > 0) {
                item.achievement = ((item.primaryValue / item.target) * 100).setScale(1);
            }

            // Extra fields
            if (String.isNotBlank(subtitleField)) item.subtitle = String.valueOf(ar.get(subtitleField));
            if (String.isNotBlank(badgeField)) item.badge = String.valueOf(ar.get(badgeField));
            if (String.isNotBlank(severityField)) item.severity = String.valueOf(ar.get(severityField));
            if (String.isNotBlank(textField)) item.textValue = String.valueOf(ar.get(textField));
            if (String.isNotBlank(typeField)) item.badge = String.valueOf(ar.get(typeField));

            // Metrics map
            item.metrics = new Map<String, Decimal>();
            if (metricsArray != null) {
                Integer metricIdx = 0;
                for (Object mObj : metricsArray) {
                    if (!(mObj instanceof Map<String, Object>)) continue;
                    Map<String, Object> metric = (Map<String, Object>) mObj;
                    String mLabel = (String) metric.get('label');
                    if (String.isNotBlank(mLabel)) {
                        Decimal mVal = ar.get('metric' + metricIdx) != null ? (Decimal) ar.get('metric' + metricIdx) : 0;
                        item.metrics.put(mLabel, mVal);
                    }
                    metricIdx++;
                }
            }

            // Columns map
            item.columns = new Map<String, Decimal>();
            if (columnsArray != null) {
                Integer colIdx = 0;
                for (Object cObj : columnsArray) {
                    if (!(cObj instanceof Map<String, Object>)) continue;
                    Map<String, Object> col = (Map<String, Object>) cObj;
                    String cLabel = (String) col.get('label');
                    if (String.isNotBlank(cLabel)) {
                        Decimal cVal = ar.get('col' + colIdx) != null ? (Decimal) ar.get('col' + colIdx) : 0;
                        item.columns.put(cLabel, cVal);
                    }
                    colIdx++;
                }
            }

            result.items.add(item);
        }

        return result;
    }

    private static ComponentResult executeComponentQuery(Map<String, Object> comp, List<Object> activeFilters) {
        String objectName = (String) comp.get('object');
        String aggregation = (String) comp.get('aggregation');
        String field = (String) comp.get('field');
        String groupByField = (String) comp.get('groupByField');
        String compType = (String) comp.get('type');

        validateApiNameInternal(objectName, 'object');
        validateApiNameInternal(field, 'field');
        validateAggregationInternal(aggregation);
        if (String.isNotBlank(groupByField)) {
            validateApiNameInternal(groupByField, 'groupByField');
        }

        Integer maxGroups = null;
        Object maxGroupsObj = comp.get('maxGroups');
        if (maxGroupsObj != null && String.isNotBlank(String.valueOf(maxGroupsObj))) {
            maxGroups = Integer.valueOf(String.valueOf(maxGroupsObj));
        }

        List<String> conditions = buildConditionsInternal(comp, activeFilters);
        String query = buildQuery(compType, objectName, aggregation, field, groupByField, conditions, maxGroups);

        ComponentResult result = new ComponentResult();
        result.chartData = new List<ChartDataPoint>();
        List<AggregateResult> aggResults = Database.query(query);

        if (compType == 'kpi') {
            if (!aggResults.isEmpty()) {
                Object val = aggResults[0].get('val');
                result.value = val != null ? (Decimal) val : 0;
            } else {
                result.value = 0;
            }
        } else {
            for (AggregateResult ar : aggResults) {
                String label = String.valueOf(ar.get(groupByField));
                if (String.isBlank(label)) label = BLANK_GROUP_LABEL;
                Decimal val = ar.get('val') != null ? (Decimal) ar.get('val') : 0;
                result.chartData.add(new ChartDataPoint(label, val));
            }
        }

        return result;
    }

    // Internal buildConditions that uses non-AuraHandledException validators
    private static List<String> buildConditionsInternal(Map<String, Object> comp, List<Object> activeFilters) {
        List<String> conditions = new List<String>();

        List<Object> staticFilters = (List<Object>) comp.get('staticFilters');
        if (staticFilters != null) {
            for (Object sf : staticFilters) {
                if (!(sf instanceof Map<String, Object>)) continue;
                Map<String, Object> filter = (Map<String, Object>) sf;
                String cond = buildStaticConditionInternal(filter);
                if (String.isNotBlank(cond)) conditions.add(cond);
            }
        }

        for (Object af : activeFilters) {
            if (!(af instanceof Map<String, Object>)) continue;
            Map<String, Object> filter = (Map<String, Object>) af;
            String filterField = (String) filter.get('field');
            String filterType = (String) filter.get('type');
            Object filterValue = filter.get('value');

            if (filterValue == null || String.valueOf(filterValue) == '') continue;
            if (String.isNotBlank(filterField)) validateApiNameInternal(filterField, 'filter field');

            if (filterType == 'dateRange') {
                if (!(filterValue instanceof Map<String, Object>)) continue;
                Map<String, Object> dateRange = (Map<String, Object>) filterValue;
                String startDate = (String) dateRange.get('start');
                String endDate = (String) dateRange.get('end');
                if (String.isNotBlank(startDate)) {
                    conditions.add(filterField + ' >= ' + startDate);
                }
                if (String.isNotBlank(endDate)) {
                    conditions.add(filterField + ' <= ' + endDate);
                }
            } else if (filterType == 'dateLiteral') {
                String literal = String.valueOf(filterValue);
                if (isValidDateLiteral(literal)) {
                    conditions.add(filterField + ' = ' + literal);
                }
            } else if (filterType == 'picklist' || filterType == 'text') {
                conditions.add(filterField + ' = \'' + String.escapeSingleQuotes(String.valueOf(filterValue)) + '\'');
            } else if (filterType == 'currentUser') {
                conditions.add(filterField + ' = \'' + UserInfo.getUserId() + '\'');
            } else if (filterType == 'userHierarchy') {
                Set<Id> subordinateIds = getSubordinateUserIds();
                if (!subordinateIds.isEmpty()) {
                    List<String> idStrings = new List<String>();
                    for (Id subId : subordinateIds) {
                        idStrings.add('\'' + subId + '\'');
                    }
                    conditions.add(filterField + ' IN (' + String.join(idStrings, ',') + ')');
                }
            } else if (filterType == 'lookup') {
                conditions.add(filterField + ' = \'' + String.escapeSingleQuotes(String.valueOf(filterValue)) + '\'');
            } else if (filterType == 'hierarchy') {
                String selectedUserId = String.valueOf(filterValue);
                String hierarchyMode = filter.get('hierarchyMode') != null ? String.valueOf(filter.get('hierarchyMode')) : 'role';
                Set<Id> hierarchyIds;
                if (hierarchyMode == 'manager') {
                    hierarchyIds = DashboardConfigController.getAllManagerSubordinateIds(selectedUserId);
                } else {
                    hierarchyIds = DashboardConfigController.getAllSubordinateUserIds(selectedUserId);
                }
                if (!hierarchyIds.isEmpty()) {
                    List<String> idStrings = new List<String>();
                    for (Id uid : hierarchyIds) {
                        idStrings.add('\'' + uid + '\'');
                    }
                    conditions.add(filterField + ' IN (' + String.join(idStrings, ',') + ')');
                }
            }
        }

        return conditions;
    }

    private static String buildStaticConditionInternal(Map<String, Object> filter) {
        String field = (String) filter.get('field');
        String operator = (String) filter.get('operator');
        String value = (String) filter.get('value');

        if (String.isBlank(field) || String.isBlank(value)) return null;
        validateApiNameInternal(field, 'static filter field');

        if (isValidDateLiteral(value)) {
            return field + ' ' + getOperatorSymbol(operator) + ' ' + value;
        }

        String escapedValue = String.escapeSingleQuotes(value);

        if (operator == 'contains') {
            return field + ' LIKE \'%' + escapedValue + '%\'';
        } else if (operator == 'notContains') {
            return '(NOT ' + field + ' LIKE \'%' + escapedValue + '%\')';
        }

        return field + ' ' + getOperatorSymbol(operator) + ' \'' + escapedValue + '\'';
    }

    // Result classes
    public class ComponentResult {
        @AuraEnabled public String componentId;
        @AuraEnabled public Decimal value;
        @AuraEnabled public List<ChartDataPoint> chartData;
        @AuraEnabled public List<MultiMetricResult> multiMetricData;
        @AuraEnabled public String errorMessage;
    }

    public class ChartDataPoint {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal value;

        public ChartDataPoint(String label, Decimal value) {
            this.label = label;
            this.value = value;
        }
    }

    public class MultiMetricComponentResult {
        @AuraEnabled public List<MultiMetricResult> items;
    }

    public class MultiMetricResult {
        @AuraEnabled public String groupLabel;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String badge;
        @AuraEnabled public Decimal primaryValue;
        @AuraEnabled public Decimal secondaryValue;
        @AuraEnabled public Decimal target;
        @AuraEnabled public Decimal achievement;
        @AuraEnabled public String severity;
        @AuraEnabled public String textValue;
        @AuraEnabled public Map<String, Decimal> metrics;
        @AuraEnabled public Map<String, Decimal> columns;
    }

    public class ReportResult {
        @AuraEnabled public List<ReportColumn> columns;
        @AuraEnabled public List<Map<String, String>> rows;
        @AuraEnabled public Integer totalRecords;
    }

    public class ReportColumn {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String label;
    }

    // Custom exception that preserves getMessage() when caught in Apex
    // (unlike AuraHandledException which always returns "Script-thrown exception")
    public class DashboardDataException extends Exception {}
}