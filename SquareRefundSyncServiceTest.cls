@IsTest
private class SquareRefundSyncServiceTest {

    // =====================================================================
    // Endpoint-aware Square mock
    // =====================================================================

    private class RefundMock implements HttpCalloutMock {
        private Map<String, Object> refundBody;
        private Map<String, Object> paymentBody;
        private Boolean returnNullRefund = false;
        private Boolean throwOnPayment = false;

        RefundMock(
            Map<String, Object> refundBody,
            Map<String, Object> paymentBody
        ) {
            this.refundBody = refundBody;
            this.paymentBody = paymentBody;
        }

        RefundMock withNullRefund() {
            this.returnNullRefund = true;
            return this;
        }

        RefundMock withPaymentThrows() {
            this.throwOnPayment = true;
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint() == null
                ? ''
                : req.getEndpoint().toLowerCase();

            if (endpoint.contains('refund')) {
                res.setStatusCode(200);

                if (returnNullRefund || refundBody == null) {
                    res.setBody('{}');
                } else {
                    res.setBody(JSON.serialize(
                        new Map<String, Object>{
                            'refund' => refundBody
                        }
                    ));
                }

                return res;
            }

            if (endpoint.contains('payment')) {
                if (throwOnPayment) {
                    res.setStatusCode(500);
                    res.setBody('{"errors":[{"detail":"Payment lookup failed"}]}');
                    return res;
                }

                res.setStatusCode(200);

                if (paymentBody == null) {
                    res.setBody('{}');
                } else {
                    res.setBody(JSON.serialize(
                        new Map<String, Object>{
                            'payment' => paymentBody
                        }
                    ));
                }

                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    // =====================================================================
    // Test data helpers
    // =====================================================================

    private static Account createAccount() {
        Account acc = new Account(
            Name = 'Square Refund Test Account'
        );
        insert acc;
        return acc;
    }

    private static Order createOrder(
        Account acc,
        String squarePaymentId,
        String squareOrderId
    ) {
        Order ord = new Order(
            AccountId             = acc.Id,
            Status                = 'Draft',
            EffectiveDate         = Date.today(),
            Type                  = 'POS',
            Square_Payment_Id__c  = squarePaymentId,
            Square_Order_Id__c    = squareOrderId,
            Financial_Status__c   = 'Paid',
            Fulfillment_Status__c = 'Fulfilled'
        );
        insert ord;
        return ord;
    }

    private static Map<String, Object> refundMap(
        String status,
        String paymentId,
        String orderId,
        Integer amountCents,
        String reason,
        String createdAt,
        String updatedAt
    ) {
        Map<String, Object> refund = new Map<String, Object>{
            'id'         => 'REF_TEST',
            'status'     => status,
            'payment_id' => paymentId,
            'order_id'   => orderId
        };

        if (amountCents != null) {
            refund.put(
                'amount_money',
                new Map<String, Object>{
                    'amount'   => amountCents,
                    'currency' => 'USD'
                }
            );
        }

        if (reason != null) {
            refund.put('reason', reason);
        }

        if (createdAt != null) {
            refund.put('created_at', createdAt);
        }

        if (updatedAt != null) {
            refund.put('updated_at', updatedAt);
        }

        return refund;
    }

    private static Map<String, Object> refundMapWithEmptyAmountMoney(
        String status,
        String paymentId,
        String orderId
    ) {
        Map<String, Object> refund = refundMap(
            status,
            paymentId,
            orderId,
            null,
            'Amount object without amount',
            '2026-07-01T10:00:00Z',
            null
        );

        refund.put(
            'amount_money',
            new Map<String, Object>{
                'currency' => 'USD'
            }
        );

        return refund;
    }

    private static Map<String, Object> paymentMap(
        String paymentId,
        String orderId
    ) {
        Map<String, Object> payment = new Map<String, Object>{
            'id' => paymentId
        };

        if (orderId != null) {
            payment.put('order_id', orderId);
        }

        return payment;
    }

    // =====================================================================
    // Guard / early return tests
    // =====================================================================

    @IsTest
    static void testSyncRefund_BlankRefundId_ReturnsTrue() {
        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            '',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);
    }

    @IsTest
    static void testSyncRefund_NullRefund_ReturnsTrue() {
        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(null, null).withNullRefund()
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_NULL',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);
    }

    // =====================================================================
    // Completed refund tests
    // =====================================================================

    @IsTest
    static void testSyncRefund_Completed_OrderFoundByPaymentId_UpdatesAllRefundFields() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            'PAY_BY_PAYMENT',
            'ORD_BY_PAYMENT'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_BY_PAYMENT',
                    'ORD_REFUND_OBJECT',
                    2500,
                    'Customer returned item',
                    '2026-07-01T10:15:30Z',
                    null
                ),
                null
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_COMPLETED_PAYMENT',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Square_Payment_Id__c,
                   Financial_Status__c,
                   Fulfillment_Status__c,
                   Refund_Date__c,
                   Refund_Reason__c,
                   Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals('PAY_BY_PAYMENT', updated.Square_Payment_Id__c);
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
        System.assertEquals('Customer returned item', updated.Refund_Reason__c);
        System.assertEquals(25.00, updated.Refund_Amount__c);
        System.assertEquals(
            Datetime.valueOfGmt('2026-07-01 10:15:30'),
            updated.Refund_Date__c
        );
    }

    @IsTest
    static void testSyncRefund_Completed_BlankPaymentId_OrderFoundByRefundOrderId() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            null,
            'ORD_BY_REFUND_ORDER_ID'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    '',
                    'ORD_BY_REFUND_ORDER_ID',
                    1750,
                    'Refund by refund order id',
                    '2026-07-01T11:00:00Z',
                    null
                ),
                null
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_BY_REFUND_ORDER_ID',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Square_Payment_Id__c,
                   Financial_Status__c,
                   Fulfillment_Status__c,
                   Refund_Reason__c,
                   Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals(null, updated.Square_Payment_Id__c);
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
        System.assertEquals('Refund by refund order id', updated.Refund_Reason__c);
        System.assertEquals(17.50, updated.Refund_Amount__c);
    }

    @IsTest
    static void testSyncRefund_Completed_FallbackPaymentOrderId_FindsOrder() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            null,
            'ORD_FROM_PAYMENT'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_FALLBACK',
                    'ORD_REFUND_DIFFERENT',
                    3300,
                    'Fallback through payment order id',
                    '2026-07-01T12:00:00Z',
                    null
                ),
                paymentMap(
                    'PAY_FALLBACK',
                    'ORD_FROM_PAYMENT'
                )
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_PAYMENT_FALLBACK',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Square_Payment_Id__c,
                   Financial_Status__c,
                   Fulfillment_Status__c,
                   Refund_Amount__c,
                   Refund_Reason__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals('PAY_FALLBACK', updated.Square_Payment_Id__c);
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
        System.assertEquals(33.00, updated.Refund_Amount__c);
        System.assertEquals('Fallback through payment order id', updated.Refund_Reason__c);
    }

    @IsTest
    static void testSyncRefund_Completed_PaymentLookupThrows_FallsBackToRefundOrderId() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            null,
            'ORD_AFTER_PAYMENT_ERROR'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_LOOKUP_ERROR',
                    'ORD_AFTER_PAYMENT_ERROR',
                    4400,
                    'Payment lookup failed fallback',
                    '2026-07-01T13:00:00Z',
                    null
                ),
                null
            ).withPaymentThrows()
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_PAYMENT_LOOKUP_ERROR',
            'refund.updated',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Square_Payment_Id__c,
                   Financial_Status__c,
                   Fulfillment_Status__c,
                   Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals('PAY_LOOKUP_ERROR', updated.Square_Payment_Id__c);
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
        System.assertEquals(44.00, updated.Refund_Amount__c);
    }

    // =====================================================================
    // Pending / non-completed refund tests
    // =====================================================================

    @IsTest
    static void testSyncRefund_Pending_OrderFound_UpdatesRefundFieldsButKeepsStatus() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            'PAY_PENDING',
            'ORD_PENDING'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'PENDING',
                    'PAY_PENDING',
                    'ORD_PENDING',
                    1250,
                    'Pending refund reason',
                    '2026-07-01T14:00:00Z',
                    null
                ),
                null
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_PENDING',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Financial_Status__c,
                   Fulfillment_Status__c,
                   Refund_Date__c,
                   Refund_Reason__c,
                   Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals('Paid', updated.Financial_Status__c);
        System.assertEquals('Fulfilled', updated.Fulfillment_Status__c);
        System.assertEquals('Pending refund reason', updated.Refund_Reason__c);
        System.assertEquals(12.50, updated.Refund_Amount__c);
        System.assertEquals(
            Datetime.valueOfGmt('2026-07-01 14:00:00'),
            updated.Refund_Date__c
        );
    }

    @IsTest
    static void testSyncRefund_Pending_NoOrderFound_ReturnsFalse() {
        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'PENDING',
                    'PAY_PENDING_NO_ORDER',
                    'ORD_PENDING_NO_ORDER',
                    1250,
                    'No order pending refund',
                    '2026-07-01T14:30:00Z',
                    null
                ),
                paymentMap(
                    'PAY_PENDING_NO_ORDER',
                    'ORD_ORIGINAL_NO_MATCH'
                )
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_PENDING_NO_ORDER',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(false, result);
    }

    // =====================================================================
    // Date parsing and optional fields
    // =====================================================================

    @IsTest
    static void testSyncRefund_UsesUpdatedAtWhenCreatedAtMissing() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            'PAY_UPDATED_AT',
            'ORD_UPDATED_AT'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_UPDATED_AT',
                    'ORD_UPDATED_AT',
                    990,
                    'Uses updated at',
                    null,
                    '2026-07-01T15:45:10Z'
                ),
                null
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_UPDATED_AT',
            'refund.updated',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Refund_Date__c,
                   Refund_Reason__c,
                   Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals(
            Datetime.valueOfGmt('2026-07-01 15:45:10'),
            updated.Refund_Date__c
        );
        System.assertEquals('Uses updated at', updated.Refund_Reason__c);
        System.assertEquals(9.90, updated.Refund_Amount__c);
    }

    @IsTest
    static void testSyncRefund_DateWithMillisecondsParsesCorrectly() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            'PAY_MILLISECONDS',
            'ORD_MILLISECONDS'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_MILLISECONDS',
                    'ORD_MILLISECONDS',
                    777,
                    'Milliseconds date',
                    '2026-07-01T16:05:30.123Z',
                    null
                ),
                null
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_MILLISECONDS',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Refund_Date__c,
                   Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals(
            Datetime.valueOfGmt('2026-07-01 16:05:30'),
            updated.Refund_Date__c
        );
        System.assertEquals(7.77, updated.Refund_Amount__c);
    }

    @IsTest
    static void testSyncRefund_InvalidDateFallsBackToNowAndStillUpdates() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            'PAY_BAD_DATE',
            'ORD_BAD_DATE'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_BAD_DATE',
                    'ORD_BAD_DATE',
                    500,
                    'Bad date refund',
                    'not-a-valid-date',
                    null
                ),
                null
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_BAD_DATE',
            'refund.updated',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Refund_Date__c,
                   Refund_Reason__c,
                   Refund_Amount__c,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertNotEquals(null, updated.Refund_Date__c);
        System.assertEquals('Bad date refund', updated.Refund_Reason__c);
        System.assertEquals(5.00, updated.Refund_Amount__c);
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
    }

    @IsTest
    static void testSyncRefund_NoDateUsesSystemNowAndNoAmountNoReasonStillUpdates() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            'PAY_NO_OPTIONAL_FIELDS',
            'ORD_NO_OPTIONAL_FIELDS'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_NO_OPTIONAL_FIELDS',
                    'ORD_NO_OPTIONAL_FIELDS',
                    null,
                    null,
                    null,
                    null
                ),
                null
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_NO_OPTIONAL_FIELDS',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Refund_Date__c,
                   Refund_Reason__c,
                   Refund_Amount__c,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertNotEquals(null, updated.Refund_Date__c);
        System.assertEquals(null, updated.Refund_Reason__c);
        System.assertEquals(null, updated.Refund_Amount__c);
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
    }

    @IsTest
    static void testSyncRefund_AmountMoneyExistsButAmountMissing_DoesNotOverwriteAmount() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            'PAY_EMPTY_AMOUNT',
            'ORD_EMPTY_AMOUNT'
        );

        ord.Refund_Amount__c = 99.99;
        update ord;

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMapWithEmptyAmountMoney(
                    'COMPLETED',
                    'PAY_EMPTY_AMOUNT',
                    'ORD_EMPTY_AMOUNT'
                ),
                null
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_EMPTY_AMOUNT',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(true, result);

        Order updated = [
            SELECT Refund_Amount__c,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals(99.99, updated.Refund_Amount__c);
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
    }

    // =====================================================================
    // No order / fallback failure tests
    // =====================================================================

    @IsTest
    static void testSyncRefund_PaymentResponseHasNoOrderId_AndRefundOrderIdNoMatch_ReturnsFalse() {
        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_NO_ORDER_ID',
                    'ORD_NO_MATCH',
                    2000,
                    'No matching order',
                    '2026-07-01T17:00:00Z',
                    null
                ),
                paymentMap(
                    'PAY_NO_ORDER_ID',
                    null
                )
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_NO_ORDER_ID',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(false, result);
    }

    @IsTest
    static void testSyncRefund_NoOrderFoundAnywhere_ReturnsFalse() {
        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_GHOST',
                    'ORD_GHOST',
                    2000,
                    'Ghost refund',
                    '2026-07-01T18:00:00Z',
                    null
                ),
                paymentMap(
                    'PAY_GHOST',
                    'ORD_GHOST_ORIGINAL'
                )
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_GHOST',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(false, result);
    }

    @IsTest
    static void testSyncRefund_DeletedOrderNotFound_ReturnsFalse() {
        Account acc = createAccount();

        Order ord = createOrder(
            acc,
            'PAY_DELETED',
            'ORD_DELETED'
        );

        delete ord;

        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    'PAY_DELETED',
                    'ORD_DELETED',
                    1500,
                    'Deleted order',
                    '2026-07-01T19:00:00Z',
                    null
                ),
                paymentMap(
                    'PAY_DELETED',
                    'ORD_DELETED'
                )
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_DELETED',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(false, result);
    }

    @IsTest
    static void testSyncRefund_BlankPaymentAndBlankRefundOrderId_ReturnsFalse() {
        Test.setMock(
            HttpCalloutMock.class,
            new RefundMock(
                refundMap(
                    'COMPLETED',
                    '',
                    '',
                    1000,
                    'Blank ids',
                    '2026-07-01T20:00:00Z',
                    null
                ),
                null
            )
        );

        Test.startTest();

        Boolean result = SquareRefundSyncService.syncRefund(
            'REF_BLANK_IDS',
            'refund.created',
            '{}'
        );

        Test.stopTest();

        System.assertEquals(false, result);
    }
}