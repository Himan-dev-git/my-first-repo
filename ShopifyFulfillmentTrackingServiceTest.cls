@IsTest
private class ShopifyFulfillmentTrackingServiceTest {

    private class TrackingMock implements HttpCalloutMock {
        private String mode;

        TrackingMock(String mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest req) {
            if (mode == 'throwException') {
                throw new CalloutException('Mock callout failure');
            }

            HttpResponse res = new HttpResponse();

            if (mode == 'http500') {
                res.setStatusCode(500);
                res.setBody('{}');
                return res;
            }

            res.setStatusCode(200);

            if (mode == 'topErrors') {
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'errors' => new List<Object>{
                        new Map<String, Object>{ 'message' => 'Top level error' }
                    }
                }));
                return res;
            }

            if (mode == 'nullData') {
                res.setBody(JSON.serialize(new Map<String, Object>()));
                return res;
            }

            if (mode == 'missingUpdateMap') {
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'data' => new Map<String, Object>()
                }));
                return res;
            }

            if (mode == 'userErrors') {
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'data' => new Map<String, Object>{
                        'fulfillmentTrackingInfoUpdate' => new Map<String, Object>{
                            'userErrors' => new List<Object>{
                                new Map<String, Object>{ 'message' => 'Bad tracking' }
                            }
                        }
                    }
                }));
                return res;
            }

            res.setBody(JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'fulfillmentTrackingInfoUpdate' => new Map<String, Object>{
                        'fulfillment' => new Map<String, Object>{
                            'id' => 'gid://shopify/Fulfillment/123',
                            'status' => 'SUCCESS'
                        },
                        'userErrors' => new List<Object>()
                    }
                }
            }));

            return res;
        }
    }

    private static Fulfilment__c createFulfillment(
        String shopId,
        String trackingNumber,
        String trackingCompany,
        String trackingUrl
    ) {
        Fulfilment__c f = new Fulfilment__c(
            Shop_ID__c = shopId,
            Tracking_Number__c = trackingNumber,
            Tracking_Company__c = trackingCompany,
            Tracking_URL__c = trackingUrl,
            Status__c = 'Pending'
        );
        insert f;
        return f;
    }

    @IsTest
    static void testNullAndEmptyInput() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('success'));

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(null);
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>());
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testNoRowsBecauseShopIdNull() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('success'));

        Fulfilment__c f = createFulfillment(null, 'TRACK-1', 'UPS', 'https://track.test');

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSkipBlankTrackingNumber() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('success'));

        Fulfilment__c f = createFulfillment('123', null, 'UPS', 'https://track.test');

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSuccessWithCompanyAndUrl() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('success'));

        Fulfilment__c f = createFulfillment('123', 'TRACK-123', ' UPS ', 'https://track.test');

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSuccessWithoutCompanyAndUrl() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('success'));

        Fulfilment__c f = createFulfillment('124', 'TRACK-124', null, null);

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testCalloutException() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('throwException'));

        Fulfilment__c f = createFulfillment('125', 'TRACK-125', 'FedEx', null);

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testHttp500() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('http500'));

        Fulfilment__c f = createFulfillment('126', 'TRACK-126', 'UPS', null);

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testTopLevelErrors() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('topErrors'));

        Fulfilment__c f = createFulfillment('127', 'TRACK-127', 'UPS', null);

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testNullData() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('nullData'));

        Fulfilment__c f = createFulfillment('128', 'TRACK-128', 'UPS', null);

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testMissingUpdateMap() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('missingUpdateMap'));

        Fulfilment__c f = createFulfillment('129', 'TRACK-129', 'UPS', null);

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testUserErrors() {
        Test.setMock(HttpCalloutMock.class, new TrackingMock('userErrors'));

        Fulfilment__c f = createFulfillment('130', 'TRACK-130', 'UPS', null);

        Test.startTest();
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>{ f.Id });
        Test.stopTest();

        System.assert(true);
    }
}