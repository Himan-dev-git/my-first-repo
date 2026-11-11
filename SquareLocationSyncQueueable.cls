public without sharing class SquareLocationSyncQueueable
implements Queueable, Database.AllowsCallouts {

    private Id locationId;
    private String sourceTopic;

    public SquareLocationSyncQueueable(
        Id locationId,
        String sourceTopic
    ) {
        this.locationId = locationId;
        this.sourceTopic = sourceTopic;
    }

    public void execute(QueueableContext context) {
        if (locationId == null) {
            System.debug(
                LoggingLevel.WARN,
                'SquareLocationSyncQueueable skipped because locationId is null.'
            );
            return;
        }

        try {
            SquareLocationSyncService.syncSalesforceLocationToSquare(
                locationId,
                sourceTopic
            );

        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'SquareLocationSyncQueueable failed. locationId=' +
                locationId +
                ', sourceTopic=' +
                sourceTopic +
                ', error=' +
                e.getMessage() +
                ', stack=' +
                e.getStackTraceString()
            );
        }
    }
}