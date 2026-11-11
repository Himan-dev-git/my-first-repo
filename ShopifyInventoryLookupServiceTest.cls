@IsTest
private class ShopifyInventoryLookupServiceTest {

    private class InventoryFoundMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(
                '{"data":{"productVariant":{"id":"gid://shopify/ProductVariant/111",' +
                '"inventoryItem":{"id":"gid://shopify/InventoryItem/999",' +
                '"inventoryLevels":{"nodes":[' +
                '{"location":{"id":"gid://shopify/Location/123"},"quantities":[{"name":"available","quantity":15}]},' +
                '{"location":{"id":"gid://shopify/Location/456"},"quantities":[{"name":"available","quantity":5}]}' +
                ']}}}}}'
            );

            return res;
        }
    }

    private class InventoryLocationNotFoundMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(
                '{"data":{"productVariant":{"id":"gid://shopify/ProductVariant/111",' +
                '"inventoryItem":{"id":"gid://shopify/InventoryItem/999",' +
                '"inventoryLevels":{"nodes":[' +
                '{"location":{"id":"gid://shopify/Location/999"},"quantities":[{"name":"available","quantity":20}]}' +
                ']}}}}}'
            );

            return res;
        }
    }

    private class NoInventoryItemMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"data":{"productVariant":{"id":"gid://shopify/ProductVariant/111","inventoryItem":null}}}');
            return res;
        }
    }

    private class NullNodesMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(
                '{"data":{"productVariant":{"inventoryItem":{"id":"gid://shopify/InventoryItem/999",' +
                '"inventoryLevels":null}}}}'
            );

            return res;
        }
    }

    private class BadQuantityMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(
                '{"data":{"productVariant":{"inventoryItem":{"id":"gid://shopify/InventoryItem/999",' +
                '"inventoryLevels":{"nodes":[' +
                '{"location":{"id":"gid://shopify/Location/123"},"quantities":[{"name":"available","quantity":"abc"}]}' +
                ']}}}}}'
            );

            return res;
        }
    }

    @IsTest
    static void testResolveVariantLocationContext_Found() {
        Test.setMock(HttpCalloutMock.class, new InventoryFoundMock());

        Test.startTest();
        ShopifyInventoryLookupService.VariantInventoryContext ctx =
            ShopifyInventoryLookupService.resolveVariantLocationContext('111', '123');
        Test.stopTest();

        System.assertNotEquals(null, ctx, 'Context should not be null');
        System.assertEquals('999', ctx.inventoryItemId, 'Inventory item numeric id should be extracted');
        System.assertEquals(true, ctx.hasLevelAtLocation, 'Location level should be found');
        System.assertEquals(15, ctx.currentAvailable, 'Available quantity should be mapped');
    }

    @IsTest
    static void testResolveVariantLocationContext_LocationNotFound() {
        Test.setMock(HttpCalloutMock.class, new InventoryLocationNotFoundMock());

        Test.startTest();
        ShopifyInventoryLookupService.VariantInventoryContext ctx =
            ShopifyInventoryLookupService.resolveVariantLocationContext('111', '123');
        Test.stopTest();

        System.assertEquals('999', ctx.inventoryItemId);
        System.assertEquals(false, ctx.hasLevelAtLocation);
        System.assertEquals(null, ctx.currentAvailable);
    }

    @IsTest
    static void testResolveVariantLocationContext_NoInventoryItem() {
        Test.setMock(HttpCalloutMock.class, new NoInventoryItemMock());

        Test.startTest();
        ShopifyInventoryLookupService.VariantInventoryContext ctx =
            ShopifyInventoryLookupService.resolveVariantLocationContext('111', '123');
        Test.stopTest();

        System.assertEquals(null, ctx.inventoryItemId);
        System.assertEquals(false, ctx.hasLevelAtLocation);
        System.assertEquals(null, ctx.currentAvailable);
    }

    @IsTest
    static void testResolveVariantLocationContext_NullInventoryLevels() {
        Test.setMock(HttpCalloutMock.class, new NullNodesMock());

        Test.startTest();
        ShopifyInventoryLookupService.VariantInventoryContext ctx =
            ShopifyInventoryLookupService.resolveVariantLocationContext('111', '123');
        Test.stopTest();

        System.assertEquals('999', ctx.inventoryItemId);
        System.assertEquals(false, ctx.hasLevelAtLocation);
        System.assertEquals(null, ctx.currentAvailable);
    }

    @IsTest
    static void testResolveVariantLocationContext_BadQuantity() {
        Test.setMock(HttpCalloutMock.class, new BadQuantityMock());

        Test.startTest();
        ShopifyInventoryLookupService.VariantInventoryContext ctx =
            ShopifyInventoryLookupService.resolveVariantLocationContext('111', '123');
        Test.stopTest();

        System.assertEquals('999', ctx.inventoryItemId);
        System.assertEquals(true, ctx.hasLevelAtLocation);
        System.assertEquals(null, ctx.currentAvailable, 'Bad quantity should safely return null');
    }
}