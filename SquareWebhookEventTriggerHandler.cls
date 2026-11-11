public without sharing class SquareWebhookEventTriggerHandler {

    public static void handleAfterInsert(List<Square_Webhook_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        for (Square_Webhook_Event__e evt : events) {
            if (evt == null) {
                continue;
            }

            String eventType = evt.Event_Type__c;
            String squareObjectId = evt.Square_Object_Id__c;
            String rawPayload = evt.Raw_Payload__c;

            if (String.isBlank(eventType) || String.isBlank(squareObjectId)) {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareWebhookEventTriggerHandler skipped event because eventType or squareObjectId is blank.'
                );
                continue;
            }

            if (
                eventType == 'order.created' ||
                eventType == 'order.updated'
            ) {
                System.debug(
                    LoggingLevel.INFO,
                    'SquareWebhookEventTriggerHandler enqueueing SquareOrderQueueable. ' +
                    'squareOrderId=' + squareObjectId +
                    ', eventType=' + eventType
                );

                System.enqueueJob(
                    new SquareOrderQueueable(
                        squareObjectId,
                        eventType,
                        rawPayload
                    )
                );

            } else if (
                eventType == 'payment.created' ||
                eventType == 'payment.updated'
            ) {
                System.debug(
                    LoggingLevel.INFO,
                    'SquareWebhookEventTriggerHandler enqueueing SquarePaymentQueueable. ' +
                    'squarePaymentId=' + squareObjectId +
                    ', eventType=' + eventType
                );

                System.enqueueJob(
                    new SquarePaymentQueueable(
                        squareObjectId
                    )
                );

            } else if (
                eventType == 'refund.created' ||
                eventType == 'refund.updated'
            ) {
                System.debug(
                    LoggingLevel.INFO,
                    'SquareWebhookEventTriggerHandler enqueueing SquareRefundQueueable. ' +
                    'squareRefundId=' + squareObjectId +
                    ', eventType=' + eventType
                );

                System.enqueueJob(
                    new SquareRefundQueueable(
                        squareObjectId,
                        eventType,
                        rawPayload
                    )
                );

            } else {
                System.debug(
                    LoggingLevel.INFO,
                    'SquareWebhookEventTriggerHandler ignored Square event. ' +
                    'squareObjectId=' + squareObjectId +
                    ', eventType=' + eventType
                );
            }
        }
    }
}