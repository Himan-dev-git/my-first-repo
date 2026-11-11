@IsTest
private class RestHelperTest {

    @IsTest
    static void testBuildUrlForShopify() {
        
        String appName = 'shopify';
        String requestName = 'ListCustomers';
        
        // Query the metadata for endpoint mapping
        Endpoint_Mapping__mdt mapping = [
            SELECT API_Version__c, App_Name__c, Method__c, Named_Credential__c, Relative_URL__c, Request_Name__c 
            FROM Endpoint_Mapping__mdt 
            WHERE Request_Name__c = :requestName 
            AND App_Name__c = :appName
            LIMIT 1
        ];
        
        String url = RestHelper.buildUrl(appName, requestName, '', 'customers', mapping);
        
        System.assertNotEquals(null, url, 'URL should not be null.');
        System.assert(url.contains('2024-07/customers.json'), 'URL should contain the correct API version and endpoint.');
    }

    @IsTest
    static void testBuildUrlForShopify_WithRecordIdentifier() {
        
        String appName = 'shopify';
        String requestName = 'SingleOrder';
        
        // Query the metadata for endpoint mapping
        Endpoint_Mapping__mdt mapping = [
            SELECT API_Version__c, App_Name__c, Method__c, Named_Credential__c, Relative_URL__c, Request_Name__c 
            FROM Endpoint_Mapping__mdt 
            WHERE Request_Name__c = :requestName 
            AND App_Name__c = :appName
            LIMIT 1
        ];
        
        String url = RestHelper.buildUrl(appName, requestName, '12345', 'orders', mapping);
        
        System.assertNotEquals(null, url, 'URL should not be null.');
        System.assert(url.endsWith('/2024-07/orders/12345.json'), 'URL should end with the correct API version, topic, and record identifier.');
    }
    
    @IsTest
    static void testBuildUrlForShopify_UpdateProduct() {
        
        String appName = 'shopify';
        String requestName = 'UpdateProduct';
        
        // Query the metadata for endpoint mapping
        Endpoint_Mapping__mdt mapping = [
            SELECT API_Version__c, App_Name__c, Method__c, Named_Credential__c, Relative_URL__c, Request_Name__c 
            FROM Endpoint_Mapping__mdt 
            WHERE Request_Name__c = :requestName 
            AND App_Name__c = :appName
            LIMIT 1
        ];
        
        String url = RestHelper.buildUrl(appName, requestName, '12345', 'products', mapping);
        
        System.assertNotEquals(null, url, 'URL should not be null.');
        System.assert(url.contains('/2024-07/products/12345.json'), 'URL should contain the correct API version and endpoint.');
    }
    
    @IsTest
    static void testBuildUrlForSquare() {
        
        String appName = 'square';
        String requestName = 'ListCustomers';
        
        // Query the metadata for endpoint mapping
        Endpoint_Mapping__mdt mapping = [
            SELECT API_Version__c, App_Name__c, Method__c, Named_Credential__c, Relative_URL__c, Request_Name__c 
            FROM Endpoint_Mapping__mdt 
            WHERE Request_Name__c = :requestName 
            AND App_Name__c = :appName
            LIMIT 1
        ];
        
        String url = RestHelper.buildUrl(appName, requestName, '', 'customers', mapping);
        
        System.assertNotEquals(null, url, 'URL should not be null.');
        System.assert(url.contains('v2/customers'), 'URL should contain the correct API version and endpoint.');
    }

    @IsTest
    static void testBuildUrlForRoyalMail() {
        
        String appName = 'royalmail';
        String requestName = 'SingleOrder';
        
        // Query the metadata for endpoint mapping
        Endpoint_Mapping__mdt mapping = [
            SELECT API_Version__c, App_Name__c, Method__c, Named_Credential__c, Relative_URL__c, Request_Name__c 
            FROM Endpoint_Mapping__mdt 
            WHERE Request_Name__c = :requestName 
            AND App_Name__c = :appName
            LIMIT 1
        ];
		       
        String url = RestHelper.buildUrl(appName, requestName, '56789', 'orders', mapping);
        
        System.assertNotEquals(null, url, 'URL should not be null.');
        System.assert(url.endsWith('v1/orders/56789'), 'URL should end with the correct endpoint and order identifier.');
    }
    
    @IsTest
    static void testHandleRestRequest() {
        Test.startTest();
        
        // Prepare mock data
        String appName = 'shopify';
        String requestName = 'ListCustomers';
        String recordIdentifier = '';

        // Call the method
        RestHelper.handleRestRequest(appName, requestName, recordIdentifier, 'customers');
        
        // Assertions for logs can be added if needed
        Test.stopTest();
    }

    @IsTest
    static void testHandleHttpResponse() {
        // Simulate a response
        HttpResponse res = new HttpResponse();
        res.setBody('{"key": "value"}');
        res.setStatusCode(200);

        // Call the method
        Test.startTest();
        RestHelper.handleHttpResponse(res, 'customers');
        Test.stopTest();
        
        // Assertions for logs can be added if needed
    }
}