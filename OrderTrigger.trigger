trigger OrderTrigger on Order (after insert, after update) {

    if (Trigger.isAfter && Trigger.isInsert) {
        OrderTriggerHandler.afterInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        OrderTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}