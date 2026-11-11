public with sharing class OrderTriggerHandler {
    
    public static void afterInsert(List<Order> newOrders) {
        if (newOrders == null || newOrders.isEmpty()) {
            return;
        }
        
        List<Id> orderIdsToDeduct = new List<Id>();
        
        for (Order ord : newOrders) {
            if (ord == null || ord.Id == null) {
                continue;
            }
            
            if (shouldDeductInventory(ord)) {
                orderIdsToDeduct.add(ord.Id);
            }
        }
        
        if (!orderIdsToDeduct.isEmpty()) {
            OrderInventoryAdjustmentService.deduct(orderIdsToDeduct);
        }
    }
    
    public static void afterUpdate(
        List<Order> newOrders,
        Map<Id, Order> oldMap
    ) {
        if (newOrders == null || newOrders.isEmpty() || oldMap == null) {
            return;
        }
        
        List<Id> orderIdsToRestore = new List<Id>();
        Set<Id> orderIdsToUpdateInShopify = new Set<Id>();
        
        for (Order newOrd : newOrders) {
            if (newOrd == null || newOrd.Id == null) {
                continue;
            }
            
            Order oldOrd = oldMap.get(newOrd.Id);
            
            if (oldOrd == null) {
                continue;
            }
            
            /*
* EXISTING SHOPIFY ORDER UPDATE:
*
* Only send updates to Shopify when the Salesforce Order already
* contains a Shopify Order Id.
*
* This service is UPDATE ONLY.
* It must never create a Shopify Order.
*/
            if (
                !String.isBlank(newOrd.Shop_ID__c) &&
                (
                    newOrd.Financial_Status__c != oldOrd.Financial_Status__c ||
                  //newOrd.Fulfillment_Status__c != oldOrd.Fulfillment_Status__c || -- Commenting for outbound Order sync
                    newOrd.ShippingStreet != oldOrd.ShippingStreet ||
                    newOrd.ShippingCity != oldOrd.ShippingCity ||
                    newOrd.ShippingState != oldOrd.ShippingState ||
                    newOrd.ShippingPostalCode != oldOrd.ShippingPostalCode ||
                    newOrd.ShippingCountry != oldOrd.ShippingCountry
                )
            ) {
                orderIdsToUpdateInShopify.add(newOrd.Id);
            }
            
            Boolean wasRefunded = isRefundedOrCancelled(oldOrd);
            Boolean isNowRefunded = isRefundedOrCancelled(newOrd);
            
            if (!wasRefunded && isNowRefunded) {
                orderIdsToRestore.add(newOrd.Id);
            }
        }
        
        if (!orderIdsToRestore.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                '### REFUND RESTORE USING METADATA ROUTE ### orderIds=' +
                orderIdsToRestore
            );
            
            OrderInventoryAdjustmentService.restore(orderIdsToRestore);
        }
        
        if (!orderIdsToUpdateInShopify.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                '### SHOPIFY EXISTING ORDER UPDATE SYNC ### orderIds=' +
                orderIdsToUpdateInShopify
            );
            
            ShopifyOrderUpdateGraphQLService.syncOrderUpdatesAsync(
                new List<Id>(orderIdsToUpdateInShopify)
            );
        }
    }
    
    private static Boolean isRefundedOrCancelled(Order ord) {
        if (ord == null) {
            return false;
        }
        
        String statusValue = normalize(ord.Status);
        String financialStatusValue = normalize(ord.Financial_Status__c);
        String fulfillmentStatusValue = normalize(ord.Fulfillment_Status__c);
        
        return statusValue == 'cancelled' ||
            statusValue == 'canceled' ||
            financialStatusValue == 'refunded' ||
            financialStatusValue == 'partially_refunded' ||
            fulfillmentStatusValue == 'cancelled' ||
            fulfillmentStatusValue == 'canceled';
    }
    
    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }
    
    public static void adjustInventoryForOrders(List<Id> orderIds, Integer direction) {
        OrderInventoryAdjustmentService.adjust(orderIds, direction);
    }
    
    private static Boolean shouldDeductInventory(Order ord) {
        if (ord == null) {
            return false;
        }
        
        if (String.isBlank(ord.Type)) {
            return false;
        }
        
        if (isRefundedOrCancelled(ord)) {
            return false;
        }
        
        return true;
    }
}