public without sharing class ProductSalesInsightMigrationBatch
    implements Database.Batchable<SObject> {

    public Database.QueryLocator start(
        Database.BatchableContext context
    ) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Product2
            WHERE Type__c = 'Variant'
        ]);
    }

    public void execute(
        Database.BatchableContext context,
        List<SObject> scope
    ) {
        Set<Id> productIds = new Set<Id>();

        for (SObject record : scope) {
            if (record != null) {
                productIds.add((Id) record.get('Id'));
            }
        }

        if (!productIds.isEmpty()) {
            ProductSalesInsightService.refreshForProducts(
                productIds
            );
        }
    }

    public void finish(
        Database.BatchableContext context
    ) {
        System.debug(
            LoggingLevel.INFO,
            'Product sales insight migration completed.'
        );
    }
}