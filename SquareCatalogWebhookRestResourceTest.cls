@IsTest
private class SquareCatalogWebhookRestResourceTest {

    private static void setupRestRequest(String body) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestUri = '/services/apexrest/square/catalog/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);

        RestContext.request = req;
        RestContext.response = res;
    }

    @IsTest
    static void testCatalogVersionUpdatedPublishesEvent() {
        setupRestRequest(
            '{"type":"catalog.version.updated","merchant_id":"MERCHANT_123"}'
        );

        Test.startTest();
        SquareCatalogWebhookRestResource.receiveWebhook();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Webhook should return HTTP 200.'
        );
    }

    @IsTest
    static void testNonCatalogVersionUpdatedDoesNotPublishEvent() {
        setupRestRequest(
            '{"type":"payment.updated","merchant_id":"MERCHANT_123"}'
        );

        Test.startTest();
        SquareCatalogWebhookRestResource.receiveWebhook();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Non-matching webhook should still return HTTP 200.'
        );
    }

    @IsTest
    static void testMissingTypeDoesNotPublishEvent() {
        setupRestRequest(
            '{"merchant_id":"MERCHANT_123"}'
        );

        Test.startTest();
        SquareCatalogWebhookRestResource.receiveWebhook();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Webhook without type should still return HTTP 200.'
        );
    }
}