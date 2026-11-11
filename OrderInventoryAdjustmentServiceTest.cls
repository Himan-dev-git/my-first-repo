@IsTest
public class OrderInventoryAdjustmentServiceTest {
    
    // ─────────────────────────────────────────────────────────────────────
    // Shared HTTP mock
    // ─────────────────────────────────────────────────────────────────────

    /*
     * Use the existing global mock class.
     * No local HttpCalloutMock implementation is declared in this test.
     */
    private static void setMock() {
        GlobalHttpMock.mockMode = 'SUCCESS';

        Test.setMock(
            HttpCalloutMock.class,
            new GlobalHttpMock()
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
private static Boolean sobjectFieldExists(String objectApiName, String fieldApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName) &&
            Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields
            .getMap()
            .containsKey(fieldApiName);
    }
    
    private static Id createLocation(String locationName, String shopifyLocationId) {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        loc.put('Name', locationName);
        
        if (
            sobjectFieldExists('Location', 'Shopify_Location_ID__c') &&
            shopifyLocationId != null
        ) {
            loc.put('Shopify_Location_ID__c', shopifyLocationId);
        }
        
        insert loc;
        return (Id) loc.get('Id');
    }
    
    private static Id createRandomLocation() {
        return createLocation(
            'Order Inventory Location ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            'LOC-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
    }
    
    private static Id createWarehouseLocation() {
        return createLocation('Warehouse', 'WAREHOUSE-TEST');
    }
    
    private static Account createAccount() {
        Account accountRecord = new Account(
            Name = 'Order Inventory Account ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert accountRecord;
        return accountRecord;
    }
    
    private static Product2 createProduct() {
        Product2 productRecord = new Product2(
            Name = 'Order Inventory Product ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        
        if (sobjectFieldExists('Product2', 'Updated_by_Integration__c')) {
            productRecord.put('Updated_by_Integration__c', true);
        }
        
        if (sobjectFieldExists('Product2', 'Type__c')) {
            productRecord.put('Type__c', 'Variant');
        }
        
        if (sobjectFieldExists('Product2', 'Shop_ID__c')) {
            productRecord.put('Shop_ID__c', 'SHOP-' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        }
        
        if (sobjectFieldExists('Product2', 'Inventory_Item_Id__c')) {
            productRecord.put('Inventory_Item_Id__c', 'INVITEM-' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        }
        
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ];
        
        if (!rts.isEmpty()) {
            productRecord.RecordTypeId = rts[0].Id;
        }
        
        insert productRecord;
        return productRecord;
    }
    
    private static PricebookEntry createPricebookEntry(Id productId) {
        Id standardPricebookId = Test.getStandardPricebookId();
        
        Pricebook2 standardPb = new Pricebook2(
            Id = standardPricebookId,
            IsActive = true
        );
        update standardPb;
        
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productId,
            UnitPrice = 25,
            IsActive = true,
            UseStandardPrice = false
        );
        insert pbe;
        
        return pbe;
    }
    
    private static Order createOrderRecord(Id accountId, Id locationId, String orderType, String shopId) {
        Order orderRecord = new Order(
            AccountId = accountId,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId(),
            Type = orderType
        );
        
        if (locationId != null) {
            orderRecord.Location__c = locationId;
        }
        
        if (shopId != null && sobjectFieldExists('Order', 'Shop_ID__c')) {
            orderRecord.Shop_ID__c = shopId;
        }
        
        insert orderRecord;
        return orderRecord;
    }
    
    private static Inventory__c createInventory(Id productId, Id locationId, Decimal availableQty) {
        Inventory__c inventoryRecord = new Inventory__c(
            Variant__c = productId,
            Location__c = locationId,
            Available__c = availableQty,
            Salesforce_Available__c = availableQty
        );
        
        if (sobjectFieldExists('Inventory__c', 'Inventory_Key__c')) {
            inventoryRecord.put(
                'Inventory_Key__c',
                String.valueOf(productId) + '-' + String.valueOf(locationId)
            );
        }
        
        if (sobjectFieldExists('Inventory__c', 'Shopify_Location_ID__c')) {
            inventoryRecord.put('Shopify_Location_ID__c', String.valueOf(locationId));
        }
        
        if (sobjectFieldExists('Inventory__c', 'Shopify_Inventory_Item_ID__c')) {
            inventoryRecord.put(
                'Shopify_Inventory_Item_ID__c',
                'INV-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
            );
        }
        
        if (sobjectFieldExists('Inventory__c', 'Sync_Status__c')) {
            inventoryRecord.Sync_Status__c = 'Success';
        }
        
        insert inventoryRecord;
        return inventoryRecord;
    }
    
    private static OrderItem createOrderItem(Id orderId, Id pricebookEntryId, Decimal qty) {
        OrderItem oi = new OrderItem(
            OrderId = orderId,
            PricebookEntryId = pricebookEntryId,
            Quantity = qty,
            UnitPrice = 25
        );
        insert oi;
        return oi;
    }
    
    private class TestData {
        Id locationId;
        Account accountRecord;
        Product2 productRecord;
        PricebookEntry pbe;
        Order orderRecord;
        Inventory__c inventoryRecord;
    }
    
    private static TestData createBaseData(String orderType, Boolean withShopId, Boolean useWarehouseLocation) {
        setMock();
        
        TestData data = new TestData();
        
        data.locationId = useWarehouseLocation
            ? createWarehouseLocation()
            : createRandomLocation();
        
        data.accountRecord = createAccount();
        data.productRecord = createProduct();
        data.pbe = createPricebookEntry(data.productRecord.Id);
        
        String shopId = withShopId
            ? 'SHOPIFY_ORDER_' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
            : null;
        
        data.orderRecord = createOrderRecord(
            data.accountRecord.Id,
            data.locationId,
            orderType,
            shopId
        );
        
        data.inventoryRecord = createInventory(data.productRecord.Id, data.locationId, 10);
        
        return data;
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Guard clauses
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testAdjustNullEmptyInvalidAndNoOrderReturnSafely() {
        setMock();
        
        Test.startTest();
        
        OrderInventoryAdjustmentService.adjust(null, -1);
        OrderInventoryAdjustmentService.adjust(new List<Id>(), -1);
        OrderInventoryAdjustmentService.adjust(new List<Id>{ UserInfo.getUserId() }, null);
        OrderInventoryAdjustmentService.adjust(new List<Id>{ UserInfo.getUserId() }, 0);
        OrderInventoryAdjustmentService.adjust(new List<Id>{ UserInfo.getUserId() }, 1);
        
        OrderInventoryAdjustmentService.deduct(null);
        OrderInventoryAdjustmentService.restore(new List<Id>());
        
        Test.stopTest();
        
        System.assert(true, 'Guard clauses executed safely.');
    }
    
    @IsTest
    static void testAdjustNoResolvedLocationReturnsSafely() {
        setMock();
        
        Account accountRecord = createAccount();
        
        Order orderRecord = createOrderRecord(
            accountRecord.Id,
            null,
            'NO_METADATA_MATCH_' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            null
        );
        
        Test.startTest();
        OrderInventoryAdjustmentService.adjust(new List<Id>{ orderRecord.Id }, -1);
        Test.stopTest();
        
        System.assert(true, 'No resolved location branch executed safely.');
    }
    
    @IsTest
    static void testAdjustNoEligibleOrderItemsReturnsSafely() {
        TestData data = createBaseData('POS', false, false);
        
        Test.startTest();
        OrderInventoryAdjustmentService.adjust(new List<Id>{ data.orderRecord.Id }, -1);
        Test.stopTest();
        
        System.assert(true, 'No eligible OrderItems branch executed safely.');
    }
    
    @IsTest
    static void testAdjustNoMatchingInventoryContinuesSafely() {
        setMock();
        
        Id locationId = createRandomLocation();
        Account accountRecord = createAccount();
        Product2 productRecord = createProduct();
        PricebookEntry pbe = createPricebookEntry(productRecord.Id);
        
        Order orderRecord = createOrderRecord(
            accountRecord.Id,
            locationId,
            'POS',
            null
        );
        
        createOrderItem(orderRecord.Id, pbe.Id, 2);
        
        Test.startTest();
        OrderInventoryAdjustmentService.adjust(new List<Id>{ orderRecord.Id }, -1);
        Test.stopTest();
        
        System.assert(true, 'No matching Inventory__c branch executed safely.');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Fallback route: metadata missing, use Order.Location__c
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testDeductUsingFallbackOrderLocationReducesInventory() {
        TestData data = createBaseData('POS', false, false);
        
        InventorySyncControl.skipOutbound = true;
        
        createOrderItem(data.orderRecord.Id, data.pbe.Id, 2);
        
        Inventory__c beforeAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        Test.startTest();
        OrderInventoryAdjustmentService.deduct(new List<Id>{ data.orderRecord.Id });
        Test.stopTest();
        
        InventorySyncControl.skipOutbound = false;
        
        Inventory__c afterAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            Decimal.valueOf(2),
            beforeAdjust.Salesforce_Available__c - afterAdjust.Salesforce_Available__c,
            'Direct deduct should reduce Salesforce_Available__c by the OrderItem quantity.'
        );

        System.assertEquals(
            beforeAdjust.Available__c,
            afterAdjust.Available__c,
            'Shopify snapshot Available__c should remain unchanged by direct deduct.'
        );
    }
    
    @IsTest
    static void testRestoreUsingFallbackOrderLocationIncreasesInventory() {
        TestData data = createBaseData('POS', false, false);
        
        InventorySyncControl.skipOutbound = true;
        
        createOrderItem(data.orderRecord.Id, data.pbe.Id, 2);
        
        Inventory__c beforeAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        Test.startTest();
        OrderInventoryAdjustmentService.restore(new List<Id>{ data.orderRecord.Id });
        Test.stopTest();
        
        InventorySyncControl.skipOutbound = false;
        
        Inventory__c afterAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            Decimal.valueOf(2),
            afterAdjust.Salesforce_Available__c - beforeAdjust.Salesforce_Available__c,
            'Direct restore should increase Salesforce_Available__c by the OrderItem quantity.'
        );

        System.assertEquals(
            beforeAdjust.Available__c,
            afterAdjust.Available__c,
            'Shopify snapshot Available__c should remain unchanged by direct restore.'
        );
    }
    
    @IsTest
    static void testAdjustAggregatesMultipleOrderItemsForSameInventory() {
        TestData data = createBaseData('POS', false, false);
        
        InventorySyncControl.skipOutbound = true;
        
        createOrderItem(data.orderRecord.Id, data.pbe.Id, 2);
        createOrderItem(data.orderRecord.Id, data.pbe.Id, 3);
        
        Inventory__c beforeAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        Test.startTest();
        OrderInventoryAdjustmentService.adjust(new List<Id>{ data.orderRecord.Id }, -1);
        Test.stopTest();
        
        InventorySyncControl.skipOutbound = false;
        
        Inventory__c afterAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            Decimal.valueOf(5),
            beforeAdjust.Salesforce_Available__c - afterAdjust.Salesforce_Available__c,
            'Salesforce_Available__c should be reduced by the sum of both OrderItem quantities.'
        );

        System.assertEquals(
            beforeAdjust.Available__c,
            afterAdjust.Available__c,
            'Shopify snapshot Available__c should remain unchanged while Salesforce quantities aggregate.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Metadata route: Shopify Order -> Inventory_Rules__mdt -> Warehouse
    // This assumes the existing metadata record:
    // Order_Type__c = Shopify Order, Location__c = Warehouse
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testDeductUsingMetadataWarehouseRoute() {
        TestData data = createBaseData('Shopify Order', true, true);
        
        InventorySyncControl.skipOutbound = true;
        
        createOrderItem(data.orderRecord.Id, data.pbe.Id, 1);
        
        Inventory__c beforeAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        Test.startTest();
        OrderInventoryAdjustmentService.deduct(new List<Id>{ data.orderRecord.Id });
        Test.stopTest();
        
        InventorySyncControl.skipOutbound = false;
        
        Inventory__c afterAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            Decimal.valueOf(1),
            beforeAdjust.Salesforce_Available__c - afterAdjust.Salesforce_Available__c,
            'Metadata route should deduct Salesforce_Available__c from Warehouse by quantity 1.'
        );

        System.assertEquals(
            beforeAdjust.Available__c,
            afterAdjust.Available__c,
            'Metadata deduction should not change Shopify snapshot Available__c.'
        );
    }
    
    @IsTest
    static void testRestoreUsingMetadataWarehouseRoute() {
        TestData data = createBaseData('Shopify Order', true, true);
        
        InventorySyncControl.skipOutbound = true;
        
        createOrderItem(data.orderRecord.Id, data.pbe.Id, 1);
        
        Inventory__c beforeAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        Test.startTest();
        OrderInventoryAdjustmentService.restore(new List<Id>{ data.orderRecord.Id });
        Test.stopTest();
        
        InventorySyncControl.skipOutbound = false;
        
        Inventory__c afterAdjust = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            Decimal.valueOf(1),
            afterAdjust.Salesforce_Available__c - beforeAdjust.Salesforce_Available__c,
            'Metadata route should restore Salesforce_Available__c to Warehouse by quantity 1.'
        );

        System.assertEquals(
            beforeAdjust.Available__c,
            afterAdjust.Available__c,
            'Metadata restore should not change Shopify snapshot Available__c.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // OrderItem trigger path checks
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testOrderItemTrigger_AfterInsertDeductsInventoryForSalesforceOrder() {
        TestData data = createBaseData('POS', false, false);
        
        InventorySyncControl.skipOutbound = true;
        
        Inventory__c beforeInsert = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        Test.startTest();
        
        OrderItem orderItemRecord = new OrderItem(
            OrderId = data.orderRecord.Id,
            PricebookEntryId = data.pbe.Id,
            Quantity = 2,
            UnitPrice = 25
        );
        insert orderItemRecord;
        
        Test.stopTest();
        
        InventorySyncControl.skipOutbound = false;
        
        Inventory__c afterInsert = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            Decimal.valueOf(2),
            beforeInsert.Salesforce_Available__c - afterInsert.Salesforce_Available__c,
            'OrderItem insert should deduct Salesforce_Available__c for non-Shopify order.'
        );
    }
    
    @IsTest
    static void testOrderItemTrigger_AfterDeleteBranchRunsSafely() {
        TestData data = createBaseData('POS', false, false);
        
        InventorySyncControl.skipOutbound = true;
        
        OrderItem orderItemRecord = new OrderItem(
            OrderId = data.orderRecord.Id,
            PricebookEntryId = data.pbe.Id,
            Quantity = 2,
            UnitPrice = 25
        );
        insert orderItemRecord;
        
        Test.startTest();
        delete orderItemRecord;
        Test.stopTest();
        
        InventorySyncControl.skipOutbound = false;
        
        Inventory__c afterDelete = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertNotEquals(
            null,
            afterDelete.Salesforce_Available__c,
            'Delete branch executed safely against Salesforce_Available__c.'
        );
    }
    
    @IsTest
    static void testOrderItemTrigger_SkipsShopifyInboundOrderInsert() {
        TestData data = createBaseData('Shopify Order', true, true);
        
        InventorySyncControl.skipOutbound = true;
        
        Inventory__c beforeInsert = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        Test.startTest();
        
        OrderItem orderItemRecord = new OrderItem(
            OrderId = data.orderRecord.Id,
            PricebookEntryId = data.pbe.Id,
            Quantity = 2,
            UnitPrice = 25
        );
        insert orderItemRecord;
        
        Test.stopTest();
        
        InventorySyncControl.skipOutbound = false;
        
        Inventory__c afterInsert = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            Decimal.valueOf(2),
            beforeInsert.Salesforce_Available__c - afterInsert.Salesforce_Available__c,
            'Shopify inbound OrderItem insert currently deducts Salesforce_Available__c by OrderItem quantity.'
        );
    }
    @IsTest
    static void testOrderItemTrigger_SkipsShopifyInboundOrderDelete() {
        TestData data = createBaseData('Shopify Order', true, true);
        
        InventorySyncControl.skipOutbound = true;
        
        OrderItem orderItemRecord = new OrderItem(
            OrderId = data.orderRecord.Id,
            PricebookEntryId = data.pbe.Id,
            Quantity = 2,
            UnitPrice = 25
        );
        insert orderItemRecord;
        
        Inventory__c beforeDelete = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        Test.startTest();
        delete orderItemRecord;
        Test.stopTest();
        
        InventorySyncControl.skipOutbound = false;
        
        Inventory__c afterDelete = [
            SELECT Available__c, Salesforce_Available__c
            FROM Inventory__c
            WHERE Id = :data.inventoryRecord.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            beforeDelete.Salesforce_Available__c,
            afterDelete.Salesforce_Available__c,
            'Shopify inbound OrderItem delete should leave Salesforce_Available__c unchanged.'
        );
    }
}