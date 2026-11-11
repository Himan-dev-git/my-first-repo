trigger ProductCollectionTrigger on Product_Collection__c (after insert, after delete) {
    if (ShopifyCollectionGraphQLService.bypassProductCollectionTrigger) return;

    if (Trigger.isInsert) {
        for (Product_Collection__c row : Trigger.new) {
            ShopifyCollectionGraphQLService.addProductToCollectionAsync(row.Id);
        }
    }

    if (Trigger.isDelete) {
        Set<Id> productIds = new Set<Id>();
        Set<Id> collectionIds = new Set<Id>();

        for (Product_Collection__c row : Trigger.old) {
            if (row.Product__c != null) productIds.add(row.Product__c);
            if (row.Collection__c != null) collectionIds.add(row.Collection__c);
        }

        Map<Id, Product2> products = new Map<Id, Product2>([
            SELECT Id, Shop_ID__c
            FROM Product2
            WHERE Id IN :productIds
        ]);

        Map<Id, Collection__c> collections = new Map<Id, Collection__c>([
            SELECT Id, Shopify_Collection_Id__c
            FROM Collection__c
            WHERE Id IN :collectionIds
        ]);

        for (Product_Collection__c row : Trigger.old) {
            Product2 p = products.get(row.Product__c);
            Collection__c c = collections.get(row.Collection__c);

            if (p == null || c == null) continue;
            if (String.isBlank(p.Shop_ID__c) || String.isBlank(c.Shopify_Collection_Id__c)) continue;

            ShopifyCollectionGraphQLService.removeProductFromCollectionAsync(
                c.Shopify_Collection_Id__c,
                p.Shop_ID__c
            );
        }
    }
}