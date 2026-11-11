@IsTest
private class InventoryLevelOrchestrationServiceTest {

    private static final Id VARIANT_RECORD_TYPE_ID = '012P4000001IEqLIAW';

    private static Product2 createVariant(String inventoryItemId, String shopId) {
        Product2 p = new Product2(
            Name = 'Test Variant',
            IsActive = true,
            RecordTypeId = VARIANT_RECORD_TYPE_ID,
            Type__c = 'Variant',
            Inventory_Item_Id__c = inventoryItemId,
            Shop_Id__c = shopId
        );
        insert p;
        return p;
    }

    @IsTest
    static void testNullPayload() {
        Test.startTest();
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(null);
        Test.stopTest();

        System.assertEquals(false, InventorySyncControl.skipOutbound);
    }

    @IsTest
    static void testMissingInventoryItemId() {
        Map<String, Object> payload = new Map<String, Object>{
            'location_id' => '123',
            'available' => 5
        };

        Test.startTest();
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(payload);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Inventory__c]);
    }

    @IsTest
    static void testMissingLocationId() {
        Map<String, Object> payload = new Map<String, Object>{
            'inventory_item_id' => '999',
            'available' => 5
        };

        Test.startTest();
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(payload);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Inventory__c]);
    }

    @IsTest
    static void testNoMatchingVariant() {
        Map<String, Object> payload = new Map<String, Object>{
            'inventory_item_id' => 'NO-VARIANT',
            'location_id' => 'LOC-1',
            'available' => 10
        };

        Test.startTest();
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(payload);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Inventory__c]);
    }

    @IsTest
    static void testCreateInventoryRecord() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Product2 variant = createVariant('INV-123', 'SHOP-123');

        Map<String, Object> payload = new Map<String, Object>{
            'inventory_item_id' => 'INV-123',
            'location_id' => 'LOC-123',
            'available' => 25
        };

        Test.startTest();
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(payload);
        Test.stopTest();

        Inventory__c inv = [
            SELECT Id, Variant__c, Available__c,
                   Shopify_Inventory_Item_ID__c,
                   Shopify_Location_ID__c,
                   Inventory_Key__c,
                   Sync_Status__c,
                   Last_Sync_At__c
            FROM Inventory__c
            WHERE Inventory_Key__c = 'SHOP-123-LOC-123'
            LIMIT 1
        ];

        System.assertEquals(variant.Id, inv.Variant__c);
        System.assertEquals(25, inv.Available__c);
        System.assertEquals('INV-123', inv.Shopify_Inventory_Item_ID__c);
        System.assertEquals('LOC-123', inv.Shopify_Location_ID__c);
        System.assertEquals('SHOP-123-LOC-123', inv.Inventory_Key__c);
        System.assertEquals('Success', inv.Sync_Status__c);
        System.assertNotEquals(null, inv.Last_Sync_At__c);
        System.assertEquals(false, InventorySyncControl.skipOutbound);
    }

    @IsTest
    static void testUpdateExistingInventoryByInventoryKey() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Product2 variant = createVariant('INV-456', 'SHOP-456');

        Inventory__c existingInv = new Inventory__c(
            Variant__c = variant.Id,
            Inventory_Key__c = 'SHOP-456-LOC-456',
            Shopify_Inventory_Item_ID__c = 'INV-456',
            Shopify_Location_ID__c = 'LOC-456',
            Available__c = 1
        );
        insert existingInv;

        Map<String, Object> payload = new Map<String, Object>{
            'inventory_item_id' => 'INV-456',
            'location_id' => 'LOC-456',
            'available' => 99
        };

        Test.startTest();
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(payload);
        Test.stopTest();

        Inventory__c updatedInv = [
            SELECT Available__c, Sync_Status__c
            FROM Inventory__c
            WHERE Id = :existingInv.Id
        ];

        System.assertEquals(99, updatedInv.Available__c);
        System.assertEquals('Success', updatedInv.Sync_Status__c);
    }

    @IsTest
    static void testUpdateExistingInventoryByShopifyIds() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Product2 variant = createVariant('INV-789', 'SHOP-789');

        Inventory__c existingInv = new Inventory__c(
            Variant__c = variant.Id,
            Inventory_Key__c = 'OLD-KEY',
            Shopify_Inventory_Item_ID__c = 'INV-789',
            Shopify_Location_ID__c = 'LOC-789',
            Available__c = 2
        );
        insert existingInv;

        Map<String, Object> payload = new Map<String, Object>{
            'inventory_item_id' => 'INV-789',
            'location_id' => 'LOC-789',
            'available' => 44
        };

        Test.startTest();
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(payload);
        Test.stopTest();

        Inventory__c updatedInv = [
            SELECT Available__c, Inventory_Key__c
            FROM Inventory__c
            WHERE Id = :existingInv.Id
        ];

        System.assertEquals(44, updatedInv.Available__c);
        System.assertEquals('SHOP-789-LOC-789', updatedInv.Inventory_Key__c);
    }

    @IsTest
    static void testNormalizeGidAndDecimalValues() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Product2 variant = createVariant('12345', 'SHOP-GID');

        Map<String, Object> payload = new Map<String, Object>{
            'inventory_item_id' => 'gid://shopify/InventoryItem/12345',
            'location_id' => 'gid://shopify/Location/67890',
            'available' => '12.0'
        };

        Test.startTest();
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(payload);
        Test.stopTest();

        Inventory__c inv = [
            SELECT Variant__c, Available__c,
                   Shopify_Inventory_Item_ID__c,
                   Shopify_Location_ID__c,
                   Inventory_Key__c
            FROM Inventory__c
            WHERE Inventory_Key__c = 'SHOP-GID-67890'
            LIMIT 1
        ];

        System.assertEquals(variant.Id, inv.Variant__c);
        System.assertEquals(12, inv.Available__c);
        System.assertEquals('12345', inv.Shopify_Inventory_Item_ID__c);
        System.assertEquals('67890', inv.Shopify_Location_ID__c);
    }

    @IsTest
    static void testScientificNotationAndNullAvailable() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Product2 variant = createVariant('100000', 'SHOP-SCI');

        Map<String, Object> payload = new Map<String, Object>{
            'inventory_item_id' => '1E5',
            'location_id' => '2E5',
            'available' => null
        };

        Test.startTest();
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(payload);
        Test.stopTest();

        Inventory__c inv = [
            SELECT Variant__c, Available__c,
                   Shopify_Inventory_Item_ID__c,
                   Shopify_Location_ID__c,
                   Inventory_Key__c
            FROM Inventory__c
            WHERE Inventory_Key__c = 'SHOP-SCI-200000'
            LIMIT 1
        ];

        System.assertEquals(variant.Id, inv.Variant__c);
        System.assertEquals(0, inv.Available__c);
        System.assertEquals('100000', inv.Shopify_Inventory_Item_ID__c);
        System.assertEquals('200000', inv.Shopify_Location_ID__c);
    }
}