public without sharing class ShopifyGeneratedSkuBackfillBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    @TestVisible
    private static final String MODE_WRITEBACK = 'WRITEBACK';

    @TestVisible
    private static final String MODE_CLEAR_ALL = 'CLEAR_ALL';

    @TestVisible
    private static final String MODE_REGENERATE_ALL = 'REGENERATE_ALL';

    private static final Integer REGENERATION_BATCH_SIZE = 1;

    private String batchMode;

    public class ShopifyGeneratedSkuBackfillException extends Exception {}

    public ShopifyGeneratedSkuBackfillBatch() {
        this.batchMode = MODE_WRITEBACK;
    }

    /*
     * Compatibility constructor for existing callers:
     * false = write existing Salesforce SKUs to Shopify
     * true  = clear and regenerate every parent/variant SKU
     */
    public ShopifyGeneratedSkuBackfillBatch(Boolean regenerateAllSkus) {
        this.batchMode = regenerateAllSkus == true
            ? MODE_CLEAR_ALL
            : MODE_WRITEBACK;
    }

    public ShopifyGeneratedSkuBackfillBatch(String requestedMode) {
        if (
            requestedMode != MODE_WRITEBACK &&
            requestedMode != MODE_CLEAR_ALL &&
            requestedMode != MODE_REGENERATE_ALL
        ) {
            throw new ShopifyGeneratedSkuBackfillException(
                'Unsupported SKU backfill mode: ' + requestedMode
            );
        }

        this.batchMode = requestedMode;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (batchMode == MODE_REGENERATE_ALL) {
            /*
             * Parent Products are the Batch scope so every parent is processed
             * as one complete style. The execute method loads every child Variant.
             */
            return Database.getQueryLocator([
                SELECT Id,
                       Name,
                       Shop_ID__c,
                       StockKeepingUnit,
                       Family,
                       Type__c
                FROM Product2
                WHERE Type__c = 'Product'
                ORDER BY Family, CreatedDate, Id
            ]);
        }

        if (batchMode == MODE_CLEAR_ALL) {
            /*
             * Clear only Variants that can be regenerated and their parent Products.
             * Orphan Variants are intentionally excluded so they are not left blank.
             */
            return Database.getQueryLocator([
                SELECT Id,
                       Parent__c,
                       StockKeepingUnit
                FROM Product2
                WHERE Type__c = 'Variant'
                  AND Parent__c != null
                ORDER BY Parent__c, CreatedDate, Id
            ]);
        }

        /* WRITEBACK */
        return Database.getQueryLocator([
            SELECT Id,
                   Shop_ID__c,
                   StockKeepingUnit
            FROM Product2
            WHERE Type__c = 'Variant'
              AND Shop_ID__c != null
              AND StockKeepingUnit != null
            ORDER BY CreatedDate, Id
        ]);
    }

    public void execute(
        Database.BatchableContext context,
        List<SObject> scope
    ) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        if (batchMode == MODE_CLEAR_ALL) {
            clearExistingSkus(scope);
            return;
        }

        if (batchMode == MODE_REGENERATE_ALL) {
            regenerateAllSkus(scope);
            return;
        }

        writeExistingSkusToShopify(scope);
    }

    /*
     * ============================================================
     * PHASE 1: CLEAR CURRENT PARENT AND VARIANT SKUS
     * ============================================================
     */
    private static void clearExistingSkus(List<SObject> scope) {
        Set<Id> parentIds = new Set<Id>();
        List<Product2> recordsToClear = new List<Product2>();

        for (SObject scopeRecord : scope) {
            Product2 variant = (Product2) scopeRecord;

            if (variant == null || variant.Id == null) {
                continue;
            }

            recordsToClear.add(
                new Product2(
                    Id = variant.Id,
                    StockKeepingUnit = null
                )
            );

            if (variant.Parent__c != null) {
                parentIds.add(variant.Parent__c);
            }
        }

        for (Id parentId : parentIds) {
            recordsToClear.add(
                new Product2(
                    Id = parentId,
                    StockKeepingUnit = null
                )
            );
        }

        if (recordsToClear.isEmpty()) {
            return;
        }

        Database.SaveResult[] results = Database.update(recordsToClear, false);

        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) {
                continue;
            }

            logSaveErrors(
                'SKU clear failed',
                recordsToClear[index].Id,
                null,
                results[index].getErrors()
            );
        }

        System.debug(
            LoggingLevel.INFO,
            'SKU clear phase processed records. RecordCount=' +
            recordsToClear.size()
        );
    }

    /*
     * ============================================================
     * PHASE 2: REGENERATE EVERY PRODUCT FAMILY
     * ============================================================
     */
    private static void regenerateAllSkus(List<SObject> scope) {
        Set<Id> parentIds = new Set<Id>();

        for (SObject scopeRecord : scope) {
            Product2 parentProduct = (Product2) scopeRecord;

            if (parentProduct != null && parentProduct.Id != null) {
                parentIds.add(parentProduct.Id);
            }
        }

        if (parentIds.isEmpty()) {
            return;
        }

        List<Product2> variants = queryVariantsForParents(parentIds);

        if (variants.isEmpty()) {
            return;
        }

        Map<Id, List<Product2>> variantsByParentId =
            new Map<Id, List<Product2>>();

        for (Product2 variant : variants) {
            if (variant.Parent__c == null) {
                continue;
            }

            if (!variantsByParentId.containsKey(variant.Parent__c)) {
                variantsByParentId.put(
                    variant.Parent__c,
                    new List<Product2>()
                );
            }

            variantsByParentId.get(variant.Parent__c).add(variant);
        }

        List<Id> variantIdsForShopify = new List<Id>();

        for (Id parentId : parentIds) {
            List<Product2> siblingVariants = variantsByParentId.get(parentId);

            if (siblingVariants == null || siblingVariants.isEmpty()) {
                continue;
            }

            variantIdsForShopify.addAll(
                regenerateSingleParent(parentId, siblingVariants)
            );
        }

        enqueueShopifyWriteback(variantIdsForShopify);
    }

    private static List<Id> regenerateSingleParent(
        Id parentId,
        List<Product2> siblingVariants
    ) {
        List<Id> shopifyVariantIds = new List<Id>();

        if (
            parentId == null ||
            siblingVariants == null ||
            siblingVariants.isEmpty()
        ) {
            return shopifyVariantIds;
        }

        Savepoint parentSavepoint = Database.setSavepoint();

        try {
            for (Product2 variant : siblingVariants) {
                variant.StockKeepingUnit = null;
                variant.Type__c = 'Variant';
            }

            /*
             * The clear phase has already removed all persisted parent/Variant SKUs.
             * ProductSkuService can now start each Product Type sequence from 0001
             * and will reuse one style number for all siblings under this parent.
             */
            ProductSkuService.assignSkusForNewInboundVariants(siblingVariants);

            String parentShortSku;
            List<Product2> variantUpdates = new List<Product2>();

            for (Product2 variant : siblingVariants) {
                if (String.isBlank(variant.StockKeepingUnit)) {
                    throw new ShopifyGeneratedSkuBackfillException(
                        'SKU generation returned blank for Variant ' + variant.Id
                    );
                }

                String currentShortSku =
                    ProductSkuService.buildShortSkuForVariant(variant);

                if (String.isBlank(currentShortSku)) {
                    throw new ShopifyGeneratedSkuBackfillException(
                        'Could not derive parent short SKU from Variant ' +
                        variant.Id
                    );
                }

                if (
                    parentShortSku != null &&
                    parentShortSku != currentShortSku
                ) {
                    throw new ShopifyGeneratedSkuBackfillException(
                        'Variants under Parent ' + parentId +
                        ' generated different style numbers. Existing=' +
                        parentShortSku + ', New=' + currentShortSku
                    );
                }

                parentShortSku = currentShortSku;

                Product2 variantUpdate = new Product2(
                    Id = variant.Id,
                    StockKeepingUnit = variant.StockKeepingUnit
                );

                copyGeneratedFieldIfPresent(
                    variant,
                    variantUpdate,
                    'Style_Number__c'
                );
                copyGeneratedFieldIfPresent(
                    variant,
                    variantUpdate,
                    'SKU_Style_Number__c'
                );
                copyGeneratedFieldIfPresent(
                    variant,
                    variantUpdate,
                    'Dimension_Code__c'
                );

                variantUpdates.add(variantUpdate);
            }

            Database.update(variantUpdates, true);

            Database.update(
                new Product2(
                    Id = parentId,
                    StockKeepingUnit = parentShortSku
                ),
                true
            );

            for (Product2 variant : siblingVariants) {
                if (!String.isBlank(variant.Shop_ID__c)) {
                    shopifyVariantIds.add(variant.Id);
                }

                System.debug(
                    LoggingLevel.INFO,
                    'SKU regenerated. ParentId=' + parentId +
                    ', VariantId=' + variant.Id +
                    ', NewSKU=' + variant.StockKeepingUnit
                );
            }

            System.debug(
                LoggingLevel.INFO,
                'Parent shortened SKU regenerated. ParentId=' + parentId +
                ', NewSKU=' + parentShortSku
            );

            return shopifyVariantIds;

        } catch (Exception regenerationException) {
            Database.rollback(parentSavepoint);

            System.debug(
                LoggingLevel.ERROR,
                'SKU regeneration rolled back for ParentId=' + parentId +
                ', Error=' + regenerationException.getMessage() +
                ', StackTrace=' +
                regenerationException.getStackTraceString()
            );

            return new List<Id>();
        }
    }

    private static List<Product2> queryVariantsForParents(Set<Id> parentIds) {
        List<String> fields = new List<String>{
            'Id',
            'Name',
            'Shop_ID__c',
            'StockKeepingUnit',
            'Family',
            'Material__c',
            'Type__c',
            'Parent__c',
            'Parent__r.Id',
            'Parent__r.Name',
            'Parent__r.Shop_ID__c',
            'Parent__r.StockKeepingUnit',
            'Parent__r.Type__c',
            'Parent__r.Family',
            'Size__c'
        };

        addFieldIfPresent(fields, 'Product_Type__c');
        addFieldIfPresent(fields, 'Type_Code__c');
        addFieldIfPresent(fields, 'Metal_Colour__c');
        addFieldIfPresent(fields, 'Metal_Color__c');
        addFieldIfPresent(fields, 'Dimension__c');
        addFieldIfPresent(fields, 'Ring_Size__c');
        addFieldIfPresent(fields, 'Chain_Length__c');
        addFieldIfPresent(fields, 'Length__c');
        addFieldIfPresent(fields, 'Parent_SKU_Key__c');
        addFieldIfPresent(fields, 'SF_Parent_Product_Name__c');
        addFieldIfPresent(fields, 'Style_Number__c');
        addFieldIfPresent(fields, 'SKU_Style_Number__c');
        addFieldIfPresent(fields, 'Dimension_Code__c');

        String queryText =
            'SELECT ' + String.join(fields, ', ') +
            ' FROM Product2' +
            ' WHERE Type__c = \'Variant\'' +
            ' AND Parent__c IN :parentIds' +
            ' ORDER BY Parent__c, CreatedDate, Id';

        return Database.query(queryText);
    }

    /*
     * ============================================================
     * WRITE EXISTING SALESFORCE SKUS TO SHOPIFY
     * ============================================================
     */
    private static void writeExistingSkusToShopify(List<SObject> scope) {
        List<Id> variantIdsForShopify = new List<Id>();

        for (SObject scopeRecord : scope) {
            Product2 variant = (Product2) scopeRecord;

            if (
                variant == null ||
                variant.Id == null ||
                String.isBlank(variant.Shop_ID__c) ||
                String.isBlank(variant.StockKeepingUnit)
            ) {
                continue;
            }

            variantIdsForShopify.add(variant.Id);
        }

        enqueueShopifyWriteback(variantIdsForShopify);
    }

    private static void enqueueShopifyWriteback(List<Id> variantIds) {
        if (variantIds == null || variantIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new ShopifySkuWritebackQueueable(variantIds)
        );

        System.debug(
            LoggingLevel.INFO,
            'Shopify SKU writeback Queueable created. VariantCount=' +
            variantIds.size()
        );
    }

    private static void addFieldIfPresent(
        List<String> fields,
        String fieldApiName
    ) {
        if (
            fields == null ||
            String.isBlank(fieldApiName) ||
            fields.contains(fieldApiName)
        ) {
            return;
        }

        if (
            Product2.SObjectType.getDescribe()
                .fields.getMap()
                .containsKey(fieldApiName)
        ) {
            fields.add(fieldApiName);
        }
    }

    private static void copyGeneratedFieldIfPresent(
        Product2 source,
        Product2 target,
        String fieldApiName
    ) {
        if (
            source == null ||
            target == null ||
            String.isBlank(fieldApiName) ||
            !Product2.SObjectType.getDescribe()
                .fields.getMap()
                .containsKey(fieldApiName)
        ) {
            return;
        }

        try {
            Object generatedValue = source.get(fieldApiName);

            if (generatedValue != null) {
                target.put(fieldApiName, generatedValue);
            }
        } catch (SObjectException ignoredException) {
            // Optional field was not queried or is unavailable in this org.
        }
    }

    private static void logSaveErrors(
        String prefix,
        Id productId,
        String sku,
        Database.Error[] errors
    ) {
        if (errors == null) {
            return;
        }

        for (Database.Error saveError : errors) {
            if (saveError == null) {
                continue;
            }

            System.debug(
                LoggingLevel.ERROR,
                prefix +
                '. Product2Id=' + productId +
                ', SKU=' + sku +
                ', StatusCode=' + saveError.getStatusCode() +
                ', Message=' + saveError.getMessage()
            );
        }
    }

    public void finish(Database.BatchableContext context) {
        if (batchMode == MODE_CLEAR_ALL) {
            Id regenerationJobId = Database.executeBatch(
                new ShopifyGeneratedSkuBackfillBatch(
                    MODE_REGENERATE_ALL
                ),
                REGENERATION_BATCH_SIZE
            );

            System.debug(
                LoggingLevel.INFO,
                'SKU clear phase completed. Full regeneration Batch started. ' +
                'BatchJobId=' + regenerationJobId
            );

            return;
        }

        if (batchMode == MODE_REGENERATE_ALL) {
            System.debug(
                LoggingLevel.INFO,
                'Full Salesforce SKU regeneration completed. ' +
                'Shopify writeback jobs were queued for linked Variants.'
            );

            return;
        }

        System.debug(
            LoggingLevel.INFO,
            'Existing Salesforce SKU writeback completed.'
        );
    }
}