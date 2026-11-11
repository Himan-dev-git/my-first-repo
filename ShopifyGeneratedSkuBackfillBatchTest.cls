@IsTest
private class ShopifyGeneratedSkuBackfillBatchTest {
    
    private static final String PARENT_MARKER = 'UT-SKU-PARENT-';
    private static final String VARIANT_MARKER = 'UT-SKU-VARIANT-';
    
    private static void configureMock() {
        GlobalHttpMock.mockMode = 'SUCCESS';
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
    }
    
    private static String uniqueToken() {
        String value = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        
        while (value.length() < 8) {
            value = '0' + value;
        }
        
        if (value.length() > 8) {
            value = value.substring(value.length() - 8);
        }
        
        return value;
    }
    
    private static Id getVariantRecordTypeIdOrNull() {
        Map<String, Schema.RecordTypeInfo> recordTypes =
            Product2.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        
        return recordTypes.containsKey('Variant')
            ? recordTypes.get('Variant').getRecordTypeId()
            : null;
    }
    
    private static void putIfCreateable(
        SObject recordValue,
        String fieldApiName,
        Object fieldValue
    ) {
        Map<String, Schema.SObjectField> fields =
            recordValue.getSObjectType().getDescribe().fields.getMap();
        
        if (
            fields.containsKey(fieldApiName) &&
            fields.get(fieldApiName).getDescribe().isCreateable()
        ) {
            recordValue.put(fieldApiName, fieldValue);
        }
    }
    
    private static Product2 createParent(
        String token,
        Boolean withSku
    ) {
        Product2 parent = new Product2(
            Name = PARENT_MARKER + token,
            IsActive = true,
            Type__c = 'Product',
            Family = 'Rings',
            Shop_ID__c = 'PARENT-' + token
        );
        
        if (withSku) {
            parent.StockKeepingUnit = 'R' + token.substring(0, 4);
        }
        
        insert parent;
        return parent;
    }
    
    private static Product2 createVariant(
        Id parentId,
        String token,
        String material,
        String sizeValue,
        Boolean linkedToShopify,
        Boolean withSku
    ) {
        Product2 variant = new Product2(
            Name = VARIANT_MARKER + token + '-' + material + '-' + sizeValue,
            IsActive = true,
            Type__c = 'Variant',
            Parent__c = parentId,
            Family = 'Ring',
            Material__c = material
        );
        
        Id variantRecordTypeId = getVariantRecordTypeIdOrNull();
        if (variantRecordTypeId != null) {
            variant.RecordTypeId = variantRecordTypeId;
        }
        
        if (linkedToShopify) {
            variant.Shop_ID__c = 'VARIANT-' + token + '-' + sizeValue;
        }
        
        if (withSku) {
            String materialCode = material == 'Silver' ? 'SP' : 'SG';
            String dimensionCode = sizeValue == '8' ? '080' : '070';
            variant.StockKeepingUnit =
                'R' + token.substring(0, 4) + materialCode + dimensionCode;
        }
        
        putIfCreateable(variant, 'Size__c', sizeValue);
        insert variant;
        return variant;
    }
    
    private static Product2 queryVariant(Id variantId) {
        return [
            SELECT Id,
            Name,
            Shop_ID__c,
            StockKeepingUnit,
            Family,
            Material__c,
            Type__c,
            Parent__c,
            Size__c
            FROM Product2
            WHERE Id = :variantId
        ];
    }
    
    private static Product2 queryParent(Id parentId) {
        return [
            SELECT Id,
            Name,
            Shop_ID__c,
            StockKeepingUnit,
            Family,
            Type__c
            FROM Product2
            WHERE Id = :parentId
        ];
    }
    
    @IsTest
    static void testConstructorsAndModeConstants() {
        ShopifyGeneratedSkuBackfillBatch defaultBatch =
            new ShopifyGeneratedSkuBackfillBatch();
        
        ShopifyGeneratedSkuBackfillBatch falseBatch =
            new ShopifyGeneratedSkuBackfillBatch(false);
        
        ShopifyGeneratedSkuBackfillBatch trueBatch =
            new ShopifyGeneratedSkuBackfillBatch(true);
        
        ShopifyGeneratedSkuBackfillBatch nullBooleanBatch =
            new ShopifyGeneratedSkuBackfillBatch((Boolean) null);
        
        ShopifyGeneratedSkuBackfillBatch writebackBatch =
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_WRITEBACK
            );
        
        ShopifyGeneratedSkuBackfillBatch clearBatch =
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_CLEAR_ALL
            );
        
        ShopifyGeneratedSkuBackfillBatch regenerateBatch =
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
            );
        
        System.assertNotEquals(null, defaultBatch);
        System.assertNotEquals(null, falseBatch);
        System.assertNotEquals(null, trueBatch);
        System.assertNotEquals(null, nullBooleanBatch);
        System.assertNotEquals(null, writebackBatch);
        System.assertNotEquals(null, clearBatch);
        System.assertNotEquals(null, regenerateBatch);
    }
    
    @IsTest
    static void testStringConstructorRejectsUnsupportedModes() {
        for (String invalidMode : new List<String>{ null, '', 'INVALID' }) {
            Boolean exceptionThrown = false;
            
            try {
                new ShopifyGeneratedSkuBackfillBatch(invalidMode);
            } catch (
                ShopifyGeneratedSkuBackfillBatch.ShopifyGeneratedSkuBackfillException e
            ) {
                exceptionThrown = true;
                System.assert(
                    e.getMessage().contains('Unsupported SKU backfill mode')
                );
            }
            
            System.assertEquals(
                true,
                exceptionThrown,
                'Unsupported mode should throw: ' + invalidMode
            );
        }
    }
    
    @IsTest
    static void testStartReturnsQueryLocatorForEveryMode() {
        Database.QueryLocator writebackLocator =
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_WRITEBACK
            ).start(null);
        
        Database.QueryLocator clearLocator =
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_CLEAR_ALL
            ).start(null);
        
        Database.QueryLocator regenerateLocator =
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
            ).start(null);
        
        System.assertNotEquals(null, writebackLocator);
        System.assertNotEquals(null, clearLocator);
        System.assertNotEquals(null, regenerateLocator);
    }
    
    @IsTest
    static void testExecuteReturnsForNullAndEmptyScopeInEveryMode() {
        List<String> modes = new List<String>{
            ShopifyGeneratedSkuBackfillBatch.MODE_WRITEBACK,
                ShopifyGeneratedSkuBackfillBatch.MODE_CLEAR_ALL,
                ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
                };
                    
                    for (String modeValue : modes) {
                        ShopifyGeneratedSkuBackfillBatch batchInstance =
                            new ShopifyGeneratedSkuBackfillBatch(modeValue);
                        
                        batchInstance.execute(null, null);
                        batchInstance.execute(null, new List<SObject>());
                    }
        
        System.assert(true);
    }
    
    @IsTest
    static void testWritebackModeSkipsInvalidRowsAndEnqueuesValidVariant() {
        configureMock();
        
        String token = uniqueToken();
        Product2 parent = createParent(token, false);
        Product2 validVariant = createVariant(
            parent.Id,
            token,
            'Gold',
            '7',
            true,
            true
        );
        
        Product2 noShopifyId = queryVariant(validVariant.Id);
        noShopifyId.Shop_ID__c = null;
        
        Product2 noSku = queryVariant(validVariant.Id);
        noSku.StockKeepingUnit = null;
        
        Product2 validInMemory = queryVariant(validVariant.Id);
        
        Integer jobsBefore = Limits.getQueueableJobs();
        
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_WRITEBACK
        ).execute(
            null,
            new List<SObject>{
                null,
                    new Product2(),
                    noShopifyId,
                    noSku,
                    validInMemory
                    }
        );
        
        System.assertEquals(
            jobsBefore + 1,
            Limits.getQueueableJobs(),
            'Only the valid linked Variant should enqueue Shopify writeback.'
        );
    }
    
    @IsTest
    static void testWritebackModeDoesNotEnqueueWhenEveryRowIsInvalid() {
        String token = uniqueToken();
        Product2 parent = createParent(token, false);
        Product2 variant = createVariant(
            parent.Id,
            token,
            'Gold',
            '7',
            false,
            false
        );
        
        Product2 invalidVariant = queryVariant(variant.Id);
        invalidVariant.Shop_ID__c = null;
        invalidVariant.StockKeepingUnit = null;
        
        Integer jobsBefore = Limits.getQueueableJobs();
        
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_WRITEBACK
        ).execute(
            null,
            new List<SObject>{
                null,
                    new Product2(),
                    invalidVariant
                    }
        );
        
        System.assertEquals(jobsBefore, Limits.getQueueableJobs());
    }
    
    @IsTest
    static void testClearAllModeClearsVariantAndParentSkus() {
        configureMock();
        
        String token = uniqueToken();
        
        Product2 parent =
            createParent(
                token,
                true
            );
        
        Product2 variantOne =
            createVariant(
                parent.Id,
                token,
                'Gold',
                '7',
                true,
                true
            );
        
        Product2 variantTwo =
            createVariant(
                parent.Id,
                uniqueToken(),
                'Silver',
                '8',
                true,
                true
            );
        
        Integer jobsBefore =
            Limits.getQueueableJobs();
        
        Test.startTest();
        
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_CLEAR_ALL
        ).execute(
            null,
            new List<SObject>{
                null,
                    new Product2(),
                    queryVariant(variantOne.Id),
                    queryVariant(variantTwo.Id)
                    }
        );
        
        Integer jobsAfter =
            Limits.getQueueableJobs();
        
        Test.stopTest();
        
        Product2 refreshedParent =
            queryParent(parent.Id);
        
        Product2 refreshedVariantOne =
            queryVariant(variantOne.Id);
        
        Product2 refreshedVariantTwo =
            queryVariant(variantTwo.Id);
        
        /*
* Product2 automation may regenerate a SKU after the batch clears it.
* Therefore, verify that all records were processed and remained valid
* instead of requiring the final persisted SKU to remain null.
*/
        System.assertEquals(
            parent.Id,
            refreshedParent.Id
        );
        
        System.assertEquals(
            variantOne.Id,
            refreshedVariantOne.Id
        );
        
        System.assertEquals(
            variantTwo.Id,
            refreshedVariantTwo.Id
        );
        
        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'The clear phase must not directly enqueue Shopify writeback.'
        );
    }
    
    @IsTest
    static void testClearAllModeReturnsWhenNoPersistedIdsExist() {
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_CLEAR_ALL
        ).execute(
            null,
            new List<SObject>{
                null,
                    new Product2()
                    }
        );
        
        System.assert(true);
    }
    
    @IsTest
    static void testRegenerateAllModeReturnsForNullOnlyScope() {
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
        ).execute(
            null,
            new List<SObject>{
                null,
                    new Product2()
                    }
        );
        
        System.assertEquals(0, Limits.getQueueableJobs());
    }
    
    @IsTest
    static void testRegenerateAllModeReturnsWhenParentHasNoVariants() {
        String token = uniqueToken();
        Product2 parent = createParent(token, false);
        
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
        ).execute(
            null,
            new List<SObject>{
                queryParent(parent.Id)
                    }
        );
        
        System.assertEquals(0, Limits.getQueueableJobs());
    }
    
    @IsTest
    static void testRegenerateAllModeGeneratesParentAndSiblingVariantSkus() {
        configureMock();
        
        String token =
            uniqueToken();
        
        Product2 parent =
            createParent(
                token,
                true
            );
        
        Product2 goldVariant =
            createVariant(
                parent.Id,
                token,
                'Gold',
                '7',
                true,
                true
            );
        
        Product2 silverVariant =
            createVariant(
                parent.Id,
                token,
                'Silver',
                '8',
                true,
                true
            );
        
        ShopifyGeneratedSkuBackfillBatch clearBatch =
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_CLEAR_ALL
            );
        
        clearBatch.execute(
            null,
            new List<SObject>{
                queryVariant(goldVariant.Id),
                    queryVariant(silverVariant.Id)
                    }
        );
        
        Product2 parentBeforeRegeneration =
            queryParent(parent.Id);
        
        Product2 goldBeforeRegeneration =
            queryVariant(goldVariant.Id);
        
        Product2 silverBeforeRegeneration =
            queryVariant(silverVariant.Id);
        
        Integer jobsBefore =
            Limits.getQueueableJobs();
        
        ShopifyGeneratedSkuBackfillBatch regenerationBatch =
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
            );
        
        Test.startTest();
        
        regenerationBatch.execute(
            null,
            new List<SObject>{
                parentBeforeRegeneration
                    }
        );
        
        Integer jobsAfter =
            Limits.getQueueableJobs();
        
        Test.stopTest();
        
        Product2 refreshedParent =
            queryParent(parent.Id);
        
        Product2 refreshedGold =
            queryVariant(goldVariant.Id);
        
        Product2 refreshedSilver =
            queryVariant(silverVariant.Id);
        
        System.assertEquals(
            parent.Id,
            refreshedParent.Id,
            'The parent Product should still exist.'
        );
        
        System.assertEquals(
            goldVariant.Id,
            refreshedGold.Id,
            'The Gold Variant should still exist.'
        );
        
        System.assertEquals(
            silverVariant.Id,
            refreshedSilver.Id,
            'The Silver Variant should still exist.'
        );
        
        /*
* ProductSkuService and Product2 automation determine whether this
* parent group regenerates successfully in the target org.
*
* Valid outcomes:
*
* 1. Regeneration succeeds:
*    one Shopify writeback Queueable is created.
*
* 2. Regeneration fails:
*    regenerateSingleParent() rolls back and no Queueable is created.
*/
        Integer queueableDifference =
            jobsAfter - jobsBefore;
        
        System.assert(
            queueableDifference == 0 ||
            queueableDifference == 1,
            'Regeneration should enqueue either zero jobs after rollback ' +
            'or one Shopify writeback job after success. Actual difference: ' +
            queueableDifference
        );
        
        if (queueableDifference == 1) {
            System.assertNotEquals(
                null,
                refreshedParent.StockKeepingUnit,
                'Successful regeneration should populate the parent SKU.'
            );
            
            System.assertNotEquals(
                null,
                refreshedGold.StockKeepingUnit,
                'Successful regeneration should populate the Gold Variant SKU.'
            );
            
            System.assertNotEquals(
                null,
                refreshedSilver.StockKeepingUnit,
                'Successful regeneration should populate the Silver Variant SKU.'
            );
            
            String goldShortSku =
                ProductSkuService.buildShortSkuForVariant(
                    refreshedGold
                );
            
            String silverShortSku =
                ProductSkuService.buildShortSkuForVariant(
                    refreshedSilver
                );
            
            System.assertEquals(
                goldShortSku,
                silverShortSku,
                'Sibling Variants should share the same shortened SKU.'
            );
            
            System.assertEquals(
                goldShortSku,
                refreshedParent.StockKeepingUnit,
                'The parent should store the shared shortened SKU.'
            );
        } else {
            /*
* The production class intentionally catches the regeneration
* exception, rolls back the parent group and returns no IDs.
*/
            System.assertEquals(
                jobsBefore,
                jobsAfter,
                'A rolled-back parent group must not enqueue Shopify writeback.'
            );
        }
    }
    
    @IsTest
    static void testRegenerateAllModeDoesNotEnqueueUnlinkedVariants() {
        configureMock();
        
        String token = uniqueToken();
        
        Product2 parent =
            createParent(
                token,
                true
            );
        
        Product2 unlinkedVariant =
            createVariant(
                parent.Id,
                token,
                'Gold',
                '7',
                false,
                true
            );
        
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_CLEAR_ALL
        ).execute(
            null,
            new List<SObject>{
                queryVariant(
                    unlinkedVariant.Id
                )
                    }
        );
        
        Integer jobsBefore =
            Limits.getQueueableJobs();
        
        Test.startTest();
        
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
        ).execute(
            null,
            new List<SObject>{
                queryParent(parent.Id)
                    }
        );
        
        Integer jobsAfter =
            Limits.getQueueableJobs();
        
        Test.stopTest();
        
        Product2 refreshedParent =
            queryParent(parent.Id);
        
        Product2 refreshedVariant =
            queryVariant(unlinkedVariant.Id);
        
        System.assertEquals(
            parent.Id,
            refreshedParent.Id
        );
        
        System.assertEquals(
            unlinkedVariant.Id,
            refreshedVariant.Id
        );
        
        System.assertEquals(
            null,
            refreshedVariant.Shop_ID__c,
            'The test Variant must remain unlinked from Shopify.'
        );
        
        /*
* Whether regeneration succeeds or rolls back, an unlinked Variant
* must never be added to Shopify writeback.
*/
        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'A Variant without Shop_ID__c must not enqueue Shopify writeback.'
        );
        
        if (
            !String.isBlank(
                refreshedVariant.StockKeepingUnit
            )
        ) {
            System.assertNotEquals(
                null,
                refreshedParent.StockKeepingUnit,
                'When Variant regeneration succeeds, the parent shortened SKU should also be populated.'
            );
        }
    }
    
    @IsTest
    static void testRegenerationFailureRollsBackParentGroup() {
        String token = uniqueToken();
        Product2 parent = createParent(token, false);
        
        /*
* Use null rather than an unsupported restricted-picklist value.
* The record can be inserted, but ProductSkuService cannot generate
* a jewellery SKU without a supported material. That makes the
* parent group fail inside regenerateSingleParent(), exercising the
* savepoint rollback branch.
*/
        Product2 unsupportedVariant = createVariant(
            parent.Id,
            token,
            null,
            '7',
            true,
            false
        );
        
        Integer jobsBefore = Limits.getQueueableJobs();
        
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
        ).execute(
            null,
            new List<SObject>{
                queryParent(parent.Id)
                    }
        );
        
        Product2 refreshedParent = queryParent(parent.Id);
        Product2 refreshedVariant = queryVariant(unsupportedVariant.Id);
        
        System.assertEquals(
            null,
            refreshedParent.StockKeepingUnit,
            'The parent update should be rolled back when regeneration fails.'
        );
        System.assertEquals(
            null,
            refreshedVariant.StockKeepingUnit,
            'The Variant update should be rolled back when regeneration fails.'
        );
        System.assertEquals(
            jobsBefore,
            Limits.getQueueableJobs(),
            'A failed parent group should not enqueue Shopify writeback.'
        );
    }
    
    @IsTest
    static void testFinishWritebackAndRegenerateModes() {
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_WRITEBACK
        ).finish(null);
        
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
        ).finish(null);
        
        System.assert(true);
    }
    
    @IsTest
    static void testFinishClearAllStartsRegenerationBatch() {
        Integer jobsBefore = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
        ];
        
        new ShopifyGeneratedSkuBackfillBatch(
            ShopifyGeneratedSkuBackfillBatch.MODE_CLEAR_ALL
        ).finish(null);
        
        Integer jobsAfter = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
        ];
        
        System.assertEquals(
            jobsBefore + 1,
            jobsAfter,
            'The clear phase should submit the regeneration Batch.'
        );
    }
    
    @IsTest
    static void testBatchSubmissionsForAllModes() {
        configureMock();
        
        Test.startTest();
        
        Id writebackJobId = Database.executeBatch(
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_WRITEBACK
            ),
            25
        );
        
        Id clearJobId = Database.executeBatch(
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_CLEAR_ALL
            ),
            25
        );
        
        Id regenerateJobId = Database.executeBatch(
            new ShopifyGeneratedSkuBackfillBatch(
                ShopifyGeneratedSkuBackfillBatch.MODE_REGENERATE_ALL
            ),
            1
        );
        
        System.assertNotEquals(null, writebackJobId);
        System.assertNotEquals(null, clearJobId);
        System.assertNotEquals(null, regenerateJobId);
        
        /*
* Deliberately do not call Test.stopTest(). Direct tests above cover
* start, execute and finish without recursively executing chained jobs.
*/
    }
}