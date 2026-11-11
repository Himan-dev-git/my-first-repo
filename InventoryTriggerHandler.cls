public with sharing class InventoryTriggerHandler {

    public static void beforeSave(List<Inventory__c> newRows, Map<Id, Inventory__c> oldMap) {
        if (newRows == null || newRows.isEmpty()) {
            return;
        }

        // Keep your existing mapping logic.
        // This populates Shopify_Location_ID__c, Shopify_Inventory_Item_ID__c,
        // Inventory_Key__c, Sync_Status__c, etc.
        InventoryBootstrapService.populateMappings(newRows);

        validateOneInventoryPerVariantLocation(newRows);
    }

    public static void afterSave(List<Inventory__c> newRows, Map<Id, Inventory__c> oldMap) {
        if (InventorySyncControl.skipOutbound == true) {
            return;
        }
        
        /*
 * DISABLED FOR NEW INVENTORY MODEL.
 *
 * Salesforce should no longer automatically overwrite Shopify inventory.
 * Available__c now represents the latest Shopify available quantity snapshot.
 * Salesforce_Available__c represents the internal Salesforce inventory quantity.
 *
 * Discrepancies should be reviewed through reports/dashboards and corrected
 * manually in Shopify if required.
 *
 * Keeping the old outbound sync logic commented so it can be restored later
 * if the business decides to allow Salesforce-approved Shopify corrections.
 */
/*

        List<Id> idsToSync = new List<Id>();

        for (Inventory__c row : newRows) {
            Boolean shouldSync = false;

            if (oldMap == null || !oldMap.containsKey(row.Id)) {
                shouldSync = true;
            } else {
                Inventory__c oldRow = oldMap.get(row.Id);
                if (row.Available__c != oldRow.Available__c) {
                    shouldSync = true;
                }
            }

            if (shouldSync && isInventoryReadyForSync(row)) {
                idsToSync.add(row.Id);
            }
        }
        
        //Disable for data migration
        if (!idsToSync.isEmpty() && !System.isFuture() && !System.isBatch()) {
            ShopifyInventorySyncService.syncInventoryRowsAsync(idsToSync);
        } 
*/
    }
	
        
    private static void validateOneInventoryPerVariantLocation(List<Inventory__c> newRows) {
        Set<Id> variantIds = new Set<Id>();
        Set<Id> locationIds = new Set<Id>();
        Set<Id> currentInventoryIds = new Set<Id>();

        Map<String, Inventory__c> rowsByVariantLocationKey = new Map<String, Inventory__c>();

        for (Inventory__c row : newRows) {
            if (row.Id != null) {
                currentInventoryIds.add(row.Id);
            }

            if (row.Variant__c == null || row.Location__c == null) {
                continue;
            }

            variantIds.add(row.Variant__c);
            locationIds.add(row.Location__c);

            String key = buildVariantLocationKey(row.Variant__c, row.Location__c);

            if (rowsByVariantLocationKey.containsKey(key)) {
                row.addError(
                    'Duplicate Inventory is not allowed. Only one Inventory record can exist for the same Variant/SKU and Location.'
                );

                Inventory__c firstRow = rowsByVariantLocationKey.get(key);
                firstRow.addError(
                    'Duplicate Inventory is not allowed. Only one Inventory record can exist for the same Variant/SKU and Location.'
                );
            } else {
                rowsByVariantLocationKey.put(key, row);
            }
        }

        if (variantIds.isEmpty() || locationIds.isEmpty()) {
            return;
        }

        List<Inventory__c> existingRows = [
            SELECT Id,
                   Name,
                   Variant__c,
                   Location__c,
                   Variant__r.Name,
                   Location__r.Name
            FROM Inventory__c
            WHERE Variant__c IN :variantIds
            AND Location__c IN :locationIds
        ];

        Map<String, Inventory__c> existingByVariantLocationKey = new Map<String, Inventory__c>();

        for (Inventory__c existingRow : existingRows) {
            if (existingRow.Variant__c == null || existingRow.Location__c == null) {
                continue;
            }

            if (currentInventoryIds.contains(existingRow.Id)) {
                continue;
            }

            String key = buildVariantLocationKey(existingRow.Variant__c, existingRow.Location__c);

            if (!existingByVariantLocationKey.containsKey(key)) {
                existingByVariantLocationKey.put(key, existingRow);
            }
        }

        for (Inventory__c row : newRows) {
            if (row.Variant__c == null || row.Location__c == null) {
                continue;
            }

            String key = buildVariantLocationKey(row.Variant__c, row.Location__c);

            if (existingByVariantLocationKey.containsKey(key)) {
                Inventory__c existingRow = existingByVariantLocationKey.get(key);

                row.addError(
                    'Duplicate Inventory is not allowed. An Inventory record already exists for this Variant/SKU and Location. ' +
                    'Existing Inventory: ' + existingRow.Name
                );
            }
        }
    }

    private static String buildVariantLocationKey(Id variantId, Id locationId) {
        return String.valueOf(variantId) + '-' + String.valueOf(locationId);
    }

    private static Boolean isInventoryReadyForSync(Inventory__c row) {
        return row.Variant__c != null &&
               row.Location__c != null &&
               !String.isBlank(row.Shopify_Location_ID__c) &&
               row.Available__c != null;
    }
}