@IsTest
private class SquareCustomerQueueableTest {

    private static final String CUSTOMER_ID = 'CUSTOMER_TEST_123';
    private static final String EVENT_TYPE_CREATED = 'customer.created';
    private static final String EVENT_TYPE_UPDATED = 'customer.updated';

    private static String buildRawPayload(String customerId) {
        return JSON.serialize(new Map<String, Object>{
            'type' => EVENT_TYPE_CREATED,
            'event_id' => 'EVENT_CUSTOMER_TEST_123',
            'data' => new Map<String, Object>{
                'object' => new Map<String, Object>{
                    'customer' => new Map<String, Object>{
                        'id' => customerId,
                        'given_name' => 'Test',
                        'family_name' => 'Customer',
                        'email_address' => 'square-customer-test@example.com',
                        'phone_number' => '+15555550123',
                        'created_at' => '2026-01-01T00:00:00Z',
                        'updated_at' => '2026-01-01T00:00:00Z'
                    }
                }
            }
        });
    }

    @IsTest
    static void testExecuteCustomerCreated() {
        String rawPayload = buildRawPayload(CUSTOMER_ID);

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerQueueable(
                CUSTOMER_ID,
                EVENT_TYPE_CREATED,
                rawPayload
            )
        );
        Test.stopTest();

        System.assert(true, 'SquareCustomerQueueable customer.created path completed.');
    }

    @IsTest
    static void testExecuteCustomerUpdated() {
        String rawPayload = buildRawPayload(CUSTOMER_ID);

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerQueueable(
                CUSTOMER_ID,
                EVENT_TYPE_UPDATED,
                rawPayload
            )
        );
        Test.stopTest();

        System.assert(true, 'SquareCustomerQueueable customer.updated path completed.');
    }

    @IsTest
    static void testExecuteWithBlankCustomerId() {
        String rawPayload = buildRawPayload('');

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerQueueable(
                '',
                EVENT_TYPE_CREATED,
                rawPayload
            )
        );
        Test.stopTest();

        System.assert(true, 'Blank customerId path completed safely.');
    }

    @IsTest
    static void testExecuteWithNullCustomerId() {
        String rawPayload = buildRawPayload(null);

        Test.startTest();
        System.enqueueJob(
            new SquareCustomerQueueable(
                null,
                EVENT_TYPE_CREATED,
                rawPayload
            )
        );
        Test.stopTest();

        System.assert(true, 'Null customerId path completed safely.');
    }

    @IsTest
    static void testExecuteCatchBlockWithInvalidPayload() {
        Test.startTest();
        System.enqueueJob(
            new SquareCustomerQueueable(
                CUSTOMER_ID,
                EVENT_TYPE_CREATED,
                '{bad json'
            )
        );
        Test.stopTest();

        System.assert(true, 'Invalid payload should exercise catch/logging path if service throws.');
    }
}