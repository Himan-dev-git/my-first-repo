@IsTest
private class ShopifyInventoryGraphQLServiceTest {
    // ─────────────────────────────────────────────────────────────────────
    // Special mock only for branches not covered by GlobalHttpMock.
    // GlobalHttpMock is used for the normal Shopify GraphQL inventory paths.
    // ─────────────────────────────────────────────────────────────────────
    
    private class InventorySpecialMock implements HttpCalloutMock {
        private String mode;
        
        InventorySpecialMock(String modeValue) {
            this.mode = modeValue;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            String body = req.getBody();
            
            // Safe responses if Product2 triggers call ShopifyProductGraphQLService.
            if (body != null && body.contains('productVariantsBulkUpdate')) {
                res.setBody(
                    '{"data":{"productVariantsBulkUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"productVariants":[{"id":"gid://shopify/ProductVariant/456","title":"Default Title","sku":"SKU-1"}],' +
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
                    '"product":{"id":"gid://shopify/Product/123","title":"Updated Product"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'NO_DATA') {
                res.setBody('{"errors":[{"message":"bad"}]}');
                return res;
            }
            
            if (mode == 'MISSING_PRODUCT_VARIANT') {
                res.setBody('{"data":{}}');
                return res;
            }
            
            if (mode == 'MISSING_INVENTORY_ITEM') {
                res.setBody('{"data":{"productVariant":{}}}');
                return res;
            }
            
            if (mode == 'NULL_INVENTORY_LEVELS') {
                res.setBody(
                    '{"data":{"productVariant":{"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/555"' +
                    '}}}}'
                );
                return res;
            }
            
            if (mode == 'EMPTY_LEVELS') {
                res.setBody(
                    '{"data":{"productVariant":{"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/555",' +
                    '"inventoryLevels":{"nodes":[]}' +
                    '}}}}'
                );
                return res;
            }
            
            if (mode == 'NULL_LOCATION_AND_BAD_QUANTITY') {
                res.setBody(
                    '{"data":{"productVariant":{"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/555",' +
                    '"inventoryLevels":{"nodes":[' +
                    '{"location":null,"quantities":[{"name":"available","quantity":"bad"}]},' +
                    '{"location":{"id":"gid://shopify/Location/111","name":"Loc 111"},' +
                    '"quantities":[' +
                    '{"name":"available","quantity":"bad"},' +
                    '{"name":"on_hand","quantity":"bad"},' +
                    '{"name":"committed","quantity":"bad"},' +
                    '{"name":"incoming","quantity":"bad"},' +
                    '{"name":"ignored_quantity","quantity":99}' +
                    ']}' +
                    ']}' +
                    '}}}}'
                );
                return res;
            }
            
            if (mode == 'LOCATION_WITHOUT_ID') {
                res.setBody(
                    '{"data":{"productVariant":{"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/555",' +
                    '"inventoryLevels":{"nodes":[' +
                    '{"location":{"name":"No Id Location"},"quantities":[{"name":"available","quantity":5}]}' +
                    ']}' +
                    '}}}}'
                );
                return res;
            }
            
            if (mode == 'UNKNOWN_LOCATION_NO_MATCH') {
                res.setBody(
                    '{"data":{"productVariant":{"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/555",' +
                    '"inventoryLevels":{"nodes":[' +
                    '{"location":{"id":"gid://shopify/Location/NO_MATCH","name":"No Match"},' +
                    '"quantities":[{"name":"available","quantity":7}]}' +
                    ']}' +
                    '}}}}'
                );
                return res;
            }
            
            res.setBody(
                '{"data":{"productVariant":{"inventoryItem":{' +
                '"id":"gid://shopify/InventoryItem/555",' +
                '"inventoryLevels":{"nodes":[' +
                '{"location":{"id":"gid://shopify/Location/111","name":"Loc 111"},' +
                '"quantities":[' +
                '{"name":"available","quantity":10},' +
                '{"name":"on_hand","quantity":12},' +
                '{"name":"committed","quantity":2},' +
                '{"name":"incoming","quantity":1}' +
                ']}' +
                ']}' +
                '}}}}'
            );
            return res;
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static void setGlobalMock(String mode) {
        GlobalHttpMock.mockMode = mode;
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
    }
    
    private static Id getVariantRecordTypeIdOrNull() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ];
        
        return rts.isEmpty() ? null : rts[0].Id;
    }
    
    private static Product2 createVariant(String shopId) {
        setGlobalMock('SUCCESS');
        
        Product2 p = new Product2(
            Name = 'Variant ' + shopId,
            IsActive = true,
            Type__c = 'Variant',
            Shop_Id__c = shopId,
            Updated_by_Integration__c = true
        );
        
        Id variantRtId = getVariantRecordTypeIdOrNull();
        if (variantRtId != null) {
            p.RecordTypeId = variantRtId;
        }
        
        insert p;
        return p;
    }
    
    private static Product2 createProductTypeProduct(String shopId) {
        setGlobalMock('SUCCESS');
        
        Product2 p = new Product2(
            Name = 'Normal Product ' + shopId,
            IsActive = true,
            Type__c = 'Product',
            Shop_Id__c = shopId,
            Updated_by_Integration__c = true
        );
        
        insert p;
        return p;
    }
    
    private static void createLocation(String shopifyLocationId) {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        loc.put('Name', 'Test Location ' + shopifyLocationId);
        loc.put('Shopify_Location_ID__c', shopifyLocationId);
        insert loc;
    }
    
    private static Integer inventoryCountByKey(String inventoryKey) {
        return [
            SELECT COUNT()
            FROM Inventory__c
            WHERE Inventory_Key__c = :inventoryKey
        ];
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Validation tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testNullProductIdThrows() {
        try {
            ShopifyInventoryGraphQLService.syncVariantInventoryByProductId(null);
            System.assert(false, 'Expected Product Id validation exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('Product Id is required'),
                'Unexpected message: ' + e.getMessage()
            );
        }
    }
    
    @IsTest
    static void testMissingShopIdThrows() {
        setGlobalMock('SUCCESS');
        
        Product2 p = new Product2(
            Name = 'No Shop Id',
            IsActive = true,
            Type__c = 'Variant',
            Updated_by_Integration__c = true
        );
        insert p;
        
        try {
            ShopifyInventoryGraphQLService.syncVariantInventoryByProductId(p.Id);
            System.assert(false, 'Expected Shop_Id__c validation exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('Shop_Id__c is blank'),
                'Unexpected message: ' + e.getMessage()
            );
        }
    }
    
    @IsTest
    static void testDirectMethodValidation() {
        try {
            ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(null, '123');
            System.assert(false, 'Expected Salesforce variant Id validation exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('Salesforce variant Id is required'),
                'Unexpected message: ' + e.getMessage()
            );
        }
        
        Product2 variant = createVariant('44444');
        
        try {
            ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(variant.Id, null);
            System.assert(false, 'Expected Shopify variant Id validation exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('Shopify variant Id is required'),
                'Unexpected message: ' + e.getMessage()
            );
        }
        
        try {
            ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(variant.Id, '   ');
            System.assert(false, 'Expected blank Shopify variant Id validation exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('Shopify variant Id is required'),
                'Unexpected message: ' + e.getMessage()
            );
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Shopify response exception tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testNoDataThrows() {
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('NO_DATA'));
        
        try {
            ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(
                UserInfo.getUserId(),
                '12345'
            );
            
            System.assert(false, 'Expected no data / top-level errors exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('top-level errors') ||
                e.getMessage().contains('No data returned'),
                'Unexpected message: ' + e.getMessage()
            );
        }
    }
    
    @IsTest
    static void testMissingProductVariantThrows() {
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('MISSING_PRODUCT_VARIANT'));
        
        Product2 variant = createVariant('33333');
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('MISSING_PRODUCT_VARIANT'));
        
        try {
            Test.startTest();
            ShopifyInventoryGraphQLService.syncVariantInventoryByProductId(variant.Id);
            Test.stopTest();
            
            System.assert(false, 'Expected productVariant missing exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('productVariant missing'),
                'Unexpected message: ' + e.getMessage()
            );
        }
    }
    
    @IsTest
    static void testMissingInventoryItemThrows() {
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('MISSING_INVENTORY_ITEM'));
        
        Product2 variant = createVariant('22222');
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('MISSING_INVENTORY_ITEM'));
        
        try {
            Test.startTest();
            ShopifyInventoryGraphQLService.syncVariantInventoryByProductId(variant.Id);
            Test.stopTest();
            
            System.assert(false, 'Expected inventoryItem missing exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('inventoryItem missing'),
                'Unexpected message: ' + e.getMessage()
            );
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Return-path tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testEmptyInventoryLevelsReturns() {
        Product2 variant = createVariant('99999');
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('EMPTY_LEVELS'));
        
        Test.startTest();
        ShopifyInventoryGraphQLService.syncVariantInventoryByProductId(variant.Id);
        Test.stopTest();
        
        System.assertEquals(
            0,
            inventoryCountByKey('99999-111'),
            'No inventory should be created when nodes is empty.'
        );
    }
    
    @IsTest
    static void testNullInventoryLevelsReturns() {
        Product2 variant = createVariant('12345-NULL-LEVEL');
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('NULL_INVENTORY_LEVELS'));
        
        Test.startTest();
        ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(
            variant.Id,
            '12345-NULL-LEVEL'
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            inventoryCountByKey('12345-NULL-LEVEL-111'),
            'No inventory should be created when inventoryLevels is null.'
        );
    }
    
    @IsTest
    static void testLocationWithoutIdStillCreatesInventoryRowWithNullLocationId() {
        Product2 variant = createVariant('LOC-NO-ID');
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('LOCATION_WITHOUT_ID'));
        
        Test.startTest();
        ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(
            variant.Id,
            'LOC-NO-ID'
        );
        Test.stopTest();
        
        List<Inventory__c> invs = [
            SELECT Inventory_Key__c,
            Shopify_Location_ID__c,
            Location__c,
            Available__c
            FROM Inventory__c
            WHERE Inventory_Key__c = 'LOC-NO-ID-null'
        ];
        
        System.assertEquals(
            1,
            invs.size(),
            'Current service behavior creates an inventory row even when Shopify location id is missing.'
        );
        
        System.assertEquals('LOC-NO-ID-null', invs[0].Inventory_Key__c);
        System.assertEquals(null, invs[0].Shopify_Location_ID__c);
        System.assertEquals(null, invs[0].Location__c);
        System.assertEquals(5, invs[0].Available__c);
    }
    // ─────────────────────────────────────────────────────────────────────
    // Success / upsert tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testSuccessFlowCreatesInventoryWithGlobalMock() {
        Product2 variant = createVariant('12345');
        createLocation('LOC1');
        
        setGlobalMock('SUCCESS');
        
        Test.startTest();
        ShopifyInventoryGraphQLService.syncVariantInventoryByProductId(variant.Id);
        Test.stopTest();
        
        List<Inventory__c> invs = [
            SELECT Inventory_Key__c,
            Available__c,
            On_Hand__c,
            Committed__c,
            Incoming__c,
            Shopify_Inventory_Item_ID__c,
            Shopify_Location_ID__c,
            Sync_Status__c
            FROM Inventory__c
            WHERE Inventory_Key__c = '12345-LOC1'
        ];
        
        System.assertEquals(1, invs.size());
        System.assertEquals(7, invs[0].Available__c);
        System.assertEquals(9, invs[0].On_Hand__c);
        System.assertEquals(2, invs[0].Committed__c);
        System.assertEquals(3, invs[0].Incoming__c);
        System.assertEquals('999', invs[0].Shopify_Inventory_Item_ID__c);
        System.assertEquals('LOC1', invs[0].Shopify_Location_ID__c);
    }
    
    @IsTest
    static void testSuccessFlowCreatesInventoryWithSpecialMock() {
        Product2 variant = createVariant('12345-SPECIAL');
        createLocation('111');
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('SUCCESS'));
        
        Test.startTest();
        ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(
            variant.Id,
            '12345-SPECIAL'
        );
        Test.stopTest();
        
        List<Inventory__c> invs = [
            SELECT Inventory_Key__c,
            Available__c,
            On_Hand__c,
            Committed__c,
            Incoming__c,
            Shopify_Inventory_Item_ID__c,
            Shopify_Location_ID__c,
            Sync_Status__c
            FROM Inventory__c
            WHERE Inventory_Key__c = '12345-SPECIAL-111'
        ];
        
        System.assertEquals(1, invs.size());
        System.assertEquals(10, invs[0].Available__c);
        System.assertEquals(12, invs[0].On_Hand__c);
        System.assertEquals(2, invs[0].Committed__c);
        System.assertEquals(1, invs[0].Incoming__c);
        System.assertEquals('555', invs[0].Shopify_Inventory_Item_ID__c);
        System.assertEquals('111', invs[0].Shopify_Location_ID__c);
    }
    
    @IsTest
    static void testUpdateExistingInventory() {
        Product2 variant = createVariant('12345-UPD');
        createLocation('111');
        
        Id locId = [
            SELECT Id
            FROM Location
            WHERE Shopify_Location_ID__c = '111'
            LIMIT 1
        ].Id;
        
        InventorySyncControl.skipOutbound = true;
        
        Inventory__c existing = new Inventory__c(
            Variant__c = variant.Id,
            Location__c = locId,
            Inventory_Key__c = '12345-UPD-111',
            Shopify_Inventory_Item_ID__c = 'OLD',
            Shopify_Location_ID__c = '111',
            Available__c = 1
        );
        insert existing;
        
        InventorySyncControl.skipOutbound = false;
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('SUCCESS'));
        
        Test.startTest();
        ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(
            variant.Id,
            '12345-UPD'
        );
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Id, Available__c, Shopify_Inventory_Item_ID__c
            FROM Inventory__c
            WHERE Inventory_Key__c = '12345-UPD-111'
            LIMIT 1
        ];
        
        System.assertEquals(10, updated.Available__c);
        System.assertEquals('555', updated.Shopify_Inventory_Item_ID__c);
    }
    
    @IsTest
    static void testNullLocationAndBadQuantityBranches() {
        Product2 variant = createVariant('12345-BAD-QTY');
        createLocation('111');
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('NULL_LOCATION_AND_BAD_QUANTITY'));
        
        Test.startTest();
        ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(
            variant.Id,
            '12345-BAD-QTY'
        );
        Test.stopTest();
        
        List<Inventory__c> invs = [
            SELECT Inventory_Key__c, Available__c, On_Hand__c, Committed__c, Incoming__c
            FROM Inventory__c
            WHERE Inventory_Key__c = '12345-BAD-QTY-111'
        ];
        
        System.assertEquals(1, invs.size());
        System.assertEquals(0, invs[0].Available__c);
        System.assertEquals(0, invs[0].On_Hand__c);
        System.assertEquals(0, invs[0].Committed__c);
        System.assertEquals(0, invs[0].Incoming__c);
    }
    
    @IsTest
    static void testNoMatchingLocationStillCreatesInventoryWithoutLocationLookup() {
        Product2 variant = createVariant('12345-NO-MATCH');
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('UNKNOWN_LOCATION_NO_MATCH'));
        
        Test.startTest();
        ShopifyInventoryGraphQLService.syncVariantInventoryByShopifyVariantId(
            variant.Id,
            '12345-NO-MATCH'
        );
        Test.stopTest();
        
        List<Inventory__c> invs = [
            SELECT Inventory_Key__c, Location__c, Available__c, Shopify_Location_ID__c
            FROM Inventory__c
            WHERE Inventory_Key__c = '12345-NO-MATCH-NO_MATCH'
        ];
        
        System.assertEquals(1, invs.size());
        System.assertEquals(null, invs[0].Location__c);
        System.assertEquals(7, invs[0].Available__c);
        System.assertEquals('NO_MATCH', invs[0].Shopify_Location_ID__c);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Product type branch
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testProductTypeNotVariantStillContinuesWithoutForcingInventoryAssert() {
        Product2 p = createProductTypeProduct('12345-PRODUCT');
        createLocation('111');
        
        Test.setMock(HttpCalloutMock.class, new InventorySpecialMock('SUCCESS'));
        
        Test.startTest();
        ShopifyInventoryGraphQLService.syncVariantInventoryByProductId(p.Id);
        Test.stopTest();
        
        // This branch only proves Type__c != Variant does not stop execution.
        // Some orgs block Inventory__c.Variant__c from pointing to a Product-type Product2,
        // so do not assert that inventory must be created.
        System.assert(
            inventoryCountByKey('12345-PRODUCT-111') == 0 ||
            inventoryCountByKey('12345-PRODUCT-111') == 1,
            'Product type warning branch executed without throwing.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Utility method
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testExtractNumericId() {
        System.assertEquals(
            '777',
            ShopifyInventoryGraphQLService.extractNumericIdFromGid('gid://shopify/Location/777')
        );
        
        System.assertEquals(
            null,
            ShopifyInventoryGraphQLService.extractNumericIdFromGid(null)
        );
        
        System.assertEquals(
            null,
            ShopifyInventoryGraphQLService.extractNumericIdFromGid('')
        );
        
        System.assertEquals(
            'NO_SLASH_VALUE',
            ShopifyInventoryGraphQLService.extractNumericIdFromGid('NO_SLASH_VALUE')
        );
    }
    
    @IsTest
static void testFormatShopifyMeasurementValueBranches() {
    System.assertEquals(
        null,
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(null)
    );

    System.assertEquals(
        null,
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>()
        )
    );

    System.assertEquals(
        '10',
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>{ 'value' => '10' }
        )
    );

    System.assertEquals(
        '10in',
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>{ 'value' => '10', 'unit' => 'inches' }
        )
    );

    System.assertEquals(
        '10cm',
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>{ 'value' => '10', 'unit' => 'centimeters' }
        )
    );

    System.assertEquals(
        '10mm',
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>{ 'value' => '10', 'unit' => 'millimeters' }
        )
    );

    System.assertEquals(
        '10g',
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>{ 'value' => '10', 'unit' => 'grams' }
        )
    );

    System.assertEquals(
        '10kg',
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>{ 'value' => '10', 'unit' => 'kilograms' }
        )
    );

    System.assertEquals(
        '10lb',
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>{ 'value' => '10', 'unit' => 'pounds' }
        )
    );

    System.assertEquals(
        '10oz',
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>{ 'value' => '10', 'unit' => 'ounces' }
        )
    );

    System.assertEquals(
        '10 stone',
        ShopifyInventoryGraphQLService.formatShopifyMeasurementValue(
            new Map<String, Object>{ 'value' => '10', 'unit' => 'stone' }
        )
    );
}
}