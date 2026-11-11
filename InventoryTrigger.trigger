trigger InventoryTrigger on Inventory__c (
    before insert,
    before update,
    after insert,
    after update
) {
    if (Trigger.isBefore) {
        InventoryTriggerHandler.beforeSave(Trigger.new, Trigger.oldMap);
    }
    
    if (Trigger.isAfter) {
        InventoryTriggerHandler.afterSave(Trigger.new, Trigger.oldMap);
    }
}