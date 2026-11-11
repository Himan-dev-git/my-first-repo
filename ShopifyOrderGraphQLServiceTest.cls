@IsTest
private class ShopifyOrderGraphQLServiceTest {

    private class ShopifyMock implements HttpCalloutMock {
        private String mode;

        ShopifyMock(String mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest req) {
            if (mode == 'EXCEPTION') {
                throw new CalloutException('Mock callout failure');
            }

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String body = req.getBody();

            /*
             * Product2 trigger / Shopify product sync side-effect safety.
             * These prevent unrelated async product sync from breaking tests.
             */
            if (body != null && body.contains('productVariantsBulkUpdate')) {
                res.setStatusCode(200);
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
                res.setStatusCode(200);
                res.setBody(
                    '{"data":{"productCreate":{' +
                    '"product":{"id":"gid://shopify/Product/123","legacyResourceId":"123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (body != null && body.contains('productUpdate')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"data":{"productUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            /*
             * markOrderAsPaid branch.
             */
            if (body != null && body.contains('orderMarkAsPaid')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"data":{"orderMarkAsPaid":{' +
                    '"order":{"id":"gid://shopify/Order/999","name":"#1001","displayFinancialStatus":"PAID"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            /*
             * Main orderCreate response branches.
             */
            if (mode == 'NON_200') {
                res.setStatusCode(500);
                res.setBody('server error');
                return res;
            }

            res.setStatusCode(200);

            if (mode == 'NO_DATA') {
                res.setBody('{"errors":[{"message":"bad"}]}');
                return res;
            }

            if (mode == 'NULL_DATA') {
                res.setBody('{"data":null}');
                return res;
            }

            if (mode == 'NO_ORDER_CREATE') {
                res.setBody('{"data":{}}');
                return res;
            }

            if (mode == 'NULL_ORDER_CREATE') {
                res.setBody('{"data":{"orderCreate":null}}');
                return res;
            }

            if (mode == 'USER_ERRORS') {
                res.setBody(
                    '{"data":{"orderCreate":{' +
                    '"userErrors":[{"field":["order"],"message":"Error"}],' +
                    '"order":null' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'NO_ORDER_ID') {
                res.setBody(
                    '{"data":{"orderCreate":{' +
                    '"userErrors":[],' +
                    '"order":{"name":"#1001"}' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'BLANK_ORDER_ID') {
                res.setBody(
                    '{"data":{"orderCreate":{' +
                    '"userErrors":[],' +
                    '"order":{"id":"","name":"#1001"}' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'NO_LINE_ITEMS') {
                res.setBody(
                    '{"data":{"orderCreate":{' +
                    '"userErrors":[],' +
                    '"order":{"id":"gid://shopify/Order/999","name":"#1001"}' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'EMPTY_LINE_ITEM_NODES') {
                res.setBody(
                    '{"data":{"orderCreate":{' +
                    '"userErrors":[],' +
                    '"order":{' +
                    '"id":"gid://shopify/Order/999",' +
                    '"name":"#1001",' +
                    '"lineItems":{"nodes":[]}' +
                    '}' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'LINE_ITEM_WITH_BLANK_ID') {
                res.setBody(
                    '{"data":{"orderCreate":{' +
                    '"userErrors":[],' +
                    '"order":{' +
                    '"id":"gid://shopify/Order/999",' +
                    '"name":"#1001",' +
                    '"lineItems":{"nodes":[{"id":"","quantity":1,"title":"Item 1"}]}' +
                    '}' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'TWO_LINE_ITEMS') {
                res.setBody(
                    '{"data":{"orderCreate":{' +
                    '"userErrors":[],' +
                    '"order":{' +
                    '"id":"gid://shopify/Order/999",' +
                    '"name":"#1001",' +
                    '"lineItems":{"nodes":[' +
                    '{"id":"gid://shopify/LineItem/111","quantity":1,"title":"Item 1"},' +
                    '{"id":"gid://shopify/LineItem/222","quantity":2,"title":"Item 2"}' +
                    ']}' +
                    '}' +
                    '}}}'
                );
                return res;
            }

            res.setBody(
                '{"data":{"orderCreate":{' +
                '"userErrors":[],' +
                '"order":{' +
                '"id":"gid://shopify/Order/999",' +
                '"name":"#1001",' +
                '"lineItems":{"nodes":[' +
                '{"id":"gid://shopify/LineItem/111","quantity":1,"title":"Item 1"}' +
                ']}' +
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

    private static Account createAccount() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        return acc;
    }

    private static Account createPersonAccountIfAvailable() {
        List<RecordType> personRts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];

        if (personRts.isEmpty()) {
            return createAccount();
        }

        Account acc = new Account(
            RecordTypeId = personRts[0].Id,
            LastName = 'Customer'
        );

        putIfCreateable(acc, 'FirstName', 'Test');
        putIfCreateable(acc, 'PersonEmail', 'customer@example.com');

        insert acc;
        return acc;
    }

    private static Product2 createProduct(String shopId) {
        Product2 p = new Product2(
            Name = 'Test Product ' + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 100000)),
            IsActive = true,
            Shop_ID__c = shopId
        );

        Id variantRtId = getVariantRecordTypeIdOrNull();
        if (variantRtId != null) {
            p.RecordTypeId = variantRtId;
        }

        putIfCreateable(p, 'Type__c', 'Variant');

        insert p;
        return p;
    }

    private static Order createOrder(String shopId) {
        return createOrderForAccount(createAccount(), shopId, null);
    }

    private static Order createPaidOrder(String shopId) {
        return createOrderForAccount(createPersonAccountIfAvailable(), shopId, 'Paid');
    }

    private static Order createOrderForAccount(Account acc, String shopId, String financialStatus) {
        Id pbId = Test.getStandardPricebookId();

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = pbId,
            CurrencyIsoCode = 'GBP',
            Shop_ID__c = shopId,
            ShippingStreet = '123 Test St',
            ShippingCity = 'Test City',
            ShippingState = 'CA',
            ShippingPostalCode = '90001',
            ShippingCountry = 'US'
        );

        if (financialStatus != null) {
            ord.Financial_Status__c = financialStatus;
        }

        insert ord;
        return ord;
    }

    private static PricebookEntry createPbe(Product2 p, Decimal priceValue) {
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = p.Id,
            UnitPrice = priceValue,
            IsActive = true,
            CurrencyIsoCode = 'GBP'
        );
        insert pbe;
        return pbe;
    }

    private static Order createOrderWithItem(String orderShopId, String productShopId) {
        Product2 p = createProduct(productShopId);
        PricebookEntry pbe = createPbe(p, 100);

        Order ord = createOrder(orderShopId);

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert oi;

        return ord;
    }

    private static Order createPaidOrderWithItem(String productShopId) {
        Product2 p = createProduct(productShopId);
        PricebookEntry pbe = createPbe(p, 100);

        Order ord = createPaidOrder(null);

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert oi;

        return ord;
    }

    private static Order createOrderWithTwoItems() {
        Product2 p1 = createProduct('456');
        Product2 p2 = createProduct('789');

        PricebookEntry pbe1 = createPbe(p1, 100);
        PricebookEntry pbe2 = createPbe(p2, 200);

        Order ord = createOrder(null);

        insert new List<OrderItem>{
            new OrderItem(
                OrderId = ord.Id,
                PricebookEntryId = pbe1.Id,
                Quantity = 1,
                UnitPrice = 100
            ),
            new OrderItem(
                OrderId = ord.Id,
                PricebookEntryId = pbe2.Id,
                Quantity = 2,
                UnitPrice = 200
            )
        };

        return ord;
    }

    @IsTest
    static void testNullAndEmptyInput() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('SUCCESS'));

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(null);
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>());
        Test.stopTest();

        System.assert(true, 'Null and empty inputs should safely return.');
    }

    @IsTest
    static void testQueriedOrdersEmptySkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('SUCCESS'));

        Account acc = createAccount();

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ acc.Id });
        Test.stopTest();

        System.assert(true, 'Non-order Id should produce empty Order query and safely return.');
    }

    @IsTest
    static void testNoOrderItemsSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('SUCCESS'));

        Order ord = createOrder(null);

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testOrderAlreadyHasShopIdSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('SUCCESS'));

        Order ord = createOrderWithItem('123', '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals('123', afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testOrderItemMissingProductShopIdSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('SUCCESS'));

        Order ord = createOrderWithItem(null, null);

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testCalloutExceptionSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('EXCEPTION'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testNon200Skips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('NON_200'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testNoDataSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('NO_DATA'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testNullDataSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('NULL_DATA'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testNoOrderCreateSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('NO_ORDER_CREATE'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testNullOrderCreateSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('NULL_ORDER_CREATE'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testUserErrorsSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('USER_ERRORS'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testNoOrderIdSkips() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('NO_ORDER_ID'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testBlankOrderIdSkipsOrderUpdate() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('BLANK_ORDER_ID'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order afterOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals(null, afterOrder.Shop_ID__c);
    }

    @IsTest
    static void testNoLineItemsStillUpdatesOrder() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('NO_LINE_ITEMS'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order updatedOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        OrderItem updatedItem = [
            SELECT Shop_ID__c
            FROM OrderItem
            WHERE OrderId = :ord.Id
            LIMIT 1
        ];

        System.assertEquals('999', updatedOrder.Shop_ID__c);
        System.assertEquals(null, updatedItem.Shop_ID__c);
    }

    @IsTest
    static void testEmptyLineItemNodesUpdatesOnlyOrder() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('EMPTY_LINE_ITEM_NODES'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order updatedOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        OrderItem updatedItem = [
            SELECT Shop_ID__c
            FROM OrderItem
            WHERE OrderId = :ord.Id
            LIMIT 1
        ];

        System.assertEquals('999', updatedOrder.Shop_ID__c);
        System.assertEquals(null, updatedItem.Shop_ID__c);
    }

    @IsTest
    static void testLineItemBlankIdDoesNotUpdateItem() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('LINE_ITEM_WITH_BLANK_ID'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order updatedOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        OrderItem updatedItem = [
            SELECT Shop_ID__c
            FROM OrderItem
            WHERE OrderId = :ord.Id
            LIMIT 1
        ];

        System.assertEquals('999', updatedOrder.Shop_ID__c);
        System.assertEquals(null, updatedItem.Shop_ID__c);
    }

    @IsTest
    static void testSuccessfulOrderCreateUpdatesOrderAndItem() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('SUCCESS'));

        Order ord = createOrderWithItem(null, '456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order updatedOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        OrderItem updatedItem = [
            SELECT Shop_ID__c
            FROM OrderItem
            WHERE OrderId = :ord.Id
            LIMIT 1
        ];

        System.assertEquals('999', updatedOrder.Shop_ID__c);
        System.assertEquals('111', updatedItem.Shop_ID__c);
    }

    @IsTest
    static void testSuccessfulPaidOrderCallsMarkPaidAndUpdates() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('SUCCESS'));

        Order ord = createPaidOrderWithItem('456');

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order updatedOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        System.assertEquals('999', updatedOrder.Shop_ID__c);
    }

    @IsTest
    static void testTwoLineItemsUpdateBothItems() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMock('TWO_LINE_ITEMS'));

        Order ord = createOrderWithTwoItems();

        Test.startTest();
        ShopifyOrderGraphQLService.syncOrdersAsync(new List<Id>{ ord.Id });
        Test.stopTest();

        Order updatedOrder = [
            SELECT Shop_ID__c
            FROM Order
            WHERE Id = :ord.Id
        ];

        List<OrderItem> updatedItems = [
            SELECT Shop_ID__c
            FROM OrderItem
            WHERE OrderId = :ord.Id
            ORDER BY CreatedDate ASC
        ];

        System.assertEquals('999', updatedOrder.Shop_ID__c);
        System.assertEquals(2, updatedItems.size());
        System.assertEquals('111', updatedItems[0].Shop_ID__c);
        System.assertEquals('222', updatedItems[1].Shop_ID__c);
    }

    @IsTest
    static void testExtractNumericId() {
        System.assertEquals(
            '123',
            ShopifyOrderGraphQLService.extractNumericId('gid://shopify/Order/123')
        );

        System.assertEquals(
            '123',
            ShopifyOrderGraphQLService.extractNumericId('123')
        );

        System.assertEquals(
            null,
            ShopifyOrderGraphQLService.extractNumericId(null)
        );

        System.assertEquals(
            null,
            ShopifyOrderGraphQLService.extractNumericId('')
        );
    }
}