public with sharing class ShopifyGraphQLHelper {
    
    private static final String NAMED_CREDENTIAL = 'Shopify_Admin_API';
    private static final String API_VERSION = '2026-04';
    
    public class ShopifyGraphQLException extends Exception {}
    
    public static Map<String, Object> execute(String query, Map<String, Object> variables) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/admin/api/' + API_VERSION + '/graphql.json');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        //req.setHeader('X-Shopify-Access-Token', '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');
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'query' => query,
                'variables' => variables == null ? new Map<String, Object>() : variables
                    };
                        
                        req.setBody(JSON.serialize(requestBody));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res == null) {
            throw new ShopifyGraphQLException('No response from Shopify GraphQL.');
        }
        
        Integer statusCode = res.getStatusCode();
        String body = res.getBody();
        
        if (statusCode < 200 || statusCode >= 300) {
            throw new ShopifyGraphQLException('Shopify GraphQL HTTP Error ' + statusCode + ': ' + body);
        }
        
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(body);
        
        if (responseMap.containsKey('errors') && responseMap.get('errors') != null) {
            throw new ShopifyGraphQLException('Shopify GraphQL top-level errors: ' + JSON.serialize(responseMap.get('errors')));
        }
        
        return responseMap;
    }
    
    public static String toProductGid(String shopifyId) {
        if (String.isBlank(shopifyId)) return null;
        if (shopifyId.startsWith('gid://')) return shopifyId;
        return 'gid://shopify/Product/' + shopifyId;
    }
    
    public static String toVariantGid(String shopifyId) {
        if (String.isBlank(shopifyId)) return null;
        if (shopifyId.startsWith('gid://')) return shopifyId;
        return 'gid://shopify/ProductVariant/' + shopifyId;
    }
    
    public static String toCustomerGid(String shopifyId) {
        if (String.isBlank(shopifyId)) return null;
        if (shopifyId.startsWith('gid://')) return shopifyId;
        return 'gid://shopify/Customer/' + shopifyId;
    }
    
    public static String toInventoryItemGid(String shopifyId) {
        if (String.isBlank(shopifyId)) return null;
        if (shopifyId.startsWith('gid://')) return shopifyId;
        return 'gid://shopify/InventoryItem/' + shopifyId;
    }
    
    public static String toLocationGid(String shopifyId) {
        if (String.isBlank(shopifyId)) return null;
        if (shopifyId.startsWith('gid://')) return shopifyId;
        return 'gid://shopify/Location/' + shopifyId;
    }    
    
    public static String extractNumericIdFromGid(String gid) {
        if (String.isBlank(gid)) return null;
        List<String> parts = gid.split('/');
        return parts.isEmpty() ? null : parts[parts.size() - 1];
    }
    public static Map<String, Object> executeAllowPartialData(String query, Map<String, Object> variables) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/admin/api/' + API_VERSION + '/graphql.json');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'query' => query,
                'variables' => variables == null ? new Map<String, Object>() : variables
                    };
                        
                        req.setBody(JSON.serialize(requestBody));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res == null) {
            throw new ShopifyGraphQLException('No response from Shopify GraphQL.');
        }
        
        Integer statusCode = res.getStatusCode();
        String body = res.getBody();
        
        if (statusCode < 200 || statusCode >= 300) {
            throw new ShopifyGraphQLException('Shopify GraphQL HTTP Error ' + statusCode + ': ' + body);
        }
        
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }
    public static String executeRaw(String gid) {
        return null;
    }
}