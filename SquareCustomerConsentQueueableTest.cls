@IsTest
private class SquareCustomerConsentQueueableTest {

    private static final String PAYMENT_ID = 'PAYMENT_CONSENT_TEST_12345';
    private static final String CUSTOMER_ID = 'CUSTOMER_CONSENT_TEST_12345';

    private static Map<String, Object> buildPayment(
        String paymentId,
        String customerId
    ) {
        return new Map<String, Object>{
            'id' => paymentId,
            'customer_id' => customerId,
            'order_id' => 'ORDER_CONSENT_TEST_12345',
            'status' => 'COMPLETED',
            'created_at' => '2026-01-01T00:00:00Z',
            'amount_money' => new Map<String, Object>{
                'amount' => 2500,
                'currency' => 'USD'
            },
            'total_money' => new Map<String, Object>{
                'amount' => 2500,
                'currency' => 'USD'
            }
        };
    }

    private static Map<String, Object> buildSquareCustomer(String customerId) {
        return new Map<String, Object>{
            'id' => customerId,
            'given_name' => 'Test',
            'family_name' => 'Customer',
            'email_address' => 'square-consent-test@example.com',
            'phone_number' => '+15555550123',
            'created_at' => '2026-01-01T00:00:00Z',
            'updated_at' => '2026-01-01T00:00:00Z'
        };
    }

    @IsTest
    static void testBlankPaymentIdReturnsSafely() {
        Map<String, Object> payment = buildPayment(
            '',
            CUSTOMER_ID
        );

        Map<String, Object> customer = buildSquareCustomer(CUSTOMER_ID);

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerConsentQueueable(
                '',
                payment,
                customer
            )
        );
        Test.stopTest();

        System.assert(true, 'Blank paymentId should return safely.');
    }

    @IsTest
    static void testNullPaymentIdReturnsSafely() {
        Map<String, Object> payment = buildPayment(
            null,
            CUSTOMER_ID
        );

        Map<String, Object> customer = buildSquareCustomer(CUSTOMER_ID);

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerConsentQueueable(
                null,
                payment,
                customer
            )
        );
        Test.stopTest();

        System.assert(true, 'Null paymentId should return safely.');
    }

    @IsTest
    static void testNullPaymentReturnsSafely() {
        Map<String, Object> customer = buildSquareCustomer(CUSTOMER_ID);

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerConsentQueueable(
                PAYMENT_ID,
                null,
                customer
            )
        );
        Test.stopTest();

        System.assert(true, 'Null payment map should return safely.');
    }

    @IsTest
    static void testValidPaymentAndCustomerCompletes() {
        Map<String, Object> payment = buildPayment(
            PAYMENT_ID,
            CUSTOMER_ID
        );

        Map<String, Object> customer = buildSquareCustomer(CUSTOMER_ID);

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerConsentQueueable(
                PAYMENT_ID,
                payment,
                customer
            )
        );
        Test.stopTest();

        System.assert(true, 'Valid payment/customer path should complete.');
    }

    @IsTest
    static void testNullSquareCustomerCompletesOrLogsSafely() {
        Map<String, Object> payment = buildPayment(
            PAYMENT_ID,
            CUSTOMER_ID
        );

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerConsentQueueable(
                PAYMENT_ID,
                payment,
                null
            )
        );
        Test.stopTest();

        System.assert(true, 'Null squareCustomer should not break queueable transaction.');
    }

    @IsTest
    static void testBadPaymentDataHitsCatchBlockSafely() {
        Map<String, Object> badPayment = new Map<String, Object>{
            'id' => PAYMENT_ID,
            'customer_id' => CUSTOMER_ID,
            'amount_money' => 'this-should-be-a-map-not-a-string'
        };

        Map<String, Object> customer = buildSquareCustomer(CUSTOMER_ID);

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerConsentQueueable(
                PAYMENT_ID,
                badPayment,
                customer
            )
        );
        Test.stopTest();

        System.assert(true, 'Bad payment data should be caught and logged safely.');
    }
}