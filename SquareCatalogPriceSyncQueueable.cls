public without sharing class SquareCatalogPriceSyncQueueable
implements Queueable, Database.AllowsCallouts {

    public void execute(QueueableContext context) {
        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();
    }
}