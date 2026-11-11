public without sharing class SquarePricebookSyncQueueable implements Queueable, Database.AllowsCallouts {

    public void execute(QueueableContext context) {

        // ── Step 1: Callout — fetch all ITEM_VARIATION objects from Square ───
        Map<String, Object> catalogResponse;
        try {
            catalogResponse = SquareApiClient.searchCatalogItemVariations();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SquarePricebookSyncQueueable: catalog fetch failed — ' +
                e.getMessage());
            return;
        }

        if (catalogResponse == null || !catalogResponse.containsKey('objects')) {
            System.debug(LoggingLevel.WARN,
                'SquarePricebookSyncQueueable: no catalog objects returned.');
            return;
        }

        List<Object> objects = (List<Object>) catalogResponse.get('objects');
        if (objects == null || objects.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'SquarePricebookSyncQueueable: catalog objects list is empty.');
            return;
        }

        // ── Step 2: Parse — collect all (variationId, price) per SKU ─────────
        // Collect ALL occurrences first so we can resolve duplicates
        // using the Salesforce-stored variation ID
        Map<String, List<Object[]>> skuToAllVariations =
            new Map<String, List<Object[]>>();

        for (Object obj : objects) {
            Map<String, Object> variation = (Map<String, Object>) obj;
            if (variation == null) continue;

            String variationId = (String) variation.get('id');
            if (String.isBlank(variationId)) continue;

            Map<String, Object> variationData =
                variation.containsKey('item_variation_data')
                    ? (Map<String, Object>) variation.get('item_variation_data')
                    : null;
            if (variationData == null) continue;

            String sku = (String) variationData.get('sku');
            if (String.isBlank(sku)) continue;

            String skuKey = sku.trim().toUpperCase();

            Map<String, Object> priceMoney =
                variationData.containsKey('price_money')
                    ? (Map<String, Object>) variationData.get('price_money')
                    : null;
            if (priceMoney == null || priceMoney.get('amount') == null) continue;

            Decimal price =
                Decimal.valueOf(String.valueOf(priceMoney.get('amount'))) / 100;
            if (price <= 0) continue;

            if (!skuToAllVariations.containsKey(skuKey)) {
                skuToAllVariations.put(skuKey, new List<Object[]>());
            }
            skuToAllVariations.get(skuKey).add(
                new Object[]{ variationId, price }
            );
        }

        if (skuToAllVariations.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'SquarePricebookSyncQueueable: no SKUs with fixed prices found.');
            return;
        }

        // ── Step 3: SOQL — load Salesforce variation IDs to resolve dupes ────
        Map<String, String> sfSkuToVariationId = new Map<String, String>();
        for (Product2 p : [
            SELECT StockKeepingUnit, Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE StockKeepingUnit != null
            AND StockKeepingUnit != ''
        ]) {
            String k = p.StockKeepingUnit.trim().toUpperCase();
            if (!String.isBlank(p.Square_Catalog_Variation_Id__c)) {
                sfSkuToVariationId.put(k, p.Square_Catalog_Variation_Id__c);
            }
        }

        // ── Step 4: Resolve — one price + one variationId per SKU ────────────
        Map<String, Decimal> skuToPriceMap    = new Map<String, Decimal>();
        Map<String, String>  skuToSquareVarId = new Map<String, String>();

        for (String skuKey : skuToAllVariations.keySet()) {
            List<Object[]> candidates = skuToAllVariations.get(skuKey);

            if (candidates.size() == 1) {
                skuToPriceMap.put(skuKey,    (Decimal) candidates[0][1]);
                skuToSquareVarId.put(skuKey, (String)  candidates[0][0]);
            } else {
                String  sfVarId  = sfSkuToVariationId.get(skuKey);
                Boolean resolved = false;

                for (Object[] c : candidates) {
                    if ((String) c[0] == sfVarId) {
                        skuToPriceMap.put(skuKey,    (Decimal) c[1]);
                        skuToSquareVarId.put(skuKey, (String)  c[0]);
                        resolved = true;
                        System.debug(LoggingLevel.INFO,
                            'Duplicate SKU ' + skuKey +
                            ': resolved via SF variation ID → £' + c[1]);
                        break;
                    }
                }

                if (!resolved) {
                    Object[] last = candidates[candidates.size() - 1];
                    skuToPriceMap.put(skuKey,    (Decimal) last[1]);
                    skuToSquareVarId.put(skuKey, (String)  last[0]);
                    System.debug(LoggingLevel.WARN,
                        'Duplicate SKU ' + skuKey +
                        ': no SF variation ID match — using last candidate £' +
                        last[1]);
                }
            }
        }

        System.debug(LoggingLevel.INFO,
            'SquarePricebookSyncQueueable: ' + skuToPriceMap.size() +
            ' SKUs resolved from Square: ' + skuToPriceMap.keySet());

        // ── Step 5: SOQL — find Square Pricebook ─────────────────────────────
        List<Pricebook2> squarePbs = [
            SELECT Id FROM Pricebook2
            WHERE Name = 'Square Pricebook'
            AND IsActive = true
            LIMIT 1
        ];
        if (squarePbs.isEmpty()) {
            System.debug(LoggingLevel.ERROR,
                'SquarePricebookSyncQueueable: Square Pricebook not found.');
            return;
        }
        Id squarePricebookId = squarePbs[0].Id;

        // ── Step 6: SOQL — match Product2 records by SKU ─────────────────────
        List<Product2> matchedVariants = new List<Product2>();
        for (Product2 p : [
            SELECT Id, StockKeepingUnit, Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE StockKeepingUnit != null
            AND StockKeepingUnit != ''
        ]) {
            String key = p.StockKeepingUnit.trim().toUpperCase();
            if (skuToPriceMap.containsKey(key)) {
                matchedVariants.add(p);
            }
        }

        if (matchedVariants.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'SquarePricebookSyncQueueable: no matching Product2 records. ' +
                'Ensure variants have StockKeepingUnit populated.');
            return;
        }

        System.debug(LoggingLevel.INFO,
            'SquarePricebookSyncQueueable: matched ' +
            matchedVariants.size() + ' Product2 variants.');

        // Build lookup maps
        Set<Id>         variantIds     = new Set<Id>();
        Map<Id, String> variantIdToSku = new Map<Id, String>();
        for (Product2 v : matchedVariants) {
            variantIds.add(v.Id);
            variantIdToSku.put(v.Id, v.StockKeepingUnit.trim().toUpperCase());
        }

        // ── Step 7: SOQL — find existing Square Pricebook entries ────────────
        // Order DESC by LastModifiedDate so the newest record comes first
        // when there are duplicates per product
        List<PricebookEntry> existingEntries = [
            SELECT Id, Product2Id, UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :squarePricebookId
            AND Product2Id IN :variantIds
            ORDER BY Product2Id, LastModifiedDate DESC
        ];

        // ── Step 8: DML — update prices ──────────────────────────────────────
        // CRITICAL: build a CLEAN new PricebookEntry with only Id + UnitPrice
        // Do NOT pass the queried record directly — doing so carries the
        // cross-object Product2Id relationship field which causes:
        // CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY: Product2Id inaccessible
        List<PricebookEntry> entriesToUpdate   = new List<PricebookEntry>();
        Set<Id>              variantsProcessed = new Set<Id>();
        List<Id>             duplicatesToDelete = new List<Id>();

        for (PricebookEntry pbe : existingEntries) {
            if (variantsProcessed.contains(pbe.Product2Id)) {
                // Duplicate — keep only the newest, delete older ones
                duplicatesToDelete.add(pbe.Id);
                continue;
            }
            variantsProcessed.add(pbe.Product2Id);

            String  sku      = variantIdToSku.get(pbe.Product2Id);
            Decimal newPrice = skuToPriceMap.get(sku);

            if (newPrice != null && pbe.UnitPrice != newPrice) {
                // ✅ Clean record — only Id and fields being changed
                // This avoids the Product2Id inaccessible error
                entriesToUpdate.add(new PricebookEntry(
                    Id               = pbe.Id,
                    UnitPrice        = newPrice,
                    UseStandardPrice = false,
                    IsActive         = true
                ));
                System.debug(LoggingLevel.INFO,
                    'SquarePricebookSyncQueueable: queued update SKU=' + sku +
                    ' £' + pbe.UnitPrice + ' → £' + newPrice);
            }
        }

        // Delete duplicates first
        if (!duplicatesToDelete.isEmpty()) {
            Database.delete(duplicatesToDelete, false);
            System.debug(LoggingLevel.WARN,
                'SquarePricebookSyncQueueable: deleted ' +
                duplicatesToDelete.size() + ' duplicate pricebook entries.');
        }

        // Update prices
        if (!entriesToUpdate.isEmpty()) {
            Database.SaveResult[] results =
                Database.update(entriesToUpdate, false);
            Integer successCount = 0;
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    successCount++;
                } else {
                    System.debug(LoggingLevel.ERROR,
                        'PricebookEntry update failed: ' + sr.getErrors());
                }
            }
            System.debug(LoggingLevel.INFO,
                'SquarePricebookSyncQueueable: updated ' +
                successCount + ' of ' + entriesToUpdate.size() +
                ' pricebook entries.');
        } else {
            System.debug(LoggingLevel.INFO,
                'SquarePricebookSyncQueueable: all prices already up to date.');
        }

        // ── Step 9: DML — insert entries for products not yet in pricebook ───
        List<PricebookEntry> entriesToInsert = new List<PricebookEntry>();
        for (Product2 v : matchedVariants) {
            if (variantsProcessed.contains(v.Id)) continue;

            String  skuKey   = v.StockKeepingUnit.trim().toUpperCase();
            Decimal newPrice = skuToPriceMap.get(skuKey);
            if (newPrice == null) continue;

            entriesToInsert.add(new PricebookEntry(
                Pricebook2Id     = squarePricebookId,
                Product2Id       = v.Id,
                UnitPrice        = newPrice,
                IsActive         = true,
                UseStandardPrice = false
            ));
            System.debug(LoggingLevel.INFO,
                'SquarePricebookSyncQueueable: inserting new entry SKU=' +
                skuKey + ' £' + newPrice);
        }

        if (!entriesToInsert.isEmpty()) {
            Database.SaveResult[] results =
                Database.insert(entriesToInsert, false);
            Integer successCount = 0;
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    successCount++;
                } else {
                    System.debug(LoggingLevel.ERROR,
                        'PricebookEntry insert failed: ' + sr.getErrors());
                }
            }
            System.debug(LoggingLevel.INFO,
                'SquarePricebookSyncQueueable: inserted ' +
                successCount + ' new pricebook entries.');
        }

        // ── Step 10: DML — update Square_Catalog_Variation_Id__c if changed ──
        List<Product2> variantsToUpdate = new List<Product2>();
        for (Product2 v : matchedVariants) {
            String skuKey      = v.StockKeepingUnit.trim().toUpperCase();
            String squareVarId = skuToSquareVarId.get(skuKey);
            if (!String.isBlank(squareVarId) &&
                    v.Square_Catalog_Variation_Id__c != squareVarId) {
                variantsToUpdate.add(new Product2(
                    Id = v.Id,
                    Square_Catalog_Variation_Id__c = squareVarId
                ));
            }
        }
        if (!variantsToUpdate.isEmpty()) {
            Database.update(variantsToUpdate, false);
            System.debug(LoggingLevel.INFO,
                'SquarePricebookSyncQueueable: updated variation IDs on ' +
                variantsToUpdate.size() + ' products.');
        }

        System.debug(LoggingLevel.INFO,
            'SquarePricebookSyncQueueable: sync complete.');
    }
}