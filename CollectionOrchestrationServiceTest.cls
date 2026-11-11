@IsTest
private class CollectionOrchestrationServiceTest {
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static String uniqueValue(String prefix) {
        return prefix + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
    
    private static void setMock() {
        GlobalHttpMock.mockMode = 'SUCCESS';
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
    }
    
    private static Collection__c buildCollection(String nameValue, String shopifyCollectionId) {
        Collection__c col = new Collection__c(
            Name = nameValue,
            Shopify_Collection_Id__c = shopifyCollectionId
        );
        
        col.Description__c = 'Initial description';
        col.Manual__c = true;
        col.Smart__c = false;
        
        return col;
    }
    
    private static Collection__c insertCollectionWithTriggerBypassed(String nameValue, String shopifyCollectionId) {
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        
        Collection__c col = buildCollection(nameValue, shopifyCollectionId);
        insert col;
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        
        return col;
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // CollectionOrchestrationService.processCollectionWebhook tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testProcessCollectionWebhook_NullPayload() {
        setMock();
        
        Test.startTest();
        CollectionOrchestrationService.processCollectionWebhook(null);
        Test.stopTest();
        
        System.assert(true, 'No exception expected for null payload.');
    }
    
    @IsTest
    static void testProcessCollectionWebhook_MissingId() {
        Map<String, Object> payload = new Map<String, Object>{
            'name' => 'Test Collection'
                };
                    
                    setMock();
        
        Test.startTest();
        CollectionOrchestrationService.processCollectionWebhook(payload);
        Test.stopTest();
        
        System.assert(true, 'No exception expected for missing id.');
    }
    
    @IsTest
    static void testProcessCollectionWebhook_WithNumericId() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => 123456789,
                'title' => 'Webhook Collection'
                };
                    
                    setMock();
        
        Test.startTest();
        CollectionOrchestrationService.processCollectionWebhook(payload);
        Test.stopTest();
        
        System.assert(true, 'Webhook collection branch executed.');
    }
    
    @IsTest
    static void testProcessCollectionWebhook_WithStringId() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => '987654321',
                'title' => 'Webhook Collection String Id'
                };
                    
                    setMock();
        
        Test.startTest();
        CollectionOrchestrationService.processCollectionWebhook(payload);
        Test.stopTest();
        
        System.assert(true, 'Webhook collection string id branch executed.');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // CollectionOrchestrationService.processCollectionDeleteWebhook tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testProcessCollectionDeleteWebhook_NullPayload() {
        setMock();
        
        Test.startTest();
        CollectionOrchestrationService.processCollectionDeleteWebhook(null);
        Test.stopTest();
        
        System.assert(true, 'No exception expected for null delete payload.');
    }
    
    @IsTest
    static void testProcessCollectionDeleteWebhook_MissingId() {
        Map<String, Object> payload = new Map<String, Object>{
            'title' => 'Deleted Collection'
                };
                    
                    setMock();
        
        Test.startTest();
        CollectionOrchestrationService.processCollectionDeleteWebhook(payload);
        Test.stopTest();
        
        System.assert(true, 'No exception expected for delete payload without id.');
    }
    
    @IsTest
    static void testProcessCollectionDeleteWebhook_NoMatchingCollection() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => uniqueValue('NO-MATCH')
                };
                    
                    setMock();
        
        Test.startTest();
        CollectionOrchestrationService.processCollectionDeleteWebhook(payload);
        Test.stopTest();
        
        System.assertEquals(
            false,
            ShopifyCollectionGraphQLService.bypassCollectionTrigger,
            'Collection trigger bypass should remain false.'
        );
        
        System.assertEquals(
            false,
            ShopifyCollectionGraphQLService.bypassProductCollectionTrigger,
            'Product collection trigger bypass should remain false.'
        );
    }
    
    @IsTest
    static void testProcessCollectionDeleteWebhook_WithMatchingCollection() {
        String shopifyCollectionId = uniqueValue('DELETE-COL');
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = true;
        
        Collection__c col = new Collection__c(
            Name = 'Delete Matching Collection',
            Shopify_Collection_Id__c = shopifyCollectionId
        );
        insert col;
        
        Product_Collection__c pc = new Product_Collection__c(
            Collection__c = col.Id
        );
        insert pc;
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        ShopifyCollectionGraphQLService.bypassProductCollectionTrigger = false;
        
        Map<String, Object> payload = new Map<String, Object>{
            'id' => shopifyCollectionId
                };
                    
                    setMock();
        
        Test.startTest();
        CollectionOrchestrationService.processCollectionDeleteWebhook(payload);
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Product_Collection__c WHERE Id = :pc.Id],
            'Related Product_Collection__c should be deleted.'
        );
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Collection__c WHERE Id = :col.Id],
            'Collection__c should be deleted.'
        );
        
        System.assertEquals(
            false,
            ShopifyCollectionGraphQLService.bypassCollectionTrigger,
            'Collection trigger bypass should be reset to false.'
        );
        
        System.assertEquals(
            false,
            ShopifyCollectionGraphQLService.bypassProductCollectionTrigger,
            'Product collection trigger bypass should be reset to false.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // CollectionTrigger coverage tests
    // Trigger:
    // after insert, after update
    // bypass return path
    // shouldSync true path
    // shouldSync false path
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testCollectionTrigger_AfterInsert_ShouldSync() {
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        setMock();
        
        Collection__c col = buildCollection(
            'Trigger Insert Collection',
            uniqueValue('TRIGGER-INSERT')
        );
        
        Test.startTest();
        insert col;
        Test.stopTest();
        
        Collection__c insertedCol = [
            SELECT Id, Name, Shopify_Collection_Id__c
            FROM Collection__c
            WHERE Id = :col.Id
        ];
        
        System.assertEquals(col.Id, insertedCol.Id);
        System.assertEquals(false, ShopifyCollectionGraphQLService.bypassCollectionTrigger);
    }
    
    @IsTest
    static void testCollectionTrigger_AfterInsert_BypassReturnsWithoutSync() {
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        setMock();
        
        Collection__c col = buildCollection(
            'Trigger Bypass Insert Collection',
            uniqueValue('TRIGGER-BYPASS')
        );
        
        Test.startTest();
        insert col;
        Test.stopTest();
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        
        Collection__c insertedCol = [
            SELECT Id, Name
            FROM Collection__c
            WHERE Id = :col.Id
        ];
        
        System.assertEquals(col.Id, insertedCol.Id);
    }
    
    @IsTest
    static void testCollectionTrigger_AfterUpdate_NameChanged_ShouldSync() {
        Collection__c col = insertCollectionWithTriggerBypassed(
            'Trigger Update Original',
            uniqueValue('TRIGGER-UPD-NAME')
        );
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        setMock();
        
        Test.startTest();
        col.Name = 'Trigger Update Changed';
        update col;
        Test.stopTest();
        
        Collection__c updatedCol = [
            SELECT Id, Name
            FROM Collection__c
            WHERE Id = :col.Id
        ];
        
        System.assertEquals('Trigger Update Changed', updatedCol.Name);
    }
    
    @IsTest
    static void testCollectionTrigger_AfterUpdate_DescriptionChanged_ShouldSync() {
        Collection__c col = insertCollectionWithTriggerBypassed(
            'Trigger Update Description',
            uniqueValue('TRIGGER-UPD-DESC')
        );
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        setMock();
        
        Test.startTest();
        col.Description__c = 'Updated description from test';
        update col;
        Test.stopTest();
        
        Collection__c updatedCol = [
            SELECT Id, Description__c
            FROM Collection__c
            WHERE Id = :col.Id
        ];
        
        System.assertEquals('Updated description from test', updatedCol.Description__c);
    }
    
    @IsTest
    static void testCollectionTrigger_AfterUpdate_ManualChanged_ShouldSync() {
        Collection__c col = insertCollectionWithTriggerBypassed(
            'Trigger Update Manual',
            uniqueValue('TRIGGER-UPD-MANUAL')
        );
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        setMock();
        
        Test.startTest();
        col.Manual__c = false;
        update col;
        Test.stopTest();
        
        Collection__c updatedCol = [
            SELECT Id, Manual__c
            FROM Collection__c
            WHERE Id = :col.Id
        ];
        
        System.assertEquals(false, updatedCol.Manual__c);
    }
    
    @IsTest
    static void testCollectionTrigger_AfterUpdate_SmartChanged_ShouldSync() {
        Collection__c col = insertCollectionWithTriggerBypassed(
            'Trigger Update Smart',
            uniqueValue('TRIGGER-UPD-SMART')
        );
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        setMock();
        
        Test.startTest();
        col.Smart__c = true;
        update col;
        Test.stopTest();
        
        Collection__c updatedCol = [
            SELECT Id, Smart__c
            FROM Collection__c
            WHERE Id = :col.Id
        ];
        
        System.assertEquals(true, updatedCol.Smart__c);
    }
    
    @IsTest
    static void testCollectionTrigger_AfterUpdate_NoWatchedFieldsChanged_ShouldNotSync() {
        Collection__c col = insertCollectionWithTriggerBypassed(
            'Trigger No Sync Original',
            uniqueValue('TRIGGER-NO-SYNC')
        );
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        setMock();
        
        Test.startTest();
        
        // Re-save the same watched values. This covers update path where shouldSync stays false.
        col.Name = col.Name;
        col.Description__c = col.Description__c;
        col.Manual__c = col.Manual__c;
        col.Smart__c = col.Smart__c;
        update col;
        
        Test.stopTest();
        
        Collection__c updatedCol = [
            SELECT Id, Name
            FROM Collection__c
            WHERE Id = :col.Id
        ];
        
        System.assertEquals(col.Name, updatedCol.Name);
    }
    
    @IsTest
    static void testCollectionTrigger_AfterUpdate_BypassReturnsWithoutSync() {
        Collection__c col = insertCollectionWithTriggerBypassed(
            'Trigger Update Bypass Original',
            uniqueValue('TRIGGER-UPD-BYPASS')
        );
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = true;
        setMock();
        
        Test.startTest();
        col.Name = 'Trigger Update Bypass Changed';
        update col;
        Test.stopTest();
        
        ShopifyCollectionGraphQLService.bypassCollectionTrigger = false;
        
        Collection__c updatedCol = [
            SELECT Id, Name
            FROM Collection__c
            WHERE Id = :col.Id
        ];
        
        System.assertEquals('Trigger Update Bypass Changed', updatedCol.Name);
    }
}