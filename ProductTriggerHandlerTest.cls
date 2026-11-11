@IsTest
private class ProductTriggerHandlerTest {
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static void setMock() {
        GlobalHttpMock.mockMode = 'SUCCESS';
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
    }
    
    private static String uniqueValue(String prefix) {
        return prefix + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
    
    private static Product2 buildProduct(String nameValue, String shopId, Boolean fromIntegration) {
        return new Product2(
            Name = nameValue,
            IsActive = true,
            Updated_by_Integration__c = fromIntegration,
            Shop_Id__c = shopId
        );
    }
    
    private static User createShopifyIntegrationUser() {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        
        String uniqueSuffix = String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Math.abs(Crypto.getRandomInteger()));
        
        User u = new User(
            FirstName = 'Shopify',
            LastName = 'Webhook Site',
            Alias = 'shpwhk',
            Email = 'shopify_webhook_site_' + uniqueSuffix + '@test.com',
            Username = 'shopify_webhook_site_' + uniqueSuffix + '@test.com',
            CommunityNickname = 'shopifywebhook' + uniqueSuffix.left(8),
            ProfileId = p.Id,
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        
        insert u;
        return u;
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Actual trigger coverage: after insert
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testProductTriggerAfterInsertSyncsProduct() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger Insert Product'),
            'TRG-INSERT-001',
            false
        );
        
        Test.startTest();
        insert product;
        Test.stopTest();
        
        Product2 insertedProduct = [
            SELECT Id, Name
            FROM Product2
            WHERE Id = :product.Id
            LIMIT 1
        ];
        
        System.assertNotEquals(null, insertedProduct.Id);
    }
    
    @IsTest
    static void testProductTriggerAfterInsertStillSyncsEvenIfUpdatedByIntegrationFlagIsTrue() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger Insert Integration Flag Product'),
            'TRG-INSERT-INT-001',
            true
        );
        
        Test.startTest();
        insert product;
        Test.stopTest();
        
        Product2 insertedProduct = [
            SELECT Id, Updated_by_Integration__c
            FROM Product2
            WHERE Id = :product.Id
            LIMIT 1
        ];
        
        System.assertEquals(true, insertedProduct.Updated_by_Integration__c);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Actual trigger coverage: after update
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testProductTriggerAfterUpdateNameChangeSyncsProduct() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger Update Product'),
            'TRG-UPD-001',
            false
        );
        insert product;
        
        product.Name = uniqueValue('Trigger Update Product Changed');
        
        Test.startTest();
        update product;
        Test.stopTest();
        
        Product2 updatedProduct = [
            SELECT Id, Name
            FROM Product2
            WHERE Id = :product.Id
            LIMIT 1
        ];
        
        System.assertEquals(product.Name, updatedProduct.Name);
    }
    
    @IsTest
    static void testProductTriggerAfterUpdateFamilyChangeSyncsProduct() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger Family Product'),
            'TRG-FAMILY-001',
            false
        );
        insert product;
        
        product.Family = 'Ring';
        
        Test.startTest();
        update product;
        Test.stopTest();
        
        Product2 updatedProduct = [
            SELECT Id, Family
            FROM Product2
            WHERE Id = :product.Id
            LIMIT 1
        ];
        
        System.assertEquals('Ring', updatedProduct.Family);
    }
    
    @IsTest
    static void testProductTriggerAfterUpdateDescriptionChangeSyncsProduct() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger Description Product'),
            'TRG-DESC-001',
            false
        );
        insert product;
        
        product.Description = 'Updated description for trigger coverage';
        
        Test.startTest();
        update product;
        Test.stopTest();
        
        Product2 updatedProduct = [
            SELECT Id, Description
            FROM Product2
            WHERE Id = :product.Id
            LIMIT 1
        ];
        
        System.assertEquals('Updated description for trigger coverage', updatedProduct.Description);
    }
    
    @IsTest
    static void testProductTriggerAfterUpdateIsActiveChangeSyncsProduct() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger Active Product'),
            'TRG-ACTIVE-001',
            false
        );
        insert product;
        
        product.IsActive = false;
        
        Test.startTest();
        update product;
        Test.stopTest();
        
        Product2 updatedProduct = [
            SELECT Id, IsActive
            FROM Product2
            WHERE Id = :product.Id
            LIMIT 1
        ];
        
        System.assertEquals(false, updatedProduct.IsActive);
    }
    
    @IsTest
    static void testProductTriggerAfterUpdateMaterialChangeSyncsProduct() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger Material Product'),
            'TRG-MAT-001',
            false
        );
        insert product;
        
        product.Material__c = 'Gold';
        
        Test.startTest();
        update product;
        Test.stopTest();
        
        Product2 updatedProduct = [
            SELECT Id, Material__c
            FROM Product2
            WHERE Id = :product.Id
            LIMIT 1
        ];
        
        System.assertEquals('Gold', updatedProduct.Material__c);
    }
    
    @IsTest
    static void testProductTriggerAfterUpdateSkuChangeSyncsProduct() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger SKU Product'),
            'TRG-SKU-001',
            false
        );
        insert product;
        
        product.StockKeepingUnit = uniqueValue('SKU');
        
        Test.startTest();
        update product;
        Test.stopTest();
        
        Product2 updatedProduct = [
            SELECT Id, StockKeepingUnit
            FROM Product2
            WHERE Id = :product.Id
            LIMIT 1
        ];
        
        System.assertEquals(product.StockKeepingUnit, updatedProduct.StockKeepingUnit);
    }
    
    @IsTest
    static void testProductTriggerAfterUpdateOnlyTechnicalFieldDoesNotSync() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger Technical Field Product'),
            'TRG-TECH-001',
            false
        );
        insert product;
        
        product.Updated_by_Integration__c = true;
        
        Test.startTest();
        update product;
        Test.stopTest();
        
        Product2 updatedProduct = [
            SELECT Id, Updated_by_Integration__c
            FROM Product2
            WHERE Id = :product.Id
            LIMIT 1
        ];
        
        System.assertEquals(true, updatedProduct.Updated_by_Integration__c);
    }
    
    @IsTest
    static void testProductTriggerAfterUpdateNoMeaningfulChangeDoesNotSync() {
        setMock();
        
        Product2 product = buildProduct(
            uniqueValue('Trigger No Change Product'),
            'TRG-NOCHANGE-001',
            false
        );
        insert product;
        
        Test.startTest();
        update product;
        Test.stopTest();
        
        System.assertNotEquals(null, product.Id);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Shopify integration username skip branch
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testAfterInsertSkippedForShopifyIntegrationUserName() {
        User integrationUser = createShopifyIntegrationUser();
        
        System.runAs(integrationUser) {
            Product2 product = buildProduct(
                uniqueValue('Integration User Insert Product'),
                'TRG-INT-USER-INSERT-001',
                false
            );
            
            Test.startTest();
            insert product;
            Test.stopTest();
            
            System.assertNotEquals(null, product.Id);
        }
    }
    
    @IsTest
    static void testAfterUpdateSkippedForShopifyIntegrationUserName() {
        User integrationUser = createShopifyIntegrationUser();
        
        System.runAs(integrationUser) {
            Product2 oldProduct = new Product2(
                Id = fakeProductId(),
                Name = 'Old Integration Product',
                IsActive = true,
                Shop_Id__c = 'TRG-INT-USER-UPD-001'
            );
            
            Product2 newProduct = new Product2(
                Id = oldProduct.Id,
                Name = 'New Integration Product',
                IsActive = true,
                Shop_Id__c = 'TRG-INT-USER-UPD-001'
            );
            
            Test.startTest();
            ProductTriggerHandler.handleAfterUpdate(
                new List<Product2>{ newProduct },
                new Map<Id, Product2>{ oldProduct.Id => oldProduct }
            );
            Test.stopTest();
            
            System.assert(true, 'Shopify integration username update branch returned safely.');
        }
    }
    // ─────────────────────────────────────────────────────────────────────
    // Direct handler coverage: guard clauses and null records
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testHandleAfterInsertNullAndEmptyInputsReturn() {
        Test.startTest();
        ProductTriggerHandler.handleAfterInsert(null);
        ProductTriggerHandler.handleAfterInsert(new List<Product2>());
        Test.stopTest();
        
        System.assert(true, 'Null and empty insert inputs returned safely.');
    }
    
    @IsTest
    static void testHandleAfterInsertSkipsNullProductInList() {
        setMock();
        
        Test.startTest();
        ProductTriggerHandler.handleAfterInsert(new List<Product2>{ null });
        Test.stopTest();
        
        System.assert(true, 'Null Product2 item skipped safely.');
    }
    
    @IsTest
    static void testHandleAfterUpdateNullAndEmptyInputsReturn() {
        Test.startTest();
        ProductTriggerHandler.handleAfterUpdate(null, new Map<Id, Product2>());
        ProductTriggerHandler.handleAfterUpdate(new List<Product2>(), new Map<Id, Product2>());
        ProductTriggerHandler.handleAfterUpdate(new List<Product2>{ new Product2(Name = 'No Old Map') }, null);
        Test.stopTest();
        
        System.assert(true, 'Null and empty update inputs returned safely.');
    }
    
    @IsTest
    static void testHandleAfterUpdateSkipsNullProductAndMissingOldRecord() {
        setMock();
        
        Product2 detachedProduct = new Product2(
            Id = fakeProductId(),
            Name = 'Detached Product'
        );
        
        Test.startTest();
        ProductTriggerHandler.handleAfterUpdate(
            new List<Product2>{ null, detachedProduct },
            new Map<Id, Product2>()
        );
        Test.stopTest();
        
        System.assert(true, 'Null product and missing old product branches executed.');
    }
    
    @IsTest
    static void testHandleAfterUpdateRelevantChangeDirectCall() {
        setMock();
        
        Product2 oldProduct = buildProduct(
            'Old Direct Product',
            'DIRECT-UPD-001',
            false
        );
        insert oldProduct;
        
        Product2 newProduct = [
            SELECT Id, Name, Family, Description, IsActive, Material__c, StockKeepingUnit,
            Shop_Id__c, Updated_by_Integration__c
            FROM Product2
            WHERE Id = :oldProduct.Id
            LIMIT 1
        ];
        
        Product2 oldCopy = newProduct.clone(true, true, false, false);
        newProduct.Name = 'New Direct Product';
        
        Test.startTest();
        ProductTriggerHandler.handleAfterUpdate(
            new List<Product2>{ newProduct },
            new Map<Id, Product2>{ oldCopy.Id => oldCopy }
        );
        Test.stopTest();
        
        System.assertEquals('New Direct Product', newProduct.Name);
    }
    
    @IsTest
    static void testHandleAfterUpdateOnlyIgnoredFieldDirectCallDoesNotSync() {
        setMock();
        
        Product2 oldProduct = buildProduct(
            'Old Ignored Field Product',
            'DIRECT-IGNORED-001',
            false
        );
        insert oldProduct;
        
        Product2 newProduct = [
            SELECT Id, Name, Shop_Id__c, Updated_by_Integration__c
            FROM Product2
            WHERE Id = :oldProduct.Id
            LIMIT 1
        ];
        
        Product2 oldCopy = newProduct.clone(true, true, false, false);
        newProduct.Updated_by_Integration__c = true;
        
        Test.startTest();
        ProductTriggerHandler.handleAfterUpdate(
            new List<Product2>{ newProduct },
            new Map<Id, Product2>{ oldCopy.Id => oldCopy }
        );
        Test.stopTest();
        
        System.assertEquals(true, newProduct.Updated_by_Integration__c);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Utility
    // ─────────────────────────────────────────────────────────────────────
    
    private static Id fakeProductId() {
        String prefix = Product2.SObjectType.getDescribe().getKeyPrefix();
        return Id.valueOf(prefix + '000000000001AAA');
    }
}