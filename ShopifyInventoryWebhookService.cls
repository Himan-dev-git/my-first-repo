public class ShopifyInventoryWebhookService {

    public static void process(String jsonPayload) {

        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(jsonPayload);

        String inventoryItemId = String.valueOf(payload.get('inventory_item_id'));
        String locationId = String.valueOf(payload.get('location_id'));
        Decimal available = Decimal.valueOf(String.valueOf(payload.get('available')));

        // 🔥 THIS is the core fix
        List<Inventory__c> invList = [
            SELECT Id, Available__c
            FROM Inventory__c
            WHERE Shopify_Inventory_Item_ID__c = :inventoryItemId
            AND Shopify_Location_ID__c = :locationId
            LIMIT 1
        ];

        if (!invList.isEmpty()) {
            Inventory__c inv = invList[0];
            inv.Available__c = available;
            inv.Sync_Status__c = 'Success';
            inv.Last_Sync_At__c = System.now();
            update inv;
        } else {
            System.debug('❌ Inventory record not found for mapping');
        }
    }
}