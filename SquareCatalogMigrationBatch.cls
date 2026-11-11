public without sharing class SquareCatalogMigrationBatch
    implements Database.Batchable<SObject>,
               Database.AllowsCallouts {

    /*
     * When true, inventory migration starts after the complete
     * catalog Batch finishes.
     */
    private Boolean startInventoryAfterCatalog;

    public SquareCatalogMigrationBatch() {
        this(false);
    }

    public SquareCatalogMigrationBatch(
        Boolean startInventoryAfterCatalog
    ) {
        this.startInventoryAfterCatalog =
            startInventoryAfterCatalog == true;
    }

    public Database.QueryLocator start(
        Database.BatchableContext context
    ) {
        /*
         * Only Variant records are passed to SquareCatalogService.
         *
         * That existing service:
         * - loads the parent Product;
         * - creates or updates the Square ITEM;
         * - creates or updates the ITEM_VARIATION;
         * - copies the current Salesforce SKU;
         * - reads the Square Pricebook price;
         * - writes Square IDs back to Salesforce;
         * - and queues the parent image synchronization.
         */
        return Database.getQueryLocator([
            SELECT Id
            FROM Product2
            WHERE Type__c = 'Variant'
            AND Parent__c != null
            AND StockKeepingUnit != null
            AND IsActive = true
            ORDER BY Parent__c, Id
        ]);
    }

    public void execute(
        Database.BatchableContext context,
        List<SObject> scope
    ) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        /*
         * Keep Batch scope at 1.
         *
         * SquareCatalogService enqueues an image Queueable.
         * Processing multiple variants in one Batch transaction could
         * create more than one Queueable and reproduce:
         *
         * Too many queueable jobs added to the queue
         */
        List<Id> variantIds =
            new List<Id>();

        for (SObject scopeRecord : scope) {
            if (scopeRecord != null) {
                variantIds.add(
                    (Id) scopeRecord.get('Id')
                );
            }
        }

        if (variantIds.isEmpty()) {
            return;
        }

        try {
            SquareCatalogService.syncProductsToSquare(
                variantIds
            );

            System.debug(
                LoggingLevel.INFO,
                'Square catalog migration processed variants: ' +
                variantIds
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Square catalog migration failed. ' +
                'VariantIds=' + variantIds +
                ', Error=' + e.getMessage() +
                ', Stack=' + e.getStackTraceString()
            );

            /*
             * Re-throw so Apex Jobs correctly reports the failed scope.
             */
            throw e;
        }
    }

    public void finish(
        Database.BatchableContext context
    ) {
        System.debug(
            LoggingLevel.INFO,
            'Square catalog migration completed.'
        );

        if (!startInventoryAfterCatalog) {
            return;
        }

        /*
         * finish() runs after all catalog transactions and their DML
         * have committed. Inventory can now safely use the Square
         * variation IDs stored in Salesforce.
         */
        Database.executeBatch(
            new SquareInventoryMigrationBatch(),
            25
        );

        System.debug(
            LoggingLevel.INFO,
            'Square inventory migration started after catalog migration.'
        );
    }
}