public class InventoryLevelOrchestrationService {

    private static final Integer MAX_RETRY_ATTEMPTS = 1;
    private static final String RETRY_ATTEMPT_KEY = '__inventoryRetryAttempt';

    /*
     * Main entry point used by ShopifyPlatformEventHandler and by the retry queueable.
     *
     * This version intentionally keeps only ONE public method signature:
     *   processInventoryLevelWebhook(Map<String, Object> payload)
     *
     * That avoids the compile-order problem where InventoryLevelRetryQueueable
     * cannot compile until this service has the new overload, while this service
     * cannot compile until the queueable constructor exists.
     */
    public static void processInventoryLevelWebhook(Map<String, Object> payload) {
        processInventoryLevelWebhookInternal(payload);
    }

    public static Boolean processInventoryLevelWebhookInternal(Map<String, Object> payload) {
        if (payload == null) {
            System.debug(LoggingLevel.WARN, 'Inventory skipped: payload is null.');
            return false;
        }

        Integer retryAttempt = getRetryAttempt(payload);

        String inventoryItemId = normalizeId(payload.get('inventory_item_id'));
        String shopifyLocationId = normalizeId(payload.get('location_id'));
        Decimal availableQty = getAvailableQuantity(payload);

        if (String.isBlank(inventoryItemId) || String.isBlank(shopifyLocationId)) {
            System.debug(
                LoggingLevel.WARN,
                'Inventory skipped because inventory_item_id or location_id is blank. payload=' +
                JSON.serialize(payload)
            );
            return false;
        }

        Product2 variant = findVariantByInventoryItemId(inventoryItemId);

        if (variant == null) {
            System.debug(
                LoggingLevel.WARN,
                'Inventory variant not found yet for inventory item ' + inventoryItemId +
                '. retryAttempt=' + retryAttempt
            );

            enqueueRetryIfAllowed(payload, retryAttempt);
            return false;
        }

        Id sfLocationId = ShopifyLocationGraphQLService.getOrCreateSalesforceLocation(shopifyLocationId);
        String inventoryKey = variant.Shop_ID__c + '-' + shopifyLocationId;

        Inventory__c inv = findInventory(inventoryItemId, shopifyLocationId, inventoryKey);

        InventorySyncControl.skipOutbound = true;

        try {
            if (inv == null) {
                inv = new Inventory__c();
                inv.Variant__c = variant.Id;
                inv.Location__c = sfLocationId;
                inv.Inventory_Key__c = inventoryKey;
            }

            inv.Available__c = availableQty;
            /*
* Initialize Salesforce inventory only when it is blank.
* Do not overwrite Salesforce_Available__c on every Shopify webhook,
* because Salesforce_Available__c may include Square/manual sales.
*/
            if (inv.Salesforce_Available__c == null) {
                inv.Salesforce_Available__c = availableQty;
            }
            inv.Shopify_Inventory_Item_ID__c = inventoryItemId;
            inv.Shopify_Inventory_Item_ID__c = inventoryItemId;
            inv.Shopify_Location_ID__c = shopifyLocationId;
            inv.Location__c = sfLocationId;
            inv.Inventory_Key__c = inventoryKey;
            inv.Sync_Status__c = 'Success';
            inv.Last_Sync_At__c = System.now();

            if (Inventory__c.SObjectType.getDescribe().fields.getMap().containsKey('Shop_ID__c')) {
                inv.put('Shop_ID__c', variant.Shop_ID__c);
            }

            upsert inv Inventory_Key__c;

            System.debug(
                LoggingLevel.INFO,
                'Inventory upserted successfully. InventoryItemId=' + inventoryItemId +
                ', ShopifyLocationId=' + shopifyLocationId +
                ', VariantShopId=' + variant.Shop_ID__c +
                ', Available=' + availableQty
            );

            return true;

        } finally {
            InventorySyncControl.skipOutbound = false;
        }
    }

    private static void enqueueRetryIfAllowed(
        Map<String, Object> payload,
        Integer retryAttempt
    ) {
        if (payload == null) return;

        if (retryAttempt == null) {
            retryAttempt = 0;
        }

        if (retryAttempt >= MAX_RETRY_ATTEMPTS) {
            System.debug(
                LoggingLevel.ERROR,
                'Inventory retry limit reached. payload=' + JSON.serialize(payload)
            );
            return;
        }

        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            System.debug(
                LoggingLevel.WARN,
                'Inventory retry not queued because queueable limit is already used. payload=' +
                JSON.serialize(payload)
            );
            return;
        }

        Map<String, Object> retryPayload = new Map<String, Object>();
        retryPayload.putAll(payload);
        retryPayload.put(RETRY_ATTEMPT_KEY, retryAttempt + 1);

        System.enqueueJob(
            new InventoryLevelRetryQueueable(JSON.serialize(retryPayload))
        );

        System.debug(
            LoggingLevel.INFO,
            'Inventory retry queued. nextAttempt=' + String.valueOf(retryAttempt + 1) +
            ', payload=' + JSON.serialize(retryPayload)
        );
    }

    private static Integer getRetryAttempt(Map<String, Object> payload) {
        if (payload == null || !payload.containsKey(RETRY_ATTEMPT_KEY)) {
            return 0;
        }

        Object rawAttempt = payload.get(RETRY_ATTEMPT_KEY);

        if (rawAttempt == null) {
            return 0;
        }

        try {
            return Integer.valueOf(String.valueOf(rawAttempt));
        } catch (Exception e) {
            return 0;
        }
    }

    private static Decimal getAvailableQuantity(Map<String, Object> payload) {
        if (payload == null || payload.get('available') == null) {
            return 0;
        }

        try {
            return Decimal.valueOf(String.valueOf(payload.get('available')));
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'Inventory available quantity could not be parsed. Value=' +
                String.valueOf(payload.get('available')) +
                ', Error=' + e.getMessage()
            );
            return 0;
        }
    }

    private static Inventory__c findInventory(
        String inventoryItemId,
        String shopifyLocationId,
        String inventoryKey
    ) {
        List<Inventory__c> rows = [
            SELECT Id,
                   Available__c,
                   Salesforce_Available__c,
                   Variant__c,
                   Location__c,
                   Shopify_Inventory_Item_ID__c,
                   Shopify_Location_ID__c,
                   Inventory_Key__c
            FROM Inventory__c
            WHERE Inventory_Key__c = :inventoryKey
            LIMIT 1
        ];

        if (!rows.isEmpty()) return rows[0];

        rows = [
            SELECT Id,
                   Available__c,
                   Salesforce_Available__c,
                   Variant__c,
                   Location__c,
                   Shopify_Inventory_Item_ID__c,
                   Shopify_Location_ID__c,
                   Inventory_Key__c
            FROM Inventory__c
            WHERE Shopify_Inventory_Item_ID__c = :inventoryItemId
            AND Shopify_Location_ID__c = :shopifyLocationId
            LIMIT 1
        ];

        return rows.isEmpty() ? null : rows[0];
    }

    private static Product2 findVariantByInventoryItemId(String inventoryItemId) {
        if (String.isBlank(inventoryItemId)) {
            return null;
        }

        List<Product2> variants = [
            SELECT Id,
                   Shop_ID__c,
                   Inventory_Item_Id__c
            FROM Product2
            WHERE Inventory_Item_Id__c = :inventoryItemId
            LIMIT 1
        ];

        return variants.isEmpty() ? null : variants[0];
    }

    private static String normalizeId(Object rawValue) {
        if (rawValue == null) return null;

        String value = String.valueOf(rawValue).trim();
        if (String.isBlank(value)) return null;

        if (value.contains('/')) {
            List<String> parts = value.split('/');
            value = parts[parts.size() - 1];
        }

        if (value.endsWith('.0')) {
            value = value.substring(0, value.length() - 2);
        }

        if (value.contains('E') || value.contains('e')) {
            Decimal d = Decimal.valueOf(value);
            value = String.valueOf(d.setScale(0));
        }

        return value;
    }
}