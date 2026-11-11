@IsTest
private class SquareWebhookRestResourceTest {
    
    private static void setupRestRequest(String body) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestUri = '/services/apexrest/square/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        
        RestContext.request = req;
        RestContext.response = res;
    }
    
    @IsTest
    static void testIgnoredEventType() {
        setupRestRequest('{"type":"customer.created"}');
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testPaymentCreatedWithNullData() {
        setupRestRequest('{"type":"payment.created"}');
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testPaymentUpdatedWithNullObject() {
        setupRestRequest(
            '{"type":"payment.updated","data":{}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testPaymentCreatedWithoutPaymentObject() {
        setupRestRequest(
            '{"type":"payment.created","data":{"object":{"order":{}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testPaymentCreatedWithBlankPaymentId() {
        setupRestRequest(
            '{"type":"payment.created","data":{"object":{"payment":{"id":""}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testPaymentCreatedWithValidPaymentId() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        setupRestRequest(
            '{"type":"payment.created","data":{"object":{"payment":{"id":"PAYMENT_ID_123456789012345"}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testPaymentUpdatedWithValidPaymentId() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        setupRestRequest(
            '{"type":"payment.updated","data":{"object":{"payment":{"id":"PAYMENT_ID_123456789012345"}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testBlankBodyReturns200() {
        setupRestRequest('');
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testInvalidJsonReturns200() {
        setupRestRequest('{bad json');
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testUnhandledEventTypeReturns200() {
        setupRestRequest('{"type":"inventory.count.updated"}');
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testPaymentCreatedWithObjectIdFallback() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        setupRestRequest(
            '{"type":"payment.created","data":{"object":{"id":"PAYMENT_OBJECT_ID_123"}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    @IsTest
    static void testOrderCreatedWithDataId() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        setupRestRequest(
            '{"type":"order.created","data":{"id":"ORDER_DATA_ID_123"}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testOrderUpdatedWithOrderObjectId() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        setupRestRequest(
            '{"type":"order.updated","data":{"object":{"order":{"id":"ORDER_OBJECT_ID_123"}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testOrderCreatedWithObjectIdFallback() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        setupRestRequest(
            '{"type":"order.created","data":{"object":{"id":"ORDER_FALLBACK_ID_123"}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testOrderCreatedWithoutOrderId() {
        setupRestRequest(
            '{"type":"order.created","data":{"object":{"order":{}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testRefundCreatedWithDataId() {
        setupRestRequest(
            '{"type":"refund.created","event_id":"EVENT_123","data":{"id":"REFUND_DATA_ID_123"}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testRefundUpdatedWithRefundObjectId() {
        setupRestRequest(
            '{"type":"refund.updated","event_id":"EVENT_456","data":{"object":{"refund":{"id":"REFUND_OBJECT_ID_123"}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testRefundCreatedWithObjectIdFallback() {
        setupRestRequest(
            '{"type":"refund.created","data":{"object":{"id":"REFUND_FALLBACK_ID_123"}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testRefundCreatedWithoutRefundId() {
        setupRestRequest(
            '{"type":"refund.created","data":{"object":{"refund":{}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testCustomerCreatedWithCustomerObjectId() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        setupRestRequest(
            '{"type":"customer.created","data":{"object":{"customer":{"id":"CUSTOMER_OBJECT_ID_123"}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testCustomerUpdatedWithObjectIdFallback() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        setupRestRequest(
            '{"type":"customer.updated","data":{"object":{"id":"CUSTOMER_FALLBACK_ID_123"}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testCustomerUpdatedWithoutCustomerId() {
        setupRestRequest(
            '{"type":"customer.updated","data":{"object":{"customer":{}}}}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testCatalogVersionUpdated() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        setupRestRequest(
            '{"type":"catalog.version.updated"}'
        );
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    private static void setupRestRequestWithNullBody() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestUri = '/services/apexrest/square/';
        req.httpMethod = 'POST';
        req.requestBody = null;
        
        RestContext.request = req;
        RestContext.response = res;
    }
    
    @IsTest
    static void testNullRequestBodyReturns200() {
        setupRestRequestWithNullBody();
        
        Test.startTest();
        SquareWebhookRestResource.receiveWebhook();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    
    
}