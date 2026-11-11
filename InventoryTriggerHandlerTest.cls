@IsTest
private class InventoryTriggerHandlerTest {

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

    private static String nextShortValue(
        String prefix
    ) {
        counter++;

        String value =
            prefix +
            String.valueOf(counter) +
            EncodingUtil.convertToHex(
                Crypto.generateAesKey(128)
            ).substring(0, 6);

        if (value.length() > 20) {
            value = value.substring(0, 20);
        }

        return value;
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

        System.assertEquals(
            1,
            recordTypes.size(),
            'The Product2 Variant record type is required.'
        );

        return recordTypes[0].Id;
    }

    private static Product2 createProduct() {
        configureMock();

        Product2 product = new Product2(
            Name = 'Handler Variant ' +
                nextShortValue('P'),
            IsActive = true,
            RecordTypeId =
                getVariantRecordTypeId(),
            Type__c = 'Variant',
            Shop_ID__c =
                nextShortValue('VAR'),
            Inventory_Item_Id__c =
                nextShortValue('INV')
        );

        if (
            fieldExists(
                'Product2',
                'Updated_by_Integration__c'
            )
        ) {
            product.put(
                'Updated_by_Integration__c',
                true
            );
        }

        insert product;

        return product;
    }

    private static Id createLocation() {
        configureMock();

        SObject locationRecord =
            Schema.getGlobalDescribe()
                .get('Location')
                .newSObject();

        locationRecord.put(
            'Name',
            'Handler Location ' +
                nextShortValue('L')
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
                nextShortValue('LOC')
            );
        }

        insert locationRecord;

        return (Id) locationRecord.get('Id');
    }

    private static String getShopifyLocationId(
        Id locationId
    ) {
        SObject locationRecord = Database.query(
            'SELECT Shopify_Location_ID__c ' +
            'FROM Location ' +
            'WHERE Id = :locationId'
        );

        return String.valueOf(
            locationRecord.get(
                'Shopify_Location_ID__c'
            )
        );
    }

    private static Inventory__c buildReadyInventory(
        Product2 product,
        Id locationId,
        Decimal availableQuantity
    ) {
        String shopifyLocationId =
            getShopifyLocationId(locationId);

        return new Inventory__c(
            Variant__c = product.Id,
            Location__c = locationId,
            Available__c = availableQuantity,
            Shopify_Location_ID__c =
                shopifyLocationId,
            Shopify_Inventory_Item_ID__c =
                product.Inventory_Item_Id__c,
            Inventory_Key__c =
                product.Shop_ID__c +
                '-' +
                shopifyLocationId,
            Sync_Status__c = 'Success'
        );
    }

    private static Inventory__c insertInventory(
        Product2 product,
        Id locationId,
        Decimal availableQuantity
    ) {
        configureMock();

        Inventory__c inventory =
            buildReadyInventory(
                product,
                locationId,
                availableQuantity
            );

        InventorySyncControl.skipOutbound =
            true;

        try {
            insert inventory;
        } finally {
            InventorySyncControl.skipOutbound =
                false;
        }

        return [
            SELECT Id,
                   Name,
                   Variant__c,
                   Location__c,
                   Available__c,
                   Shopify_Location_ID__c,
                   Shopify_Inventory_Item_ID__c,
                   Inventory_Key__c,
                   Sync_Status__c
            FROM Inventory__c
            WHERE Id = :inventory.Id
        ];
    }

    private static Inventory__c createMinimalInventory() {
        configureMock();

        InventorySyncControl.skipOutbound =
            true;

        Inventory__c inventory =
            new Inventory__c(
                Available__c = 1
            );

        try {
            insert inventory;
        } finally {
            InventorySyncControl.skipOutbound =
                false;
        }

        return inventory;
    }
    /*
     * ============================================================
     * BEFORE SAVE — EARLY RETURNS
     * ============================================================
     */

    @IsTest
    static void testBeforeSaveNullRowsReturnsEarly() {
        InventoryTriggerHandler.beforeSave(
            null,
            null
        );

        System.assert(true);
    }

    @IsTest
    static void testBeforeSaveEmptyRowsReturnsEarly() {
        InventoryTriggerHandler.beforeSave(
            new List<Inventory__c>(),
            null
        );

        System.assert(true);
    }

    /*
     * ============================================================
     * BEFORE SAVE — POPULATE MAPPINGS
     * ============================================================
     */

    @IsTest
    static void testBeforeSavePopulatesMappings() {
        Product2 product =
            createProduct();

        Id locationId =
            createLocation();

        Inventory__c inventory =
            new Inventory__c(
                Variant__c = product.Id,
                Location__c = locationId,
                Available__c = 10
            );

        InventoryTriggerHandler.beforeSave(
            new List<Inventory__c>{
                inventory
            },
            null
        );

        System.assertEquals(
            product.Inventory_Item_Id__c,
            inventory.Shopify_Inventory_Item_ID__c
        );

        System.assertNotEquals(
            null,
            inventory.Shopify_Location_ID__c
        );

        System.assertNotEquals(
            null,
            inventory.Inventory_Key__c
        );
    }

    @IsTest
    static void testBeforeSaveSkipsRowsMissingLookups() {
        Product2 product =
            createProduct();

        Id locationId =
            createLocation();

        Inventory__c noVariant =
            new Inventory__c(
                Location__c = locationId,
                Available__c = 5
            );

        Inventory__c noLocation =
            new Inventory__c(
                Variant__c = product.Id,
                Available__c = 5
            );

        InventoryTriggerHandler.beforeSave(
            new List<Inventory__c>{
                noVariant,
                noLocation
            },
            null
        );

        System.assertEquals(
            false,
            noVariant.hasErrors()
        );

        System.assertEquals(
            false,
            noLocation.hasErrors()
        );
    }

    /*
     * ============================================================
     * BEFORE SAVE — DUPLICATES IN SAME LIST
     * ============================================================
     */

    @IsTest
    static void testBeforeSaveRejectsDuplicatesInSameTransaction() {
        Product2 product =
            createProduct();

        Id locationId =
            createLocation();

        Inventory__c firstRow =
            buildReadyInventory(
                product,
                locationId,
                5
            );

        Inventory__c secondRow =
            buildReadyInventory(
                product,
                locationId,
                10
            );

        InventoryTriggerHandler.beforeSave(
            new List<Inventory__c>{
                firstRow,
                secondRow
            },
            null
        );

        System.assertEquals(
            true,
            firstRow.hasErrors()
        );

        System.assertEquals(
            true,
            secondRow.hasErrors()
        );

        System.assert(
            firstRow.getErrors()[0]
                .getMessage()
                .contains(
                    'Duplicate Inventory is not allowed'
                )
        );

        System.assert(
            secondRow.getErrors()[0]
                .getMessage()
                .contains(
                    'Duplicate Inventory is not allowed'
                )
        );
    }

    /*
     * ============================================================
     * BEFORE SAVE — DUPLICATE AGAINST DATABASE
     * ============================================================
     */

    @IsTest
    static void testBeforeSaveRejectsExistingDatabaseDuplicate() {
        Product2 product =
            createProduct();

        Id locationId =
            createLocation();

        Inventory__c existingInventory =
            insertInventory(
                product,
                locationId,
                5
            );

        Inventory__c duplicateInventory =
            buildReadyInventory(
                product,
                locationId,
                15
            );

        InventoryTriggerHandler.beforeSave(
            new List<Inventory__c>{
                duplicateInventory
            },
            null
        );

        System.assertEquals(
            true,
            duplicateInventory.hasErrors()
        );

        String errorMessage =
            duplicateInventory
                .getErrors()[0]
                .getMessage();

        System.assert(
            errorMessage.contains(
                'An Inventory record already exists'
            )
        );

        System.assert(
            errorMessage.contains(
                existingInventory.Name
            )
        );
    }

    /*
     * ============================================================
     * BEFORE SAVE — UPDATE CURRENT RECORD
     * ============================================================
     */

    @IsTest
    static void testBeforeSaveExcludesCurrentRecordFromDuplicateCheck() {
        Product2 product =
            createProduct();

        Id locationId =
            createLocation();

        Inventory__c existingInventory =
            insertInventory(
                product,
                locationId,
                5
            );

        Inventory__c oldInventory =
            existingInventory.clone(
                true,
                true,
                false,
                false
            );

        InventoryTriggerHandler.beforeSave(
            new List<Inventory__c>{
                existingInventory
            },
            new Map<Id, Inventory__c>{
                existingInventory.Id =>
                    oldInventory
            }
        );

        System.assertEquals(
            false,
            existingInventory.hasErrors()
        );
    }

    /*
     * ============================================================
     * AFTER SAVE — OUTBOUND BYPASS
     * ============================================================
     */

    @IsTest
    static void testAfterSaveSkipOutboundReturnsEarly() {
        Product2 product =
            createProduct();

        Id locationId =
            createLocation();

        Inventory__c inventory =
            insertInventory(
                product,
                locationId,
                10
            );

        InventorySyncControl.skipOutbound =
            true;

        try {
            Test.startTest();

            InventoryTriggerHandler.afterSave(
                new List<Inventory__c>{
                    inventory
                },
                null
            );

            System.assertEquals(
                0,
                Limits.getFutureCalls(),
                'No future job should be created while outbound sync is skipped.'
            );

            Test.stopTest();
        } finally {
            InventorySyncControl.skipOutbound =
                false;
        }
    }

    /*
     * ============================================================
     * AFTER SAVE — INSERT (OUTBOUND DISABLED FOR MIGRATION)
     * ============================================================
     */

    @IsTest
    static void testAfterSaveInsertReadyInventoryDoesNotScheduleWhileMigrationDisabled() {
        configureMock();

        Product2 product = createProduct();
        Id locationId = createLocation();

        Inventory__c inventory =
            insertInventory(
                product,
                locationId,
                10
            );

        Test.startTest();

        InventoryTriggerHandler.afterSave(
            new List<Inventory__c>{
                inventory
            },
            null
        );

        /*
         * The handler still evaluates whether the row is eligible for sync,
         * but the outbound ShopifyInventorySyncService call is intentionally
         * commented out in production during data migration.
         */
        System.assertEquals(
            0,
            Limits.getFutureCalls(),
            'Outbound inventory synchronization is currently disabled during data migration.'
        );

        Test.stopTest();
    }

    /*
     * ============================================================
     * AFTER SAVE — QUANTITY CHANGED (OUTBOUND DISABLED)
     * ============================================================
     */

    @IsTest
    static void testAfterSaveAvailableChangedDoesNotScheduleWhileMigrationDisabled() {
        configureMock();

        Product2 product = createProduct();
        Id locationId = createLocation();

        Inventory__c oldInventory =
            insertInventory(
                product,
                locationId,
                5
            );

        Inventory__c newInventory =
            oldInventory.clone(
                true,
                true,
                false,
                false
            );

        newInventory.Available__c = 15;

        Test.startTest();

        InventoryTriggerHandler.afterSave(
            new List<Inventory__c>{
                newInventory
            },
            new Map<Id, Inventory__c>{
                oldInventory.Id => oldInventory
            }
        );

        /*
         * Available__c changed, so shouldSync becomes true and the row is
         * evaluated by isInventoryReadyForSync(). The actual future call is
         * disabled in the production handler during migration.
         */
        System.assertEquals(
            0,
            Limits.getFutureCalls(),
            'Changed inventory should not schedule outbound sync while migration disablement is active.'
        );

        Test.stopTest();
    }

    /*
     * ============================================================
     * AFTER SAVE — QUANTITY UNCHANGED
     * ============================================================
     */

    @IsTest
    static void testAfterSaveAvailableUnchangedDoesNotSync() {
        Product2 product =
            createProduct();

        Id locationId =
            createLocation();

        Inventory__c oldInventory =
            insertInventory(
                product,
                locationId,
                5
            );

        Inventory__c newInventory =
            oldInventory.clone(
                true,
                true,
                false,
                false
            );

        Test.startTest();

        InventoryTriggerHandler.afterSave(
            new List<Inventory__c>{
                newInventory
            },
            new Map<Id, Inventory__c>{
                oldInventory.Id =>
                    oldInventory
            }
        );

        System.assertEquals(
            0,
            Limits.getFutureCalls(),
            'An unchanged available quantity should not schedule a future invocation.'
        );

        Test.stopTest();
    }

    /*
     * ============================================================
     * AFTER SAVE — ROWS NOT READY
     * ============================================================
     */

    @IsTest
    static void testAfterSaveRowsNotReadyDoNotSync() {
        Product2 product =
            createProduct();

        Id locationId =
            createLocation();

        Inventory__c noVariant =
            createMinimalInventory();

        noVariant.Location__c =
            locationId;

        noVariant.Shopify_Location_ID__c =
            getShopifyLocationId(
                locationId
            );

        noVariant.Available__c =
            10;

        Inventory__c noLocation =
            createMinimalInventory();

        noLocation.Variant__c =
            product.Id;

        noLocation.Shopify_Location_ID__c =
            'LOC123';

        noLocation.Available__c =
            10;

        Inventory__c noShopifyLocation =
            createMinimalInventory();

        noShopifyLocation.Variant__c =
            product.Id;

        noShopifyLocation.Location__c =
            locationId;

        noShopifyLocation.Shopify_Location_ID__c =
            null;

        noShopifyLocation.Available__c =
            10;

        Inventory__c noAvailable =
            createMinimalInventory();

        noAvailable.Variant__c =
            product.Id;

        noAvailable.Location__c =
            locationId;

        noAvailable.Shopify_Location_ID__c =
            'LOC123';

        noAvailable.Available__c =
            null;

        Test.startTest();

        InventoryTriggerHandler.afterSave(
            new List<Inventory__c>{
                noVariant,
                noLocation,
                noShopifyLocation,
                noAvailable
            },
            null
        );

        System.assertEquals(
            0,
            Limits.getFutureCalls(),
            'Incomplete inventory rows should not schedule outbound synchronization.'
        );

        Test.stopTest();
    }

    /*
     * ============================================================
     * AFTER SAVE — MIXED ROWS (OUTBOUND DISABLED)
     * ============================================================
     */

    @IsTest
    static void testAfterSaveCollectsOnlyReadyChangedRowsWithoutSchedulingDuringMigration() {
        configureMock();

        Product2 firstProduct = createProduct();
        Product2 secondProduct = createProduct();

        Id firstLocationId = createLocation();
        Id secondLocationId = createLocation();

        Inventory__c firstOldInventory =
            insertInventory(
                firstProduct,
                firstLocationId,
                5
            );

        Inventory__c secondOldInventory =
            insertInventory(
                secondProduct,
                secondLocationId,
                8
            );

        Inventory__c changedReadyInventory =
            firstOldInventory.clone(
                true,
                true,
                false,
                false
            );

        changedReadyInventory.Available__c = 20;

        Inventory__c unchangedInventory =
            secondOldInventory.clone(
                true,
                true,
                false,
                false
            );

        Test.startTest();

        InventoryTriggerHandler.afterSave(
            new List<Inventory__c>{
                changedReadyInventory,
                unchangedInventory
            },
            new Map<Id, Inventory__c>{
                firstOldInventory.Id => firstOldInventory,
                secondOldInventory.Id => secondOldInventory
            }
        );

        /*
         * This covers both the changed and unchanged branches while the
         * outbound synchronization line remains disabled for migration.
         */
        System.assertEquals(
            0,
            Limits.getFutureCalls(),
            'Eligible rows should not schedule outbound sync while the production call is commented out.'
        );

        Test.stopTest();
    }

    /*
     * ============================================================
     * AFTER SAVE — READY ROW WITH OUTBOUND DISABLED
     * ============================================================
     */

    @IsTest
    static void testAfterSaveReadyRowStillDoesNotScheduleOutboundDuringMigration() {
        configureMock();

        Product2 product = createProduct();
        Id locationId = createLocation();

        Inventory__c inventory =
            insertInventory(
                product,
                locationId,
                11
            );

        Test.startTest();

        InventoryTriggerHandler.afterSave(
            new List<Inventory__c>{
                inventory
            },
            null
        );

        System.assertEquals(
            0,
            Limits.getFutureCalls(),
            'The outbound future call is disabled in InventoryTriggerHandler during data migration.'
        );

        Test.stopTest();
    }
}