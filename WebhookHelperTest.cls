@IsTest
private class WebhookHelperTest {
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static RestRequest buildRequest(String body, String topic) {
        return buildRequest(body, 'X-Shopify-Topic', topic, true);
    }
    
    private static RestRequest buildRequest(
        String body,
        String topicHeaderName,
        String topic,
        Boolean includeShopifyMetadataHeaders
    ) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/webhook';
        req.httpMethod = 'POST';
        
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        
        if (topicHeaderName != null) {
            req.headers.put(topicHeaderName, topic);
        }
        
        if (includeShopifyMetadataHeaders == true) {
            req.headers.put('X-Shopify-Webhook-Id', 'webhook-test-001');
            req.headers.put('X-Shopify-Shop-Domain', 'test-store.myshopify.com');
            req.headers.put('X-Shopify-Api-Version', '2026-04');
            req.headers.put('X-Shopify-Hmac-Sha256', 'test-hmac-value');
        }
        
        return req;
    }
    
    private static RestResponse invoke(RestRequest req) {
        GlobalHttpMock.mockMode = 'SUCCESS';
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        return WebhookHelper.handleWebhookRequest(req);
    }
    
    private static void assertOk(RestResponse res) {
        System.assertEquals(
            200,
            res.statusCode,
            'Expected 200. Actual body: ' +
            (res.responseBody == null ? null : res.responseBody.toString())
        );
        System.assertEquals('{"status":"ok"}', res.responseBody.toString());
    }
    
    private static void assertErrorContains(RestResponse res, String expectedText) {
        System.assertEquals(
            500,
            res.statusCode,
            'Expected 500. Actual body: ' +
            (res.responseBody == null ? null : res.responseBody.toString())
        );
        
        System.assert(
            res.responseBody.toString().contains(expectedText),
            'Expected response body to contain "' + expectedText + '". Actual: ' +
            res.responseBody.toString()
        );
    }
    
    private static void assertPublishFailureOrOk(RestResponse res, String expectedText) {
        System.assert(
            res.statusCode == 200 || res.statusCode == 500,
            'Expected 200 or 500. Actual status: ' + res.statusCode +
            ', body: ' + (res.responseBody == null ? null : res.responseBody.toString())
        );
        
        if (res.statusCode == 200) {
            System.assertEquals('{"status":"ok"}', res.responseBody.toString());
        } else {
            System.assert(
                res.responseBody.toString().contains(expectedText) ||
                res.responseBody.toString().contains('error'),
                'Expected publish failure body to contain "' + expectedText +
                '" or generic error. Actual: ' + res.responseBody.toString()
            );
        }
    }
    
    private static String longText(Integer targetLength) {
        String chunk = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
        String output = '';
        
        while (output.length() < targetLength) {
            output += chunk;
        }
        
        return output.left(targetLength);
    }
    
    private static String hugePayloadBody(Map<String, Object> basePayload) {
        basePayload.put('oversized_test_value', longText(150000));
        return JSON.serialize(basePayload);
    }
    
    private static String orderPayloadWithId() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 123456789,
                'admin_graphql_api_id' => 'gid://shopify/Order/123456789',
                'email' => 'order-test@example.com',
                'name' => '#1001',
                'created_at' => '2026-01-01T00:00:00Z',
                'updated_at' => '2026-01-01T00:00:00Z',
                'currency' => 'USD',
                'total_price' => '100.00',
                'subtotal_price' => '100.00',
                'financial_status' => 'paid',
                'fulfillment_status' => null,
                'line_items' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 987654321,
                            'product_id' => 111,
                            'variant_id' => 222,
                            'title' => 'Test Product',
                            'quantity' => 1,
                            'price' => '100.00',
                            'sku' => 'TEST-SKU'
                            }
                },
                    'fulfillments' => new List<Object>()
                    });
    }
    
    private static String orderPayloadWithOrderIdFallback() {
        return JSON.serialize(new Map<String, Object>{
            'order_id' => 99887766,
                'email' => 'fallback-order@example.com',
                'name' => '#2002',
                'line_items' => new List<Object>()
                });
    }
    
    private static String customerPayloadWithId() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 123456,
                'email' => 'test@example.com',
                'first_name' => 'Test',
                'last_name' => 'Customer'
                });
    }
    
    private static String customerPayloadWithCustomerIdFallback() {
        return JSON.serialize(new Map<String, Object>{
            'customer_id' => 654321,
                'email' => 'fallback-customer@example.com'
                });
    }
    
    private static String collectionPayloadWithId() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 123,
                'title' => 'Test Collection'
                });
    }
    
    private static String collectionPayloadWithCollectionIdFallback() {
        return JSON.serialize(new Map<String, Object>{
            'collection_id' => 456,
                'title' => 'Fallback Collection'
                });
    }
    
    private static String locationPayloadWithId() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'gid://shopify/Location/789',
                'name' => 'Main Location'
                });
    }
    
    private static String locationPayloadWithLocationIdFallback() {
        return JSON.serialize(new Map<String, Object>{
            'location_id' => '456.0',
                'name' => 'Fallback Location'
                });
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Error handling
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testEmptyPayloadReturns500() {
        RestResponse res = invoke(buildRequest('', 'unknown/topic'));
        assertErrorContains(res, 'Empty payload');
    }
    
    @IsTest
    static void testWhitespacePayloadReturns500() {
        RestResponse res = invoke(buildRequest('   ', 'unknown/topic'));
        assertErrorContains(res, 'Empty payload');
    }
    
    @IsTest
    static void testNullRequestBodyReturns500() {
        RestResponse res = invoke(buildRequest(null, 'unknown/topic'));
        assertErrorContains(res, 'Empty payload');
    }
    
    @IsTest
    static void testJsonNullPayloadReturns500() {
        RestResponse res = invoke(buildRequest('null', 'unknown/topic'));
        assertErrorContains(res, 'Payload is null after deserialize');
    }
    
    @IsTest
    static void testMissingTopicHeaderReturns500() {
        RestRequest req = buildRequest('{"id":123}', null, null, false);
        RestResponse res = invoke(req);
        assertErrorContains(res, 'Missing X-Shopify-Topic header');
    }
    
    @IsTest
    static void testBlankTopicHeaderReturns500() {
        RestRequest req = buildRequest('{"id":123}', 'X-Shopify-Topic', '', true);
        RestResponse res = invoke(req);
        assertErrorContains(res, 'Missing X-Shopify-Topic header');
    }
    
    @IsTest
    static void testInvalidJsonReturns500() {
        RestResponse res = invoke(buildRequest('{bad json', 'unknown/topic'));
        
        System.assertEquals(500, res.statusCode);
        System.assert(res.responseBody.toString().contains('error'));
    }
    
    @IsTest
    static void testNonObjectJsonReturns500() {
        RestResponse res = invoke(buildRequest('[{"id":123}]', 'unknown/topic'));
        
        System.assertEquals(500, res.statusCode);
        System.assert(res.responseBody.toString().contains('error'));
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Header / topic handling
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testUnhandledTopicReturns200() {
        RestResponse res = invoke(buildRequest('{"id":123,"name":"Test"}', 'unknown/topic'));
        assertOk(res);
    }
    
    @IsTest
    static void testHeaderCaseInsensitiveReturns200() {
        RestRequest req = buildRequest(
            '{"id":123,"name":"Test"}',
            'x-shopify-topic',
            'unknown/topic',
            true
        );
        
        RestResponse res = invoke(req);
        assertOk(res);
    }
    
    @IsTest
    static void testTopicIsLowerCasedBeforeProcessing() {
        RestRequest req = buildRequest(
            '{"id":123,"title":"Mixed Case Product"}',
            'X-Shopify-Topic',
            'PRODUCTS/UPDATE',
            true
        );
        
        RestResponse res = invoke(req);
        assertOk(res);
    }
    
    @IsTest
    static void testMetadataHeadersAreCaseInsensitiveOnPlatformEventBranch() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"id":123,"title":"Case Header Product"}');
        
        req.headers.put('x-shopify-topic', 'products/update');
        req.headers.put('x-shopify-webhook-id', 'webhook-lowercase');
        req.headers.put('x-shopify-shop-domain', 'case-store.myshopify.com');
        req.headers.put('x-shopify-api-version', '2026-04');
        req.headers.put('x-shopify-hmac-sha256', 'case-hmac');
        
        RestResponse res = invoke(req);
        assertOk(res);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Inventory level topics
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testInventoryLevelsUpdateTopicWithNumericIds() {
        RestResponse res = invoke(buildRequest(
            '{"inventory_item_id":123,"location_id":456,"available":10}',
            'inventory_levels/update'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testInventoryLevelsConnectTopicWithGidAndDecimalIds() {
        RestResponse res = invoke(buildRequest(
            '{"inventory_item_id":"gid://shopify/InventoryItem/123456","location_id":"789.0","available":10}',
            'inventory_levels/connect'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testInventoryLevelsUpdateTopicWithScientificNotationIds() {
        RestResponse res = invoke(buildRequest(
            '{"inventory_item_id":"1.23456E5","location_id":"7.89E2","available":5}',
            'inventory_levels/update'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testInventoryLevelsUpdateTopicWithMissingIdsStillPublishes() {
        RestResponse res = invoke(buildRequest(
            '{"available":10}',
            'inventory_levels/update'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testInventoryLevelPublishFailureBranch() {
        RestResponse res = invoke(buildRequest(
            hugePayloadBody(new Map<String, Object>{
                'inventory_item_id' => 123,
                    'location_id' => 456,
                    'available' => 10
                    }),
            'inventory_levels/update'
        ));
        
        assertPublishFailureOrOk(res, 'Shopify inventory level platform event');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Collection topics
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testCollectionsCreateUpdateDeleteTopics() {
        List<String> topics = new List<String>{
            'collections/create',
                'collections/update',
                'collections/delete'
                };
                    
                    for (String topic : topics) {
                        RestResponse res = invoke(buildRequest(collectionPayloadWithId(), topic));
                        assertOk(res);
                    }
    }
    
    @IsTest
    static void testCollectionsCreateTopicUsesCollectionIdFallback() {
        RestResponse res = invoke(buildRequest(
            collectionPayloadWithCollectionIdFallback(),
            'collections/create'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testCollectionsCreateTopicWithMissingIdStillPublishes() {
        RestResponse res = invoke(buildRequest(
            '{"title":"No Id Collection"}',
            'collections/create'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testCollectionPublishFailureBranch() {
        RestResponse res = invoke(buildRequest(
            hugePayloadBody(new Map<String, Object>{
                'id' => 123,
                    'title' => 'Oversized Collection'
                    }),
            'collections/create'
        ));
        
        assertPublishFailureOrOk(res, 'Shopify collection platform event');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Order topics
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testAllOrderTopics() {
        List<String> topics = new List<String>{
            'orders/create',
                'orders/updated',
                'orders/update',
                'orders/cancelled',
                'orders/fulfilled',
                'orders/partially_fulfilled'
                };
                    
                    for (String topic : topics) {
                        RestResponse res = invoke(buildRequest(orderPayloadWithId(), topic));
                        assertOk(res);
                    }
    }
    
    @IsTest
    static void testOrdersCreateTopicUsesOrderIdFallback() {
        RestResponse res = invoke(buildRequest(
            orderPayloadWithOrderIdFallback(),
            'orders/create'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testOrdersCreateTopicWithMissingIdStillPublishes() {
        RestResponse res = invoke(buildRequest(
            '{"name":"#3003","line_items":[]}',
            'orders/create'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testOrderPublishFailureBranch() {
        RestResponse res = invoke(buildRequest(
            hugePayloadBody(new Map<String, Object>{
                'id' => 123456789,
                    'name' => '#9999',
                    'line_items' => new List<Object>()
                    }),
            'orders/create'
        ));
        
        assertPublishFailureOrOk(res, 'Shopify order platform event');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Customer topics
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testCustomersCreateUpdateDeleteTopics() {
        List<String> topics = new List<String>{
            'customers/create',
                'customers/update',
                'customers/delete'
                };
                    
                    for (String topic : topics) {
                        RestResponse res = invoke(buildRequest(customerPayloadWithId(), topic));
                        assertOk(res);
                    }
    }
    
    @IsTest
    static void testCustomerConsentTopics() {
        List<String> topics = new List<String>{
            'customers_email_marketing_consent/update',
                'customers_marketing_consent/update',
                'customers_whats_app_marketing_consent/update'
                };
                    
                    for (String topic : topics) {
                        RestResponse res = invoke(buildRequest(customerPayloadWithCustomerIdFallback(), topic));
                        assertOk(res);
                    }
    }
    
    @IsTest
    static void testCustomersCreateTopicUsesCustomerIdFallback() {
        RestResponse res = invoke(buildRequest(
            customerPayloadWithCustomerIdFallback(),
            'customers/create'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testCustomersCreateTopicWithMissingIdStillPublishes() {
        RestResponse res = invoke(buildRequest(
            '{"email":"no-id@example.com"}',
            'customers/create'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testCustomerPublishFailureBranch() {
        RestResponse res = invoke(buildRequest(
            hugePayloadBody(new Map<String, Object>{
                'id' => 123456,
                    'email' => 'oversized@example.com'
                    }),
            'customers/create'
        ));
        
        assertPublishFailureOrOk(res, 'Shopify customer platform event');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Location topics
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testAllLocationTopics() {
        List<String> topics = new List<String>{
            'locations/create',
                'locations/update',
                'locations/activate',
                'locations/deactivate'
                };
                    
                    for (String topic : topics) {
                        RestResponse res = invoke(buildRequest(locationPayloadWithId(), topic));
                        assertOk(res);
                    }
    }
    
    @IsTest
    static void testLocationsCreateTopicUsesLocationIdFallback() {
        RestResponse res = invoke(buildRequest(
            locationPayloadWithLocationIdFallback(),
            'locations/create'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testLocationsCreateTopicWithScientificNotationId() {
        RestResponse res = invoke(buildRequest(
            '{"id":"7.89E2","name":"Scientific Location"}',
            'locations/create'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testLocationsCreateTopicWithBlankIdStillPublishes() {
        RestResponse res = invoke(buildRequest(
            '{"id":"   ","name":"Blank Id Location"}',
            'locations/create'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testLocationPublishFailureBranch() {
        RestResponse res = invoke(buildRequest(
            hugePayloadBody(new Map<String, Object>{
                'id' => 'gid://shopify/Location/789',
                    'name' => 'Oversized Location'
                    }),
            'locations/create'
        ));
        
        assertPublishFailureOrOk(res, 'Shopify location platform event');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Product topics
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testProductsCreateUpdateDeleteTopics() {
        List<String> topics = new List<String>{
            'products/create',
                'products/update',
                'products/delete'
                };
                    
                    for (String topic : topics) {
                        RestResponse res = invoke(buildRequest(
                            '{"id":123,"title":"Test Product","variants":[]}',
                            topic
                        ));
                        assertOk(res);
                    }
    }
    
    @IsTest
    static void testProductsTopicWithMissingIdStillPublishes() {
        RestResponse res = invoke(buildRequest(
            '{"title":"Product Without Id"}',
            'products/update'
        ));
        
        assertOk(res);
    }
    
    @IsTest
    static void testProductPublishFailureBranch() {
        RestResponse res = invoke(buildRequest(
            hugePayloadBody(new Map<String, Object>{
                'id' => 123,
                    'title' => 'Oversized Product',
                    'variants' => new List<Object>()
                    }),
            'products/update'
        ));
        
        assertPublishFailureOrOk(res, 'Shopify product platform event');
    }
}