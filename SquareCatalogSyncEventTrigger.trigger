trigger SquareCatalogSyncEventTrigger on Square_Catalog_Sync_Event__e (after insert) {
    if (!Trigger.new.isEmpty()) {
        System.enqueueJob(new SquareCatalogPriceSyncQueueable());
    }
}