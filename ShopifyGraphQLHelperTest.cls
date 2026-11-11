@IsTest
private class ShopifyGraphQLHelperTest {

    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.assertEquals('POST', req.getMethod());
            System.assert(req.getEndpoint().contains('/graphql.json'));
            System.assertEquals('application/json', req.getHeader('Content-Type'));

            Map<String, Object> requestBody =
                (Map<String, Object>) JSON.deserializeUntyped(req.getBody());

            System.assert(requestBody.containsKey('query'));
            System.assert(requestBody.containsKey('variables'));

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"data":{"customerCreate":{"customer":{"id":"gid://shopify/Customer/12345"},"userErrors":[]}}}'
            );
            return res;
        }
    }

    private class GraphQLErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"errors":[{"message":"GraphQL error"}]}');
            return res;
        }
    }

    private class HttpErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Bad Request"}');
            return res;
        }
    }

    private class PartialDataMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"data":{"product":{"id":"gid://shopify/Product/111"}},"errors":[{"message":"partial warning"}]}'
            );
            return res;
        }
    }

    @IsTest
    static void testExecuteSuccessWithVariables() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();

        Map<String, Object> result = ShopifyGraphQLHelper.execute(
            'query Customer($id: ID!) { customer(id: $id) { id } }',
            new Map<String, Object>{
                'id' => 'gid://shopify/Customer/12345'
            }
        );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('data'));
    }

    @IsTest
    static void testExecuteSuccessWithNullVariables() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();

        Map<String, Object> result = ShopifyGraphQLHelper.execute(
            'query { shop { name } }',
            null
        );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('data'));
    }

    @IsTest
    static void testExecuteHttpErrorThrowsException() {
        Test.setMock(HttpCalloutMock.class, new HttpErrorMock());

        Test.startTest();

        try {
            ShopifyGraphQLHelper.execute('query {}', null);
            System.assert(false, 'Expected HTTP error exception.');
        } catch (ShopifyGraphQLHelper.ShopifyGraphQLException e) {
            System.assert(
                e.getMessage().contains('Shopify GraphQL HTTP Error 400'),
                'Expected HTTP error message.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void testExecuteTopLevelGraphQLErrorThrowsException() {
        Test.setMock(HttpCalloutMock.class, new GraphQLErrorMock());

        Test.startTest();

        try {
            ShopifyGraphQLHelper.execute('query {}', null);
            System.assert(false, 'Expected GraphQL top-level error exception.');
        } catch (ShopifyGraphQLHelper.ShopifyGraphQLException e) {
            System.assert(
                e.getMessage().contains('top-level errors'),
                'Expected top-level GraphQL error message.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void testExecuteAllowPartialDataAllowsErrors() {
        Test.setMock(HttpCalloutMock.class, new PartialDataMock());

        Test.startTest();

        Map<String, Object> result =
            ShopifyGraphQLHelper.executeAllowPartialData(
                'query { product { id } }',
                null
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('data'));
        System.assert(result.containsKey('errors'));
    }

    @IsTest
    static void testExecuteAllowPartialDataHttpErrorThrowsException() {
        Test.setMock(HttpCalloutMock.class, new HttpErrorMock());

        Test.startTest();

        try {
            ShopifyGraphQLHelper.executeAllowPartialData('query {}', null);
            System.assert(false, 'Expected HTTP error exception.');
        } catch (ShopifyGraphQLHelper.ShopifyGraphQLException e) {
            System.assert(
                e.getMessage().contains('Shopify GraphQL HTTP Error 400'),
                'Expected HTTP error message.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void testGidHelpersNormalIds() {
        System.assertEquals(
            'gid://shopify/Product/100',
            ShopifyGraphQLHelper.toProductGid('100')
        );
        System.assertEquals(
            'gid://shopify/ProductVariant/200',
            ShopifyGraphQLHelper.toVariantGid('200')
        );
        System.assertEquals(
            'gid://shopify/Customer/300',
            ShopifyGraphQLHelper.toCustomerGid('300')
        );
        System.assertEquals(
            'gid://shopify/InventoryItem/400',
            ShopifyGraphQLHelper.toInventoryItemGid('400')
        );
        System.assertEquals(
            'gid://shopify/Location/500',
            ShopifyGraphQLHelper.toLocationGid('500')
        );
    }

    @IsTest
    static void testGidHelpersAlreadyGids() {
        System.assertEquals(
            'gid://shopify/Product/100',
            ShopifyGraphQLHelper.toProductGid('gid://shopify/Product/100')
        );
        System.assertEquals(
            'gid://shopify/ProductVariant/200',
            ShopifyGraphQLHelper.toVariantGid('gid://shopify/ProductVariant/200')
        );
        System.assertEquals(
            'gid://shopify/Customer/300',
            ShopifyGraphQLHelper.toCustomerGid('gid://shopify/Customer/300')
        );
        System.assertEquals(
            'gid://shopify/InventoryItem/400',
            ShopifyGraphQLHelper.toInventoryItemGid('gid://shopify/InventoryItem/400')
        );
        System.assertEquals(
            'gid://shopify/Location/500',
            ShopifyGraphQLHelper.toLocationGid('gid://shopify/Location/500')
        );
    }

    @IsTest
    static void testGidHelpersBlankInputs() {
        System.assertEquals(null, ShopifyGraphQLHelper.toProductGid(null));
        System.assertEquals(null, ShopifyGraphQLHelper.toProductGid(''));
        System.assertEquals(null, ShopifyGraphQLHelper.toProductGid('   '));

        System.assertEquals(null, ShopifyGraphQLHelper.toVariantGid(null));
        System.assertEquals(null, ShopifyGraphQLHelper.toCustomerGid(null));
        System.assertEquals(null, ShopifyGraphQLHelper.toInventoryItemGid(null));
        System.assertEquals(null, ShopifyGraphQLHelper.toLocationGid(null));
    }

    @IsTest
    static void testExtractNumericIdFromGid() {
        System.assertEquals(
            '12345',
            ShopifyGraphQLHelper.extractNumericIdFromGid('gid://shopify/Product/12345')
        );

        System.assertEquals(
            '999',
            ShopifyGraphQLHelper.extractNumericIdFromGid('999')
        );

        System.assertEquals(null, ShopifyGraphQLHelper.extractNumericIdFromGid(null));
        System.assertEquals(null, ShopifyGraphQLHelper.extractNumericIdFromGid(''));
        System.assertEquals(null, ShopifyGraphQLHelper.extractNumericIdFromGid('   '));
    }

    @IsTest
    static void testExecuteRaw() {
        Test.startTest();

        String result = ShopifyGraphQLHelper.executeRaw('gid://shopify/Product/123');

        Test.stopTest();

        System.assertEquals(null, result);
    }
}