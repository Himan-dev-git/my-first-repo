@IsTest
private class SquareInventoryDeductionQueueableTest {

    private class SquarePaymentMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();

            if (endpoint != null && endpoint.contains('/v2/payments/')) {
                res.setBody(
                    '{"payment":{' +
                    '"id":"PAYMENT_ID_123456789012345",' +
                    '"order_id":"ORDER_ID_123456789012345",' +
                    '"team_member_id":"TEAM_MEMBER_123",' +
                    '"location_id":"LOCATION_123",' +
                    '"receipt_url":"https://example.com/receipt",' +
                    '"amount_money":{"amount":2500,"currency":"USD"}' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/orders/')) {
                res.setBody(
                    '{"order":{' +
                    '"id":"ORDER_ID_123456789012345",' +
                    '"location_id":"LOCATION_123",' +
                    '"line_items":[]' +
                    '}}'
                );
                return res;
            }

            res.setBody('{}');
            return res;
        }
    }

    @IsTest
    static void testQueueableExecutesWithValidPaymentId() {
        Test.setMock(HttpCalloutMock.class, new SquarePaymentMock());

        Test.startTest();
        System.enqueueJob(
            new SquareInventoryDeductionQueueable('PAYMENT_ID_123456789012345')
        );
        Test.stopTest();

        System.assert(true, 'Queueable executed with valid payment id.');
    }
}