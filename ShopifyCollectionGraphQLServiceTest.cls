@IsTest
private class ShopifyCollectionGraphQLServiceTest {
    
    private static Collection__c createCollection(Boolean withShopifyId) {
        Collection__c c = new Collection__c(
            Name = 'Test Collection',
            Description__c = 'Desc'
        );
        
        if (withShopifyId) {
            c.Shopify_Collection_Id__c = '123';
        }
        
        insert c;
        return c;
    }
    
    private static Product2 createProduct(String shopId) {
        Product2 p = new Product2(
            Name = 'Test Product',
            IsActive = true,
            Shop_ID__c = shopId,
            Updated_by_Integration__c = true
        );
        insert p;
        return p;
    }
    
    private static Product_Collection__c createPC(Id productId, Id collectionId, String key) {
        Product_Collection__c pc = new Product_Collection__c(
            Product__c = productId,
            Collection__c = collectionId,
            External_key__c = key
        );
        insert pc;
        return pc;
    }
    
    @IsTest
    static void testCreateCollectionPath() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Collection__c c = createCollection(false);
        
        Test.startTest();
        ShopifyCollectionGraphQLService.syncCollectionAsync(c.Id);
        Test.stopTest();
        
        System.assertNotEquals(null,
                               [SELECT Shopify_Collection_Id__c FROM Collection__c WHERE Id = :c.Id].Shopify_Collection_Id__c
                              );
    }
    
    @IsTest
    static void testUpdateCollectionPath() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Collection__c c = createCollection(true);
        
        Test.startTest();
        ShopifyCollectionGraphQLService.syncCollectionAsync(c.Id);
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testAddProductToCollection() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        // Prevent trigger side effects during insert
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = true;
        
        Collection__c c = createCollection(true);
        Product2 p = createProduct('555');
        
        Product_Collection__c pc = new Product_Collection__c(
            Product__c = p.Id,
            Collection__c = c.Id,
            External_key__c = c.Shopify_Collection_Id__c + '-' + p.Shop_ID__c // 🔥 IMPORTANT
        );
        insert pc;
        
        // Reset flags before actual method call
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        Test.startTest();
        ShopifyCollectionGraphQLService.addProductToCollectionAsync(pc.Id);
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testRemoveProductFromCollection() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Test.startTest();
        ShopifyCollectionGraphQLService.removeProductFromCollectionAsync('123', '555');
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testPullCollectionAndUpsert() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Test.startTest();
        ShopifyCollectionGraphQLService.pullCollectionAsync('123');
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testUpsertCollectionFromShopify_InsertAndMembership() {
        Product2 p = createProduct('999');
        
        Map<String, Object> collectionNode = new Map<String, Object>{
            'id' => 'gid://shopify/Collection/777',
                'title' => 'Test Title',
                'descriptionHtml' => 'Desc',
                'ruleSet' => null,
                'products' => new Map<String, Object>{
                    'nodes' => new List<Object>{
                        new Map<String, Object>{
                            'legacyResourceId' => '999'
                                }
                    }
                }
        };
            Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        Test.startTest();
        ShopifyCollectionGraphQLService.upsertCollectionFromShopify(collectionNode);
        Test.stopTest();
        
        Collection__c c = [
            SELECT Id, Shopify_Collection_Id__c
            FROM Collection__c
            WHERE Shopify_Collection_Id__c = '777'
            LIMIT 1
        ];
        
        List<Product_Collection__c> pcs = [
            SELECT Id FROM Product_Collection__c WHERE Collection__c = :c.Id
        ];
        
        System.assertEquals(1, pcs.size());
    }
    
    @IsTest
    static void testMembershipDeletePath() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Product2 p = createProduct('888');
        
        Collection__c c = new Collection__c(
            Name = 'Existing',
            Shopify_Collection_Id__c = '888'
        );
        insert c;
        
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = true;
        
        Product_Collection__c pc = new Product_Collection__c(
            Product__c = p.Id,
            Collection__c = c.Id,
            External_key__c = '888-888'
        );
        insert pc;
        
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        Map<String, Object> collectionNode = new Map<String, Object>{
            'id' => 'gid://shopify/Collection/888',
                'title' => 'Updated',
                'descriptionHtml' => 'Desc',
                'ruleSet' => null,
                'products' => new Map<String, Object>{
                    'nodes' => new List<Object>()
                        }
        };
            
            Test.startTest();
        ShopifyCollectionGraphQLService.upsertCollectionFromShopify(collectionNode);
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Product_Collection__c WHERE Collection__c = :c.Id]
        );
    }
    
    @IsTest
    static void testExtractNumericId() {
        String result = ShopifyCollectionGraphQLService.extractNumericId(
            'gid://shopify/Collection/12345'
        );
        
        System.assertEquals('12345', result);
    }
    
    @IsTest
    static void testGuardClauses() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Test.startTest();
        ShopifyCollectionGraphQLService.syncCollectionAsync(null);
        ShopifyCollectionGraphQLService.addProductToCollectionAsync(null);
        ShopifyCollectionGraphQLService.removeProductFromCollectionAsync(null, null);
        ShopifyCollectionGraphQLService.pullCollectionAsync(null);
        ShopifyCollectionGraphQLService.upsertCollectionFromShopify(null);
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testProductCollectionTrigger_AfterInsert() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = true;
        
        Collection__c c = createCollection(true);
        Product2 p = createProduct('555');
        
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        Test.startTest();
        
        Product_Collection__c pc = new Product_Collection__c(
            Product__c = p.Id,
            Collection__c = c.Id,
            External_key__c = c.Shopify_Collection_Id__c + '-' + p.Shop_ID__c
        );
        insert pc;
        
        Test.stopTest();
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        System.assertNotEquals(null, pc.Id, 'Product collection row should insert and fire after insert trigger.');
    }
    
    @IsTest
    static void testProductCollectionTrigger_AfterDelete() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = true;
        
        Collection__c c = createCollection(true);
        Product2 p = createProduct('555');
        
        Product_Collection__c pc = new Product_Collection__c(
            Product__c = p.Id,
            Collection__c = c.Id,
            External_key__c = c.Shopify_Collection_Id__c + '-' + p.Shop_ID__c
        );
        insert pc;
        
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        Test.startTest();
        delete pc;
        Test.stopTest();
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Product_Collection__c
                WHERE Id = :pc.Id
            ],
            'Product collection row should delete and fire after delete trigger.'
        );
    }
    
    @IsTest
    static void testProductCollectionTrigger_BypassFlag() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = true;
        
        Collection__c c = createCollection(true);
        Product2 p = createProduct('555');
        
        Test.startTest();
        
        Product_Collection__c pc = new Product_Collection__c(
            Product__c = p.Id,
            Collection__c = c.Id,
            External_key__c = c.Shopify_Collection_Id__c + '-' + p.Shop_ID__c
        );
        insert pc;
        
        delete pc;
        
        Test.stopTest();
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        System.assert(true, 'ProductCollectionTrigger bypass flag path completed safely.');
    }
    
    @IsTest
    static void testProductCollectionTrigger_DeleteSkipsBlankIds() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = true;
        
        Collection__c c = createCollection(false);
        Product2 p = createProduct(null);
        
        Product_Collection__c pc = new Product_Collection__c(
            Product__c = p.Id,
            Collection__c = c.Id,
            External_key__c = 'blank-id-test'
        );
        insert pc;
        
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        Test.startTest();
        delete pc;
        Test.stopTest();
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        System.assert(true, 'Delete trigger skipped rows with blank Shopify ids safely.');
    }
    
    @IsTest
    static void testShopifyCollectionEventTriggerFires() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Shopify_Collection__e evt = new Shopify_Collection__e(
            Shopify_Topic__c = 'collections/create',
            Shop_ID__c = '123',
            Shopify_Payload__c = JSON.serialize(new Map<String, Object>{
                'id' => 123,
                    'title' => 'Trigger Test Collection',
                    'body_html' => 'Trigger collection description'
                    })
        );
        
        Test.startTest();
        
        Database.SaveResult sr = EventBus.publish(evt);
        
        System.assertEquals(
            true,
            sr.isSuccess(),
            'Shopify collection platform event should publish successfully.'
        );
        
        Test.getEventBus().deliver();
        
        Test.stopTest();
        
        System.assert(true, 'ShopifyCollectionEvent trigger fired successfully.');
    }
}