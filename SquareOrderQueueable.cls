public without sharing class SquareOrderQueueable
implements Queueable, Database.AllowsCallouts {
    
    private String squareOrderId;
    private String eventType;
    private String rawPayload;
    
    public SquareOrderQueueable(
        String squareOrderId,
        String eventType,
        String rawPayload
    ) {
        this.squareOrderId = squareOrderId;
        this.eventType = eventType;
        this.rawPayload = rawPayload;
    }
    
    public void execute(QueueableContext context) {
        try {
            SquareOrderStatusSyncService.syncSquareOrder(
                squareOrderId,
                eventType,
                rawPayload
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Square order sync failed. squareOrderId=' +
                squareOrderId +
                ', eventType=' +
                eventType +
                ', error=' +
                e.getMessage()
            );
            
            // CHANGE: No process change here.
            // This queueable already correctly delegates order sync.
            // Refund fix is handled in SquareRefundSyncService.
        }
    }
    
}