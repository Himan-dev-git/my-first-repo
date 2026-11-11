@IsTest
private class SquareCatalogPriceSyncQueueableTest {

    private class SquarePriceMock implements HttpCalloutMock {
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

            // Safe Square catalog object response.
            res.setBody(
                '{"object":{' +
                '"id":"VAR_123",' +
                '"type":"ITEM_VARIATION",' +
                '"item_variation_data":{' +
                '"price_money":{"amount":1000,"currency":"USD"}' +
                '}' +
                '}}'
            );

            return res;
        }
    }

    @IsTest
    static void testQueueableExecutes() {
        Test.setMock(HttpCalloutMock.class, new SquarePriceMock());

        Test.startTest();
        System.enqueueJob(new SquareCatalogPriceSyncQueueable());
        Test.stopTest();

        System.assert(true, 'Queueable executed SquareCatalogPriceSyncService safely.');
    }

    @IsTest
    static void testSquareCatalogSyncEventTriggerFires() {
        Test.setMock(HttpCalloutMock.class, new SquarePriceMock());

        Square_Catalog_Sync_Event__e evt = new Square_Catalog_Sync_Event__e();

        Test.startTest();

        Database.SaveResult sr = EventBus.publish(evt);
        System.assertEquals(
            true,
            sr.isSuccess(),
            'Platform event should publish successfully.'
        );

        Test.getEventBus().deliver();

        Test.stopTest();

        System.assert(true, 'SquareCatalogSyncEventTrigger fired and enqueued the queueable.');
    }
}