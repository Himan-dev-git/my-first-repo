public without sharing class InventoryLevelRetryQueueable implements Queueable {

    private String payloadJson;

    /*
     * Single-argument constructor to avoid Developer Console compile-order issues.
     */
    public InventoryLevelRetryQueueable(String payloadJson) {
        this.payloadJson = payloadJson;
    }

    public void execute(QueueableContext context) {
        if (String.isBlank(payloadJson)) {
            System.debug(LoggingLevel.WARN, 'InventoryLevelRetryQueueable skipped: payloadJson is blank.');
            return;
        }

        Map<String, Object> payload;

        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'InventoryLevelRetryQueueable failed to deserialize payload. Error=' +
                e.getMessage() +
                ', payloadJson=' + payloadJson
            );
            return;
        }

        InventoryLevelOrchestrationService.processInventoryLevelWebhook(payload);
    }
}