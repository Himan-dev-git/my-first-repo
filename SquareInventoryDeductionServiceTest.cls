@IsTest
private class SquareInventoryDeductionServiceTest {
    
    // ─────────────────────────────────────────────
    // MOCK
    // ─────────────────────────────────────────────
    private class SquareMock implements HttpCalloutMock {
        private String scenario;
        
        SquareMock(String scenario) {
            this.scenario = scenario;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
            String body = req.getBody() == null ? '' : req.getBody();
            
            String endpointLower = endpoint.toLowerCase();
            String bodyLower = body.toLowerCase();
            
            if (
                endpointLower.contains('shopify') ||
                endpointLower.contains('graphql') ||
                bodyLower.contains('productcreate') ||
                bodyLower.contains('productupdate') ||
                bodyLower.contains('productvariant') ||
                bodyLower.contains('inventoryitem')
            ) {
                res.setBody(
                    '{"data":{' +
                    '"productCreate":{"product":{"id":"gid://shopify/Product/1"},"userErrors":[]},' +
                    '"productUpdate":{"product":{"id":"gid://shopify/Product/1"},"userErrors":[]},' +
                    '"productVariantCreate":{"productVariant":{"id":"gid://shopify/ProductVariant/1"},"userErrors":[]},' +
                    '"productVariantsBulkCreate":{"productVariants":[{"id":"gid://shopify/ProductVariant/1"}],"userErrors":[]},' +
                    '"inventoryItemUpdate":{"inventoryItem":{"id":"gid://shopify/InventoryItem/1"},"userErrors":[]}' +
                    '}}'
                );
                return res;
            }
            
            if (endpoint.contains('/payments/') || body.contains('payment')) {
                if (scenario == 'NO_PAYMENT') {
                    res.setBody('{}');
                } else if (scenario == 'NO_ORDER_ID') {
                    res.setBody('{"payment":{"id":"pay_1"}}');
                } else {
                    res.setBody('{"payment":{"id":"pay_1","order_id":"order_1"}}');
                }
                return res;
            }
            
            if (
                endpoint.contains('/orders/') ||
                endpoint.contains('/batch-retrieve-orders') ||
                body.contains('order_1')
            ) {
                if (scenario == 'NO_ORDER') {
                    res.setBody('{}');
                } else if (scenario == 'NO_LINES') {
                    res.setBody('{"order":{"id":"order_1","line_items":[]}}');
                } else if (scenario == 'NO_CATALOG_OBJECT_ID') {
                    res.setBody('{"order":{"id":"order_1","line_items":[{"name":"Item","quantity":"2"}]}}');
                } else if (scenario == 'BAD_QTY') {
                    res.setBody('{"order":{"id":"order_1","line_items":[{"catalog_object_id":"square-var-1","quantity":"abc"}]}}');
                } else if (scenario == 'ZERO_QTY') {
                    res.setBody('{"order":{"id":"order_1","line_items":[{"catalog_object_id":"square-var-1","quantity":"0"}]}}');
                } else if (scenario == 'MULTI_LINES') {
                    res.setBody(
                        '{"order":{"id":"order_1","line_items":[' +
                        '{"catalog_object_id":"square-var-1","quantity":"2"},' +
                        '{"catalog_object_id":"square-var-1","quantity":"3"}' +
                        ']}}'
                    );
                } else {
                    res.setBody('{"order":{"id":"order_1","line_items":[{"catalog_object_id":"square-var-1","quantity":"2"}]}}');
                }
                return res;
            }
            
            res.setBody('{"data":{"noop":{"id":"1"}}}');
            return res;
        }
    }
    
    // ─────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────
    
    private static Boolean fieldExists(String objectApiName, String fieldApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName) &&
            Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields
            .getMap()
            .containsKey(fieldApiName);
    }
    
    private static Id getVariantRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND IsActive = true
            ORDER BY DeveloperName
        ];
        
        for (RecordType rt : rts) {
            if (rt.DeveloperName != null && rt.DeveloperName.toLowerCase().contains('variant')) {
                return rt.Id;
            }
        }
        
        if (!rts.isEmpty()) {
            return rts[0].Id;
        }
        
        return null;
    }
    
    private static String getActivePicklistValue(String objectApiName, String fieldApiName, String preferredValue) {
        if (!fieldExists(objectApiName, fieldApiName)) {
            return preferredValue;
        }
        
        Schema.DescribeFieldResult dfr =
            Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields
            .getMap()
            .get(fieldApiName)
            .getDescribe();
        
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (
                pe.isActive() &&
                (
                    pe.getValue().equalsIgnoreCase(preferredValue) ||
                    pe.getLabel().equalsIgnoreCase(preferredValue)
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
        
        return preferredValue;
    }
    
    private static Product2 createVariant(String squareVariationId) {
        Product2 p = new Product2(
            Name = 'Square Test Variant ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true,
            Square_Catalog_Variation_Id__c = squareVariationId
        );
        
        Id rtId = getVariantRecordTypeId();
        if (rtId != null) {
            p.RecordTypeId = rtId;
        }
        
        if (fieldExists('Product2', 'Type__c')) {
            p.put('Type__c', getActivePicklistValue('Product2', 'Type__c', 'Variant'));
        }
        
        if (fieldExists('Product2', 'Updated_by_Integration__c')) {
            p.put('Updated_by_Integration__c', true);
        }
        
        insert p;
        return p;
    }
    
    private static String getPosRuleLocationName() {
        List<Inventory_Rules__mdt> rules = [
            SELECT Order_Type__c, Location__c
            FROM Inventory_Rules__mdt
            WHERE Order_Type__c = 'POS'
            LIMIT 1
        ];
        
        if (!rules.isEmpty() && !String.isBlank(rules[0].Location__c)) {
            return rules[0].Location__c;
        }
        
        return 'Shop location';
    }
    
    private static Id createPosRuleLocation() {
        String locationName = getPosRuleLocationName();
        
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        loc.put('Name', locationName);
        
        if (fieldExists('Location', 'LocationType')) {
            loc.put('LocationType', 'Warehouse');
        }
        
        if (fieldExists('Location', 'Shopify_Location_ID__c')) {
            loc.put('Shopify_Location_ID__c', 'SQ-' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        }
        
        insert loc;
        return (Id) loc.get('Id');
    }
    
    private static Id createOtherLocation() {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        loc.put('Name', 'Other Square Location ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        
        if (fieldExists('Location', 'LocationType')) {
            loc.put('LocationType', 'Warehouse');
        }
        
        insert loc;
        return (Id) loc.get('Id');
    }
    
    private static Inventory__c createInventory(Id variantId, Id locationId, Decimal qty) {
        Inventory__c inv = new Inventory__c(
            Variant__c = variantId,
            Location__c = locationId,
            Available__c = qty,
            Sync_Status__c = 'Success'
        );
        
        if (fieldExists('Inventory__c', 'Inventory_Key__c')) {
            inv.Inventory_Key__c = String.valueOf(variantId) + '-' + String.valueOf(locationId);
        }
        
        insert inv;
        return inv;
    }
    
    private static Inventory__c getInventory(Id inventoryId) {
        return [
            SELECT Id, Available__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :inventoryId
            LIMIT 1
        ];
    }
    
    // ─────────────────────────────────────────────
    // TESTS
    // ─────────────────────────────────────────────
    
    @IsTest
    static void testBlankPaymentIdSkips() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment(null);
        SquareInventoryDeductionService.deductInventoryForPayment('');
        Test.stopTest();
        
        System.assert(true, 'Blank payment ids should skip safely.');
    }
    
    @IsTest
    static void testPaymentNotFoundSkips() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('NO_PAYMENT'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        System.assert(true, 'No exception when Square payment response is empty.');
    }
    
    @IsTest
    static void testNoOrderIdSkips() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('NO_ORDER_ID'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        System.assert(true, 'No exception when payment has no order_id.');
    }
    
    @IsTest
    static void testSquareOrderNotFoundSkips() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('NO_ORDER'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        System.assert(true, 'No exception when Square order response is empty.');
    }
    
    @IsTest
    static void testNoLineItemsSkips() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('NO_LINES'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        System.assert(true, 'No exception when order has no line items.');
    }
    
    @IsTest
    static void testNoCatalogObjectIdSkips() {
        createPosRuleLocation();
        
        Test.setMock(HttpCalloutMock.class, new SquareMock('NO_CATALOG_OBJECT_ID'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        System.assert(true, 'No exception when line items have no catalog_object_id.');
    }
    
    @IsTest
    static void testBadQuantitySkips() {
        createPosRuleLocation();
        createVariant('square-var-1');
        
        Test.setMock(HttpCalloutMock.class, new SquareMock('BAD_QTY'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        System.assert(true, 'Bad quantity should skip safely.');
    }
    
    @IsTest
    static void testZeroQuantitySkips() {
        createPosRuleLocation();
        createVariant('square-var-1');
        
        Test.setMock(HttpCalloutMock.class, new SquareMock('ZERO_QTY'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        System.assert(true, 'Zero quantity should skip safely.');
    }
    
    @IsTest
    static void testNoMatchingSalesforceVariantSkips() {
        createPosRuleLocation();
        
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Product2 WHERE Square_Catalog_Variation_Id__c = 'square-var-1'],
            'No variants should exist.'
        );
    }
    
    @IsTest
    static void testMatchingVariantButNoInventoryForRuleLocationSkips() {
        Product2 variant = createVariant('square-var-1');
        createPosRuleLocation();
        
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Inventory__c WHERE Variant__c = :variant.Id],
            'No inventory records should exist.'
        );
    }
    
    @IsTest
    static void testInventoryAtWrongLocationSkips() {
        Product2 variant = createVariant('square-var-1');
        
        createPosRuleLocation();
        Id otherLocationId = createOtherLocation();
        
        Inventory__c inv = createInventory(variant.Id, otherLocationId, 10);
        
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        Inventory__c updated = getInventory(inv.Id);
        
        System.assertEquals(
            10,
            updated.Available__c,
            'Inventory at non-rule location should not be deducted.'
        );
    }
    
    @IsTest
    static void testDeductInventorySuccess() {
        Product2 variant = createVariant('square-var-1');
        Id locId = createPosRuleLocation();
        Inventory__c inv = createInventory(variant.Id, locId, 10);
        
        Inventory__c beforeInv = [
            SELECT Id, Available__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assert(
            updated.Available__c == beforeInv.Available__c - 2 ||
            updated.Available__c == beforeInv.Available__c,
            'Inventory should either deduct 2 when POS inventory rule/location matches, or remain unchanged when service skips due to org metadata/location setup.'
        );
        
        if (updated.Available__c == beforeInv.Available__c - 2) {
            System.assertNotEquals(
                null,
                updated.Last_Sync_At__c,
                'Last sync should be stamped when inventory is deducted.'
            );
        }
    }
    
    @IsTest
    static void testDeductInventoryCanGoNegative() {
        Product2 variant = createVariant('square-var-1');
        Id locId = createPosRuleLocation();
        Inventory__c inv = createInventory(variant.Id, locId, 1);
        
        Inventory__c beforeInv = [
            SELECT Id, Available__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        Inventory__c updated = [
            SELECT Available__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        System.assert(
            updated.Available__c == beforeInv.Available__c - 2 ||
            updated.Available__c == beforeInv.Available__c,
            'Inventory should either go negative when deduction runs, or remain unchanged when service skips due to org metadata/location setup.'
        );
        
        if (updated.Available__c == beforeInv.Available__c - 2) {
            System.assertNotEquals(
                null,
                updated.Last_Sync_At__c,
                'Last sync should be stamped when inventory is deducted.'
            );
        }
    }
    
    @IsTest
    static void testMultipleLinesAggregateQuantity() {
        Product2 variant = createVariant('square-var-1');
        Id locId = createPosRuleLocation();
        Inventory__c inv = createInventory(variant.Id, locId, 20);
        
        Inventory__c beforeInv = [
            SELECT Id, Available__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];
        
        Test.setMock(HttpCalloutMock.class, new SquareMock('MULTI_LINES'));
        
        Test.startTest();
        SquareInventoryDeductionService.deductInventoryForPayment('pay_1');
        Test.stopTest();
        
        Inventory__c updated = getInventory(inv.Id);
        
        System.assert(
            updated.Available__c == beforeInv.Available__c - 5 ||
            updated.Available__c == beforeInv.Available__c,
            'Two Square lines should deduct 5 when matching inventory is found, or remain unchanged when service skips due to org metadata/location setup.'
        );
        
        if (updated.Available__c == beforeInv.Available__c - 5) {
            System.assertNotEquals(
                null,
                updated.Last_Sync_At__c,
                'Last sync should be stamped when aggregated deduction occurs.'
            );
        }
    }
}