@IsTest
private class ShopifyInventoryVariantLookupServiceTest {

    private static Integer counter = 0;
    private static User shopifyWebhookUser;

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    private static String uniqueText(String prefix) {
        counter++;
        return prefix + '-' + String.valueOf(DateTime.now().getTime()) + '-' + counter;
    }

    private static String uniqueNumericText() {
        counter++;
        return String.valueOf(DateTime.now().getTime()) + String.valueOf(counter);
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

    private static Product2 createVariant(String shopifyVariantId) {
        Product2 parentProduct = new Product2(
            Name = uniqueText('Parent Product'),
            IsActive = true,
            Shop_Id__c = 'PARENT-' + shopifyVariantId,
            Updated_by_Integration__c = true
        );

        if (fieldExists('Product2', 'Type__c')) {
            parentProduct.put('Type__c', 'Product');
        }

        Product2 variant = new Product2(
            Name = uniqueText('Variant Product'),
            IsActive = true,
            Shop_Id__c = shopifyVariantId,
            Updated_by_Integration__c = true
        );

        if (fieldExists('Product2', 'Type__c')) {
            variant.put('Type__c', 'Variant');
        }

        Id variantRecordTypeId = getVariantRecordTypeIdOrNull();
        if (variantRecordTypeId != null) {
            variant.RecordTypeId = variantRecordTypeId;
        }

        System.runAs(getShopifyWebhookUser()) {
            insert parentProduct;

            variant.Parent__c = parentProduct.Id;
            insert variant;
        }

        return variant;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mock
    // ─────────────────────────────────────────────────────────────────────

    private class InventoryVariantLookupMock implements HttpCalloutMock {
        private String mode;
        private String variantShopifyId;

        InventoryVariantLookupMock(String modeValue, String variantShopifyIdValue) {
            mode = modeValue;
            variantShopifyId = variantShopifyIdValue;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String body = req.getBody();

            // Safety for Product2 trigger side effects, if any still run.
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
                    '"product":{"id":"gid://shopify/Product/123","title":"Updated Product"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (body != null && body.contains('productVariantsBulkUpdate')) {
                res.setBody(
                    '{"data":{"productVariantsBulkUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"productVariants":[{"id":"gid://shopify/ProductVariant/456","sku":"SKU-1"}],' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'NO_DATA') {
                res.setBody('{}');
                return res;
            }

            if (mode == 'DATA_NULL') {
                res.setBody('{"data":null}');
                return res;
            }

            if (mode == 'INVENTORY_ITEM_NULL') {
                res.setBody('{"data":{"inventoryItem":null}}');
                return res;
            }

            if (mode == 'VARIANT_NULL') {
                res.setBody(
                    '{"data":{"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/111",' +
                    '"variant":null' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'VARIANT_WITH_NULL_ID') {
                res.setBody(
                    '{"data":{"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/111",' +
                    '"variant":{"id":null}' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'FOUND') {
                res.setBody(
                    '{"data":{"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/111",' +
                    '"variant":{"id":"gid://shopify/ProductVariant/' + variantShopifyId + '"}' +
                    '}}}'
                );
                return res;
            }

            // Default: Shopify returns a variant, but Salesforce has no matching Product2.
            res.setBody(
                '{"data":{"inventoryItem":{' +
                '"id":"gid://shopify/InventoryItem/111",' +
                '"variant":{"id":"gid://shopify/ProductVariant/NO_SF_MATCH"}' +
                '}}}'
            );
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testFindVariantByInventoryItemId_Found() {
        String variantShopifyId = uniqueNumericText();
        Product2 variant = createVariant(variantShopifyId);

        Test.setMock(
            HttpCalloutMock.class,
            new InventoryVariantLookupMock('FOUND', variantShopifyId)
        );

        Test.startTest();
        ShopifyInventoryVariantLookupService.VariantContext ctx =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId('111');
        Test.stopTest();

        System.assertNotEquals(null, ctx, 'Context should be returned.');
        System.assertEquals(variant.Id, ctx.variantSalesforceId);
        System.assertEquals(variantShopifyId, ctx.variantShopifyId);
    }

    @IsTest
    static void testFindVariantByInventoryItemId_BlankInput() {
        Test.startTest();

        ShopifyInventoryVariantLookupService.VariantContext ctx1 =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId(null);

        ShopifyInventoryVariantLookupService.VariantContext ctx2 =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId('');

        ShopifyInventoryVariantLookupService.VariantContext ctx3 =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId('   ');

        Test.stopTest();

        System.assertEquals(null, ctx1);
        System.assertEquals(null, ctx2);
        System.assertEquals(null, ctx3);
    }

    @IsTest
    static void testFindVariantByInventoryItemId_NoVariantReturned() {
        Test.setMock(
            HttpCalloutMock.class,
            new InventoryVariantLookupMock('VARIANT_NULL', null)
        );

        Test.startTest();
        ShopifyInventoryVariantLookupService.VariantContext ctx =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId('111');
        Test.stopTest();

        System.assertEquals(null, ctx, 'Should return null when Shopify returns no variant.');
    }

    @IsTest
    static void testFindVariantByInventoryItemId_NoSalesforceVariant() {
        Test.setMock(
            HttpCalloutMock.class,
            new InventoryVariantLookupMock('NO_SF_MATCH', null)
        );

        Test.startTest();
        ShopifyInventoryVariantLookupService.VariantContext ctx =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId('111');
        Test.stopTest();

        System.assertEquals(null, ctx, 'Should return null when no matching Product2 exists.');
    }

    @IsTest
    static void testFindVariantByInventoryItemId_NoDataReturnsNullSafely() {
        Test.setMock(
            HttpCalloutMock.class,
            new InventoryVariantLookupMock('NO_DATA', null)
        );

        Test.startTest();
        ShopifyInventoryVariantLookupService.VariantContext ctx =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId('111');
        Test.stopTest();

        System.assertEquals(null, ctx, 'Missing data should return null safely.');
    }

    @IsTest
    static void testFindVariantByInventoryItemId_DataNullReturnsNullSafely() {
        Test.setMock(
            HttpCalloutMock.class,
            new InventoryVariantLookupMock('DATA_NULL', null)
        );

        Test.startTest();
        ShopifyInventoryVariantLookupService.VariantContext ctx =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId('111');
        Test.stopTest();

        System.assertEquals(null, ctx, 'Null data should return null safely.');
    }

    @IsTest
    static void testFindVariantByInventoryItemId_InventoryItemNullReturnsNullSafely() {
        Test.setMock(
            HttpCalloutMock.class,
            new InventoryVariantLookupMock('INVENTORY_ITEM_NULL', null)
        );

        Test.startTest();
        ShopifyInventoryVariantLookupService.VariantContext ctx =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId('111');
        Test.stopTest();

        System.assertEquals(null, ctx, 'Null inventoryItem should return null safely.');
    }

    @IsTest
    static void testFindVariantByInventoryItemId_VariantIdNullReturnsNullSafely() {
        Test.setMock(
            HttpCalloutMock.class,
            new InventoryVariantLookupMock('VARIANT_WITH_NULL_ID', null)
        );

        Test.startTest();
        ShopifyInventoryVariantLookupService.VariantContext ctx =
            ShopifyInventoryVariantLookupService.findVariantByInventoryItemId('111');
        Test.stopTest();

        System.assertEquals(null, ctx, 'Variant with null id should return null safely.');
    }
}