@IsTest
private class InventoryLevelRetryJobTest {
    
    private static Integer counter = 0;
    
    /*
* ============================================================
* HELPERS
* ============================================================
*/
    
    private static void configureMock() {
        GlobalHttpMock.mockMode = 'SUCCESS';
        
        Test.setMock(
            HttpCalloutMock.class,
            new GlobalHttpMock()
        );
    }
    
    private static String nextShortId(
        String prefix
    ) {
        counter++;
        
        return prefix +
            String.valueOf(counter);
    }
    
    private static String uniqueText(
        String prefix
    ) {
        counter++;
        
        return prefix +
            '-' +
            String.valueOf(counter);
    }
    
    private static Boolean fieldExists(
        String objectApiName,
        String fieldApiName
    ) {
        if (
            !Schema.getGlobalDescribe()
            .containsKey(objectApiName)
        ) {
            return false;
        }
        
        return Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields
            .getMap()
            .containsKey(fieldApiName);
    }
    
    private static Id getVariantRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ];
        
        return recordTypes.isEmpty()
            ? null
            : recordTypes[0].Id;
    }
    
    private static Product2 createVariant(
        String shopifyVariantId,
        String inventoryItemId
    ) {
        configureMock();
        
        Product2 parent = new Product2(
            Name = uniqueText(
                'Retry Parent Product'
            ),
            IsActive = true,
            Shop_ID__c = nextShortId('P')
        );
        
        if (fieldExists('Product2', 'Type__c')) {
            parent.put(
                'Type__c',
                'Product'
            );
        }
        
        if (
            fieldExists(
                'Product2',
                'Updated_by_Integration__c'
            )
        ) {
            parent.put(
                'Updated_by_Integration__c',
                true
            );
        }
        
        insert parent;
        
        Product2 variant = new Product2(
            Name = uniqueText(
                'Retry Variant Product'
            ),
            IsActive = true,
            Parent__c = parent.Id,
            Shop_ID__c = shopifyVariantId,
            Inventory_Item_Id__c =
            inventoryItemId
        );
        
        if (fieldExists('Product2', 'Type__c')) {
            variant.put(
                'Type__c',
                'Variant'
            );
        }
        
        if (
            fieldExists(
                'Product2',
                'Updated_by_Integration__c'
            )
        ) {
            variant.put(
                'Updated_by_Integration__c',
                true
            );
        }
        
        Id variantRecordTypeId =
            getVariantRecordTypeId();
        
        if (variantRecordTypeId != null) {
            variant.RecordTypeId =
                variantRecordTypeId;
        }
        
        insert variant;
        
        return variant;
    }
    
    private class FakeRetryScheduler
        implements InventoryLevelRetryJob.RetryScheduler {
            
            public Integer callCount = 0;
            public String receivedInventoryItemId;
            public String receivedLocationId;
            public Decimal receivedQuantity;
            public Integer receivedAttempt;
            
            public void schedule(
                String inventoryItemId,
                String shopifyLocationId,
                Decimal availableQty,
                Integer nextAttempt
            ) {
                callCount++;
                
                receivedInventoryItemId =
                    inventoryItemId;
                
                receivedLocationId =
                    shopifyLocationId;
                
                receivedQuantity =
                    availableQty;
                
                receivedAttempt =
                    nextAttempt;
            }
        }
    
    private static Id createSalesforceLocation(
        String shopifyLocationId
    ) {
        SObject locationRecord =
            Schema.getGlobalDescribe()
            .get('Location')
            .newSObject();
        
        locationRecord.put(
            'Name',
            uniqueText('Retry Location')
        );
        
        if (
            fieldExists(
                'Location',
                'LocationType'
            )
        ) {
            locationRecord.put(
                'LocationType',
                'Warehouse'
            );
        }
        
        if (
            fieldExists(
                'Location',
                'Shopify_Location_ID__c'
            )
        ) {
            locationRecord.put(
                'Shopify_Location_ID__c',
                shopifyLocationId
            );
        }
        
        insert locationRecord;
        
        return (Id) locationRecord.get('Id');
    }
    
    private static Inventory__c queryInventory(
        String inventoryKey
    ) {
        return [
            SELECT Id,
            Variant__c,
            Location__c,
            Available__c,
            Salesforce_Available__c,
            Shopify_Inventory_Item_ID__c,
            Shopify_Location_ID__c,
            Inventory_Key__c,
            Sync_Status__c,
            Last_Sync_At__c
            FROM Inventory__c
            WHERE Inventory_Key__c = :inventoryKey
            LIMIT 1
        ];
    }
    
    /*
* ============================================================
* VARIANT FOUND — INSERT USING SALESFORCE AVAILABLE
* ============================================================
*/
    
    @IsTest
    static void testExecuteVariantFoundInsertsInventory() {
        String inventoryItemId =
            nextShortId('II');
        
        String shopifyLocationId =
            nextShortId('L');
        
        String shopifyVariantId =
            nextShortId('V');
        
        Product2 variant =
            createVariant(
                shopifyVariantId,
                inventoryItemId
            );
        
        Id locationId =
            createSalesforceLocation(
                shopifyLocationId
            );
        
        configureMock();
        
        System.assertEquals(
            false,
            InventorySyncControl.skipOutbound
        );
        
        Test.startTest();
        
        new InventoryLevelRetryJob(
            inventoryItemId,
            shopifyLocationId,
            12,
            1
        ).execute(null);
        
        Test.stopTest();
        
        String expectedInventoryKey =
            shopifyVariantId +
            '-' +
            shopifyLocationId;
        
        Inventory__c inventory =
            queryInventory(
                expectedInventoryKey
            );
        
        System.assertEquals(
            variant.Id,
            inventory.Variant__c
        );
        
        System.assertEquals(
            locationId,
            inventory.Location__c
        );
        
        System.assertEquals(
            12,
            inventory.Salesforce_Available__c,
            'A newly created Inventory row should initialize Salesforce_Available__c from the Shopify available quantity.'
        );

        System.assertEquals(
            null,
            inventory.Available__c,
            'InventoryLevelRetryJob no longer writes Available__c; that field remains the Shopify snapshot.'
        );
        
        System.assertEquals(
            inventoryItemId,
            inventory.Shopify_Inventory_Item_ID__c
        );
        
        System.assertEquals(
            shopifyLocationId,
            inventory.Shopify_Location_ID__c
        );
        
        System.assertEquals(
            expectedInventoryKey,
            inventory.Inventory_Key__c
        );
        
        System.assertEquals(
            'Success',
            inventory.Sync_Status__c
        );
        
        System.assertNotEquals(
            null,
            inventory.Last_Sync_At__c
        );
        
        System.assertEquals(
            false,
            InventorySyncControl.skipOutbound,
            'The outbound bypass flag must be restored in the finally block.'
        );
        
        if (
            fieldExists(
                'Inventory__c',
                'Shop_ID__c'
            )
        ) {
            Inventory__c inventoryWithShopId = [
                SELECT Id,
                Shop_ID__c
                FROM Inventory__c
                WHERE Id = :inventory.Id
            ];
            
            System.assertEquals(
                shopifyVariantId,
                inventoryWithShopId.Shop_ID__c
            );
        }
    }
    
    /*
* ============================================================
* VARIANT FOUND — UPDATE SALESFORCE AVAILABLE BY EXTERNAL KEY
* ============================================================
*/
    
    @IsTest
    static void testExecuteVariantFoundUpdatesExistingInventory() {
        String inventoryItemId =
            nextShortId('II');
        
        String shopifyLocationId =
            nextShortId('L');
        
        String shopifyVariantId =
            nextShortId('V');
        
        Product2 variant =
            createVariant(
                shopifyVariantId,
                inventoryItemId
            );
        
        Id locationId =
            createSalesforceLocation(
                shopifyLocationId
            );
        
        String inventoryKey =
            shopifyVariantId +
            '-' +
            shopifyLocationId;
        
        InventorySyncControl.skipOutbound = true;
        
        try {
            insert new Inventory__c(
                Variant__c = variant.Id,
                Location__c = locationId,
                Available__c = 2,
                Salesforce_Available__c = 2,
                Shopify_Inventory_Item_ID__c =
                inventoryItemId,
                Shopify_Location_ID__c =
                shopifyLocationId,
                Inventory_Key__c =
                inventoryKey,
                Sync_Status__c = 'Success'
            );
        } finally {
            InventorySyncControl.skipOutbound =
                false;
        }
        
        Inventory__c original =
            queryInventory(
                inventoryKey
            );
        
        configureMock();
        
        Test.startTest();
        
        new InventoryLevelRetryJob(
            inventoryItemId,
            shopifyLocationId,
            33,
            1
        ).execute(null);
        
        Test.stopTest();
        
        Inventory__c updated =
            queryInventory(
                inventoryKey
            );
        
        System.assertEquals(
            original.Id,
            updated.Id,
            'The upsert should update the existing inventory record.'
        );
        
        System.assertEquals(
            33,
            updated.Salesforce_Available__c,
            'Upsert should replace the Salesforce-side available quantity.'
        );

        System.assertEquals(
            2,
            updated.Available__c,
            'Available__c should remain unchanged because it is reserved for the Shopify snapshot.'
        );
        
        System.assertEquals(
            'Success',
            updated.Sync_Status__c
        );
        
        System.assertNotEquals(
            null,
            updated.Last_Sync_At__c
        );
        
        System.assertEquals(
            false,
            InventorySyncControl.skipOutbound
        );
    }
    
    /*
* ============================================================
* DECIMAL AND NULL QUANTITIES
* ============================================================
*/
    
    @IsTest
    static void testExecuteSupportsDecimalAvailableQuantity() {
        String inventoryItemId =
            nextShortId('II');
        
        String shopifyLocationId =
            nextShortId('L');
        
        String shopifyVariantId =
            nextShortId('V');
        
        createVariant(
            shopifyVariantId,
            inventoryItemId
        );
        
        createSalesforceLocation(
            shopifyLocationId
        );
        
        configureMock();
        
        new InventoryLevelRetryJob(
            inventoryItemId,
            shopifyLocationId,
            7.5,
            2
        ).execute(null);
        
        String inventoryKey =
            shopifyVariantId +
            '-' +
            shopifyLocationId;
        
        Inventory__c inventory =
            queryInventory(
                inventoryKey
            );
        
        System.assertEquals(
            7.5,
            inventory.Salesforce_Available__c,
            'Decimal Shopify quantities should be written to Salesforce_Available__c.'
        );

        System.assertEquals(
            null,
            inventory.Available__c,
            'Available__c should not be populated by InventoryLevelRetryJob.'
        );
    }
    
    @IsTest
    static void testExecuteSupportsNullAvailableQuantity() {
        String inventoryItemId =
            nextShortId('II');
        
        String shopifyLocationId =
            nextShortId('L');
        
        String shopifyVariantId =
            nextShortId('V');
        
        createVariant(
            shopifyVariantId,
            inventoryItemId
        );
        
        createSalesforceLocation(
            shopifyLocationId
        );
        
        configureMock();
        
        new InventoryLevelRetryJob(
            inventoryItemId,
            shopifyLocationId,
            null,
            2
        ).execute(null);
        
        String inventoryKey =
            shopifyVariantId +
            '-' +
            shopifyLocationId;
        
        Inventory__c inventory =
            queryInventory(
                inventoryKey
            );
        
        System.assertEquals(
            null,
            inventory.Salesforce_Available__c,
            'A null incoming quantity should leave Salesforce_Available__c null.'
        );

        System.assertEquals(
            null,
            inventory.Available__c,
            'Available__c should remain untouched.'
        );
    }
    
    /*
* ============================================================
* VARIANT MISSING — RETRY ENQUEUED
* ============================================================
*/
    
    @IsTest
    static void testExecuteMissingVariantBeforeMaximumAttemptSchedulesRetry() {
        String inventoryItemId =
            nextShortId('MISSING');
        
        String shopifyLocationId =
            nextShortId('L');
        
        FakeRetryScheduler fakeScheduler =
            new FakeRetryScheduler();
        
        InventoryLevelRetryJob.retryScheduler =
            fakeScheduler;
        
        try {
            new InventoryLevelRetryJob(
                inventoryItemId,
                shopifyLocationId,
                5,
                1
            ).execute(null);
            
            System.assertEquals(
                1,
                fakeScheduler.callCount,
                'One retry should be scheduled.'
            );
            
            System.assertEquals(
                inventoryItemId,
                fakeScheduler.receivedInventoryItemId
            );
            
            System.assertEquals(
                shopifyLocationId,
                fakeScheduler.receivedLocationId
            );
            
            System.assertEquals(
                5,
                fakeScheduler.receivedQuantity
            );
            
            System.assertEquals(
                2,
                fakeScheduler.receivedAttempt,
                'Attempt 1 should schedule attempt 2.'
            );
            
            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM Inventory__c
                    WHERE Shopify_Inventory_Item_ID__c =
                    :inventoryItemId
                ]
            );
        } finally {
            InventoryLevelRetryJob.retryScheduler =
                null;
        }
    }
    
    @IsTest
    static void testExecuteMissingVariantAtAttemptTwoSchedulesAttemptThree() {
        FakeRetryScheduler fakeScheduler =
            new FakeRetryScheduler();
        
        InventoryLevelRetryJob.retryScheduler =
            fakeScheduler;
        
        try {
            new InventoryLevelRetryJob(
                nextShortId('MISSING'),
                nextShortId('L'),
                8,
                2
            ).execute(null);
            
            System.assertEquals(
                1,
                fakeScheduler.callCount
            );
            
            System.assertEquals(
                3,
                fakeScheduler.receivedAttempt
            );
        } finally {
            InventoryLevelRetryJob.retryScheduler =
                null;
        }
    }
    @IsTest
    static void testExecuteMissingVariantAtAttemptTwoEnqueuesThirdAttempt() {
        String inventoryItemId =
            nextShortId('MISSING');
        
        String shopifyLocationId =
            nextShortId('L');
        
        configureMock();
        
        Integer jobsBefore =
            Limits.getQueueableJobs();
        
        new InventoryLevelRetryJob(
            inventoryItemId,
            shopifyLocationId,
            8,
            2
        ).execute(null);
        
        System.assertEquals(
            jobsBefore + 1,
            Limits.getQueueableJobs(),
            'Attempt 2 should enqueue attempt 3.'
        );
    }
    
    /*
* ============================================================
* VARIANT MISSING — FINAL FAILURE
* ============================================================
*/
    
    @IsTest
    static void testExecuteMissingVariantAtAttemptThreeStopsRetrying() {
        String inventoryItemId =
            nextShortId('MISSING');
        
        String shopifyLocationId =
            nextShortId('L');
        
        configureMock();
        
        Integer jobsBefore =
            Limits.getQueueableJobs();
        
        Test.startTest();
        
        new InventoryLevelRetryJob(
            inventoryItemId,
            shopifyLocationId,
            9,
            3
        ).execute(null);
        
        Test.stopTest();
        
        System.assertEquals(
            jobsBefore,
            Limits.getQueueableJobs(),
            'Attempt 3 should not enqueue another retry.'
        );
        
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Inventory__c
                WHERE Shopify_Inventory_Item_ID__c =
                :inventoryItemId
            ]
        );
    }
    
    @IsTest
    static void testExecuteMissingVariantAboveMaximumAttemptStopsRetrying() {
        String inventoryItemId =
            nextShortId('MISSING');
        
        String shopifyLocationId =
            nextShortId('L');
        
        Integer jobsBefore =
            Limits.getQueueableJobs();
        
        new InventoryLevelRetryJob(
            inventoryItemId,
            shopifyLocationId,
            10,
            4
        ).execute(null);
        
        System.assertEquals(
            jobsBefore,
            Limits.getQueueableJobs()
        );
    }
}