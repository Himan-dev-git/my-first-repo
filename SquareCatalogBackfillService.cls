public without sharing class SquareCatalogBackfillService {

    public static void backfillSquareIdsBySku() {

        Map<String, Object> response =
            SquareApiClient.searchCatalogItemVariations();

        List<Object> objects = (List<Object>) response.get('objects');

        if (objects == null || objects.isEmpty()) {
            System.debug('No Square variations returned.');
            return;
        }

        Map<String, SquareSkuMatch> matchBySku =
            new Map<String, SquareSkuMatch>();

        Set<String> duplicateSkus = new Set<String>();

        for (Object rawObj : objects) {
            Map<String, Object> obj = (Map<String, Object>) rawObj;

            String variationId = (String) obj.get('id');

            Map<String, Object> variationData =
                (Map<String, Object>) obj.get('item_variation_data');

            if (String.isBlank(variationId) || variationData == null) {
                continue;
            }

            String sku = (String) variationData.get('sku');
            String itemId = (String) variationData.get('item_id');

            if (String.isBlank(sku) || String.isBlank(itemId)) {
                continue;
            }

            String skuKey = sku.trim().toUpperCase();

            if (matchBySku.containsKey(skuKey)) {
                duplicateSkus.add(skuKey);
                continue;
            }

            SquareSkuMatch match = new SquareSkuMatch();
            match.itemId = itemId;
            match.variationId = variationId;

            matchBySku.put(skuKey, match);
        }

        if (!duplicateSkus.isEmpty()) {
            System.debug(
                LoggingLevel.ERROR,
                'Duplicate SKUs found in Square. These were skipped: ' +
                duplicateSkus
            );
        }

        if (matchBySku.isEmpty()) {
            System.debug('No unique Square variations with SKU found.');
            return;
        }

        List<Product2> variants = [
            SELECT Id,
                   Name,
                   StockKeepingUnit,
                   Parent__c,
                   Square_Catalog_Variation_Id__c,
                   Parent__r.Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Type__c = 'Variant'
            AND StockKeepingUnit != null
            AND Parent__c != null
        ];

        List<Product2> variantUpdates = new List<Product2>();
        Map<Id, Product2> parentUpdatesById = new Map<Id, Product2>();

        for (Product2 v : variants) {
            String skuKey = v.StockKeepingUnit == null
                ? null
                : v.StockKeepingUnit.trim().toUpperCase();

            if (String.isBlank(skuKey)) {
                continue;
            }

            if (!matchBySku.containsKey(skuKey)) {
                continue;
            }

            if (duplicateSkus.contains(skuKey)) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Skipped SKU because duplicate exists in Square: ' +
                    skuKey +
                    ', Salesforce Variant=' +
                    v.Id
                );
                continue;
            }

            SquareSkuMatch match = matchBySku.get(skuKey);

            if (v.Square_Catalog_Variation_Id__c != match.variationId) {
                variantUpdates.add(
                    new Product2(
                        Id = v.Id,
                        Square_Catalog_Variation_Id__c = match.variationId
                    )
                );
            }

            if (
                v.Parent__c != null &&
                v.Parent__r.Square_Catalog_Item_Id__c != match.itemId
            ) {
                parentUpdatesById.put(
                    v.Parent__c,
                    new Product2(
                        Id = v.Parent__c,
                        Square_Catalog_Item_Id__c = match.itemId
                    )
                );
            }
        }

        System.debug(
            'Square parent item backfill updates: ' +
            parentUpdatesById.values()
        );

        System.debug(
            'Square variation backfill updates: ' +
            variantUpdates
        );

        if (!parentUpdatesById.isEmpty()) {
            update parentUpdatesById.values();
        }

        if (!variantUpdates.isEmpty()) {
            update variantUpdates;
        }
    }

    private class SquareSkuMatch {
        String itemId;
        String variationId;
    }
}