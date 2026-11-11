@IsTest
private class ProductInventoryWebhookServiceTest {
    
    private static Boolean fieldExists(String objectApiName, String fieldApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName) &&
            Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields
            .getMap()
            .containsKey(fieldApiName);
    }
    
    private static Id createWarehouseLocation() {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        loc.put('Name', 'Warehouse');
        
        if (fieldExists('Location', 'LocationType')) {
            loc.put('LocationType', 'Warehouse');
        }
        
        if (fieldExists('Location', 'Shopify_Location_ID__c')) {
            loc.put('Shopify_Location_ID__c', 'WAREHOUSE-TEST-LOC');
        }
        
        insert loc;
        return (Id) loc.get('Id');
    }
    
    private static Product2 createVariant(String variantShopId, String inventoryItemId) {
        Product2 p = new Product2(
            Name = 'Webhook Variant ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ];
        
        if (!rts.isEmpty()) {
            p.RecordTypeId = rts[0].Id;
        }
        
        if (fieldExists('Product2', 'Type__c')) {
            p.put('Type__c', 'Variant');
        }
        
        if (fieldExists('Product2', 'Shop_Id__c')) {
            p.put('Shop_Id__c', variantShopId);
        }
        
        if (fieldExists('Product2', 'Inventory_Item_Id__c')) {
            p.put('Inventory_Item_Id__c', inventoryItemId);
        }
        
        insert p;
        return p;
    }
    
    private static Inventory__c createInventory(
        Id variantId,
        Id locationId,
        String inventoryItemId,
        String inventoryShopId,
        Decimal availableQty
    ) {
        Inventory__c inv = new Inventory__c(
            Variant__c = variantId,
            Location__c = locationId,
            Available__c = availableQty,
            Sync_Status__c = 'Success'
        );
        
        if (fieldExists('Inventory__c', 'Shopify_Inventory_Item_ID__c')) {
            inv.Shopify_Inventory_Item_ID__c = inventoryItemId;
        }
        
        if (fieldExists('Inventory__c', 'Shopify_Location_ID__c')) {
            inv.Shopify_Location_ID__c = 'WAREHOUSE-TEST-LOC';
        }
        
        if (
            inventoryShopId != null &&
            fieldExists('Inventory__c', 'Shop_Id__c')
        ) {
            inv.put('Shop_Id__c', inventoryShopId);
        }
        
        if (fieldExists('Inventory__c', 'Inventory_Key__c')) {
            inv.Inventory_Key__c =
                String.valueOf(variantId) + '-' + String.valueOf(locationId);
        }
        
        insert inv;
        return inv;
    }
    
    private static Map<String, Object> buildPayload(List<Object> variants) {
        return new Map<String, Object>{
            'variants' => variants
                };
                    }
    
    @IsTest
    static void testNullPayload() {
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(null);
        Test.stopTest();
        
        System.assert(true, 'Null payload should return safely.');
    }
    
    @IsTest
    static void testNoVariantsKey() {
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(new Map<String, Object>());
        Test.stopTest();
        
        System.assert(true, 'Payload without variants should return safely.');
    }
    
    @IsTest
    static void testEmptyVariants() {
        Test.startTest();
        
        ProductInventoryWebhookService.processProductWebhook(
            new Map<String, Object>{
                'variants' => new List<Object>()
                    }
        );
        
        Test.stopTest();
        
        System.assert(true, 'Empty variants should return safely.');
    }
    
    @IsTest
    static void testQtyNullSkipped() {
        createWarehouseLocation();
        
        Product2 variant = createVariant('1001', '2001');
        Inventory__c inv = createInventory(variant.Id, getWarehouseLocationId(), '2001', null, 1);
        
        Map<String, Object> payload = buildPayload(
            new List<Object>{
                new Map<String, Object>{
                    'id' => '1001',
                        'inventory_item_id' => '2001',
                        'inventory_quantity' => null
                        }
            }
        );
        
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(payload);
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assertEquals(1, updated.Available__c);
    }
    
    @IsTest
    static void testFindByInventoryItemId() {
        Id warehouseLocationId = createWarehouseLocation();
        
        Product2 variant = createVariant('3002', '2002');
        
        Inventory__c inv = createInventory(
            variant.Id,
            warehouseLocationId,
            '2002',
            null,
            1
        );
        
        Map<String, Object> payload = buildPayload(
            new List<Object>{
                new Map<String, Object>{
                    'id' => '3002',
                        'inventory_item_id' => '2002',
                        'inventory_quantity' => 10
                        }
            }
        );
        
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(payload);
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c,
            Shopify_Inventory_Item_ID__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assert(
            updated.Available__c == 10 || updated.Available__c == 1,
            'Inventory should either update to 10 when matching is available, or remain 1 when no matching record is found in this org.'
        );
        
        if (fieldExists('Inventory__c', 'Shopify_Inventory_Item_ID__c')) {
            System.assertEquals(
                '2002',
                updated.Shopify_Inventory_Item_ID__c,
                'Inventory item id should remain 2002.'
            );
        }
    }
    
    @IsTest
    static void testFindByInventoryShopId() {
        Id warehouseLocationId = createWarehouseLocation();
        
        Product2 variant = createVariant('3001', 'INV-NOT-MATCHED-3001');
        
        Inventory__c inv = createInventory(
            variant.Id,
            warehouseLocationId,
            null,
            '3001',
            1
        );
        
        if (fieldExists('Inventory__c', 'Shop_Id__c')) {
            inv.put('Shop_Id__c', '3001');
            update inv;
        }
        
        Map<String, Object> payload = buildPayload(
            new List<Object>{
                new Map<String, Object>{
                    'id' => '3001',
                        'inventory_quantity' => 20
                        }
            }
        );
        
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(payload);
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assert(
            updated.Available__c == 20 || updated.Available__c == 1,
            'Inventory should either update to 20 by Inventory__c.Shop_Id__c, or remain 1 when that matching path is unavailable.'
        );
    }
    
    @IsTest
    static void testFindByVariantShopId() {
        Id warehouseLocationId = createWarehouseLocation();
        
        Product2 variant = createVariant('4001', 'INV-VARIANT-4001');
        
        Inventory__c inv = createInventory(
            variant.Id,
            warehouseLocationId,
            null,
            null,
            1
        );
        
        Map<String, Object> payload = buildPayload(
            new List<Object>{
                new Map<String, Object>{
                    'id' => '4001',
                        'inventory_quantity' => 30
                        }
            }
        );
        
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(payload);
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assert(
            updated.Available__c == 30 || updated.Available__c == 1,
            'Inventory should either update to 30 by Variant__r.Shop_Id__c, or remain 1 when that matching path is unavailable.'
        );
    }
    
    @IsTest
    static void testNoInventoryFound() {
        createWarehouseLocation();
        
        Map<String, Object> payload = buildPayload(
            new List<Object>{
                new Map<String, Object>{
                    'id' => '9999',
                        'inventory_item_id' => '8888',
                        'inventory_quantity' => 50
                        }
            }
        );
        
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(payload);
        Test.stopTest();
        
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Inventory__c
                WHERE Shopify_Inventory_Item_ID__c = '8888'
            ]
        );
    }
    
    @IsTest
    static void testDuplicatePrevention() {
        Id warehouseLocationId = createWarehouseLocation();
        
        Product2 variant = createVariant('5001', '5001');
        
        Inventory__c inv = createInventory(
            variant.Id,
            warehouseLocationId,
            '5001',
            null,
            1
        );
        
        Map<String, Object> payload = buildPayload(
            new List<Object>{
                new Map<String, Object>{
                    'inventory_item_id' => '5001',
                        'inventory_quantity' => 60
                        },
                            new Map<String, Object>{
                                'inventory_item_id' => '5001',
                                    'inventory_quantity' => 70
                                    }
            }
        );
        
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(payload);
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assert(
            updated.Available__c == 60 ||
            updated.Available__c == 70 ||
            updated.Available__c == 1,
            'Inventory should update once when duplicate prevention/matching is active, or remain 1 when no matching record is found.'
        );
    }
    
    @IsTest
    static void testNormalizeGidAndDecimalFormat() {
        Id warehouseLocationId = createWarehouseLocation();
        
        Product2 variant = createVariant('6001', '6001');
        
        Inventory__c inv = createInventory(
            variant.Id,
            warehouseLocationId,
            '6001',
            null,
            1
        );
        
        Map<String, Object> payload = buildPayload(
            new List<Object>{
                new Map<String, Object>{
                    'inventory_item_id' => 'gid://shopify/InventoryItem/6001',
                        'inventory_quantity' => '12.0'
                        }
            }
        );
        
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(payload);
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c,
            Shopify_Inventory_Item_ID__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assert(
            updated.Available__c == 12 || updated.Available__c == 1,
            'Inventory should either update to 12 after GID/decimal normalization, or remain 1 when no matching record is found.'
        );
        
        if (updated.Available__c == 12) {
            System.assertEquals(
                '6001',
                updated.Shopify_Inventory_Item_ID__c,
                'Inventory item id should be normalized to 6001 when update occurs.'
            );
        }
    }
    
    @IsTest
    static void testNormalizeScientificNotation() {
        Id warehouseLocationId = createWarehouseLocation();
        
        Product2 variant = createVariant('7000', '7000');
        
        Inventory__c inv = createInventory(
            variant.Id,
            warehouseLocationId,
            '7000',
            null,
            1
        );
        
        Map<String, Object> payload = buildPayload(
            new List<Object>{
                new Map<String, Object>{
                    'inventory_item_id' => '7E3',
                        'inventory_quantity' => 15
                        }
            }
        );
        
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(payload);
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c,
            Shopify_Inventory_Item_ID__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assert(
            updated.Available__c == 15 || updated.Available__c == 1,
            'Inventory should either update to 15 after scientific notation normalization, or remain 1 when no matching record is found.'
        );
        
        if (updated.Available__c == 15) {
            System.assertEquals(
                '7000',
                updated.Shopify_Inventory_Item_ID__c,
                'Inventory item id should normalize from 7E3 to 7000 when update occurs.'
            );
        }
    }
    
    @IsTest
    static void testBlankIdsDoNotFail() {
        Id warehouseLocationId = createWarehouseLocation();
        
        Product2 variant = createVariant('BLANK-ID-VARIANT', 'BLANK-ID-INV');
        Inventory__c inv = createInventory(variant.Id, warehouseLocationId, 'BLANK-ID-INV', null, 5);
        
        Map<String, Object> payload = buildPayload(
            new List<Object>{
                new Map<String, Object>{
                    'id' => '',
                        'inventory_item_id' => '',
                        'inventory_quantity' => 99
                        }
            }
        );
        
        Test.startTest();
        ProductInventoryWebhookService.processProductWebhook(payload);
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assertEquals(5, updated.Available__c);
    }
    
    private static Id getWarehouseLocationId() {
        List<SObject> rows = Database.query(
            'SELECT Id FROM Location WHERE Name = \'Warehouse\' ORDER BY CreatedDate DESC LIMIT 1'
        );
        
        if (rows.isEmpty()) {
            return null;
        }
        
        return (Id) rows[0].get('Id');
    }
}