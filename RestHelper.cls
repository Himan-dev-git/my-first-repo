public class RestHelper {
    
    public static final List<String> METHODS_NEEDING_BODY = new List<String>{'PUT','POST'};
    
    @future(callout=true)
    public static void handleRestRequestAsync(String appName, String requestName, String recordIdentifier, String topicName, String jsonBody) {
		handleRestRequest(appName, requestName, recordIdentifier, topicName, jsonBody);        
    }
    
    public static void handleRestRequest(String appName, String requestName, String recordIdentifier, String topicName){
    	handleRestRequest(appName, requestName, recordIdentifier, topicName, '');     
    }
    
    public static void handleRestRequest(String appName, String requestName, String recordIdentifier, String topicName, String jsonBody) {
        // Query the metadata for endpoint mapping
        Endpoint_Mapping__mdt mapping = [
            SELECT API_Version__c, App_Name__c, Method__c, Named_Credential__c, Relative_URL__c, Request_Name__c 
            FROM Endpoint_Mapping__mdt 
            WHERE Request_Name__c = :requestName 
            AND App_Name__c = :appName
            LIMIT 1
        ];
        
        String url = buildUrl(appName, requestName, recordIdentifier, topicName, mapping);
        if (url == null) {
            System.debug('Error: Unable to build the URL.');
            return;
        }
        
        // Create the HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod(mapping.Method__c); // Default method to GET, modify if needed
        req.setHeader('Content-Type', 'application/json');
        
		if (METHODS_NEEDING_BODY.contains(mapping.Method__c)) {
        	req.setBody(jsonBody);
            system.debug('Body is set to '+jsonBody);
        }
        system.debug('Request is '+req);
        Http http = new Http();
        HttpResponse res;
        
        // Commenting out the HTTP call for testing purposes
        
        try {
            if (!Test.isRunningTest()) {
                res = http.send(req);
                system.debug('Request sent');
                system.debug('Response received is');
                system.debug(res);
            }         	
            if(mapping.Method__c == 'GET'){
            	handleHttpResponse(res, topicName);
            }
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
        }
        
    }

    public static String buildUrl(String appName, String requestName, String recordIdentifier, String topicNames, Endpoint_Mapping__mdt mapping) {

        // Build the base URL from the Named Credential
        String namedCredentialUrl = 'callout:' + mapping.Named_Credential__c;

        // Replace the {{record_id}} placeholder with the actual recordIdentifier if it exists
        String relativeUrl = mapping.Relative_URL__c;
        if (!String.isEmpty(recordIdentifier)) {
            relativeUrl = relativeUrl.replace('{{record_id}}', recordIdentifier);
        }

        // Construct the final URL based on the app name and other parameters
        if (mapping.App_Name__c == 'shopify' || mapping.App_Name__c == 'square' || mapping.App_Name__c == 'royalmail') {
            return namedCredentialUrl + '/' + mapping.API_Version__c + relativeUrl;
        } else {
            return null; // Unsupported app name
        }
    }
    
    public static void handleHttpResponse(HttpResponse res, String topicName) {
        try {
            String[] topicNames = new List<String>{topicName};
            String jsonPayload = res.getBody();
            System.debug('Incoming Webhook Request: ' + jsonPayload);
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(jsonPayload);

            if (topicNames.contains('customers')) {
                AccountOrchestrationService.processCustomersFromRestRequest(payload, topicNames);
            }
            if (topicNames.contains('orders')) {
                OrderOrchestrationService.processOrdersFromRestRequest(payload, topicNames);
            }
            if (topicNames.contains('products') || topicNames.contains('variants')) {
                ProductOrchestrationService.processProductsFromRestRequest(payload, new List<String>{'products', 'variants'});
            }
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
        }
    }
}