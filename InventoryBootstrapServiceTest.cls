@IsTest
private class InventoryBootstrapServiceTest {
    
    private static Product2 createVariant(String shopId, String inventoryItemId) {
        Id variantRecordTypeId;
        
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ];
        
        if (!recordTypes.isEmpty()) {
            variantRecordTypeId = recordTypes[0].Id;
        }
        
        Product2 p = new Product2(
            Name = 'Test Variant ' + String.valueOf(System.now().getTime()),
            IsActive = true,
            Shop_Id__c = shopId,
            Inventory_Item_Id__c = inventoryItemId
        );
        
        if (variantRecordTypeId != null) {
            p.RecordTypeId = variantRecordTypeId;
        }
        
        insert p;
        return p;
    }
    
    private static Id createLocation(String locationName, String shopifyLocationId) {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        
        loc.put('Name', locationName);
        
        Map<String, Schema.SObjectField> locationFields =
            Schema.getGlobalDescribe().get('Location').getDescribe().fields.getMap();
        
        if (
            locationFields.containsKey('Shopify_Location_ID__c') &&
            shopifyLocationId != null
        ) {
            loc.put('Shopify_Location_ID__c', shopifyLocationId);
        }
        
        insert loc;
        return (Id) loc.get('Id');
    }
    
    private static Id createLocation(String shopifyLocationId) {
        return createLocation(
            'Test Location ' + String.valueOf(System.now().getTime()),
            shopifyLocationId
        );
    }
    
    @IsTest
    static void testNullAndEmptyRows() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Test.startTest();
        InventoryBootstrapService.populateMappings(null);
        InventoryBootstrapService.populateMappings(new List<Inventory__c>());
        Test.stopTest();
        
        System.assert(true, 'Null and empty rows should not fail.');
    }
    
    @IsTest
    static void testPopulateMappingsWithVariantAndLocation() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 variant = createVariant('SHOP-123', 'INV-ITEM-123');
        Id locationId = createLocation('LOC-456');
        
        Inventory__c inv = new Inventory__c(
            Variant__c = variant.Id,
            Location__c = locationId
        );
        
        Test.startTest();
        InventoryBootstrapService.populateMappings(new List<Inventory__c>{ inv });
        Test.stopTest();
        
        System.assertEquals('LOC-456', inv.Shopify_Location_ID__c);
        System.assertEquals('INV-ITEM-123', inv.Shopify_Inventory_Item_ID__c);
        System.assertEquals('SHOP-123-LOC-456', inv.Inventory_Key__c);
        System.assertEquals('Success', inv.Sync_Status__c);
        
        if (Inventory__c.SObjectType.getDescribe().fields.getMap().containsKey('Shop_Id__c')) {
            System.assertEquals('SHOP-123', String.valueOf(inv.get('Shop_Id__c')));
        }
    }
    
    @IsTest
    static void testPopulateMappingsWithVariantOnly() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 variant = createVariant('SHOP-789', 'INV-ITEM-789');
        
        Inventory__c inv = new Inventory__c(
            Variant__c = variant.Id
        );
        
        Test.startTest();
        InventoryBootstrapService.populateMappings(new List<Inventory__c>{ inv });
        Test.stopTest();
        
        System.assertEquals('INV-ITEM-789', inv.Shopify_Inventory_Item_ID__c);
        System.assertEquals(null, inv.Shopify_Location_ID__c);
        System.assertEquals(null, inv.Inventory_Key__c);
        System.assertEquals('Success', inv.Sync_Status__c);
    }
    
    @IsTest
    static void testPopulateMappingsWithLocationOnly() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Id locationId = createLocation('LOC-ONLY');
        
        Inventory__c inv = new Inventory__c(
            Location__c = locationId
        );
        
        Test.startTest();
        InventoryBootstrapService.populateMappings(new List<Inventory__c>{ inv });
        Test.stopTest();
        
        System.assertEquals('LOC-ONLY', inv.Shopify_Location_ID__c);
        System.assertEquals(null, inv.Shopify_Inventory_Item_ID__c);
        System.assertEquals(null, inv.Inventory_Key__c);
        System.assertEquals('Success', inv.Sync_Status__c);
    }
    
    @IsTest
    static void testExistingSyncStatusIsNotOverwritten() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 variant = createVariant('SHOP-456', 'INV-ITEM-456');
        Id locationId = createLocation('LOC-456-EXISTING');
        
        Inventory__c inv = new Inventory__c(
            Variant__c = variant.Id,
            Location__c = locationId,
            Sync_Status__c = 'Pending'
        );
        
        Test.startTest();
        InventoryBootstrapService.populateMappings(new List<Inventory__c>{ inv });
        Test.stopTest();
        
        System.assertEquals('Pending', inv.Sync_Status__c);
        System.assertEquals('SHOP-456-LOC-456-EXISTING', inv.Inventory_Key__c);
    }
    
    @IsTest
    static void testBlankVariantFields() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 variant = new Product2(
            Name = 'Blank Variant ' + String.valueOf(System.now().getTime()),
            IsActive = true
        );
        insert variant;
        
        Id locationId = createLocation('LOC-BLANK');
        
        Inventory__c inv = new Inventory__c(
            Variant__c = variant.Id,
            Location__c = locationId
        );
        
        Test.startTest();
        InventoryBootstrapService.populateMappings(new List<Inventory__c>{ inv });
        Test.stopTest();
        
        System.assertEquals(
            'LOC-BLANK',
            inv.Shopify_Location_ID__c,
            'Shopify Location Id should still come from Location.'
        );
        
        System.assertEquals(
            null,
            inv.Shopify_Inventory_Item_ID__c,
            'Inventory Item Id should remain null because Product2.Inventory_Item_Id__c is blank.'
        );
        
        System.assertEquals(
            String.valueOf(variant.Id) + '-' + String.valueOf(locationId),
            inv.Inventory_Key__c,
            'When Product2.Shop_ID__c is blank, Inventory_Key__c should fall back to Variant__c + Location__c.'
        );
        
        System.assertEquals(
            'Success',
            inv.Sync_Status__c,
            'Sync_Status__c should default to Success.'
        );
    }
    @IsTest
    static void testFallbackInventoryKeyWhenShopifyLocationIdMissing() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 variant = createVariant('SHOP-FALLBACK', 'INV-FALLBACK');
        
        Id locationId = createLocation(
            'Location Without Shopify Id ' + String.valueOf(System.now().getTime()),
            null
        );
        
        Inventory__c inv = new Inventory__c(
            Variant__c = variant.Id,
            Location__c = locationId
        );
        
        Test.startTest();
        InventoryBootstrapService.populateMappings(new List<Inventory__c>{ inv });
        Test.stopTest();
        
        System.assertEquals(
            null,
            inv.Shopify_Location_ID__c,
            'Shopify Location Id should stay blank.'
        );
        
        System.assertEquals(
            'INV-FALLBACK',
            inv.Shopify_Inventory_Item_ID__c,
            'Inventory Item Id should still come from Product2.'
        );
        
        System.assertEquals(
            String.valueOf(variant.Id) + '-' + String.valueOf(locationId),
            inv.Inventory_Key__c,
            'Inventory_Key__c should fall back to Variant__c + Location__c.'
        );
        
        System.assertEquals('Success', inv.Sync_Status__c);
    }
    
    @IsTest
    static void testNoVariantOrLocation() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Inventory__c inv = new Inventory__c();
        
        Test.startTest();
        InventoryBootstrapService.populateMappings(new List<Inventory__c>{ inv });
        Test.stopTest();
        
        System.assertEquals('Success', inv.Sync_Status__c);
        System.assertEquals(null, inv.Shopify_Location_ID__c);
        System.assertEquals(null, inv.Shopify_Inventory_Item_ID__c);
        System.assertEquals(null, inv.Inventory_Key__c);
    }
    
    @IsTest
    static void testBulkRowsMixedData() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 variant = createVariant('SHOP-BULK', 'INV-BULK');
        Id locationId = createLocation('LOC-BULK');
        
        Inventory__c fullRow = new Inventory__c(
            Variant__c = variant.Id,
            Location__c = locationId
        );
        
        Inventory__c emptyRow = new Inventory__c();
        
        Test.startTest();
        InventoryBootstrapService.populateMappings(
            new List<Inventory__c>{ fullRow, emptyRow }
        );
        Test.stopTest();
        
        System.assertEquals('SHOP-BULK-LOC-BULK', fullRow.Inventory_Key__c);
        System.assertEquals('Success', fullRow.Sync_Status__c);
        System.assertEquals('Success', emptyRow.Sync_Status__c);
    }
    
    @IsTest
    static void testInventoryTrigger_BeforeAndAfterInsert() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 variant = createVariant('SHOP-TRG-INS', 'INV-TRG-INS');
        Id locationId = createLocation('LOC-TRIGGER-INSERT');
        
        Inventory__c inventoryRecord = new Inventory__c(
            Variant__c = variant.Id,
            Location__c = locationId
        );
        
        Test.startTest();
        insert inventoryRecord;
        Test.stopTest();
        
        Inventory__c insertedInventory = [
            SELECT Id,
            Variant__c,
            Location__c,
            Shopify_Location_ID__c,
            Shopify_Inventory_Item_ID__c,
            Inventory_Key__c,
            Sync_Status__c
            FROM Inventory__c
            WHERE Id = :inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals('LOC-TRIGGER-INSERT', insertedInventory.Shopify_Location_ID__c);
        System.assertEquals('INV-TRG-INS', insertedInventory.Shopify_Inventory_Item_ID__c);
        System.assertEquals('SHOP-TRG-INS-LOC-TRIGGER-INSERT', insertedInventory.Inventory_Key__c);
        System.assertEquals('Success', insertedInventory.Sync_Status__c);
    }
    
    @IsTest
    static void testInventoryTrigger_BeforeAndAfterUpdate() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 originalVariant = createVariant('SHOP-TRG-OLD', 'INV-TRG-OLD');
        Id originalLocationId = createLocation('LOC-TRIGGER-OLD');
        
        Product2 updatedVariant = createVariant('SHOP-TRG-UPD', 'INV-TRG-UPD');
        Id updatedLocationId = createLocation('LOC-TRIGGER-UPDATE');
        
        Inventory__c inventoryRecord = new Inventory__c(
            Variant__c = originalVariant.Id,
            Location__c = originalLocationId
        );
        insert inventoryRecord;
        
        inventoryRecord.Variant__c = updatedVariant.Id;
        inventoryRecord.Location__c = updatedLocationId;
        inventoryRecord.Sync_Status__c = null;
        
        Test.startTest();
        update inventoryRecord;
        Test.stopTest();
        
        Inventory__c updatedInventory = [
            SELECT Id,
            Variant__c,
            Location__c,
            Shopify_Location_ID__c,
            Shopify_Inventory_Item_ID__c,
            Inventory_Key__c,
            Sync_Status__c
            FROM Inventory__c
            WHERE Id = :inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals('LOC-TRIGGER-UPDATE', updatedInventory.Shopify_Location_ID__c);
        System.assertEquals('INV-TRG-UPD', updatedInventory.Shopify_Inventory_Item_ID__c);
        System.assertEquals('SHOP-TRG-UPD-LOC-TRIGGER-UPDATE', updatedInventory.Inventory_Key__c);
        System.assertEquals('Success', updatedInventory.Sync_Status__c);
    }
    
    @IsTest
    static void testInventoryTrigger_InsertWithNoVariantOrLocation() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Inventory__c inventoryRecord = new Inventory__c();
        
        Test.startTest();
        insert inventoryRecord;
        Test.stopTest();
        
        Inventory__c insertedInventory = [
            SELECT Id,
            Shopify_Location_ID__c,
            Shopify_Inventory_Item_ID__c,
            Inventory_Key__c,
            Sync_Status__c
            FROM Inventory__c
            WHERE Id = :inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(null, insertedInventory.Shopify_Location_ID__c);
        System.assertEquals(null, insertedInventory.Shopify_Inventory_Item_ID__c);
        System.assertEquals(null, insertedInventory.Inventory_Key__c);
        System.assertEquals('Success', insertedInventory.Sync_Status__c);
    }
    
    @IsTest
    static void testInventoryTrigger_UpdateWithExistingSyncStatus() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 variant = createVariant('SHOP-TRG-PEND', 'INV-TRG-PEND');
        Id locationId = createLocation('LOC-TRIGGER-PENDING');
        
        Inventory__c inventoryRecord = new Inventory__c(
            Variant__c = variant.Id,
            Location__c = locationId,
            Sync_Status__c = 'Success'
        );
        insert inventoryRecord;
        
        inventoryRecord.Sync_Status__c = 'Success';
        
        Test.startTest();
        update inventoryRecord;
        Test.stopTest();
        
        Inventory__c updatedInventory = [
            SELECT Id,
            Inventory_Key__c,
            Sync_Status__c
            FROM Inventory__c
            WHERE Id = :inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            'SHOP-TRG-PEND-LOC-TRIGGER-PENDING',
            updatedInventory.Inventory_Key__c
        );
        
        System.assertEquals('Success', updatedInventory.Sync_Status__c);
    }
}