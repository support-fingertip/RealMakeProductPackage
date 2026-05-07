public with sharing class QuoteConfiguratorController {

    @AuraEnabled(cacheable=true)
    public static InitWrapper getUnitNumericFields(string recId) {
        InitWrapper inwrp = new InitWrapper();

        List<FieldInfo> result = new List<FieldInfo>();
        Map<String, Schema.SObjectField> fields =
            Unit__c.SObjectType.getDescribe().fields.getMap();

        for (Schema.SObjectField f : fields.values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (d.getType() == Schema.DisplayType.Double ||
                d.getType() == Schema.DisplayType.Integer ||
                d.getType() == Schema.DisplayType.Currency ||
                d.getType() == Schema.DisplayType.Percent) {
                result.add(new FieldInfo(d.getLabel(), d.getName()));
            }
        }
        
        string queryval = [select id, Quote_Calculation_Logic__c from Project__c where Id =: recId].Quote_Calculation_Logic__c;
        inwrp.FieldInfos = result;
        inwrp.QuoteCalculationLogic = queryval;
        
        return inwrp;
    }

    @AuraEnabled
    public static void saveFormulaRec(Id projectId, String formula) {
        update new Project__c(
            Id = projectId,
            Quote_Calculation_Logic__c = formula
        );
    }

    public class InitWrapper {
        @AuraEnabled public List<FieldInfo> FieldInfos;
        @AuraEnabled public String QuoteCalculationLogic;
    }
    
    public class FieldInfo {
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        public FieldInfo(String l, String a) {
            label = l;
            apiName = a;
        }
    }
    
    
    @AuraEnabled
    public static String validateFormula(String formula) {
        try {
            return FormulaEvaluator.validate(formula);
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
}