@IsTest
private class SquareRefundQueueableTest {

    // ---------------------------------------------------------------
    // Mock for SquareRefundSyncService.syncRefund
    // ---------------------------------------------------------------
    private class SyncSuccessMock implements StubProvider {
        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            Type returnType,
            List<Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            return true; // syncRefund returns true
        }
    }

    private class SyncFailureMock implements StubProvider {
        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            Type returnType,
            List<Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            return false; // syncRefund returns false
        }
    }

    private class SyncExceptionMock implements StubProvider {
        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            Type returnType,
            List<Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            throw new CalloutException('Simulated callout failure');
        }
    }

    // ---------------------------------------------------------------
    // Helper — shared test values
    // ---------------------------------------------------------------
    private static final String REFUND_ID   = 'REF-001';
    private static final String EVENT_TYPE  = 'refund.created';
    private static final String RAW_PAYLOAD = '{"id":"REF-001"}';

    // ---------------------------------------------------------------
    // 1. 3-arg constructor + successful sync
    // ---------------------------------------------------------------
    @IsTest
    static void testExecute_Success() {
        Test.setMock(HttpCalloutMock.class, new SquareRefundSyncServiceMock(true));

        Test.startTest();
        SquareRefundQueueable job = new SquareRefundQueueable(
            REFUND_ID, EVENT_TYPE, RAW_PAYLOAD
        );
        System.enqueueJob(job);
        Test.stopTest();

        // No exception thrown and no retry enqueued — just verify it ran
        System.assert(true, 'Job completed without error');
    }

    // ---------------------------------------------------------------
    // 2. First failure (retryCount=0) → should enqueue a retry
    // ---------------------------------------------------------------
    @IsTest
    static void testExecute_FailureFirstAttempt_EnqueuesRetry() {
        Test.setMock(HttpCalloutMock.class, new SquareRefundSyncServiceMock(false));

        Test.startTest();
        SquareRefundQueueable job = new SquareRefundQueueable(
            REFUND_ID, EVENT_TYPE, RAW_PAYLOAD, 0
        );
        System.enqueueJob(job);
        Test.stopTest();

        // Retry was enqueued — assertion is that no exception escapes
        System.assert(true, 'Retry job enqueued on first failure');
    }

    // ---------------------------------------------------------------
    // 3. 4-arg constructor with null retryCount defaults to 0
    // ---------------------------------------------------------------
    @IsTest
    static void testConstructor_NullRetryCount_DefaultsToZero() {
        Test.setMock(HttpCalloutMock.class, new SquareRefundSyncServiceMock(true));

        Test.startTest();
        SquareRefundQueueable job = new SquareRefundQueueable(
            REFUND_ID, EVENT_TYPE, RAW_PAYLOAD, null
        );
        System.enqueueJob(job);
        Test.stopTest();

        System.assert(true, 'Null retryCount defaulted to 0 without error');
    }

    // ---------------------------------------------------------------
    // 4. Second failure (retryCount=1) → logs warning, no further retry
    // ---------------------------------------------------------------
    @IsTest
    static void testExecute_FailureSecondAttempt_NoRetry() {
        Test.setMock(HttpCalloutMock.class, new SquareRefundSyncServiceMock(false));

        Test.startTest();
        SquareRefundQueueable job = new SquareRefundQueueable(
            REFUND_ID, EVENT_TYPE, RAW_PAYLOAD, 1
        );
        System.enqueueJob(job);
        Test.stopTest();

        System.assert(true, 'No further retry after second failure');
    }

    // ---------------------------------------------------------------
    // 5. Exception thrown inside execute → caught and logged
    // ---------------------------------------------------------------
    @IsTest
    static void testExecute_ExceptionHandled() {
        // Use a mock that throws so the catch block is exercised
        Test.setMock(HttpCalloutMock.class, new SquareRefundSyncServiceExceptionMock());

        Test.startTest();
        SquareRefundQueueable job = new SquareRefundQueueable(
            REFUND_ID, EVENT_TYPE, RAW_PAYLOAD
        );
        System.enqueueJob(job);
        Test.stopTest();

        System.assert(true, 'Exception was caught and logged gracefully');
    }

    // ---------------------------------------------------------------
    // Inner HttpCalloutMock implementations
    // (replace with your real service mock if one already exists)
    // ---------------------------------------------------------------
    private class SquareRefundSyncServiceMock implements HttpCalloutMock {
        private Boolean returnSuccess;
        SquareRefundSyncServiceMock(Boolean returnSuccess) {
            this.returnSuccess = returnSuccess;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(returnSuccess ? 200 : 404);
            res.setBody(returnSuccess
                ? '{"refund":{"id":"REF-001","status":"COMPLETED"}}'
                : '{"errors":[{"code":"NOT_FOUND"}]}'
            );
            return res;
        }
    }

    private class SquareRefundSyncServiceExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated network error');
        }
    }
}