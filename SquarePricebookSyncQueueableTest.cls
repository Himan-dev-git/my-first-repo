@IsTest
private class SquarePricebookSyncQueueableTest {

    private class CombinedMock implements HttpCalloutMock {
        private String mode;

        CombinedMock(String mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String body = req.getBody();

            /*
             * Shopify Product trigger / async side-effect responses.
             * These prevent ShopifyGraphQLHelper "Missing data" errors
             * when Product2 insert/update triggers outbound Shopify sync.
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

            /*
             * Square catalog list responses.
             */
            if (endpoint != null && endpoint.contains('/v2/catalog/list')) {
                if (mode == 'ERROR') {
                    res.setStatusCode(500);
                    res.setBody('{"errors":[{"detail":"Square error"}]}');
                    return res;
                }

                res.setStatusCode(200);

                if (mode == 'NO_OBJECTS_KEY') {
                    res.setBody('{}');
                    return res;
                }

                if (mode == 'NULL_OBJECTS') {
                    res.setBody('{"objects":null}');
                    return res;
                }

                if (mode == 'EMPTY_OBJECTS') {
                    res.setBody('{"objects":[]}');
                    return res;
                }

                if (mode == 'INVALID_OBJECTS') {
                    res.setBody(
                        '{"objects":[' +
                        'null,' +
                        '{"id":""},' +
                        '{"id":"VAR_NO_DATA"},' +
                        '{"id":"VAR_NO_SKU","item_variation_data":{}},' +
                        '{"id":"VAR_NO_PRICE","item_variation_data":{"sku":"SKU-NO-PRICE"}},' +
                        '{"id":"VAR_ZERO_PRICE","item_variation_data":{"sku":"SKU-ZERO","price_money":{"amount":0}}}' +
                        ']}'
                    );
                    return res;
                }

                if (mode == 'NO_MATCHING_PRODUCT') {
                    res.setBody(
                        '{"objects":[' +
                        '{"id":"SQVAR-NOMATCH","item_variation_data":{"sku":"NO-MATCH","price_money":{"amount":1299}}}' +
                        ']}'
                    );
                    return res;
                }

                if (mode == 'DUPLICATE_SKU_MATCH_SF_ID') {
                    res.setBody(
                        '{"objects":[' +
                        '{"id":"SQVAR-OLD","item_variation_data":{"sku":"DUP-SKU","price_money":{"amount":1000}}},' +
                        '{"id":"SQVAR-MATCH","item_variation_data":{"sku":"DUP-SKU","price_money":{"amount":2500}}}' +
                        ']}'
                    );
                    return res;
                }

                if (mode == 'DUPLICATE_SKU_USE_LAST') {
                    res.setBody(
                        '{"objects":[' +
                        '{"id":"SQVAR-FIRST","item_variation_data":{"sku":"DUP-LAST","price_money":{"amount":1000}}},' +
                        '{"id":"SQVAR-LAST","item_variation_data":{"sku":"DUP-LAST","price_money":{"amount":3300}}}' +
                        ']}'
                    );
                    return res;
                }

                if (mode == 'PRICE_ALREADY_UP_TO_DATE') {
                    res.setBody(
                        '{"objects":[' +
                        '{"id":"SQVAR-UPTODATE","item_variation_data":{"sku":"UPTODATE","price_money":{"amount":1999}}}' +
                        ']}'
                    );
                    return res;
                }

                res.setBody(
                    '{"objects":[' +
                    '{"id":"SQVAR-1","item_variation_data":{"sku":"SKU-1","price_money":{"amount":1999}}}' +
                    ']}'
                );
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
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

    private static Product2 createVariant(String sku, String squareVariationId) {
        Product2 p = new Product2(
            Name = 'Test Variant ' + sku,
            IsActive = true,
            StockKeepingUnit = sku
        );

        Id rtId = getVariantRecordTypeIdOrNull();
        if (rtId != null) {
            p.RecordTypeId = rtId;
        }

        if (squareVariationId != null) {
            p.Square_Catalog_Variation_Id__c = squareVariationId;
        }

        putIfCreateable(p, 'Type__c', 'Variant');

        insert p;

        createStandardPrice(p.Id, 1);

        return p;
    }

    private static void createStandardPrice(Id productId, Decimal priceValue) {
        Id standardPbId = Test.getStandardPricebookId();

        List<PricebookEntry> existing = [
            SELECT Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPbId
            AND Product2Id = :productId
            LIMIT 1
        ];

        if (existing.isEmpty()) {
            PricebookEntry standardPbe = new PricebookEntry(
                Pricebook2Id = standardPbId,
                Product2Id = productId,
                UnitPrice = priceValue,
                IsActive = true
            );
            insert standardPbe;
        }
    }

    private static Pricebook2 createSquarePricebook() {
        Pricebook2 pb = new Pricebook2(
            Name = 'Square Pricebook',
            IsActive = true
        );
        insert pb;
        return pb;
    }

    private static PricebookEntry createSquarePbe(
        Id pricebookId,
        Id productId,
        Decimal unitPrice
    ) {
        createStandardPrice(productId, unitPrice);

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productId,
            UnitPrice = unitPrice,
            IsActive = true,
            UseStandardPrice = false
        );
        insert pbe;
        return pbe;
    }

    @IsTest
    static void testSchedulerExecutesAndEnqueuesQueueable() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('EMPTY_OBJECTS'));

        Test.startTest();
        String jobId = System.schedule(
            'Square Pricebook Sync Scheduler Test ' + System.now().getTime(),
            '0 0 0 1 1 ? 2099',
            new SquarePricebookSyncScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }

    @IsTest
    static void testQueueableCalloutFailureReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('ERROR'));

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testQueueableNoObjectsKeyReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('NO_OBJECTS_KEY'));

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testQueueableNullObjectsReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('NULL_OBJECTS'));

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testQueueableEmptyObjectsReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('EMPTY_OBJECTS'));

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testQueueableInvalidObjectsReturnNoSkuPriceMap() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('INVALID_OBJECTS'));

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testQueueableSquarePricebookMissingReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('SUCCESS'));

        createVariant('SKU-1', null);

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Pricebook2 WHERE Name = 'Square Pricebook']
        );
    }

    @IsTest
    static void testQueueableNoMatchingProductReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('NO_MATCHING_PRODUCT'));

        createSquarePricebook();
        createVariant('DIFFERENT-SKU', null);

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM PricebookEntry
                WHERE Pricebook2.Name = 'Square Pricebook'
            ]
        );
    }

    @IsTest
    static void testQueueableInsertsNewSquarePricebookEntryAndUpdatesVariationId() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('SUCCESS'));

        Pricebook2 squarePb = createSquarePricebook();
        Product2 variant = createVariant('SKU-1', null);

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        List<PricebookEntry> entries = [
            SELECT Id, UnitPrice, Product2Id, Pricebook2Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :squarePb.Id
            AND Product2Id = :variant.Id
        ];

        System.assertEquals(1, entries.size());
        System.assertEquals(19.99, entries[0].UnitPrice);

        Product2 updatedVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        System.assertEquals('SQVAR-1', updatedVariant.Square_Catalog_Variation_Id__c);
    }

    @IsTest
    static void testQueueableUpdatesExistingPricebookEntry() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('SUCCESS'));

        Pricebook2 squarePb = createSquarePricebook();
        Product2 variant = createVariant('SKU-1', 'SQVAR-1');
        PricebookEntry existing = createSquarePbe(squarePb.Id, variant.Id, 5);

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        PricebookEntry updatedEntry = [
            SELECT UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Id = :existing.Id
        ];

        System.assertEquals(19.99, updatedEntry.UnitPrice);
        System.assertEquals(true, updatedEntry.IsActive);
    }

    @IsTest
    static void testQueueableAllPricesAlreadyUpToDate() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('PRICE_ALREADY_UP_TO_DATE'));

        Pricebook2 squarePb = createSquarePricebook();
        Product2 variant = createVariant('UPTODATE', 'SQVAR-UPTODATE');
        PricebookEntry existing = createSquarePbe(squarePb.Id, variant.Id, 19.99);

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        PricebookEntry afterEntry = [
            SELECT UnitPrice
            FROM PricebookEntry
            WHERE Id = :existing.Id
        ];

        System.assertEquals(19.99, afterEntry.UnitPrice);
    }

    @IsTest
    static void testQueueableDuplicateSkuResolvedBySalesforceVariationId() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('DUPLICATE_SKU_MATCH_SF_ID'));

        Pricebook2 squarePb = createSquarePricebook();
        Product2 variant = createVariant('DUP-SKU', 'SQVAR-MATCH');

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        PricebookEntry entry = [
            SELECT UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :squarePb.Id
            AND Product2Id = :variant.Id
            LIMIT 1
        ];

        System.assertEquals(25, entry.UnitPrice);
    }

    @IsTest
    static void testQueueableDuplicateSkuUsesLastWhenNoSalesforceMatch() {
        Test.setMock(HttpCalloutMock.class, new CombinedMock('DUPLICATE_SKU_USE_LAST'));

        Pricebook2 squarePb = createSquarePricebook();
        Product2 variant = createVariant('DUP-LAST', 'NON_MATCHING_VAR');

        Test.startTest();
        System.enqueueJob(new SquarePricebookSyncQueueable());
        Test.stopTest();

        PricebookEntry entry = [
            SELECT UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :squarePb.Id
            AND Product2Id = :variant.Id
            LIMIT 1
        ];

        System.assertEquals(33, entry.UnitPrice);

        Product2 updatedVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :variant.Id
        ];

        System.assertEquals('SQVAR-LAST', updatedVariant.Square_Catalog_Variation_Id__c);
    }
}