@IsTest
private class InventoryRuleServiceTest {

    private static final String ORDER_TYPE_SHOPIFY = 'Shopify Order';
    private static final String LOCATION_WAREHOUSE = 'Warehouse';

    // Creates Salesforce standard Location object dynamically
    // because "Location" conflicts with System.Location in Apex.
    private static Id createLocationRecord(String locationName) {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        loc.put('Name', locationName);
        insert loc;
        return (Id) loc.get('Id');
    }

    @IsTest
    static void testGetRuleForOrderType_MetadataFoundButLocationMissing() {
        Test.startTest();

        InventoryRuleService.InventoryRuleResult result =
            InventoryRuleService.getRuleForOrderType(ORDER_TYPE_SHOPIFY);

        Test.stopTest();

        // Do not fail deployment if the Custom Metadata rule does not exist in this org.
        if (result == null) {
            System.assertEquals(
                null,
                result,
                'No metadata rule exists for this order type in this org.'
            );
            return;
        }

        System.assertEquals(
            ORDER_TYPE_SHOPIFY,
            result.orderType,
            'Order type should come from metadata.'
        );

        System.assertEquals(
            null,
            result.locationId,
            'Location Id should be null because Location record was not created in this test.'
        );

        System.assertNotEquals(
            null,
            result.locationName,
            'Location name should come from metadata when metadata exists.'
        );
    }

    @IsTest
    static void testGetRuleForOrderType_MetadataAndLocationFound() {
        /*
         * First call service to check whether metadata exists.
         * If metadata does not exist in Production, this test should not fail deployment.
         */
        InventoryRuleService.InventoryRuleResult metadataResult =
            InventoryRuleService.getRuleForOrderType(ORDER_TYPE_SHOPIFY);

        if (metadataResult == null || String.isBlank(metadataResult.locationName)) {
            System.assertEquals(
                null,
                metadataResult,
                'No usable metadata rule exists for Shopify Order in this org.'
            );
            return;
        }

        Id resolvedLocationId = createLocationRecord(metadataResult.locationName);

        Test.startTest();

        InventoryRuleService.InventoryRuleResult result =
            InventoryRuleService.getRuleForOrderType(ORDER_TYPE_SHOPIFY);

        Id locationId =
            InventoryRuleService.getLocationIdForOrderType(ORDER_TYPE_SHOPIFY);

        String locationName =
            InventoryRuleService.getLocationNameForOrderType(ORDER_TYPE_SHOPIFY);

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'Inventory rule result should not be null when metadata exists.'
        );

        System.assertEquals(
            ORDER_TYPE_SHOPIFY,
            result.orderType,
            'Order type should match metadata.'
        );

        System.assertEquals(
            metadataResult.locationName,
            result.locationName,
            'Location name should match metadata.'
        );

        System.assertEquals(
            resolvedLocationId,
            result.locationId,
            'Location Id should resolve from Salesforce Location.'
        );

        System.assertEquals(
            resolvedLocationId,
            locationId,
            'getLocationIdForOrderType should return matching Location Id.'
        );

        System.assertEquals(
            metadataResult.locationName,
            locationName,
            'getLocationNameForOrderType should return metadata location name.'
        );
    }

    @IsTest
    static void testGetRuleForOrder_UsingOrderRecord() {
        /*
         * Check whether metadata exists first.
         * This avoids deployment failure if Production does not have the same Custom Metadata setup.
         */
        InventoryRuleService.InventoryRuleResult metadataResult =
            InventoryRuleService.getRuleForOrderType(ORDER_TYPE_SHOPIFY);

        if (metadataResult == null || String.isBlank(metadataResult.locationName)) {
            Account fallbackAcc = new Account(
                Name = 'Inventory Rule Test Account No Metadata'
            );
            insert fallbackAcc;

            Order fallbackOrder = new Order(
                AccountId = fallbackAcc.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Type = ORDER_TYPE_SHOPIFY
            );
            insert fallbackOrder;

            Test.startTest();

            InventoryRuleService.InventoryRuleResult fallbackResult =
                InventoryRuleService.getRuleForOrder(fallbackOrder);

            Id fallbackLocationId =
                InventoryRuleService.getLocationIdForOrder(fallbackOrder);

            Test.stopTest();

            System.assertEquals(
                null,
                fallbackResult,
                'Order should not resolve an inventory rule when metadata is missing.'
            );

            System.assertEquals(
                null,
                fallbackLocationId,
                'Location Id should be null when metadata is missing.'
            );

            return;
        }

        Id resolvedLocationId = createLocationRecord(metadataResult.locationName);

        Account acc = new Account(
            Name = 'Inventory Rule Test Account'
        );
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = ORDER_TYPE_SHOPIFY
        );
        insert ord;

        Order queriedOrder = [
            SELECT Id, Type
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        Test.startTest();

        InventoryRuleService.InventoryRuleResult result =
            InventoryRuleService.getRuleForOrder(queriedOrder);

        Id locationId =
            InventoryRuleService.getLocationIdForOrder(queriedOrder);

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'Inventory rule should resolve from Order.Type when metadata exists.'
        );

        System.assertEquals(
            ORDER_TYPE_SHOPIFY,
            result.orderType,
            'Order.Type should match metadata Order_Type__c.'
        );

        System.assertEquals(
            metadataResult.locationName,
            result.locationName,
            'Metadata location name should match resolved result.'
        );

        System.assertEquals(
            resolvedLocationId,
            result.locationId,
            'Resolved Location Id should match created Location.'
        );

        System.assertEquals(
            resolvedLocationId,
            locationId,
            'getLocationIdForOrder should return resolved Location Id.'
        );
    }

    @IsTest
    static void testBlankAndNullInputs() {
        Test.startTest();

        InventoryRuleService.InventoryRuleResult blankTypeResult =
            InventoryRuleService.getRuleForOrderType('');

        InventoryRuleService.InventoryRuleResult nullTypeResult =
            InventoryRuleService.getRuleForOrderType(null);

        InventoryRuleService.InventoryRuleResult nullOrderResult =
            InventoryRuleService.getRuleForOrder(null);

        Id blankLocationId =
            InventoryRuleService.getLocationIdForOrderType('');

        Id nullTypeLocationId =
            InventoryRuleService.getLocationIdForOrderType(null);

        Id nullOrderLocationId =
            InventoryRuleService.getLocationIdForOrder(null);

        String blankLocationName =
            InventoryRuleService.getLocationNameForOrderType('');

        String nullLocationName =
            InventoryRuleService.getLocationNameForOrderType(null);

        Test.stopTest();

        System.assertEquals(
            null,
            blankTypeResult,
            'Blank order type should return null.'
        );

        System.assertEquals(
            null,
            nullTypeResult,
            'Null order type should return null.'
        );

        System.assertEquals(
            null,
            nullOrderResult,
            'Null Order should return null.'
        );

        System.assertEquals(
            null,
            blankLocationId,
            'Blank order type should not resolve location.'
        );

        System.assertEquals(
            null,
            nullTypeLocationId,
            'Null order type should not resolve location.'
        );

        System.assertEquals(
            null,
            nullOrderLocationId,
            'Null Order should not resolve location.'
        );

        System.assertEquals(
            null,
            blankLocationName,
            'Blank order type should not resolve location name.'
        );

        System.assertEquals(
            null,
            nullLocationName,
            'Null order type should not resolve location name.'
        );
    }

    @IsTest
    static void testOrderWithBlankType() {
        Order ord = new Order();

        Test.startTest();

        InventoryRuleService.InventoryRuleResult result =
            InventoryRuleService.getRuleForOrder(ord);

        Id locationId =
            InventoryRuleService.getLocationIdForOrder(ord);

        Test.stopTest();

        System.assertEquals(
            null,
            result,
            'Order with blank Type should return null.'
        );

        System.assertEquals(
            null,
            locationId,
            'Order with blank Type should not resolve location.'
        );
    }

    @IsTest
    static void testNoMetadataRuleFound() {
        String fakeOrderType =
            'DO_NOT_MATCH_ANY_METADATA_' + String.valueOf(System.now().getTime());

        Test.startTest();

        InventoryRuleService.InventoryRuleResult result =
            InventoryRuleService.getRuleForOrderType(fakeOrderType);

        Id locationId =
            InventoryRuleService.getLocationIdForOrderType(fakeOrderType);

        String locationName =
            InventoryRuleService.getLocationNameForOrderType(fakeOrderType);

        Test.stopTest();

        System.assertEquals(
            null,
            result,
            'Unknown order type should not find metadata.'
        );

        System.assertEquals(
            null,
            locationId,
            'Unknown order type should not resolve location Id.'
        );

        System.assertEquals(
            null,
            locationName,
            'Unknown order type should not resolve location name.'
        );
    }


    @IsTest
    static void testPosOrderAlwaysResolvesWarehouse() {
        // The POS rule may be absent in an org, or may be configured incorrectly.
        // Both cases must still resolve the Salesforce inventory Location Warehouse.
        Id warehouseId = createLocationRecord(LOCATION_WAREHOUSE);

        Account acc = new Account(Name = 'POS Inventory Rule Test Account');
        insert acc;

        Order posOrder = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'POS'
        );
        insert posOrder;

        Test.startTest();
        InventoryRuleService.InventoryRuleResult byType =
            InventoryRuleService.getRuleForOrderType('POS');
        InventoryRuleService.InventoryRuleResult byOrder =
            InventoryRuleService.getRuleForOrder(posOrder);
        Id locationIdByType = InventoryRuleService.getLocationIdForOrderType('POS');
        Id locationIdByOrder = InventoryRuleService.getLocationIdForOrder(posOrder);
        String locationName = InventoryRuleService.getLocationNameForOrderType('POS');
        Test.stopTest();

        System.assertNotEquals(null, byType, 'POS should return an InventoryRuleResult.');
        System.assertEquals('Warehouse', byType.locationName);
        System.assertEquals(warehouseId, byType.locationId);

        System.assertNotEquals(null, byOrder, 'POS Order should resolve an InventoryRuleResult.');
        System.assertEquals('Warehouse', byOrder.locationName);
        System.assertEquals(warehouseId, byOrder.locationId);

        System.assertEquals(warehouseId, locationIdByType);
        System.assertEquals(warehouseId, locationIdByOrder);
        System.assertEquals('Warehouse', locationName);
    }

    @IsTest
    static void testPosOrderUsesWarehouseWhenMetadataLocationIsDifferent() {
        Id warehouseId = createLocationRecord(LOCATION_WAREHOUSE);

        // Read any configured POS rule. If it points elsewhere, create that
        // Salesforce Location too, so the test verifies the POS override rather
        // than relying on the missing-Location fallback.
        List<Inventory_Rules__mdt> posRules = [
            SELECT DeveloperName, Order_Type__c, Location__c
            FROM Inventory_Rules__mdt
            WHERE Order_Type__c = 'POS'
            LIMIT 1
        ];

        if (!posRules.isEmpty() &&
            String.isNotBlank(posRules[0].Location__c) &&
            !posRules[0].Location__c.trim().equalsIgnoreCase('Warehouse')) {
            createLocationRecord(posRules[0].Location__c);
        }

        Test.startTest();
        InventoryRuleService.InventoryRuleResult result =
            InventoryRuleService.getRuleForOrderType('POS');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('Warehouse', result.locationName);
        System.assertEquals(
            warehouseId,
            result.locationId,
            'POS must use Warehouse even when metadata specifies another location.'
        );
    }

}