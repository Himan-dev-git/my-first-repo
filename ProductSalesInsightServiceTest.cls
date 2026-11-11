@IsTest
private class ProductSalesInsightServiceTest {

    private static Integer counter = 0;
    private static User shopifyWebhookUser;

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    private static String uniqueText(String prefix) {
        counter++;
        return prefix + '-' + String.valueOf(DateTime.now().getTime()) + '-' + counter;
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

    private static User getShopifyWebhookUser() {
        if (shopifyWebhookUser != null) {
            return shopifyWebhookUser;
        }

        String suffix =
            String.valueOf(DateTime.now().getTime()) +
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
        return u;
    }

    private static Account createAccount(String namePrefix) {
        Account acc = new Account(Name = uniqueText(namePrefix));
        insert acc;
        return acc;
    }

    private static Product2 createProduct(String namePrefix) {
        Product2 p = new Product2(
            Name = uniqueText(namePrefix),
            IsActive = true
        );

        if (fieldExists('Product2', 'Shop_ID__c')) {
            p.put('Shop_ID__c', uniqueText('SHOP'));
        }

        if (fieldExists('Product2', 'Updated_by_Integration__c')) {
            p.put('Updated_by_Integration__c', true);
        }

        if (fieldExists('Product2', 'Type__c')) {
            p.put('Type__c', 'Product');
        }

        /*
         * Insert as shopify_webhook_site user so Product2 triggers do not start
         * outbound Shopify/Square side effects in tests.
         */
        System.runAs(getShopifyWebhookUser()) {
            insert p;
        }

        return p;
    }

    private static PricebookEntry createPricebookEntry(Product2 productRecord, Decimal unitPrice) {
        Id standardPricebookId = Test.getStandardPricebookId();

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = unitPrice,
            IsActive = true
        );

        insert pbe;
        return pbe;
    }

    private static Order createOrder(
        Account acc,
        Date effectiveDate,
        String orderType,
        String status
    ) {
        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = effectiveDate,
            Status = status,
            Type = orderType,
            Pricebook2Id = Test.getStandardPricebookId()
        );

        insert ord;
        return ord;
    }

    private static OrderItem createOrderItem(
        Order ord,
        PricebookEntry pbe,
        Decimal quantity,
        Decimal unitPrice
    ) {
        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = quantity,
            UnitPrice = unitPrice
        );

        insert oi;
        return oi;
    }

    private static Product2 querySalesInsightFields(Id productId) {
        return [
            SELECT Id,
                   Sales_Last_90_Days_Unit__c,
                   Sales_Last_90_Days_Buyer__c,
                   Sales_Last_90_Days_Net_Sales__c,
                   Sales_Insight_Last_Sync__c
            FROM Product2
            WHERE Id = :productId
            LIMIT 1
        ];
    }

    // ─────────────────────────────────────────────────────────────────────
    // Safe mock for any Product2 trigger side-effect callouts
    // ─────────────────────────────────────────────────────────────────────

    private class SafeHttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String body = req.getBody();

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

            res.setBody('{"data":{}}');
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testRefreshForProducts_NullAndEmptyReturnSafely() {
        Test.startTest();

        ProductSalesInsightService.refreshForProducts(null);
        ProductSalesInsightService.refreshForProducts(new Set<Id>());

        Test.stopTest();

        System.assert(true, 'Null and empty productIds should return safely.');
    }

    @IsTest
    static void testRefreshForProducts_NoOrderItemsSetsZeros() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());

        Product2 productRecord = createProduct('No Sales Product');

        Test.startTest();

        ProductSalesInsightService.refreshForProducts(
            new Set<Id>{ productRecord.Id }
        );

        Test.stopTest();

        Product2 updated = querySalesInsightFields(productRecord.Id);

        System.assertEquals(0, updated.Sales_Last_90_Days_Unit__c);
        System.assertEquals(0, updated.Sales_Last_90_Days_Buyer__c);
        System.assertEquals(0, updated.Sales_Last_90_Days_Net_Sales__c);
        System.assertNotEquals(null, updated.Sales_Insight_Last_Sync__c);
    }

    @IsTest
    static void testRefreshForProducts_WithShopifyOrderItemsAggregatesCorrectly() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());

        Product2 productRecord = createProduct('Sales Product');
        PricebookEntry pbe = createPricebookEntry(productRecord, 100);

        Account buyerOne = createAccount('Buyer One');
        Account buyerTwo = createAccount('Buyer Two');

        Order orderOne = createOrder(
            buyerOne,
            Date.today().addDays(-10),
            'Shopify Order',
            'Draft'
        );

        Order orderTwo = createOrder(
            buyerTwo,
            Date.today().addDays(-20),
            'Shopify Order',
            'Draft'
        );

        /*
         * Two lines for two different buyers.
         * Net Sales uses OrderItem.TotalPrice when available.
         */
        createOrderItem(orderOne, pbe, 2, 50);
        createOrderItem(orderTwo, pbe, 3, 40);

        Test.startTest();

        ProductSalesInsightService.refreshForProducts(
            new Set<Id>{ productRecord.Id }
        );

        Test.stopTest();

        Product2 updated = querySalesInsightFields(productRecord.Id);

        System.assertEquals(5, updated.Sales_Last_90_Days_Unit__c);
        System.assertEquals(2, updated.Sales_Last_90_Days_Buyer__c);
        System.assertEquals(220, updated.Sales_Last_90_Days_Net_Sales__c);
        System.assertNotEquals(null, updated.Sales_Insight_Last_Sync__c);
    }

    @IsTest
    static void testRefreshForProducts_SameBuyerCountsOnce() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());

        Product2 productRecord = createProduct('Same Buyer Product');
        PricebookEntry pbe = createPricebookEntry(productRecord, 25);

        Account buyer = createAccount('Same Buyer');

        Order orderOne = createOrder(
            buyer,
            Date.today().addDays(-5),
            'Shopify Order',
            'Draft'
        );

        Order orderTwo = createOrder(
            buyer,
            Date.today().addDays(-6),
            'Shopify Order',
            'Draft'
        );

        createOrderItem(orderOne, pbe, 1, 25);
        createOrderItem(orderTwo, pbe, 4, 25);

        Test.startTest();

        ProductSalesInsightService.refreshForProducts(
            new Set<Id>{ productRecord.Id }
        );

        Test.stopTest();

        Product2 updated = querySalesInsightFields(productRecord.Id);

        System.assertEquals(5, updated.Sales_Last_90_Days_Unit__c);
        System.assertEquals(1, updated.Sales_Last_90_Days_Buyer__c);
        System.assertEquals(125, updated.Sales_Last_90_Days_Net_Sales__c);
        System.assertNotEquals(null, updated.Sales_Insight_Last_Sync__c);
    }

    @IsTest
    static void testRefreshForProducts_IgnoresNonShopifyAndOlderThan90DaysOrders() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());

        Product2 productRecord = createProduct('Ignored Orders Product');
        PricebookEntry pbe = createPricebookEntry(productRecord, 10);

        Account buyer = createAccount('Ignored Buyer');

        Order nonShopifyOrder = createOrder(
            buyer,
            Date.today().addDays(-10),
            'POS',
            'Draft'
        );

        Order oldShopifyOrder = createOrder(
            buyer,
            Date.today().addDays(-120),
            'Shopify Order',
            'Draft'
        );

        createOrderItem(nonShopifyOrder, pbe, 5, 10);
        createOrderItem(oldShopifyOrder, pbe, 7, 10);

        Test.startTest();

        ProductSalesInsightService.refreshForProducts(
            new Set<Id>{ productRecord.Id }
        );

        Test.stopTest();

        Product2 updated = querySalesInsightFields(productRecord.Id);

        System.assertEquals(0, updated.Sales_Last_90_Days_Unit__c);
        System.assertEquals(0, updated.Sales_Last_90_Days_Buyer__c);
        System.assertEquals(0, updated.Sales_Last_90_Days_Net_Sales__c);
        System.assertNotEquals(null, updated.Sales_Insight_Last_Sync__c);
    }

    @IsTest
    static void testRefreshForProducts_MultipleProductsOneWithSalesOneWithoutSales() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());

        Product2 productWithSales = createProduct('Product With Sales');
        Product2 productWithoutSales = createProduct('Product Without Sales');

        PricebookEntry pbe = createPricebookEntry(productWithSales, 30);
        Account buyer = createAccount('Multi Product Buyer');

        Order shopifyOrder = createOrder(
            buyer,
            Date.today().addDays(-15),
            'Shopify Order',
            'Draft'
        );

        createOrderItem(shopifyOrder, pbe, 2, 30);

        Test.startTest();

        ProductSalesInsightService.refreshForProducts(
            new Set<Id>{
                productWithSales.Id,
                productWithoutSales.Id
            }
        );

        Test.stopTest();

        Product2 withSales = querySalesInsightFields(productWithSales.Id);
        Product2 withoutSales = querySalesInsightFields(productWithoutSales.Id);

        System.assertEquals(2, withSales.Sales_Last_90_Days_Unit__c);
        System.assertEquals(1, withSales.Sales_Last_90_Days_Buyer__c);
        System.assertEquals(60, withSales.Sales_Last_90_Days_Net_Sales__c);
        System.assertNotEquals(null, withSales.Sales_Insight_Last_Sync__c);

        System.assertEquals(0, withoutSales.Sales_Last_90_Days_Unit__c);
        System.assertEquals(0, withoutSales.Sales_Last_90_Days_Buyer__c);
        System.assertEquals(0, withoutSales.Sales_Last_90_Days_Net_Sales__c);
        System.assertNotEquals(null, withoutSales.Sales_Insight_Last_Sync__c);
    }

    @IsTest
    static void testRefreshForProductsAsync() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());

        Product2 productRecord = createProduct('Async Sales Product');
        PricebookEntry pbe = createPricebookEntry(productRecord, 15);

        Account buyer = createAccount('Async Buyer');

        Order shopifyOrder = createOrder(
            buyer,
            Date.today().addDays(-1),
            'Shopify Order',
            'Draft'
        );

        createOrderItem(shopifyOrder, pbe, 2, 15);

        Test.startTest();

        ProductSalesInsightService.refreshForProductsAsync(
            new List<Id>{ productRecord.Id }
        );

        Test.stopTest();

        Product2 updated = querySalesInsightFields(productRecord.Id);

        System.assertEquals(2, updated.Sales_Last_90_Days_Unit__c);
        System.assertEquals(1, updated.Sales_Last_90_Days_Buyer__c);
        System.assertEquals(30, updated.Sales_Last_90_Days_Net_Sales__c);
        System.assertNotEquals(null, updated.Sales_Insight_Last_Sync__c);
    }
}