public class ProductTriggerHandler {

    public static void handleAfterInsert(List<Product2> newProducts) {
        if (newProducts == null || newProducts.isEmpty()) {
            return;
        }

        if (System.isFuture() || System.isBatch() || System.isQueueable()) {
            return;
        }

        // Do not send outbound sync for inbound Shopify webhook transactions.
        // Replace this with your exact integration username if needed.
        if (isShopifyIntegrationUser()) {
            return;
        }

        Set<Id> productIdsToSync = new Set<Id>();

        for (Product2 p : newProducts) {
            if (p == null) {
                continue;
            }

            // Do not use Updated_by_Integration__c as a permanent hard stop.
            // A Shopify-originated product may still be manually edited later
            // and should then sync back to Shopify.
            productIdsToSync.add(p.Id);
        }

        if (!productIdsToSync.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                'ProductTriggerHandler.handleAfterInsert syncing products => ' + productIdsToSync
            );

            ShopifyProductGraphQLService.syncProductsAsync(new List<Id>(productIdsToSync));
        }
    }

    public static void handleAfterUpdate(List<Product2> newProducts, Map<Id, Product2> oldProductsMap) {
        if (newProducts == null || newProducts.isEmpty() || oldProductsMap == null) {
            return;
        }

        if (System.isFuture() || System.isBatch() || System.isQueueable()) {
            return;
        }

        // Do not send outbound sync for inbound Shopify webhook transactions.
        // This prevents Shopify -> Salesforce -> Shopify loops.
        if (isShopifyIntegrationUser()) {
            return;
        }

        Set<Id> productIdsToSync = new Set<Id>();

        for (Product2 newProduct : newProducts) {
            if (newProduct == null) {
                continue;
            }

            Product2 oldProduct = oldProductsMap.get(newProduct.Id);

            if (oldProduct == null) {
                continue;
            }

            Map<String, String> changedFieldsMap =
                Utilities.getChangedFieldsMap(newProduct, oldProduct);

            // Ignore technical fields
            changedFieldsMap.remove('Shop_ID__c');
            changedFieldsMap.remove('Shop_Id__c');
            changedFieldsMap.remove('Updated_by_Integration__c');
            changedFieldsMap.remove('LastModifiedDate');
            changedFieldsMap.remove('SystemModstamp');
            changedFieldsMap.remove('LastModifiedById');

            // Optional: keep outbound product sync focused only on fields Shopify can receive.
            // Add/remove fields here as needed.
            Set<String> outboundRelevantFields = new Set<String>{
                'Name',
                'Family',
                'Description',
                'IsActive',
                'Material__c',
                'StockKeepingUnit'
            };

            Boolean hasOutboundRelevantChange = false;

            for (String changedField : changedFieldsMap.keySet()) {
                if (outboundRelevantFields.contains(changedField)) {
                    hasOutboundRelevantChange = true;
                    break;
                }
            }

            if (hasOutboundRelevantChange) {
                productIdsToSync.add(newProduct.Id);
            }
        }

        if (!productIdsToSync.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                'ProductTriggerHandler.handleAfterUpdate syncing products => ' + productIdsToSync
            );

            ShopifyProductGraphQLService.syncProductsAsync(new List<Id>(productIdsToSync));
        }
    }

    private static Boolean isShopifyIntegrationUser() {
        String userName = UserInfo.getUserName();

        return userName != null &&
            userName.toLowerCase().contains('shopify_webhook_site');
    }
}