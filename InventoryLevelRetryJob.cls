public without sharing class InventoryLevelRetryJob
    implements Queueable, Database.AllowsCallouts {

    private String inventoryItemId;
    private String shopifyLocationId;
    private Decimal availableQty;
    private Integer attempt;

    /*
     * Allows tests to replace the actual Queueable enqueue operation.
     */
    @TestVisible
    private static RetryScheduler retryScheduler =
        new DefaultRetryScheduler();

    public interface RetryScheduler {
        void schedule(
            String inventoryItemId,
            String shopifyLocationId,
            Decimal availableQty,
            Integer nextAttempt
        );
    }

    private class DefaultRetryScheduler
        implements RetryScheduler {

        public void schedule(
            String inventoryItemId,
            String shopifyLocationId,
            Decimal availableQty,
            Integer nextAttempt
        ) {
            System.enqueueJob(
                new InventoryLevelRetryJob(
                    inventoryItemId,
                    shopifyLocationId,
                    availableQty,
                    nextAttempt
                )
            );
        }
    }

    public InventoryLevelRetryJob(
        String inventoryItemId,
        String shopifyLocationId,
        Decimal availableQty,
        Integer attempt
    ) {
        this.inventoryItemId = inventoryItemId;
        this.shopifyLocationId = shopifyLocationId;
        this.availableQty = availableQty;
        this.attempt = attempt;
    }

    public void execute(QueueableContext qc) {
        Product2 variant = findVariant();

        if (variant == null && attempt < 3) {
            retryScheduler.schedule(
                inventoryItemId,
                shopifyLocationId,
                availableQty,
                attempt + 1
            );

            return;
        }

        if (variant == null) {
            System.debug(
                'Inventory retry failed. No variant found for inventory item ' +
                inventoryItemId
            );

            return;
        }

        Id sfLocationId =
            ShopifyLocationGraphQLService.getOrCreateSalesforceLocation(
                    shopifyLocationId
                );

        String inventoryKey =
            variant.Shop_ID__c +
            '-' +
            shopifyLocationId;

        Inventory__c inv =
            new Inventory__c();

        inv.Variant__c =
            variant.Id;

        inv.Location__c =
            sfLocationId;
        
        /*
* New inventory row baseline:
* Shopify Available and Salesforce Available start equal.
* Future Square/manual sales will change Salesforce_Available__c only.
*/
        inv.Salesforce_Available__c =
            availableQty;
        
        inv.Shopify_Inventory_Item_ID__c =
            inventoryItemId;

        inv.Shopify_Location_ID__c =
            shopifyLocationId;

        inv.Inventory_Key__c =
            inventoryKey;

        inv.Sync_Status__c =
            'Success';

        inv.Last_Sync_At__c =
            System.now();

        if (
            Inventory__c.SObjectType
                .getDescribe()
                .fields
                .getMap()
                .containsKey('Shop_ID__c')
        ) {
            inv.put(
                'Shop_ID__c',
                variant.Shop_ID__c
            );
        }

        InventorySyncControl.skipOutbound =
            true;

        try {
            upsert inv Inventory_Key__c;
        } finally {
            InventorySyncControl.skipOutbound =
                false;
        }
    }

    private Product2 findVariant() {
        List<Product2> variants = [
            SELECT Id,
                   Shop_ID__c,
                   Inventory_Item_Id__c
            FROM Product2
            WHERE Inventory_Item_Id__c =
                :inventoryItemId
            LIMIT 1
        ];

        return variants.isEmpty()
            ? null
            : variants[0];
    }
}