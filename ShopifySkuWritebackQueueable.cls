public with sharing class ShopifySkuWritebackQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> variantIds;

    public ShopifySkuWritebackQueueable(List<Id> variantIds) {
        this.variantIds = variantIds;
    }

    public void execute(QueueableContext context) {
        if (variantIds == null || variantIds.isEmpty()) {
            return;
        }

        List<Product2> sfVariants = [
            SELECT Id, Shop_Id__c, StockKeepingUnit, Parent__c, Parent__r.Shop_Id__c
            FROM Product2
            WHERE Id IN :variantIds
        ];

        for (Product2 v : sfVariants) {
            if (v == null) continue;
            if (String.isBlank(v.Shop_Id__c)) continue;
            if (String.isBlank(v.StockKeepingUnit)) continue;
            if (v.Parent__r == null || String.isBlank(v.Parent__r.Shop_Id__c)) continue;

            String mutation =
                'mutation productVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {' +
                '  productVariantsBulkUpdate(productId: $productId, variants: $variants) {' +
                '    product { id }' +
                '    productVariants { id title sku }' +
                '    userErrors { field message }' +
                '  }' +
                '}';

            Map<String, Object> variantInput = new Map<String, Object>{
                'id'            => ShopifyGraphQLHelper.toVariantGid(v.Shop_Id__c),
                'inventoryItem' => new Map<String, Object>{ 'sku' => v.StockKeepingUnit }
            };

            try {
                Map<String, Object> response = ShopifyGraphQLHelper.execute(
                    mutation,
                    new Map<String, Object>{
                        'productId' => ShopifyGraphQLHelper.toProductGid(v.Parent__r.Shop_Id__c),
                        'variants'  => new List<Object>{ variantInput }
                    }
                );

                validateUserErrors(response, 'productVariantsBulkUpdate');

                System.debug(
                    LoggingLevel.INFO,
                    'ShopifySkuWritebackQueueable: SKU "' + v.StockKeepingUnit +
                    '" pushed to Shopify for variant ' + v.Shop_Id__c
                );
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'ShopifySkuWritebackQueueable: Failed to push SKU "' +
                    v.StockKeepingUnit + '" to Shopify for variant ' +
                    v.Shop_Id__c + ': ' + e.getMessage()
                );
            }
        }
    }

    @TestVisible
    private static void validateUserErrors(Map<String, Object> response, String mutationName) {
        if (response == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException(
                'Missing Shopify response.'
            );
        }

        if (!response.containsKey('data') || response.get('data') == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException(
                'Missing data from Shopify response.'
            );
        }

        Map<String, Object> data = (Map<String, Object>) response.get('data');

        if (!data.containsKey(mutationName) || data.get(mutationName) == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException(
                'Missing mutation result from Shopify response for ' + mutationName + '.'
            );
        }

        Map<String, Object> mutationResult = (Map<String, Object>) data.get(mutationName);
        List<Object> userErrors = (List<Object>) mutationResult.get('userErrors');

        if (userErrors != null && !userErrors.isEmpty()) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException(
                mutationName + ' userErrors: ' + JSON.serialize(userErrors)
            );
        }
    }
}