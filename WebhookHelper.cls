global without sharing class WebhookHelper {
    
    global class WebhookProcessingException extends Exception {}
    
    public static RestResponse handleWebhookRequest(RestRequest req) {
        RestResponse res = new RestResponse();
        res.addHeader('Content-Type', 'application/json');
        
        try {
            String jsonPayload =
                req.requestBody == null ? null : req.requestBody.toString();
            
            if (String.isBlank(jsonPayload)) {
                throw new WebhookProcessingException('Empty payload');
            }
            
            Object raw = JSON.deserializeUntyped(jsonPayload);
            if (raw == null) {
                throw new WebhookProcessingException('Payload is null after deserialize');
            }
            
            Map<String, Object> payload = (Map<String, Object>) raw;
            
            String topic = getHeaderIgnoreCase(req, 'X-Shopify-Topic');
            if (String.isBlank(topic)) {
                throw new WebhookProcessingException('Missing X-Shopify-Topic header');
            }
            
            topic = topic.toLowerCase();
            
            if (
                topic == 'inventory_levels/update' ||
                topic == 'inventory_levels/connect'
            ) {
                Shopify_Inventory_Level__e evt = new Shopify_Inventory_Level__e(
                    Shopify_Topic__c = topic,
                    Shop_ID__c = getInventoryItemId(payload),
                    Inventory_Item_ID__c = getInventoryItemId(payload),
                    Shopify_Location_ID__c = getInventoryLocationId(payload),
                    Shopify_Payload__c = jsonPayload,
                    Shopify_Webhook_Id__c = getHeaderIgnoreCase(req, 'X-Shopify-Webhook-Id'),
                    Shopify_Shop_Domain__c = getHeaderIgnoreCase(req, 'X-Shopify-Shop-Domain'),
                    Shopify_API_Version__c = getHeaderIgnoreCase(req, 'X-Shopify-Api-Version'),
                    Shopify_HMAC__c = getHeaderIgnoreCase(req, 'X-Shopify-Hmac-Sha256'),
                    Shopify_Triggered_At__c = System.now()
                );
                
                Database.SaveResult sr = EventBus.publish(evt);
                
                if (!sr.isSuccess()) {
                    String errMsg = '';
                    
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' ';
                    }
                    
                    throw new WebhookProcessingException(
                        'Failed to publish Shopify inventory level platform event: ' + errMsg
                    );
                }
            }
            
            else if (
                topic == 'collections/create' ||
                topic == 'collections/update' ||
                topic == 'collections/delete'
            ) {
                Shopify_Collection__e evt = new Shopify_Collection__e(
                    Shopify_Topic__c = topic,
                    Shop_ID__c = getCollectionShopId(payload),
                    Shopify_Payload__c = jsonPayload,
                    Shopify_Webhook_ID__c = getHeaderIgnoreCase(req, 'X-Shopify-Webhook-Id'),
                    Shopify_Shop_Domain__c = getHeaderIgnoreCase(req, 'X-Shopify-Shop-Domain'),
                    Shopify_API_Version__c = getHeaderIgnoreCase(req, 'X-Shopify-Api-Version'),
                    Shopify_HMAC__c = getHeaderIgnoreCase(req, 'X-Shopify-Hmac-Sha256'),
                    Shopify_Triggered_At__c = System.now()
                );
                
                Database.SaveResult sr = EventBus.publish(evt);
                
                if (!sr.isSuccess()) {
                    String errMsg = '';
                    
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' ';
                    }
                    
                    throw new WebhookProcessingException(
                        'Failed to publish Shopify collection platform event: ' + errMsg
                    );
                }
            }
            
            else if (
                topic == 'orders/create' ||
                topic == 'orders/updated' ||
                topic == 'orders/update' ||
                topic == 'orders/cancelled' ||
                topic == 'orders/cancelled' ||
                topic == 'orders/fulfilled' ||
                topic == 'orders/partially_fulfilled'
            ) {
                Shopify_Order__e evt = new Shopify_Order__e(
                    ShopifyTopic__c = topic,
                    Shop_ID__c = getOrderShopId(payload),
                    Shopify_Payload__c = jsonPayload,
                    ShopifyWebhookID__c = getHeaderIgnoreCase(req, 'X-Shopify-Webhook-Id'),
                    ShopifyShopDomain__c = getHeaderIgnoreCase(req, 'X-Shopify-Shop-Domain'),
                    ShopifyAPIVersion__c = getHeaderIgnoreCase(req, 'X-Shopify-Api-Version'),
                    ShopifyHMAC__c = getHeaderIgnoreCase(req, 'X-Shopify-Hmac-Sha256'),
                    ShopifyTriggeredAt__c = System.now()
                );
                
                Database.SaveResult sr = EventBus.publish(evt);
                
                if (!sr.isSuccess()) {
                    String errMsg = '';
                    
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' ';
                    }
                    
                    throw new WebhookProcessingException(
                        'Failed to publish Shopify order platform event: ' + errMsg
                    );
                }
            }                    
            
            else if (
                topic.startsWith('customers/') ||
                topic == 'customers_email_marketing_consent/update' ||
                topic == 'customers_marketing_consent/update' ||
                topic == 'customers_whats_app_marketing_consent/update'
            ) {
                
                Shopify_Customer__e evt = new Shopify_Customer__e(
                    ShopifyTopic__c = topic,
                    Shop_ID__c = getCustomerShopId(payload),
                    Shopify_Payload__c = jsonPayload,
                    ShopifyWebhookID__c = getHeaderIgnoreCase(req, 'X-Shopify-Webhook-Id'),
                    ShopifyShopDomain__c = getHeaderIgnoreCase(req, 'X-Shopify-Shop-Domain'),
                    ShopifyAPIVersion__c = getHeaderIgnoreCase(req, 'X-Shopify-Api-Version'),
                    ShopifyHMAC__c = getHeaderIgnoreCase(req, 'X-Shopify-Hmac-Sha256'),
                    ShopifyTriggeredAt__c = System.now()
                );
                
                Database.SaveResult sr = EventBus.publish(evt);
                
                if (!sr.isSuccess()) {
                    String errMsg = '';
                    
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' ';
                    }
                    
                    throw new WebhookProcessingException(
                        'Failed to publish Shopify customer platform event: ' + errMsg
                    );
                }
            }
            
            else if (
                topic == 'locations/create' ||
                topic == 'locations/update' ||
                topic == 'locations/activate' ||
                topic == 'locations/deactivate'
            ) {
                Shopify_Location__e evt = new Shopify_Location__e(
                    Shopify_Topic__c = topic,
                    Shop_ID__c = getLocationShopId(payload),
                    Shopify_Payload__c = jsonPayload,
                    Shopify_Webhook_ID__c = getHeaderIgnoreCase(req, 'X-Shopify-Webhook-Id'),
                    Shopify_Shop_Domain__c = getHeaderIgnoreCase(req, 'X-Shopify-Shop-Domain'),
                    Shopify_API_Version__c = getHeaderIgnoreCase(req, 'X-Shopify-Api-Version'),
                    Shopify_HMAC__c = getHeaderIgnoreCase(req, 'X-Shopify-Hmac-Sha256'),
                    Shopify_Triggered_At__c = System.now()
                );
                
                Database.SaveResult sr = EventBus.publish(evt);
                
                if (!sr.isSuccess()) {
                    String errMsg = '';
                    
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' ';
                    }
                    
                    throw new WebhookProcessingException(
                        'Failed to publish Shopify location platform event: ' + errMsg
                    );
                }
            }
            
            else if (topic.startsWith('products/')) {
                
                Shopify_Product__e evt = new Shopify_Product__e(
                    ShopifyTopic__c = topic,
                    Shop_ID__c = String.valueOf(payload.get('id')),
                    Shopify_Payload__c = jsonPayload,
                    ShopifyWebhookID__c = getHeaderIgnoreCase(req, 'X-Shopify-Webhook-Id'),
                    ShopifyShopDomain__c = getHeaderIgnoreCase(req, 'X-Shopify-Shop-Domain'),
                    ShopifyAPIVersion__c = getHeaderIgnoreCase(req, 'X-Shopify-Api-Version'),
                    ShopifyHMAC__c = getHeaderIgnoreCase(req, 'X-Shopify-Hmac-Sha256'),
                    ShopifyTriggeredAt__c = System.now()
                );
                
                Database.SaveResult sr = EventBus.publish(evt);
                
                if (!sr.isSuccess()) {
                    String errMsg = '';
                    
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' ';
                    }
                    
                    throw new WebhookProcessingException(
                        'Failed to publish Shopify product platform event: ' + errMsg
                    );
                }
            }
            
            else {
                System.debug(
                    LoggingLevel.INFO,
                    'WebhookHelper: unhandled topic "' + topic + '" acknowledged without processing'
                );
            }
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"status":"ok"}');
            return res;
            
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'WebhookHelper exception: ' + e.getMessage() + ' | ' + e.getStackTraceString()
            );
            
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(
                '{"error":"' + e.getMessage().replace('"', '\\"') + '"}'
            );
            return res;
        }
    }
    
    private static String getOrderShopId(Map<String, Object> payload) {
        if (payload == null) {
            return null;
        }
        
        if (payload.containsKey('id') && payload.get('id') != null) {
            return String.valueOf(payload.get('id'));
        }
        
        if (payload.containsKey('order_id') && payload.get('order_id') != null) {
            return String.valueOf(payload.get('order_id'));
        }
        
        return null;
    }
    
    private static String getHeaderIgnoreCase(RestRequest req, String headerName) {
        if (req == null || req.headers == null || String.isBlank(headerName)) {
            return null;
        }
        
        String lowerTarget = headerName.toLowerCase();
        
        for (String key : req.headers.keySet()) {
            if (key != null && key.toLowerCase() == lowerTarget) {
                return req.headers.get(key);
            }
        }
        
        return null;
    }
    
    private static String getCustomerShopId(Map<String, Object> payload) {
        if (payload == null) {
            return null;
        }
        
        if (payload.containsKey('id') && payload.get('id') != null) {
            return String.valueOf(payload.get('id'));
        }
        
        if (payload.containsKey('customer_id') && payload.get('customer_id') != null) {
            return String.valueOf(payload.get('customer_id'));
        }
        
        return null;
    }
    
    private static String getCollectionShopId(Map<String, Object> payload) {
        if (payload == null) {
            return null;
        }
        
        if (payload.containsKey('id') && payload.get('id') != null) {
            return String.valueOf(payload.get('id'));
        }
        
        if (payload.containsKey('collection_id') && payload.get('collection_id') != null) {
            return String.valueOf(payload.get('collection_id'));
        }
        
        return null;
    }
    
    private static String getInventoryItemId(Map<String, Object> payload) {
        if (payload == null) {
            return null;
        }
        
        if (payload.containsKey('inventory_item_id') && payload.get('inventory_item_id') != null) {
            return normalizeWebhookId(payload.get('inventory_item_id'));
        }
        
        return null;
    }
    
    private static String getInventoryLocationId(Map<String, Object> payload) {
        if (payload == null) {
            return null;
        }
        
        if (payload.containsKey('location_id') && payload.get('location_id') != null) {
            return normalizeWebhookId(payload.get('location_id'));
        }
        
        return null;
    }
    
    private static String getLocationShopId(Map<String, Object> payload) {
        if (payload == null) {
            return null;
        }
        
        if (payload.containsKey('id') && payload.get('id') != null) {
            return normalizeWebhookId(payload.get('id'));
        }
        
        if (payload.containsKey('location_id') && payload.get('location_id') != null) {
            return normalizeWebhookId(payload.get('location_id'));
        }
        
        return null;
    }
    
    private static String normalizeWebhookId(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        
        String value = String.valueOf(rawValue).trim();
        
        if (String.isBlank(value)) {
            return null;
        }
        
        if (value.contains('/')) {
            List<String> parts = value.split('/');
            value = parts[parts.size() - 1];
        }
        
        if (value.endsWith('.0')) {
            value = value.substring(0, value.length() - 2);
        }
        
        if (value.contains('E') || value.contains('e')) {
            Decimal d = Decimal.valueOf(value);
            value = String.valueOf(d.setScale(0));
        }
        
        return value;
    }
}