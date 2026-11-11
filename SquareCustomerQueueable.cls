public without sharing class SquareCustomerQueueable
implements Queueable, Database.AllowsCallouts {

    private String customerId;
    private String eventType;
    private String rawPayload;

    public SquareCustomerQueueable(
        String customerId,
        String eventType,
        String rawPayload
    ) {
        this.customerId = customerId;
        this.eventType = eventType;
        this.rawPayload = rawPayload;
    }

    public void execute(QueueableContext context) {
        try {
            SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
                customerId,
                eventType,
                rawPayload
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Square customer sync failed. customerId=' +
                customerId +
                ', eventType=' +
                eventType +
                ', error=' +
                e.getMessage()
            );

            SquareCustomerConsentService.logCustomerSyncError(
                customerId,
                eventType,
                rawPayload,
                e
            );
        }
    }
}