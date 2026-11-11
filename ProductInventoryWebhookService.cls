public class ProductInventoryWebhookService {

    private static final String ORDER_TYPE_SHOPIFY = 'Shopify';
    private static final String ORDER_TYPE_SHOPIFY_ORDER = 'Shopify Order';

    public static void processProductWebhook(Map<String, Object> productPayload) {
        if (productPayload == null) {
            return;
        }

        if (!productPayload.containsKey('variants')) {
            return;
        }

        List<Object> variants = (List<Object>) productPayload.get('variants');

        if (variants == null || variants.isEmpty()) {
            return;
        }

        DeductionLocation inventoryLocation = getInventoryLocationForShopify();

        if (inventoryLocation == null || inventoryLocation.locationId == null) {
            System.debug(
                LoggingLevel.WARN,
                'ProductInventoryWebhookService skipped: no Shopify inventory location found from Inventory_Rules__mdt.'
            );
            return;
        }

        List<Inventory__c> updates = new List<Inventory__c>();
        Set<Id> updatedInventoryIds = new Set<Id>();

        for (Object obj : variants) {
            Map<String, Object> v = (Map<String, Object>) obj;

            String variantShopifyId = normalizeShopifyId(v.get('id'));
            String inventoryItemId = normalizeShopifyId(v.get('inventory_item_id'));

            Decimal qty = v.get('inventory_quantity') == null
                ? null
                : Decimal.valueOf(String.valueOf(v.get('inventory_quantity')));

            System.debug('ProductInventory variantShopifyId=' + variantShopifyId);
            System.debug('ProductInventory inventoryItemId=' + inventoryItemId);
            System.debug('ProductInventory qty=' + qty);
            System.debug('ProductInventory locationId=' + inventoryLocation.locationId);
            System.debug('ProductInventory locationName=' + inventoryLocation.locationName);

            if (qty == null) {
                continue;
            }

            Inventory__c inv = findInventoryRow(
                variantShopifyId,
                inventoryItemId,
                inventoryLocation.locationId
            );

            if (inv == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'ProductInventory: no Inventory__c found for configured Inventory Rules location. ' +
                    'variantShopifyId=' + variantShopifyId +
                    ', inventoryItemId=' + inventoryItemId +
                    ', locationId=' + inventoryLocation.locationId +
                    ', locationName=' + inventoryLocation.locationName
                );
                continue;
            }

            if (updatedInventoryIds.contains(inv.Id)) {
                continue;
            }

            Inventory__c upd = new Inventory__c();
            upd.Id = inv.Id;
            upd.Available__c = qty;
            upd.Sync_Status__c = 'Success';
            upd.Last_Sync_At__c = System.now();

            if (!String.isBlank(inventoryItemId)) {
                upd.Shopify_Inventory_Item_ID__c = inventoryItemId;
            }

            updates.add(upd);
            updatedInventoryIds.add(inv.Id);
        }

        if (!updates.isEmpty()) {
            InventorySyncControl.skipOutbound = true;

            try {
                update updates;
            } finally {
                InventorySyncControl.skipOutbound = false;
            }
        }
    }

    private static Inventory__c findInventoryRow(
        String variantShopifyId,
        String inventoryItemId,
        Id locationId
    ) {
        if (locationId == null) {
            return null;
        }

        if (!String.isBlank(inventoryItemId)) {
            List<Inventory__c> byItemId = [
                SELECT Id,
                       Available__c,
                       Shopify_Inventory_Item_ID__c,
                       Shopify_Location_ID__c,
                       Inventory_Key__c,
                       Shop_Id__c,
                       Variant__c,
                       Location__c
                FROM Inventory__c
                WHERE Shopify_Inventory_Item_ID__c = :inventoryItemId
                AND Location__c = :locationId
                LIMIT 1
            ];

            if (!byItemId.isEmpty()) {
                return byItemId[0];
            }
        }

        if (!String.isBlank(variantShopifyId)) {
            List<Inventory__c> byShopId = [
                SELECT Id,
                       Available__c,
                       Shopify_Inventory_Item_ID__c,
                       Shopify_Location_ID__c,
                       Inventory_Key__c,
                       Shop_Id__c,
                       Variant__c,
                       Location__c
                FROM Inventory__c
                WHERE Shop_Id__c = :variantShopifyId
                AND Location__c = :locationId
                LIMIT 1
            ];

            if (!byShopId.isEmpty()) {
                return byShopId[0];
            }

            List<Inventory__c> byVariant = [
                SELECT Id,
                       Available__c,
                       Shopify_Inventory_Item_ID__c,
                       Shopify_Location_ID__c,
                       Inventory_Key__c,
                       Shop_Id__c,
                       Variant__c,
                       Location__c
                FROM Inventory__c
                WHERE Variant__r.Shop_Id__c = :variantShopifyId
                AND Location__c = :locationId
                LIMIT 1
            ];

            if (!byVariant.isEmpty()) {
                return byVariant[0];
            }
        }

        return null;
    }

    private static DeductionLocation getInventoryLocationForShopify() {
        List<String> orderTypes = new List<String>{
            ORDER_TYPE_SHOPIFY,
            ORDER_TYPE_SHOPIFY_ORDER
        };

        List<Inventory_Rules__mdt> rules = [
            SELECT DeveloperName,
                   Order_Type__c,
                   Location__c
            FROM Inventory_Rules__mdt
            WHERE Order_Type__c IN :orderTypes
        ];

        if (rules.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'No Inventory Rules metadata found for Shopify / Shopify Order.'
            );
            return null;
        }

        Inventory_Rules__mdt selectedRule;

        for (String orderType : orderTypes) {
            for (Inventory_Rules__mdt rule : rules) {
                if (rule.Order_Type__c == orderType) {
                    selectedRule = rule;
                    break;
                }
            }

            if (selectedRule != null) {
                break;
            }
        }

        if (selectedRule == null) {
            selectedRule = rules[0];
        }

        String locationName = selectedRule.Location__c;

        if (String.isBlank(locationName)) {
            System.debug(
                LoggingLevel.WARN,
                'Inventory Rules metadata has blank Location__c for orderType=' +
                selectedRule.Order_Type__c
            );
            return null;
        }

        List<SObject> locationRows = Database.query(
            'SELECT Id, Name FROM Location WHERE Name = \'' +
            String.escapeSingleQuotes(locationName) +
            '\' LIMIT 1'
        );

        if (locationRows.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'No Salesforce Location found for Inventory Rules location. ' +
                'orderType=' + selectedRule.Order_Type__c +
                ', locationName=' + locationName
            );
            return null;
        }

        SObject locationRow = locationRows[0];

        DeductionLocation result = new DeductionLocation();
        result.locationId = (Id) locationRow.get('Id');
        result.locationName = (String) locationRow.get('Name');

        return result;
    }

    private static String normalizeShopifyId(Object rawValue) {
        if (rawValue == null) {
            return null;
        }

        String value = String.valueOf(rawValue).trim();

        if (String.isBlank(value)) {
            return null;
        }

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

    private class DeductionLocation {
        Id locationId;
        String locationName;
    }
}