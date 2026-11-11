@IsTest
private class ShopifyOrderBackfillServiceTest {

    private static final String GRAPHQL_ENDPOINT = 'callout:Shopify_Admin_API/admin/api/2026-04/graphql.json';
    private static final String REST_ORDER_ENDPOINT = 'callout:Shopify_Admin_API/admin/api/2026-04/orders/';

    private class ShopifyOrderBackfillMock implements HttpCalloutMock {
        private String mode;

        ShopifyOrderBackfillMock(String mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = request == null ? null : request.getEndpoint();
            String requestMethod = request == null ? null : request.getMethod();

            if (requestMethod == 'POST' && endpoint != null && endpoint.contains('/graphql.json')) {
                return graphQlResponse(response);
            }

            if (requestMethod == 'GET' && endpoint != null && endpoint.contains('/orders/')) {
                return restOrderResponse(response, endpoint);
            }

            response.setStatusCode(404);
            response.setBody('{"error":"Unexpected test endpoint"}');
            return response;
        }

        private HttpResponse graphQlResponse(HttpResponse response) {
            if (mode == 'PAGE_HTTP_ERROR') {
                response.setStatusCode(500);
                response.setBody('{"error":"Simulated GraphQL failure"}');
                return response;
            }

            if (mode == 'PAGE_INVALID_ROOT') {
                response.setStatusCode(200);
                response.setBody('[{"data":"invalid-root"}]');
                return response;
            }

            if (mode == 'PAGE_GRAPHQL_ERRORS') {
                response.setStatusCode(200);
                response.setBody('{"errors":[{"message":"Simulated GraphQL error"}]}');
                return response;
            }

            if (mode == 'PAGE_ERRORS_NOT_LIST') {
                response.setStatusCode(200);
                response.setBody('{"errors":"not-a-list","data":{"orders":{"edges":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}');
                return response;
            }

            if (mode == 'PAGE_MISSING_DATA') {
                response.setStatusCode(200);
                response.setBody('{"extensions":{"cost":1}}');
                return response;
            }

            if (mode == 'PAGE_DATA_NULL') {
                response.setStatusCode(200);
                response.setBody('{"data":null}');
                return response;
            }

            if (mode == 'PAGE_ORDERS_NULL') {
                response.setStatusCode(200);
                response.setBody('{"data":{"orders":null}}');
                return response;
            }

            if (mode == 'PAGE_EDGES_NOT_LIST') {
                response.setStatusCode(200);
                response.setBody('{"data":{"orders":{"edges":"not-a-list","pageInfo":{"hasNextPage":false,"endCursor":null}}}}');
                return response;
            }

            if (mode == 'PAGE_INVALID_EDGES') {
                response.setStatusCode(200);
                response.setBody('{"data":{"orders":{"edges":[null,"invalid-edge",{"cursor":"C1","node":null},{"cursor":"C2","node":{}},{"cursor":"C3","node":{"legacyResourceId":null}},{"cursor":"C4","node":{"legacyResourceId":"900001"}}],"pageInfo":{"hasNextPage":false,"endCursor":"END-INVALID-EDGES"}}}}');
                return response;
            }

            if (mode == 'PAGE_WITH_ORDER') {
                response.setStatusCode(200);
                response.setBody(graphQlPageBody(new List<String>{ '900001' }, false, 'CURSOR-900001'));
                return response;
            }

            if (mode == 'PAGE_WITH_MULTIPLE_ORDERS') {
                response.setStatusCode(200);
                response.setBody(graphQlPageBody(new List<String>{ '900001', '900002' }, false, 'CURSOR-900002'));
                return response;
            }

            if (mode == 'PAGE_WITH_NEXT') {
                response.setStatusCode(200);
                response.setBody(graphQlPageBody(new List<String>(), true, 'NEXT-CURSOR'));
                return response;
            }

            if (mode == 'PAGE_NEXT_WITH_BLANK_CURSOR') {
                response.setStatusCode(200);
                response.setBody(graphQlPageBody(new List<String>(), true, null));
                return response;
            }

            if (mode == 'PAGE_NO_PAGE_INFO') {
                response.setStatusCode(200);
                response.setBody('{"data":{"orders":{"edges":[]}}}');
                return response;
            }

            response.setStatusCode(200);
            response.setBody(graphQlPageBody(new List<String>(), false, null));
            return response;
        }

        private HttpResponse restOrderResponse(HttpResponse response, String endpoint) {
            if (mode == 'REST_HTTP_ERROR') {
                response.setStatusCode(500);
                response.setBody('{"error":"Simulated REST failure"}');
                return response;
            }

            if (mode == 'PAGE_WITH_ORDER_REST_FAILURE' || mode == 'PAGE_WITH_MULTIPLE_ORDERS_REST_FAILURE') {
                response.setStatusCode(500);
                response.setBody('{"error":"Simulated order retrieval failure"}');
                return response;
            }

            if (mode == 'REST_INVALID_ROOT') {
                response.setStatusCode(200);
                response.setBody('[{"order":"invalid-root"}]');
                return response;
            }

            if (mode == 'REST_MISSING_ORDER') {
                response.setStatusCode(200);
                response.setBody('{"orders":[]}');
                return response;
            }

            if (mode == 'REST_ORDER_NULL') {
                response.setStatusCode(200);
                response.setBody('{"order":null}');
                return response;
            }

            String shopifyOrderId = extractOrderId(endpoint);
            response.setStatusCode(200);
            response.setBody(
                '{"order":{' +
                '"id":"' + String.escapeSingleQuotes(shopifyOrderId) + '",' +
                '"name":"#1001",' +
                '"currency":"USD",' +
                '"created_at":"2026-01-15T10:30:45Z",' +
                '"financial_status":"paid",' +
                '"fulfillment_status":null,' +
                '"line_items":[],' +
                '"fulfillments":[]' +
                '}}'
            );
            return response;
        }

        private String graphQlPageBody(List<String> orderIds, Boolean hasNextPage, String endCursor) {
            List<Object> edges = new List<Object>();
            Integer counter = 0;

            for (String orderId : orderIds) {
                counter++;
                edges.add(new Map<String, Object>{
                    'cursor' => 'CURSOR-' + String.valueOf(counter),
                    'node' => new Map<String, Object>{ 'legacyResourceId' => orderId }
                });
            }

            return JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'orders' => new Map<String, Object>{
                        'edges' => edges,
                        'pageInfo' => new Map<String, Object>{
                            'hasNextPage' => hasNextPage,
                            'endCursor' => endCursor
                        }
                    }
                }
            });
        }

        private String extractOrderId(String endpoint) {
            Integer ordersPosition = endpoint.indexOf('/orders/');
            if (ordersPosition < 0) {
                return 'UNKNOWN';
            }

            String remainingEndpoint = endpoint.substring(ordersPosition + '/orders/'.length());
            Integer jsonPosition = remainingEndpoint.indexOf('.json');
            if (jsonPosition >= 0) {
                remainingEndpoint = remainingEndpoint.substring(0, jsonPosition);
            }

            return EncodingUtil.urlDecode(remainingEndpoint, 'UTF-8');
        }
    }

    private class PageWithRestFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (request.getMethod() == 'POST' && request.getEndpoint().contains('/graphql.json')) {
                response.setStatusCode(200);
                response.setBody(JSON.serialize(new Map<String, Object>{
                    'data' => new Map<String, Object>{
                        'orders' => new Map<String, Object>{
                            'edges' => new List<Object>{
                                new Map<String, Object>{
                                    'cursor' => 'CURSOR-1',
                                    'node' => new Map<String, Object>{ 'legacyResourceId' => '900001' }
                                }
                            },
                            'pageInfo' => new Map<String, Object>{
                                'hasNextPage' => false,
                                'endCursor' => 'CURSOR-1'
                            }
                        }
                    }
                }));
                return response;
            }

            response.setStatusCode(500);
            response.setBody('{"error":"Simulated REST order failure"}');
            return response;
        }
    }

    private static void configureMock(String mode) {
        Test.setMock(HttpCalloutMock.class, new ShopifyOrderBackfillMock(mode));
    }

    @IsTest
    static void testBackfillAllOrdersEnqueuesFirstPage() {
        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        Id jobId = ShopifyOrderBackfillService.backfillAllOrders();
        Integer jobsAfter = Limits.getQueueableJobs();

        System.assertNotEquals(null, jobId);
        System.assertEquals(jobsBefore + 1, jobsAfter, 'The first order-page Queueable should be enqueued.');
    }

    @IsTest
    static void testBackfillOrdersFromNullUsesAllOrders() {
        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        Id jobId = ShopifyOrderBackfillService.backfillOrdersFrom(null);
        Integer jobsAfter = Limits.getQueueableJobs();

        System.assertNotEquals(null, jobId);
        System.assertEquals(jobsBefore + 1, jobsAfter);
    }

    @IsTest
    static void testBackfillOrdersFromDateEnqueuesJob() {
        Datetime createdAtMin = Datetime.newInstanceGMT(2026, 1, 15, 10, 30, 45);

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        Id jobId = ShopifyOrderBackfillService.backfillOrdersFrom(createdAtMin);
        Integer jobsAfter = Limits.getQueueableJobs();

        System.assertNotEquals(null, jobId);
        System.assertEquals(jobsBefore + 1, jobsAfter);
    }

    @IsTest
    static void testBackfillOrdersBetweenEnqueuesJob() {
        Datetime createdAtMin = Datetime.newInstanceGMT(2026, 1, 1, 0, 0, 0);
        Datetime createdAtMax = createdAtMin.addDays(10);

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        Id jobId = ShopifyOrderBackfillService.backfillOrdersBetween(createdAtMin, createdAtMax);
        Integer jobsAfter = Limits.getQueueableJobs();

        System.assertNotEquals(null, jobId);
        System.assertEquals(jobsBefore + 1, jobsAfter);
    }

    @IsTest
    static void testBackfillOrdersBetweenRequiresMinimum() {
        Boolean exceptionThrown = false;

        try {
            ShopifyOrderBackfillService.backfillOrdersBetween(null, Datetime.now());
        } catch (ShopifyOrderBackfillService.ShopifyOrderBackfillException e) {
            exceptionThrown = true;
            System.assertEquals('Both createdAtMin and createdAtMax are required.', e.getMessage());
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testBackfillOrdersBetweenRequiresMaximum() {
        Boolean exceptionThrown = false;

        try {
            ShopifyOrderBackfillService.backfillOrdersBetween(Datetime.now(), null);
        } catch (ShopifyOrderBackfillService.ShopifyOrderBackfillException e) {
            exceptionThrown = true;
            System.assertEquals('Both createdAtMin and createdAtMax are required.', e.getMessage());
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testBackfillOrdersBetweenRejectsEqualDates() {
        Datetime value = Datetime.newInstanceGMT(2026, 2, 1, 0, 0, 0);
        Boolean exceptionThrown = false;

        try {
            ShopifyOrderBackfillService.backfillOrdersBetween(value, value);
        } catch (ShopifyOrderBackfillService.ShopifyOrderBackfillException e) {
            exceptionThrown = true;
            System.assertEquals('createdAtMax must be later than createdAtMin.', e.getMessage());
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testBackfillOrdersBetweenRejectsEarlierMaximum() {
        Datetime createdAtMin = Datetime.newInstanceGMT(2026, 2, 10, 0, 0, 0);
        Boolean exceptionThrown = false;

        try {
            ShopifyOrderBackfillService.backfillOrdersBetween(createdAtMin, createdAtMin.addDays(-1));
        } catch (ShopifyOrderBackfillService.ShopifyOrderBackfillException e) {
            exceptionThrown = true;
            System.assertEquals('createdAtMax must be later than createdAtMin.', e.getMessage());
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testQueueableCompletesEmptyPage() {
        configureMock('PAGE_EMPTY');
        ShopifyOrderBackfillService.OrderPageQueueable job = new ShopifyOrderBackfillService.OrderPageQueueable(null, null);

        Test.startTest();
        job.execute(null);
        System.assertEquals(1, Limits.getCallouts(), 'The GraphQL page request should make one callout.');
        System.assertEquals(0, Limits.getQueueableJobs(), 'No next-page job should be created.');
        Test.stopTest();
    }

    @IsTest
    static void testQueueableHandlesGraphQlHttpFailure() {
        configureMock('PAGE_HTTP_ERROR');
        ShopifyOrderBackfillService.OrderPageQueueable job = new ShopifyOrderBackfillService.OrderPageQueueable(null, 'created_at:>=test');

        Test.startTest();
        job.execute(null);
        System.assertEquals(1, Limits.getCallouts());
        System.assertEquals(0, Limits.getQueueableJobs(), 'A failed page request should not enqueue another page.');
        Test.stopTest();
    }

    @IsTest
    static void testQueueableHandlesInvalidGraphQlRoot() {
        configureMock('PAGE_INVALID_ROOT');

        Test.startTest();
        new ShopifyOrderBackfillService.OrderPageQueueable(null, null).execute(null);
        System.assertEquals(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void testQueueableHandlesGraphQlErrors() {
        configureMock('PAGE_GRAPHQL_ERRORS');

        Test.startTest();
        new ShopifyOrderBackfillService.OrderPageQueueable(null, null).execute(null);
        System.assertEquals(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void testQueueableHandlesMissingOrdersObject() {
        List<String> modes = new List<String>{ 'PAGE_MISSING_DATA', 'PAGE_DATA_NULL', 'PAGE_ORDERS_NULL' };

        for (String mode : modes) {
            configureMock(mode);
            new ShopifyOrderBackfillService.OrderPageQueueable(null, null).execute(null);
        }

        System.assert(true);
    }

    @IsTest
    static void testQueueableHandlesInvalidEdges() {
        configureMock('PAGE_INVALID_EDGES');

        Test.startTest();
        new ShopifyOrderBackfillService.OrderPageQueueable('INPUT-CURSOR', 'created_at:>=test').execute(null);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testQueueableHandlesNonListProperties() {
        configureMock('PAGE_ERRORS_NOT_LIST');
        new ShopifyOrderBackfillService.OrderPageQueueable(null, null).execute(null);

        configureMock('PAGE_EDGES_NOT_LIST');
        new ShopifyOrderBackfillService.OrderPageQueueable(null, null).execute(null);

        System.assert(true);
    }

    @IsTest
    static void testQueueableHandlesMissingPageInfo() {
        configureMock('PAGE_NO_PAGE_INFO');

        Test.startTest();
        new ShopifyOrderBackfillService.OrderPageQueueable(null, null).execute(null);
        System.assertEquals(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void testQueueableProcessesOrderPayload() {
        configureMock('PAGE_WITH_ORDER');

        Test.startTest();
        new ShopifyOrderBackfillService.OrderPageQueueable(null, null).execute(null);
        System.assertEquals(2, Limits.getCallouts(), 'The Queueable should retrieve one GraphQL page and one REST order.');
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testQueueableContinuesAfterRestOrderFailure() {
        Test.setMock(HttpCalloutMock.class, new PageWithRestFailureMock());

        Test.startTest();
        new ShopifyOrderBackfillService.OrderPageQueueable(null, null).execute(null);
        System.assertEquals(2, Limits.getCallouts());
        System.assertEquals(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void testQueueableDoesNotEnqueueBlankNextCursor() {
        configureMock('PAGE_NEXT_WITH_BLANK_CURSOR');

        Test.startTest();
        new ShopifyOrderBackfillService.OrderPageQueueable(null, null).execute(null);
        System.assertEquals(0, Limits.getQueueableJobs(), 'A blank end cursor must not enqueue another Queueable.');
        Test.stopTest();
    }

    @IsTest
    static void testFetchRestOrderSuccess() {
        configureMock('REST_SUCCESS');

        Test.startTest();
        Map<String, Object> orderPayload = ShopifyOrderBackfillService.fetchRestOrder('900001');
        Test.stopTest();

        System.assertNotEquals(null, orderPayload);
        System.assertEquals('900001', String.valueOf(orderPayload.get('id')));
        System.assertEquals('USD', String.valueOf(orderPayload.get('currency')));
    }

    @IsTest
    static void testFetchRestOrderRequiresId() {
        List<String> invalidIds = new List<String>{ null, '', '   ' };

        for (String invalidId : invalidIds) {
            Boolean exceptionThrown = false;

            try {
                ShopifyOrderBackfillService.fetchRestOrder(invalidId);
            } catch (ShopifyOrderBackfillService.ShopifyOrderBackfillException e) {
                exceptionThrown = true;
                System.assertEquals('Shopify order ID is required.', e.getMessage());
            }

            System.assertEquals(true, exceptionThrown);
        }
    }

    @IsTest
    static void testFetchRestOrderEncodesOrderId() {
        configureMock('REST_SUCCESS');
        Map<String, Object> orderPayload = ShopifyOrderBackfillService.fetchRestOrder('gid test/order');
        System.assertEquals('gid test/order', String.valueOf(orderPayload.get('id')));
    }

    @IsTest
    static void testFetchRestOrderThrowsForHttpFailure() {
        configureMock('REST_HTTP_ERROR');
        Boolean exceptionThrown = false;

        try {
            ShopifyOrderBackfillService.fetchRestOrder('900001');
        } catch (ShopifyOrderBackfillService.ShopifyOrderBackfillException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('REST order request for 900001 failed'));
            System.assert(e.getMessage().contains('Status=500'));
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testFetchRestOrderThrowsForInvalidResponses() {
        List<String> modes = new List<String>{ 'REST_INVALID_ROOT', 'REST_MISSING_ORDER', 'REST_ORDER_NULL' };

        for (String mode : modes) {
            configureMock(mode);
            Boolean exceptionThrown = false;

            try {
                ShopifyOrderBackfillService.fetchRestOrder('900001');
            } catch (ShopifyOrderBackfillService.ShopifyOrderBackfillException e) {
                exceptionThrown = true;
                System.assert(e.getMessage().contains('Shopify REST response did not contain order'));
            }

            System.assertEquals(true, exceptionThrown, 'Expected an exception for mode ' + mode);
        }
    }

    @IsTest
    static void testCustomException() {
        ShopifyOrderBackfillService.ShopifyOrderBackfillException exceptionValue = new ShopifyOrderBackfillService.ShopifyOrderBackfillException('Test message');
        System.assertEquals('Test message', exceptionValue.getMessage());
    }
}