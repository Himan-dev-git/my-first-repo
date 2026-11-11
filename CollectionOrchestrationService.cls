public class CollectionOrchestrationService {

    public static void processCollectionWebhook(Map<String, Object> payload) {
        if (payload == null || payload.get('id') == null) return;

        String collectionShopId = String.valueOf(payload.get('id'));

        ShopifyCollectionGraphQLService.pullCollectionAsync(collectionShopId);
    }

    public static void processCollectionDeleteWebhook(Map<String, Object> payload) {
        if (payload == null || payload.get('id') == null) return;

        String collectionShopId = String.valueOf(payload.get('id'));

        List<Collection__c> cols = [
            SELECT Id
            FROM Collection__c
            WHERE Shopify_Collection_Id__c = :collectionShopId
            LIMIT 1
        ];

        if (cols.isEmpty()) return;

        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = true;

        try {
            delete [
                SELECT Id
                FROM Product_Collection__c
                WHERE Collection__c = :cols[0].Id
            ];

            delete cols[0];
        } finally {
            ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
            ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        }
    }
}