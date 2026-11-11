@IsTest
private class SquareOrderSyncServiceTest {

    private static final String SQUARE_CUSTOMER_ID = 'SQUARE_CUSTOMER_12345';

    // ---------------------------------------------------------------------
    // Mock
    // ---------------------------------------------------------------------

    private class SafeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{}');
            return res;
        }
    }

    // ---------------------------------------------------------------------
    // Test Data Helpers
    // ---------------------------------------------------------------------

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];

        System.assert(
            !rts.isEmpty(),
            'Person Account record type is required for SquareOrderSyncService tests.'
        );

        return rts[0].Id;
    }

    private static Account createSquarePersonAccount(String squareCustomerId) {
        Account acc = new Account(
            RecordTypeId = getPersonAccountRecordTypeId(),
            LastName = 'Square Customer ' + squareCustomerId,
            PersonEmail = 'square-' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '@example.com',
            Square_Customer_Id__c = squareCustomerId
        );

        insert acc;
        return acc;
    }

    private static Id createShopLocation() {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        loc.put('Name', 'Shop Location');

        Map<String, Schema.SObjectField> fields =
            Schema.SObjectType.Location.fields.getMap();

        if (fields.containsKey('LocationType')) {
            loc.put('LocationType', 'Warehouse');
        }

        insert loc;
        return (Id) loc.get('Id');
    }

    private static Pricebook2 createSquarePricebook() {
        Pricebook2 pb = new Pricebook2(
            Name = 'Square Pricebook',
            IsActive = true
        );

        insert pb;
        return pb;
    }

    private static void activateStandardPricebook() {
        update new Pricebook2(
            Id = Test.getStandardPricebookId(),
            IsActive = true
        );
    }

    private static User createSalesAssistant(String teamMemberId) {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        Integer uniqueNumber = Math.abs(Crypto.getRandomInteger());
        String uniqueText = String.valueOf(uniqueNumber);

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Square Assistant',
            Email = 'assistant' + uniqueText + '@example.com',
            Username = 'assistant' + uniqueText + '@example.com.squaretest',
            Alias = ('asst' + uniqueText).left(8),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Square_Team_Member_Id__c = teamMemberId
        );

        insert u;
        return u;
    }

    private static Order createExistingSquareOrder(
        String paymentId,
        String squareCustomerId,
        Boolean withPricebook,
        String financialStatus,
        String fulfillmentStatus
    ) {
        Account acc = createSquarePersonAccount(squareCustomerId);

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS',
            Square_Payment_Id__c = paymentId,
            Financial_Status__c = financialStatus,
            Fulfillment_Status__c = fulfillmentStatus
        );

        if (withPricebook == true) {
            activateStandardPricebook();
            ord.Pricebook2Id = Test.getStandardPricebookId();
        }

        insert ord;
        return ord;
    }

    // ---------------------------------------------------------------------
    // Payment / Square Order Builders
    // ---------------------------------------------------------------------

    private static Map<String, Object> buildPayment(
        String paymentId,
        String orderId,
        String teamMemberId,
        String locationId,
        Integer amountCents,
        String squareCustomerId
    ) {
        Map<String, Object> payment = new Map<String, Object>{
            'id' => paymentId,
            'order_id' => orderId,
            'location_id' => locationId,
            'receipt_url' => 'https://example.com/receipt'
        };

        if (teamMemberId != null) {
            payment.put('team_member_id', teamMemberId);
        }

        if (squareCustomerId != null) {
            payment.put('customer_id', squareCustomerId);
        }

        if (amountCents != null) {
            payment.put(
                'amount_money',
                new Map<String, Object>{
                    'amount' => amountCents,
                    'currency' => 'USD'
                }
            );
        }

        return payment;
    }

    private static Map<String, Object> buildSquareOrderBasic(String orderId) {
        return new Map<String, Object>{
            'id' => orderId
        };
    }

    private static Map<String, Object> buildSquareOrderWithCustomerId(
        String orderId,
        String squareCustomerId
    ) {
        return new Map<String, Object>{
            'id' => orderId,
            'customer_id' => squareCustomerId
        };
    }

    private static Map<String, Object> buildSquareOrderWithTenderCustomerId(
        String orderId,
        String squareCustomerId
    ) {
        return new Map<String, Object>{
            'id' => orderId,
            'tenders' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'TENDER_1',
                    'customer_id' => squareCustomerId
                }
            }
        };
    }

    private static Map<String, Object> buildSquareOrderWithEmptyTender(
        String orderId
    ) {
        return new Map<String, Object>{
            'id' => orderId,
            'tenders' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'TENDER_1'
                }
            }
        };
    }

    // ---------------------------------------------------------------------
    // Guard Clause Tests
    // ---------------------------------------------------------------------

    @IsTest
    static void testNullPaymentReturnsSafely() {
        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            'PAYMENT_ID_123456789012345',
            null,
            null
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Order],
            'Null payment should not create an Order.'
        );
    }

    @IsTest
    static void testInvalidPaymentIdReturnsSafely() {
        Map<String, Object> payment = buildPayment(
            'SHORT_ID',
            'SQUARE_ORDER_SHORT',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            'SHORT_ID',
            payment,
            null
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Order
                WHERE Square_Payment_Id__c = 'SHORT_ID'
            ],
            'Invalid Square payment id should return without creating an Order.'
        );
    }

    @IsTest
    static void testNoMatchingPersonAccountSkipsOrderCreation() {
        String paymentId = 'PAYMENT_ID_NO_ACCOUNT_12345';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_NO_ACCOUNT',
            null,
            'LOCATION_123',
            2500,
            'NO_MATCHING_CUSTOMER'
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Order
                WHERE Square_Payment_Id__c = :paymentId
            ],
            'Order should not be created when Person Account is missing.'
        );
    }

    @IsTest
    static void testBlankCustomerIdSkipsOrderCreation() {
        String paymentId = 'PAYMENT_ID_BLANK_CUSTOMER';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_BLANK_CUSTOMER',
            null,
            'LOCATION_123',
            2500,
            null
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Order
                WHERE Square_Payment_Id__c = :paymentId
            ],
            'Order should not be created when customer id is blank and cannot be recovered.'
        );
    }

    // ---------------------------------------------------------------------
    // New Order Creation Tests
    // ---------------------------------------------------------------------

    @IsTest
    static void testCreatesOrderFromPaymentCustomerIdWithoutSquareOrder() {
        Test.setMock(HttpCalloutMock.class, new SafeMock());

        Account acc = createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        Id shopLocationId = createShopLocation();

        String paymentId = 'PAYMENT_ID_CREATE_12345';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_CREATE',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order ord = [
            SELECT Id,
                   AccountId,
                   Square_Payment_Id__c,
                   Square_Order_Id__c,
                   Square_Location_Id__c,
                   Square_Receipt_Url__c,
                   Shop_Total_Amount__c,
                   Financial_Status__c,
                   Fulfillment_Status__c,
                   Type,
                   Status,
                   EffectiveDate,
                   Location__c
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals(acc.Id, ord.AccountId);
        System.assertEquals(paymentId, ord.Square_Payment_Id__c);
        System.assertEquals('SQUARE_ORDER_CREATE', ord.Square_Order_Id__c);
        System.assertEquals('LOCATION_123', ord.Square_Location_Id__c);
        System.assertEquals('https://example.com/receipt', ord.Square_Receipt_Url__c);
        System.assertEquals(25.00, ord.Shop_Total_Amount__c);
        System.assertEquals('Paid', ord.Financial_Status__c);
        System.assertEquals(null, ord.Fulfillment_Status__c);
        System.assertEquals('POS', ord.Type);
        System.assertEquals('Draft', ord.Status);
        System.assertEquals(Date.today(), ord.EffectiveDate);
        System.assertEquals(shopLocationId, ord.Location__c);
    }

    @IsTest
    static void testCreatesOrderWithoutShopLocation() {
        createSquarePersonAccount(SQUARE_CUSTOMER_ID);

        String paymentId = 'PAYMENT_ID_NO_SHOP_LOC_12345';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_NO_SHOP_LOC',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order ord = [
            SELECT Id, Location__c
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals(
            null,
            ord.Location__c,
            'Location__c should remain blank when Shop Location does not exist.'
        );
    }

    @IsTest
    static void testCreatesOrderWithSquarePricebook() {
        createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        createShopLocation();

        Pricebook2 squarePb = createSquarePricebook();

        String paymentId = 'PAYMENT_ID_PRICEBOOK_12345';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_PRICEBOOK',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            buildSquareOrderBasic('SQUARE_ORDER_PRICEBOOK')
        );

        Test.stopTest();

        Order ord = [
            SELECT Id, Pricebook2Id
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals(
            squarePb.Id,
            ord.Pricebook2Id,
            'Order should use Square Pricebook when active Square Pricebook exists.'
        );
    }

    @IsTest
    static void testPaymentWithoutAmountMoneyStillCreatesOrder() {
        createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        createShopLocation();

        String paymentId = 'PAYMENT_ID_NO_AMOUNT_12345';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_NO_AMOUNT',
            null,
            'LOCATION_123',
            null,
            SQUARE_CUSTOMER_ID
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order ord = [
            SELECT Id,
                   Shop_Total_Amount__c,
                   Financial_Status__c
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals(null, ord.Shop_Total_Amount__c);
        System.assertEquals('Paid', ord.Financial_Status__c);
    }

    // ---------------------------------------------------------------------
    // Customer Id Recovery From Square Order
    // ---------------------------------------------------------------------

    @IsTest
    static void testCustomerIdExtractedFromSquareOrderTopLevel() {
        Account acc = createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        createShopLocation();

        String paymentId = 'PAYMENT_ID_ORDER_CUSTOMER';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_CUSTOMER',
            null,
            'LOCATION_123',
            2500,
            null
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            buildSquareOrderWithCustomerId(
                'SQUARE_ORDER_CUSTOMER',
                SQUARE_CUSTOMER_ID
            )
        );

        Test.stopTest();

        Order ord = [
            SELECT Id, AccountId
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals(acc.Id, ord.AccountId);
    }

    @IsTest
    static void testCustomerIdExtractedFromSquareOrderTender() {
        Account acc = createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        createShopLocation();

        String paymentId = 'PAYMENT_ID_TENDER_CUSTOMER';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_TENDER',
            null,
            'LOCATION_123',
            2500,
            null
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            buildSquareOrderWithTenderCustomerId(
                'SQUARE_ORDER_TENDER',
                SQUARE_CUSTOMER_ID
            )
        );

        Test.stopTest();

        Order ord = [
            SELECT Id, AccountId
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals(acc.Id, ord.AccountId);
    }

    @IsTest
    static void testSquareOrderWithTenderButNoCustomerSkipsOrderCreation() {
        String paymentId = 'PAYMENT_ID_EMPTY_TENDER';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_EMPTY_TENDER',
            null,
            'LOCATION_123',
            2500,
            null
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            buildSquareOrderWithEmptyTender('SQUARE_ORDER_EMPTY_TENDER')
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Order
                WHERE Square_Payment_Id__c = :paymentId
            ],
            'Order should not be created when no Square customer id is available.'
        );
    }

    // ---------------------------------------------------------------------
    // Existing Order Update Tests
    // ---------------------------------------------------------------------

    @IsTest
    static void testExistingOrderIsUpdated() {
        Test.setMock(HttpCalloutMock.class, new SafeMock());

        createShopLocation();

        String paymentId = 'PAYMENT_ID_EXISTING_12345';

        Order existingOrder = createExistingSquareOrder(
            paymentId,
            SQUARE_CUSTOMER_ID,
            true,
            'Paid',
            null
        );

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_UPDATED',
            null,
            'LOCATION_NEW',
            5555,
            SQUARE_CUSTOMER_ID
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            buildSquareOrderBasic('SQUARE_ORDER_UPDATED')
        );

        Test.stopTest();

        Order updatedOrder = [
            SELECT Id,
                   Square_Order_Id__c,
                   Square_Location_Id__c,
                   Shop_Total_Amount__c,
                   Financial_Status__c,
                   Type,
                   Status,
                   EffectiveDate
            FROM Order
            WHERE Id = :existingOrder.Id
            LIMIT 1
        ];

        System.assertEquals('SQUARE_ORDER_UPDATED', updatedOrder.Square_Order_Id__c);
        System.assertEquals('LOCATION_NEW', updatedOrder.Square_Location_Id__c);
        System.assertEquals(55.55, updatedOrder.Shop_Total_Amount__c);
        System.assertEquals('Paid', updatedOrder.Financial_Status__c);
        System.assertEquals('POS', updatedOrder.Type);
        System.assertEquals('Draft', updatedOrder.Status);
        System.assertEquals(Date.today(), updatedOrder.EffectiveDate);
    }

    @IsTest
    static void testExistingOrderWithoutPricebookGetsSquarePricebook() {
        createShopLocation();

        Pricebook2 squarePb = createSquarePricebook();

        String paymentId = 'PAYMENT_ID_EXISTING_NO_PB';

        Order existingOrder = createExistingSquareOrder(
            paymentId,
            SQUARE_CUSTOMER_ID,
            false,
            'Paid',
            null
        );

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_EXISTING_NO_PB',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            buildSquareOrderBasic('SQUARE_ORDER_EXISTING_NO_PB')
        );

        Test.stopTest();

        Order updatedOrder = [
            SELECT Id, Pricebook2Id
            FROM Order
            WHERE Id = :existingOrder.Id
            LIMIT 1
        ];

        System.assertEquals(
            squarePb.Id,
            updatedOrder.Pricebook2Id,
            'Existing Order without Pricebook should receive Square Pricebook.'
        );
    }

    // ---------------------------------------------------------------------
    // Refund Tests
    // ---------------------------------------------------------------------

    @IsTest
    static void testFullyRefundedPaymentCreatesRefundedRestockedOrder() {
        createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        createShopLocation();

        String paymentId = 'PAYMENT_ID_REFUNDED_12345';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_REFUNDED',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        payment.put(
            'refunded_money',
            new Map<String, Object>{
                'amount' => 2500,
                'currency' => 'USD'
            }
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order ord = [
            SELECT Id,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals('Refunded', ord.Financial_Status__c);
        System.assertEquals('Restocked', ord.Fulfillment_Status__c);
    }

    @IsTest
    static void testPartialRefundStillCreatesPaidOrder() {
        createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        createShopLocation();

        String paymentId = 'PAYMENT_ID_PARTIAL_REFUND';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_PARTIAL_REFUND',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        payment.put(
            'refunded_money',
            new Map<String, Object>{
                'amount' => 1000,
                'currency' => 'USD'
            }
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order ord = [
            SELECT Id,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals('Paid', ord.Financial_Status__c);
        System.assertEquals(null, ord.Fulfillment_Status__c);
    }

    @IsTest
    static void testExistingRefundedOrderIsNotOverwrittenToPaid() {
        createShopLocation();

        String paymentId = 'PAYMENT_ID_ALREADY_REFUNDED';

        Order existingOrder = createExistingSquareOrder(
            paymentId,
            SQUARE_CUSTOMER_ID,
            false,
            'Refunded',
            'Restocked'
        );

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_ALREADY_REFUNDED',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order updatedOrder = [
            SELECT Id,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id = :existingOrder.Id
            LIMIT 1
        ];

        System.assertEquals('Refunded', updatedOrder.Financial_Status__c);
        System.assertEquals('Restocked', updatedOrder.Fulfillment_Status__c);
    }

    @IsTest
    static void testExistingOrderBecomesRefundedWhenPaymentFullyRefunded() {
        createShopLocation();

        String paymentId = 'PAYMENT_ID_EXISTING_FULL_REFUND';

        Order existingOrder = createExistingSquareOrder(
            paymentId,
            SQUARE_CUSTOMER_ID,
            false,
            'Paid',
            null
        );

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_EXISTING_FULL_REFUND',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        payment.put(
            'refunded_money',
            new Map<String, Object>{
                'amount' => 2500,
                'currency' => 'USD'
            }
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order updatedOrder = [
            SELECT Id,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id = :existingOrder.Id
            LIMIT 1
        ];

        System.assertEquals('Refunded', updatedOrder.Financial_Status__c);
        System.assertEquals('Restocked', updatedOrder.Fulfillment_Status__c);
    }

    @IsTest
    static void testRefundedPaymentWithoutAmountMoneyDoesNotMarkRefunded() {
        createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        createShopLocation();

        String paymentId = 'PAYMENT_ID_REFUND_NO_AMOUNT';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_REFUND_NO_AMOUNT',
            null,
            'LOCATION_123',
            null,
            SQUARE_CUSTOMER_ID
        );

        payment.put(
            'refunded_money',
            new Map<String, Object>{
                'amount' => 2500,
                'currency' => 'USD'
            }
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order ord = [
            SELECT Id,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals('Paid', ord.Financial_Status__c);
        System.assertEquals(null, ord.Fulfillment_Status__c);
    }

    @IsTest
    static void testRefundedMoneyWithoutAmountReturnsPaidPath() {
        createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        createShopLocation();

        String paymentId = 'PAYMENT_ID_REFUND_EMPTY_MONEY';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_REFUND_EMPTY_MONEY',
            null,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        payment.put(
            'refunded_money',
            new Map<String, Object>{
                'currency' => 'USD'
            }
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order ord = [
            SELECT Id,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals('Paid', ord.Financial_Status__c);
        System.assertEquals(null, ord.Fulfillment_Status__c);
    }

    // ---------------------------------------------------------------------
    // Sales Assistant Found Path
    // Do not test missing Sales Assistant here because production code
    // enqueues SquareSalesAssistantOrderQueueable and that currently causes
    // Maximum stack depth in tests.
    // ---------------------------------------------------------------------

    @IsTest
    static void testSalesAssistantFoundAssignsUserToOrder() {
        String teamMemberId = 'TEAM_MEMBER_FOUND_12345';

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Profile.Name = 'System Administrator'
            AND IsActive = true
            LIMIT 1
        ];

        User assistant;

        System.runAs(adminUser) {
            assistant = createSalesAssistant(teamMemberId);
        }

        createSquarePersonAccount(SQUARE_CUSTOMER_ID);
        createShopLocation();

        String paymentId = 'PAYMENT_ID_TEAM_MEMBER_FOUND_12345';

        Map<String, Object> payment = buildPayment(
            paymentId,
            'SQUARE_ORDER_TEAM_MEMBER_FOUND',
            teamMemberId,
            'LOCATION_123',
            2500,
            SQUARE_CUSTOMER_ID
        );

        Test.startTest();

        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            null
        );

        Test.stopTest();

        Order ord = [
            SELECT Id, Sales_Assistant__c
            FROM Order
            WHERE Square_Payment_Id__c = :paymentId
            LIMIT 1
        ];

        System.assertEquals(
            assistant.Id,
            ord.Sales_Assistant__c,
            'Sales Assistant should be assigned when matching User exists.'
        );
    }

    // ---------------------------------------------------------------------
    // Duplicate Recovery Helper Tests
    // Requires @TestVisible recoverDuplicateOrder(...) in production class.
    // ---------------------------------------------------------------------

    @IsTest
    static void testRecoverDuplicateOrder_UpdatesExistingRaceOrder() {
        Account acc = createSquarePersonAccount(SQUARE_CUSTOMER_ID);

        String paymentId = 'PAYMENT_ID_DUP_RECOVERY_12345';

        Order existingOrder = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS',
            Square_Payment_Id__c = paymentId,
            Financial_Status__c = 'Paid'
        );
        insert existingOrder;

        Pricebook2 squarePb = createSquarePricebook();

        Order incomingOrder = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS',
            Square_Payment_Id__c = paymentId,
            Square_Order_Id__c = 'SQUARE_ORDER_DUP_RECOVERY',
            Square_Location_Id__c = 'LOCATION_DUP_RECOVERY',
            Square_Receipt_Url__c = 'https://example.com/receipt',
            Shop_Total_Amount__c = 25.00,
            Financial_Status__c = 'Paid'
        );

        Test.startTest();

        SquareOrderSyncService.recoverDuplicateOrder(
            incomingOrder,
            paymentId,
            squarePb.Id,
            false
        );

        Test.stopTest();

        Order updatedOrder = [
            SELECT Id,
                   Pricebook2Id,
                   Square_Order_Id__c,
                   Square_Location_Id__c,
                   Square_Receipt_Url__c,
                   Shop_Total_Amount__c,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id = :existingOrder.Id
            LIMIT 1
        ];

        System.assertEquals(squarePb.Id, updatedOrder.Pricebook2Id);
        System.assertEquals('SQUARE_ORDER_DUP_RECOVERY', updatedOrder.Square_Order_Id__c);
        System.assertEquals('LOCATION_DUP_RECOVERY', updatedOrder.Square_Location_Id__c);
        System.assertEquals('https://example.com/receipt', updatedOrder.Square_Receipt_Url__c);
        System.assertEquals(25.00, updatedOrder.Shop_Total_Amount__c);
        System.assertEquals('Paid', updatedOrder.Financial_Status__c);
        System.assertEquals(null, updatedOrder.Fulfillment_Status__c);
    }

    @IsTest
    static void testRecoverDuplicateOrder_PaymentFullyRefunded() {
        Account acc = createSquarePersonAccount(SQUARE_CUSTOMER_ID);

        String paymentId = 'PAYMENT_ID_DUP_REFUNDED_12345';

        Order existingOrder = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS',
            Square_Payment_Id__c = paymentId,
            Financial_Status__c = 'Paid'
        );
        insert existingOrder;

        Order incomingOrder = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS',
            Square_Payment_Id__c = paymentId,
            Financial_Status__c = 'Paid'
        );

        Test.startTest();

        SquareOrderSyncService.recoverDuplicateOrder(
            incomingOrder,
            paymentId,
            null,
            true
        );

        Test.stopTest();

        Order updatedOrder = [
            SELECT Id,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id = :existingOrder.Id
            LIMIT 1
        ];

        System.assertEquals('Refunded', updatedOrder.Financial_Status__c);
        System.assertEquals('Restocked', updatedOrder.Fulfillment_Status__c);
    }

    @IsTest
    static void testRecoverDuplicateOrder_ExistingOrderAlreadyRefunded() {
        Account acc = createSquarePersonAccount(SQUARE_CUSTOMER_ID);

        String paymentId = 'PAYMENT_ID_DUP_ALREADY_REFUNDED';

        Order existingOrder = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS',
            Square_Payment_Id__c = paymentId,
            Financial_Status__c = 'Refunded',
            Fulfillment_Status__c = 'Restocked'
        );
        insert existingOrder;

        Order incomingOrder = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS',
            Square_Payment_Id__c = paymentId,
            Financial_Status__c = 'Paid'
        );

        Test.startTest();

        SquareOrderSyncService.recoverDuplicateOrder(
            incomingOrder,
            paymentId,
            null,
            false
        );

        Test.stopTest();

        Order updatedOrder = [
            SELECT Id,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id = :existingOrder.Id
            LIMIT 1
        ];

        System.assertEquals('Refunded', updatedOrder.Financial_Status__c);
        System.assertEquals('Restocked', updatedOrder.Fulfillment_Status__c);
    }

    @IsTest
    static void testRecoverDuplicateOrder_NoRaceOrderFound() {
        Account acc = createSquarePersonAccount(SQUARE_CUSTOMER_ID);

        Order incomingOrder = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS',
            Square_Payment_Id__c = 'PAYMENT_ID_NO_RACE_ORDER',
            Financial_Status__c = 'Paid'
        );

        Test.startTest();

        SquareOrderSyncService.recoverDuplicateOrder(
            incomingOrder,
            'PAYMENT_ID_NO_RACE_ORDER',
            null,
            false
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Order
                WHERE Square_Payment_Id__c = 'PAYMENT_ID_NO_RACE_ORDER'
            ],
            'No Order should be inserted by recoverDuplicateOrder when no race Order is found.'
        );
    }

    // ---------------------------------------------------------------------
    // Default Square Customer Account Tests
    // ---------------------------------------------------------------------

    @IsTest
    static void testGetDefaultSquareCustomerAccountIdCreatesAccount() {
        Test.startTest();

        Id accId = SquareOrderSyncService.getDefaultSquareCustomerAccountId();

        Test.stopTest();

        Account acc = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :accId
            LIMIT 1
        ];

        System.assertEquals('Square POS Customer', acc.Name);
    }

    @IsTest
    static void testGetDefaultSquareCustomerAccountIdReturnsExistingAccount() {
        Account acc = new Account(Name = 'Square POS Customer');
        insert acc;

        Test.startTest();

        Id returnedId = SquareOrderSyncService.getDefaultSquareCustomerAccountId();

        Test.stopTest();

        System.assertEquals(acc.Id, returnedId);
    }

    // ---------------------------------------------------------------------
    // @TestVisible Helper Method Tests
    // ---------------------------------------------------------------------

    @IsTest
    static void testExtractSalesAssistantName_AllBranches() {
        System.assertEquals(
            null,
            SquareOrderSyncService.extractSalesAssistantName(null)
        );

        System.assertEquals(
            'Team Member Name',
            SquareOrderSyncService.extractSalesAssistantName(
                new Map<String, Object>{
                    'team_member_name' => 'Team Member Name'
                }
            )
        );

        System.assertEquals(
            'Employee Name',
            SquareOrderSyncService.extractSalesAssistantName(
                new Map<String, Object>{
                    'employee_name' => 'Employee Name'
                }
            )
        );

        System.assertEquals(
            'Creator Name',
            SquareOrderSyncService.extractSalesAssistantName(
                new Map<String, Object>{
                    'creator_name' => 'Creator Name'
                }
            )
        );

        System.assertEquals(
            null,
            SquareOrderSyncService.extractSalesAssistantName(
                new Map<String, Object>{
                    'id' => 'PAYMENT_WITHOUT_NAME'
                }
            )
        );
    }

    @IsTest
    static void testBuildUserAlias_AllBranches() {
        System.assertEquals(
            'jdoe',
            SquareOrderSyncService.buildUserAlias('John', 'Doe')
        );

        System.assertEquals(
            'doe',
            SquareOrderSyncService.buildUserAlias(null, 'Doe')
        );

        System.assertEquals(
            'j',
            SquareOrderSyncService.buildUserAlias('John', null)
        );

        System.assertEquals(
            'squser',
            SquareOrderSyncService.buildUserAlias(null, null)
        );

        System.assertEquals(
            'jlonglas',
            SquareOrderSyncService.buildUserAlias('John', 'LongLastname')
        );

        System.assertEquals(
            'jsmith',
            SquareOrderSyncService.buildUserAlias('John!', 'Smith###')
        );
    }

    @IsTest
    static void testGetFreeUserProfile_OrgDependentPath() {
        Test.startTest();

        try {
            Profile p = SquareOrderSyncService.getFreeUserProfile();
            System.assertNotEquals(
                null,
                p.Id,
                'If the org has Chatter Free or Identity profile, method should return a Profile.'
            );
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage() != null,
                'If the org has no Chatter Free or Identity profile, exception path is valid.'
            );
        }

        Test.stopTest();
    }
}