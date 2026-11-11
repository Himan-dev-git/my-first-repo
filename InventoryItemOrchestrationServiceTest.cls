@IsTest
private class InventoryItemOrchestrationServiceTest {

    @IsTest
    static void testWithValidPayload() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Map<String, Object> payload = new Map<String, Object>{
            'id' => 123,
            'sku' => 'TEST-SKU'
        };

        Test.startTest();
        InventoryItemOrchestrationService.processInventoryItemWebhook(payload);
        Test.stopTest();

        System.assert(true, 'Valid payload executed successfully');
    }

    @IsTest
    static void testWithEmptyPayload() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Map<String, Object> payload = new Map<String, Object>();

        Test.startTest();
        InventoryItemOrchestrationService.processInventoryItemWebhook(payload);
        Test.stopTest();

        System.assert(true, 'Empty payload handled');
    }

    @IsTest
    static void testWithNullPayload() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Test.startTest();
        InventoryItemOrchestrationService.processInventoryItemWebhook(null);
        Test.stopTest();

        System.assert(true, 'Null payload handled');
    }
}