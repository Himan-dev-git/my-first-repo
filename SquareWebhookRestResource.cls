@RestResource(urlMapping='/square/*')
global without sharing class SquareWebhookRestResource {
    
    @HttpPost
    global static void receiveWebhook() {
        RestRequest req = RestContext.request;
        String body = req.requestBody == null ? null : req.requestBody.toString();
        
        System.debug(LoggingLevel.INFO, 'Square Webhook Body: ' + body);
        
        if (String.isBlank(body)) {
            RestContext.response.statusCode = 200;
            return;
        }
        
        Map<String, Object> payload;
        
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Square webhook JSON parse failed: ' + e.getMessage()
            );
            
            RestContext.response.statusCode = 200;
            return;
        }
        
        String eventType = (String) payload.get('type');
        
        System.debug(
            LoggingLevel.INFO,
            'Square Webhook eventType: ' + eventType
        );
        
        try {
            if (
                eventType == 'payment.created' ||
                eventType == 'payment.updated'
            ) {
                handlePaymentEvent(payload, eventType, body);
                
            } else if (
                eventType == 'terminal.checkout.created' ||
                eventType == 'terminal.checkout.updated'
            ) {
                handleTerminalCheckoutEvent(payload, eventType, body);
                
            } else if (
                eventType == 'order.created' ||
                eventType == 'order.updated'
            ) {
                handleOrderEvent(payload, eventType, body);
                
            } else if (
                eventType == 'refund.created' ||
                eventType == 'refund.updated'
            ) {
                handleRefundEvent(payload, eventType, body);
                
            } else if (
                eventType == 'customer.created' ||
                eventType == 'customer.updated'
            ) {
                handleCustomerEvent(payload, eventType, body);
                
            } else if (eventType == 'catalog.version.updated') {
                handleCatalogEvent(payload, eventType, body);
                
            } else {
                System.debug(
                    LoggingLevel.INFO,
                    'Square webhook received but not handled: ' + eventType
                );
            }
            
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Square webhook handler failed. eventType=' +
                eventType +
                ', error=' +
                e.getMessage()
            );
            
            try {
                SquareCustomerConsentService.logCustomerSyncError(
                    null,
                    eventType,
                    body,
                    e
                );
            } catch (Exception logEx) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Square webhook error logging failed: ' +
                    logEx.getMessage()
                );
            }
        }
        
        RestContext.response.statusCode = 200;
    }
    
    private static void handlePaymentEvent(
        Map<String, Object> payload,
        String eventType,
        String body
    ) {
        String paymentId = extractSquarePaymentId(payload);
        
        System.debug(
            LoggingLevel.INFO,
            'Square payment_id from webhook: ' + paymentId
        );
        
        if (String.isBlank(paymentId)) {
            System.debug(
                LoggingLevel.WARN,
                'Square payment webhook received but payment id was not found.'
            );
            return;
        }
        
        publishSquareWebhookEvent(
            paymentId,
            eventType,
            body,
            payload,
            'Payment'
        );
    }
    
    private static void handleOrderEvent(
        Map<String, Object> payload,
        String eventType,
        String body
    ) {
        String squareOrderId = extractSquareOrderId(payload);
        
        System.debug(
            LoggingLevel.INFO,
            'Square order_id from webhook: ' + squareOrderId
        );
        
        if (String.isBlank(squareOrderId)) {
            System.debug(
                LoggingLevel.WARN,
                'Square order webhook received but order id was not found.'
            );
            return;
        }
        
        publishSquareWebhookEvent(
            squareOrderId,
            eventType,
            body,
            payload,
            'Order'
        );
    }
    
    private static void handleTerminalCheckoutEvent(
        Map<String, Object> payload,
        String eventType,
        String body
    ) {
        String checkoutId = extractSquareTerminalCheckoutId(payload);
        
        System.debug(
            LoggingLevel.INFO,
            'Square terminal checkout_id from webhook: ' + checkoutId
        );
        
        if (String.isBlank(checkoutId)) {
            System.debug(
                LoggingLevel.WARN,
                'Square terminal checkout webhook received but checkout id was not found.'
            );
            return;
        }
        
        publishSquareWebhookEvent(
            checkoutId,
            eventType,
            body,
            payload,
            'Checkout'
        );
    }
    
    private static void handleRefundEvent(
        Map<String, Object> payload,
        String eventType,
        String body
    ) {
        String refundId = extractSquareRefundId(payload);
        
        System.debug(
            LoggingLevel.INFO,
            'Square refund_id from webhook: ' + refundId
        );
        
        if (String.isBlank(refundId)) {
            System.debug(
                LoggingLevel.WARN,
                'Square refund webhook received but refund id was not found.'
            );
            return;
        }
        
        String squareEventId = payload.get('event_id') == null
            ? null
            : String.valueOf(payload.get('event_id'));
        
        Database.SaveResult sr = publishSquareWebhookEvent(
            refundId,
            eventType,
            body,
            payload,
            'Refund'
        );
        
        if (sr.isSuccess()) {
            System.debug(
                LoggingLevel.INFO,
                'Square refund platform event published. refundId=' +
                refundId +
                ', eventType=' +
                eventType
            );
        } else {
            for (Database.Error err : sr.getErrors()) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Square refund platform event publish failed. refundId=' +
                    refundId +
                    ', error=' +
                    err.getMessage()
                );
            }
        }
    }
    
    private static void handleCustomerEvent(
        Map<String, Object> payload,
        String eventType,
        String body
    ) {
        String customerId = extractSquareCustomerId(payload);
        
        System.debug(
            LoggingLevel.INFO,
            'Square customer_id from webhook: ' + customerId
        );
        
        if (String.isNotBlank(customerId)) {
            Square_Customer__e evt = new Square_Customer__e();
            evt.Square_Customer_Id__c = customerId;
            evt.Event_Type__c = eventType;
            evt.Raw_Payload__c = body;
            evt.Source__c = 'Square';
            
            if (payload.containsKey('event_id') && payload.get('event_id') != null) {
                evt.Square_Event_Id__c = String.valueOf(payload.get('event_id'));
            }
            
            Database.SaveResult sr = EventBus.publish(evt);
            
            if (sr.isSuccess()) {
                System.debug(
                    LoggingLevel.INFO,
                    'Square customer platform event published. customerId=' +
                    customerId +
                    ', eventType=' +
                    eventType
                );
            } else {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Square customer platform event publish failed. customerId=' +
                        customerId +
                        ', eventType=' +
                        eventType +
                        ', statusCode=' +
                        err.getStatusCode() +
                        ', fields=' +
                        err.getFields() +
                        ', error=' +
                        err.getMessage()
                    );
                }
            }
        } else {
            System.debug(
                LoggingLevel.WARN,
                'Square customer webhook received but customer id was not found.'
            );
        }
    }
    
    private static void handleCatalogEvent(
        Map<String, Object> payload,
        String eventType,
        String body
    ) {
        System.debug(
            LoggingLevel.INFO,
            'Square catalog event received — publishing platform event. eventType=' +
            eventType
        );
        
        Square_Catalog__e evt = new Square_Catalog__e();
        evt.Event_Type__c = eventType;
        evt.Raw_Payload__c = body;
        evt.Source__c = 'Square';
        
        if (payload != null && payload.containsKey('event_id') && payload.get('event_id') != null) {
            evt.Square_Event_Id__c = String.valueOf(payload.get('event_id'));
        }
        
        if (payload != null) {
            String squareObjectId = extractSquareCatalogObjectId(payload);
            
            if (!String.isBlank(squareObjectId)) {
                evt.Square_Object_Id__c = squareObjectId;
            }
        }
        
        Database.SaveResult sr = EventBus.publish(evt);
        
        if (sr.isSuccess()) {
            System.debug(
                LoggingLevel.INFO,
                'Square catalog platform event published. eventType=' +
                eventType
            );
        } else {
            for (Database.Error err : sr.getErrors()) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Square catalog platform event publish failed. eventType=' +
                    eventType +
                    ', statusCode=' +
                    err.getStatusCode() +
                    ', fields=' +
                    err.getFields() +
                    ', error=' +
                    err.getMessage()
                );
            }
        }
    }
    
    private static String extractSquareCustomerId(
        Map<String, Object> payload
    ) {
        if (payload == null) return null;
        
        Map<String, Object> dataMap =
            (Map<String, Object>) payload.get('data');
        
        if (dataMap == null) return null;
        
        Map<String, Object> objectMap =
            (Map<String, Object>) dataMap.get('object');
        
        if (objectMap == null) return null;
        
        Map<String, Object> customerMap =
            (Map<String, Object>) objectMap.get('customer');
        
        if (
            customerMap != null &&
            customerMap.get('id') != null
        ) {
            return (String) customerMap.get('id');
        }
        
        if (objectMap.get('id') != null) {
            return (String) objectMap.get('id');
        }
        
        return null;
    }
    
    private static String extractSquareOrderId(
        Map<String, Object> payload
    ) {
        if (payload == null) return null;
        
        Map<String, Object> dataMap =
            (Map<String, Object>) payload.get('data');
        
        if (dataMap == null) return null;
        
        if (dataMap.get('id') != null) {
            return (String) dataMap.get('id');
        }
        
        Map<String, Object> objectMap =
            (Map<String, Object>) dataMap.get('object');
        
        if (objectMap == null) return null;
        
        Map<String, Object> orderMap =
            (Map<String, Object>) objectMap.get('order');
        
        if (
            orderMap != null &&
            orderMap.get('id') != null
        ) {
            return (String) orderMap.get('id');
        }
        
        if (objectMap.get('id') != null) {
            return (String) objectMap.get('id');
        }
        
        return null;
    }
    
    private static String extractSquareTerminalCheckoutId(
        Map<String, Object> payload
    ) {
        if (payload == null) {
            return null;
        }
        
        Map<String, Object> dataMap =
            (Map<String, Object>) payload.get('data');
        
        if (dataMap == null) {
            return null;
        }
        
        if (dataMap.get('id') != null) {
            return String.valueOf(dataMap.get('id'));
        }
        
        Map<String, Object> objectMap =
            (Map<String, Object>) dataMap.get('object');
        
        if (objectMap == null) {
            return null;
        }
        
        Map<String, Object> checkoutMap =
            (Map<String, Object>) objectMap.get('checkout');
        
        if (
            checkoutMap != null &&
            checkoutMap.get('id') != null
        ) {
            return String.valueOf(checkoutMap.get('id'));
        }
        
        if (objectMap.get('id') != null) {
            return String.valueOf(objectMap.get('id'));
        }
        
        return null;
    }
    
    private static String extractSquareRefundId(
        Map<String, Object> payload
    ) {
        if (payload == null) return null;
        
        Map<String, Object> dataMap =
            (Map<String, Object>) payload.get('data');
        
        if (dataMap == null) return null;
        
        if (dataMap.get('id') != null) {
            return (String) dataMap.get('id');
        }
        
        Map<String, Object> objectMap =
            (Map<String, Object>) dataMap.get('object');
        
        if (objectMap == null) return null;
        
        Map<String, Object> refundMap =
            (Map<String, Object>) objectMap.get('refund');
        
        if (
            refundMap != null &&
            refundMap.get('id') != null
        ) {
            return (String) refundMap.get('id');
        }
        
        if (objectMap.get('id') != null) {
            return (String) objectMap.get('id');
        }
        
        return null;
    }
    
    private static String extractSquareCatalogObjectId(Map<String, Object> payload) {
        if (payload == null) {
            return null;
        }
        
        Map<String, Object> dataMap = (Map<String, Object>) payload.get('data');
        
        if (dataMap == null) {
            return null;
        }
        
        if (dataMap.get('id') != null) {
            return String.valueOf(dataMap.get('id'));
        }
        
        Map<String, Object> objectMap = (Map<String, Object>) dataMap.get('object');
        
        if (objectMap == null) {
            return null;
        }
        
        Map<String, Object> catalogObjectMap = (Map<String, Object>) objectMap.get('catalog_object');
        
        if (catalogObjectMap != null && catalogObjectMap.get('id') != null) {
            return String.valueOf(catalogObjectMap.get('id'));
        }
        
        if (objectMap.get('id') != null) {
            return String.valueOf(objectMap.get('id'));
        }
        
        return null;
    }
    
    private static String extractSquarePaymentId(
        Map<String, Object> payload
    ) {
        if (payload == null) return null;
        
        Map<String, Object> dataMap =
            (Map<String, Object>) payload.get('data');
        
        if (dataMap == null) return null;
        
        Map<String, Object> objectMap =
            (Map<String, Object>) dataMap.get('object');
        
        if (objectMap == null) return null;
        
        Map<String, Object> paymentMap =
            (Map<String, Object>) objectMap.get('payment');
        
        if (
            paymentMap != null &&
            paymentMap.get('id') != null
        ) {
            return (String) paymentMap.get('id');
        }
        
        if (objectMap.get('id') != null) {
            return (String) objectMap.get('id');
        }
        
        return null;
    }
    
    private static Database.SaveResult publishSquareWebhookEvent(
        String squareObjectId,
        String eventType,
        String body,
        Map<String, Object> payload,
        String objectType
    ) {
        String squareEventId =
            payload != null && payload.get('event_id') != null
            ? String.valueOf(payload.get('event_id'))
            : null;
        
        Square_Webhook_Event__e evt = new Square_Webhook_Event__e();
        evt.Square_Object_Id__c = squareObjectId;
        evt.Event_Type__c = eventType;
        evt.Raw_Payload__c = body;
        evt.Square_Event_Id__c = squareEventId;
        
        if (Square_Webhook_Event__e.SObjectType.getDescribe().fields.getMap().containsKey('Source__c')) {
            evt.put('Source__c', 'Square');
        }
        
        if (Square_Webhook_Event__e.SObjectType.getDescribe().fields.getMap().containsKey('Square_Object_Type__c')) {
            evt.put('Square_Object_Type__c', objectType);
        }
        
        Database.SaveResult sr = EventBus.publish(evt);
        
        if (sr.isSuccess()) {
            System.debug(
                LoggingLevel.INFO,
                'Square webhook platform event published. objectType=' +
                objectType +
                ', squareObjectId=' +
                squareObjectId +
                ', eventType=' +
                eventType
            );
        } else {
            for (Database.Error err : sr.getErrors()) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Square webhook platform event publish failed. objectType=' +
                    objectType +
                    ', squareObjectId=' +
                    squareObjectId +
                    ', eventType=' +
                    eventType +
                    ', statusCode=' +
                    err.getStatusCode() +
                    ', fields=' +
                    err.getFields() +
                    ', error=' +
                    err.getMessage()
                );
            }
        }
        
        return sr;
    }
}