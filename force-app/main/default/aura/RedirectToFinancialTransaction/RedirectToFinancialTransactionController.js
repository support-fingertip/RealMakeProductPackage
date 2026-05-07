({
    doInit : function(component, event, helper) {
        var recordId = component.get("v.recordId");

        var evt = $A.get("e.force:navigateToComponent");
        evt.setParams({
            componentDef : "c:financialTransactionManager",
            componentAttributes: {
                recordId : recordId
            }
        });
        evt.fire();

        // Close the quick action panel
        $A.get("e.force:closeQuickAction").fire();
    }
})