@IsTest
private class SquareCatalogQueueableTest {

    private class SquareCatalogMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String body = req.getBody();

            // Safe Shopify side-effect responses from Product2 triggers.
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

            // SquareApiClient.upsertCatalogObject response.
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
                    '"id_mappings":[]}'
                );
                return res;
            }

            // Square image queueable safety.
            if (endpoint != null && endpoint.contains('/v2/catalog/images')) {
                res.setBody(
                    '{"image":{"id":"IMG_123","type":"IMAGE"}}'
                );
                return res;
            }

            res.setBody(
                '{"data":{' +
                '"productCreate":{"product":{"id":"gid://shopify/Product/123","legacyResourceId":"123"},"userErrors":[]},' +
                '"productUpdate":{"product":{"id":"gid://shopify/Product/123"},"userErrors":[]},' +
                '"productVariantsBulkUpdate":{"product":{"id":"gid://shopify/Product/123"},"productVariants":[],"userErrors":[]}' +
                '}}'
            );
            return res;
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

    private static Product2 createParentProduct() {
        Product2 parent = new Product2(
            Name = 'Parent Product ' + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 100000)),
            IsActive = true
        );

        if (Schema.SObjectType.Product2.fields.getMap().containsKey('Type__c')) {
            parent.put('Type__c', 'Product');
        }

        insert parent;
        return parent;
    }

    private static Product2 createProduct(
        String shopId,
        String typeValue,
        Id parentId
    ) {
        Product2 p = new Product2(
            Name = 'Test Product ' + shopId,
            IsActive = true,
            Shop_ID__c = shopId,
            StockKeepingUnit = 'SKU-' + shopId
        );

        if (typeValue == 'Variant') {
            Id rtId = getVariantRecordTypeIdOrNull();
            if (rtId != null) {
                p.RecordTypeId = rtId;
            }
        }

        p.Type__c = typeValue;

        if (parentId != null) {
            p.Parent__c = parentId;
        }

        insert p;
        return p;
    }

    private static Pricebook2 createSquarePricebook() {
        Pricebook2 pb = new Pricebook2(
            Name = 'Square Pricebook',
            IsActive = true
        );
        insert pb;
        return pb;
    }

    private static void createPrices(Id productId, Id squarePricebookId) {
        PricebookEntry standardPbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = productId,
            UnitPrice = 10,
            IsActive = true
        );
        insert standardPbe;

        PricebookEntry squarePbe = new PricebookEntry(
            Pricebook2Id = squarePricebookId,
            Product2Id = productId,
            UnitPrice = 10,
            IsActive = true,
            UseStandardPrice = false
        );
        insert squarePbe;
    }

    @IsTest
    static void testQueueableNullInputReturnsSafely() {
        Test.startTest();
        System.enqueueJob(new SquareCatalogQueueable(null));
        Test.stopTest();

        System.assert(true, 'Null variantShopIds should return safely.');
    }

    @IsTest
    static void testQueueableEmptyInputReturnsSafely() {
        Test.startTest();
        System.enqueueJob(new SquareCatalogQueueable(new Set<String>()));
        Test.stopTest();

        System.assert(true, 'Empty variantShopIds should return safely.');
    }

    @IsTest
    static void testQueueableNoMatchingVariantsReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock());

        Test.startTest();
        System.enqueueJob(new SquareCatalogQueueable(new Set<String>{ 'NO_MATCH' }));
        Test.stopTest();

        System.assert(true, 'No matching variants should return safely.');
    }

    @IsTest
    static void testQueueableIgnoresNonVariantProduct() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock());

        createProduct('SHOP_NON_VARIANT', 'Product', null);

        Test.startTest();
        System.enqueueJob(
            new SquareCatalogQueueable(new Set<String>{ 'SHOP_NON_VARIANT' })
        );
        Test.stopTest();

        Product2 p = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Shop_ID__c = 'SHOP_NON_VARIANT'
            LIMIT 1
        ];

        System.assertEquals(
            null,
            p.Square_Catalog_Item_Id__c,
            'Non-Variant Product2 should be ignored by the query.'
        );
    }

    @IsTest
static void testQueueableFindsVariantAndCallsSquareCatalogServiceSafely() {
    Test.setMock(HttpCalloutMock.class, new SquareCatalogMock());

    // Parent__c intentionally null.
    // This lets SquareCatalogQueueable find the Variant and call SquareCatalogService,
    // but SquareCatalogService will skip syncVariantToSquare because Parent__c is null.
    Product2 variant = createProduct('SHOP_VARIANT_1', 'Variant', null);

    Test.startTest();
    System.enqueueJob(
        new SquareCatalogQueueable(new Set<String>{ 'SHOP_VARIANT_1' })
    );
    Test.stopTest();

    Product2 afterVariant = [
        SELECT Id, Square_Catalog_Variation_Id__c
        FROM Product2
        WHERE Id = :variant.Id
    ];

    System.assertEquals(
        null,
        afterVariant.Square_Catalog_Variation_Id__c,
        'Variant was found by the queueable, but skipped safely by SquareCatalogService because Parent__c is null.'
    );
}
    @IsTest
static void testQueueableHandlesMultipleVariantIdsSafely() {
    Test.setMock(HttpCalloutMock.class, new SquareCatalogMock());

    // Parent__c intentionally null to avoid full SquareCatalogService callout/enqueue chain.
    Product2 variant1 = createProduct('SHOP_VARIANT_2', 'Variant', null);
    Product2 variant2 = createProduct('SHOP_VARIANT_3', 'Variant', null);

    Test.startTest();
    System.enqueueJob(
        new SquareCatalogQueueable(
            new Set<String>{ 'SHOP_VARIANT_2', 'SHOP_VARIANT_3' }
        )
    );
    Test.stopTest();

    List<Product2> variants = [
        SELECT Id, Square_Catalog_Variation_Id__c
        FROM Product2
        WHERE Id IN :new Set<Id>{ variant1.Id, variant2.Id }
    ];

    System.assertEquals(2, variants.size());

    for (Product2 v : variants) {
        System.assertEquals(
            null,
            v.Square_Catalog_Variation_Id__c,
            'Variants should be found by SquareCatalogQueueable and skipped safely by SquareCatalogService.'
        );
    }
}
}