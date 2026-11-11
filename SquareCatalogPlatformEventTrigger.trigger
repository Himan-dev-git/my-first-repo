trigger SquareCatalogPlatformEventTrigger on Square_Catalog__e (after insert) { 
    SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(Trigger.New); 
}