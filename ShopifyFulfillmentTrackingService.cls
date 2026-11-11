public without sharing class ShopifyFulfillmentTrackingService {

    @future(callout=true)
    public static void syncTrackingAsync(List<Id> fulfillmentIds) {
        if (fulfillmentIds == null || fulfillmentIds.isEmpty()) {
            return;
        }

        List<Fulfilment__c> fulfillments = [
            SELECT Id,
                   Shop_ID__c,
                   Tracking_Number__c,
                   Tracking_Company__c,
                   Tracking_URL__c,
                   Status__c
            FROM Fulfilment__c
            WHERE Id IN :fulfillmentIds
              AND Shop_ID__c != null
        ];

        for (Fulfilment__c f : fulfillments) {
            if (String.isBlank(f.Shop_ID__c)) {
                continue;
            }
            if (String.isBlank(f.Tracking_Number__c)) {
                continue;
            }

            sendTrackingUpdate(f);
        }
    }

    private static void sendTrackingUpdate(Fulfilment__c f) {
        
        String fulfillmentGid = f.Shop_ID__c;
        
        if (!fulfillmentGid.startsWith('gid://')) {
            fulfillmentGid = 'gid://shopify/Fulfillment/' + fulfillmentGid;
        }
        
        String mutation =
            'mutation FulfillmentTrackingInfoUpdate(' +
            '  $fulfillmentId: ID!,' +
            '  $trackingInfoInput: FulfillmentTrackingInput!,' +
            '  $notifyCustomer: Boolean' +
            ') {' +
            '  fulfillmentTrackingInfoUpdate(' +
            '    fulfillmentId: $fulfillmentId,' +
            '    trackingInfoInput: $trackingInfoInput,' +
            '    notifyCustomer: $notifyCustomer' +
            '  ) {' +
            '    fulfillment {' +
            '      id' +
            '      status' +
            '      trackingInfo {' +
            '        company' +
            '        number' +
            '        url' +
            '      }' +
            '    }' +
            '    userErrors {' +
            '      field' +
            '      message' +
            '    }' +
            '  }' +
            '}';

        Map<String, Object> trackingInfoInput = new Map<String, Object>();

        trackingInfoInput.put('number', f.Tracking_Number__c);

        if (!String.isBlank(f.Tracking_Company__c)) {
            trackingInfoInput.put('company', normalizeCarrier(f.Tracking_Company__c));
        }

        if (!String.isBlank(f.Tracking_URL__c)) {
            trackingInfoInput.put('url', f.Tracking_URL__c);
        }

        Map<String, Object> variables = new Map<String, Object>{
            'fulfillmentId' => 'gid://shopify/Fulfillment/' + f.Shop_ID__c,
            'trackingInfoInput' => trackingInfoInput,
            'notifyCustomer' => false
        };

        Map<String, Object> body = new Map<String, Object>{
            'query' => mutation,
            'variables' => variables
        };

        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Shopify_Admin_API/admin/api/2026-04/graphql.json');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse res;

        try {
            res = http.send(req);
            System.debug('Tracking update status: ' + res.getStatusCode());
            System.debug('Tracking update body: ' + res.getBody());
        } catch (Exception e) {
            System.debug('Tracking update failed for Fulfilment__c ' + f.Id + ': ' + e.getMessage());
            return;
        }

        if (res == null || res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            return;
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (responseMap == null) {
            return;
        }

        List<Object> topErrors = (List<Object>) responseMap.get('errors');
        if (topErrors != null && !topErrors.isEmpty()) {
            System.debug('Shopify top-level errors: ' + JSON.serialize(topErrors));
            return;
        }

        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        if (dataMap == null) {
            return;
        }

        Map<String, Object> updateMap = (Map<String, Object>) dataMap.get('fulfillmentTrackingInfoUpdate');
        if (updateMap == null) {
            return;
        }

        List<Object> userErrors = (List<Object>) updateMap.get('userErrors');
        if (userErrors != null && !userErrors.isEmpty()) {
            System.debug('Shopify tracking userErrors: ' + JSON.serialize(userErrors));
            return;
        }
    }

    private static String normalizeCarrier(String carrier) {
        if (String.isBlank(carrier)) {
            return null;
        }
        return carrier.trim();
    }
}