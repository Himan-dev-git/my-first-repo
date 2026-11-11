public with sharing class ShopifyFulfillmentCreateService {
    
    @future(callout=true)
    public static void createFulfillmentsAsync(List<Id> fulfillmentIds) {
        if (fulfillmentIds == null || fulfillmentIds.isEmpty()) {
            return;
        }
        
        List<Fulfilment__c> fulfillments = [
            SELECT Id,
            Shop_ID__c,
            Status__c, 
            Tracking_Number__c,
            Tracking_Company__c,
            Tracking_URL__c,
            Order__c,
            Order__r.Shop_ID__c
            FROM Fulfilment__c
            WHERE Id IN :fulfillmentIds
        ];
        
        for (Fulfilment__c f : fulfillments) {
            if (!String.isBlank(f.Shop_ID__c)) {
                continue;
            }
            if (f.Order__c == null || f.Order__r == null || String.isBlank(f.Order__r.Shop_ID__c)) {
                System.debug('ShopifyFulfillmentCreateService: Order or Shopify Order ID missing for Fulfilment ' + f.Id);
                continue;
            }
            
            String fulfillmentOrderId = fetchOpenFulfillmentOrderId(f.Order__r.Shop_ID__c);
            if (String.isBlank(fulfillmentOrderId)) {
                System.debug('ShopifyFulfillmentCreateService: No open fulfillment order found for Shopify Order ' + f.Order__r.Shop_ID__c);
                continue;
            }
            
            String createdFulfillmentId = createFulfillment(
                fulfillmentOrderId,
                f.Tracking_Number__c,
                f.Tracking_Company__c,
                f.Tracking_URL__c
            );
            
            if (!String.isBlank(createdFulfillmentId)) {
                List<SObject> updates = new List<SObject>();
                
                updates.add(
                    new Fulfilment__c(
                        Id = f.Id,
                        Shop_ID__c = createdFulfillmentId,
                        Status__c = 'Success'
                    )
                );
                
                // Auto-mark Order fulfilled after Shopify accepts fulfillment
                if (f.Order__c != null) {
                    
                    updates.add(
                        new Order(
                            Id = f.Order__c,
                            Fulfillment_Status__c = 'Fulfilled'
                        )
                    );
                }
                
                update updates;
            }
        }
    }
    
    private static String fetchOpenFulfillmentOrderId(String shopifyOrderId) {
        String query =
            'query getFulfillmentOrders($id: ID!) {' +
            '  order(id: $id) {' +
            '    fulfillmentOrders(first: 10) {' +
            '      nodes {' +
            '        id ' +
            '        status ' +
            '      }' +
            '    }' +
            '  }' +
            '}';
        
        Map<String, Object> body = new Map<String, Object>{
            'query' => query,
                'variables' => new Map<String, Object>{
                    'id' => 'gid://shopify/Order/' + shopifyOrderId
                        }
        };
            
            HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Shopify_Admin_API/admin/api/2026-04/graphql.json');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));
        
        HttpResponse res = (new Http()).send(req);
        System.debug('fetchOpenFulfillmentOrderId response: ' + res.getBody());
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            return null;
        }
        
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (responseMap == null) return null;
        
        List<Object> errors = (List<Object>) responseMap.get('errors');
        if (errors != null && !errors.isEmpty()) {
            System.debug('fetchOpenFulfillmentOrderId top-level errors: ' + JSON.serialize(errors));
            return null;
        }
        
        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        if (dataMap == null) return null;
        
        Map<String, Object> orderMap = (Map<String, Object>) dataMap.get('order');
        if (orderMap == null) return null;
        
        Map<String, Object> fulfillmentOrdersMap = (Map<String, Object>) orderMap.get('fulfillmentOrders');
        if (fulfillmentOrdersMap == null) return null;
        
        List<Object> nodes = (List<Object>) fulfillmentOrdersMap.get('nodes');
        if (nodes == null || nodes.isEmpty()) return null;
        
        for (Object nodeObj : nodes) {
            Map<String, Object> node = (Map<String, Object>) nodeObj;
            String status = String.valueOf(node.get('status'));
            if (status == 'OPEN' || status == 'IN_PROGRESS') {
                return extractNumericId(String.valueOf(node.get('id')));
            }
        }
        
        return null;
    }
    
    private static String createFulfillment(
        String fulfillmentOrderId,
        String trackingNumber,
        String trackingCompany,
        String trackingUrl
    ) {
        String mutation =
            'mutation fulfillmentCreate($fulfillment: FulfillmentInput!) {' +
            '  fulfillmentCreate(fulfillment: $fulfillment) {' +
            '    fulfillment {' +
            '      id ' +
            '      status ' +
            '      trackingInfo {' +
            '        company ' +
            '        number ' +
            '        url ' +
            '      }' +
            '    }' +
            '    userErrors {' +
            '      field ' +
            '      message ' +
            '    }' +
            '  }' +
            '}';
        
        Map<String, Object> fulfillmentInput = new Map<String, Object>();
        fulfillmentInput.put(
            'lineItemsByFulfillmentOrder',
            new List<Object>{
                new Map<String, Object>{
                    'fulfillmentOrderId' => 'gid://shopify/FulfillmentOrder/' + fulfillmentOrderId
                        }
            }
        );
        fulfillmentInput.put('notifyCustomer', false);
        
        Map<String, Object> trackingInfo = new Map<String, Object>();
        if (!String.isBlank(trackingNumber)) trackingInfo.put('number', trackingNumber);
        if (!String.isBlank(trackingCompany)) trackingInfo.put('company', trackingCompany.trim());
        if (!String.isBlank(trackingUrl)) trackingInfo.put('url', trackingUrl);
        
        if (!trackingInfo.isEmpty()) {
            fulfillmentInput.put('trackingInfo', trackingInfo);
        }
        
        Map<String, Object> body = new Map<String, Object>{
            'query' => mutation,
                'variables' => new Map<String, Object>{
                    'fulfillment' => fulfillmentInput
                        }
        };
            
            HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Shopify_Admin_API/admin/api/2026-04/graphql.json');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));
        
        HttpResponse res = (new Http()).send(req);
        System.debug('createFulfillment response: ' + res.getBody());
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            return null;
        }
        
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (responseMap == null) return null;
        
        List<Object> errors = (List<Object>) responseMap.get('errors');
        if (errors != null && !errors.isEmpty()) {
            System.debug('createFulfillment top-level errors: ' + JSON.serialize(errors));
            return null;
        }
        
        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        if (dataMap == null) return null;
        
        Map<String, Object> createMap = (Map<String, Object>) dataMap.get('fulfillmentCreate');
        if (createMap == null) return null;
        
        List<Object> userErrors = (List<Object>) createMap.get('userErrors');
        if (userErrors != null && !userErrors.isEmpty()) {
            System.debug('createFulfillment userErrors: ' + JSON.serialize(userErrors));
            return null;
        }
        
        Map<String, Object> fulfillmentMap = (Map<String, Object>) createMap.get('fulfillment');
        if (fulfillmentMap == null) return null;
        
        return extractNumericId(String.valueOf(fulfillmentMap.get('id')));
    }
    
    private static String extractNumericId(String gid) {
        if (String.isBlank(gid)) {
            return null;
        }
        List<String> parts = gid.split('/');
        return parts.isEmpty() ? null : parts[parts.size() - 1];
    }
}