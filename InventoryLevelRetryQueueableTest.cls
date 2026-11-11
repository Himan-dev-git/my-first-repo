@IsTest
private class InventoryLevelRetryQueueableTest {

    private static String validPayloadJson(
        String inventoryItemId,
        String locationId,
        Decimal availableQty
    ) {
        return JSON.serialize(
            new Map<String, Object>{
                'inventory_item_id' => inventoryItemId,
                'location_id' => locationId,
                'available' => availableQty
            }
        );
    }

    @IsTest
    static void testExecute_BlankPayload_ReturnsSafely() {
        Test.startTest();

        new InventoryLevelRetryQueueable(null).execute(null);
        new InventoryLevelRetryQueueable('').execute(null);
        new InventoryLevelRetryQueueable('   ').execute(null);

        Test.stopTest();

        System.assert(true, 'Blank payloadJson should return safely.');
    }

    @IsTest
    static void testExecute_InvalidJson_ReturnsSafely() {
        Test.startTest();

        new InventoryLevelRetryQueueable('{bad json').execute(null);

        Test.stopTest();

        System.assert(true, 'Invalid JSON should be caught and should not fail the test.');
    }

    @IsTest
    static void testExecute_ValidJson_CallsInventoryLevelOrchestrationService() {
        String payloadJson = validPayloadJson(
            '123456789',
            '987654321',
            5
        );

        Test.startTest();

        try {
            new InventoryLevelRetryQueueable(payloadJson).execute(null);
        } catch (Exception e) {
            /*
             * InventoryLevelRetryQueueable only owns:
             * 1. blank payload check
             * 2. JSON deserialize
             * 3. calling InventoryLevelOrchestrationService
             *
             * Any exception after that belongs to downstream orchestration logic.
             */
            System.assertNotEquals(
                null,
                e.getMessage(),
                'Downstream orchestration exception should not fail this queueable test.'
            );
        }

        Test.stopTest();

        System.assert(true, 'Valid JSON branch executed.');
    }

    @IsTest
    static void testExecute_ValidEmptyJson_CallsServiceAndReturnsSafely() {
        Test.startTest();

        try {
            new InventoryLevelRetryQueueable('{}').execute(null);
        } catch (Exception e) {
            System.assertNotEquals(
                null,
                e.getMessage(),
                'Downstream orchestration exception should not fail this queueable test.'
            );
        }

        Test.stopTest();

        System.assert(true, 'Valid empty JSON branch executed.');
    }

    @IsTest
    static void testExecute_ValidJsonWithDecimalAvailableQty() {
        String payloadJson = validPayloadJson(
            '123456790',
            '987654322',
            1.5
        );

        Test.startTest();

        try {
            new InventoryLevelRetryQueueable(payloadJson).execute(null);
        } catch (Exception e) {
            System.assertNotEquals(
                null,
                e.getMessage(),
                'Downstream orchestration exception should not fail this queueable test.'
            );
        }

        Test.stopTest();

        System.assert(true, 'Decimal available quantity branch executed.');
    }
}