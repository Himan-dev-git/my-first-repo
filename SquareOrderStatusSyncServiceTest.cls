@IsTest
private class SquareOrderStatusSyncServiceTest {
    
    // =====================================================================
    // Test data helpers
    // =====================================================================
    
    private static Account createPersonAccount(String squareCustomerId) {
        RecordType personAccRT = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];
        
        Account acc = new Account(
            LastName              = 'Square Test ' + String.valueOf(squareCustomerId),
            RecordTypeId          = personAccRT.Id,
            Square_Customer_Id__c = squareCustomerId
        );
        insert acc;
        return acc;
    }
    
    private static SObject createProviderCustomerMapping(String squareLocationId) {
        Schema.SObjectType providerType =
            SquarePopUpAccountService.getProviderCustomerObjectType();
        System.assertNotEquals(
            null,
            providerType,
            'Order.Pop_up_Provider__c must be a Lookup(Customer).'
        );

        Map<String, Schema.SObjectField> fields = providerType.getDescribe().fields.getMap();
        System.assert(
            fields.containsKey('Square_Location_Id__c'),
            'The Customer object must expose Square_Location_Id__c.'
        );

        SObject providerCustomer = providerType.newSObject();
        if (fields.containsKey('Name') && fields.get('Name').getDescribe().isCreateable()) {
            providerCustomer.put('Name', 'Provider Customer ' + squareLocationId);
        }
        providerCustomer.put('Square_Location_Id__c', squareLocationId);
        insert providerCustomer;
        return providerCustomer;
    }

    private static Order createDraftOrder(
        Id accountId,
        String squareOrderId,
        String squarePaymentId,
        String financialStatus,
        String fulfillmentStatus
    ) {
        Order ord = new Order(
            AccountId             = accountId,
            EffectiveDate         = Date.today(),
            Status                = 'Draft',
            Type                  = 'POS',
            Square_Order_Id__c    = squareOrderId,
            Square_Payment_Id__c  = squarePaymentId,
            Financial_Status__c   = financialStatus,
            Fulfillment_Status__c = fulfillmentStatus
        );
        insert ord;
        return ord;
    }
    
    private static Id createWarehouseLocationIfPossible() {
        try {
            SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
            loc.put('Name', 'Warehouse');
            insert loc;
            return (Id) loc.get('Id');
        } catch (Exception e) {
            System.debug('Warehouse Location test setup skipped: ' + e.getMessage());
            return null;
        }
    }
    
    private static Map<String, Object> squareOrder(
        String orderId,
        String customerId,
        String paymentId,
        String state,
        Integer amountCents
    ) {
        Map<String, Object> orderMap = new Map<String, Object>{
            'id'          => orderId,
            'location_id' => 'LOC_001',
            'state'       => state,
            'total_money' => new Map<String, Object>{
                'amount'   => amountCents,
                'currency' => 'USD'
            },
            'line_items'  => new List<Object>{
                new Map<String, Object>{
                    'uid'      => 'line_1',
                    'name'     => 'Test Item',
                    'quantity' => '1'
                }
            }
        };
        
        if (customerId != null) {
            orderMap.put('customer_id', customerId);
        }
        
        if (paymentId != null) {
            orderMap.put(
                'tenders',
                new List<Object>{
                    new Map<String, Object>{
                        'id'          => 'tender_' + paymentId,
                        'payment_id'  => paymentId,
                        'customer_id' => customerId
                    }
                }
            );
        }
        
        return orderMap;
    }
    
    private static Map<String, Object> zeroValueSquareOrder(
        String orderId
    ) {
        return new Map<String, Object>{
            'id'          => orderId,
            'location_id' => 'LOC_001',
            'state'       => 'COMPLETED',
            'total_money' => new Map<String, Object>{
                'amount'   => 0,
                'currency' => 'USD'
            }
        };
    }
    
    private static Map<String, Object> payment(
        String paymentId,
        String customerId,
        Integer amountCents,
        Integer refundedCents
    ) {
        Map<String, Object> paymentMap = new Map<String, Object>{
            'id'             => paymentId,
            'amount_money'   => new Map<String, Object>{
                'amount'   => amountCents,
                'currency' => 'USD'
            },
            'refunded_money' => new Map<String, Object>{
                'amount'   => refundedCents,
                'currency' => 'USD'
            }
        };
        
        if (customerId != null) {
            paymentMap.put('customer_id', customerId);
        }
        
        return paymentMap;
    }
    
    private static Map<String, Object> customer(String customerId) {
        return new Map<String, Object>{
            'id'            => customerId,
            'given_name'    => 'Square',
            'family_name'   => 'Customer',
            'email_address' => customerId.toLowerCase() + '@example.com',
            'phone_number'  => '+15555550123',
            'preferences'   => new Map<String, Object>{
                'email_unsubscribed' => false
            }
        };
    }
    
    // =====================================================================
    // Endpoint-aware Square mock
    // =====================================================================
    
    private class SquareEndpointMock implements HttpCalloutMock {
        private Map<String, Object> orderResponse;
        private Map<String, Object> paymentResponse;
        private Map<String, Object> customerResponse;
        private Boolean orderNotFound = false;
        private Boolean paymentThrows = false;
        private Boolean customerThrows = false;
        
        SquareEndpointMock(
            Map<String, Object> orderResponse,
            Map<String, Object> paymentResponse,
            Map<String, Object> customerResponse
        ) {
            this.orderResponse = orderResponse;
            this.paymentResponse = paymentResponse;
            this.customerResponse = customerResponse;
        }
        
        SquareEndpointMock withOrderNotFound() {
            this.orderNotFound = true;
            return this;
        }
        
        SquareEndpointMock withPaymentThrows() {
            this.paymentThrows = true;
            return this;
        }
        
        SquareEndpointMock withCustomerThrows() {
            this.customerThrows = true;
            return this;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            String endpoint = req.getEndpoint() == null
                ? ''
                : req.getEndpoint().toLowerCase();
            
            if (endpoint.contains('/v2/orders/')) {
                res.setStatusCode(200);
                if (orderNotFound || orderResponse == null) {
                    res.setBody('{}');
                } else {
                    res.setBody(JSON.serialize(new Map<String, Object>{
                        'order' => orderResponse
                    }));
                }
                return res;
            }
            
            if (endpoint.contains('/v2/payments/')) {
                if (paymentThrows) {
                    res.setStatusCode(500);
                    res.setBody('{"errors":[{"detail":"Payment API failed"}]}');
                    return res;
                }
                
                res.setStatusCode(200);
                if (paymentResponse == null) {
                    res.setBody('{}');
                } else {
                    res.setBody(JSON.serialize(new Map<String, Object>{
                        'payment' => paymentResponse
                    }));
                }
                return res;
            }
            
            if (endpoint.contains('/v2/customers/')) {
                if (customerThrows) {
                    res.setStatusCode(500);
                    res.setBody('{"errors":[{"detail":"Customer API failed"}]}');
                    return res;
                }
                
                res.setStatusCode(200);
                if (customerResponse == null) {
                    res.setBody('{}');
                } else {
                    res.setBody(JSON.serialize(new Map<String, Object>{
                        'customer' => customerResponse
                    }));
                }
                return res;
            }

            if (endpoint.contains('/v2/locations/') && req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'location' => new Map<String, Object>{
                        'id' => 'LOC_001',
                        'name' => 'Test Pop-up Location',
                        'status' => 'ACTIVE'
                    }
                }));
                return res;
            }
            
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }
    
    // =====================================================================
    // Main syncSquareOrder tests
    // =====================================================================
    
    @IsTest
    static void testSyncSquareOrder_BlankId_ReturnsWithoutDml() {
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder(null, 'order.updated', '{}');
        SquareOrderStatusSyncService.syncSquareOrder('', 'order.updated', '{}');
        Test.stopTest();
        
        System.assertEquals(0, [SELECT COUNT() FROM Order]);
    }
    
    @IsTest
    static void testSyncSquareOrder_OrderNotFound_ReturnsWithoutDml() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(null, null, null).withOrderNotFound()
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_NOT_FOUND', 'order.updated', '{}');
        Test.stopTest();
        
        System.assertEquals(0, [SELECT COUNT() FROM Order]);
    }
    
    @IsTest
    static void testSyncSquareOrder_OrderUpdatedWithoutExistingOrder_SkipsInsert() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_UPDATED_NO_EXISTING', null, null, 'COMPLETED', 1000),
                null,
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder(
            'ORD_UPDATED_NO_EXISTING',
            'order.updated',
            '{}'
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Order
                WHERE Square_Order_Id__c = 'ORD_UPDATED_NO_EXISTING'
            ],
            'order.updated should not create a new Order when no existing Order exists.'
        );
    }
    
    @IsTest
    static void testSyncSquareOrder_FulfillmentUpdatedWithoutExistingOrder_SkipsInsert() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_FULFILLMENT_NO_EXISTING', null, null, 'COMPLETED', 1000),
                null,
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder(
            'ORD_FULFILLMENT_NO_EXISTING',
            'order.fulfillment.updated',
            '{}'
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Order
                WHERE Square_Order_Id__c = 'ORD_FULFILLMENT_NO_EXISTING'
            ],
            'order.fulfillment.updated should not create a new Order when no existing Order exists.'
        );
    }
    
    @IsTest
    static void testSyncSquareOrder_ZeroValueNoLineItemsOrderCreated_SkipsInsert() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                zeroValueSquareOrder('ORD_ZERO_SHELL'),
                null,
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder(
            'ORD_ZERO_SHELL',
            'order.created',
            '{}'
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Order
                WHERE Square_Order_Id__c = 'ORD_ZERO_SHELL'
            ],
            'Empty zero-value Square shell should be skipped.'
        );
    }
    
    @IsTest
    static void testSyncSquareOrder_CustomerExistsButNoPersonAccount_SkipsOrder() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_NO_ACCOUNT', 'CUST_NO_ACCOUNT', 'PAY_NO_ACCOUNT', 'COMPLETED', 1500),
                payment('PAY_NO_ACCOUNT', 'CUST_NO_ACCOUNT', 1500, 0),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_NO_ACCOUNT', 'order.created', '{}');
        Test.stopTest();
        
        System.assertEquals(0, [SELECT COUNT() FROM Order]);
    }
    
    @IsTest
    static void testSyncSquareOrder_NoCustomer_UsesDefaultAccountAndCreatesOrder() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_ANON', null, null, 'COMPLETED', 1000),
                null,
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_ANON', 'order.created', '{}');
        Test.stopTest();
        
        List<Order> createdOrders = [
            SELECT Id, AccountId, Square_Order_Id__c, Financial_Status__c,
            Fulfillment_Status__c, Shop_Total_Amount__c, Type, Status,
            RecordType.Name
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_ANON'
            LIMIT 1
        ];
        
        System.assertEquals(
            1,
            createdOrders.size(),
            'Expected an Order to be created for ORD_ANON'
        );
        
        Order created = createdOrders[0];
        
        System.assertNotEquals(null, created.AccountId);
        System.assertEquals('Paid', created.Financial_Status__c);
        System.assertEquals('Fulfilled', created.Fulfillment_Status__c);
        System.assertEquals(10.00, created.Shop_Total_Amount__c);
        System.assertEquals('POS', created.Type);
        System.assertEquals('Draft', created.Status);
        System.assertEquals('POS', created.Type);
        System.assertEquals('Pop-up', created.RecordType.Name);
    }
    
    @IsTest
    static void testSyncSquareOrder_NewPaidOrder_CreatesOrder() {
        Account acc = createPersonAccount('CUST_CREATE_PAID');
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_CREATE_PAID', 'CUST_CREATE_PAID', 'PAY_CREATE_PAID', 'COMPLETED', 2500),
                payment('PAY_CREATE_PAID', 'CUST_CREATE_PAID', 2500, 0),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_CREATE_PAID', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Square_Order_Id__c, Square_Payment_Id__c,
                   Financial_Status__c, Fulfillment_Status__c,
                   Shop_Total_Amount__c, Square_Location_Id__c, Square_Raw_JSON__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_CREATE_PAID'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('PAY_CREATE_PAID', created.Square_Payment_Id__c);
        System.assertEquals('Paid', created.Financial_Status__c);
        System.assertEquals('Fulfilled', created.Fulfillment_Status__c);
        System.assertEquals(25.00, created.Shop_Total_Amount__c);
        System.assertEquals('LOC_001', created.Square_Location_Id__c);
        System.assertNotEquals(null, created.Square_Raw_JSON__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_CanceledOrder_CreatesRefundedOrder() {
        Account acc = createPersonAccount('CUST_CANCELED');
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_CANCELED', 'CUST_CANCELED', null, 'CANCELED', 2200),
                null,
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_CANCELED', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Financial_Status__c, Fulfillment_Status__c, Shop_Total_Amount__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_CANCELED'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('Refunded', created.Financial_Status__c);
        System.assertEquals('Unfulfilled', created.Fulfillment_Status__c);
        System.assertEquals(22.00, created.Shop_Total_Amount__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_OpenOrder_CreatesPendingOrder() {
        Account acc = createPersonAccount('CUST_OPEN');
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_OPEN', 'CUST_OPEN', null, 'OPEN', 3300),
                null,
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_OPEN', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Financial_Status__c, Fulfillment_Status__c, Shop_Total_Amount__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_OPEN'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('Pending', created.Financial_Status__c);
        System.assertEquals('Unfulfilled', created.Fulfillment_Status__c);
        System.assertEquals(33.00, created.Shop_Total_Amount__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_FullyRefundedPayment_OverridesToRefunded() {
        Account acc = createPersonAccount('CUST_FULL_REFUND_SYNC');
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_FULL_REFUND_SYNC', 'CUST_FULL_REFUND_SYNC', 'PAY_FULL_REFUND_SYNC', 'COMPLETED', 3000),
                payment('PAY_FULL_REFUND_SYNC', 'CUST_FULL_REFUND_SYNC', 3000, 3000),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_FULL_REFUND_SYNC', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Financial_Status__c, Fulfillment_Status__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_FULL_REFUND_SYNC'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('Refunded', created.Financial_Status__c);
        System.assertEquals('Restocked', created.Fulfillment_Status__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_PartialRefund_StaysPaid() {
        Account acc = createPersonAccount('CUST_PARTIAL_REFUND_SYNC');
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_PARTIAL_REFUND_SYNC', 'CUST_PARTIAL_REFUND_SYNC', 'PAY_PARTIAL_REFUND_SYNC', 'COMPLETED', 5000),
                payment('PAY_PARTIAL_REFUND_SYNC', 'CUST_PARTIAL_REFUND_SYNC', 5000, 1000),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_PARTIAL_REFUND_SYNC', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Financial_Status__c, Fulfillment_Status__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_PARTIAL_REFUND_SYNC'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('Paid', created.Financial_Status__c);
        System.assertEquals('Fulfilled', created.Fulfillment_Status__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_ExistingOrderFoundByPaymentId_UpdatesOrder() {
        Account acc = createPersonAccount('CUST_EXISTING_PAYMENT');
        Order existingOrd = createDraftOrder(
            acc.Id,
            null,
            'PAY_EXISTING_PAYMENT',
            'Pending',
            'Unfulfilled'
        );
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_EXISTING_PAYMENT', 'CUST_EXISTING_PAYMENT', 'PAY_EXISTING_PAYMENT', 'COMPLETED', 4400),
                payment('PAY_EXISTING_PAYMENT', 'CUST_EXISTING_PAYMENT', 4400, 0),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_EXISTING_PAYMENT', 'order.updated', '{}');
        Test.stopTest();
        
        Order updated = [
            SELECT Id, Square_Order_Id__c, Square_Payment_Id__c,
                   Financial_Status__c, Fulfillment_Status__c, Shop_Total_Amount__c
            FROM Order
            WHERE Id = :existingOrd.Id
            LIMIT 1
        ];
        
        System.assertEquals('ORD_EXISTING_PAYMENT', updated.Square_Order_Id__c);
        System.assertEquals('PAY_EXISTING_PAYMENT', updated.Square_Payment_Id__c);
        System.assertEquals('Paid', updated.Financial_Status__c);
        System.assertEquals('Fulfilled', updated.Fulfillment_Status__c);
        System.assertEquals(44.00, updated.Shop_Total_Amount__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_ExistingOrderFoundByOrderId_UpdatesOrder() {
        Account acc = createPersonAccount('CUST_EXISTING_ORDER');
        Order existingOrd = createDraftOrder(
            acc.Id,
            'ORD_EXISTING_ORDER',
            null,
            'Pending',
            'Unfulfilled'
        );
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_EXISTING_ORDER', 'CUST_EXISTING_ORDER', 'PAY_EXISTING_ORDER', 'COMPLETED', 1800),
                payment('PAY_EXISTING_ORDER', 'CUST_EXISTING_ORDER', 1800, 0),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_EXISTING_ORDER', 'order.updated', '{}');
        Test.stopTest();
        
        Order updated = [
            SELECT Id, Square_Order_Id__c, Square_Payment_Id__c,
                   Financial_Status__c, Fulfillment_Status__c, Shop_Total_Amount__c
            FROM Order
            WHERE Id = :existingOrd.Id
            LIMIT 1
        ];
        
        System.assertEquals('ORD_EXISTING_ORDER', updated.Square_Order_Id__c);
        System.assertEquals('PAY_EXISTING_ORDER', updated.Square_Payment_Id__c);
        System.assertEquals('Paid', updated.Financial_Status__c);
        System.assertEquals('Fulfilled', updated.Fulfillment_Status__c);
        System.assertEquals(18.00, updated.Shop_Total_Amount__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_ExistingRefundedOrder_RemainsRefunded() {
        Account acc = createPersonAccount('CUST_ALREADY_REFUNDED');
        Order existingOrd = createDraftOrder(
            acc.Id,
            'ORD_ALREADY_REFUNDED',
            'PAY_ALREADY_REFUNDED',
            'Refunded',
            'Unfulfilled'
        );
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_ALREADY_REFUNDED', 'CUST_ALREADY_REFUNDED', 'PAY_ALREADY_REFUNDED', 'COMPLETED', 2000),
                payment('PAY_ALREADY_REFUNDED', 'CUST_ALREADY_REFUNDED', 2000, 0),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_ALREADY_REFUNDED', 'order.updated', '{}');
        Test.stopTest();
        
        Order updated = [
            SELECT Financial_Status__c, Fulfillment_Status__c
            FROM Order
            WHERE Id = :existingOrd.Id
            LIMIT 1
        ];
        
        System.assertEquals('Refunded', updated.Financial_Status__c);
        System.assertEquals('Restocked', updated.Fulfillment_Status__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_CustomerIdRecoveredFromTender() {
        Account acc = createPersonAccount('CUST_FROM_TENDER');
        
        Map<String, Object> orderMap = new Map<String, Object>{
            'id'          => 'ORD_FROM_TENDER',
            'location_id' => 'LOC_001',
            'state'       => 'COMPLETED',
            'total_money' => new Map<String, Object>{ 'amount' => 700, 'currency' => 'USD' },
            'line_items'  => new List<Object>{
                new Map<String, Object>{ 'uid' => 'line_1', 'name' => 'Test Item', 'quantity' => '1' }
            },
            'tenders'     => new List<Object>{
                new Map<String, Object>{
                    'id'          => 'tender_001',
                    'payment_id'  => 'PAY_FROM_TENDER',
                    'customer_id' => 'CUST_FROM_TENDER'
                }
            }
        };
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                orderMap,
                payment('PAY_FROM_TENDER', 'CUST_FROM_TENDER', 700, 0),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_FROM_TENDER', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Square_Payment_Id__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_FROM_TENDER'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('PAY_FROM_TENDER', created.Square_Payment_Id__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_CustomerIdRecoveredFromPayment() {
        Account acc = createPersonAccount('CUST_FROM_PAYMENT');
        
        Map<String, Object> orderMap = new Map<String, Object>{
            'id'          => 'ORD_FROM_PAYMENT',
            'location_id' => 'LOC_001',
            'state'       => 'COMPLETED',
            'total_money' => new Map<String, Object>{ 'amount' => 900, 'currency' => 'USD' },
            'line_items'  => new List<Object>{
                new Map<String, Object>{ 'uid' => 'line_1', 'name' => 'Test Item', 'quantity' => '1' }
            },
            'tenders'     => new List<Object>{
                new Map<String, Object>{
                    'id'         => 'tender_payment_only',
                    'payment_id' => 'PAY_FROM_PAYMENT'
                }
            }
        };
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                orderMap,
                payment('PAY_FROM_PAYMENT', 'CUST_FROM_PAYMENT', 900, 0),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_FROM_PAYMENT', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Square_Payment_Id__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_FROM_PAYMENT'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('PAY_FROM_PAYMENT', created.Square_Payment_Id__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_PaymentApiThrows_StillUsesOrderCustomer() {
        Account acc = createPersonAccount('CUST_PAYMENT_THROWS');
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_PAYMENT_THROWS', 'CUST_PAYMENT_THROWS', 'PAY_PAYMENT_THROWS', 'COMPLETED', 1000),
                null,
                null
            ).withPaymentThrows()
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_PAYMENT_THROWS', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Financial_Status__c, Fulfillment_Status__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_PAYMENT_THROWS'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('Paid', created.Financial_Status__c);
        System.assertEquals('Fulfilled', created.Fulfillment_Status__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_CustomerApiThrows_FallsBackToExistingPersonAccount() {
        Account acc = createPersonAccount('CUST_CUSTOMER_THROWS');
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_CUSTOMER_THROWS', 'CUST_CUSTOMER_THROWS', 'PAY_CUSTOMER_THROWS', 'COMPLETED', 1100),
                payment('PAY_CUSTOMER_THROWS', 'CUST_CUSTOMER_THROWS', 1100, 0),
                null
            ).withCustomerThrows()
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_CUSTOMER_THROWS', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Financial_Status__c, Fulfillment_Status__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_CUSTOMER_THROWS'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('Paid', created.Financial_Status__c);
        System.assertEquals('Fulfilled', created.Fulfillment_Status__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_CustomerResponseWithNoPayment_CoversPaymentForCustomerFallback() {
        Account acc = createPersonAccount('CUST_CUSTOMER_ONLY');
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_CUSTOMER_ONLY', 'CUST_CUSTOMER_ONLY', null, 'COMPLETED', 1250),
                null,
                customer('CUST_CUSTOMER_ONLY')
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_CUSTOMER_ONLY', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Square_Order_Id__c, Square_Payment_Id__c,
                   Financial_Status__c, Fulfillment_Status__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_CUSTOMER_ONLY'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals(null, created.Square_Payment_Id__c);
        System.assertEquals('Paid', created.Financial_Status__c);
        System.assertEquals('Fulfilled', created.Fulfillment_Status__c);
    }
    
    @IsTest
    static void testSyncSquareOrder_AssignsSquarePricebookWhenPresent() {
        Account acc = createPersonAccount('CUST_PRICEBOOK');
        Pricebook2 squarePb = new Pricebook2(Name = 'Square Pricebook', IsActive = true);
        insert squarePb;
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_PRICEBOOK', 'CUST_PRICEBOOK', 'PAY_PRICEBOOK', 'COMPLETED', 1500),
                payment('PAY_PRICEBOOK', 'CUST_PRICEBOOK', 1500, 0),
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_PRICEBOOK', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Pricebook2Id
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_PRICEBOOK'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals(squarePb.Id, created.Pricebook2Id);
    }
    
    @IsTest
    static void testSyncSquareOrder_AssignsWarehouseInventoryLocation() {
        Account acc = createPersonAccount('CUST_LOCATION');
        Id warehouseLocationId = createWarehouseLocationIfPossible();
        System.assertNotEquals(
            null,
            warehouseLocationId,
            'The test must create a Salesforce Location named Warehouse.'
        );
        
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder('ORD_LOCATION', 'CUST_LOCATION', null, 'COMPLETED', 1500),
                null,
                null
            )
        );
        
        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder('ORD_LOCATION', 'order.created', '{}');
        Test.stopTest();
        
        Order created = [
            SELECT AccountId, Location__c, Square_Location_Id__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_LOCATION'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('LOC_001', created.Square_Location_Id__c,
            'Square location identifier must remain stored on Square_Location_Id__c.');
        
        if (warehouseLocationId != null) {
            System.assertEquals(
                warehouseLocationId,
                created.Location__c,
                'Order.Location__c must refer to the Salesforce Warehouse inventory Location.'
            );
        }
    }
    
    @IsTest
    static void testSyncSquareOrder_AssignsProviderCustomerBySquareLocationIdOnly() {
        SObject providerCustomer = createProviderCustomerMapping('LOC_001');
        Account customerAccount = createPersonAccount('CUST_PROVIDER_LOOKUP');

        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                squareOrder(
                    'ORD_PROVIDER_LOOKUP',
                    'CUST_PROVIDER_LOOKUP',
                    null,
                    'COMPLETED',
                    2500
                ),
                null,
                null
            )
        );

        Test.startTest();
        SquareOrderStatusSyncService.syncSquareOrder(
            'ORD_PROVIDER_LOOKUP',
            'order.created',
            '{}'
        );
        Test.stopTest();

        Order created = [
            SELECT Id, AccountId, Square_Location_Id__c,
                   Location__c, Pop_up_Provider__c
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_PROVIDER_LOOKUP'
            LIMIT 1
        ];

        System.assertEquals(customerAccount.Id, created.AccountId,
            'Order.AccountId remains the purchasing Person Account.');
        System.assertEquals('LOC_001', created.Square_Location_Id__c);
        System.assertEquals(
            (Id) providerCustomer.get('Id'),
            created.Pop_up_Provider__c,
            'Order.Pop_up_Provider__c must reference the Customer whose Square_Location_Id__c matches.'
        );

        // Location__c remains the Salesforce Warehouse inventory Location.
        // It must not be used for resolving the Pop-up Provider Customer.
        Id warehouseLocationId = InventoryRuleService.getLocationIdForOrderType('POS');
        if (warehouseLocationId != null) {
            System.assertEquals(warehouseLocationId, created.Location__c);
        }
    }

    // =====================================================================
    // Direct method tests: duplicate recovery and update paths
    // =====================================================================
    
    @IsTest
    static void testInsertOrderWithDuplicateRecovery_SuccessPath() {
        Account acc = createPersonAccount('CUST_INSERT_SUCCESS');
        
        Map<String, Object> sqOrder = squareOrder(
            'ORD_INSERT_SUCCESS',
            'CUST_INSERT_SUCCESS',
            'PAY_INSERT_SUCCESS',
            'COMPLETED',
            1000
        );
        
        Order ord = new Order(
            AccountId             = acc.Id,
            EffectiveDate         = Date.today(),
            Status                = 'Draft',
            Type                  = 'POS',
            Square_Order_Id__c    = 'ORD_INSERT_SUCCESS',
            Square_Payment_Id__c  = 'PAY_INSERT_SUCCESS',
            Square_Location_Id__c = 'LOC_INSERT_SUCCESS',
            Shop_Total_Amount__c  = 10.00,
            Square_Raw_JSON__c    = JSON.serialize(sqOrder),
            Financial_Status__c   = 'Paid',
            Fulfillment_Status__c = 'Fulfilled'
        );
        
        Test.startTest();
        
        SquareOrderStatusSyncService.insertOrderWithDuplicateRecovery(
            ord,
            'ORD_INSERT_SUCCESS',
            'PAY_INSERT_SUCCESS',
            acc.Id,
            'LOC_INSERT_SUCCESS',
            'Paid',
            'Fulfilled',
            10.00,
            sqOrder,
            false,
            null // popUpProviderCustomerId not required in this test
        );
        
        Test.stopTest();
        
        Order created = [
            SELECT Id, AccountId, Square_Order_Id__c, Square_Payment_Id__c,
                   Square_Location_Id__c, Shop_Total_Amount__c,
                   Financial_Status__c, Fulfillment_Status__c, Type, Status
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_INSERT_SUCCESS'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('ORD_INSERT_SUCCESS', created.Square_Order_Id__c);
        System.assertEquals('PAY_INSERT_SUCCESS', created.Square_Payment_Id__c);
        System.assertEquals('LOC_INSERT_SUCCESS', created.Square_Location_Id__c);
        System.assertEquals(10.00, created.Shop_Total_Amount__c);
        System.assertEquals('Paid', created.Financial_Status__c);
        System.assertEquals('Fulfilled', created.Fulfillment_Status__c);
        System.assertEquals('POS', created.Type);
        System.assertEquals('Draft', created.Status);
    }
    
    @IsTest
    static void testInsertOrderWithDuplicateRecovery_FullyRefundedInsertPath() {
        Account acc = createPersonAccount('CUST_INSERT_REFUND');
        
        Map<String, Object> sqOrder = squareOrder(
            'ORD_INSERT_REFUND',
            'CUST_INSERT_REFUND',
            'PAY_INSERT_REFUND',
            'COMPLETED',
            1000
        );
        
        Order ord = new Order(
            AccountId             = acc.Id,
            EffectiveDate         = Date.today(),
            Status                = 'Draft',
            Type                  = 'POS',
            Square_Order_Id__c    = 'ORD_INSERT_REFUND',
            Square_Payment_Id__c  = 'PAY_INSERT_REFUND',
            Square_Location_Id__c = 'LOC_INSERT_REFUND',
            Shop_Total_Amount__c  = 10.00,
            Square_Raw_JSON__c    = JSON.serialize(sqOrder),
            Financial_Status__c   = 'Refunded',
            Fulfillment_Status__c = 'Unfulfilled'
        );
        
        Test.startTest();
        
        SquareOrderStatusSyncService.insertOrderWithDuplicateRecovery(
            ord,
            'ORD_INSERT_REFUND',
            'PAY_INSERT_REFUND',
            acc.Id,
            'LOC_INSERT_REFUND',
            'Paid',
            'Fulfilled',
            10.00,
            sqOrder,
            true,
            null // popUpProviderCustomerId not required in this test
        );
        
        Test.stopTest();
        
        Order created = [
            SELECT Id, AccountId, Square_Order_Id__c, Square_Payment_Id__c,
                   Square_Location_Id__c, Shop_Total_Amount__c,
                   Financial_Status__c, Fulfillment_Status__c, Type, Status
            FROM Order
            WHERE Square_Order_Id__c = 'ORD_INSERT_REFUND'
            LIMIT 1
        ];
        
        System.assertEquals(acc.Id, created.AccountId);
        System.assertEquals('ORD_INSERT_REFUND', created.Square_Order_Id__c);
        System.assertEquals('PAY_INSERT_REFUND', created.Square_Payment_Id__c);
        System.assertEquals('LOC_INSERT_REFUND', created.Square_Location_Id__c);
        System.assertEquals(10.00, created.Shop_Total_Amount__c);
        System.assertEquals('Refunded', created.Financial_Status__c);
        System.assertEquals('Unfulfilled', created.Fulfillment_Status__c);
        System.assertEquals('POS', created.Type);
        System.assertEquals('Draft', created.Status);
    }
    
    @IsTest
    static void testInsertOrderWithDuplicateRecovery_NonDuplicateFailureThrows() {
        Account acc = createPersonAccount('CUST_NON_DUP_FAIL');
        Order badOrder = new Order(Status = 'Draft', Type = 'POS');
        
        Boolean threwExpectedException = false;
        
        Test.startTest();
        try {
            SquareOrderStatusSyncService.insertOrderWithDuplicateRecovery(
                badOrder,
                'ORD_NON_DUP_FAIL',
                'PAY_NON_DUP_FAIL',
                acc.Id,
                'LOC_001',
                'Paid',
                'Fulfilled',
                10.00,
                squareOrder('ORD_NON_DUP_FAIL', 'CUST_NON_DUP_FAIL', 'PAY_NON_DUP_FAIL', 'COMPLETED', 1000),
                false,
                null // popUpProviderCustomerId not required in this test
            );
        } catch (DmlException e) {
            threwExpectedException = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, threwExpectedException);
    }
    
    @IsTest
    static void testUpdateOrder_SuccessPath() {
        Account acc = createPersonAccount('CUST_UPDATE_SUCCESS');
        Order ord = createDraftOrder(
            acc.Id,
            'ORD_UPDATE_SUCCESS',
            'PAY_UPDATE_SUCCESS',
            'Pending',
            'Unfulfilled'
        );
        
        ord.Financial_Status__c = 'Paid';
        ord.Fulfillment_Status__c = 'Fulfilled';
        ord.Shop_Total_Amount__c = 44.44;
        
        Test.startTest();
        SquareOrderStatusSyncService.updateOrder(
            ord,
            'ORD_UPDATE_SUCCESS',
            'PAY_UPDATE_SUCCESS'
        );
        Test.stopTest();
        
        Order updated = [
            SELECT Financial_Status__c, Fulfillment_Status__c, Shop_Total_Amount__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];
        
        System.assertEquals('Paid', updated.Financial_Status__c);
        System.assertEquals('Fulfilled', updated.Fulfillment_Status__c);
        System.assertEquals(44.44, updated.Shop_Total_Amount__c);
    }
    
    @IsTest
    static void testUpdateOrder_FailurePathDoesNotThrow() {
        Account acc = createPersonAccount('CUST_UPDATE_FAIL');
        Order ord = createDraftOrder(
            acc.Id,
            'ORD_UPDATE_FAIL',
            'PAY_UPDATE_FAIL',
            'Pending',
            'Unfulfilled'
        );
        ord.EffectiveDate = null;
        
        Test.startTest();
        SquareOrderStatusSyncService.updateOrder(
            ord,
            'ORD_UPDATE_FAIL',
            'PAY_UPDATE_FAIL'
        );
        Test.stopTest();
        
        Order unchanged = [
            SELECT EffectiveDate
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, unchanged.EffectiveDate);
    }
    
    // =====================================================================
    // Direct method tests: finders
    // =====================================================================
    
    @IsTest
    static void testFindExistingOrder_ByPaymentIdOrderIdAndMissing() {
        Account acc = createPersonAccount('CUST_FINDERS');
        Order byPayment = createDraftOrder(acc.Id, null, 'PAY_FIND_ME', 'Pending', 'Unfulfilled');
        Order byOrder = createDraftOrder(acc.Id, 'ORD_FIND_ME', null, 'Pending', 'Unfulfilled');
        
        Test.startTest();
        Order foundByPayment = SquareOrderStatusSyncService.findExistingOrder('PAY_FIND_ME', 'ORD_X');
        Order foundByOrder = SquareOrderStatusSyncService.findExistingOrder(null, 'ORD_FIND_ME');
        Order missing = SquareOrderStatusSyncService.findExistingOrder('PAY_MISSING', 'ORD_MISSING');
        Order blank = SquareOrderStatusSyncService.findExistingOrder(null, null);
        Test.stopTest();
        
        System.assertEquals(byPayment.Id, foundByPayment.Id);
        System.assertEquals(byOrder.Id, foundByOrder.Id);
        System.assertEquals(null, missing);
        System.assertEquals(null, blank);
    }
    
    @IsTest
    static void testFindExistingOrderIncludingDeleted_ByPaymentOrderAndMissing() {
        Account acc = createPersonAccount('CUST_DELETED_FINDERS');
        Order byPayment = createDraftOrder(acc.Id, 'ORD_DEL_PAY', 'PAY_DEL_PAY', 'Pending', 'Unfulfilled');
        Order byOrder = createDraftOrder(acc.Id, 'ORD_DEL_ORDER', null, 'Pending', 'Unfulfilled');
        delete new List<Order>{ byPayment, byOrder };
        
        Test.startTest();
        Order foundByPayment = SquareOrderStatusSyncService.findExistingOrderIncludingDeleted('PAY_DEL_PAY', 'ORD_DEL_PAY');
        Order foundByOrder = SquareOrderStatusSyncService.findExistingOrderIncludingDeleted(null, 'ORD_DEL_ORDER');
        Order missing = SquareOrderStatusSyncService.findExistingOrderIncludingDeleted('PAY_MISSING_DEL', 'ORD_MISSING_DEL');
        Test.stopTest();
        
        System.assertNotEquals(null, foundByPayment);
        System.assertEquals(true, foundByPayment.IsDeleted);
        System.assertNotEquals(null, foundByOrder);
        System.assertEquals(true, foundByOrder.IsDeleted);
        System.assertEquals(null, missing);
    }
    
    // =====================================================================
    // Direct method tests: helpers
    // =====================================================================
    
    @IsTest
    static void testSquareOrderHasLineItems_AllBranches() {
        System.assertEquals(false, SquareOrderStatusSyncService.squareOrderHasLineItems(null));
        System.assertEquals(false, SquareOrderStatusSyncService.squareOrderHasLineItems(new Map<String, Object>()));
        System.assertEquals(false, SquareOrderStatusSyncService.squareOrderHasLineItems(
            new Map<String, Object>{ 'line_items' => 'not_a_list' }
        ));
        System.assertEquals(false, SquareOrderStatusSyncService.squareOrderHasLineItems(
            new Map<String, Object>{ 'line_items' => new List<Object>() }
        ));
        System.assertEquals(true, SquareOrderStatusSyncService.squareOrderHasLineItems(
            new Map<String, Object>{
                'line_items' => new List<Object>{
                    new Map<String, Object>{ 'uid' => 'line_1' }
                }
            }
        ));
    }
    
    @IsTest
    static void testExtractSalesforceIdFromDuplicateException() {
        System.assertEquals(null, SquareOrderStatusSyncService.extractSalesforceIdFromDuplicateException(null));
        System.assertEquals(null, SquareOrderStatusSyncService.extractSalesforceIdFromDuplicateException(''));
        System.assertEquals(null, SquareOrderStatusSyncService.extractSalesforceIdFromDuplicateException('no id here'));
        System.assertEquals(
            '8010g000001abcdef',
            SquareOrderStatusSyncService.extractSalesforceIdFromDuplicateException(
                'DUPLICATE_VALUE duplicates value on record with id: 8010g000001abcdef: []'
            )
        );
    }
    
    @IsTest
    static void testFindPersonAccountIdBySquareCustomerId() {
        Account acc = createPersonAccount('CUST_LOOKUP');
        
        System.assertEquals(null, SquareOrderStatusSyncService.findPersonAccountIdBySquareCustomerId(null));
        System.assertEquals(null, SquareOrderStatusSyncService.findPersonAccountIdBySquareCustomerId(''));
        System.assertEquals(acc.Id, SquareOrderStatusSyncService.findPersonAccountIdBySquareCustomerId('CUST_LOOKUP'));
        System.assertEquals(acc.Id, SquareOrderStatusSyncService.findPersonAccountIdBySquareCustomerId('  CUST_LOOKUP  '));
        System.assertEquals(null, SquareOrderStatusSyncService.findPersonAccountIdBySquareCustomerId('CUST_MISSING'));
    }
    
    @IsTest
    static void testExtractTotalAmount_AllBranches() {
        System.assertEquals(0, SquareOrderStatusSyncService.extractTotalAmount(null));
        System.assertEquals(
            0,
            SquareOrderStatusSyncService.extractTotalAmount(new Map<String, Object>{ 'id' => 'ORD_NO_TOTAL' })
        );
        System.assertEquals(
            0,
            SquareOrderStatusSyncService.extractTotalAmount(
                new Map<String, Object>{
                    'total_money' => new Map<String, Object>{ 'currency' => 'USD' }
                }
            )
        );
        System.assertEquals(
            12.34,
            SquareOrderStatusSyncService.extractTotalAmount(
                new Map<String, Object>{
                    'total_money' => new Map<String, Object>{ 'amount' => 1234, 'currency' => 'USD' }
                }
            )
        );
    }
    
    @IsTest
    static void testExtractCustomerIdFromSquareOrder_AllBranches() {
        System.assertEquals(null, SquareOrderStatusSyncService.extractCustomerIdFromSquareOrder(null));
        System.assertEquals(
            'CUST_TOP',
            SquareOrderStatusSyncService.extractCustomerIdFromSquareOrder(
                new Map<String, Object>{
                    'customer_id' => 'CUST_TOP',
                    'tenders' => new List<Object>{
                        new Map<String, Object>{ 'customer_id' => 'CUST_TENDER' }
                    }
                }
            )
        );
        System.assertEquals(
            'CUST_TENDER',
            SquareOrderStatusSyncService.extractCustomerIdFromSquareOrder(
                new Map<String, Object>{
                    'tenders' => new List<Object>{
                        'not_a_map',
                        new Map<String, Object>{ 'id' => 'tender_without_customer' },
                        new Map<String, Object>{ 'customer_id' => 'CUST_TENDER' }
                    }
                }
            )
        );
        System.assertEquals(
            null,
            SquareOrderStatusSyncService.extractCustomerIdFromSquareOrder(
                new Map<String, Object>{
                    'tenders' => new List<Object>{
                        new Map<String, Object>{ 'id' => 'tender_without_customer' }
                    }
                }
            )
        );
    }
    
    @IsTest
    static void testExtractPaymentIdFromSquareOrder_AllBranches() {
        System.assertEquals(null, SquareOrderStatusSyncService.extractPaymentIdFromSquareOrder(null));
        System.assertEquals(
            null,
            SquareOrderStatusSyncService.extractPaymentIdFromSquareOrder(new Map<String, Object>{ 'id' => 'ORD_NO_TENDERS' })
        );
        System.assertEquals(
            null,
            SquareOrderStatusSyncService.extractPaymentIdFromSquareOrder(
                new Map<String, Object>{
                    'id' => 'ORD_NON_MAP',
                    'tenders' => new List<Object>{ 'not_a_map' }
                }
            )
        );
        System.assertEquals(
            null,
            SquareOrderStatusSyncService.extractPaymentIdFromSquareOrder(
                new Map<String, Object>{
                    'id' => 'ORD_BLANK',
                    'tenders' => new List<Object>{
                        new Map<String, Object>{ 'payment_id' => '' }
                    }
                }
            )
        );
        System.assertEquals(
            null,
            SquareOrderStatusSyncService.extractPaymentIdFromSquareOrder(
                new Map<String, Object>{
                    'id' => 'ORD_SAME',
                    'tenders' => new List<Object>{
                        new Map<String, Object>{ 'payment_id' => 'ORD_SAME' }
                    }
                }
            )
        );
        System.assertEquals(
            'PAY_SECOND',
            SquareOrderStatusSyncService.extractPaymentIdFromSquareOrder(
                new Map<String, Object>{
                    'id' => 'ORD_SECOND',
                    'tenders' => new List<Object>{
                        new Map<String, Object>{ 'id' => 'tender_without_payment' },
                        new Map<String, Object>{ 'payment_id' => 'PAY_SECOND' }
                    }
                }
            )
        );
    }
    
    @IsTest
    static void testExtractMoneyAmount_AllBranches() {
        Map<String, Object> root = new Map<String, Object>{
            'amount_money' => new Map<String, Object>{ 'amount' => 1234, 'currency' => 'USD' },
            'empty_money'  => new Map<String, Object>{ 'currency' => 'USD' },
            'null_money'   => null
        };
        
        System.assertEquals(0, SquareOrderStatusSyncService.extractMoneyAmount(null, 'amount_money'));
        System.assertEquals(0, SquareOrderStatusSyncService.extractMoneyAmount(root, null));
        System.assertEquals(0, SquareOrderStatusSyncService.extractMoneyAmount(root, ''));
        System.assertEquals(0, SquareOrderStatusSyncService.extractMoneyAmount(root, 'missing_money'));
        System.assertEquals(0, SquareOrderStatusSyncService.extractMoneyAmount(root, 'empty_money'));
        System.assertEquals(0, SquareOrderStatusSyncService.extractMoneyAmount(root, 'null_money'));
        System.assertEquals(1234, SquareOrderStatusSyncService.extractMoneyAmount(root, 'amount_money'));
    }
    
    @IsTest
    static void testMapStatusHelpers() {
        System.assertEquals(
            'Paid',
            SquareOrderStatusSyncService.mapFinancialStatus(new Map<String, Object>{ 'state' => 'COMPLETED' })
        );
        System.assertEquals(
            'Refunded',
            SquareOrderStatusSyncService.mapFinancialStatus(new Map<String, Object>{ 'state' => 'CANCELED' })
        );
        System.assertEquals(
            'Pending',
            SquareOrderStatusSyncService.mapFinancialStatus(new Map<String, Object>{ 'state' => 'OPEN' })
        );
        System.assertEquals(
            'Fulfilled',
            SquareOrderStatusSyncService.mapFulfillmentStatus(new Map<String, Object>(), 'Paid')
        );
        System.assertEquals(
            'Unfulfilled',
            SquareOrderStatusSyncService.mapFulfillmentStatus(new Map<String, Object>(), 'Pending')
        );
        System.assertEquals(
            'Unfulfilled',
            SquareOrderStatusSyncService.mapFulfillmentStatus(new Map<String, Object>(), 'Refunded')
        );
    }
    
    @IsTest
    static void testIsSquarePaymentFullyRefunded_AllBranches() {
        System.assertEquals(false, SquareOrderStatusSyncService.isSquarePaymentFullyRefunded(null));
        System.assertEquals(false, SquareOrderStatusSyncService.isSquarePaymentFullyRefunded(''));
    }
    
    @IsTest
    static void testIsSquarePaymentFullyRefunded_PaymentMissingReturnsFalse() {
        Test.setMock(HttpCalloutMock.class, new SquareEndpointMock(null, null, null));
        
        Test.startTest();
        Boolean result = SquareOrderStatusSyncService.isSquarePaymentFullyRefunded('PAY_MISSING');
        Test.stopTest();
        
        System.assertEquals(false, result);
    }
    
    @IsTest
    static void testIsSquarePaymentFullyRefunded_FullyRefundedReturnsTrue() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                null,
                payment('PAY_FULL_HELPER', null, 1000, 1000),
                null
            )
        );
        
        Test.startTest();
        Boolean result = SquareOrderStatusSyncService.isSquarePaymentFullyRefunded('PAY_FULL_HELPER');
        Test.stopTest();
        
        System.assertEquals(true, result);
    }
    
    @IsTest
    static void testIsSquarePaymentFullyRefunded_PartialRefundReturnsFalse() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(
                null,
                payment('PAY_PARTIAL_HELPER', null, 1000, 200),
                null
            )
        );
        
        Test.startTest();
        Boolean result = SquareOrderStatusSyncService.isSquarePaymentFullyRefunded('PAY_PARTIAL_HELPER');
        Test.stopTest();
        
        System.assertEquals(false, result);
    }
    
    @IsTest
    static void testIsSquarePaymentFullyRefunded_ApiThrowsReturnsFalse() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareEndpointMock(null, null, null).withPaymentThrows()
        );
        
        Test.startTest();
        Boolean result = SquareOrderStatusSyncService.isSquarePaymentFullyRefunded('PAY_ERROR_HELPER');
        Test.stopTest();
        
        System.assertEquals(false, result);
    }
}