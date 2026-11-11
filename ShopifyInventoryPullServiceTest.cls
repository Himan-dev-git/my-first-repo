@IsTest
private class ShopifyInventoryPullServiceTest {
    
    private class InventoryPullMock implements HttpCalloutMock {
        private String mode;
        
        InventoryPullMock(String mode) {
            this.mode = mode;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            String body = req.getBody();
            
            if (body != null && body.contains('productVariantsBulkUpdate')) {
                res.setBody(
                    '{"data":{"productVariantsBulkUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"productVariants":[],' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            if (body != null && body.contains('productCreate')) {
                res.setBody(
                    '{"data":{"productCreate":{' +
                    '"product":{"id":"gid://shopify/Product/123","legacyResourceId":"123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            if (body != null && body.contains('productUpdate')) {
                res.setBody(
                    '{"data":{"productUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'NULL_DATA') {
                res.setBody('{"data":null}');
                return res;
            }
            
            if (mode == 'NO_VARIANT') {
                res.setBody('{"data":{"productVariant":null}}');
                return res;
            }
            
            if (mode == 'NO_INVENTORY_ITEM') {
                res.setBody(
                    '{"data":{"productVariant":{' +
                    '"id":"gid://shopify/ProductVariant/111",' +
                    '"inventoryItem":null' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'NO_INVENTORY_LEVELS') {
                res.setBody(
                    '{"data":{"productVariant":{' +
                    '"id":"gid://shopify/ProductVariant/111",' +
                    '"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/999",' +
                    '"inventoryLevels":null' +
                    '}' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'NO_MATCHING_LOCATION') {
                res.setBody(
                    '{"data":{"productVariant":{' +
                    '"id":"gid://shopify/ProductVariant/111",' +
                    '"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/999",' +
                    '"inventoryLevels":{"nodes":[{' +
                    '"location":{"id":"gid://shopify/Location/NO_MATCH","name":"Missing Location"},' +
                    '"quantities":[{"name":"available","quantity":7}]' +
                    '}]}' +
                    '}' +
                    '}}}'
                );
                return res;
            }
            
            res.setBody(
                '{"data":{"productVariant":{' +
                '"id":"gid://shopify/ProductVariant/111",' +
                '"inventoryItem":{' +
                '"id":"gid://shopify/InventoryItem/999",' +
                '"inventoryLevels":{"nodes":[{' +
                '"location":{"id":"gid://shopify/Location/1","name":"Main Location"},' +
                '"quantities":[{"name":"available","quantity":7}]' +
                '}]}' +
                '}' +
                '}}}'
            );
            return res;
        }
    }
    
    private static void putIfCreateable(SObject row, String fieldName, Object value) {
        Map<String, Schema.SObjectField> fields =
            row.getSObjectType().getDescribe().fields.getMap();
        
        if (
            fields.containsKey(fieldName) &&
            fields.get(fieldName).getDescribe().isCreateable()
        ) {
            row.put(fieldName, value);
        }
    }
    
    private static Id getVariantRecordTypeId() {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ].Id;
    }
    
    private static Product2 createVariant(String shopId) {
        Product2 p = new Product2(
            Name = 'Test Variant ' + shopId,
            IsActive = true,
            RecordTypeId = getVariantRecordTypeId(),
            Shop_ID__c = shopId
        );
        
        putIfCreateable(p, 'Type__c', 'Variant');
        putIfCreateable(p, 'Updated_by_Integration__c', true);
        
        insert p;
        return p;
    }
    
    private static Id createShopifyLocation(String shopifyLocationId) {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        
        loc.put('Name', 'Test Location ' + shopifyLocationId);
        loc.put('LocationType', 'Warehouse');
        loc.put('Shopify_Location_ID__c', shopifyLocationId);
        
        insert loc;
        return (Id) loc.get('Id');
    }
    
    private static void assertShopifyLocationWasCreated(Id locationId, String expectedShopifyLocationId) {
        SObject loc = Database.query(
            'SELECT Id, Shopify_Location_ID__c ' +
            'FROM Location ' +
            'WHERE Id = :locationId ' +
            'LIMIT 1'
        );
        
        System.assertEquals(
            expectedShopifyLocationId,
            String.valueOf(loc.get('Shopify_Location_ID__c')),
            'Test Location must have the expected Shopify_Location_ID__c.'
        );
    }
    
    private static Decimal getInventoryAvailable(Id variantId) {
        List<Inventory__c> rows = [
            SELECT Available__c
            FROM Inventory__c
            WHERE Variant__c = :variantId
            LIMIT 1
        ];
        
        return rows.isEmpty() ? null : rows[0].Available__c;
    }
    
    @IsTest
    static void testNullAndEmptyInputs() {
        Test.startTest();
        ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(null);
        ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(new List<String>());
        Test.stopTest();
        
        System.assert(true, 'Null and empty inputs should safely return.');
    }
    
    @IsTest
    static void testNoMatchingVariant() {
        Test.setMock(HttpCalloutMock.class, new InventoryPullMock('SUCCESS'));
        
        Test.startTest();
        ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(
            new List<String>{ 'NO_MATCH_VARIANT' }
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Inventory__c],
            'No Product2 variant match should create no Inventory__c.'
        );
    }
    
    @IsTest
    static void testNullData() {
        Test.setMock(HttpCalloutMock.class, new InventoryPullMock('NULL_DATA'));
        
        Product2 variant = createVariant('10001');
        
        Test.startTest();
        ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(
            new List<String>{ variant.Shop_ID__c }
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Inventory__c WHERE Variant__c = :variant.Id],
            'Null data should not create Inventory__c.'
        );
    }
    
    @IsTest
    static void testNoInventoryItem() {
        Test.setMock(HttpCalloutMock.class, new InventoryPullMock('NO_INVENTORY_ITEM'));
        
        Product2 variant = createVariant('10002');
        
        Test.startTest();
        ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(
            new List<String>{ variant.Shop_ID__c }
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Inventory__c WHERE Variant__c = :variant.Id],
            'Missing inventoryItem should not create Inventory__c.'
        );
    }
    
    @IsTest
    static void testNoInventoryLevels() {
        Test.setMock(HttpCalloutMock.class, new InventoryPullMock('NO_INVENTORY_LEVELS'));
        
        Product2 variant = createVariant('10003');
        
        Test.startTest();
        ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(
            new List<String>{ variant.Shop_ID__c }
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Inventory__c WHERE Variant__c = :variant.Id],
            'Missing inventoryLevels should not create Inventory__c.'
        );
    }
    
    @IsTest
    static void testNoMatchingLocation() {
        Test.setMock(HttpCalloutMock.class, new InventoryPullMock('NO_MATCHING_LOCATION'));
        
        Product2 variant = createVariant('10004');
        
        Test.startTest();
        ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(
            new List<String>{ variant.Shop_ID__c }
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Inventory__c WHERE Variant__c = :variant.Id],
            'If Salesforce Location does not exist, inventory should be skipped.'
        );
    }
    
    @IsTest
    static void testSuccessCreatesInventory() {
        Test.setMock(HttpCalloutMock.class, new InventoryPullMock('SUCCESS'));
        
        Product2 variant = createVariant('10005');
        Id locationId = createShopifyLocation('1');
        
        assertShopifyLocationWasCreated(locationId, '1');
        
        Test.startTest();
        ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(
            new List<String>{ variant.Shop_ID__c }
        );
        Test.stopTest();
        
        List<Inventory__c> rows = [
            SELECT Id,
            Variant__c,
            Location__c,
            Available__c,
            Shopify_Inventory_Item_ID__c,
            Shopify_Location_ID__c,
            Inventory_Key__c
            FROM Inventory__c
            WHERE Variant__c = :variant.Id
        ];
        
        System.assertEquals(1, rows.size(), 'One inventory row should be created.');
        System.assertEquals(variant.Id, rows[0].Variant__c);
        System.assertEquals(locationId, rows[0].Location__c);
        System.assertEquals(7, rows[0].Available__c);
        System.assertEquals('999', rows[0].Shopify_Inventory_Item_ID__c);
        System.assertEquals('1', rows[0].Shopify_Location_ID__c);
        System.assertEquals(variant.Shop_ID__c + '-1', rows[0].Inventory_Key__c);
    }
    
    @IsTest
    static void testUpsertsExistingInventory() {
        Test.setMock(HttpCalloutMock.class, new InventoryPullMock('SUCCESS'));
        
        Product2 variant = createVariant('10006');
        Id locationId = createShopifyLocation('1');
        
        assertShopifyLocationWasCreated(locationId, '1');
        
        InventorySyncControl.skipOutbound = true;
        try {
            Inventory__c existingInv = new Inventory__c(
                Variant__c = variant.Id,
                Location__c = locationId,
                Available__c = 1,
                Shopify_Inventory_Item_ID__c = '999',
                Shopify_Location_ID__c = '1',
                Inventory_Key__c = variant.Shop_ID__c + '-1'
            );
            insert existingInv;
        } finally {
            InventorySyncControl.skipOutbound = false;
        }
        
        Test.startTest();
        ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(
            new List<String>{ variant.Shop_ID__c }
        );
        Test.stopTest();
        
        List<Inventory__c> rows = [
            SELECT Id, Available__c
            FROM Inventory__c
            WHERE Variant__c = :variant.Id
            AND Shopify_Location_ID__c = '1'
        ];
        
        System.assertEquals(1, rows.size(), 'Existing inventory should be updated, not duplicated.');
        System.assertEquals(7, rows[0].Available__c);
    }
}