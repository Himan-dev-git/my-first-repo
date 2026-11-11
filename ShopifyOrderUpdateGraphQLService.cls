public without sharing class ShopifyOrderUpdateGraphQLService {
    
    @future(callout=true)
    public static void syncOrderUpdatesAsync(List<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) return;
        
        List<Order> orders = [
            SELECT Id,
            Shop_ID__c,
            Fulfillment_Status__c,
            Financial_Status__c,
            ShippingStreet,
            ShippingCity,
            ShippingState,
            ShippingPostalCode,
            ShippingCountry,
            Account.FirstName,
            Account.LastName,
            TotalAmount,
            CurrencyIsoCode,
            Type
            FROM Order
            WHERE Id IN :orderIds
            AND Shop_ID__c != null
        ];
        
        for (Order ord : orders) {
            // 1. Financial status sync first
            syncFinancialStatus(ord);
            
            // 2. Fulfillment sync
            String financialStatus = String.isBlank(ord.Financial_Status__c)
                ? ''
                : ord.Financial_Status__c.trim().toLowerCase();
            
            String fulfillmentStatus = String.isBlank(ord.Fulfillment_Status__c)
                ? ''
                : ord.Fulfillment_Status__c.trim().toLowerCase();
            
            if (
                fulfillmentStatus == 'fulfilled' &&
                financialStatus != 'refunded' &&
                financialStatus != 'partially_refunded'
            ) {
                fulfillOrder(ord);
            }
            
            // 3. Shipping address sync
            updateOrderAddress(ord);
        }
    }
    
    private static void syncFinancialStatus(Order ord) {
        if (ord == null || String.isBlank(ord.Shop_ID__c) || String.isBlank(ord.Financial_Status__c)) {
            return;
        }
        
        String financialStatus = ord.Financial_Status__c.trim().toLowerCase();
        
        if (financialStatus == 'paid') {
            markOrderAsPaid(ord);
        } else if (financialStatus == 'partially_paid') {
            createPartialManualPayment(ord);
        }
    }
    
    private static void markOrderAsPaid(Order ord) {
        
        String orderGid = ord.Shop_ID__c;
        
        if (!orderGid.startsWith('gid://')) {
            orderGid = 'gid://shopify/Order/' + orderGid;
        }
        
        String mutation =
            'mutation MarkOrderPaid($input: OrderMarkAsPaidInput!) {' +
            '  orderMarkAsPaid(input: $input) {' +
            '    order {' +
            '      id ' +
            '      name ' +
            '      displayFinancialStatus ' +
            '    } ' +
            '    userErrors {' +
            '      field ' +
            '      message ' +
            '    } ' +
            '  } ' +
            '}';
        
        Map<String, Object> variables = new Map<String, Object>{
            'input' => new Map<String, Object>{
                'id' => orderGid
                    }
        };
            
            HttpResponse res = postGraphQL(mutation, variables);
        System.debug('orderMarkAsPaid response: ' + res.getBody());
    }
    
    private static void createPartialManualPayment(Order ord) {
        Decimal paymentAmount = ord.TotalAmount; // replace if your org uses custom amount field
        
        if (paymentAmount == null || paymentAmount <= 0) {
            return;
        }
        
        // Example: if you want partial payment, send the partial amount instead of full amount.
        // Replace this with your real partial-payment field if you have one.
        Decimal partialAmount = paymentAmount / 2;
        
        String mutation =
            'mutation CreateManualPayment(' +
            '  $id: ID!, ' +
            '  $amount: MoneyInput, ' +
            '  $paymentMethodName: String, ' +
            '  $processedAt: DateTime' +
            ') {' +
            '  orderCreateManualPayment(' +
            '    id: $id, ' +
            '    amount: $amount, ' +
            '    paymentMethodName: $paymentMethodName, ' +
            '    processedAt: $processedAt' +
            '  ) {' +
            '    order {' +
            '      id ' +
            '      name ' +
            '      displayFinancialStatus ' +
            '    } ' +
            '    userErrors {' +
            '      field ' +
            '      message ' +
            '    } ' +
            '  } ' +
            '}';
        
        Map<String, Object> variables = new Map<String, Object>{
            'id' => 'gid://shopify/Order/' + ord.Shop_ID__c,
                'amount' => new Map<String, Object>{
                    'amount' => String.valueOf(partialAmount),
                        'currencyCode' => ord.CurrencyIsoCode
                        },
                            'paymentMethodName' => 'Manual',
                            'processedAt' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                            };
                                
                                HttpResponse res = postGraphQL(mutation, variables);
        System.debug('orderCreateManualPayment response: ' + res.getBody());
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
    
    private static void fulfillOrder(Order ord) {
        String query =
            'query getFulfillmentOrders($id: ID!) {' +
            '  order(id: $id) {' +
            '    fulfillmentOrders(first: 10) {' +
            '      nodes {' +
            '        id' +
            '        status' +
            '      }' +
            '    }' +
            '  }' +
            '}';
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'query' => query,
                'variables' => new Map<String, Object>{
                    'id' => 'gid://shopify/Order/' + ord.Shop_ID__c
                        }
        };
            
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Shopify_Admin_API/admin/api/2026-04/graphql.json');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(requestBody));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return;
        
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        if (dataMap == null) return;
        
        Map<String, Object> orderMap = (Map<String, Object>) dataMap.get('order');
        if (orderMap == null) return;
        
        Map<String, Object> fulfillmentOrdersMap = (Map<String, Object>) orderMap.get('fulfillmentOrders');
        if (fulfillmentOrdersMap == null) return;
        
        List<Object> nodes = (List<Object>) fulfillmentOrdersMap.get('nodes');
        if (nodes == null || nodes.isEmpty()) return;
        
        String fulfillmentOrderId = null;
        for (Object nodeObj : nodes) {
            Map<String, Object> node = (Map<String, Object>) nodeObj;
            if (String.valueOf(node.get('status')) == 'OPEN' || String.valueOf(node.get('status')) == 'IN_PROGRESS') {
                fulfillmentOrderId = String.valueOf(node.get('id'));
                break;
            }
        }
        
        if (String.isBlank(fulfillmentOrderId)) return;
        
        String mutation =
            'mutation fulfillmentCreate($fulfillment: FulfillmentInput!) {' +
            '  fulfillmentCreate(fulfillment: $fulfillment) {' +
            '    fulfillment { id status }' +
            '    userErrors { field message }' +
            '  }' +
            '}';
        
        Map<String, Object> fulfillmentInput = new Map<String, Object>{
            'lineItemsByFulfillmentOrder' => new List<Object>{
                new Map<String, Object>{
                    'fulfillmentOrderId' => fulfillmentOrderId
                        }
            },
                'notifyCustomer' => false
                };
                    
                    Map<String, Object> body = new Map<String, Object>{
                        'query' => mutation,
                            'variables' => new Map<String, Object>{
                                'fulfillment' => fulfillmentInput
                                    }
                    };
                        
        HttpRequest fulfillReq = new HttpRequest();
        fulfillReq.setMethod('POST');
        fulfillReq.setEndpoint('callout:Shopify_Admin_API/admin/api/2026-04/graphql.json');
        fulfillReq.setHeader('Content-Type', 'application/json');
        fulfillReq.setBody(JSON.serialize(body));
        
        HttpResponse fulfillRes = (new Http()).send(fulfillReq);
        System.debug('Fulfillment update response: ' + fulfillRes.getBody());
    }
    
    private static void updateOrderAddress(Order ord) {
        String mutation =
            'mutation orderUpdate($input: OrderInput!) {' +
            '  orderUpdate(input: $input) {' +
            '    order { id }' +
            '    userErrors { field message }' +
            '  }' +
            '}';
        
        Map<String, Object> shippingAddress = new Map<String, Object>{
            'address1' => ord.ShippingStreet,
                'city' => ord.ShippingCity,
                'province' => ord.ShippingState,
                'zip' => ord.ShippingPostalCode,
                'country' => ord.ShippingCountry,
                'firstName' => ord.Account != null ? ord.Account.FirstName : null,
                    'lastName' => ord.Account != null ? ord.Account.LastName : null
                        };
                            
                            Map<String, Object> input = new Map<String, Object>{
                                'id' => 'gid://shopify/Order/' + ord.Shop_ID__c,
                                    'shippingAddress' => shippingAddress
                                    };
                                        
                                        Map<String, Object> body = new Map<String, Object>{
                                            'query' => mutation,
                                                'variables' => new Map<String, Object>{ 'input' => input }
                                        };
                                            
                                            HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Shopify_Admin_API/admin/api/2026-04/graphql.json');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));
        
        HttpResponse res = (new Http()).send(req);
        System.debug('Order update response: ' + res.getBody());
    }
}