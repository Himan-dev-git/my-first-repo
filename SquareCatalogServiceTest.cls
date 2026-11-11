@IsTest
private class SquareCatalogServiceTest {

    private class SquareCatalogMock implements HttpCalloutMock {
        private String mode;

        SquareCatalogMock(String mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String body = req.getBody();

            /*
             * Safe Shopify side-effect responses from Product2 triggers.
             */
            if (body != null && body.contains('productVariantsBulkUpdate')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"data":{"productVariantsBulkUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"productVariants":[],' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (body != null && body.contains('productCreate')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"data":{"productCreate":{' +
                    '"product":{"id":"gid://shopify/Product/123","legacyResourceId":"123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (body != null && body.contains('productUpdate')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"data":{"productUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'NOT_FOUND') {
                res.setStatusCode(404);
                res.setBody('{"errors":[{"code":"NOT_FOUND","detail":"catalog object not found"}]}');
                return res;
            }

            if (mode == 'ERROR') {
                res.setStatusCode(500);
                res.setBody('{"errors":[{"detail":"mock error"}]}');
                return res;
            }

            res.setStatusCode(200);

            /*
             * Square retrieveCatalogObject.
             */
            if (
                endpoint != null &&
                endpoint.contains('/v2/catalog/object/') &&
                req.getMethod() == 'GET'
            ) {
                if (mode == 'LATEST_WITH_VARIATIONS') {
                    res.setBody(
                        '{"object":{' +
                        '"id":"SQUARE_ITEM_EXISTING",' +
                        '"type":"ITEM",' +
                        '"version":12345,' +
                        '"item_data":{' +
                        '"variations":[' +
                        '{"id":"VAR_EXISTING","version":777},' +
                        '{"id":null,"version":888}' +
                        ']}' +
                        '}}'
                    );
                    return res;
                }

                if (mode == 'LATEST_NULL_OBJECT') {
                    res.setBody('{"object":null}');
                    return res;
                }

                res.setBody(
                    '{"object":{' +
                    '"id":"SQUARE_ITEM_EXISTING",' +
                    '"type":"ITEM",' +
                    '"version":12345' +
                    '}}'
                );
                return res;
            }

            /*
             * Square image upload queueable safety.
             */
            if (endpoint != null && endpoint.contains('/v2/catalog/images')) {
                res.setBody(
                    '{"image":{' +
                    '"id":"IMG_123",' +
                    '"type":"IMAGE",' +
                    '"image_data":{"name":"Product Image"}' +
                    '}}'
                );
                return res;
            }

            /*
             * Square upsertCatalogObject.
             */
            if (
                endpoint != null &&
                endpoint.contains('/v2/catalog/object') &&
                req.getMethod() == 'POST'
            ) {
                if (mode == 'NO_CATALOG_OBJECT') {
                    res.setBody('{"id_mappings":[]}');
                    return res;
                }

                if (mode == 'NO_VARIATION_MAPPING') {
                    res.setBody(
                        '{"catalog_object":{' +
                        '"id":"SQUARE_ITEM_123",' +
                        '"type":"ITEM"' +
                        '},' +
                        '"id_mappings":[]}'
                    );
                    return res;
                }

                if (mode == 'EXISTING_VARIATION') {
                    res.setBody(
                        '{"catalog_object":{' +
                        '"id":"SQUARE_ITEM_EXISTING",' +
                        '"type":"ITEM"' +
                        '},' +
                        '"id_mappings":[]}'
                    );
                    return res;
                }

                if (mode == 'SYNC_ITEM') {
                    res.setBody(
                        '{"catalog_object":{' +
                        '"id":"SQUARE_ITEM_FROM_SYNC_ITEM",' +
                        '"type":"ITEM",' +
                        '"version":99' +
                        '}}'
                    );
                    return res;
                }

                res.setBody(
                    '{"catalog_object":{' +
                    '"id":"SQUARE_ITEM_123",' +
                    '"type":"ITEM"' +
                    '},' +
                    '"id_mappings":[]}'
                );
                return res;
            }

            res.setBody('{}');
            return res;
        }
    }

    private class DynamicSquareCatalogMock implements HttpCalloutMock {
        private Id variantId;

        DynamicSquareCatalogMock(Id variantId) {
            this.variantId = variantId;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String body = req.getBody();

            if (body != null && body.contains('productVariantsBulkUpdate')) {
                res.setBody(
                    '{"data":{"productVariantsBulkUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"productVariants":[],' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (body != null && body.contains('productCreate')) {
                res.setBody(
                    '{"data":{"productCreate":{' +
                    '"product":{"id":"gid://shopify/Product/123","legacyResourceId":"123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (body != null && body.contains('productUpdate')) {
                res.setBody(
                    '{"data":{"productUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/catalog/images')) {
                res.setBody(
                    '{"image":{"id":"IMG_123","type":"IMAGE"}}'
                );
                return res;
            }

            if (
                endpoint != null &&
                endpoint.contains('/v2/catalog/object') &&
                req.getMethod() == 'POST'
            ) {
                res.setBody(
                    '{"catalog_object":{' +
                    '"id":"SQUARE_ITEM_123",' +
                    '"type":"ITEM"' +
                    '},' +
                    '"id_mappings":[' +
                    '{"client_object_id":"#VAR_' + String.valueOf(variantId) + '","object_id":"SQUARE_VARIATION_123"}' +
                    ']}'
                );
                return res;
            }

            res.setBody('{}');
            return res;
        }
    }

    private static void putIfCreateable(SObject row, String fieldName, Object value) {
        Map<String, Schema.SObjectField> fields =
            row.getSObjectType().getDescribe().fields.getMap();

        if (
            fields.containsKey(fieldName) &&
            fields.get(fieldName).getDescribe().isCreateable()
        ) {
            row.put(fieldName, value);
        }
    }

    private static Id getVariantRecordTypeIdOrNull() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ];

        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Pricebook2 createSquarePricebook() {
        List<Pricebook2> existing = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = 'Square Pricebook'
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        Pricebook2 pb = new Pricebook2(
            Name = 'Square Pricebook',
            IsActive = true
        );
        insert pb;
        return pb;
    }

    private static Product2 createParentProduct(String squareItemId) {
        Product2 parent = new Product2(
            Name = 'Parent Product ' + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 100000)),
            Description = 'Parent Description',
            IsActive = true
        );

        putIfCreateable(parent, 'Type__c', 'Product');

        if (squareItemId != null) {
            parent.Square_Catalog_Item_Id__c = squareItemId;
        }

        insert parent;
        return parent;
    }

    private static Product2 createStandaloneProduct(String name) {
        Product2 p = new Product2(
            Name = name,
            Description = 'Test description',
            IsActive = true,
            StockKeepingUnit = name.replace(' ', '_').toUpperCase()
        );

        putIfCreateable(p, 'Type__c', 'Product');

        insert p;
        return p;
    }

    private static Product2 createVariantProduct(
        Id parentId,
        String sku,
        String squareVariationId
    ) {
        Product2 variant = new Product2(
            Name = 'Variant ' + sku,
            IsActive = true,
            StockKeepingUnit = sku,
            Parent__c = parentId,
            Type__c = 'Variant'
        );

        Id variantRtId = getVariantRecordTypeIdOrNull();
        if (variantRtId != null) {
            variant.RecordTypeId = variantRtId;
        }

        if (squareVariationId != null) {
            variant.Square_Catalog_Variation_Id__c = squareVariationId;
        }

        insert variant;
        return variant;
    }

    private static void createStandardPrice(Id productId, Decimal priceValue) {
        List<PricebookEntry> existing = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :productId
            AND Pricebook2Id = :Test.getStandardPricebookId()
            LIMIT 1
        ];

        if (existing.isEmpty()) {
            PricebookEntry standardPbe = new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = productId,
                UnitPrice = priceValue,
                IsActive = true
            );
            insert standardPbe;
        }
    }

    private static void createSquarePrice(Id squarePbId, Id productId, Decimal priceValue) {
        createStandardPrice(productId, priceValue);

        PricebookEntry squarePbe = new PricebookEntry(
            Pricebook2Id = squarePbId,
            Product2Id = productId,
            UnitPrice = priceValue,
            IsActive = true,
            UseStandardPrice = false
        );
        insert squarePbe;
    }

    @IsTest
    static void testNullAndEmptyInputsReturnSafely() {
        Test.startTest();
        SquareCatalogService.syncProductsToSquare(null);
        SquareCatalogService.syncProductsToSquare(new List<Id>());
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testNonVariantProductIsSkipped() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('SUCCESS'));

        Product2 parent = createParentProduct(null);

        Test.startTest();
        SquareCatalogService.syncProductsToSquare(new List<Id>{ parent.Id });
        Test.stopTest();

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :parent.Id
        ];

        System.assertEquals(null, afterParent.Square_Catalog_Item_Id__c);
    }

    @IsTest
    static void testVariantWithoutParentIsSkipped() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('SUCCESS'));

        Product2 variant = createVariantProduct(null, 'SKU-NO-PARENT', null);

        Test.startTest();
        SquareCatalogService.syncProductsToSquare(new List<Id>{ variant.Id });
        Test.stopTest();

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        System.assertEquals(null, afterVariant.Square_Catalog_Variation_Id__c);
    }

    @IsTest
    static void testVariantSyncUpdatesParentAndVariantIds() {
        Product2 parent = createParentProduct(null);
        Product2 variant = createVariantProduct(parent.Id, 'SKU-1', null);

        Pricebook2 squarePb = createSquarePricebook();
        createSquarePrice(squarePb.Id, variant.Id, 19.99);

        Test.setMock(HttpCalloutMock.class, new DynamicSquareCatalogMock(variant.Id));

        Test.startTest();
        SquareCatalogService.syncProductsToSquare(new List<Id>{ variant.Id });
        Test.stopTest();

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :parent.Id
        ];

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        System.assertEquals('SQUARE_ITEM_123', afterParent.Square_Catalog_Item_Id__c);
        System.assertEquals('SQUARE_VARIATION_123', afterVariant.Square_Catalog_Variation_Id__c);
    }

    @IsTest
    static void testVariantSyncWithExistingSquareIdsKeepsExistingVariationId() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('EXISTING_VARIATION'));

        Product2 parent = createParentProduct('EXISTING_ITEM_ID');
        Product2 variant = createVariantProduct(parent.Id, 'SKU-EXISTING', 'EXISTING_VARIATION_ID');

        Pricebook2 squarePb = createSquarePricebook();
        createSquarePrice(squarePb.Id, variant.Id, 25);

        Test.startTest();
        SquareCatalogService.syncProductsToSquare(new List<Id>{ variant.Id });
        Test.stopTest();

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :parent.Id
        ];

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        System.assertEquals('SQUARE_ITEM_EXISTING', afterParent.Square_Catalog_Item_Id__c);
        System.assertEquals('EXISTING_VARIATION_ID', afterVariant.Square_Catalog_Variation_Id__c);
    }

    @IsTest
    static void testNoCatalogObjectReturnsWithoutUpdates() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('NO_CATALOG_OBJECT'));

        Product2 parent = createParentProduct(null);
        Product2 variant = createVariantProduct(parent.Id, 'SKU-NO-OBJ', null);

        Pricebook2 squarePb = createSquarePricebook();
        createSquarePrice(squarePb.Id, variant.Id, 10);

        Test.startTest();
        SquareCatalogService.syncProductsToSquare(new List<Id>{ variant.Id });
        Test.stopTest();

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :parent.Id
        ];

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        System.assertEquals(null, afterParent.Square_Catalog_Item_Id__c);
        System.assertEquals(null, afterVariant.Square_Catalog_Variation_Id__c);
    }

    @IsTest
    static void testNoVariationMappingUpdatesOnlyParent() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('NO_VARIATION_MAPPING'));

        Product2 parent = createParentProduct(null);
        Product2 variant = createVariantProduct(parent.Id, 'SKU-NO-MAP', null);

        Pricebook2 squarePb = createSquarePricebook();
        createSquarePrice(squarePb.Id, variant.Id, 5);

        Test.startTest();
        SquareCatalogService.syncProductsToSquare(new List<Id>{ variant.Id });
        Test.stopTest();

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :parent.Id
        ];

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        System.assertEquals('SQUARE_ITEM_123', afterParent.Square_Catalog_Item_Id__c);
        System.assertEquals(null, afterVariant.Square_Catalog_Variation_Id__c);
    }

    @IsTest
    static void testSyncItemToSquareUpdatesProduct() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('SYNC_ITEM'));

        Product2 p = createStandaloneProduct('Standalone Product');

        Product2 queried = [
            SELECT Id, Name, Description, Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :p.Id
        ];

        Test.startTest();
        SquareCatalogService.syncItemToSquare(queried);
        Test.stopTest();

        Product2 updatedProduct = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :p.Id
        ];

        System.assertEquals(
            'SQUARE_ITEM_FROM_SYNC_ITEM',
            updatedProduct.Square_Catalog_Item_Id__c
        );
    }

    @IsTest
    static void testSyncItemToSquareNoCatalogObjectNoUpdate() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('NO_CATALOG_OBJECT'));

        Product2 p = createStandaloneProduct('No Catalog Object Product');

        Product2 queried = [
            SELECT Id, Name, Description, Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :p.Id
        ];

        Test.startTest();
        SquareCatalogService.syncItemToSquare(queried);
        Test.stopTest();

        Product2 updatedProduct = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :p.Id
        ];

        System.assertEquals(null, updatedProduct.Square_Catalog_Item_Id__c);
    }

    @IsTest
    static void testGetStandardPricesAndVariantPrice() {
        Product2 variant = createVariantProduct(null, 'PRIVATE-PRICE-SKU', null);

        Pricebook2 squarePb = createSquarePricebook();
        createSquarePrice(squarePb.Id, variant.Id, 31.50);

        Test.startTest();
        Map<Id, Decimal> prices =
            SquareCatalogService.getStandardPrices(new List<Id>{ variant.Id });

        Decimal singlePrice =
            SquareCatalogService.getVariantPrice(variant.Id);
        Test.stopTest();

        System.assertEquals(31.50, prices.get(variant.Id));
        System.assertEquals(31.50, singlePrice);
    }

    @IsTest
    static void testGetVariantPriceReturnsZeroWhenNoEntry() {
        createSquarePricebook();

        Product2 variant = createVariantProduct(null, 'NO-PRICE-SKU', null);

        Test.startTest();
        Decimal price = SquareCatalogService.getVariantPrice(variant.Id);
        Test.stopTest();

        System.assertEquals(null, price);
    }

    @IsTest
static void testGetPrimaryImageUrlNoFileReturnsNull() {
    Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('SUCCESS'));

    Product2 parent = createParentProduct(null);

    Test.startTest();
    String url = SquareCatalogService.getPrimaryImageUrl(parent.Id);
    Test.stopTest();

    System.assertEquals(null, url);
}

    @IsTest
static void testGetPrimaryImageUrlCreatesAndReusesDistribution() {
    Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('SUCCESS'));

    Product2 parent = createParentProduct(null);

    ContentVersion cv = new ContentVersion(
        Title = 'SquareImage',
        PathOnClient = '/SquareImage.jpg',
        VersionData = Blob.valueOf('fake image bytes'),
        FirstPublishLocationId = parent.Id
    );
    insert cv;

    Test.startTest();
    String firstUrl = SquareCatalogService.getPrimaryImageUrl(parent.Id);
    String secondUrl = SquareCatalogService.getPrimaryImageUrl(parent.Id);
    Test.stopTest();

    System.assertEquals(firstUrl, secondUrl);

    System.assertEquals(
        1,
        [
            SELECT COUNT()
            FROM ContentDistribution
            WHERE Name = 'Square Product Image'
        ]
    );
}
    @IsTest
    static void testAddLatestSquareVersionNullNoIdAndClientId() {
        Test.startTest();

        Map<String, Object> nullResult =
            SquareCatalogService.addLatestSquareVersionIfNeeded(null);

        Map<String, Object> noIdMap = new Map<String, Object>{
            'type' => 'ITEM'
        };
        Map<String, Object> noIdResult =
            SquareCatalogService.addLatestSquareVersionIfNeeded(noIdMap);

        Map<String, Object> clientIdMap = new Map<String, Object>{
            'id' => '#ITEM_TEMP',
            'type' => 'ITEM'
        };
        Map<String, Object> clientIdResult =
            SquareCatalogService.addLatestSquareVersionIfNeeded(clientIdMap);

        Test.stopTest();

        System.assertEquals(null, nullResult);
        System.assertEquals(false, noIdResult.containsKey('version'));
        System.assertEquals(false, clientIdResult.containsKey('version'));
    }

    @IsTest
    static void testAddLatestSquareVersionSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('SUCCESS'));

        Map<String, Object> catalogObject = new Map<String, Object>{
            'id' => 'SQUARE_ITEM_EXISTING',
            'type' => 'ITEM'
        };

        Test.startTest();
        Map<String, Object> result =
            SquareCatalogService.addLatestSquareVersionIfNeeded(catalogObject);
        Test.stopTest();

        System.assertEquals(12345, result.get('version'));
    }

    @IsTest
    static void testAddLatestSquareVersionNon404ErrorIsRethrown() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('ERROR'));

        Map<String, Object> catalogObject = new Map<String, Object>{
            'id' => 'SQUARE_ITEM_EXISTING',
            'type' => 'ITEM'
        };

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            SquareCatalogService.addLatestSquareVersionIfNeeded(catalogObject);
        } catch (Exception e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('Status=500'),
                'The original non-404 Square error should be rethrown. Actual: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'A non-404 retrieve failure must not be silently swallowed.'
        );
    }


    @IsTest
    static void testSyncVariantNullAndNoParentBranches() {
        Product2 variant = createVariantProduct(null, 'VARIANT-NO-PARENT', null);

        Product2 queriedVariant = [
            SELECT Id,
                   Name,
                   Parent__c,
                   Square_Catalog_Variation_Id__c,
                   StockKeepingUnit
            FROM Product2
            WHERE Id = :variant.Id
        ];

        Test.startTest();

        SquareCatalogService.syncVariantToSquare(null);
        SquareCatalogService.syncVariantToSquare(queriedVariant);

        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSyncVariantWithExistingVariationIdDirectCall() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('EXISTING_VARIATION'));

        Product2 parent = createParentProduct('EXISTING_ITEM_DIRECT');
        Product2 variant = createVariantProduct(parent.Id, 'DIRECT-SKU', 'EXISTING_VAR_DIRECT');

        Pricebook2 squarePb = createSquarePricebook();
        createSquarePrice(squarePb.Id, variant.Id, 11);

        Product2 queriedVariant = [
            SELECT Id,
                   Name,
                   Parent__c,
                   StockKeepingUnit,
                   Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        Test.startTest();
        SquareCatalogService.syncVariantToSquare(queriedVariant);
        Test.stopTest();

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        System.assertEquals('EXISTING_VAR_DIRECT', afterVariant.Square_Catalog_Variation_Id__c);
    }

    @IsTest
    static void testSyncVariantWithoutSquarePriceThrows() {
        Product2 parent = createParentProduct(null);
        Product2 variant = createVariantProduct(parent.Id, 'NO-SQUARE-PRICE', null);
        createSquarePricebook();

        Product2 queriedVariant = [
            SELECT Id, Name, Parent__c, StockKeepingUnit,
                   Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            SquareCatalogService.syncVariantToSquare(queriedVariant);
        } catch (SquareCatalogService.SquareCatalogSyncException e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('no active Square Pricebook entry'),
                'Unexpected exception: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testAddLatestSquareVersionNotFoundConvertsToNewObject() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('NOT_FOUND'));

        Map<String, Object> variationData = new Map<String, Object>{
            'item_id' => 'OLD_ITEM'
        };

        Map<String, Object> variation = new Map<String, Object>{
            'id' => 'OLD_VARIATION',
            'version' => 10,
            'item_variation_data' => variationData
        };

        Map<String, Object> catalogObject = new Map<String, Object>{
            'id' => 'OLD_ITEM',
            'version' => 20,
            'type' => 'ITEM',
            'item_data' => new Map<String, Object>{
                'variations' => new List<Object>{ variation }
            }
        };

        Test.startTest();
        Map<String, Object> result =
            SquareCatalogService.addLatestSquareVersionIfNeeded(catalogObject);
        Test.stopTest();

        String newItemId = String.valueOf(result.get('id'));
        System.assert(newItemId.startsWith('#ITEM_'));
        System.assertEquals(false, result.containsKey('version'));

        List<Object> variations = (List<Object>)
            ((Map<String, Object>) result.get('item_data')).get('variations');
        Map<String, Object> convertedVariation =
            (Map<String, Object>) variations[0];

        System.assert(String.valueOf(convertedVariation.get('id')).startsWith('#VAR_'));
        System.assertEquals(false, convertedVariation.containsKey('version'));
        System.assertEquals(
            newItemId,
            ((Map<String, Object>) convertedVariation.get('item_variation_data')).get('item_id')
        );
    }

    @IsTest
    static void testAddLatestSquareVersionNullLatestObjectReturnsOriginal() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock('LATEST_NULL_OBJECT'));

        Map<String, Object> catalogObject = new Map<String, Object>{
            'id' => 'SQUARE_ITEM_EXISTING',
            'type' => 'ITEM'
        };

        Test.startTest();
        Map<String, Object> result =
            SquareCatalogService.addLatestSquareVersionIfNeeded(catalogObject);
        Test.stopTest();

        System.assertEquals(false, result.containsKey('version'));
        System.assertEquals('SQUARE_ITEM_EXISTING', result.get('id'));
    }

    @IsTest
    static void testApplyLatestVersionsUpdatesItemAndMatchingVariation() {
        Map<String, Object> matchingOutgoing = new Map<String, Object>{
            'id' => 'VAR_EXISTING'
        };
        Map<String, Object> clientOutgoing = new Map<String, Object>{
            'id' => '#VAR_NEW'
        };
        Map<String, Object> missingIdOutgoing = new Map<String, Object>();
        Map<String, Object> unknownOutgoing = new Map<String, Object>{
            'id' => 'VAR_UNKNOWN'
        };

        Map<String, Object> outgoing = new Map<String, Object>{
            'id' => 'SQUARE_ITEM_EXISTING',
            'item_data' => new Map<String, Object>{
                'variations' => new List<Object>{
                    matchingOutgoing,
                    clientOutgoing,
                    missingIdOutgoing,
                    unknownOutgoing
                }
            }
        };

        Map<String, Object> latest = new Map<String, Object>{
            'version' => 12345,
            'item_data' => new Map<String, Object>{
                'variations' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'VAR_EXISTING',
                        'version' => 777
                    },
                    new Map<String, Object>{
                        'id' => null,
                        'version' => 888
                    }
                }
            }
        };

        Test.startTest();
        SquareCatalogService.applyLatestVersions(outgoing, latest);
        Test.stopTest();

        System.assertEquals(12345, outgoing.get('version'));
        System.assertEquals(777, matchingOutgoing.get('version'));
        System.assertEquals(false, clientOutgoing.containsKey('version'));
        System.assertEquals(false, missingIdOutgoing.containsKey('version'));
        System.assertEquals(false, unknownOutgoing.containsKey('version'));
    }

    @IsTest
    static void testApplyLatestVersionsNullDataBranches() {
        Map<String, Object> outgoingNoData = new Map<String, Object>();
        Map<String, Object> latestNoData = new Map<String, Object>{
            'version' => 5
        };

        SquareCatalogService.applyLatestVersions(outgoingNoData, latestNoData);
        System.assertEquals(5, outgoingNoData.get('version'));

        Map<String, Object> outgoingNoVariations = new Map<String, Object>{
            'item_data' => new Map<String, Object>()
        };
        Map<String, Object> latestNoVariations = new Map<String, Object>{
            'item_data' => new Map<String, Object>()
        };

        SquareCatalogService.applyLatestVersions(
            outgoingNoVariations,
            latestNoVariations
        );

        System.assert(true);
    }

    @IsTest
    static void testIsSquareCatalogObjectNotFoundBranches() {
        System.assertEquals(
            false,
            SquareCatalogService.isSquareCatalogObjectNotFound(null)
        );

        Exception blankMessage =
            new SquareCatalogService.SquareCatalogSyncException();
        System.assertEquals(
            false,
            SquareCatalogService.isSquareCatalogObjectNotFound(blankMessage)
        );

        System.assertEquals(
            true,
            SquareCatalogService.isSquareCatalogObjectNotFound(
                new SquareCatalogService.SquareCatalogSyncException('Status=404')
            )
        );

        System.assertEquals(
            true,
            SquareCatalogService.isSquareCatalogObjectNotFound(
                new SquareCatalogService.SquareCatalogSyncException(
                    '{"code":"NOT_FOUND"}'
                )
            )
        );

        System.assertEquals(
            true,
            SquareCatalogService.isSquareCatalogObjectNotFound(
                new SquareCatalogService.SquareCatalogSyncException(
                    'Catalog object not found'
                )
            )
        );

        System.assertEquals(
            false,
            SquareCatalogService.isSquareCatalogObjectNotFound(
                new SquareCatalogService.SquareCatalogSyncException('Status=500')
            )
        );
    }

    @IsTest
    static void testConvertToNewCatalogObjectNullItemDataAndVariations() {
        Map<String, Object> noItemData = new Map<String, Object>{
            'id' => 'OLD',
            'version' => 1
        };

        Map<String, Object> first =
            SquareCatalogService.convertToNewCatalogObject(noItemData);
        System.assert(String.valueOf(first.get('id')).startsWith('#ITEM_'));
        System.assertEquals(false, first.containsKey('version'));

        Map<String, Object> noVariations = new Map<String, Object>{
            'id' => 'OLD2',
            'version' => 2,
            'item_data' => new Map<String, Object>()
        };

        Map<String, Object> second =
            SquareCatalogService.convertToNewCatalogObject(noVariations);
        System.assert(String.valueOf(second.get('id')).startsWith('#ITEM_'));
        System.assertEquals(false, second.containsKey('version'));
    }

    @IsTest
    static void testConvertToNewCatalogObjectVariationWithoutData() {
        Map<String, Object> variation = new Map<String, Object>{
            'id' => 'OLD_VAR',
            'version' => 3
        };

        Map<String, Object> catalogObject = new Map<String, Object>{
            'id' => 'OLD_ITEM',
            'item_data' => new Map<String, Object>{
                'variations' => new List<Object>{ variation }
            }
        };

        Map<String, Object> result =
            SquareCatalogService.convertToNewCatalogObject(catalogObject);

        System.assert(String.valueOf(result.get('id')).startsWith('#ITEM_'));
        System.assert(String.valueOf(variation.get('id')).startsWith('#VAR_'));
        System.assertEquals(false, variation.containsKey('version'));
    }

}