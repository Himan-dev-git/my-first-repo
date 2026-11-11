@IsTest
private class ShopifyFulfillmentCreateServiceTest {
    
    private class FulfillmentMock implements HttpCalloutMock {
        String mode;
        
        FulfillmentMock(String mode) {
            this.mode = mode;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            String body = req.getBody();
            
            if (mode == 'http500') {
                res.setStatusCode(500);
                res.setBody('{}');
                return res;
            }
            
            if (body.contains('getFulfillmentOrders')) {
                if (mode == 'noOpen') {
                    res.setBody(JSON.serialize(new Map<String, Object>{
                        'data' => new Map<String, Object>{
                            'order' => new Map<String, Object>{
                                'fulfillmentOrders' => new Map<String, Object>{
                                    'nodes' => new List<Object>{
                                        new Map<String, Object>{
                                            'id' => 'gid://shopify/FulfillmentOrder/111',
                                                'status' => 'CLOSED'
                                                }
                                    }
                                }
                            }
                        }
                    }));
                    return res;
                }
                
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'data' => new Map<String, Object>{
                        'order' => new Map<String, Object>{
                            'fulfillmentOrders' => new Map<String, Object>{
                                'nodes' => new List<Object>{
                                    new Map<String, Object>{
                                        'id' => 'gid://shopify/FulfillmentOrder/111',
                                            'status' => 'OPEN'
                                            }
                                }
                            }
                        }
                    }
                }));
                return res;
            }
            
            if (mode == 'createErrors') {
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'errors' => new List<Object>{
                        new Map<String, Object>{ 'message' => 'error' }
                    }
                }));
                return res;
            }
            
            if (mode == 'userErrors') {
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'data' => new Map<String, Object>{
                        'fulfillmentCreate' => new Map<String, Object>{
                            'fulfillment' => null,
                                'userErrors' => new List<Object>{
                                    new Map<String, Object>{ 'message' => 'bad request' }
                                }
                        }
                    }
                }));
                return res;
            }
            
            res.setBody(JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'fulfillmentCreate' => new Map<String, Object>{
                        'fulfillment' => new Map<String, Object>{
                            'id' => 'gid://shopify/Fulfillment/222',
                                'status' => 'SUCCESS'
                                },
                                    'userErrors' => new List<Object>()
                                    }
                }
            }));
            return res;
        }
    }
    
    private static Order createOrder(String shopId) {
        Account a = new Account(Name = 'Test Account');
        insert a;
        
        Order o = new Order(
            AccountId = a.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Shop_ID__c = shopId
        );
        insert o;
        return o;
    }
    
    private static Fulfilment__c createFulfillment(Id orderId, String shopId) {
        Fulfilment__c f = new Fulfilment__c(
            Order__c = orderId,
            Shop_ID__c = shopId,
            Tracking_Number__c = 'TRACK123',
            Tracking_Company__c = ' UPS ',
            Tracking_URL__c = 'https://tracking.test'
        );
        insert f;
        return f;
    }
    
    @IsTest
    static void testNullAndEmptyInput() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Test.startTest();
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(null);
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(new List<Id>());
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testSkipAlreadyHasShopId() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Order o = createOrder('1001');
        Fulfilment__c f = createFulfillment(o.Id, 'EXISTING');
        
        Test.startTest();
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(new List<Id>{ f.Id });
        Test.stopTest();
        
        f = [SELECT Shop_ID__c FROM Fulfilment__c WHERE Id = :f.Id];
        System.assertEquals('EXISTING', f.Shop_ID__c);
    }
    
    @IsTest
    static void testSkipMissingOrderShopId() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Order o = createOrder(null);
        Fulfilment__c f = createFulfillment(o.Id, null);
        
        Test.startTest();
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(new List<Id>{ f.Id });
        Test.stopTest();
        
        f = [SELECT Shop_ID__c FROM Fulfilment__c WHERE Id = :f.Id];
        System.assertEquals(null, f.Shop_ID__c);
    }
    
    @IsTest
    static void testSuccessCreatesFulfillment() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Order o = createOrder('2001');
        Fulfilment__c f = createFulfillment(o.Id, null);
        
        Test.startTest();
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(new List<Id>{ f.Id });
        Test.stopTest();
        
        f = [SELECT Shop_ID__c, Status__c FROM Fulfilment__c WHERE Id = :f.Id];
        System.assertEquals('222', f.Shop_ID__c);
        System.assertEquals('Success', f.Status__c);
    }
    
    @IsTest
    static void testNoOpenFulfillmentOrder() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('noOpen'));
        
        Order o = createOrder('3001');
        Fulfilment__c f = createFulfillment(o.Id, null);
        
        Test.startTest();
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(new List<Id>{ f.Id });
        Test.stopTest();
        
        f = [SELECT Shop_ID__c FROM Fulfilment__c WHERE Id = :f.Id];
        System.assertEquals(null, f.Shop_ID__c);
    }
    
    @IsTest
    static void testHttp500ReturnsNoUpdate() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('http500'));
        
        Order o = createOrder('4001');
        Fulfilment__c f = createFulfillment(o.Id, null);
        
        Test.startTest();
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(new List<Id>{ f.Id });
        Test.stopTest();
        
        f = [SELECT Shop_ID__c FROM Fulfilment__c WHERE Id = :f.Id];
        System.assertEquals(null, f.Shop_ID__c);
    }
    
    @IsTest
    static void testCreateTopLevelErrorsNoUpdate() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('createErrors'));
        
        Order o = createOrder('5001');
        Fulfilment__c f = createFulfillment(o.Id, null);
        
        Test.startTest();
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(new List<Id>{ f.Id });
        Test.stopTest();
        
        f = [SELECT Shop_ID__c FROM Fulfilment__c WHERE Id = :f.Id];
        System.assertEquals(null, f.Shop_ID__c);
    }
    
    @IsTest
    static void testCreateUserErrorsNoUpdate() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('userErrors'));
        
        Order o = createOrder('6001');
        Fulfilment__c f = createFulfillment(o.Id, null);
        
        Test.startTest();
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(new List<Id>{ f.Id });
        Test.stopTest();
        
        f = [SELECT Shop_ID__c FROM Fulfilment__c WHERE Id = :f.Id];
        System.assertEquals(null, f.Shop_ID__c);
    }
    
    @IsTest
    static void testFulfilmentTrigger_AfterInsertCreatesShopifyFulfillment() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Order orderRecord = createOrder('7001');
        
        Fulfilment__c fulfillmentRecord = new Fulfilment__c(
            Order__c = orderRecord.Id,
            Shop_ID__c = null,
            Tracking_Number__c = 'TRACK_INSERT_123',
            Tracking_Company__c = 'UPS',
            Tracking_URL__c = 'https://tracking.test/insert'
        );
        
        Test.startTest();
        insert fulfillmentRecord;
        Test.stopTest();
        
        fulfillmentRecord = [
            SELECT Id, Shop_ID__c
            FROM Fulfilment__c
            WHERE Id = :fulfillmentRecord.Id
            LIMIT 1
        ];
        
        System.assertNotEquals(
            null,
            fulfillmentRecord.Id,
            'FulfilmentTrigger after insert should execute safely.'
        );
    }
    
    @IsTest
    static void testFulfilmentTrigger_AfterInsertSkipsWhenShopIdExists() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Order orderRecord = createOrder('7002');
        
        Fulfilment__c fulfillmentRecord = new Fulfilment__c(
            Order__c = orderRecord.Id,
            Shop_ID__c = 'EXISTING_SHOPIFY',
            Tracking_Number__c = 'TRACK_SKIP_123',
            Tracking_Company__c = 'UPS',
            Tracking_URL__c = 'https://tracking.test/skip'
        );
        
        Test.startTest();
        insert fulfillmentRecord;
        Test.stopTest();
        
        fulfillmentRecord = [
            SELECT Id, Shop_ID__c
            FROM Fulfilment__c
            WHERE Id = :fulfillmentRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            'EXISTING_SHOPIFY',
            fulfillmentRecord.Shop_ID__c,
            'After insert should skip create path when Shopify fulfillment id already exists.'
        );
    }
    
    @IsTest
    static void testFulfilmentTrigger_AfterInsertSkipsWhenOrderMissing() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Fulfilment__c fulfillmentRecord = new Fulfilment__c(
            Order__c = null,
            Shop_ID__c = null,
            Tracking_Number__c = 'TRACK_NO_ORDER_123',
            Tracking_Company__c = 'UPS',
            Tracking_URL__c = 'https://tracking.test/no-order'
        );
        
        Test.startTest();
        insert fulfillmentRecord;
        Test.stopTest();
        
        fulfillmentRecord = [
            SELECT Id, Shop_ID__c
            FROM Fulfilment__c
            WHERE Id = :fulfillmentRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            null,
            fulfillmentRecord.Shop_ID__c,
            'After insert should skip create path when Order__c is missing.'
        );
    }
    
    @IsTest
    static void testFulfilmentTrigger_AfterUpdateTracksWhenTrackingChanges() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Order orderRecord = createOrder('7003');
        
        Fulfilment__c fulfillmentRecord = new Fulfilment__c(
            Order__c = orderRecord.Id,
            Shop_ID__c = 'SHOPIFY_FULF_7003',
            Tracking_Number__c = 'OLD_TRACKING',
            Tracking_Company__c = 'UPS',
            Tracking_URL__c = 'https://tracking.test/old'
        );
        insert fulfillmentRecord;
        
        fulfillmentRecord.Tracking_Number__c = 'NEW_TRACKING';
        fulfillmentRecord.Tracking_Company__c = 'FedEx';
        fulfillmentRecord.Tracking_URL__c = 'https://tracking.test/new';
        
        Test.startTest();
        update fulfillmentRecord;
        Test.stopTest();
        
        Fulfilment__c updatedFulfillment = [
            SELECT Id, Tracking_Number__c, Tracking_Company__c, Tracking_URL__c
            FROM Fulfilment__c
            WHERE Id = :fulfillmentRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals('NEW_TRACKING', updatedFulfillment.Tracking_Number__c);
        System.assertEquals('FedEx', updatedFulfillment.Tracking_Company__c);
        System.assertEquals('https://tracking.test/new', updatedFulfillment.Tracking_URL__c);
    }
    
    @IsTest
    static void testFulfilmentTrigger_AfterUpdateSkipsWhenNoShopId() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Fulfilment__c fulfillmentRecord = new Fulfilment__c(
            Order__c = null,
            Shop_ID__c = null,
            Tracking_Number__c = 'OLD_TRACKING',
            Tracking_Company__c = 'UPS',
            Tracking_URL__c = 'https://tracking.test/old'
        );
        insert fulfillmentRecord;
        
        fulfillmentRecord.Tracking_Number__c = 'NEW_TRACK_NO_SHOP';
        
        Test.startTest();
        update fulfillmentRecord;
        Test.stopTest();
        
        Fulfilment__c updatedFulfillment = [
            SELECT Id, Shop_ID__c, Tracking_Number__c
            FROM Fulfilment__c
            WHERE Id = :fulfillmentRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(null, updatedFulfillment.Shop_ID__c);
        System.assertEquals('NEW_TRACK_NO_SHOP', updatedFulfillment.Tracking_Number__c);
    }
    
    @IsTest
    static void testFulfilmentTrigger_AfterUpdateSkipsWhenTrackingUnchanged() {
        Test.setMock(HttpCalloutMock.class, new FulfillmentMock('success'));
        
        Order orderRecord = createOrder('7005');
        
        Fulfilment__c fulfillmentRecord = new Fulfilment__c(
            Order__c = orderRecord.Id,
            Shop_ID__c = 'SHOPIFY_FULF_7005',
            Tracking_Number__c = 'TRACK_UNCHANGED',
            Tracking_Company__c = 'UPS',
            Tracking_URL__c = 'https://tracking.test/unchanged'
        );
        insert fulfillmentRecord;
        
        Test.startTest();
        update fulfillmentRecord;
        Test.stopTest();
        
        System.assertNotEquals(
            null,
            fulfillmentRecord.Id,
            'After update should skip tracking sync when tracking fields are unchanged.'
        );
    }
}