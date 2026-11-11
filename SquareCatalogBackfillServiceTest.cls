@IsTest
private class SquareCatalogBackfillServiceTest {

    private static Integer counter = 0;
    private static User shopifyWebhookUser;

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    private static String uniqueText(String prefix) {
        counter++;
        return prefix + '-' + String.valueOf(DateTime.now().getTime()) + '-' + counter;
    }

    private static User getShopifyWebhookUser() {
        if (shopifyWebhookUser != null) {
            return shopifyWebhookUser;
        }

        String suffix = String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Math.abs(Crypto.getRandomInteger()));

        User u = new User(
            FirstName = 'Shopify',
            LastName = 'Webhook Site',
            Alias = 'shpwhk',
            Email = 'shopify_webhook_site_' + suffix + '@test.com',
            Username = 'shopify_webhook_site_' + suffix + '@test.com',
            CommunityNickname = ('shopifywebhook' + suffix).left(40),
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert u;
        shopifyWebhookUser = u;
        return shopifyWebhookUser;
    }

    private static Boolean fieldExists(String objectApiName, String fieldApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName) &&
            Schema.getGlobalDescribe()
                .get(objectApiName)
                .getDescribe()
                .fields
                .getMap()
                .containsKey(fieldApiName);
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

    private class ProductPair {
        Product2 parentProduct;
        Product2 variantProduct;
    }

    private static ProductPair createParentAndVariant(
        String sku,
        String existingSquareItemId,
        String existingSquareVariationId
    ) {
        Product2 parent = new Product2(
            Name = uniqueText('Parent Product'),
            IsActive = true,
            Updated_by_Integration__c = true
        );

        if (fieldExists('Product2', 'Type__c')) {
            parent.put('Type__c', 'Product');
        }

        if (existingSquareItemId != null) {
            parent.Square_Catalog_Item_Id__c = existingSquareItemId;
        }

        Product2 variant = new Product2(
            Name = uniqueText('Variant ' + sku),
            IsActive = true,
            StockKeepingUnit = sku,
            Updated_by_Integration__c = true
        );

        if (fieldExists('Product2', 'Type__c')) {
            variant.put('Type__c', 'Variant');
        }

        Id rtId = getVariantRecordTypeIdOrNull();
        if (rtId != null) {
            variant.RecordTypeId = rtId;
        }

        if (existingSquareVariationId != null) {
            variant.Square_Catalog_Variation_Id__c = existingSquareVariationId;
        }

        System.runAs(getShopifyWebhookUser()) {
            insert parent;
            variant.Parent__c = parent.Id;
            insert variant;
        }

        ProductPair pair = new ProductPair();
        pair.parentProduct = parent;
        pair.variantProduct = variant;
        return pair;
    }

    private static Product2 createNonVariant(String sku) {
        Product2 p = new Product2(
            Name = uniqueText('Non Variant ' + sku),
            IsActive = true,
            StockKeepingUnit = sku,
            Updated_by_Integration__c = true
        );

        if (fieldExists('Product2', 'Type__c')) {
            p.put('Type__c', 'Product');
        }

        System.runAs(getShopifyWebhookUser()) {
            insert p;
        }

        return p;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mock
    // Handles both Square catalog search and possible Shopify Product2
    // trigger side-effect callouts.
    // ─────────────────────────────────────────────────────────────────────

    private class SquareBackfillMock implements HttpCalloutMock {
        private String mode;

        SquareBackfillMock(String modeValue) {
            mode = modeValue;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

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
                    '{"id":""},' +
                    '{"id":"SQVAR_NO_DATA"},' +
                    '{"id":"SQVAR_NO_SKU","item_variation_data":{}},' +
                    '{"id":"SQVAR_BLANK_SKU","item_variation_data":{"sku":"   ","item_id":"SQITEM_BLANK"}},' +
                    '{"id":"SQVAR_BLANK_ITEM","item_variation_data":{"sku":"SKU-INVALID","item_id":"   "}}' +
                    ']}'
                );
                return res;
            }

            if (mode == 'NO_MATCHING_SALESFORCE_SKU') {
                res.setBody(
                    '{"objects":[' +
                    '{"id":"SQVAR_NO_MATCH","item_variation_data":{"sku":"NO-MATCH-SKU","item_id":"SQITEM_NO_MATCH"}}' +
                    ']}'
                );
                return res;
            }

            if (mode == 'MATCH_EXISTING_VALUE') {
                res.setBody(
                    '{"objects":[' +
                    '{"id":"SQVAR_EXISTING","item_variation_data":{"sku":"EXISTING-SKU","item_id":"SQITEM_EXISTING"}}' +
                    ']}'
                );
                return res;
            }

            if (mode == 'MATCH_TRIM_UPPER') {
                res.setBody(
                    '{"objects":[' +
                    '{"id":"SQVAR_TRIM_UPPER","item_variation_data":{"sku":"  mixed-sku  ","item_id":"SQITEM_TRIM_UPPER"}}' +
                    ']}'
                );
                return res;
            }

            if (mode == 'DUPLICATE_SKU') {
                res.setBody(
                    '{"objects":[' +
                    '{"id":"SQVAR_DUP_1","item_variation_data":{"sku":"DUP-SKU","item_id":"SQITEM_DUP_1"}},' +
                    '{"id":"SQVAR_DUP_2","item_variation_data":{"sku":"dup-sku","item_id":"SQITEM_DUP_2"}}' +
                    ']}'
                );
                return res;
            }

            if (mode == 'MULTI_MATCH') {
                res.setBody(
                    '{"objects":[' +
                    '{"id":"SQVAR_A","item_variation_data":{"sku":"SKU-A","item_id":"SQITEM_A"}},' +
                    '{"id":"SQVAR_B","item_variation_data":{"sku":"SKU-B","item_id":"SQITEM_B"}}' +
                    ']}'
                );
                return res;
            }

            res.setBody(
                '{"objects":[' +
                '{"id":"SQVAR_123","item_variation_data":{"sku":"SKU-123","item_id":"SQITEM_123"}}' +
                ']}'
            );
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testNoObjectsKeyReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('NO_OBJECTS_KEY'));

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        System.assert(true, 'No objects key should return safely.');
    }

    @IsTest
    static void testNullObjectsReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('NULL_OBJECTS'));

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        System.assert(true, 'Null objects should return safely.');
    }

    @IsTest
    static void testEmptyObjectsReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('EMPTY_OBJECTS'));

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        System.assert(true, 'Empty objects should return safely.');
    }

    @IsTest
    static void testInvalidObjectsProduceNoUpdates() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('INVALID_OBJECTS'));

        ProductPair pair = createParentAndVariant('SKU-INVALID', null, null);

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :pair.variantProduct.Id
            LIMIT 1
        ];

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :pair.parentProduct.Id
            LIMIT 1
        ];

        System.assertEquals(null, afterVariant.Square_Catalog_Variation_Id__c);
        System.assertEquals(null, afterParent.Square_Catalog_Item_Id__c);
    }

    @IsTest
    static void testMatchingSkuUpdatesVariantAndParent() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('SUCCESS'));

        ProductPair pair = createParentAndVariant('SKU-123', null, null);

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c, Parent__c
            FROM Product2
            WHERE Id = :pair.variantProduct.Id
            LIMIT 1
        ];

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :pair.parentProduct.Id
            LIMIT 1
        ];

        System.assertEquals('SQVAR_123', afterVariant.Square_Catalog_Variation_Id__c);
        System.assertEquals('SQITEM_123', afterParent.Square_Catalog_Item_Id__c);
    }

    @IsTest
    static void testNonVariantIsIgnored() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('SUCCESS'));

        Product2 nonVariant = createNonVariant('SKU-123');

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        Product2 afterProduct = [
            SELECT Square_Catalog_Variation_Id__c, Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :nonVariant.Id
            LIMIT 1
        ];

        System.assertEquals(null, afterProduct.Square_Catalog_Variation_Id__c);
        System.assertEquals(null, afterProduct.Square_Catalog_Item_Id__c);
    }

    @IsTest
    static void testNoMatchingSalesforceSkuNoUpdate() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('NO_MATCHING_SALESFORCE_SKU'));

        ProductPair pair = createParentAndVariant('DIFFERENT-SKU', null, null);

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :pair.variantProduct.Id
            LIMIT 1
        ];

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :pair.parentProduct.Id
            LIMIT 1
        ];

        System.assertEquals(null, afterVariant.Square_Catalog_Variation_Id__c);
        System.assertEquals(null, afterParent.Square_Catalog_Item_Id__c);
    }

    @IsTest
    static void testExistingSameValuesDoNotChange() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('MATCH_EXISTING_VALUE'));

        ProductPair pair = createParentAndVariant(
            'EXISTING-SKU',
            'SQITEM_EXISTING',
            'SQVAR_EXISTING'
        );

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :pair.variantProduct.Id
            LIMIT 1
        ];

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :pair.parentProduct.Id
            LIMIT 1
        ];

        System.assertEquals('SQVAR_EXISTING', afterVariant.Square_Catalog_Variation_Id__c);
        System.assertEquals('SQITEM_EXISTING', afterParent.Square_Catalog_Item_Id__c);
    }

    @IsTest
    static void testSkuTrimAndUppercaseMatchUpdatesVariantAndParent() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('MATCH_TRIM_UPPER'));

        ProductPair pair = createParentAndVariant('MIXED-SKU', null, null);

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :pair.variantProduct.Id
            LIMIT 1
        ];

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :pair.parentProduct.Id
            LIMIT 1
        ];

        System.assertEquals('SQVAR_TRIM_UPPER', afterVariant.Square_Catalog_Variation_Id__c);
        System.assertEquals('SQITEM_TRIM_UPPER', afterParent.Square_Catalog_Item_Id__c);
    }

    @IsTest
    static void testDuplicateSquareSkuIsSkipped() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('DUPLICATE_SKU'));

        ProductPair pair = createParentAndVariant('DUP-SKU', null, null);

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        Product2 afterVariant = [
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id = :pair.variantProduct.Id
            LIMIT 1
        ];

        Product2 afterParent = [
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :pair.parentProduct.Id
            LIMIT 1
        ];

        System.assertEquals(null, afterVariant.Square_Catalog_Variation_Id__c);
        System.assertEquals(null, afterParent.Square_Catalog_Item_Id__c);
    }

    @IsTest
    static void testMultipleMatchingSkusUpdateMultipleVariantsAndParents() {
        Test.setMock(HttpCalloutMock.class, new SquareBackfillMock('MULTI_MATCH'));

        ProductPair pairA = createParentAndVariant('SKU-A', null, null);
        ProductPair pairB = createParentAndVariant('SKU-B', null, null);

        Test.startTest();
        SquareCatalogBackfillService.backfillSquareIdsBySku();
        Test.stopTest();

        Map<Id, Product2> variants = new Map<Id, Product2>([
            SELECT Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id IN :new Set<Id>{ pairA.variantProduct.Id, pairB.variantProduct.Id }
        ]);

        Map<Id, Product2> parents = new Map<Id, Product2>([
            SELECT Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id IN :new Set<Id>{ pairA.parentProduct.Id, pairB.parentProduct.Id }
        ]);

        System.assertEquals('SQVAR_A', variants.get(pairA.variantProduct.Id).Square_Catalog_Variation_Id__c);
        System.assertEquals('SQVAR_B', variants.get(pairB.variantProduct.Id).Square_Catalog_Variation_Id__c);

        System.assertEquals('SQITEM_A', parents.get(pairA.parentProduct.Id).Square_Catalog_Item_Id__c);
        System.assertEquals('SQITEM_B', parents.get(pairB.parentProduct.Id).Square_Catalog_Item_Id__c);
    }
}