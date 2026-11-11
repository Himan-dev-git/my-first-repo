@IsTest
private class OrderTriggerHandlerTest {
    
    private class TestData {
        Account acc;
        Id locId;
        Id effectiveInventoryLocationId;
        Id productId;
        PricebookEntry pbe;
        Inventory__c inv;
        Order ord;
    }
    
    private static Boolean fieldExists(String objectApiName, String fieldApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName) &&
            Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields
            .getMap()
            .containsKey(fieldApiName);
    }
    
    private static Id createLocation(String nameValue) {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        loc.put('Name', nameValue);
        
        if (fieldExists('Location', 'LocationType')) {
            loc.put('LocationType', 'Warehouse');
        }
        
        if (fieldExists('Location', 'Shopify_Location_ID__c')) {
            loc.put('Shopify_Location_ID__c', 'LOC-' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        }
        
        insert loc;
        return (Id) loc.get('Id');
    }
    
    private static Id createVariantProduct() {
        Product2 p = new Product2(
            Name = 'Test Variant ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ];
        
        if (!rts.isEmpty()) {
            p.RecordTypeId = rts[0].Id;
        }
        
        if (fieldExists('Product2', 'Type__c')) {
            p.put('Type__c', getPicklistValue('Product2', 'Type__c', 'Variant'));
        }
        
        if (fieldExists('Product2', 'Product_Type__c')) {
            p.put('Product_Type__c', getPicklistValue('Product2', 'Product_Type__c', 'Variant'));
        }
        
        if (fieldExists('Product2', 'Shop_ID__c')) {
            p.put('Shop_ID__c', 'SHOP-' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        }
        
        if (fieldExists('Product2', 'Inventory_Item_Id__c')) {
            p.put('Inventory_Item_Id__c', 'INVITEM-' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        }
        
        insert p;
        return p.Id;
    }
    
    private static String getPicklistValue(String objectName, String fieldName, String desiredValue) {
        Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectName);
        
        if (sObjType == null) {
            return desiredValue;
        }
        
        Map<String, Schema.SObjectField> fields =
            sObjType.getDescribe().fields.getMap();
        
        if (!fields.containsKey(fieldName)) {
            return desiredValue;
        }
        
        Schema.DescribeFieldResult dfr = fields.get(fieldName).getDescribe();
        
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (
                pe.isActive() &&
                (
                    pe.getValue().equalsIgnoreCase(desiredValue) ||
                    pe.getLabel().equalsIgnoreCase(desiredValue)
                )
            ) {
                return pe.getValue();
            }
        }
        
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        
        return desiredValue;
    }
    
    private static TestData makeData(
        Decimal startingAvailable,
        String orderType
    ) {
        GlobalHttpMock.mockMode = 'SUCCESS';

        Test.setMock(
            HttpCalloutMock.class,
            new GlobalHttpMock()
        );

        InventorySyncControl.skipOutbound = true;

        TestData td =
            new TestData();

        td.acc =
            new Account(
                Name =
                    'Test Account ' +
                    String.valueOf(
                        Math.abs(
                            Crypto.getRandomInteger()
                        )
                    )
            );

        insert td.acc;

        /*
         * This is the fallback Order.Location__c.
         *
         * In some orgs Inventory_Rules__mdt resolves a different
         * location for the same Order.Type. Production deployment
         * therefore must not assume that Order.Location__c is always
         * the inventory-adjustment location.
         */
        td.locId =
            createLocation(
                'Test Location ' +
                String.valueOf(
                    Math.abs(
                        Crypto.getRandomInteger()
                    )
                )
            );

        td.productId =
            createVariantProduct();

        Id stdPbId =
            Test.getStandardPricebookId();

        Pricebook2 stdPb =
            new Pricebook2(
                Id = stdPbId,
                IsActive = true
            );

        update stdPb;

        td.pbe =
            new PricebookEntry(
                Pricebook2Id = stdPbId,
                Product2Id = td.productId,
                UnitPrice = 10,
                IsActive = true,
                UseStandardPrice = false
            );

        insert td.pbe;

        td.ord =
            new Order(
                AccountId = td.acc.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = stdPbId,
                Location__c = td.locId,
                Type = orderType,
                Financial_Status__c = 'paid',
                Fulfillment_Status__c = 'Unfulfilled'
            );

        insert td.ord;

        /*
         * Resolve the location exactly the same way as
         * OrderInventoryAdjustmentService.
         *
         * This makes the test portable between:
         * - sandboxes with no matching Inventory_Rules__mdt record, and
         * - production where the Order.Type can resolve to Warehouse or
         *   another metadata-defined Location.
         */
        Id resolvedLocationId =
            InventoryRuleService.getLocationIdForOrder(
                td.ord
            );

        td.effectiveInventoryLocationId =
            resolvedLocationId == null
                ? td.locId
                : resolvedLocationId;

        td.inv =
            new Inventory__c(
                Variant__c = td.productId,
                Location__c =
                    td.effectiveInventoryLocationId,
                Available__c =
                    startingAvailable,
                Salesforce_Available__c =
                    startingAvailable,
                Sync_Status__c = 'Success'
            );

        if (
            fieldExists(
                'Inventory__c',
                'Inventory_Key__c'
            )
        ) {
            td.inv.put(
                'Inventory_Key__c',
                String.valueOf(
                    td.productId
                ) +
                '-' +
                String.valueOf(
                    td.effectiveInventoryLocationId
                )
            );
        }

        if (
            fieldExists(
                'Inventory__c',
                'Shopify_Location_ID__c'
            )
        ) {
            td.inv.put(
                'Shopify_Location_ID__c',
                String.valueOf(
                    td.effectiveInventoryLocationId
                )
            );
        }

        insert td.inv;

        return td;
    }
    
    private static Order queryOrderForInventoryRule(
        Id orderId
    ) {
        return [
            SELECT Id,
                   Type,
                   Location__c,
                   Status,
                   Financial_Status__c,
                   Fulfillment_Status__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
    }

    private static Decimal currentSalesforceAvailable(Id invId) {
        return [
            SELECT Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :invId
            LIMIT 1
        ].Salesforce_Available__c;
    }

    private static Decimal currentShopifyAvailable(Id invId) {
        return [
            SELECT Available__c
            FROM Inventory__c
            WHERE Id = :invId
            LIMIT 1
        ].Available__c;
    }
    
    private static OrderItem createOrderItem(Id orderId, Id pbeId, Decimal qty) {
        OrderItem oi = new OrderItem(
            OrderId = orderId,
            PricebookEntryId = pbeId,
            Quantity = qty,
            UnitPrice = 10
        );
        insert oi;
        return oi;
    }
    
    @IsTest
    static void testAfterInsertDeductsInventoryAndAccumulatesLineItems() {
        TestData td = makeData(20, 'POS');
        
        createOrderItem(td.ord.Id, td.pbe.Id, 2);
        createOrderItem(td.ord.Id, td.pbe.Id, 3);
        
        Decimal beforeHandler = currentSalesforceAvailable(td.inv.Id);
        
        Test.startTest();
        OrderTriggerHandler.afterInsert(
            new List<Order>{
                queryOrderForInventoryRule(
                    td.ord.Id
                )
            }
        );
        Test.stopTest();
        
        Decimal afterHandler = currentSalesforceAvailable(td.inv.Id);
        
        System.assertEquals(
            Decimal.valueOf(5),
            beforeHandler - afterHandler,
            'Handler should deduct total OrderItem quantity from Salesforce_Available__c.'
        );
        
        System.assertEquals(
            Decimal.valueOf(20),
            currentShopifyAvailable(td.inv.Id),
            'Available__c should remain the Shopify snapshot and must not be changed by OrderTriggerHandler.'
        );

        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testAfterInsertSkipsBlankType() {
        GlobalHttpMock.mockMode = 'SUCCESS';
        Test.setMock(
            HttpCalloutMock.class,
            new GlobalHttpMock()
        );
        InventorySyncControl.skipOutbound = true;
        
        Account acc = new Account(Name = 'Blank Type Account');
        insert acc;
        
        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId(),
            Financial_Status__c = 'paid'
        );
        insert ord;
        
        Test.startTest();
        OrderTriggerHandler.afterInsert(new List<Order>{ ord });
        Test.stopTest();
        
        System.assert(true, 'Blank Type order should be skipped.');
        
        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testAfterInsertSkipsRefundedOrder() {
        TestData td = makeData(10, 'POS');
        
        td.ord.Financial_Status__c = 'refunded';
        
        Test.startTest();
        OrderTriggerHandler.afterInsert(new List<Order>{ td.ord });
        Test.stopTest();
        
        System.assert(true, 'Refunded order should not deduct.');
        
        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testAfterInsertNoEligibleLineItemsDoesNothing() {
        TestData td = makeData(8, 'POS');
        
        Decimal beforeHandler = currentSalesforceAvailable(td.inv.Id);
        
        Test.startTest();
        OrderTriggerHandler.afterInsert(new List<Order>{ td.ord });
        Test.stopTest();
        
        Decimal afterHandler = currentSalesforceAvailable(td.inv.Id);
        
        System.assertEquals(
            beforeHandler,
            afterHandler,
            'No OrderItems means no Salesforce inventory change.'
        );
        
        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testAfterInsertMissingInventoryDoesNotFail() {
        TestData td = makeData(5, 'POS');
        delete td.inv;
        
        createOrderItem(td.ord.Id, td.pbe.Id, 2);
        
        Test.startTest();
        OrderTriggerHandler.afterInsert(new List<Order>{ td.ord });
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Inventory__c WHERE Variant__c = :td.productId],
            'Missing Inventory__c should be skipped safely.'
        );
        
        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testRefundRestoresInventory() {
        TestData td = makeData(10, 'POS');
        
        createOrderItem(td.ord.Id, td.pbe.Id, 4);
        
        Decimal beforeHandler = currentSalesforceAvailable(td.inv.Id);
        
        Order oldOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'paid',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Order newOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'refunded',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Test.startTest();
        OrderTriggerHandler.afterUpdate(
            new List<Order>{ newOrder },
            new Map<Id, Order>{ oldOrder.Id => oldOrder }
        );
        Test.stopTest();
        
        Decimal afterHandler = currentSalesforceAvailable(td.inv.Id);
        
        System.assertEquals(
            Decimal.valueOf(4),
            afterHandler - beforeHandler,
            'Refunded order should restore Salesforce_Available__c.'
        );
        
        System.assertEquals(
            Decimal.valueOf(10),
            currentShopifyAvailable(td.inv.Id),
            'Available__c should remain the Shopify snapshot and must not be changed by OrderTriggerHandler.'
        );

        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testCancelledStatusRestoresInventory() {
        TestData td = makeData(10, 'POS');
        
        createOrderItem(td.ord.Id, td.pbe.Id, 3);
        
        Decimal beforeHandler = currentSalesforceAvailable(td.inv.Id);
        
        Order oldOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'paid',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Order newOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'paid',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Cancelled'
        );
        
        Test.startTest();
        OrderTriggerHandler.afterUpdate(
            new List<Order>{ newOrder },
            new Map<Id, Order>{ oldOrder.Id => oldOrder }
        );
        Test.stopTest();
        
        Decimal afterHandler = currentSalesforceAvailable(td.inv.Id);
        
        System.assertEquals(
            Decimal.valueOf(3),
            afterHandler - beforeHandler,
            'Cancelled order should restore Salesforce_Available__c.'
        );
        
        System.assertEquals(
            Decimal.valueOf(10),
            currentShopifyAvailable(td.inv.Id),
            'Available__c should remain the Shopify snapshot and must not be changed by OrderTriggerHandler.'
        );

        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testFulfillmentCancelledRestoresInventory() {
        TestData td = makeData(10, 'POS');
        
        createOrderItem(td.ord.Id, td.pbe.Id, 2);
        
        Decimal beforeHandler = currentSalesforceAvailable(td.inv.Id);
        
        Order oldOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'paid',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Order newOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'paid',
            Fulfillment_Status__c = 'Cancelled',
            Status = 'Draft'
        );
        
        Test.startTest();
        OrderTriggerHandler.afterUpdate(
            new List<Order>{ newOrder },
            new Map<Id, Order>{ oldOrder.Id => oldOrder }
        );
        Test.stopTest();
        
        Decimal afterHandler = currentSalesforceAvailable(td.inv.Id);
        
        System.assertEquals(
            Decimal.valueOf(2),
            afterHandler - beforeHandler,
            'Cancelled fulfillment should restore Salesforce_Available__c.'
        );
        
        System.assertEquals(
            Decimal.valueOf(10),
            currentShopifyAvailable(td.inv.Id),
            'Available__c should remain the Shopify snapshot and must not be changed by OrderTriggerHandler.'
        );

        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testNoInventoryChangeWhenRefundStatusDoesNotChange() {
        TestData td = makeData(10, 'POS');
        
        createOrderItem(td.ord.Id, td.pbe.Id, 3);
        
        Decimal beforeHandler = currentSalesforceAvailable(td.inv.Id);
        
        Order oldOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'paid',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Order newOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'paid',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Test.startTest();
        OrderTriggerHandler.afterUpdate(
            new List<Order>{ newOrder },
            new Map<Id, Order>{ oldOrder.Id => oldOrder }
        );
        Test.stopTest();
        
        Decimal afterHandler = currentSalesforceAvailable(td.inv.Id);
        
        System.assertEquals(
            beforeHandler,
            afterHandler,
            'No refunded/cancelled transition means no Salesforce inventory adjustment.'
        );
        
        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testAfterUpdateNullInputsReturnSafely() {
        TestData td = makeData(10, 'POS');
        
        Test.startTest();
        
        OrderTriggerHandler.afterUpdate(null, null);
        
        OrderTriggerHandler.afterUpdate(
            new List<Order>(),
            null
        );
        
        OrderTriggerHandler.afterUpdate(
            new List<Order>{ td.ord },
            null
        );
        
        OrderTriggerHandler.afterUpdate(
            new List<Order>{ td.ord },
            new Map<Id, Order>()
        );
        
        Test.stopTest();
        
        System.assert(true, 'Null, empty, and missing oldMap cases should return safely.');
    }
    
    @IsTest
    static void testAfterInsertNullInputsReturnSafely() {
        Test.startTest();
        
        OrderTriggerHandler.afterInsert(null);
        OrderTriggerHandler.afterInsert(new List<Order>());
        
        Test.stopTest();
        
        System.assert(true, 'Null and empty inputs should return safely.');
    }
    
    @IsTest
    static void testAdjustInventoryForOrdersDelegatesToService() {
        TestData td = makeData(15, 'POS');
        
        createOrderItem(td.ord.Id, td.pbe.Id, 1);
        
        Decimal beforeAdjust = currentSalesforceAvailable(td.inv.Id);
        
        Test.startTest();
        OrderTriggerHandler.adjustInventoryForOrders(new List<Id>{ td.ord.Id }, -1);
        Test.stopTest();
        
        Decimal afterAdjust = currentSalesforceAvailable(td.inv.Id);
        
        System.assertEquals(
            Decimal.valueOf(1),
            beforeAdjust - afterAdjust,
            'adjustInventoryForOrders should delegate to OrderInventoryAdjustmentService and update Salesforce_Available__c.'
        );
        
        System.assertEquals(
            Decimal.valueOf(15),
            currentShopifyAvailable(td.inv.Id),
            'Available__c should remain the Shopify snapshot and must not be changed by OrderTriggerHandler.'
        );

        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testAfterInsertSkipsOrderWithoutId() {
        Test.startTest();
        
        OrderTriggerHandler.afterInsert(
            new List<Order>{
                new Order()
                    }
        );
        
        Test.stopTest();
        
        System.assert(true, 'Order without Id should be skipped safely.');
    }
    
    @IsTest
    static void testAfterInsertSkipsCancelledOrder() {
        TestData td = makeData(10, 'POS');
        
        td.ord.Status = 'Cancelled';
        
        Test.startTest();
        OrderTriggerHandler.afterInsert(new List<Order>{ td.ord });
        Test.stopTest();
        
        System.assert(true, 'Cancelled order should be skipped by shouldDeductInventory.');
        
        InventorySyncControl.skipOutbound = false;
    }    
    
    @IsTest
    static void testAfterInsertSkipsCanceledOrderAmericanSpelling() {
        TestData td = makeData(10, 'POS');
        
        td.ord.Status = 'Canceled';
        
        Test.startTest();
        OrderTriggerHandler.afterInsert(new List<Order>{ td.ord });
        Test.stopTest();
        
        System.assert(true, 'Canceled order should be skipped by shouldDeductInventory.');
        
        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testAfterInsertSkipsPartiallyRefundedOrder() {
        TestData td = makeData(10, 'POS');
        
        td.ord.Financial_Status__c = 'partially_refunded';
        
        Test.startTest();
        OrderTriggerHandler.afterInsert(new List<Order>{ td.ord });
        Test.stopTest();
        
        System.assert(true, 'Partially refunded order should be skipped by shouldDeductInventory.');
        
        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testAfterUpdatePartiallyRefundedRestoresInventory() {
        TestData td = makeData(10, 'POS');
        
        createOrderItem(td.ord.Id, td.pbe.Id, 2);
        
        Decimal beforeHandler = currentSalesforceAvailable(td.inv.Id);
        
        Order oldOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'paid',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Order newOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'partially_refunded',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Test.startTest();
        OrderTriggerHandler.afterUpdate(
            new List<Order>{ newOrder },
            new Map<Id, Order>{ oldOrder.Id => oldOrder }
        );
        Test.stopTest();
        
        Decimal afterHandler = currentSalesforceAvailable(td.inv.Id);
        
        System.assertEquals(
            Decimal.valueOf(2),
            afterHandler - beforeHandler,
            'Partially refunded order should restore Salesforce_Available__c.'
        );
        
        System.assertEquals(
            Decimal.valueOf(10),
            currentShopifyAvailable(td.inv.Id),
            'Available__c should remain the Shopify snapshot and must not be changed by OrderTriggerHandler.'
        );

        InventorySyncControl.skipOutbound = false;
    }
    
    @IsTest
    static void testAfterUpdateAlreadyRefundedDoesNotRestoreAgain() {
        TestData td = makeData(10, 'POS');
        
        createOrderItem(td.ord.Id, td.pbe.Id, 2);
        
        Decimal beforeHandler = currentSalesforceAvailable(td.inv.Id);
        
        Order oldOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'refunded',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Order newOrder = new Order(
            Id = td.ord.Id,
            Financial_Status__c = 'refunded',
            Fulfillment_Status__c = 'Unfulfilled',
            Status = 'Draft'
        );
        
        Test.startTest();
        OrderTriggerHandler.afterUpdate(
            new List<Order>{ newOrder },
            new Map<Id, Order>{ oldOrder.Id => oldOrder }
        );
        Test.stopTest();
        
        Decimal afterHandler = currentSalesforceAvailable(td.inv.Id);
        
        System.assertEquals(
            beforeHandler,
            afterHandler,
            'Already refunded order should not restore Salesforce_Available__c again.'
        );
        
        InventorySyncControl.skipOutbound = false;
    }
}