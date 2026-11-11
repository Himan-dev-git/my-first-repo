public without sharing class ShopifyPlatformEventHandler {
    
    @TestVisible
    private static final Set<String> SUPPORTED_TOPICS = new Set<String>{
        'customers', 'products', 'variants', 'orders' , 'collections'
            };
                
                public static void handleCustomerEvents(List<Shopify_Customer__e> events) {
                    Set<String> seen = new Set<String>();
                    
                    if (events == null || events.isEmpty()) {
                        System.debug('No customer events received.');
                        return;
                    }
                    
                    for (Shopify_Customer__e evt : events) {
                        try {
                            String topicName = normalizeTopic(evt.ShopifyTopic__c, 'customers');
                            
                            /*
* NEW WEBHOOK MODE:
* If the Platform Event has Shopify_Payload__c, process the webhook payload directly.
*/
                            if (!String.isBlank(evt.Shopify_Payload__c)) {
                                processCustomerWebhookPlatformEvent(evt);
                                continue;
                            }
                            
                            /*
* EXISTING MODE:
* No payload means this is the older "fetch from Shopify" signal.
*/
                            String shopId = evt.Shop_ID__c;
                            enqueueFetch(topicName, shopId, seen);
                            
                        } catch (Exception e) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'Shopify customer platform event failed. Topic=' +
                                evt.ShopifyTopic__c +
                                ', ShopId=' +
                                evt.Shop_ID__c +
                                ', Error=' +
                                e.getMessage() +
                                ', Stack=' +
                                e.getStackTraceString()
                            );
                        }
                    }
                }
    
    public static void handleOrderEvents(List<Shopify_Order__e> events) {
        Set<String> seen = new Set<String>();
        
        if (events == null || events.isEmpty()) {
            System.debug('No order events received.');
            return;
        }
        
        for (Shopify_Order__e evt : events) {
            try {
                String topicName = normalizeTopic(evt.ShopifyTopic__c, 'orders');
                
                /*
* NEW WEBHOOK MODE:
* If the Platform Event has Shopify_Payload__c,
* process the webhook payload directly.
*/
                if (!String.isBlank(evt.Shopify_Payload__c)) {
                    processOrderWebhookPlatformEvent(evt);
                    continue;
                }
                
                /*
* EXISTING MODE:
* No payload means this is the old fetch-from-Shopify signal.
*/
                String shopId = evt.Shop_ID__c;
                enqueueFetch(topicName, shopId, seen);
                
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify order platform event failed. Topic=' +
                    evt.ShopifyTopic__c +
                    ', ShopId=' +
                    evt.Shop_ID__c +
                    ', Error=' +
                    e.getMessage() +
                    ', Stack=' +
                    e.getStackTraceString()
                );
            }
        }
    }
    
    public static void handleProductEvents(List<Shopify_Product__e> events) {
        Set<String> seen = new Set<String>();
        
        if (events == null || events.isEmpty()) {
            System.debug('No product events received.');
            return;
        }
        
        Set<String> productShopIdsForSalesInsight = new Set<String>();
        
        for (Shopify_Product__e evt : events) {
            try {
                String rawTopic = evt.ShopifyTopic__c;
                String topicName = normalizeTopic(rawTopic, 'products');
                
                if (rawTopic != null &&
                    rawTopic.toLowerCase() == 'sales_insight_refresh' &&
                    !String.isBlank(evt.Shop_ID__c)) {
                        
                        productShopIdsForSalesInsight.add(evt.Shop_ID__c);
                        continue;
                    }
                
                /*
* New webhook mode:
* Platform Event contains the raw Shopify product webhook payload.
*/
                if (!String.isBlank(evt.Shopify_Payload__c)) {
                    processProductWebhookPlatformEvent(evt);
                    continue;
                }
                
                /*
* Existing mode:
* No payload means this is still the old signal/fetch pattern.
*/
                String shopId = evt.Shop_ID__c;
                enqueueFetch(topicName, shopId, seen);
                
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify product platform event failed. Topic=' +
                    evt.ShopifyTopic__c +
                    ', ShopId=' +
                    evt.Shop_ID__c +
                    ', Error=' +
                    e.getMessage() +
                    ', Stack=' +
                    e.getStackTraceString()
                );
            }
        }
        
        if (!productShopIdsForSalesInsight.isEmpty()) {
            refreshSalesInsightForProductShopIds(productShopIdsForSalesInsight);
        }
    }
    
    public static void handleLocationEvents(List<Shopify_Location__e> events) {
        if (events == null || events.isEmpty()) {
            System.debug('No location events received.');
            return;
        }
        
        for (Shopify_Location__e evt : events) {
            try {
                if (!String.isBlank(evt.Shopify_Payload__c)) {
                    processLocationWebhookPlatformEvent(evt);
                    continue;
                }
                
                System.debug(
                    LoggingLevel.WARN,
                    'Shopify location platform event has no payload. Topic=' +
                    evt.Shopify_Topic__c +
                    ', ShopId=' +
                    evt.Shop_ID__c
                );
                
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify location platform event failed. Topic=' +
                    evt.Shopify_Topic__c +
                    ', ShopId=' +
                    evt.Shop_ID__c +
                    ', Error=' +
                    e.getMessage() +
                    ', Stack=' +
                    e.getStackTraceString()
                );
            }
        }
    }
    
    @TestVisible
    private static void processLocationWebhookPlatformEvent(Shopify_Location__e evt) {
        if (evt == null || String.isBlank(evt.Shopify_Payload__c)) {
            System.debug('Location platform event payload is blank, skipping.');
            return;
        }
        
        String rawTopic = evt.Shopify_Topic__c == null
            ? null
            : evt.Shopify_Topic__c.trim().toLowerCase();
        
        Boolean isSupportedLocationTopic =
            rawTopic != null &&
            (
                rawTopic == 'locations/create' ||
                rawTopic == 'locations/update' ||
                rawTopic == 'locations/activate' ||
                rawTopic == 'locations/deactivate'
            );
        
        if (!isSupportedLocationTopic) {
            System.debug('Unsupported Shopify location topic: ' + rawTopic);
            return;
        }
        
        Map<String, Object> locationPayload =
            (Map<String, Object>) JSON.deserializeUntyped(evt.Shopify_Payload__c);
        
        ShopifyLocationGraphQLService.processLocationWebhook(
            locationPayload,
            rawTopic
        );
    }
    
    @TestVisible
    private static void processProductWebhookPlatformEvent(Shopify_Product__e evt) {
        if (evt == null) {
            return;
        }
        
        String rawTopic = evt.ShopifyTopic__c == null
            ? null
            : evt.ShopifyTopic__c.trim().toLowerCase();
        
        if (rawTopic == 'products/delete') {
            processProductDeletePlatformEvent(evt);
            return;
        }
        
        if (rawTopic == null || !rawTopic.startsWith('products/')) {
            System.debug(
                'Unsupported Shopify product platform event topic: ' + rawTopic
            );
            return;
        }
        
        String shopifyProductId = evt.Shop_ID__c;
        
        if (String.isBlank(shopifyProductId) && !String.isBlank(evt.Shopify_Payload__c)) {
            try {
                Map<String, Object> payload =
                    (Map<String, Object>) JSON.deserializeUntyped(evt.Shopify_Payload__c);
                
                if (payload != null && payload.get('id') != null) {
                    shopifyProductId = String.valueOf(payload.get('id'));
                }
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Unable to parse product webhook payload for product id: ' +
                    e.getMessage()
                );
            }
        }
        
        if (String.isBlank(shopifyProductId)) {
            System.debug('Product platform event missing Shopify product id.');
            return;
        }
        
        ShopifyProductGraphQLService.fetchAndProcessProductForInboundSyncAsync(
            shopifyProductId
        );
    }
    
    @TestVisible
    private static void processProductDeletePlatformEvent(Shopify_Product__e evt) {
        if (evt == null || String.isBlank(evt.Shopify_Payload__c)) {
            return;
        }
        
        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(evt.Shopify_Payload__c);
        
        if (payload == null || payload.get('id') == null) {
            System.debug('Product delete event missing Shopify product id.');
            return;
        }
        
        String shopifyProductId = String.valueOf(payload.get('id'));
        
        List<Product2> productsToDeactivate = [
            SELECT Id, IsActive, Updated_by_Integration__c
            FROM Product2
            WHERE Shop_ID__c = :shopifyProductId
        ];
        
        for (Product2 p : productsToDeactivate) {
            p.IsActive = false;
            p.Updated_by_Integration__c = true;
        }
        
        if (!productsToDeactivate.isEmpty()) {
            update productsToDeactivate;
        }
    }
    
    @TestVisible
    private static void refreshSalesInsightForProductShopIds(Set<String> productShopIds) {
        if (productShopIds == null || productShopIds.isEmpty()) {
            return;
        }
        
        Set<Id> productIds = new Set<Id>();
        
        for (Product2 p : [
            SELECT Id
            FROM Product2
            WHERE Shop_ID__c IN :productShopIds
        ]) {
            productIds.add(p.Id);
        }
        
        if (!productIds.isEmpty()) {
            try {
                ProductSalesInsightService.refreshForProducts(productIds);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Sales insight refresh from platform event failed: ' +
                    e.getMessage()
                );
            }
        }
    }
    
    @TestVisible
    private static void processCustomerWebhookPlatformEvent(Shopify_Customer__e evt) {
        if (evt == null) {
            return;
        }
        
        if (String.isBlank(evt.Shopify_Payload__c)) {
            System.debug('Customer platform event payload is blank, skipping.');
            return;
        }
        
        String rawTopic = evt.ShopifyTopic__c == null
            ? null
            : evt.ShopifyTopic__c.trim().toLowerCase();
        
        if (rawTopic == 'customers/delete') {
            processCustomerDeletePlatformEvent(evt);
            return;
        }
        
        Boolean isSupportedCustomerTopic =
            rawTopic != null &&
            (
                rawTopic.startsWith('customers/') ||
                rawTopic == 'customers_email_marketing_consent/update' ||
                rawTopic == 'customers_marketing_consent/update' ||
                rawtopic == 'customers_whats_app_marketing_consent/update'
            );
        
        if (!isSupportedCustomerTopic) {
            System.debug(
                'Unsupported Shopify customer platform event topic: ' + rawTopic
            );
            return;
        }
        
        Object raw = JSON.deserializeUntyped(evt.Shopify_Payload__c);
        
        if (raw == null) {
            System.debug('Customer platform event payload deserialized to null.');
            return;
        }
        
        Map<String, Object> customerPayload = (Map<String, Object>) raw;
        
        AccountOrchestrationService.processCustomersFromRestRequest(
            new Map<String, Object>{ 'customer' => customerPayload },
            new String[]{ 'customers' }
        );
    }
    
    @TestVisible
    private static void processCustomerDeletePlatformEvent(Shopify_Customer__e evt) {
        if (evt == null || String.isBlank(evt.Shopify_Payload__c)) {
            return;
        }
        
        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(evt.Shopify_Payload__c);
        
        if (payload == null) {
            return;
        }
        
        String shopifyCustomerId;
        
        if (payload.containsKey('id') && payload.get('id') != null) {
            shopifyCustomerId = String.valueOf(payload.get('id'));
        } else if (payload.containsKey('customer_id') && payload.get('customer_id') != null) {
            shopifyCustomerId = String.valueOf(payload.get('customer_id'));
        }
        
        if (String.isBlank(shopifyCustomerId)) {
            System.debug('Customer delete event missing Shopify customer id.');
            return;
        }
        
        List<Account> accountsToUpdate = [
            SELECT Id, Updated_by_Integration__c
            FROM Account
            WHERE Shop_ID__c = :shopifyCustomerId
        ];
        
        for (Account acc : accountsToUpdate) {
            acc.Updated_by_Integration__c = true;
            
            /*
* Optional:
* If you have a field like Shopify_Deleted__c, Status__c, or Active__c,
* set it here.
*
* acc.Shopify_Deleted__c = true;
*/
        }
        
        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
    
    @TestVisible
    private static void enqueueFetch(String topicName, String shopId, Set<String> seen) {
        if (String.isBlank(topicName)) {
            System.debug('ShopifyPlatformEventHandler: topicName is blank, skipping.');
            return;
        }
        
        if (String.isBlank(shopId)) {
            System.debug('ShopifyPlatformEventHandler: shopId is blank for topic ' + topicName + ', skipping.');
            return;
        }
        
        if (!SUPPORTED_TOPICS.contains(topicName)) {
            System.debug('ShopifyPlatformEventHandler: unsupported topic ' + topicName + ', skipping.');
            return;
        }
        
        String requestName = getRequestName(topicName);
        if (String.isBlank(requestName)) {
            System.debug('ShopifyPlatformEventHandler: no request name for topic ' + topicName + ', skipping.');
            return;
        }
        
        String dedupeKey = topicName + '|' + shopId;
        if (seen.contains(dedupeKey)) {
            System.debug('ShopifyPlatformEventHandler: duplicate event in same batch ' + dedupeKey + ', skipping.');
            return;
        }
        seen.add(dedupeKey);
        
        System.debug('ShopifyPlatformEventHandler: fetching Shopify payload. topic=' + topicName + ', shopId=' + shopId + ', requestName=' + requestName);
        
        RestHelper.handleRestRequestAsync(
            'shopify',
            requestName,
            shopId,
            topicName,
            ''
        );
    }
    
    @TestVisible
    private static String normalizeTopic(String rawTopic, String fallbackTopic) {
        if (String.isBlank(rawTopic)) {
            return fallbackTopic;
        }
        
        String topicName = rawTopic.trim().toLowerCase();
        
        if (topicName.contains('/')) {
            topicName = topicName.substringBefore('/');
        }
        
        if (topicName == 'customer') return 'customers';
        if (topicName == 'product') return 'products';
        if (topicName == 'variant') return 'variants';
        if (topicName == 'order') return 'orders';
        
        return topicName;
    }
    
    @TestVisible
    private static void processOrderWebhookPlatformEvent(Shopify_Order__e evt) {
        if (evt == null || String.isBlank(evt.Shopify_Payload__c)) {
            System.debug('Order platform event payload is blank, skipping.');
            return;
        }
        
        String rawTopic = evt.ShopifyTopic__c == null
            ? null
            : evt.ShopifyTopic__c.trim().toLowerCase();
        
        if (rawTopic == 'orders/delete' || rawTopic == 'orders/deleted') {
            processOrderDeletePlatformEvent(evt);
            return;
        }
        
        Boolean isSupportedOrderTopic =
            rawTopic != null &&
            (
                rawTopic == 'orders/create' ||
                rawTopic == 'orders/updated' ||
                rawTopic == 'orders/update' ||
                rawTopic == 'orders/cancelled' ||
                rawTopic == 'orders/fulfilled' ||
                rawTopic == 'orders/partially_fulfilled'
            );
        
        if (!isSupportedOrderTopic) {
            System.debug('Unsupported Shopify order topic: ' + rawTopic);
            return;
        }
        
        Object raw = JSON.deserializeUntyped(evt.Shopify_Payload__c);
        
        if (raw == null) {
            System.debug('Order platform event payload deserialized to null.');
            return;
        }
        
        Map<String, Object> orderPayload = (Map<String, Object>) raw;
        
        OrderOrchestrationService.processOrdersFromRestRequest(
            new Map<String, Object>{ 'order' => orderPayload },
            new String[]{ 'orders', 'line_items', 'fulfillments' }
        );
    }
    
    @TestVisible
    private static void processOrderDeletePlatformEvent(Shopify_Order__e evt) {
        if (evt == null || String.isBlank(evt.Shopify_Payload__c)) {
            return;
        }
        
        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(evt.Shopify_Payload__c);
        
        if (payload == null) {
            return;
        }
        
        String shopifyOrderId;
        
        if (payload.containsKey('id') && payload.get('id') != null) {
            shopifyOrderId = String.valueOf(payload.get('id'));
        } else if (payload.containsKey('order_id') && payload.get('order_id') != null) {
            shopifyOrderId = String.valueOf(payload.get('order_id'));
        }
        
        if (String.isBlank(shopifyOrderId)) {
            System.debug('Order delete event missing Shopify order id.');
            return;
        }
        
        List<Order> ordersToUpdate = [
            SELECT Id, Status
            FROM Order
            WHERE Shop_ID__c = :shopifyOrderId
        ];
        
        for (Order ord : ordersToUpdate) {
            /*
* Choose the status that exists in your org.
* If "Cancelled" is not valid for Order.Status, use your actual allowed status.
*/
            ord.Status = 'Cancelled';
        }
        
        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }
    }
    
    public static void handleCollectionEvents(List<Shopify_Collection__e> events) {
        Set<String> seen = new Set<String>();
        
        if (events == null || events.isEmpty()) {
            System.debug('No collection events received.');
            return;
        }
        
        for (Shopify_Collection__e evt : events) {
            try {
                String topicName = normalizeTopic(evt.Shopify_Topic__c, 'collections');
                
                /*
* NEW WEBHOOK MODE:
* If the event has raw Shopify payload, process directly.
*/
                if (!String.isBlank(evt.Shopify_Payload__c)) {
                    processCollectionWebhookPlatformEvent(evt);
                    continue;
                }
                
                /*
* OLD SIGNAL MODE:
* If no payload exists, keep old fetch behavior if you support it.
*/
                String shopId = evt.Shop_ID__c;
                enqueueFetch(topicName, shopId, seen);
                
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify collection platform event failed. Topic=' +
                    evt.Shopify_Topic__c +
                    ', ShopId=' +
                    evt.Shop_ID__c +
                    ', Error=' +
                    e.getMessage() +
                    ', Stack=' +
                    e.getStackTraceString()
                );
            }
        }
    }
    
    @TestVisible
    private static void processCollectionWebhookPlatformEvent(Shopify_Collection__e evt) {
        if (evt == null || String.isBlank(evt.Shopify_Payload__c)) {
            System.debug('Collection platform event payload is blank, skipping.');
            return;
        }
        
        String rawTopic = evt.Shopify_Topic__c == null
            ? null
            : evt.Shopify_Topic__c.trim().toLowerCase();
        
        Boolean isSupportedCollectionTopic =
            rawTopic != null &&
            (
                rawTopic == 'collections/create' ||
                rawTopic == 'collections/update' ||
                rawTopic == 'collections/delete'
            );
        
        if (!isSupportedCollectionTopic) {
            System.debug('Unsupported Shopify collection topic: ' + rawTopic);
            return;
        }
        
        Map<String, Object> collectionPayload =
            (Map<String, Object>) JSON.deserializeUntyped(evt.Shopify_Payload__c);
        
        if (rawTopic == 'collections/delete') {
            CollectionOrchestrationService.processCollectionDeleteWebhook(collectionPayload);
            return;
        }
        
        CollectionOrchestrationService.processCollectionWebhook(collectionPayload);
    }
    
    public static void handleInventoryLevelEvents(List<Shopify_Inventory_Level__e> events) {
        if (events == null || events.isEmpty()) {
            System.debug('No inventory level events received.');
            return;
        }
        
        for (Shopify_Inventory_Level__e evt : events) {
            try {
                if (!String.isBlank(evt.Shopify_Payload__c)) {
                    processInventoryLevelWebhookPlatformEvent(evt);
                    continue;
                }
                
                System.debug(
                    LoggingLevel.WARN,
                    'Inventory level platform event has no payload. Topic=' +
                    evt.Shopify_Topic__c +
                    ', InventoryItemId=' +
                    evt.Inventory_Item_ID__c +
                    ', LocationId=' +
                    evt.Shopify_Location_ID__c
                );
                
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify inventory level platform event failed. Topic=' +
                    evt.Shopify_Topic__c +
                    ', InventoryItemId=' +
                    evt.Inventory_Item_ID__c +
                    ', LocationId=' +
                    evt.Shopify_Location_ID__c +
                    ', Error=' +
                    e.getMessage() +
                    ', Stack=' +
                    e.getStackTraceString()
                );
            }
        }
    }
    
    @TestVisible
    private static void processInventoryLevelWebhookPlatformEvent(Shopify_Inventory_Level__e evt) {
        if (evt == null || String.isBlank(evt.Shopify_Payload__c)) {
            System.debug('Inventory level platform event payload is blank, skipping.');
            return;
        }
        
        String rawTopic = evt.Shopify_Topic__c == null
            ? null
            : evt.Shopify_Topic__c.trim().toLowerCase();
        
        Boolean isSupportedInventoryTopic =
            rawTopic != null &&
            (
                rawTopic == 'inventory_levels/update' ||
                rawTopic == 'inventory_levels/connect'
            );
        
        if (!isSupportedInventoryTopic) {
            System.debug('Unsupported Shopify inventory level topic: ' + rawTopic);
            return;
        }
        
        Map<String, Object> inventoryPayload =
            (Map<String, Object>) JSON.deserializeUntyped(evt.Shopify_Payload__c);
        
        InventoryLevelOrchestrationService.processInventoryLevelWebhook(inventoryPayload);
    }
    
    @TestVisible
    private static String getRequestName(String topicName) {
        switch on topicName {
            when 'customers' {
                return 'SingleCustomer';
            }
            when 'products' {
                return 'SingleProduct';
            }
            when 'orders' {
                return 'SingleOrder';
            }
            when 'collections' {
                return 'SingleCollection';
            }
            when else {
                return null;
            }
        }
    }
}