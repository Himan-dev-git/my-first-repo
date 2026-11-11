trigger OrderItemTrigger on OrderItem (after insert, after delete) {

    Set<Id> orderIds = new Set<Id>();

    if (Trigger.isInsert) {
        for (OrderItem item : Trigger.new) {
            if (item.OrderId != null) {
                orderIds.add(item.OrderId);
            }
        }

        if (!orderIds.isEmpty()) {
            /*
             * Salesforce Order -> Shopify Order creation is intentionally disabled.
             *
             * OrderItem creation must NOT create a new Shopify Order.
             * Existing Shopify Orders are handled separately through
             * OrderTriggerHandler.afterUpdate() and
             * ShopifyOrderUpdateGraphQLService.
             */

            // Deduct inventory for inserted order line items.
            // Actual location is resolved through:
            // Order.Type -> Inventory_Rules__mdt -> Location -> Inventory__c
            OrderInventoryAdjustmentService.deduct(new List<Id>(orderIds));
        }
    }

    if (Trigger.isDelete) {
        for (OrderItem item : Trigger.old) {
            if (item.OrderId != null) {
                orderIds.add(item.OrderId);
            }
        }

        if (!orderIds.isEmpty()) {
            // Restore inventory when line items are removed.
            // Actual location is resolved through:
            // Order.Type -> Inventory_Rules__mdt -> Location -> Inventory__c
            OrderInventoryAdjustmentService.restore(new List<Id>(orderIds));
        }
    }
}