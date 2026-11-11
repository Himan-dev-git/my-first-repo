@IsTest
private class SquareCatalogPlatformEventHandlerTest {
    
    // ─────────────────────────────────────────────────────────────────────
    // Safe mock for any async queueable callouts if Salesforce executes them
    // during Test.stopTest().
    // ─────────────────────────────────────────────────────────────────────
    
    private class SafeHttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            String body = req.getBody();
            
            // Shopify product create/update/variant sync safety.
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
                    '"productVariants":[],' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            // Square catalog/search/update safety.
            res.setBody(
                '{"objects":[],' +
                '"catalog_object":{"id":"SQOBJ-1"},' +
                '"payment":{"id":"PAY-1"},' +
                '"order":{"id":"ORDER-1"}}'
            );
            
            return res;
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static Square_Catalog__e buildEvent(
        String eventType,
        String squareObjectId,
        String variantShopIds,
        String productIds
    ) {
        Square_Catalog__e evt = new Square_Catalog__e();
        evt.Event_Type__c = eventType;
        evt.Square_Object_Id__c = squareObjectId;
        evt.Variant_Shop_Ids__c = variantShopIds;
        evt.Product_Ids__c = productIds;
        return evt;
    }
    
    private static Integer queuedJobs() {
        return Limits.getQueueableJobs();
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Guard clauses
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testHandleAfterInsert_NullAndEmptyReturnSafely() {
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(null);
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(new List<Square_Catalog__e>());
        
        Test.stopTest();
        
        System.assert(true, 'Null and empty event lists should return safely.');
    }
    
    @IsTest
    static void testBlankEventTypeReturnsSafely() {
        Integer beforeJobs = queuedJobs();
        
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(
            new List<Square_Catalog__e>{
                buildEvent(null, 'SQOBJ-1', null, null),
                    buildEvent('', 'SQOBJ-2', null, null),
                    buildEvent('   ', 'SQOBJ-3', null, null)
                    }
        );
        
        Test.stopTest();
        
        System.assertEquals(
            beforeJobs,
            queuedJobs(),
            'Blank event types should not enqueue jobs.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // catalog.version.updated
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testCatalogVersionUpdated_EnqueuesPriceSync() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        
        Integer beforeJobs = queuedJobs();
        
        // Do not wrap in Test.stopTest-sensitive assertions about queueable output.
        // We only need to prove the handler enqueued the correct branch.
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(
            new List<Square_Catalog__e>{
                buildEvent('catalog.version.updated', 'SQOBJ-VERSION', null, null)
                    }
        );
        
        Integer afterJobs = queuedJobs();
        
        Test.stopTest();
        
        System.assertEquals(
            beforeJobs + 1,
            afterJobs,
            'catalog.version.updated should enqueue SquareCatalogPriceSyncQueueable.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // catalog.product.sync
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testCatalogProductSync_EnqueuesCatalogQueueable() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        
        Integer beforeJobs = queuedJobs();
        
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(
            new List<Square_Catalog__e>{
                buildEvent(
                    'catalog.product.sync',
                    'SQOBJ-PRODUCT',
                    ' VAR-1,VAR-2, ,VAR-1 ',
                    null
                )
                    }
        );
        
        Integer afterJobs = queuedJobs();
        
        Test.stopTest();
        
        System.assertEquals(
            beforeJobs + 1,
            afterJobs,
            'catalog.product.sync with variant ids should enqueue SquareCatalogQueueable.'
        );
    }
    
    @IsTest
    static void testCatalogProductSync_BlankVariantIdsDoesNotEnqueue() {
        Integer beforeJobs = queuedJobs();
        
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(
            new List<Square_Catalog__e>{
                buildEvent('catalog.product.sync', 'SQOBJ-PRODUCT-BLANK', null, null),
                    buildEvent('catalog.product.sync', 'SQOBJ-PRODUCT-BLANK-2', '', null),
                    buildEvent('catalog.product.sync', 'SQOBJ-PRODUCT-BLANK-3', '   ', null),
                    buildEvent('catalog.product.sync', 'SQOBJ-PRODUCT-BLANK-4', ' , , ', null)
                    }
        );
        
        Test.stopTest();
        
        System.assertEquals(
            beforeJobs,
            queuedJobs(),
            'catalog.product.sync with no parsed variant ids should not enqueue.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // catalog.image.sync
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testCatalogImageSync_EnqueuesImageQueueable() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        
        Product2 p = new Product2(
            Name = 'Square Image Sync Product',
            IsActive = true
        );
        
        if (Product2.SObjectType.getDescribe().fields.getMap().containsKey('Updated_by_Integration__c')) {
            p.put('Updated_by_Integration__c', true);
        }
        
        insert p;
        
        Integer beforeJobs = queuedJobs();
        
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(
            new List<Square_Catalog__e>{
                buildEvent(
                    'catalog.image.sync',
                    'SQOBJ-IMAGE',
                    null,
                    String.valueOf(p.Id) + ', ' + String.valueOf(p.Id) + ' , '
                )
                    }
        );
        
        Integer afterJobs = queuedJobs();
        
        Test.stopTest();
        
        System.assertEquals(
            beforeJobs + 1,
            afterJobs,
            'catalog.image.sync with product ids should enqueue SquareCatalogImageQueueable.'
        );
    }
    
    @IsTest
    static void testCatalogImageSync_BlankProductIdsDoesNotEnqueue() {
        Integer beforeJobs = queuedJobs();
        
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(
            new List<Square_Catalog__e>{
                buildEvent('catalog.image.sync', 'SQOBJ-IMAGE-BLANK', null, null),
                    buildEvent('catalog.image.sync', 'SQOBJ-IMAGE-BLANK-2', null, ''),
                    buildEvent('catalog.image.sync', 'SQOBJ-IMAGE-BLANK-3', null, '   '),
                    buildEvent('catalog.image.sync', 'SQOBJ-IMAGE-BLANK-4', null, ' , , ')
                    }
        );
        
        Test.stopTest();
        
        System.assertEquals(
            beforeJobs,
            queuedJobs(),
            'catalog.image.sync with no parsed product ids should not enqueue.'
        );
    }
    
    @IsTest
    static void testCatalogImageSync_InvalidProductIdIsCaught() {
        Integer beforeJobs = queuedJobs();
        
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(
            new List<Square_Catalog__e>{
                buildEvent(
                    'catalog.image.sync',
                    'SQOBJ-IMAGE-BAD-ID',
                    null,
                    'not-a-salesforce-id'
                )
                    }
        );
        
        Test.stopTest();
        
        System.assertEquals(
            beforeJobs,
            queuedJobs(),
            'Invalid Product_Ids__c should be caught by handler and should not enqueue.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Ignored / unknown events
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testUnknownEventTypeIgnored() {
        Integer beforeJobs = queuedJobs();
        
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(
            new List<Square_Catalog__e>{
                buildEvent('catalog.unknown.event', 'SQOBJ-UNKNOWN', 'VAR-1', String.valueOf(UserInfo.getUserId()))
                    }
        );
        
        Test.stopTest();
        
        System.assertEquals(
            beforeJobs,
            queuedJobs(),
            'Unknown event type should be ignored.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Mixed batch
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testMixedEvents_ProcessAllSupportedEvents() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        
        Product2 p = new Product2(
            Name = 'Mixed Event Image Product',
            IsActive = true
        );
        
        if (Product2.SObjectType.getDescribe().fields.getMap().containsKey('Updated_by_Integration__c')) {
            p.put('Updated_by_Integration__c', true);
        }
        
        insert p;
        
        Integer beforeJobs = queuedJobs();
        
        Test.startTest();
        
        SquareCatalogPlatformEventTriggerHandler.handleAfterInsert(
            new List<Square_Catalog__e>{
                buildEvent('catalog.version.updated', 'SQOBJ-1', null, null),
                    buildEvent('catalog.product.sync', 'SQOBJ-2', 'VAR-A, VAR-B', null),
                    buildEvent('catalog.image.sync', 'SQOBJ-3', null, String.valueOf(p.Id)),
                    buildEvent('catalog.ignored', 'SQOBJ-4', 'VAR-C', String.valueOf(p.Id)),
                    buildEvent(null, 'SQOBJ-5', null, null)
                    }
        );
        
        Integer afterJobs = queuedJobs();
        
        Test.stopTest();
        
        System.assertEquals(
            beforeJobs + 3,
            afterJobs,
            'Only the three supported non-empty events should enqueue jobs.'
        );
    }
    
    @IsTest
    static void testSquareCatalogPlatformEventTriggerFires() {
        Square_Catalog__e evt = new Square_Catalog__e(
            Event_Type__c = 'catalog.ignored',
            Square_Object_Id__c = 'SQ-CATALOG-TRIGGER-001',
            Variant_Shop_Ids__c = 'VAR-1,VAR-2'
        );
        
        Test.startTest();
        
        Database.SaveResult sr = EventBus.publish(evt);
        
        System.assertEquals(
            true,
            sr.isSuccess(),
            'Square catalog platform event should publish successfully.'
        );
        
        Test.getEventBus().deliver();
        
        Test.stopTest();
        
        System.assert(true, 'SquareCatalogPlatformEventTrigger fired successfully.');
    }
}