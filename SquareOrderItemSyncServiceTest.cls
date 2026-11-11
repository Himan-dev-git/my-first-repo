@IsTest
private class SquareOrderItemSyncServiceTest {

    // StockKeepingUnit is unique in this org. Generate a distinct SKU for every
    // test Product2, then reuse that generated value when building the Square line.
    private static Map<String, String> uniqueSkuByBase = new Map<String, String>();

    private static String getUniqueTestSku(String skuBase) {
        if (String.isBlank(skuBase)) {
            return skuBase;
        }

        if (!uniqueSkuByBase.containsKey(skuBase)) {
            String suffix = String.valueOf(DateTime.now().getTime()) +
                String.valueOf(Crypto.getRandomInteger()).replace('-', '');
            uniqueSkuByBase.put(skuBase, skuBase + '-' + suffix);
        }

        return uniqueSkuByBase.get(skuBase);
    }

    private static String resolveTestSku(String sku) {
        return uniqueSkuByBase.containsKey(sku)
            ? uniqueSkuByBase.get(sku)
            : sku;
    }

    private class TestContext {
        Id orderId;
        Id pricebookId;
        Map<String, Id> productIdsByName = new Map<String, Id>();
    }

    private static TestContext createContext() {
        TestContext context = new TestContext();

        Account accountRecord = new Account(Name = 'Square Order Item Test Account');
        insert accountRecord;

        Pricebook2 squarePricebook = new Pricebook2(
            Name = 'Square Order Item Test Pricebook',
            IsActive = true
        );
        insert squarePricebook;
        context.pricebookId = squarePricebook.Id;

        Order orderRecord = new Order(
            AccountId = accountRecord.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS',
            Pricebook2Id = squarePricebook.Id
        );
        insert orderRecord;
        context.orderId = orderRecord.Id;

        return context;
    }

    private static Id createProduct(
        String productName,
        String sku,
        Decimal standardPrice,
        Id squarePricebookId
    ) {
        Product2 productRecord = new Product2(
            Name = productName,
            IsActive = true,
            StockKeepingUnit = getUniqueTestSku(sku)
        );
        insert productRecord;

        // Salesforce requires a Standard Price Book entry before a custom
        // Price Book entry can be inserted for the same Product2.
        PricebookEntry standardEntry = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = productRecord.Id,
            UnitPrice = standardPrice,
            IsActive = true
        );
        insert standardEntry;

        PricebookEntry squareEntry = new PricebookEntry(
            Pricebook2Id = squarePricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = standardPrice,
            IsActive = true,
            UseStandardPrice = false
        );
        insert squareEntry;

        return productRecord.Id;
    }

    private static Id createProductWithoutSquarePricebookEntry(
        String productName,
        String sku,
        Decimal standardPrice
    ) {
        Product2 productRecord = new Product2(
            Name = productName,
            IsActive = true,
            StockKeepingUnit = getUniqueTestSku(sku)
        );
        insert productRecord;

        PricebookEntry standardEntry = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = productRecord.Id,
            UnitPrice = standardPrice,
            IsActive = true
        );
        insert standardEntry;
        return productRecord.Id;
    }

    private static Map<String, Object> squareLine(
        String productName,
        String sku,
        String catalogVariationId,
        String quantity,
        Integer basePriceCents
    ) {
        Map<String, Object> line = new Map<String, Object>{
            'name' => productName,
            'quantity' => quantity
        };

        if (String.isNotBlank(sku)) {
            line.put('item_variation_data', new Map<String, Object>{ 'sku' => resolveTestSku(sku) });
        }
        if (String.isNotBlank(catalogVariationId)) {
            line.put('catalog_object_id', catalogVariationId);
        }
        if (basePriceCents != null) {
            line.put('base_price_money', new Map<String, Object>{
                'amount' => basePriceCents,
                'currency' => 'GBP'
            });
        }
        return line;
    }

    private static Map<String, Object> squareOrder(List<Object> lines) {
        return new Map<String, Object>{ 'line_items' => lines };
    }

    private static List<OrderItem> getOrderItems(Id orderId) {
        String query =
            'SELECT Id, OrderId, Quantity, UnitPrice, PricebookEntry.Product2Id, ' +
            'PricebookEntry.Product2.Name';
        String providerField = findOrderItemProviderField();
        if (String.isNotBlank(providerField)) {
            query += ', ' + providerField;
        }
        query += ' FROM OrderItem WHERE OrderId = :orderId';
        return (List<OrderItem>) Database.query(query);
    }

    private static String findOrderItemProviderField() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.OrderItem.fields.getMap();
        if (fields.containsKey('Pop_up_Provider__c') &&
            SquarePopUpAccountService.isProviderCustomerReference(fields.get('Pop_up_Provider__c'))) {
            return 'Pop_up_Provider__c';
        }
        for (String fieldApiName : fields.keySet()) {
            Schema.DescribeFieldResult describeResult = fields.get(fieldApiName).getDescribe();
            String normalizedLabel =
                describeResult.getLabel().toLowerCase().replaceAll('[^a-z0-9]', '');
            if (
                (normalizedLabel == 'popupprovider' || normalizedLabel == 'popupprovideraccount') &&
                SquarePopUpAccountService.isProviderCustomerReference(fields.get(fieldApiName))
            ) {
                return fieldApiName;
            }
        }
        return null;
    }

    private static Id createPopUpProviderCustomer() {
        Schema.SObjectType providerType =
            SquarePopUpAccountService.getProviderCustomerObjectType();
        if (providerType == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fields = providerType.getDescribe().fields.getMap();
        if (!fields.containsKey('Square_Location_Id__c')) {
            return null;
        }

        String squareLocationId = 'SQ_ITEM_PROVIDER_' + String.valueOf(DateTime.now().getTime());
        SObject providerCustomer = providerType.newSObject();
        if (fields.containsKey('Name') && fields.get('Name').getDescribe().isCreateable()) {
            providerCustomer.put('Name', 'Order Item Provider ' + squareLocationId);
        }
        providerCustomer.put('Square_Location_Id__c', squareLocationId);
        insert providerCustomer;
        return (Id) providerCustomer.get('Id');
    }

    @IsTest
    static void testNullInputsAndNoLineItemsDoNothing() {
        TestContext context = createContext();

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(null, squareOrder(new List<Object>()), context.pricebookId);
        SquareOrderItemSyncService.syncOrderItems(context.orderId, null, context.pricebookId);
        SquareOrderItemSyncService.syncOrderItems(context.orderId, squareOrder(new List<Object>()), null);
        SquareOrderItemSyncService.syncOrderItems(context.orderId, squareOrder(new List<Object>()), context.pricebookId);
        Test.stopTest();

        System.assertEquals(0, getOrderItems(context.orderId).size());
    }

    @IsTest
    static void testMatchesBySkuAndUsesSquareLinePrice() {
        TestContext context = createContext();
        Id productId = createProduct('Pearl Cluster Ear Jacket', 'SKU-PEARL-100', 55, context.pricebookId);

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Pearl Cluster Ear Jacket', 'SKU-PEARL-100', null, '1', 5900)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size());
        System.assertEquals(productId, items[0].PricebookEntry.Product2Id);
        System.assertEquals(1, items[0].Quantity);
        System.assertEquals(59, items[0].UnitPrice,
            'Square line base_price_money should be converted from cents to currency units.');
    }

    @IsTest
    static void testMatchesByNormalizedProductNameWhenSkuMissing() {
        TestContext context = createContext();
        Id productId = createProduct('Arielle Ring', 'SKU-ARIELLE-200', 45, context.pricebookId);

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Arielle-Ring!', null, null, '1', 4500)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size());
        System.assertEquals(productId, items[0].PricebookEntry.Product2Id);
        System.assertEquals(45, items[0].UnitPrice);
    }

    @IsTest
    static void testCatalogVariationIdTakesPriorityOverSkuWhenFieldAvailable() {
        String catalogFieldName = getWritableCatalogFieldName();
        if (catalogFieldName == null) {
            System.debug('Skipping catalog-priority test: no supported writable Square catalog ID field exists on Product2.');
            return;
        }

        TestContext context = createContext();

        Product2 catalogProduct = new Product2(
            Name = 'Catalog Matched Product',
            IsActive = true,
            StockKeepingUnit = getUniqueTestSku('SKU-CATALOG-PRODUCT')
        );
        catalogProduct.put(catalogFieldName, 'SQ_VARIATION_123');
        insert catalogProduct;
        insertStandardAndSquarePricebookEntries(catalogProduct.Id, 40, context.pricebookId);

        Id skuProductId = createProduct(
            'SKU Matched Different Product',
            'SKU-CATALOG-PRIORITY',
            60,
            context.pricebookId
        );

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Catalog Matched Product', 'SKU-CATALOG-PRIORITY', 'SQ_VARIATION_123', '1', 4200)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size());
        System.assertEquals(
            catalogProduct.Id,
            items[0].PricebookEntry.Product2Id,
            'Catalog variation ID must take priority over SKU.'
        );
        System.assertNotEquals(skuProductId, items[0].PricebookEntry.Product2Id);
    }

    @IsTest
    static void testRetryInsertsMissingProductAndUpdatesExistingProduct() {
        TestContext context = createContext();
        Id pearlId = createProduct('Pearl Cluster Ear Jacket', 'SKU-PEARL-RETRY', 55, context.pricebookId);
        Id ringId = createProduct('Arielle Ring', 'SKU-RING-RETRY', 45, context.pricebookId);

        Map<String, Object> firstAttempt = squareOrder(new List<Object>{
            squareLine('Pearl Cluster Ear Jacket', 'SKU-PEARL-RETRY', null, '1', 5500)
        });

        // The retry now contains the line that previously failed to match plus
        // the already-synced line with a changed quantity/price.
        Map<String, Object> retryOrder = squareOrder(new List<Object>{
            squareLine('Pearl Cluster Ear Jacket', 'SKU-PEARL-RETRY', null, '2', 6000),
            squareLine('Arielle Ring', 'SKU-RING-RETRY', null, '1', 4500)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, firstAttempt, context.pricebookId);
        System.assertEquals(1, getOrderItems(context.orderId).size(), 'First attempt should create the matched product.');
        SquareOrderItemSyncService.syncOrderItems(context.orderId, retryOrder, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(2, items.size(),
            'Retry should update the existing product and insert the previously missing product.');

        Map<Id, OrderItem> byProductId = new Map<Id, OrderItem>();
        for (OrderItem item : items) {
            byProductId.put(item.PricebookEntry.Product2Id, item);
        }

        System.assertEquals(2, byProductId.get(pearlId).Quantity);
        System.assertEquals(60, byProductId.get(pearlId).UnitPrice);
        System.assertEquals(1, byProductId.get(ringId).Quantity);
        System.assertEquals(45, byProductId.get(ringId).UnitPrice);
    }

    @IsTest
    static void testMultipleSquareLinesForSameProductAreConsolidated() {
        TestContext context = createContext();
        Id productId = createProduct('Gold Bracelet', 'SKU-BRACELET-AGG', 50, context.pricebookId);

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Gold Bracelet', 'SKU-BRACELET-AGG', null, '1', 4000),
            squareLine('Gold Bracelet', 'SKU-BRACELET-AGG', null, '1', 6000)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size(), 'Same Product2 lines should be consolidated into one OrderItem.');
        System.assertEquals(productId, items[0].PricebookEntry.Product2Id);
        System.assertEquals(2, items[0].Quantity);
        System.assertEquals(50, items[0].UnitPrice, 'Weighted average unit price should preserve total line value.');
    }

    @IsTest
    static void testExistingOrderItemIsUpdatedRatherThanDuplicated() {
        TestContext context = createContext();
        Id productId = createProduct('Silver Hoop Earrings', 'SKU-HOOP-UPDATE', 25, context.pricebookId);
        PricebookEntry pbe = [
            SELECT Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :context.pricebookId
            AND Product2Id = :productId
            LIMIT 1
        ];
        insert new OrderItem(
            OrderId = context.orderId,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 25
        );

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Silver Hoop Earrings', 'SKU-HOOP-UPDATE', null, '3', 3000)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size(), 'An existing matching OrderItem must not be duplicated.');
        System.assertEquals(3, items[0].Quantity);
        System.assertEquals(30, items[0].UnitPrice);
    }

    @IsTest
    static void testAmbiguousNormalizedProductNamesAreSkipped() {
        TestContext context = createContext();
        Id firstProductId = createProduct('Pearl Cluster', 'SKU-PEARL-A', 50, context.pricebookId);
        Id secondProductId = createProduct('Pearl Cluster', 'SKU-PEARL-B', 50, context.pricebookId);
        System.assertNotEquals(firstProductId, secondProductId);

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Pearl Cluster', null, null, '1', 5000)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        System.assertEquals(0, getOrderItems(context.orderId).size(),
            'A non-unique normalized name with identical Square price candidates must not select an arbitrary Product2.');
    }

    @IsTest
    static void testDuplicateNamesChooseOnlyProductWithSquarePricebookEntry() {
        TestContext context = createContext();
        createProductWithoutSquarePricebookEntry(
            'Alba Pearl Earrings', 'SKU-ALBA-NO-SQUARE-PBE', 63
        );
        Id squareEligibleProductId = createProduct(
            'Alba Pearl Earrings', 'SKU-ALBA-SQUARE-PBE', 63, context.pricebookId
        );

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Alba Pearl Earrings', null, null, '1', 6300)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size(),
            'A duplicate name should resolve when only one exact-name Product2 has an active Square PricebookEntry.');
        System.assertEquals(squareEligibleProductId, items[0].PricebookEntry.Product2Id);
        System.assertEquals(63, items[0].UnitPrice);
    }

    @IsTest
    static void testDuplicateNamesUseUniqueSquarePriceToSelectProduct() {
        TestContext context = createContext();
        createProduct('Celine Stacking Ring', 'SKU-CELINE-55', 55, context.pricebookId);
        Id matchingPriceProductId = createProduct(
            'Celine Stacking Ring', 'SKU-CELINE-53', 53, context.pricebookId
        );

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Celine Stacking Ring', null, null, '1', 5300)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size(),
            'The Square line price should select exactly one candidate when duplicate names exist.');
        System.assertEquals(matchingPriceProductId, items[0].PricebookEntry.Product2Id);
        System.assertEquals(53, items[0].UnitPrice);
    }

    @IsTest
    static void testCatalogMatchWithoutSquarePricebookEntryFallsBackToName() {
        String catalogFieldName = getWritableCatalogFieldName();
        if (catalogFieldName == null) {
            System.debug('Skipping catalog-to-name fallback test: no supported writable Square catalog ID field exists on Product2.');
            return;
        }

        TestContext context = createContext();
        Product2 catalogOnlyProduct = new Product2(
            Name = 'Arielle Ring',
            IsActive = true,
            StockKeepingUnit = getUniqueTestSku('SKU-ARIELLE-CATALOG-ONLY')
        );
        catalogOnlyProduct.put(catalogFieldName, 'SQ_VARIATION_NO_PBE');
        insert catalogOnlyProduct;
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = catalogOnlyProduct.Id,
            UnitPrice = 45,
            IsActive = true
        );

        Id squareEligibleProductId = createProduct(
            'Arielle Ring', 'SKU-ARIELLE-WITH-PBE', 45, context.pricebookId
        );

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Arielle Ring', null, 'SQ_VARIATION_NO_PBE', '1', 4500)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size(),
            'An unorderable catalog match should not block the normalized-name fallback.');
        System.assertEquals(squareEligibleProductId, items[0].PricebookEntry.Product2Id);
    }

    @IsTest
    static void testNoProductMatchDoesNotInsertOrderItem() {
        TestContext context = createContext();

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Product That Does Not Exist', 'SKU-NOT-FOUND', 'VAR-NOT-FOUND', '1', 1000)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        System.assertEquals(0, getOrderItems(context.orderId).size());
    }

    @IsTest
    static void testMatchedProductWithoutSquarePricebookEntryIsSkipped() {
        TestContext context = createContext();
        createProductWithoutSquarePricebookEntry('Product Without Square PBE', 'SKU-NO-SQUARE-PBE', 20);

        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Product Without Square PBE', 'SKU-NO-SQUARE-PBE', null, '1', 2000)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        System.assertEquals(0, getOrderItems(context.orderId).size(),
            'Product2 must have an active PricebookEntry in the supplied Square Pricebook.');
    }

    @IsTest
    static void testMissingQuantityAndPriceUseSafeDefaults() {
        TestContext context = createContext();
        Id productId = createProduct('Defaulted Line Product', 'SKU-DEFAULTS', 37, context.pricebookId);

        Map<String, Object> line = new Map<String, Object>{
            'name' => 'Defaulted Line Product',
            'item_variation_data' => new Map<String, Object>{ 'sku' => 'SKU-DEFAULTS' },
            'quantity' => '0'
        };

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(
            context.orderId,
            squareOrder(new List<Object>{ line }),
            context.pricebookId
        );
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size());
        System.assertEquals(productId, items[0].PricebookEntry.Product2Id);
        System.assertEquals(1, items[0].Quantity, 'Zero or non-positive quantities should default to one.');
        System.assertEquals(37, items[0].UnitPrice, 'Missing Square price should default to PBE UnitPrice.');
    }

    @IsTest
    static void testOrderItemReceivesPopUpProviderCustomerLookup() {
        String providerField = findOrderItemProviderField();
        if (String.isBlank(providerField)) {
            System.debug('Skipping provider lookup assertion: no OrderItem Customer lookup labelled Pop-up Provider exists.');
            return;
        }

        TestContext context = createContext();
        Id providerCustomerId = createPopUpProviderCustomer();
        System.assertNotEquals(null, providerCustomerId,
            'A child Pop-up Provider Customer should be created for the test Square Location.');

        // Keep the parent Order lookup populated as well, in case the OrderItem
        // field's lookup filter depends on the parent Order's provider value.
        Map<String, Schema.SObjectField> orderFields = Schema.SObjectType.Order.fields.getMap();
        if (orderFields.containsKey('Pop_up_Provider__c')) {
            Order parentOrder = new Order(Id = context.orderId);
            parentOrder.put('Pop_up_Provider__c', providerCustomerId);
            update parentOrder;
        }

        createProduct('Provider Mapped Bracelet', 'SKU-PROVIDER-ITEM', 49, context.pricebookId);
        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Provider Mapped Bracelet', 'SKU-PROVIDER-ITEM', null, '1', 4900)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(
            context.orderId,
            orderMap,
            context.pricebookId,
            providerCustomerId
        );
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size());
        System.assertEquals(
            providerCustomerId,
            (Id) items[0].get(providerField),
            'OrderItem Pop-up Provider lookup should use the same valid Customer as its Order.'
        );
    }

    @IsTest
    static void testThreeArgumentCallUsesProviderCustomerLookupFromParentOrder() {
        String providerField = findOrderItemProviderField();
        if (String.isBlank(providerField)) {
            System.debug('Skipping provider inheritance test: OrderItem provider Customer lookup was not found.');
            return;
        }

        TestContext context = createContext();
        Id providerCustomerId = createPopUpProviderCustomer();
        System.assertNotEquals(null, providerCustomerId);

        Order parentOrder = new Order(Id = context.orderId);
        parentOrder.put('Pop_up_Provider__c', providerCustomerId);
        update parentOrder;

        createProduct('Inherited Provider Product', 'SKU-INHERITED-PROVIDER', 42, context.pricebookId);
        Map<String, Object> orderMap = squareOrder(new List<Object>{
            squareLine('Inherited Provider Product', 'SKU-INHERITED-PROVIDER', null, '1', 4200)
        });

        Test.startTest();
        SquareOrderItemSyncService.syncOrderItems(context.orderId, orderMap, context.pricebookId);
        Test.stopTest();

        List<OrderItem> items = getOrderItems(context.orderId);
        System.assertEquals(1, items.size());
        System.assertEquals(providerCustomerId, (Id) items[0].get(providerField));
    }

    private static void insertStandardAndSquarePricebookEntries(
        Id productId,
        Decimal unitPrice,
        Id squarePricebookId
    ) {
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = productId,
            UnitPrice = unitPrice,
            IsActive = true
        );
        insert new PricebookEntry(
            Pricebook2Id = squarePricebookId,
            Product2Id = productId,
            UnitPrice = unitPrice,
            IsActive = true,
            UseStandardPrice = false
        );
    }

    private static String getWritableCatalogFieldName() {
        List<String> candidates = new List<String>{
            'Square_Catalog_Object_Id__c',
            'Square_Catalog_Variation_Id__c',
            'Square_Variation_Id__c',
            'Square_Item_Variation_Id__c',
            'Square_Catalog_Id__c',
            'Square_Object_Id__c',
            'Square_Catalog_Item_Id__c'
        };

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Product2.fields.getMap();
        for (String candidate : candidates) {
            if (!fields.containsKey(candidate)) {
                continue;
            }
            Schema.DescribeFieldResult describeResult = fields.get(candidate).getDescribe();
            if (describeResult.isCreateable() && describeResult.getType() == Schema.DisplayType.String) {
                return candidate;
            }
        }
        return null;
    }
}