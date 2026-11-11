@IsTest
private class RestEndpoint_EventsTest {

    @IsTest
    static void testHandleCustomer() {
        // Use ApexTestHelper to set up the test request
        RestRequest req = ApexTestHelper.createShopifyRequest('customer');     
        RestResponse res = new RestResponse();
        
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        	RestEndpoint_Events.handleWebhook();
        Test.stopTest();
    }

    @IsTest
    static void testHandleCustomerWithException() {
        // Use ApexTestHelper to set up the test request
        RestRequest req = ApexTestHelper.createShopifyRequest('customer');
        req.requestBody = Blob.valueOf('invalid json');
        
        RestResponse res = new RestResponse();
        
        // Set the context for the REST request
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        	RestEndpoint_Events.handleWebhook();
        Test.stopTest(); 
    }
}