public without sharing class SquareRefundQueueable
implements Queueable, Database.AllowsCallouts {

    private String refundId;
    private String eventType;
    private String rawPayload;
    private Integer retryCount;

    public SquareRefundQueueable(
        String refundId,
        String eventType,
        String rawPayload
    ) {
        this(refundId, eventType, rawPayload, 0);
    }

    public SquareRefundQueueable(
        String refundId,
        String eventType,
        String rawPayload,
        Integer retryCount
    ) {
        this.refundId = refundId;
        this.eventType = eventType;
        this.rawPayload = rawPayload;
        this.retryCount = retryCount == null ? 0 : retryCount;
    }

    public void execute(QueueableContext context) {
        try {
            Boolean success = SquareRefundSyncService.syncRefund(
                refundId,
                eventType,
                rawPayload
            );

            /*
             * Existing process preserved:
             * If refund sync cannot find the matching Salesforce Order,
             * run one immediate retry only.
             */
            if (!success && retryCount < 1) {
                System.debug(
                    LoggingLevel.WARN,
                    'Square refund sync did not find matching Order. ' +
                    'Running one immediate retry only. refundId=' +
                    refundId +
                    ', eventType=' +
                    eventType +
                    ', retryCount=' +
                    retryCount
                );

                System.enqueueJob(
                    new SquareRefundQueueable(
                        refundId,
                        eventType,
                        rawPayload,
                        retryCount + 1
                    )
                );
            }

            if (!success && retryCount >= 1) {
                System.debug(
                    LoggingLevel.WARN,
                    'Square refund sync still did not find matching Order after retry. ' +
                    'Order sync safety check should apply refunded status when the Order syncs. ' +
                    'refundId=' +
                    refundId +
                    ', eventType=' +
                    eventType +
                    ', retryCount=' +
                    retryCount
                );
            }

        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Square refund sync failed. refundId=' +
                refundId +
                ', eventType=' +
                eventType +
                ', retryCount=' +
                retryCount +
                ', error=' +
                e.getMessage()
            );
        }
    }
}