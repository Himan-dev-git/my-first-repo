public with sharing class OrderInventoryAdjustmentService {

    // ─────────────────────────────────────────────────────────────────────
    // Public entry points
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Deduct stock.
     * Use when an Order / OrderItem should reduce inventory.
     */
    public static void deduct(List<Id> orderIds) {
        
        adjust(orderIds, -1);
    }

    /**
     * Restore stock.
     * Use when an Order / OrderItem should restore inventory because of
     * refund, cancellation, void, or line item removal.
     */
    public static void restore(List<Id> orderIds) {
        adjust(orderIds, +1);
    }

    /**
     * Core inventory adjustment method.
     *
     * direction = -1 means deduct
     * direction = +1 means restore
     *
     * New refined pattern:
     * Order.Type -> Inventory_Rules__mdt -> Location -> Inventory__c
     */      
        public static void adjust(List<Id> orderIds, Integer direction) {
            
            System.debug(
                LoggingLevel.WARN,
                '### OrderInventoryAdjustmentService.adjust START ### orderIds=' + orderIds +
                ', direction=' + direction
            );
            
            if (orderIds == null || orderIds.isEmpty()) {
                return;
            }
            if (direction == null || direction == 0) {
                return;
            }

        // ── Fetch Orders first because Inventory Rules are based on Order.Type
        Map<Id, Order> ordersById = new Map<Id, Order>([
            SELECT Id,
                   Type,
                   Location__c,
                   Status,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id IN :orderIds
        ]);

        if (ordersById.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                'OrderInventoryAdjustmentService: no Orders found. orderIds=' + orderIds
            );
            return;
        }

        // ── Resolve deduction/restock Location from Inventory Rules
        Map<Id, Id> locationIdByOrderId = new Map<Id, Id>();
        Set<Id> resolvedLocationIds = new Set<Id>();

        for (Order ord : ordersById.values()) {
            Id ruleLocationId = InventoryRuleService.getLocationIdForOrder(ord);

            // Fallback to existing Order.Location__c so existing logic is not broken.
            // This preserves the previous behavior if metadata is missing.
            if (ruleLocationId == null && ord.Location__c != null) {
                ruleLocationId = ord.Location__c;

                System.debug(
                    LoggingLevel.WARN,
                    'OrderInventoryAdjustmentService: Inventory Rule not found or Location missing. ' +
                    'Falling back to Order.Location__c. orderId=' + ord.Id +
                    ', orderType=' + ord.Type +
                    ', fallbackLocationId=' + ord.Location__c
                );
            }

            if (ruleLocationId == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'OrderInventoryAdjustmentService: no inventory location resolved. ' +
                    'Skipping orderId=' + ord.Id +
                    ', orderType=' + ord.Type
                );
                continue;
            }

            locationIdByOrderId.put(ord.Id, ruleLocationId);
            resolvedLocationIds.add(ruleLocationId);
        }

        if (locationIdByOrderId.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'OrderInventoryAdjustmentService: no Orders had a resolved inventory location.'
            );
            return;
        }

        // ── Fetch Order Items
        List<OrderItem> items = [
            SELECT Id,
                   OrderId,
                   Quantity,
                   Product2Id
            FROM OrderItem
            WHERE OrderId IN :locationIdByOrderId.keySet()
            AND Product2Id != null
        ];

        if (items.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                'OrderInventoryAdjustmentService: no eligible OrderItems found. orderIds=' + orderIds
            );
            return;
        }

        Set<Id> variantIds = new Set<Id>();

        for (OrderItem item : items) {
            if (item.Product2Id != null) {
                variantIds.add(item.Product2Id);
            }
        }

        if (variantIds.isEmpty()) {
            return;
        }

        // ── Fetch Inventory rows by Variant/SKU + resolved Location
        List<Inventory__c> invRows = [
            SELECT Id,
                   Available__c,
                   Salesforce_Available__c,
                   Variant__c,
                   Location__c,
                   Location__r.Name
            FROM Inventory__c
            WHERE Variant__c IN :variantIds
            AND Location__c IN :resolvedLocationIds
        ];

        Map<String, Inventory__c> invByVariantLocationKey = new Map<String, Inventory__c>();

        for (Inventory__c inv : invRows) {
            if (inv.Variant__c == null || inv.Location__c == null) {
                continue;
            }

            String key = buildVariantLocationKey(inv.Variant__c, inv.Location__c);

            if (invByVariantLocationKey.containsKey(key)) {
                System.debug(
                    LoggingLevel.WARN,
                    'OrderInventoryAdjustmentService: duplicate Inventory__c rows found for same Variant + Location. ' +
                    'variantId=' + inv.Variant__c +
                    ', locationId=' + inv.Location__c
                );

                // Keep the first row to avoid double adjustment.
                continue;
            }

            invByVariantLocationKey.put(key, inv);
        }

        Map<Id, Inventory__c> toUpdate = new Map<Id, Inventory__c>();

        for (OrderItem item : items) {
            Id resolvedLocationId = locationIdByOrderId.get(item.OrderId);

            if (resolvedLocationId == null) {
                continue;
            }

            String key = buildVariantLocationKey(item.Product2Id, resolvedLocationId);
            Inventory__c inv = invByVariantLocationKey.get(key);

            if (inv == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'OrderInventoryAdjustmentService: no Inventory__c found for OrderItem. ' +
                    'orderId=' + item.OrderId +
                    ', orderItemId=' + item.Id +
                    ', product2Id=' + item.Product2Id +
                    ', locationId=' + resolvedLocationId
                );
                continue;
            }
            
            /*
 * NEW INVENTORY MODEL:
 * Order deductions/restores should update Salesforce_Available__c only.
 * Available__c is reserved for the Shopify inventory snapshot.
 * This allows Salesforce to calculate discrepancy without automatically
 * changing Shopify inventory.
 */

            Decimal qty = item.Quantity == null ? 0 : item.Quantity;
            Decimal delta = qty * direction;

            if (toUpdate.containsKey(inv.Id)) {
                Inventory__c existingUpdate = toUpdate.get(inv.Id);
                existingUpdate.Salesforce_Available__c =
                    (existingUpdate.Salesforce_Available__c == null ? 0 : existingUpdate.Salesforce_Available__c) + delta;
            } else {
                Inventory__c upd = new Inventory__c();
                upd.Id = inv.Id;
                upd.Salesforce_Available__c = (inv.Salesforce_Available__c == null ? 0 : inv.Salesforce_Available__c) + delta;
                upd.Sync_Status__c = 'Success';
                upd.Last_Sync_At__c = System.now();

                toUpdate.put(inv.Id, upd);
            }

            System.debug(
                LoggingLevel.INFO,
                'OrderInventoryAdjustmentService: inventory adjusted using Inventory Rules. ' +
                'orderId=' + item.OrderId +
                ', orderItemId=' + item.Id +
                ', product2Id=' + item.Product2Id +
                ', inventoryId=' + inv.Id +
                ', locationId=' + resolvedLocationId +
                ', quantity=' + qty +
                ', direction=' + direction +
                ', delta=' + delta
            );
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate.values();

            System.debug(
                LoggingLevel.INFO,
                'OrderInventoryAdjustmentService: updated ' + toUpdate.size() +
                ' Inventory__c record(s). direction=' + direction
            );
        }
    }

    private static String buildVariantLocationKey(Id variantId, Id locationId) {
        return String.valueOf(variantId) + '-' + String.valueOf(locationId);
    }
}