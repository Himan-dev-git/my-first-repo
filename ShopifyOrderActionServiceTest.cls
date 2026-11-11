@IsTest
private class ShopifyOrderActionServiceTest {
    
    private static Integer counter = 0;
    private static User shopifyWebhookUser;
    
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static String uniqueText(String prefix) {
        counter++;
        return prefix + '-' + String.valueOf(DateTime.now().getTime()) + '-' + counter;
    }
    
    private static String uniqueEmail() {
        return 'test+' + String.valueOf(DateTime.now().getTime()) + counter + '@example.com';
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
    
    private static void activateStandardPricebook() {
        Id pbId = Test.getStandardPricebookId();
        
        try {
            update new Pricebook2(
                Id = pbId,
                IsActive = true
            );
        } catch (Exception e) {
            System.debug('Standard Pricebook already active or not updateable: ' + e.getMessage());
        }
    }
    
    private static Account createAccount() {
        Account acc = new Account(
            Name = uniqueText('Shopify Order Action Account')
        );
        insert acc;
        return acc;
    }
    
    private static Product2 createProductWithoutOutbound() {
        Product2 p = new Product2(
            Name = uniqueText('Shopify Order Action Product'),
            IsActive = true,
            Updated_by_Integration__c = true
        );
        
        if (fieldExists('Product2', 'Type__c')) {
            p.put('Type__c', 'Variant');
        }
        
        System.runAs(getShopifyWebhookUser()) {
            insert p;
        }
        
        return p;
    }
    
    private static PricebookEntry createPricebookEntry(Id productId) {
        activateStandardPricebook();
        
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = productId,
            UnitPrice = 100,
            IsActive = true
        );
        
        if (fieldExists('PricebookEntry', 'CurrencyIsoCode')) {
            pbe.put('CurrencyIsoCode', 'GBP');
        }
        
        insert pbe;
        return pbe;
    }
    
    private static Order createOrder(String shopId, String fulfillmentStatus, Boolean withAmount) {
        Account acc = createAccount();
        activateStandardPricebook();
        
        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId(),
            Shop_ID__c = shopId,
            Fulfillment_Status__c = fulfillmentStatus,
            Financial_Status__c = 'Paid'
        );
        
        if (fieldExists('Order', 'CurrencyIsoCode')) {
            ord.put('CurrencyIsoCode', 'GBP');
        }
        
        insert ord;
        
        if (withAmount) {
            Product2 p = createProductWithoutOutbound();
            PricebookEntry pbe = createPricebookEntry(p.Id);
            
            OrderItem oi = new OrderItem(
                OrderId = ord.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = 100
            );
            
            insert oi;
        }
        
        return [
            SELECT Id,
            Shop_ID__c,
            Fulfillment_Status__c,
            Financial_Status__c,
            CurrencyIsoCode,
            TotalAmount
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];
    }
    
    private static ShopifyOrderActionService.Request req(Id orderId, String actionType) {
        ShopifyOrderActionService.Request r = new ShopifyOrderActionService.Request();
        r.orderId = orderId;
        r.actionType = actionType;
        r.notifyCustomer = true;
        r.restock = true;
        r.reason = 'PAYMENT DECLINED';
        r.staffNote = 'Test note';
        return r;
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Mock
    // ─────────────────────────────────────────────────────────────────────
    
    private class OrderActionMock implements HttpCalloutMock {
        private String mode;
        
        OrderActionMock(String modeValue) {
            mode = modeValue;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            if (mode == 'HTTP_FAIL') {
                res.setStatusCode(500);
                res.setBody('server error');
                return res;
            }
            
            res.setStatusCode(200);
            
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
                    '"product":{"id":"gid://shopify/Product/123","title":"Updated Product"},' +
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
            
            if (mode == 'TOP_ERROR') {
                res.setBody('{"errors":[{"message":"top error"}]}');
                return res;
            }
            
            if (mode == 'NO_DATA') {
                res.setBody('{"data":null}');
                return res;
            }
            
            if (mode == 'MISSING_ROOT') {
                res.setBody('{"data":{"wrongField":{}}}');
                return res;
            }
            
            if (mode == 'EMPTY_BODY_OBJECT') {
                res.setBody('{}');
                return res;
            }
            
            if (mode == 'CANCEL_USER_ERROR') {
                res.setBody(
                    '{"data":{"orderCancel":{' +
                    '"orderCancelUserErrors":[{"message":"cancel failed"}],' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'CANCEL_USER_ERROR_SECOND_FIELD') {
                res.setBody(
                    '{"data":{"orderCancel":{' +
                    '"orderCancelUserErrors":[],' +
                    '"userErrors":[{"message":"generic cancel failed"}]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'REFUND_USER_ERROR') {
                if (body != null && body.contains('RefundContext')) {
                    res.setBody(refundContextBody(true, true));
                    return res;
                }
                
                res.setBody(
                    '{"data":{"refundCreate":{' +
                    '"refund":null,' +
                    '"userErrors":[{"field":["refund"],"message":"refund failed"}]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'REFUND_NO_ORDER') {
                res.setBody('{"data":{"order":null}}');
                return res;
            }
            
            if (mode == 'REFUND_NO_LINES') {
                res.setBody('{"data":{"order":{"lineItems":{"nodes":[]}}}}');
                return res;
            }
            
            if (mode == 'REFUND_NO_FULFILLMENT_LOCATION') {
                res.setBody(refundContextBody(false, true));
                return res;
            }
            
            if (mode == 'REFUND_NO_FULFILLMENTS') {
                res.setBody(refundContextBody(false, false));
                return res;
            }
            
            if (body != null && body.contains('RefundContext')) {
                res.setBody(refundContextBody(true, true));
                return res;
            }
            
            if (body != null && body.contains('orderCancel')) {
                res.setBody(
                    '{"data":{"orderCancel":{' +
                    '"job":{"id":"1","done":true},' +
                    '"orderCancelUserErrors":[],' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            if (body != null && body.contains('refundCreate')) {
                res.setBody(
                    '{"data":{"refundCreate":{' +
                    '"refund":{"id":"gid://shopify/Refund/1"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            res.setBody('{"data":{}}');
            return res;
        }
        
        private String refundContextBody(Boolean includeLocation, Boolean includeFulfillments) {
            String fulfillmentsJson = '';
            
            if (includeFulfillments) {
                fulfillmentsJson =
                    '"fulfillments":[' +
                    '{' +
                    '"location":' + (includeLocation ? '{"id":"gid://shopify/Location/1"}' : 'null') + ',' +
                    '"fulfillmentLineItems":{"nodes":[' +
                    '{"lineItem":{"id":"gid://shopify/LineItem/1"}}' +
                    ']}' +
                    '}' +
                    '],';
            } else {
                fulfillmentsJson = '"fulfillments":null,';
            }
            
            return
                '{"data":{"order":{' +
                '"lineItems":{"nodes":[' +
                '{"id":"gid://shopify/LineItem/1","quantity":1}' +
                ']},' +
                fulfillmentsJson +
                '"id":"gid://shopify/Order/123"' +
                '}}}';
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Basic run guard coverage
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testRunEmptyRequestsReturnsEmptyList() {
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>());
        Test.stopTest();
        
        System.assertEquals(0, results.size());
    }
    
    @IsTest
    static void testRunCatchesExceptionForNullOrderId() {
        ShopifyOrderActionService.Request r = new ShopifyOrderActionService.Request();
        r.orderId = null;
        r.actionType = 'CANCEL';
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assertNotEquals(null, results[0].message);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Cancel tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testCancelSuccess() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('SUCCESS'));
        
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'CANCEL');
        r.reason = 'DECLINED';
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(true, results[0].success, results[0].message);
        System.assert(results[0].message.contains('cancellation'));
        
        Order updated = [
            SELECT Fulfillment_Status__c, Cancelled_Date__c, Cancel_Reason__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];
        
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
        System.assertNotEquals(null, updated.Cancelled_Date__c);
        System.assertEquals(
            'Declined',
            updated.Cancel_Reason__c,
            'Salesforce stores the Cancel Reason picklist label/value as Declined.'
        );    }
    
    @IsTest
    static void testCancelSuccessDefaultFields() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('SUCCESS'));
        
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'CANCEL');
        r.notifyCustomer = null;
        r.restock = null;
        r.reason = null;
        r.staffNote = null;
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(true, results[0].success, results[0].message);
    }
    
    @IsTest
    static void testCancelBlockedFulfilled() {
        Order ord = createOrder('123', 'Fulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'CANCEL') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Use Refund'));
    }
    
    @IsTest
    static void testMissingShopifyId() {
        Order ord = createOrder(null, 'Unfulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'CANCEL') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('missing'));
    }
    
    @IsTest
    static void testUnsupportedAction() {
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'OTHER') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Unsupported'));
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Refund success tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testRefundSuccessOriginalPayment() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('SUCCESS'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = 50;
        r.refundMethod = 'ORIGINAL PAYMENT';
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(true, results[0].success, results[0].message);
        System.assert(results[0].message.contains('refund'));
        
        Order updated = [
            SELECT Financial_Status__c, Fulfillment_Status__c, Refund_Date__c, Refund_Reason__c, Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];
        
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
        System.assertNotEquals(null, updated.Refund_Date__c);
        System.assertEquals('PAYMENT DECLINED', updated.Refund_Reason__c);
        System.assertEquals(50, updated.Refund_Amount__c);
    }
    
    @IsTest
    static void testRefundSuccessStoreCredit() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('SUCCESS'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = 25;
        r.refundMethod = 'STORE CREDIT';
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(true, results[0].success, results[0].message);
    }
    
    @IsTest
    static void testRefundSuccessOriginalAndStoreCredit() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('SUCCESS'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = 25;
        r.refundMethod = 'ORIGINAL PAYMENT AND STORE CREDIT';
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(true, results[0].success, results[0].message);
    }
    
    @IsTest
    static void testRefundSuccessNoRestock() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('SUCCESS'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = 25;
        r.restock = false;
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(true, results[0].success, results[0].message);
        
        Order updated = [
            SELECT Financial_Status__c, Fulfillment_Status__c, Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];
        
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Unfulfilled', updated.Fulfillment_Status__c);
        System.assertEquals(25, updated.Refund_Amount__c);
    }
    
    @IsTest
    static void testRefundSuccessDefaultAmount() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('SUCCESS'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = null;
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(true, results[0].success, results[0].message);
        
        Order updated = [
            SELECT Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];
        
        System.assertEquals(100, updated.Refund_Amount__c);
    }
    
    @IsTest
    static void testRefundSuccessNegativeAmountDefaultsToTotal() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('SUCCESS'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = -5;
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(true, results[0].success, results[0].message);
        
        Order updated = [
            SELECT Refund_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];
        
        System.assertEquals(100, updated.Refund_Amount__c);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Refund validation/error tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testRefundTooHigh() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('SUCCESS'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = 9999;
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('greater than'));
    }
    
    @IsTest
    static void testRefundNoOrderReturned() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('REFUND_NO_ORDER'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = 10;
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Unable to load'));
    }
    
    @IsTest
    static void testRefundNoLinesReturned() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('REFUND_NO_LINES'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = 10;
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('No Shopify line items'));
    }
    
    @IsTest
    static void testRefundMissingFulfillmentLocation() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('REFUND_NO_FULFILLMENT_LOCATION'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = 10;
        r.restock = true;
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('fulfillment location'));
    }
    
  
    // ─────────────────────────────────────────────────────────────────────
    // sendGraphQL response tests
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testNoShopifyDataReturned() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('NO_DATA'));
        
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'CANCEL') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assertEquals('No Shopify data returned.', results[0].message);
    }
    
    @IsTest
    static void testMissingShopifyResponseField() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('MISSING_ROOT'));
        
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'CANCEL') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Missing Shopify response field'));
    }
    
    @IsTest
    static void testEmptyResponseObjectReturnsNoData() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('EMPTY_BODY_OBJECT'));
        
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'CANCEL') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assertEquals('No Shopify data returned.', results[0].message);
    }
    
    @IsTest
    static void testHttpFailure() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('HTTP_FAIL'));
        
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'CANCEL') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assertEquals('Shopify call failed.', results[0].message);
    }
    
    @IsTest
    static void testTopLevelGraphQLError() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('TOP_ERROR'));
        
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'CANCEL') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Shopify error'));
    }
    
    @IsTest
    static void testCancelUserErrorOrderCancelUserErrors() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('CANCEL_USER_ERROR'));
        
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'CANCEL') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Shopify error'));
    }
    
    @IsTest
    static void testCancelUserErrorFallbackUserErrors() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('CANCEL_USER_ERROR_SECOND_FIELD'));
        
        Order ord = createOrder('123', 'Unfulfilled', false);
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ req(ord.Id, 'CANCEL') });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Shopify error'));
    }
    
    @IsTest
    static void testRefundUserError() {
        Test.setMock(HttpCalloutMock.class, new OrderActionMock('REFUND_USER_ERROR'));
        
        Order ord = createOrder('123', 'Unfulfilled', true);
        
        ShopifyOrderActionService.Request r = req(ord.Id, 'REFUND');
        r.refundAmount = 10;
        
        Test.startTest();
        List<ShopifyOrderActionService.Result> results =
            ShopifyOrderActionService.run(new List<ShopifyOrderActionService.Request>{ r });
        Test.stopTest();
        
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Shopify error'));
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // normalizeCancelReason coverage
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testNormalizeCancelReasonBranches() {
        System.assertEquals('CUSTOMER', ShopifyOrderActionService.normalizeCancelReason(null));
        System.assertEquals('CUSTOMER', ShopifyOrderActionService.normalizeCancelReason(''));
        System.assertEquals('CUSTOMER', ShopifyOrderActionService.normalizeCancelReason('CUSTOMER'));
        System.assertEquals('DECLINED', ShopifyOrderActionService.normalizeCancelReason('DECLINED'));
        System.assertEquals('FRAUD', ShopifyOrderActionService.normalizeCancelReason('FRAUD'));
        System.assertEquals('INVENTORY', ShopifyOrderActionService.normalizeCancelReason('INVENTORY'));
        System.assertEquals('OTHER', ShopifyOrderActionService.normalizeCancelReason('OTHER'));
        System.assertEquals('STAFF', ShopifyOrderActionService.normalizeCancelReason('STAFF'));
        
        System.assertEquals('CUSTOMER', ShopifyOrderActionService.normalizeCancelReason('CUSTOMER CHANGED OR CANCELED ORDER'));
        System.assertEquals('DECLINED', ShopifyOrderActionService.normalizeCancelReason('PAYMENT DECLINED'));
        System.assertEquals('FRAUD', ShopifyOrderActionService.normalizeCancelReason('FRAUDULENT ORDER'));
        System.assertEquals('INVENTORY', ShopifyOrderActionService.normalizeCancelReason('ITEMS UNAVAILABLE'));
        System.assertEquals('STAFF', ShopifyOrderActionService.normalizeCancelReason('STAFF ERROR'));
        System.assertEquals('OTHER', ShopifyOrderActionService.normalizeCancelReason('something else'));
    }
}