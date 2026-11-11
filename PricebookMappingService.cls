public without sharing class PricebookMappingService {

    public class PricebookMappingException extends Exception {}

    @TestVisible
    private static List<Shopify_Pricebook_Mapping__mdt> testDefaultMappings;

    @TestVisible
    private static List<Shopify_Pricebook_Mapping__mdt> testActiveMappings;

    @TestVisible
    private static List<Shopify_Pricebook_Mapping__mdt> testLocationMappings;

    public static Id getDefaultPricebookId() {
        List<Shopify_Pricebook_Mapping__mdt> mappings = getDefaultMappings();

        if (!mappings.isEmpty()) {
            Id mappedPricebookId = getPricebookIdByName(mappings[0].Pricebook_Name__c);

            if (mappedPricebookId != null) {
                return mappedPricebookId;
            }
        }

        return getStandardPricebookIdSafe();
    }
    
    public static Id getStandardPricebookIdForShopifyPriceSync() {
        return getStandardPricebookIdSafe();
    }

    public static List<Id> getInboundProductPricebookIds() {
        List<Id> pricebookIds = new List<Id>();

        for (Shopify_Pricebook_Mapping__mdt m : getActiveMappings()) {
            Id pbId = getPricebookIdByName(m.Pricebook_Name__c);

            if (pbId != null && !pricebookIds.contains(pbId)) {
                pricebookIds.add(pbId);
            }
        }

        if (pricebookIds.isEmpty()) {
            Id defaultPbId = getDefaultPricebookId();

            if (defaultPbId != null) {
                pricebookIds.add(defaultPbId);
            }
        }

        return pricebookIds;
    }

    public static Id getPricebookIdByShopifyLocation(String shopifyLocationId) {
        if (String.isBlank(shopifyLocationId)) {
            return getDefaultPricebookId();
        }

        List<Shopify_Pricebook_Mapping__mdt> mappings = getLocationMappings(shopifyLocationId);

        if (!mappings.isEmpty()) {
            Id mappedPricebookId = getPricebookIdByName(mappings[0].Pricebook_Name__c);

            if (mappedPricebookId != null) {
                return mappedPricebookId;
            }
        }

        return getDefaultPricebookId();
    }

    private static Id getPricebookIdByName(String pricebookName) {
        if (String.isBlank(pricebookName)) {
            return getStandardPricebookIdSafe();
        }

        List<Pricebook2> books = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = :pricebookName
            AND IsActive = true
            LIMIT 1
        ];

        if (!books.isEmpty()) {
            return books[0].Id;
        }

        return getStandardPricebookIdSafe();
    }

    private static Id getStandardPricebookIdSafe() {
        List<Pricebook2> standardBooks = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = true
            LIMIT 1
        ];

        if (!standardBooks.isEmpty()) {
            return standardBooks[0].Id;
        }

        throw new PricebookMappingException('Standard Pricebook was not found.');
    }

    private static List<Shopify_Pricebook_Mapping__mdt> getDefaultMappings() {
        if (Test.isRunningTest() && testDefaultMappings != null) {
            return testDefaultMappings;
        }

        return [
            SELECT Pricebook_Name__c
            FROM Shopify_Pricebook_Mapping__mdt
            WHERE Active__c = true
            AND Is_Default__c = true
            LIMIT 1
        ];
    }

    private static List<Shopify_Pricebook_Mapping__mdt> getActiveMappings() {
        if (Test.isRunningTest() && testActiveMappings != null) {
            return testActiveMappings;
        }

        return [
            SELECT Pricebook_Name__c
            FROM Shopify_Pricebook_Mapping__mdt
            WHERE Active__c = true
        ];
    }

    private static List<Shopify_Pricebook_Mapping__mdt> getLocationMappings(String shopifyLocationId) {
        if (Test.isRunningTest() && testLocationMappings != null) {
            return testLocationMappings;
        }

        return [
            SELECT Pricebook_Name__c
            FROM Shopify_Pricebook_Mapping__mdt
            WHERE Active__c = true
            AND Shopify_Location_Id__c = :shopifyLocationId
            LIMIT 1
        ];
    }
}