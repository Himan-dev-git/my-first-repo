public class ApexTestHelper {
	
    public static final Map<String, String> stdShopifyHeaders = new Map<String, String>{
        'accept' => '*/*',
        'accept-encoding' => 'gzip, br',
        'connection' => 'Keep-Alive',
        'content-type' => 'application/json',
        'host' => '897976a207d6449f93325ff974b83f13.api.mockbin.io',
        'true-client-ip' => '34.121.52.229',
        'user-agent' => 'Shopify-Captain-Hook',
        'x-forwarded-for' => '34.121.52.229',
        'x-forwarded-proto' => 'https',
        'x-real-ip' => '34.121.52.229',
        'x-shopify-api-version' => '2024-10',
        'x-shopify-hmac-sha256' => 'lGT832lS1hpabmWUSWjT+2dciIcJ8TihIMIkWf7jwro=',
        'x-shopify-shop-domain' => 'esterah.com',
        'x-shopify-test' => 'true',
        'x-shopify-webhook-id' => '6d99c496-c213-4787-b8d4-8b3d9a2c10f7',
        'zp-ipcity' => 'Council Bluffs',
        'zp-ipcontinent' => 'NA',
        'zp-ipcountry' => 'US',
        'zp-iplatitude' => '41.25910',
        'zp-iplongitude' => '-95.85170',
        'zp-rid' => '76d47e6b-4ede-4fad-a68a-e743a4be98dc'
    };
        
    // Map to store JSON body templates for different topics
    public static final Map<String, String> stdShopifyBodies = new Map<String, String>{
        'customers' => '{"id": 706405506930370000, "email": "bob@biller.com", "created_at": "2024-07-23T18:00:48+01:00", "updated_at": "2024-07-23T18:00:48+01:00", "first_name": "Bob", "last_name": "Biller", "orders_count": 0, "state": "disabled", "total_spent": "0.00", "last_order_id": null, "note": "This customer loves ice cream", "verified_email": true, "multipass_identifier": null, "tax_exempt": false, "tags": "", "last_order_name": null, "currency": "GBP", "phone": null, "addresses": [], "tax_exemptions": [], "email_marketing_consent": null, "sms_marketing_consent": null, "admin_graphql_api_id": "gid://shopify/Customer/706405506930370084"}',
        'orders' => '{"id": 1234567890, "email": "customer@example.com", "created_at": "2024-07-23T18:00:48+01:00", "updated_at": "2024-07-23T18:00:48+01:00", "total_price": "100.00", "currency": "USD", "financial_status": "paid", "fulfillment_status": "fulfilled", "customer": {"id": 706405506930370000, "email": "bob@biller.com"}}'
    };
    
    public static RestRequest createShopifyRequest(String topicName) {
        RestRequest request = new RestRequest();
        request.requestUri = 'https://euda.my.salesforce-sites.com/shopify/services/apexrest/events';
        request.httpMethod = 'POST';
        
        for (String headerName : stdShopifyHeaders.keySet()) {
    		request.addHeader(headerName, stdShopifyHeaders.get(headerName));
		}
        
        // Set the x-shopify-topic header dynamically
        request.addHeader('x-shopify-topic', topicName + '/create');

        // Set the x-shopify-triggered-at header with the current date and time
        request.addHeader('x-shopify-triggered-at', Datetime.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''));

        // Set the request body using a helper method
        request.requestBody = Blob.valueOf(generateRequestBody(topicName));

        return request;
    }

    // Method to generate request body based on topic name
    public static String generateRequestBody(String topicName) {
        // Return the JSON string for the given topic or a default empty JSON
        String body = stdShopifyBodies.get(topicName);
        return body != null ? body : '{}';
    }
}