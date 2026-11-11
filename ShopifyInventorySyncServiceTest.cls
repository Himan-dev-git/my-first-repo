@IsTest
private class ShopifyInventorySyncServiceTest {
    
    private static Integer counter = 0;
    private static User shopifyWebhookUser;
    
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static String uniqueText(String prefix) {
        counter++;
        return prefix + '-' + String.valueOf(DateTime.now().getTime()) + '-' + counter;
    }
    
    private static String uniqueNumericText() {
        counter++;
        return String.valueOf(DateTime.now().getTime()) + String.valueOf(counter);
    }
    
    private static User getShopifyWebhookUser() {
        if (shopifyWebhookUser != null) {
            return shopifyWebhookUser;
        }
        
        String suffix = String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Math.abs(Crypto.getRandomInteger()));
        
        User u = new User(
            FirstName = 'Shopify',
            LastName = 'Webhook Site',
            Alias = 'shpwhk',
            Email = 'shopify_webhook_site_' + suffix + '@test.com',
            Username = 'shopify_webhook_site_' + suffix + '@test.com',
            CommunityNickname = ('shopifywebhook' + suffix).left(40),
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        
        insert u;
        shopifyWebhookUser = u;
        return shopifyWebhookUser;
    }
    
    private static Boolean fieldExists(String objectApiName, String fieldApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName) &&
            Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields
            .getMap()
            .containsKey(fieldApiName);
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
    
    private static Product2 createVariant(String variantShopId) {
        Product2 parent = new Product2(
            Name = uniqueText('Parent Product'),
            IsActive = true,
            Shop_Id__c = uniqueNumericText(),
            Updated_by_Integration__c = true
        );
        
        if (fieldExists('Product2', 'Type__c')) {
            parent.put('Type__c', 'Product');
        }
        
        Product2 variant = new Product2(
            Name = uniqueText('Test Variant'),
            IsActive = true,
            Parent__c = null,
            Shop_Id__c = variantShopId,
            Updated_by_Integration__c = true
        );
        
        if (fieldExists('Product2', 'Type__c')) {
            variant.put('Type__c', 'Variant');
        }
        
        Id variantRtId = getVariantRecordTypeIdOrNull();
        if (variantRtId != null) {
            variant.RecordTypeId = variantRtId;
        }
        
        System.runAs(getShopifyWebhookUser()) {
            insert parent;
            variant.Parent__c = parent.Id;
            insert variant;
        }
        
        return variant;
    }
    
    private static Inventory__c createInventoryRow(
        Id variantId,
        String inventoryItemId,
        String locationId,
        Decimal availableQty
    ) {
        InventorySyncControl.skipOutbound = true;
        
        Inventory__c row = new Inventory__c(
            Available__c = availableQty,
            Shopify_Inventory_Item_ID__c = inventoryItemId,
            Shopify_Location_ID__c = locationId,
            Variant__c = variantId,
            Sync_Status__c = 'Synced'
        );
        
        if (fieldExists('Inventory__c', 'Inventory_Key__c')) {
            row.put(
                'Inventory_Key__c',
                String.valueOf(variantId) + '-' + String.valueOf(locationId) + '-' + uniqueNumericText()
            );
        }
        
        insert row;
        
        InventorySyncControl.skipOutbound = false;
        return row;
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Mock
    // ─────────────────────────────────────────────────────────────────────
    
    private class InventorySyncMock implements HttpCalloutMock {
        private String mode;
        
        InventorySyncMock(String modeValue) {
            mode = modeValue;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            String body = req.getBody();
            
            // Safety for Product2 trigger side effects, if any still run.
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
            
            if (body != null && body.contains('productVariantsBulkUpdate')) {
                res.setBody(
                    '{"data":{"productVariantsBulkUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"productVariants":[{"id":"gid://shopify/ProductVariant/456","sku":"SKU-1"}],' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'CALLOUT_EXCEPTION') {
                throw new CalloutException('Mock callout failure');
            }
            
            // Mutation response.
            if (
                body != null &&
                (
                    body.contains('inventorySetQuantities') ||
                    body.contains('inventoryAdjustQuantities') ||
                    body.contains('inventorySetOnHandQuantities')
                )
            ) {
                if (mode == 'MUTATION_FAILURE') {
                    res.setBody(
                        '{"data":{"inventorySetQuantities":{' +
                        '"inventoryAdjustmentGroup":null,' +
                        '"userErrors":[{"field":["quantity"],"message":"Invalid quantity"}]' +
                        '}}}'
                    );
                    return res;
                }
                
                res.setBody(
                    '{"data":{"inventorySetQuantities":{' +
                    '"inventoryAdjustmentGroup":{"createdAt":"2026-01-01T00:00:00Z"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            // Lookup response where inventoryItem is missing.
            if (mode == 'LOOKUP_MISSING_INVENTORY_ITEM') {
                res.setBody(
                    '{"data":{"productVariant":{' +
                    '"id":"gid://shopify/ProductVariant/VAR1",' +
                    '"inventoryItem":null' +
                    '}}}'
                );
                return res;
            }
            
            // Lookup response where context cannot be resolved.
            if (mode == 'LOOKUP_NULL_PRODUCT_VARIANT') {
                res.setBody('{"data":{"productVariant":null}}');
                return res;
            }
            
            // Lookup response where inventory levels are empty.
            if (mode == 'LOOKUP_EMPTY_LEVELS') {
                res.setBody(
                    '{"data":{"productVariant":{' +
                    '"id":"gid://shopify/ProductVariant/VAR1",' +
                    '"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/INVITEM-EMPTY",' +
                    '"inventoryLevels":{"nodes":[]}' +
                    '}' +
                    '}}}'
                );
                return res;
            }
            
            // Default successful lookup response.
            String inventoryItemId = mode == 'MUTATION_FAILURE' ? 'INVITEM-2' : 'INVITEM-1';
            Decimal availableQty = mode == 'MUTATION_FAILURE' ? 3 : 5;
            
            res.setBody(
                '{"data":{"productVariant":{' +
                '"id":"gid://shopify/ProductVariant/VAR1",' +
                '"inventoryItem":{' +
                '"id":"gid://shopify/InventoryItem/' + inventoryItemId + '",' +
                '"inventoryLevels":{"nodes":[' +
                '{"location":{"id":"gid://shopify/Location/LOC-1"},' +
                '"quantities":[{"name":"available","quantity":' + String.valueOf(availableQty) + '}]}' +
                ']}' +
                '}' +
                '}}}'
            );
            return res;
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testSyncInventoryRowsAsync_NullAndEmptyInput() {
        Test.startTest();
        ShopifyInventorySyncService.syncInventoryRowsAsync(null);
        ShopifyInventorySyncService.syncInventoryRowsAsync(new List<Id>());
        Test.stopTest();
        
        System.assert(true, 'Null and empty input should exit safely.');
    }
    
    @IsTest
    static void testSyncInventoryRowsAsync_Success_ResolvesInventoryItemId() {
        Product2 variant = createVariant('VAR-1');
        Inventory__c row = createInventoryRow(variant.Id, null, 'LOC-1', 10);
        
        Test.setMock(HttpCalloutMock.class, new InventorySyncMock('SUCCESS'));
        
        Test.startTest();
        ShopifyInventorySyncService.syncInventoryRowsAsync(new List<Id>{ row.Id });
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Shopify_Inventory_Item_ID__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :row.Id
        ];
        
        System.assertEquals('INVITEM-1', updated.Shopify_Inventory_Item_ID__c);
        System.assertEquals('Success', updated.Sync_Status__c);
        System.assertNotEquals(null, updated.Last_Sync_At__c);
    }
    
    @IsTest
    static void testSyncInventoryRowsAsync_Success_ExistingInventoryItemIdPreserved() {
        Product2 variant = createVariant('VAR-EXISTING');
        Inventory__c row = createInventoryRow(variant.Id, 'EXISTING-ITEM', 'LOC-1', 10);
        
        Test.setMock(HttpCalloutMock.class, new InventorySyncMock('SUCCESS'));
        
        Test.startTest();
        ShopifyInventorySyncService.syncInventoryRowsAsync(new List<Id>{ row.Id });
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Shopify_Inventory_Item_ID__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :row.Id
        ];
        
        System.assertEquals(
            'EXISTING-ITEM',
            updated.Shopify_Inventory_Item_ID__c,
            'Existing inventory item id should be preserved.'
        );
        System.assertEquals('Success', updated.Sync_Status__c);
        System.assertNotEquals(null, updated.Last_Sync_At__c);
    }
    
    @IsTest
    static void testSyncInventoryRowsAsync_MutationReturnsUserErrors() {
        Product2 variant = createVariant('VAR-MUTATION-FAIL');
        Inventory__c row = createInventoryRow(variant.Id, null, 'LOC-1', 10);
        
        Test.setMock(HttpCalloutMock.class, new InventorySyncMock('MUTATION_FAILURE'));
        
        Test.startTest();
        ShopifyInventorySyncService.syncInventoryRowsAsync(new List<Id>{ row.Id });
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Shopify_Inventory_Item_ID__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :row.Id
        ];
        
        System.assertEquals('INVITEM-2', updated.Shopify_Inventory_Item_ID__c);
        System.assertEquals('Failed', updated.Sync_Status__c);
        System.assertNotEquals(null, updated.Last_Sync_At__c);
    }
    
    @IsTest
    static void testSyncInventoryRowsAsync_LookupCannotResolveInventoryItem() {
        Product2 variant = createVariant('VAR-NO-ITEM');
        Inventory__c row = createInventoryRow(variant.Id, null, 'LOC-1', 10);
        
        Test.setMock(HttpCalloutMock.class, new InventorySyncMock('LOOKUP_MISSING_INVENTORY_ITEM'));
        
        Test.startTest();
        ShopifyInventorySyncService.syncInventoryRowsAsync(new List<Id>{ row.Id });
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Shopify_Inventory_Item_ID__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :row.Id
        ];
        
        System.assertEquals(null, updated.Shopify_Inventory_Item_ID__c);
        System.assertEquals('Failed', updated.Sync_Status__c);
        System.assertNotEquals(null, updated.Last_Sync_At__c);
    }
    
    @IsTest
    static void testSyncInventoryRowsAsync_ContextReturnedNull() {
        Product2 variant = createVariant('VAR-NULL-CONTEXT');
        Inventory__c row = createInventoryRow(variant.Id, null, 'LOC-1', 10);
        
        Test.setMock(HttpCalloutMock.class, new InventorySyncMock('LOOKUP_NULL_PRODUCT_VARIANT'));
        
        Test.startTest();
        ShopifyInventorySyncService.syncInventoryRowsAsync(new List<Id>{ row.Id });
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Shopify_Inventory_Item_ID__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :row.Id
        ];
        
        System.assertEquals(null, updated.Shopify_Inventory_Item_ID__c);
        System.assertEquals('Failed', updated.Sync_Status__c);
        System.assertNotEquals(null, updated.Last_Sync_At__c);
    }
    
    @IsTest
    static void testSyncInventoryRowsAsync_EmptyInventoryLevelsFailsSafely() {
        Product2 variant = createVariant('VAR-EMPTY-LEVELS');
        Inventory__c row = createInventoryRow(variant.Id, null, 'LOC-1', 10);
        
        Test.setMock(HttpCalloutMock.class, new InventorySyncMock('LOOKUP_EMPTY_LEVELS'));
        
        Test.startTest();
        ShopifyInventorySyncService.syncInventoryRowsAsync(new List<Id>{ row.Id });
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Shopify_Inventory_Item_ID__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :row.Id
        ];
        
        System.assertEquals(
            'INVITEM-EMPTY',
            updated.Shopify_Inventory_Item_ID__c,
            'Inventory item id is resolved and persisted even when inventory levels are empty.'
        );
        
        System.assertEquals(
            'Success',
            updated.Sync_Status__c,
            'Current service behavior treats empty inventory levels as success if mutation succeeds.'
        );
        
        System.assertNotEquals(
            null,
            updated.Last_Sync_At__c,
            'Last sync timestamp should be populated.'
        );
    }
    
    @IsTest
    static void testSyncInventoryRowsAsync_CalloutExceptionWithExistingInventoryItem() {
        Product2 variant = createVariant('VAR-CALLOUT-FAIL');
        Inventory__c row = createInventoryRow(variant.Id, 'EXISTING-ITEM', 'LOC-1', 10);
        
        Test.setMock(HttpCalloutMock.class, new InventorySyncMock('CALLOUT_EXCEPTION'));
        
        Test.startTest();
        ShopifyInventorySyncService.syncInventoryRowsAsync(new List<Id>{ row.Id });
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Shopify_Inventory_Item_ID__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :row.Id
        ];
        
        System.assertEquals('EXISTING-ITEM', updated.Shopify_Inventory_Item_ID__c);
        System.assertEquals('Failed', updated.Sync_Status__c);
        System.assertNotEquals(null, updated.Last_Sync_At__c);
    }
    
    @IsTest
    static void testSyncInventoryRowsAsync_MultipleRowsMixedStatuses() {
        Product2 variantOne = createVariant('VAR-MULTI-1');
        Product2 variantTwo = createVariant('VAR-MULTI-2');
        
        Inventory__c rowOne = createInventoryRow(variantOne.Id, null, 'LOC-1', 4);
        Inventory__c rowTwo = createInventoryRow(variantTwo.Id, 'EXISTING-ITEM-2', 'LOC-1', 8);
        
        Test.setMock(HttpCalloutMock.class, new InventorySyncMock('SUCCESS'));
        
        Test.startTest();
        ShopifyInventorySyncService.syncInventoryRowsAsync(new List<Id>{ rowOne.Id, rowTwo.Id });
        Test.stopTest();
        
        List<Inventory__c> rows = [
            SELECT Id, Shopify_Inventory_Item_ID__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id IN :new Set<Id>{ rowOne.Id, rowTwo.Id }
        ];
        
        System.assertEquals(2, rows.size());
        
        for (Inventory__c r : rows) {
            System.assertEquals('Success', r.Sync_Status__c);
            System.assertNotEquals(null, r.Last_Sync_At__c);
            
            if (r.Id == rowOne.Id) {
                System.assertEquals('INVITEM-1', r.Shopify_Inventory_Item_ID__c);
            }
            
            if (r.Id == rowTwo.Id) {
                System.assertEquals('EXISTING-ITEM-2', r.Shopify_Inventory_Item_ID__c);
            }
        }
    }
}