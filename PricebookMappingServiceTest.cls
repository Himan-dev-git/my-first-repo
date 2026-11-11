@IsTest
private class PricebookMappingServiceTest {

    @TestSetup
    static void setupData() {
        Id standardPbId = Test.getStandardPricebookId();

        update new Pricebook2(
            Id = standardPbId,
            IsActive = true
        );

        insert new Pricebook2(
            Name = 'Shopify Retail Pricebook',
            IsActive = true
        );

        insert new Pricebook2(
            Name = 'Shopify Wholesale Pricebook',
            IsActive = true
        );
    }

    private static Shopify_Pricebook_Mapping__mdt mapping(String pricebookName) {
        Shopify_Pricebook_Mapping__mdt m = new Shopify_Pricebook_Mapping__mdt();
        m.Pricebook_Name__c = pricebookName;
        return m;
    }

    private static Id pricebookIdByName(String name) {
        return [
            SELECT Id
            FROM Pricebook2
            WHERE Name = :name
            LIMIT 1
        ].Id;
    }

    @IsTest
    static void testGetDefaultPricebookIdFallsBackToStandardPricebook() {
        Id standardPbId = Test.getStandardPricebookId();

        PricebookMappingService.testDefaultMappings =
            new List<Shopify_Pricebook_Mapping__mdt>();

        Test.startTest();
        Id result = PricebookMappingService.getDefaultPricebookId();
        Test.stopTest();

        System.assertEquals(standardPbId, result);
    }

    @IsTest
    static void testGetDefaultPricebookIdUsesMappedPricebook() {
        Id retailPbId = pricebookIdByName('Shopify Retail Pricebook');

        PricebookMappingService.testDefaultMappings =
            new List<Shopify_Pricebook_Mapping__mdt>{
                mapping('Shopify Retail Pricebook')
            };

        Test.startTest();
        Id result = PricebookMappingService.getDefaultPricebookId();
        Test.stopTest();

        System.assertEquals(retailPbId, result);
    }

    @IsTest
    static void testGetDefaultPricebookIdMappedNameNotFoundFallsBackToStandard() {
        Id standardPbId = Test.getStandardPricebookId();

        PricebookMappingService.testDefaultMappings =
            new List<Shopify_Pricebook_Mapping__mdt>{
                mapping('Missing Pricebook Name')
            };

        Test.startTest();
        Id result = PricebookMappingService.getDefaultPricebookId();
        Test.stopTest();

        System.assertEquals(standardPbId, result);
    }

    @IsTest
    static void testGetInboundProductPricebookIdsFallsBackToDefault() {
        Id standardPbId = Test.getStandardPricebookId();

        PricebookMappingService.testActiveMappings =
            new List<Shopify_Pricebook_Mapping__mdt>();

        PricebookMappingService.testDefaultMappings =
            new List<Shopify_Pricebook_Mapping__mdt>();

        Test.startTest();
        List<Id> result = PricebookMappingService.getInboundProductPricebookIds();
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(standardPbId, result[0]);
    }

    @IsTest
    static void testGetInboundProductPricebookIdsUsesActiveMappingsAndSkipsDuplicates() {
        Id retailPbId = pricebookIdByName('Shopify Retail Pricebook');
        Id wholesalePbId = pricebookIdByName('Shopify Wholesale Pricebook');

        PricebookMappingService.testActiveMappings =
            new List<Shopify_Pricebook_Mapping__mdt>{
                mapping('Shopify Retail Pricebook'),
                mapping('Shopify Retail Pricebook'),
                mapping('Shopify Wholesale Pricebook'),
                mapping('Missing Pricebook Name')
            };

        Test.startTest();
        List<Id> result = PricebookMappingService.getInboundProductPricebookIds();
        Test.stopTest();

        System.assert(result.size() >= 2, 'Should include at least the two mapped pricebooks.');
        System.assert(result.contains(retailPbId), 'Should include Retail pricebook.');
        System.assert(result.contains(wholesalePbId), 'Should include Wholesale pricebook.');
        System.assert(result.contains(retailPbId));
        System.assert(result.contains(wholesalePbId));
    }

    @IsTest
    static void testGetPricebookIdByShopifyLocationBlankFallsBackToDefault() {
        Id standardPbId = Test.getStandardPricebookId();

        PricebookMappingService.testDefaultMappings =
            new List<Shopify_Pricebook_Mapping__mdt>();

        Test.startTest();
        Id resultNull = PricebookMappingService.getPricebookIdByShopifyLocation(null);
        Id resultBlank = PricebookMappingService.getPricebookIdByShopifyLocation('');
        Id resultSpaces = PricebookMappingService.getPricebookIdByShopifyLocation('   ');
        Test.stopTest();

        System.assertEquals(standardPbId, resultNull);
        System.assertEquals(standardPbId, resultBlank);
        System.assertEquals(standardPbId, resultSpaces);
    }

    @IsTest
    static void testGetPricebookIdByShopifyLocationUsesMappedPricebook() {
        Id retailPbId = pricebookIdByName('Shopify Retail Pricebook');

        PricebookMappingService.testLocationMappings =
            new List<Shopify_Pricebook_Mapping__mdt>{
                mapping('Shopify Retail Pricebook')
            };

        Test.startTest();
        Id result = PricebookMappingService.getPricebookIdByShopifyLocation('SHOP_LOC_1');
        Test.stopTest();

        System.assertEquals(retailPbId, result);
    }

    @IsTest
    static void testGetPricebookIdByShopifyLocationNoMappingFallsBackToDefault() {
        Id standardPbId = Test.getStandardPricebookId();

        PricebookMappingService.testLocationMappings =
            new List<Shopify_Pricebook_Mapping__mdt>();

        PricebookMappingService.testDefaultMappings =
            new List<Shopify_Pricebook_Mapping__mdt>();

        Test.startTest();
        Id result = PricebookMappingService.getPricebookIdByShopifyLocation('NO_MATCHING_LOCATION');
        Test.stopTest();

        System.assertEquals(standardPbId, result);
    }

    @IsTest
    static void testGetPricebookIdByShopifyLocationMappedNameMissingFallsBackToDefault() {
        Id standardPbId = Test.getStandardPricebookId();

        PricebookMappingService.testLocationMappings =
            new List<Shopify_Pricebook_Mapping__mdt>{
                mapping('Missing Pricebook Name')
            };

        PricebookMappingService.testDefaultMappings =
            new List<Shopify_Pricebook_Mapping__mdt>();

        Test.startTest();
        Id result = PricebookMappingService.getPricebookIdByShopifyLocation('SHOP_LOC_2');
        Test.stopTest();

        System.assertEquals(standardPbId, result);
    }
}