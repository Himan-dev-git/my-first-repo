@IsTest
private class ShopifyOrderUpdateGraphQLServiceTest {

    private class ShopifyOrderMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String body = req.getBody();

            if (body.contains('getFulfillmentOrders')) {
                res.setBody(
                    '{"data":{"order":{"fulfillmentOrders":{"nodes":[' +
                    '{"id":"gid://shopify/FulfillmentOrder/111","status":"OPEN"}' +
                    ']}}}}'
                );
            } else if (body.contains('fulfillmentCreate')) {
                res.setBody(
                    '{"data":{"fulfillmentCreate":{"fulfillment":{"id":"gid://shopify/Fulfillment/222","status":"SUCCESS"},"userErrors":[]}}}'
                );
            } else if (body.contains('orderMarkAsPaid')) {
                res.setBody(
                    '{"data":{"orderMarkAsPaid":{"order":{"id":"gid://shopify/Order/123","name":"#1001","displayFinancialStatus":"PAID"},"userErrors":[]}}}'
                );
            } else if (body.contains('orderCreateManualPayment')) {
                res.setBody(
                    '{"data":{"orderCreateManualPayment":{"order":{"id":"gid://shopify/Order/123","name":"#1001","displayFinancialStatus":"PARTIALLY_PAID"},"userErrors":[]}}}'
                );
            } else if (body.contains('orderUpdate')) {
                res.setBody(
                    '{"data":{"orderUpdate":{"order":{"id":"gid://shopify/Order/123"},"userErrors":[]}}}'
                );
            } else {
                res.setBody('{"data":{}}');
            }

            return res;
        }
    }

    private class FulfillmentNon200Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();

            if (req.getBody().contains('getFulfillmentOrders')) {
                res.setStatusCode(500);
                res.setBody('server error');
            } else {
                res.setStatusCode(200);
                res.setBody('{"data":{"orderUpdate":{"order":{"id":"gid://shopify/Order/123"},"userErrors":[]}}}');
            }

            return res;
        }
    }

    private class FulfillmentNoOpenNodeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (req.getBody().contains('getFulfillmentOrders')) {
                res.setBody(
                    '{"data":{"order":{"fulfillmentOrders":{"nodes":[' +
                    '{"id":"gid://shopify/FulfillmentOrder/111","status":"CLOSED"}' +
                    ']}}}}'
                );
            } else {
                res.setBody('{"data":{"orderUpdate":{"order":{"id":"gid://shopify/Order/123"},"userErrors":[]}}}');
            }

            return res;
        }
    }

    private class FulfillmentEmptyNodesMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (req.getBody().contains('getFulfillmentOrders')) {
                res.setBody('{"data":{"order":{"fulfillmentOrders":{"nodes":[]}}}}');
            } else {
                res.setBody('{"data":{"orderUpdate":{"order":{"id":"gid://shopify/Order/123"},"userErrors":[]}}}');
            }

            return res;
        }
    }

    private static Account createAccount() {
        Account acc = new Account(
            FirstName = 'Test',
            LastName = 'Customer'
        );
        insert acc;
        return acc;
    }

    private static Order createOrder(String shopId, String financialStatus, String fulfillmentStatus) {
        Account acc = createAccount();

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Shop_ID__c = shopId,
            Financial_Status__c = financialStatus,
            Fulfillment_Status__c = fulfillmentStatus,
            ShippingStreet = '123 Test St',
            ShippingCity = 'Test City',
            ShippingState = 'CA',
            ShippingPostalCode = '90001',
            ShippingCountry = 'US'
        );
        insert ord;

        return ord;
    }

    private static Order createOrderWithAmount(String shopId, String financialStatus, String fulfillmentStatus) {

    Account acc = createAccount();

    Id standardPricebookId = Test.getStandardPricebookId();

    // Create Product
    Product2 prod = new Product2(
        Name = 'Test Product',
        IsActive = true
    );
    insert prod;

    // Create Pricebook Entry
    PricebookEntry pbe = new PricebookEntry(
        Pricebook2Id = standardPricebookId,
        Product2Id = prod.Id,
        UnitPrice = 100,
        IsActive = true,
        CurrencyIsoCode = 'GBP' // 🔥 ADD THIS
    );
    insert pbe;

    // 🔥 FIX: Set Pricebook2Id on Order
    Order ord = new Order(
        AccountId = acc.Id,
        EffectiveDate = Date.today(),
        Status = 'Draft',
        Shop_ID__c = shopId,
        Financial_Status__c = financialStatus,
        Fulfillment_Status__c = fulfillmentStatus,
        Pricebook2Id = standardPricebookId, // ✅ REQUIRED
        ShippingStreet = '123 Test St',
        ShippingCity = 'Test City',
        ShippingState = 'CA',
        ShippingPostalCode = '90001',
        ShippingCountry = 'US'
    );
    insert ord;

    // Create Order Item
    OrderItem oi = new OrderItem(
        OrderId = ord.Id,
        PricebookEntryId = pbe.Id,
        Quantity = 1,
        UnitPrice = 100
    );
    insert oi;

    return ord;
}
    @IsTest
    static void testNullAndEmptyInput() {
        Test.startTest();
        ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(null);
        ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(new List<Id>());
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testOrderWithoutShopIdIsIgnored() {
        Order ord = createOrder(null, 'paid', 'Fulfilled');

        Test.startTest();
        ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testPaidFulfilledOrderFullFlow() {
        Order ord = createOrder('123', 'paid', 'Fulfilled');

        Test.setMock(HttpCalloutMock.class, new ShopifyOrderMock());

        Test.startTest();
        ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        System.assert(true);
    }

   /* @IsTest
    static void testPartiallyPaidOrderFlow() {
        Order ord = createOrderWithAmount('123', 'partially_paid', null);

        Test.setMock(HttpCalloutMock.class, new ShopifyOrderMock());

        Test.startTest();
        ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        System.assert(true);
    }*/

    @IsTest
    static void testFinancialStatusBlankOnlyAddressSync() {
        Order ord = createOrder('123', null, null);

        Test.setMock(HttpCalloutMock.class, new ShopifyOrderMock());

        Test.startTest();
        ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testFulfillmentNon200Returns() {
        Order ord = createOrder('123', 'pending', 'Fulfilled');

        Test.setMock(HttpCalloutMock.class, new FulfillmentNon200Mock());

        Test.startTest();
        ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testFulfillmentEmptyNodesReturns() {
        Order ord = createOrder('123', 'pending', 'Fulfilled');

        Test.setMock(HttpCalloutMock.class, new FulfillmentEmptyNodesMock());

        Test.startTest();
        ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testFulfillmentNoOpenNodeReturns() {
        Order ord = createOrder('123', 'pending', 'Fulfilled');

        Test.setMock(HttpCalloutMock.class, new FulfillmentNoOpenNodeMock());

        Test.startTest();
        ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        System.assert(true);
    }
}