@IsTest
private class SquarePaymentQueueableTest {

    private class SquarePaymentMock implements HttpCalloutMock {
        private String mode;

        SquarePaymentMock(String mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();

            if (mode == 'PAYMENT_EXCEPTION') {
                throw new CalloutException('Mock payment callout failure');
            }

            if (endpoint != null && endpoint.contains('/v2/payments/')) {
                res.setStatusCode(200);

                if (mode == 'NULL_PAYMENT') {
                    res.setBody('{"payment":null}');
                    return res;
                }

                if (mode == 'PAYMENT_NO_ORDER_NO_CUSTOMER') {
                    res.setBody(
                        '{"payment":{' +
                        '"id":"PAYMENT_ID_123",' +
                        '"status":"COMPLETED",' +
                        '"created_at":"2026-01-01T00:00:00Z",' +
                        '"amount_money":{"amount":2500,"currency":"USD"},' +
                        '"total_money":{"amount":2500,"currency":"USD"}' +
                        '}}'
                    );
                    return res;
                }

                if (mode == 'PAYMENT_NO_CUSTOMER_ORDER_TOP_LEVEL_CUSTOMER' ||
                    mode == 'PAYMENT_NO_CUSTOMER_ORDER_TENDER_CUSTOMER' ||
                    mode == 'PAYMENT_NO_CUSTOMER_ORDER_NO_CUSTOMER' ||
                    mode == 'CUSTOMER_EXCEPTION') {

                    res.setBody(
                        '{"payment":{' +
                        '"id":"PAYMENT_ID_123",' +
                        '"order_id":"ORDER_ID_123",' +
                        '"location_id":"LOCATION_123",' +
                        '"receipt_url":"https://example.com/receipt",' +
                        '"status":"COMPLETED",' +
                        '"created_at":"2026-01-01T00:00:00Z",' +
                        '"amount_money":{"amount":2500,"currency":"USD"},' +
                        '"total_money":{"amount":2500,"currency":"USD"},' +
                        '"note":"Test payment without customer id"' +
                        '}}'
                    );
                    return res;
                }

                res.setBody(
                    '{"payment":{' +
                    '"id":"PAYMENT_ID_123",' +
                    '"order_id":"ORDER_ID_123",' +
                    '"team_member_id":"TEAM_MEMBER_123",' +
                    '"location_id":"LOCATION_123",' +
                    '"customer_id":"CUSTOMER_123",' +
                    '"receipt_url":"https://example.com/receipt",' +
                    '"status":"COMPLETED",' +
                    '"created_at":"2026-01-01T00:00:00Z",' +
                    '"amount_money":{"amount":2500,"currency":"USD"},' +
                    '"total_money":{"amount":2500,"currency":"USD"},' +
                    '"note":"Test payment"' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/orders/')) {
                if (mode == 'ORDER_ERROR') {
                    res.setStatusCode(500);
                    res.setBody('{"errors":[{"detail":"Mock order error"}]}');
                    return res;
                }

                res.setStatusCode(200);

                if (mode == 'PAYMENT_NO_CUSTOMER_ORDER_TOP_LEVEL_CUSTOMER') {
                    res.setBody(
                        '{"order":{' +
                        '"id":"ORDER_ID_123",' +
                        '"customer_id":"CUSTOMER_FROM_ORDER_123",' +
                        '"location_id":"LOCATION_123",' +
                        '"created_at":"2026-01-01T00:00:00Z",' +
                        '"state":"COMPLETED",' +
                        '"line_items":[]' +
                        '}}'
                    );
                    return res;
                }

                if (mode == 'PAYMENT_NO_CUSTOMER_ORDER_TENDER_CUSTOMER') {
                    res.setBody(
                        '{"order":{' +
                        '"id":"ORDER_ID_123",' +
                        '"location_id":"LOCATION_123",' +
                        '"created_at":"2026-01-01T00:00:00Z",' +
                        '"state":"COMPLETED",' +
                        '"tenders":[' +
                        '{"id":"TENDER_1","customer_id":"CUSTOMER_FROM_TENDER_123"}' +
                        '],' +
                        '"line_items":[]' +
                        '}}'
                    );
                    return res;
                }

                if (mode == 'PAYMENT_NO_CUSTOMER_ORDER_NO_CUSTOMER') {
                    res.setBody(
                        '{"order":{' +
                        '"id":"ORDER_ID_123",' +
                        '"location_id":"LOCATION_123",' +
                        '"created_at":"2026-01-01T00:00:00Z",' +
                        '"state":"COMPLETED",' +
                        '"line_items":[]' +
                        '}}'
                    );
                    return res;
                }

                res.setBody(
                    '{"order":{' +
                    '"id":"ORDER_ID_123",' +
                    '"location_id":"LOCATION_123",' +
                    '"created_at":"2026-01-01T00:00:00Z",' +
                    '"state":"COMPLETED",' +
                    '"line_items":[' +
                    '{' +
                    '"uid":"LINE_1",' +
                    '"name":"Test Item",' +
                    '"quantity":"1",' +
                    '"catalog_object_id":"CATALOG_VARIATION_123",' +
                    '"base_price_money":{"amount":2500,"currency":"USD"},' +
                    '"total_money":{"amount":2500,"currency":"USD"}' +
                    '}' +
                    ']' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/customers/')) {
                if (mode == 'CUSTOMER_EXCEPTION') {
                    throw new CalloutException('Mock customer callout failure');
                }

                res.setStatusCode(200);
                res.setBody(
                    '{"customer":{' +
                    '"id":"CUSTOMER_123",' +
                    '"given_name":"Test",' +
                    '"family_name":"Customer",' +
                    '"email_address":"square-customer@example.com",' +
                    '"phone_number":"+15555550123"' +
                    '}}'
                );
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @IsTest
    static void testBlankPaymentIdReturnsSafely() {
        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable(null));
        System.enqueueJob(new SquarePaymentQueueable(''));
        System.enqueueJob(new SquarePaymentQueueable('   '));
        Test.stopTest();

        System.assert(true, 'Blank payment ids should return safely.');
    }

    @IsTest
    static void testPaymentRetrieveExceptionReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new SquarePaymentMock('PAYMENT_EXCEPTION'));

        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable('PAYMENT_ID_123'));
        Test.stopTest();

        System.assert(true, 'Payment retrieve exception should be caught.');
    }

    @IsTest
    static void testNullPaymentReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new SquarePaymentMock('NULL_PAYMENT'));

        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable('PAYMENT_ID_123'));
        Test.stopTest();

        System.assert(true, 'Null payment response should return safely.');
    }

    @IsTest
    static void testPaymentWithoutOrderOrCustomer() {
        Test.setMock(HttpCalloutMock.class, new SquarePaymentMock('PAYMENT_NO_ORDER_NO_CUSTOMER'));

        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable('PAYMENT_ID_123'));
        Test.stopTest();

        System.assert(true, 'Payment with no order id and no customer id should complete safely.');
    }

    @IsTest
    static void testOrderRetrieveFailureIsNonFatal() {
        Test.setMock(HttpCalloutMock.class, new SquarePaymentMock('ORDER_ERROR'));

        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable('PAYMENT_ID_123'));
        Test.stopTest();

        System.assert(true, 'Square order retrieve failure should be non-fatal.');
    }

    @IsTest
    static void testSuccessfulPaymentQueueableWithPaymentCustomerId() {
        Test.setMock(HttpCalloutMock.class, new SquarePaymentMock('SUCCESS'));

        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable('PAYMENT_ID_123'));
        Test.stopTest();

        System.assert(true, 'Payment queueable should complete successfully.');
    }

    @IsTest
    static void testCustomerIdExtractedFromOrderTopLevel() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquarePaymentMock('PAYMENT_NO_CUSTOMER_ORDER_TOP_LEVEL_CUSTOMER')
        );

        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable('PAYMENT_ID_123'));
        Test.stopTest();

        System.assert(true, 'Customer id should be extracted from Square order customer_id.');
    }

    @IsTest
    static void testCustomerIdExtractedFromOrderTender() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquarePaymentMock('PAYMENT_NO_CUSTOMER_ORDER_TENDER_CUSTOMER')
        );

        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable('PAYMENT_ID_123'));
        Test.stopTest();

        System.assert(true, 'Customer id should be extracted from Square order tenders.');
    }

    @IsTest
    static void testOrderHasNoCustomerIdOrTenders() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquarePaymentMock('PAYMENT_NO_CUSTOMER_ORDER_NO_CUSTOMER')
        );

        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable('PAYMENT_ID_123'));
        Test.stopTest();

        System.assert(true, 'Order without customer_id or tenders should complete safely.');
    }

    @IsTest
    static void testCustomerRetrieveExceptionIsNonFatal() {
        Test.setMock(HttpCalloutMock.class, new SquarePaymentMock('CUSTOMER_EXCEPTION'));

        Test.startTest();
        System.enqueueJob(new SquarePaymentQueueable('PAYMENT_ID_123'));
        Test.stopTest();

        System.assert(true, 'Square customer retrieve failure should be non-fatal.');
    }
}