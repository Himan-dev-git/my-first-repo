@IsTest
private class ShopifyInventoryMutationServiceTest {

    // 🔹 SUCCESS MOCK
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(
                '{"data":{"inventorySetQuantities":{' +
                '"inventoryAdjustmentGroup":{"reason":"correction"},' +
                '"userErrors":[]}}}'
            );

            return res;
        }
    }

    // 🔹 USER ERROR MOCK
    private class UserErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(
                '{"data":{"inventorySetQuantities":{' +
                '"inventoryAdjustmentGroup":null,' +
                '"userErrors":[{"field":["quantity"],"message":"Invalid"}]}}}'
            );

            return res;
        }
    }

    // ✅ TEST: SUCCESS
    @IsTest
    static void testSetAvailableQuantity_Success() {

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();

        ShopifyInventoryMutationService.ResultWrap result =
            ShopifyInventoryMutationService.setAvailableQuantity(
                '111',   // inventoryItemId
                '222',   // locationId
                10,      // qty
                5,       // changeFromQty
                'test-key'
            );

        Test.stopTest();

        System.assertEquals(true, result.success, 'Should be successful');
        System.assertEquals('Inventory updated successfully', result.message);
    }

    // ✅ TEST: USER ERRORS FROM SHOPIFY
    @IsTest
    static void testSetAvailableQuantity_UserErrors() {

        Test.setMock(HttpCalloutMock.class, new UserErrorMock());

        Test.startTest();

        ShopifyInventoryMutationService.ResultWrap result =
            ShopifyInventoryMutationService.setAvailableQuantity(
                '111',
                '222',
                10,
                5,
                'test-key'
            );

        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail when userErrors present');
        System.assert(result.message.contains('Invalid'), 'Error message should contain Shopify error');
    }

    // ✅ TEST: MISSING INPUTS
    @IsTest
    static void testSetAvailableQuantity_MissingInputs() {

        Test.startTest();

        ShopifyInventoryMutationService.ResultWrap result =
            ShopifyInventoryMutationService.setAvailableQuantity(
                null,
                null,
                10,
                5,
                null
            );

        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('Missing inventory item ID or location ID', result.message);
    }

    // ✅ TEST: NULL QTY HANDLING
    @IsTest
    static void testSetAvailableQuantity_NullQty() {

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();

        ShopifyInventoryMutationService.ResultWrap result =
            ShopifyInventoryMutationService.setAvailableQuantity(
                '111',
                '222',
                null,   // qty null → should default to 0
                null,   // changeFromQty null → should default to 0
                null
            );

        Test.stopTest();

        System.assertEquals(true, result.success);
    }

    // ✅ TEST: RANDOM IDEMPOTENCY KEY PATH
    @IsTest
    static void testSetAvailableQuantity_NoIdempotencyKey() {

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();

        ShopifyInventoryMutationService.ResultWrap result =
            ShopifyInventoryMutationService.setAvailableQuantity(
                '111',
                '222',
                5,
                2,
                null // triggers random key generation
            );

        Test.stopTest();

        System.assertEquals(true, result.success);
    }
}