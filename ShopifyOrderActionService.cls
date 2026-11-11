public with sharing class ShopifyOrderActionService {
    public class Request {
        @InvocableVariable(required=true)
        public Id orderId;
        
        @InvocableVariable(required=true)
        public String actionType; // CANCEL or REFUND
        
        @InvocableVariable
        public Boolean notifyCustomer;
        
        @InvocableVariable
        public Boolean restock;
        
        @InvocableVariable
        public String reason;
        
        @InvocableVariable
        public String staffNote;
        
        @InvocableVariable
        public Decimal refundAmount;
        
        @InvocableVariable
        public String refundMethod;
        
        @InvocableVariable
        public String cancelreason;
    }
    
    public class Result {
        @InvocableVariable
        public Boolean success;
        
        @InvocableVariable
        public String message;
    }
    
    @InvocableMethod(label='Shopify Order Action')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        
        for (Request req : requests) {
            Result r = new Result();
            try {
                r = handleSingle(req);
            } catch (Exception e) {
                r.success = false;
                r.message = e.getMessage();
            }
            results.add(r);
        }
        
        return results;
    }
    
    private static Result handleSingle(Request req) {
        Result r = new Result();
        r.success = false;
        
        Order ord = [
            SELECT Id,
            Shop_ID__c,
            Fulfillment_Status__c,
            Financial_Status__c,
            CurrencyIsoCode,
            TotalAmount
            FROM Order
            WHERE Id = :req.orderId
            LIMIT 1
        ];
        
        if (String.isBlank(ord.Shop_ID__c)) {
            r.message = 'Shopify Order ID is missing.';
            return r;
        }
        
        if (req.actionType == 'CANCEL') {
            if (ord.Fulfillment_Status__c == 'Fulfilled') {
                r.message = 'Order is fulfilled in Shopify. Use Refund instead of Cancel.';
                return r;
            }
            return cancelOrder(ord, req);
        }
        
        if (req.actionType == 'REFUND') {
            return refundOrder(ord, req);
        }
        
        r.message = 'Unsupported action type.';
        return r;
    }
    
    private static Result cancelOrder(Order ord, Request req) {
        Result r = new Result();
        
        String mutation =
            'mutation OrderCancel(' +
            '$orderId: ID!, ' +
            '$notifyCustomer: Boolean, ' +
            '$refundMethod: OrderCancelRefundMethodInput!, ' +
            '$restock: Boolean!, ' +
            '$reason: OrderCancelReason!, ' +
            '$staffNote: String) {' +
            '  orderCancel(' +
            '    orderId: $orderId, ' +
            '    notifyCustomer: $notifyCustomer, ' +
            '    refundMethod: $refundMethod, ' +
            '    restock: $restock, ' +
            '    reason: $reason, ' +
            '    staffNote: $staffNote' +
            '  ) {' +
            '    job { id done } ' +
            '    orderCancelUserErrors { field message code } ' +
            '    userErrors { field message } ' +
            '  }' +
            '}';
        
        Map<String, Object> variables = new Map<String, Object>{
            'orderId' => 'gid://shopify/Order/' + ord.Shop_ID__c,
                'notifyCustomer' => req.notifyCustomer == null ? false : req.notifyCustomer,
                    'refundMethod' => new Map<String, Object>{
                        'originalPaymentMethodsRefund' => true
                            },
                                'restock' => req.restock == null ? true : req.restock,
                                    'reason' => normalizeCancelReason(req.reason),
                                    'staffNote' => String.isBlank(req.staffNote) ? 'Cancelled from Salesforce' : req.staffNote
                                        };
                                            //Order cancel field update.
                                            Result result = sendGraphQL(mutation, variables, 'orderCancel');

        if (result.success == true) {
            
            Order upd = new Order(
                Id = ord.Id,
                Fulfillment_Status__c = 'Restocked',
                Cancelled_Date__c = System.now(),
                Cancel_Reason__c = req.reason
            );
            
            update upd;
            //adjustSalesforceInventory(ord.Id, true);
        }
        
        return result;
    }
    
    public static String normalizeCancelReason(String reason) {
        if (String.isBlank(reason)) return 'CUSTOMER';
        
        String r = reason.trim().toUpperCase();
        
        if (r == 'CUSTOMER' || r == 'DECLINED' || r == 'FRAUD' ||
            r == 'INVENTORY' || r == 'OTHER' || r == 'STAFF') {
                return r;
            }
        
        if (r == 'CUSTOMER CHANGED OR CANCELED ORDER') return 'CUSTOMER';
        if (r == 'PAYMENT DECLINED') return 'DECLINED';
        if (r == 'FRAUDULENT ORDER') return 'FRAUD';
        if (r == 'ITEMS UNAVAILABLE') return 'INVENTORY';
        if (r == 'STAFF ERROR') return 'STAFF';
        
        return 'OTHER';
    }
    
    private static Result refundOrder(Order ord, Request req) {
        Result r = new Result();
        
        String orderGid = 'gid://shopify/Order/' + ord.Shop_ID__c;
        
        String query =
            'query RefundContext($id: ID!) {' +
            '  order(id: $id) {' +
            '    id ' +
            '    lineItems(first: 50) {' +
            '      nodes { id quantity }' +
            '    } ' +
            '    fulfillments(first: 20) {' +
            '      location { id } ' +
            '      fulfillmentLineItems(first: 50) {' +
            '        nodes {' +
            '          lineItem { id }' +
            '        }' +
            '      }' +
            '    }' +
            '  }' +
            '}';
        
        HttpResponse contextRes = postGraphQL(
            query,
            new Map<String, Object>{ 'id' => orderGid }
        );
        
        Map<String, Object> contextMap =
            (Map<String, Object>) JSON.deserializeUntyped(contextRes.getBody());
        
        Map<String, Object> dataMap =
            contextMap == null ? null : (Map<String, Object>) contextMap.get('data');
        
        Map<String, Object> orderMap =
            dataMap == null ? null : (Map<String, Object>) dataMap.get('order');
        
        if (orderMap == null) {
            r.success = false;
            r.message = 'Unable to load Shopify order refund context.';
            return r;
        }
        
        Map<String, String> locationByLineItemId = new Map<String, String>();
        
        List<Object> fulfillmentNodes =
            (List<Object>) orderMap.get('fulfillments');
        
        if (fulfillmentNodes != null) {
            for (Object fObj : fulfillmentNodes) {
                Map<String, Object> fulfillmentNode = (Map<String, Object>) fObj;
                
                Map<String, Object> locationMap =
                    (Map<String, Object>) fulfillmentNode.get('location');
                
                String locationId = locationMap == null
                    ? null
                    : String.valueOf(locationMap.get('id'));
                
                if (String.isBlank(locationId)) continue;
                
                Map<String, Object> fulfillmentLineItemsMap =
                    (Map<String, Object>) fulfillmentNode.get('fulfillmentLineItems');
                
                List<Object> fulfillmentLineItemNodes =
                    fulfillmentLineItemsMap == null
                    ? null
                    : (List<Object>) fulfillmentLineItemsMap.get('nodes');
                
                if (fulfillmentLineItemNodes == null) continue;
                
                for (Object fliObj : fulfillmentLineItemNodes) {
                    Map<String, Object> fliNode = (Map<String, Object>) fliObj;
                    Map<String, Object> lineItemMap =
                        (Map<String, Object>) fliNode.get('lineItem');
                    
                    if (lineItemMap == null) continue;
                    
                    String lineItemId = String.valueOf(lineItemMap.get('id'));
                    if (!String.isBlank(lineItemId)) {
                        locationByLineItemId.put(lineItemId, locationId);
                    }
                }
            }
        }
        
        Map<String, Object> lineItemsMap =
            (Map<String, Object>) orderMap.get('lineItems');
        
        List<Object> nodes =
            lineItemsMap == null ? null : (List<Object>) lineItemsMap.get('nodes');
        
        if (nodes == null || nodes.isEmpty()) {
            r.success = false;
            r.message = 'No Shopify line items found for refund.';
            return r;
        }
        
        Boolean shouldRestock = req.restock == null ? true : req.restock;
        
        Decimal availableAmount = ord.TotalAmount;
        Decimal requestedAmount = req.refundAmount;
        
        if (requestedAmount == null || requestedAmount <= 0) {
            requestedAmount = availableAmount;
        }
        
        if (availableAmount != null && requestedAmount > availableAmount) {
            r.success = false;
            r.message = 'Refund amount cannot be greater than available refund amount.';
            return r;
        }
        
        List<Object> refundLineItems = new List<Object>();
        
        for (Object n : nodes) {
            Map<String, Object> node = (Map<String, Object>) n;
            String lineItemId = String.valueOf(node.get('id'));
            
            Map<String, Object> refundLineItem = new Map<String, Object>{
                'lineItemId' => lineItemId,
                    'quantity' => node.get('quantity'),
                    'restockType' => shouldRestock ? 'RETURN' : 'NO_RESTOCK'
                        };
                            
                            if (shouldRestock) {
                                String locationId = locationByLineItemId.get(lineItemId);
                                
                                if (String.isBlank(locationId)) {
                                    r.success = false;
                                    r.message = 'Unable to find original Shopify fulfillment location for line item: ' + lineItemId;
                                    return r;
                                }
                                
                                refundLineItem.put('locationId', locationId);
                            }
            
            refundLineItems.add(refundLineItem);
        }
        
        String idemKey = ord.Id + '-refund-' + String.valueOf(requestedAmount);
        
        String mutation =
            'mutation RefundOrder($input: RefundInput!) {' +
            '  refundCreate(input: $input) @idempotent(key: "' + idemKey + '") {' +
            '    refund {' +
            '      id ' +
            '      totalRefundedSet { presentmentMoney { amount currencyCode } } ' +
            '    } ' +
            '    userErrors { field message } ' +
            '  }' +
            '}';
        
        Map<String, Object> input = new Map<String, Object>{
            'orderId' => orderGid,
                'refundLineItems' => refundLineItems,
                'note' => String.isBlank(req.reason) ? null : req.reason,
                    'notify' => req.notifyCustomer == null ? false : req.notifyCustomer,
                        'currency' => ord.CurrencyIsoCode,
                        'transactions' => new List<Object>()
                        };
                            
                            Result result = sendGraphQL(
                                mutation,
                                new Map<String, Object>{ 'input' => input },
                                'refundCreate'
                            );
        
        if (result.success == true) {
            Order upd = new Order(
                Id = ord.Id,
                Financial_Status__c = 'Refunded',
                Fulfillment_Status__c = shouldRestock ? 'Restocked' : ord.Fulfillment_Status__c,
                Refund_Date__c = System.now(),
                Refund_Reason__c = req.reason,
                Refund_Amount__c = requestedAmount
            );
            
            update upd;
            //adjustSalesforceInventory(ord.Id, true);
        }
        
        return result;
    }
    
    private static String normalizeRefundMethod(String refundMethod) {
        if (String.isBlank(refundMethod)) return 'ORIGINAL_PAYMENT';
        
        String v = refundMethod.trim().toUpperCase().replace(' ', '_');
        
        if (v == 'ORIGINAL_PAYMENT') return 'ORIGINAL_PAYMENT';
        if (v == 'STORE_CREDIT') return 'STORE_CREDIT';
        if (v == 'ORIGINAL_PAYMENT_AND_STORE_CREDIT') return 'ORIGINAL_PAYMENT_AND_STORE_CREDIT';
        
        return 'ORIGINAL_PAYMENT';
    }
    
    private static Result sendGraphQL(String query, Map<String, Object> variables, String rootField) {
        Result r = new Result();
        
        HttpResponse res = postGraphQL(query, variables);
        if (res == null || res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            r.success = false;
            r.message = 'Shopify call failed.';
            return r;
        }
        
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (responseMap == null) {
            r.success = false;
            r.message = 'Empty Shopify response.';
            return r;
        }
        
        List<Object> topErrors = (List<Object>) responseMap.get('errors');
        if (topErrors != null && !topErrors.isEmpty()) {
            r.success = false;
            r.message = 'Shopify error: ' + JSON.serialize(topErrors);
            return r;
        }
        
        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        if (dataMap == null) {
            r.success = false;
            r.message = 'No Shopify data returned.';
            return r;
        }
        
        Map<String, Object> rootMap = (Map<String, Object>) dataMap.get(rootField);
        if (rootMap == null) {
            r.success = false;
            r.message = 'Missing Shopify response field: ' + rootField;
            return r;
        }
        
        List<Object> userErrors = null;
        if (rootField == 'orderCancel') {
            userErrors = (List<Object>) rootMap.get('orderCancelUserErrors');
            if (userErrors == null || userErrors.isEmpty()) {
                userErrors = (List<Object>) rootMap.get('userErrors');
            }
        } else {
            userErrors = (List<Object>) rootMap.get('userErrors');
        }
        
        if (userErrors != null && !userErrors.isEmpty()) {
            r.success = false;
            r.message = 'Shopify error: ' + JSON.serialize(userErrors);
            return r;
        }
        
        r.success = true;
        r.message = rootField == 'orderCancel'
            ? 'Shopify cancellation submitted successfully.'
            : 'Shopify refund submitted successfully.';
        return r;
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
        
        return (new Http()).send(req);
    }
}