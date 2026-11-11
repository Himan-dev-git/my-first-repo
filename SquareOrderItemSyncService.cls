public without sharing class SquareOrderItemSyncService {

    /**
     * Synchronizes Square order lines to Salesforce OrderItems.
     *
     * Matching order:
     * 1. Square catalog variation/item ID
     * 2. SKU
     * 3. Exact normalized Product2.Name fallback, constrained to active
     *    PricebookEntry records in the Square Pricebook. If multiple products
     *    remain, Square line price is used only when it selects one uniquely.
     *
     * Idempotency:
     * - Does not stop merely because the Order already has an OrderItem.
     * - Existing OrderItems are matched by Product2 and updated.
     * - Missing products are inserted.
     * - Multiple Square lines resolving to the same Product2 are consolidated
     *   into one OrderItem because this implementation does not currently store
     *   a Square line-item UID on OrderItem.
     */
    /**
     * Backward-compatible entry point for callers that do not pass a provider
     * Customer Id.
     */
    public static void syncOrderItems(
        Id orderId,
        Map<String, Object> squareOrder,
        Id squarePricebookId
    ) {
        syncOrderItemsInternal(orderId, squareOrder, squarePricebookId, null);
    }

    /**
     * Preferred entry point. Pass the resolved Pop-up Provider Customer Id so
     * each OrderItem gets the same provider Customer lookup as its parent Order.
     */
    public static void syncOrderItems(
        Id orderId,
        Map<String, Object> squareOrder,
        Id squarePricebookId,
        Id popUpProviderCustomerId
    ) {
        syncOrderItemsInternal(
            orderId,
            squareOrder,
            squarePricebookId,
            popUpProviderCustomerId
        );
    }

    /**
     * Compatibility entry point for callers passing a String. The String is
     * treated strictly as a Square Location ID; it is never a location name.
     */
    public static void syncOrderItems(
        Id orderId,
        Map<String, Object> squareOrder,
        Id squarePricebookId,
        String squareLocationId
    ) {
        Id providerCustomerId = String.isBlank(squareLocationId)
            ? null
            : SquarePopUpAccountService.getPopUpProviderCustomerId(squareLocationId);
        syncOrderItemsInternal(orderId, squareOrder, squarePricebookId, providerCustomerId);
    }

    /** Core implementation shared by both public entry points. */
    private static void syncOrderItemsInternal(
        Id orderId,
        Map<String, Object> squareOrder,
        Id squarePricebookId,
        Id popUpProviderCustomerId
    ) {
        if (orderId == null || squareOrder == null || squarePricebookId == null) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderItemSyncService: required input missing. ' +
                'orderId=' + orderId + ', squareOrderNull=' + (squareOrder == null) +
                ', squarePricebookId=' + squarePricebookId
            );
            return;
        }

        // On webhook retries or legacy three-argument calls, reuse the Customer
        // lookup already resolved and stored on the parent Order.
        if (popUpProviderCustomerId == null) {
            popUpProviderCustomerId = getProviderCustomerIdFromOrder(orderId);
        }

        List<SquareLineItem> lineItems = parseLineItems(squareOrder);
        if (lineItems.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                'SquareOrderItemSyncService: no Square line_items found. orderId=' + orderId
            );
            return;
        }

        Set<String> skus = new Set<String>();
        Set<String> catalogIds = new Set<String>();
        Set<String> productNames = new Set<String>();

        for (SquareLineItem li : lineItems) {
            if (String.isNotBlank(li.sku)) {
                skus.add(li.sku.trim());
            }
            if (String.isNotBlank(li.catalogVariationId)) {
                catalogIds.add(li.catalogVariationId.trim());
            }
            if (String.isNotBlank(li.name)) {
                productNames.add(li.name.trim());
            }
        }

        ProductMatchResult productMatches = findMatchingProducts(
            skus,
            catalogIds,
            productNames
        );

        if (productMatches.productIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderItemSyncService: no Salesforce products matched by catalog ID, SKU, or name. ' +
                'orderId=' + orderId + ', lineItemCount=' + lineItems.size()
            );
            return;
        }

        Map<Id, PricebookEntry> productIdToPbe = new Map<Id, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :squarePricebookId
            AND Product2Id IN :productMatches.productIds
            AND IsActive = true
        ]) {
            productIdToPbe.put(pbe.Product2Id, pbe);
        }

        if (productIdToPbe.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderItemSyncService: no PricebookEntry found for matched products. ' +
                'orderId=' + orderId + ', pricebookId=' + squarePricebookId
            );
            return;
        }

        // Existing OrderItems are matched per product, not per Order.
        // This allows a retry to insert a missing product without duplicating
        // the product that was successfully inserted by an earlier webhook.
        Map<Id, OrderItem> existingItemByProductId = new Map<Id, OrderItem>();
        for (OrderItem existingItem : [
            SELECT Id, PricebookEntry.Product2Id, Quantity, UnitPrice
            FROM OrderItem
            WHERE OrderId = :orderId
            AND PricebookEntry.Product2Id IN :productMatches.productIds
        ]) {
            Id existingProductId = existingItem.PricebookEntry.Product2Id;
            if (!existingItemByProductId.containsKey(existingProductId)) {
                existingItemByProductId.put(existingProductId, existingItem);
            }
        }

        // Consolidate multiple Square lines for the same Salesforce Product2.
        // The weighted average preserves the total line value in one OrderItem.
        Map<Id, Decimal> quantityByProductId = new Map<Id, Decimal>();
        Map<Id, Decimal> totalByProductId = new Map<Id, Decimal>();
        Set<Id> matchedProductIds = new Set<Id>();

        for (SquareLineItem li : lineItems) {
            Id productId;

            // Match by Square catalog ID first, but only accept a product that
            // has an active PricebookEntry in the Square price book. If the
            // catalog match cannot be ordered in this price book, continue to
            // SKU and then exact normalized name matching.
            if (String.isNotBlank(li.catalogVariationId)) {
                Id catalogProductId =
                    productMatches.catalogIdToProductId.get(li.catalogVariationId.trim());
                if (catalogProductId != null && productIdToPbe.containsKey(catalogProductId)) {
                    productId = catalogProductId;
                } else if (catalogProductId != null) {
                    System.debug(LoggingLevel.WARN,
                        'SquareOrderItemSyncService: catalog match has no active Square PricebookEntry; ' +
                        'trying next matching strategy. productId=' + catalogProductId +
                        ', catalogVariationId=' + li.catalogVariationId);
                }
            }

            if (productId == null && String.isNotBlank(li.sku)) {
                Id skuProductId = productMatches.skuToProductId.get(li.sku.trim());
                if (skuProductId != null && productIdToPbe.containsKey(skuProductId)) {
                    productId = skuProductId;
                } else if (skuProductId != null) {
                    System.debug(LoggingLevel.WARN,
                        'SquareOrderItemSyncService: SKU match has no active Square PricebookEntry; ' +
                        'trying normalized name fallback. sku=' + li.sku +
                        ', productId=' + skuProductId);
                }
            }

            if (productId == null && String.isNotBlank(li.name)) {
                productId = resolveNormalizedNameMatch(
                    li.name,
                    li.basePriceMoney,
                    productMatches,
                    productIdToPbe
                );
            }

            if (productId == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareOrderItemSyncService: no Salesforce product match for Square line item. ' +
                    'name=' + li.name + ', sku=' + li.sku +
                    ', catalogVariationId=' + li.catalogVariationId
                );
                continue;
            }

            PricebookEntry pbe = productIdToPbe.get(productId);
            if (pbe == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareOrderItemSyncService: product matched but no Square PricebookEntry. ' +
                    'productId=' + productId + ', name=' + li.name
                );
                continue;
            }

            Decimal qty = (li.quantity == null || li.quantity <= 0) ? 1 : li.quantity;
            Decimal unitPrice = (li.basePriceMoney == null || li.basePriceMoney < 0)
                ? pbe.UnitPrice
                : li.basePriceMoney;

            quantityByProductId.put(
                productId,
                (quantityByProductId.containsKey(productId) ? quantityByProductId.get(productId) : 0) + qty
            );
            totalByProductId.put(
                productId,
                (totalByProductId.containsKey(productId) ? totalByProductId.get(productId) : 0) + (unitPrice * qty)
            );
            matchedProductIds.add(productId);
        }

        List<OrderItem> itemsToInsert = new List<OrderItem>();
        List<OrderItem> itemsToUpdate = new List<OrderItem>();

        for (Id productId : matchedProductIds) {
            Decimal totalQty = quantityByProductId.get(productId);
            Decimal totalAmount = totalByProductId.get(productId);
            if (totalQty == null || totalQty <= 0) {
                continue;
            }

            PricebookEntry pbe = productIdToPbe.get(productId);
            Decimal effectiveUnitPrice = totalAmount / totalQty;
            OrderItem targetItem = existingItemByProductId.get(productId);
            Boolean isExisting = targetItem != null;

            if (!isExisting) {
                targetItem = new OrderItem();
                targetItem.OrderId = orderId;
                targetItem.PricebookEntryId = pbe.Id;
            }

            targetItem.Quantity = totalQty;
            targetItem.UnitPrice = effectiveUnitPrice;

            applyPopUpProviderToOrderItem(targetItem, popUpProviderCustomerId);

            if (isExisting) {
                itemsToUpdate.add(targetItem);
            } else {
                itemsToInsert.add(targetItem);
            }
        }

        Integer insertedCount = 0;
        Integer updatedCount = 0;

        if (!itemsToInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(itemsToInsert, false);
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (insertResults[i].isSuccess()) {
                    insertedCount++;
                } else {
                    for (Database.Error err : insertResults[i].getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'SquareOrderItemSyncService: OrderItem insert failed. orderId=' +
                            orderId + ', error=' + err.getMessage()
                        );
                    }
                }
            }
        }

        if (!itemsToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(itemsToUpdate, false);
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (updateResults[i].isSuccess()) {
                    updatedCount++;
                } else {
                    for (Database.Error err : updateResults[i].getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'SquareOrderItemSyncService: OrderItem update failed. orderId=' +
                            orderId + ', orderItemId=' + itemsToUpdate[i].Id +
                            ', error=' + err.getMessage()
                        );
                    }
                }
            }
        }

        System.debug(
            LoggingLevel.INFO,
            'SquareOrderItemSyncService: OrderItem sync finished. orderId=' + orderId +
            ', inserted=' + insertedCount + ', updated=' + updatedCount +
            ', insertAttempted=' + itemsToInsert.size() +
            ', updateAttempted=' + itemsToUpdate.size() +
            ', unmatchedOrSkipped=' + (lineItems.size() - matchedProductIds.size())
        );
    }

    /**
     * Reads Order.Pop_up_Provider__c when the caller did not explicitly pass
     * the resolved provider Customer Id.
     */
    @TestVisible
    private static Id getProviderCustomerIdFromOrder(Id orderId) {
        if (orderId == null) {
            return null;
        }

        Map<String, Schema.SObjectField> orderFields =
            Schema.SObjectType.Order.fields.getMap();
        String providerField = 'Pop_up_Provider__c';
        if (!orderFields.containsKey(providerField) ||
            !isProviderCustomerReference(orderFields.get(providerField))) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderItemSyncService: Order.Pop_up_Provider__c Customer lookup is not available.'
            );
            return null;
        }

        List<SObject> orders = Database.query(
            'SELECT ' + providerField + ' FROM Order WHERE Id = :orderId LIMIT 1'
        );
        return orders.isEmpty() ? null : (Id) orders[0].get(providerField);
    }

    private static Boolean isProviderCustomerReference(Schema.SObjectField fieldToken) {
        return SquarePopUpAccountService.isProviderCustomerReference(fieldToken);
    }

    /**
     * Assign the Pop-up Provider Customer lookup on the OrderItem. The field is
     * checked dynamically because it is a custom lookup field; its expected
     * API name in this org is Pop_up_Provider__c.
     */
    private static void applyPopUpProviderToOrderItem(
        OrderItem targetItem,
        Id providerCustomerId
    ) {
        if (targetItem == null || providerCustomerId == null) {
            return;
        }

        String fieldApiName = findPopUpProviderCustomerLookupField();
        if (String.isBlank(fieldApiName)) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderItemSyncService: no OrderItem Customer lookup labelled ' +
                'Pop-up Provider was found. Provider Customer will be set on the Order only. ' +
                'providerCustomerId=' + providerCustomerId
            );
            return;
        }

        targetItem.put(fieldApiName, providerCustomerId);
        System.debug(
            LoggingLevel.INFO,
            'SquareOrderItemSyncService: assigned Pop-up Provider Customer to OrderItem. ' +
            'field=' + fieldApiName + ', orderItemId=' + targetItem.Id +
            ', providerCustomerId=' + providerCustomerId
        );
    }

    /**
     * Prefer the known API name. If this org uses a different API name on
     * OrderItem, resolve the field by its exact label and Customer reference.
     */
    @TestVisible
    private static String findPopUpProviderCustomerLookupField() {
        Map<String, Schema.SObjectField> fields =
            Schema.SObjectType.OrderItem.fields.getMap();
        String preferredApiName = 'Pop_up_Provider__c';

        if (fields.containsKey(preferredApiName) && isProviderCustomerReference(fields.get(preferredApiName))) {
            return preferredApiName;
        }

        for (String fieldApiName : fields.keySet()) {
            Schema.SObjectField fieldToken = fields.get(fieldApiName);
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (
                (normalizeProviderFieldName(fieldDescribe.getLabel()) == 'popupprovider' ||
                 normalizeProviderFieldName(fieldDescribe.getLabel()) == 'popupprovideraccount') &&
                isProviderCustomerReference(fieldToken)
            ) {
                return fieldApiName;
            }
        }

        return null;
    }


    private static String normalizeProviderFieldName(String value) {
        return String.isBlank(value)
            ? ''
            : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static ProductMatchResult findMatchingProducts(
        Set<String> skus,
        Set<String> catalogIds,
        Set<String> productNames
    ) {
        ProductMatchResult result = new ProductMatchResult();

        Map<String, Schema.SObjectField> productFields =
            Schema.SObjectType.Product2.fields.getMap();

        List<String> candidateSquareFields = new List<String>{
            'Square_Catalog_Object_Id__c',
            'Square_Catalog_Variation_Id__c',
            'Square_Variation_Id__c',
            'Square_Item_Variation_Id__c',
            'Square_Catalog_Id__c',
            'Square_Object_Id__c',
            'Square_Catalog_Item_Id__c'
        };

        List<String> availableSquareFields = new List<String>();
        for (String fieldName : candidateSquareFields) {
            if (productFields.containsKey(fieldName)) {
                availableSquareFields.add(fieldName);
            }
        }

        List<String> selectFields = new List<String>{ 'Id', 'Name', 'StockKeepingUnit' };
        selectFields.addAll(availableSquareFields);
        List<String> whereParts = new List<String>();

        if (skus != null && !skus.isEmpty()) {
            whereParts.add('StockKeepingUnit IN :skus');
        }

        if (catalogIds != null && !catalogIds.isEmpty()) {
            for (String fieldName : availableSquareFields) {
                whereParts.add(fieldName + ' IN :catalogIds');
            }
        }

        // Candidate retrieval is widened with all significant name tokens.
        // The final comparison is still exact after normalization, so a partial
        // token match cannot be selected as a product match.
        if (productNames != null) {
            for (String productName : productNames) {
                if (String.isBlank(productName)) {
                    continue;
                }
                List<String> tokenConditions = new List<String>();
                for (String token : productName.split('[^A-Za-z0-9]+')) {
                    if (String.isNotBlank(token) && token.length() >= 2) {
                        tokenConditions.add(
                            'Name LIKE \'%' + String.escapeSingleQuotes(token) + '%\''
                        );
                    }
                }
                if (!tokenConditions.isEmpty()) {
                    whereParts.add('(' + String.join(tokenConditions, ' AND ') + ')');
                }
            }
        }

        if (whereParts.isEmpty()) {
            return result;
        }

        String query =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM Product2 WHERE (' + String.join(whereParts, ' OR ') + ')';

        List<SObject> rows = Database.query(query);

        for (SObject row : rows) {
            Id productId = (Id) row.get('Id');
            result.productIds.add(productId);

            String sku = (String) row.get('StockKeepingUnit');
            if (String.isNotBlank(sku) && !result.skuToProductId.containsKey(sku)) {
                result.skuToProductId.put(sku, productId);
            }

            for (String fieldName : availableSquareFields) {
                Object value = row.get(fieldName);
                if (value == null) {
                    continue;
                }
                String catalogId = String.valueOf(value);
                if (String.isNotBlank(catalogId) && !result.catalogIdToProductId.containsKey(catalogId)) {
                    result.catalogIdToProductId.put(catalogId, productId);
                }
            }

            String normalizedName = normalizeProductName((String) row.get('Name'));
            if (String.isBlank(normalizedName)) {
                continue;
            }

            // Retain every exact normalized-name candidate. Ambiguity is
            // resolved later using Square Pricebook eligibility and, where
            // necessary, the Square line's unit price. Two Product2 rows with
            // the same name should not cause an automatic skip when only one
            // can be sold through the Square price book.
            if (!result.nameToProductIds.containsKey(normalizedName)) {
                result.nameToProductIds.put(normalizedName, new Set<Id>());
            }
            result.nameToProductIds.get(normalizedName).add(productId);
        }

        System.debug(
            LoggingLevel.INFO,
            'SquareOrderItemSyncService: product matching finished. ' +
            'candidateProducts=' + result.productIds.size() +
            ', skuMatches=' + result.skuToProductId.size() +
            ', catalogMatches=' + result.catalogIdToProductId.size() +
            ', normalizedNameGroups=' + result.nameToProductIds.size()
        );

        return result;
    }

    /**
     * Final fallback: match the Square line's name to an exact normalized
     * Product2.Name, then filter to products with an active entry in the
     * Square price book. If more than one remains, use the Square line unit
     * price only when it identifies exactly one candidate.
     */
    private static Id resolveNormalizedNameMatch(
        String squareProductName,
        Decimal squareUnitPrice,
        ProductMatchResult productMatches,
        Map<Id, PricebookEntry> productIdToPbe
    ) {
        String normalizedName = normalizeProductName(squareProductName);
        if (String.isBlank(normalizedName)) {
            return null;
        }

        Set<Id> exactNameCandidates = productMatches.nameToProductIds.get(normalizedName);
        if (exactNameCandidates == null || exactNameCandidates.isEmpty()) {
            return null;
        }

        List<Id> pricebookEligibleCandidates = new List<Id>();
        for (Id candidateId : exactNameCandidates) {
            if (productIdToPbe.containsKey(candidateId)) {
                pricebookEligibleCandidates.add(candidateId);
            }
        }

        if (pricebookEligibleCandidates.size() == 1) {
            Id selectedProductId = pricebookEligibleCandidates[0];
            System.debug(LoggingLevel.INFO,
                'SquareOrderItemSyncService: product matched by exact normalized name and ' +
                'Square Pricebook eligibility. name=' + squareProductName +
                ', productId=' + selectedProductId);
            return selectedProductId;
        }

        if (pricebookEligibleCandidates.size() > 1 && squareUnitPrice != null) {
            List<Id> exactPriceCandidates = new List<Id>();
            for (Id candidateId : pricebookEligibleCandidates) {
                Decimal pricebookUnitPrice = productIdToPbe.get(candidateId).UnitPrice;
                if (pricebookUnitPrice != null &&
                    pricebookUnitPrice.setScale(2) == squareUnitPrice.setScale(2)) {
                    exactPriceCandidates.add(candidateId);
                }
            }

            if (exactPriceCandidates.size() == 1) {
                Id selectedProductId = exactPriceCandidates[0];
                System.debug(LoggingLevel.INFO,
                    'SquareOrderItemSyncService: product matched by exact normalized name and ' +
                    'unique Square price. name=' + squareProductName +
                    ', squareUnitPrice=' + squareUnitPrice +
                    ', productId=' + selectedProductId);
                return selectedProductId;
            }
        }

        System.debug(LoggingLevel.WARN,
            'SquareOrderItemSyncService: normalized name fallback remains ambiguous or has no ' +
            'Square PricebookEntry. name=' + squareProductName +
            ', normalizedName=' + normalizedName +
            ', exactNameCandidates=' + exactNameCandidates.size() +
            ', pricebookEligibleCandidates=' + pricebookEligibleCandidates.size() +
            ', squareUnitPrice=' + squareUnitPrice);
        return null;
    }

    private static String normalizeProductName(String productName) {
        if (String.isBlank(productName)) {
            return null;
        }
        return productName.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static List<SquareLineItem> parseLineItems(Map<String, Object> squareOrder) {
        List<SquareLineItem> result = new List<SquareLineItem>();
        if (squareOrder == null) {
            return result;
        }

        Object lineItemsObj = squareOrder.get('line_items');
        if (!(lineItemsObj instanceof List<Object>)) {
            return result;
        }

        for (Object raw : (List<Object>) lineItemsObj) {
            if (!(raw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> item = (Map<String, Object>) raw;
            SquareLineItem li = new SquareLineItem();

            Object qtyObj = item.get('quantity');
            li.quantity = qtyObj == null ? 1 : Decimal.valueOf(String.valueOf(qtyObj));

            Map<String, Object> basePriceMoney = item.get('base_price_money') instanceof Map<String, Object>
                ? (Map<String, Object>) item.get('base_price_money')
                : null;
            if (basePriceMoney != null && basePriceMoney.get('amount') != null) {
                li.basePriceMoney = Decimal.valueOf(String.valueOf(basePriceMoney.get('amount'))) / 100;
            }

            if (item.get('catalog_object_id') != null) {
                li.catalogVariationId = String.valueOf(item.get('catalog_object_id'));
            }
            if (item.get('name') != null) {
                li.name = String.valueOf(item.get('name'));
            }

            Map<String, Object> itemVariationData = item.get('item_variation_data') instanceof Map<String, Object>
                ? (Map<String, Object>) item.get('item_variation_data')
                : null;
            if (itemVariationData != null && itemVariationData.get('sku') != null) {
                li.sku = String.valueOf(itemVariationData.get('sku'));
            }

            result.add(li);
        }
        return result;
    }

    private class ProductMatchResult {
        Set<Id> productIds = new Set<Id>();
        Map<String, Id> skuToProductId = new Map<String, Id>();
        Map<String, Id> catalogIdToProductId = new Map<String, Id>();
        Map<String, Set<Id>> nameToProductIds = new Map<String, Set<Id>>();
    }

    private class SquareLineItem {
        String sku;
        String catalogVariationId;
        String name;
        Decimal quantity = 1;
        Decimal basePriceMoney;
    }
}