trigger SquareWebhookEventTrigger on Square_Webhook_Event__e (after insert) {
    SquareWebhookEventTriggerHandler.handleAfterInsert(Trigger.New);
}