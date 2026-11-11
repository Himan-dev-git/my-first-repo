public class ShopifyOrderGraphQLService {
    
    @future(callout=true)
    public static void syncOrdersAsync(List<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return;
        }
        
        List<Order> orders = [
            SELECT Id,
                   OrderNumber,
                   Shop_ID__c,
                   Status,
                   StatusCode,
                   EffectiveDate,
                   CurrencyIsoCode,
                   ShippingStreet,
                   ShippingCity,
                   ShippingState,
                   ShippingPostalCode,
                   ShippingCountry,
                   Account.PersonEmail,
                   Account.FirstName,
                   Account.LastName,
                   Account.Name,
                   Financial_Status__c
            FROM Order
            WHERE Id IN :orderIds
        ];
        
        if (orders.isEmpty()) {
            return;
        }
        
        Map<Id, List<OrderItem>> orderItemsByOrderId = new Map<Id, List<OrderItem>>();
        for (OrderItem oi : [
            SELECT Id,
                   OrderId,
                   Quantity,
                   UnitPrice,
                   Product2Id,
                   Product2.Name,
                   Product2.Shop_ID__c,
                   Product2.Type__c,
                   Shop_ID__c
            FROM OrderItem
            WHERE OrderId IN :orderIds
        ]) {
            if (!orderItemsByOrderId.containsKey(oi.OrderId)) {
                orderItemsByOrderId.put(oi.OrderId, new List<OrderItem>());
            }
            orderItemsByOrderId.get(oi.OrderId).add(oi);
        }
        
        List<Order> ordersToUpdate = new List<Order>();
        List<OrderItem> orderItemsToUpdate = new List<OrderItem>();
        
        for (Order ord : orders) {
            if (!String.isBlank(ord.Shop_ID__c)) {
                continue;
            }
            
            List<OrderItem> items = orderItemsByOrderId.get(ord.Id);
            if (items == null || items.isEmpty()) {
                System.debug('ShopifyOrderGraphQLService: No OrderItems found for Order ' + ord.Id);
                continue;
            }
            
            List<Object> lineItems = new List<Object>();
            List<Id> sourceOrderItemIds = new List<Id>();
            
            for (OrderItem oi : items) {
                if (oi.Product2 == null || String.isBlank(oi.Product2.Shop_ID__c)) {
                    System.debug('ShopifyOrderGraphQLService: Missing Shopify variant Shop_ID__c for OrderItem ' + oi.Id);
                    continue;
                }
                
                Map<String, Object> lineItem = new Map<String, Object>();
                lineItem.put('variantId', 'gid://shopify/ProductVariant/' + oi.Product2.Shop_ID__c);
                lineItem.put('quantity', Integer.valueOf(String.valueOf(oi.Quantity)));
                
                Map<String, Object> priceSet = new Map<String, Object>();
                Map<String, Object> shopMoney = new Map<String, Object>();
                shopMoney.put('amount', oi.UnitPrice);
                shopMoney.put('currencyCode', ord.CurrencyIsoCode);
                priceSet.put('shopMoney', shopMoney);
                lineItem.put('priceSet', priceSet);
                
                lineItems.add(lineItem);
                sourceOrderItemIds.add(oi.Id);
            }
            
            if (lineItems.isEmpty()) {
                System.debug('ShopifyOrderGraphQLService: No valid line items found for Order ' + ord.Id);
                continue;
            }
            
            Map<String, Object> orderInput = new Map<String, Object>();
            orderInput.put('currency', ord.CurrencyIsoCode);
            orderInput.put('lineItems', lineItems);
            
            if (ord.Account != null && !String.isBlank(ord.Account.PersonEmail)) {
                orderInput.put('email', ord.Account.PersonEmail);
            }
            
            Map<String, Object> shippingAddress = new Map<String, Object>();
            if (ord.Account != null) {
                shippingAddress.put('firstName', ord.Account.FirstName);
                shippingAddress.put('lastName', ord.Account.LastName);
            }
            shippingAddress.put('address1', ord.ShippingStreet);
            shippingAddress.put('city', ord.ShippingCity);
            shippingAddress.put('province', ord.ShippingState);
            shippingAddress.put('zip', ord.ShippingPostalCode);
            shippingAddress.put('country', ord.ShippingCountry);
            
            orderInput.put('shippingAddress', shippingAddress);
            orderInput.put('billingAddress', shippingAddress);
            
            String mutation =
                'mutation orderCreate($order: OrderCreateOrderInput!, $options: OrderCreateOptionsInput) {' +
                '  orderCreate(order: $order, options: $options) {' +
                '    userErrors { field message }' +
                '    order {' +
                '      id ' +
                '      name ' +
                '      createdAt ' +
                '      lineItems(first: 50) {' +
                '        nodes {' +
                '          id ' +
                '          quantity ' +
                '          title ' +
                '        }' +
                '      }' +
                '    }' +
                '  }' +
                '}';
            
            Map<String, Object> variables = new Map<String, Object>{
                'order' => orderInput,
                'options' => new Map<String, Object>()
            };
            
            Map<String, Object> requestBody = new Map<String, Object>{
                'query' => mutation,
                'variables' => variables
            };
            
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setEndpoint('callout:Shopify_Admin_API/admin/api/2026-04/graphql.json');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(requestBody));
            
            Http http = new Http();
            HttpResponse res;
            
            try {
                res = http.send(req);
                System.debug('ShopifyOrderGraphQLService response status: ' + res.getStatusCode());
                System.debug('ShopifyOrderGraphQLService response body: ' + res.getBody());
            } catch (Exception e) {
                System.debug('ShopifyOrderGraphQLService callout failed for Order ' + ord.Id + ': ' + e.getMessage());
                continue;
            }
            
            if (res == null || res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                continue;
            }
            
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (responseMap == null || !responseMap.containsKey('data')) {
                continue;
            }
            
            Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
            if (dataMap == null || !dataMap.containsKey('orderCreate')) {
                continue;
            }
            
            Map<String, Object> orderCreateMap = (Map<String, Object>) dataMap.get('orderCreate');
            if (orderCreateMap == null) {
                continue;
            }
            
            List<Object> userErrors = (List<Object>) orderCreateMap.get('userErrors');
            if (userErrors != null && !userErrors.isEmpty()) {
                System.debug('ShopifyOrderGraphQLService userErrors for Order ' + ord.Id + ': ' + JSON.serialize(userErrors));
                continue;
            }
            
            Map<String, Object> createdOrderMap = (Map<String, Object>) orderCreateMap.get('order');
            if (createdOrderMap == null || !createdOrderMap.containsKey('id')) {
                continue;
            }
            
            String shopifyGid = String.valueOf(createdOrderMap.get('id'));
            String shopifyNumericId = extractNumericId(shopifyGid);
            
            if (!String.isBlank(shopifyNumericId)) {
                ordersToUpdate.add(new Order(
                    Id = ord.Id,
                    Shop_ID__c = shopifyNumericId
                ));
                
                /*
* NEW LOGIC:
* If Salesforce order was already marked as Paid before the Shopify order
* was created, Shopify will not automatically mark it as paid through
* orderCreate.
*
* We must explicitly call orderMarkAsPaid after Shopify returns the
* created Shopify Order Id.
*/
                if (
                    !String.isBlank(ord.Financial_Status__c) &&
                    ord.Financial_Status__c.trim().equalsIgnoreCase('Paid')
                ) {
                    markOrderAsPaid(shopifyNumericId);
                }
            }
            
            /*if (
                ord.Financial_Status__c != null &&
                ord.Financial_Status__c.trim().equalsIgnoreCase('Paid')
            ) {
                markOrderAsPaid(shopifyNumericId);
            }
			*/
            
            Map<String, Object> lineItemsMap = (Map<String, Object>) createdOrderMap.get('lineItems');
            if (lineItemsMap != null && lineItemsMap.containsKey('nodes')) {
                List<Object> createdLineItems = (List<Object>) lineItemsMap.get('nodes');
                
                Integer limitSize = Math.min(sourceOrderItemIds.size(), createdLineItems.size());
                for (Integer i = 0; i < limitSize; i++) {
                    Map<String, Object> createdLineItem = (Map<String, Object>) createdLineItems[i];
                    String createdLineItemGid = String.valueOf(createdLineItem.get('id'));
                    String createdLineItemNumericId = extractNumericId(createdLineItemGid);
                    
                    if (!String.isBlank(createdLineItemNumericId)) {
                        orderItemsToUpdate.add(new OrderItem(
                            Id = sourceOrderItemIds[i],
                            Shop_ID__c = createdLineItemNumericId
                        ));
                    }
                }
            }
        }
        
        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }
        
        if (!orderItemsToUpdate.isEmpty()) {
            update orderItemsToUpdate;
        }
    }
    @TestVisible
    private static String extractNumericId(String gid) {
        if (String.isBlank(gid)) {
            return null;
        }
        
        List<String> parts = gid.split('/');
        return parts.isEmpty() ? null : parts[parts.size() - 1];
    }
    
    private static void markOrderAsPaid(String shopifyOrderId) {
    if (String.isBlank(shopifyOrderId)) return;

    String orderGid = shopifyOrderId.startsWith('gid://')
        ? shopifyOrderId
        : 'gid://shopify/Order/' + shopifyOrderId;

    String mutation =
        'mutation MarkOrderPaid($input: OrderMarkAsPaidInput!) {' +
        '  orderMarkAsPaid(input: $input) {' +
        '    order { id name displayFinancialStatus } ' +
        '    userErrors { field message } ' +
        '  } ' +
        '}';

    Map<String, Object> variables = new Map<String, Object>{
        'input' => new Map<String, Object>{
            'id' => orderGid
        }
    };
        
        HttpResponse res = postGraphQL(mutation, variables);
        System.debug('orderMarkAsPaid after orderCreate response: ' + res.getBody());
    }
    
    private static HttpResponse postGraphQL(String query, Map<String, Object> variables) {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Shopify_Admin_API/admin/api/2026-04/graphql.json');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'query' => query,
                'variables' => variables
                }));
        
        return new Http().send(req);
    }
}