public with sharing class ShopifyInventorySyncService {
    
    /*
 * NOTE:
 * This service updates Shopify inventory from Salesforce.
 * It is intentionally no longer called automatically by InventoryTriggerHandler.
 *
 * Under the new inventory model, this should only be used later from a
 * manual/admin-approved action if the business decides to correct Shopify
 * from Salesforce.
 */

    @future(callout=true)
    public static void syncInventoryRowsAsync(List<Id> ids) {
        if (ids == null || ids.isEmpty()) return;

        List<Inventory__c> rows = [
            SELECT Id,
                   Available__c,
                   Shopify_Inventory_Item_ID__c,
                   Shopify_Location_ID__c,
                   Variant__c,
                   Variant__r.Shop_Id__c,
                   Sync_Status__c
            FROM Inventory__c
            WHERE Id IN :ids
        ];

        List<Inventory__c> updates = new List<Inventory__c>();

        for (Inventory__c r : rows) {
            String inventoryItemId = r.Shopify_Inventory_Item_ID__c;
            Decimal currentShopifyQty = null;

            try {
                // Always resolve via Shopify to get the current live quantity.
                // This gives us both the inventoryItemId (if missing) AND
                // the currentAvailable needed for changeFromQty in the mutation.
                ShopifyInventoryLookupService.VariantInventoryContext ctx =
                    ShopifyInventoryLookupService.resolveVariantLocationContext(
                        r.Variant__r.Shop_ID__c,
                        r.Shopify_Location_ID__c
                    );

                if (ctx == null) {
                    throw new ShopifyInventorySyncException(
                        'resolveVariantLocationContext returned null for record ' + r.Id
                    );
                }

                // If the inventory item ID was missing on the record, populate it now
                if (String.isBlank(inventoryItemId) && !String.isBlank(ctx.inventoryItemId)) {
                    inventoryItemId = ctx.inventoryItemId;
                }

                if (String.isBlank(inventoryItemId)) {
                    throw new ShopifyInventorySyncException(
                        'Could not resolve inventoryItemId for record ' + r.Id
                    );
                }

                currentShopifyQty = ctx.currentAvailable;

                // Call the mutation passing BOTH the new qty AND the current Shopify qty
                ShopifyInventoryMutationService.ResultWrap result =
    ShopifyInventoryMutationService.setAvailableQuantity(
        inventoryItemId,
        r.Shopify_Location_ID__c,
        r.Available__c,
        currentShopifyQty,
        'inventory-set-' + r.Id + '-' + String.valueOf(DateTime.now().getTime())
    );
                Inventory__c upd = new Inventory__c();
                upd.Id                              = r.Id;
                upd.Shopify_Inventory_Item_ID__c    = inventoryItemId;
                upd.Last_Sync_At__c                 = System.now();
                upd.Sync_Status__c                  = result.success ? 'Success' : 'Failed';

                if (!result.success) {
                    System.debug(LoggingLevel.ERROR,
                        'Inventory sync failed for ' + r.Id + ': ' + result.message);
                }

                updates.add(upd);

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'ShopifyInventorySyncService exception for ' + r.Id + ': ' + e.getMessage());

                Inventory__c failed = new Inventory__c();
                failed.Id               = r.Id;
                failed.Sync_Status__c   = 'Failed';
                failed.Last_Sync_At__c  = System.now();

                // Persist the item ID even on failure if we resolved it
                if (!String.isBlank(inventoryItemId)) {
                    failed.Shopify_Inventory_Item_ID__c = inventoryItemId;
                }

                updates.add(failed);
            }
        }

        if (!updates.isEmpty()) {
            try {
                InventorySyncControl.skipOutbound = true;
                update updates;
                InventorySyncControl.skipOutbound = false;
            } catch (Exception e) {
                InventorySyncControl.skipOutbound = false;
                System.debug(LoggingLevel.ERROR,
                    'ShopifyInventorySyncService DML error: ' + e.getMessage());
            }
        }
    }

    public class ShopifyInventorySyncException extends Exception {}
}