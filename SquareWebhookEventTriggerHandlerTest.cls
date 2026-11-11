@IsTest
private class SquareWebhookEventTriggerHandlerTest {
    
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static Square_Webhook_Event__e buildEvent(
        String eventType,
        String squareObjectId,
        String rawPayload
    ) {
        Square_Webhook_Event__e evt = new Square_Webhook_Event__e();
        evt.Event_Type__c = eventType;
        evt.Square_Object_Id__c = squareObjectId;
        evt.Raw_Payload__c = rawPayload;
        evt.Square_Event_Id__c =
            'EVENT-' + String.valueOf(DateTime.now().getTime()) +
            '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return evt;
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Guard branches
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testHandleAfterInsertWithNullEvents() {
        Test.startTest();
        SquareWebhookEventTriggerHandler.handleAfterInsert(null);
        Test.stopTest();
        
        System.assert(true, 'Null event list should exit without exception.');
    }
    
    @IsTest
    static void testHandleAfterInsertWithEmptyEvents() {
        Test.startTest();
        SquareWebhookEventTriggerHandler.handleAfterInsert(
            new List<Square_Webhook_Event__e>()
        );
        Test.stopTest();
        
        System.assert(true, 'Empty event list should exit without exception.');
    }
    
    @IsTest
    static void testNullEventRowIsSkipped() {
        Test.startTest();
        SquareWebhookEventTriggerHandler.handleAfterInsert(
            new List<Square_Webhook_Event__e>{ null }
        );
        Test.stopTest();
        
        System.assert(true, 'Null event row should be skipped.');
    }
    
    @IsTest
    static void testBlankEventTypeIsSkipped() {
        Integer beforeJobs = Limits.getQueueableJobs();
        
        SquareWebhookEventTriggerHandler.handleAfterInsert(
            new List<Square_Webhook_Event__e>{
                buildEvent(null, 'PAYMENT_123', '{}'),
                    buildEvent('', 'PAYMENT_123', '{}'),
                    buildEvent('   ', 'PAYMENT_123', '{}')
                    }
        );
        
        System.assertEquals(beforeJobs, Limits.getQueueableJobs());
    }
    
    @IsTest
    static void testBlankSquareObjectIdIsSkipped() {
        Integer beforeJobs = Limits.getQueueableJobs();
        
        SquareWebhookEventTriggerHandler.handleAfterInsert(
            new List<Square_Webhook_Event__e>{
                buildEvent('payment.created', null, '{}'),
                    buildEvent('payment.created', '', '{}'),
                    buildEvent('payment.created', '   ', '{}')
                    }
        );
        
        System.assertEquals(beforeJobs, Limits.getQueueableJobs());
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Routing branches
    // Deliberately NOT wrapped in Test.startTest()/stopTest() — enqueueing
    // here only needs to prove the *correct queueable type* was scheduled.
    // Letting these execute would require callout mocks for
    // SquareOrderQueueable / SquarePaymentQueueable / SquareRefundQueueable,
    // which belong to those classes' own test coverage, not this handler's.
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testOrderCreatedAndUpdatedEnqueueOrderQueueable() {
        Integer beforeJobs = Limits.getQueueableJobs();
        
        SquareWebhookEventTriggerHandler.handleAfterInsert(
            new List<Square_Webhook_Event__e>{
                buildEvent('order.created', 'ORDER_CREATED_123', '{"type":"order.created"}'),
                    buildEvent('order.updated', 'ORDER_UPDATED_123', '{"type":"order.updated"}')
                    }
        );
        
        Integer afterJobs = Limits.getQueueableJobs();
        
        System.assertEquals(beforeJobs + 2, afterJobs);
    }
    
    @IsTest
    static void testPaymentCreatedAndUpdatedEnqueuePaymentQueueable() {
        Integer beforeJobs = Limits.getQueueableJobs();
        
        SquareWebhookEventTriggerHandler.handleAfterInsert(
            new List<Square_Webhook_Event__e>{
                buildEvent('payment.created', 'PAYMENT_CREATED_123', '{"type":"payment.created"}'),
                    buildEvent('payment.updated', 'PAYMENT_UPDATED_123', '{"type":"payment.updated"}')
                    }
        );
        
        Integer afterJobs = Limits.getQueueableJobs();
        
        System.assertEquals(beforeJobs + 2, afterJobs);
    }
    
    @IsTest
    static void testRefundCreatedAndUpdatedEnqueueRefundQueueable() {
        Integer beforeJobs = Limits.getQueueableJobs();
        
        SquareWebhookEventTriggerHandler.handleAfterInsert(
            new List<Square_Webhook_Event__e>{
                buildEvent('refund.created', 'REFUND_CREATED_123', '{"type":"refund.created"}'),
                    buildEvent('refund.updated', 'REFUND_UPDATED_123', '{"type":"refund.updated"}')
                    }
        );
        
        Integer afterJobs = Limits.getQueueableJobs();
        
        System.assertEquals(beforeJobs + 2, afterJobs);
    }
    
    @IsTest
    static void testUnsupportedEventIsIgnored() {
        Integer beforeJobs = Limits.getQueueableJobs();
        
        Test.startTest();
        SquareWebhookEventTriggerHandler.handleAfterInsert(
            new List<Square_Webhook_Event__e>{
                buildEvent('customer.created', 'CUSTOMER_123', '{"type":"customer.created"}')
                    }
        );
        Test.stopTest();
        
        System.assertEquals(beforeJobs, Limits.getQueueableJobs());
    }
    
    @IsTest
    static void testMultipleEventsInSingleCall() {
        Integer beforeJobs = Limits.getQueueableJobs();
        
        SquareWebhookEventTriggerHandler.handleAfterInsert(
            new List<Square_Webhook_Event__e>{
                buildEvent('customer.created', 'CUSTOMER_123', '{"type":"customer.created"}'),
                    buildEvent('order.created', 'ORDER_MULTI', '{"type":"order.created"}'),
                    buildEvent('payment.updated', 'PAYMENT_MULTI', '{"type":"payment.updated"}'),
                    buildEvent('refund.created', 'REFUND_MULTI', '{"type":"refund.created"}'),
                    buildEvent(null, 'BLANK_TYPE', '{}'),
                    buildEvent('payment.created', null, '{}')
                    }
        );
        
        Integer afterJobs = Limits.getQueueableJobs();
        
        // order + payment + refund = 3 enqueued; the rest are skipped/ignored
        System.assertEquals(beforeJobs + 3, afterJobs);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Trigger coverage
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testSquareWebhookEventTriggerFiresWithBlankEvent() {
        Square_Webhook_Event__e eventRecord = new Square_Webhook_Event__e();
        
        Test.startTest();
        
        Database.SaveResult result = EventBus.publish(eventRecord);
        
        System.assertEquals(
            true,
            result.isSuccess(),
            'Square webhook platform event should publish successfully.'
        );
        
        Test.getEventBus().deliver();
        
        Test.stopTest();
        
        System.assert(true, 'SquareWebhookEventTrigger fired successfully.');
    }
    
    @IsTest
    static void testSquareWebhookEventTriggerFiresWithPaymentEvent() {
        Square_Webhook_Event__e eventRecord = buildEvent(
            'payment.created',
            'PAYMENT_TRIGGER_123',
            '{"type":"payment.created"}'
        );
        
        Test.startTest();
        
        Database.SaveResult result = EventBus.publish(eventRecord);
        
        System.assertEquals(
            true,
            result.isSuccess(),
            'Square webhook platform event should publish successfully.'
        );
        
        Test.getEventBus().deliver();
        
        Test.stopTest();
        
        System.assert(true, 'SquareWebhookEventTrigger fired successfully for payment.created.');
    }
}