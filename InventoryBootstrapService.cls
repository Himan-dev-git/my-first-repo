public without sharing class InventoryBootstrapService {

    public static void populateMappings(List<Inventory__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }

        Set<Id> variantIds = new Set<Id>();
        Set<Id> locationIds = new Set<Id>();

        for (Inventory__c row : rows) {
            if (row.Variant__c != null) {
                variantIds.add(row.Variant__c);
            }

            if (row.Location__c != null) {
                locationIds.add(row.Location__c);
            }
        }

        Map<Id, Product2> variantsById = new Map<Id, Product2>();

        if (!variantIds.isEmpty()) {
            variantsById = new Map<Id, Product2>([
                SELECT Id,
                       Shop_ID__c,
                       Inventory_Item_Id__c
                FROM Product2
                WHERE Id IN :variantIds
            ]);
        }

        Map<Id, SObject> locationsById = new Map<Id, SObject>();

        if (!locationIds.isEmpty()) {
            for (SObject locationRow : Database.query(
                'SELECT Id, Shopify_Location_ID__c FROM Location WHERE Id IN :locationIds'
            )) {
                locationsById.put((Id) locationRow.get('Id'), locationRow);
            }
        }

        Map<String, Schema.SObjectField> inventoryFields =
            Inventory__c.SObjectType.getDescribe().fields.getMap();

        for (Inventory__c row : rows) {
            Product2 variant = row.Variant__c == null
                ? null
                : variantsById.get(row.Variant__c);

            SObject locationRow = row.Location__c == null
                ? null
                : locationsById.get(row.Location__c);

            if (locationRow != null) {
                String shopifyLocationId =
                    (String) locationRow.get('Shopify_Location_ID__c');

                if (!String.isBlank(shopifyLocationId)) {
                    row.Shopify_Location_ID__c = shopifyLocationId;
                }
            }

            if (variant != null) {
                if (!String.isBlank(variant.Inventory_Item_Id__c)) {
                    row.Shopify_Inventory_Item_ID__c = variant.Inventory_Item_Id__c;
                }

                if (inventoryFields.containsKey('Shop_ID__c') &&
                    !String.isBlank(variant.Shop_ID__c)) {
                    row.put('Shop_ID__c', variant.Shop_ID__c);
                }

                if (!String.isBlank(variant.Shop_ID__c) &&
                    !String.isBlank(row.Shopify_Location_ID__c)) {
                    row.Inventory_Key__c =
                        variant.Shop_ID__c + '-' + row.Shopify_Location_ID__c;
                } else if (row.Variant__c != null && row.Location__c != null) {
                    row.Inventory_Key__c =
                        String.valueOf(row.Variant__c) + '-' + String.valueOf(row.Location__c);
                }
            }

            if (String.isBlank(row.Sync_Status__c)) {
                row.Sync_Status__c = 'Success';
            }
        }
    }
}