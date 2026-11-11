public without sharing class SquareCatalogService {
    
    public static void syncProductsToSquare(List<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return;
        }
        
        List<Product2> products = [
            SELECT Id,
            Name,
            Description,
            IsActive,
            Type__c,
            Parent__c,
            Parent__r.Name,
            Parent__r.Square_Catalog_Item_Id__c,
            StockKeepingUnit,
            Square_Catalog_Item_Id__c,
            Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Id IN :productIds
        ];
        
        Set<Id> parentProductIdsForImage = new Set<Id>();
        
        for (Product2 p : products) {
            if (
                p.Type__c != null &&
                p.Type__c.trim().equalsIgnoreCase('Variant') &&
                p.Parent__c != null
            ) {
                syncVariantToSquare(p);
                parentProductIdsForImage.add(p.Parent__c);
            }
        }
        
        if (!parentProductIdsForImage.isEmpty()) {
            System.enqueueJob(
                new SquareCatalogImageQueueable(parentProductIdsForImage)
            );
        }
    }
    
    @TestVisible
    private static void syncItemToSquare(Product2 p) {
        String squareId = String.isBlank(p.Square_Catalog_Item_Id__c)
            ? '#ITEM_' + String.valueOf(p.Id)
            : p.Square_Catalog_Item_Id__c;
        
        Map<String, Object> catalogObject = new Map<String, Object>{
            'type' => 'ITEM',
                'id' => squareId,
                'present_at_all_locations' => true,
                'item_data' => new Map<String, Object>{
                    'name' => p.Name
                        }
        };
            
            if (!String.isBlank(p.Description)) {
                ((Map<String, Object>) catalogObject.get('item_data'))
                .put('description', p.Description);
            }
        
        // Fix: Existing Square catalog objects require latest version.
        catalogObject = addLatestSquareVersionIfNeeded(catalogObject);
        
        Map<String, Object> response = SquareApiClient.upsertCatalogObject(catalogObject);
        
        Map<String, Object> obj = (Map<String, Object>) response.get('catalog_object');
        
        if (obj != null && obj.get('id') != null) {
            update new Product2(
                Id = p.Id,
                Square_Catalog_Item_Id__c = String.valueOf(obj.get('id'))
            );
        }
    }
    
    @TestVisible
    private static void syncVariantToSquare(Product2 v) {
        if (v == null || v.Parent__c == null) {
            return;
        }
        
        Decimal unitPrice = getVariantPrice(v.Id);
        
        if (unitPrice == null) {
            throw new SquareCatalogSyncException(
                'Square sync skipped because no active Square Pricebook entry exists. ' +
                'VariantId=' + v.Id +
                ', SKU=' + v.StockKeepingUnit
            );
        }
        
        Integer amountInCents = Integer.valueOf((unitPrice * 100).setScale(0));
        
        Product2 parentProduct = [
            SELECT Id,
            Name,
            Description,
            Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id = :v.Parent__c
            LIMIT 1
        ];
        
        String itemId = String.isBlank(parentProduct.Square_Catalog_Item_Id__c)
            ? '#ITEM_' + String.valueOf(parentProduct.Id)
            : parentProduct.Square_Catalog_Item_Id__c;
        
        String variationId = String.isBlank(v.Square_Catalog_Variation_Id__c)
            ? '#VAR_' + String.valueOf(v.Id)
            : v.Square_Catalog_Variation_Id__c;
        
        Map<String, Object> variationData = new Map<String, Object>{
            'item_id' => itemId,
                'name' => String.isBlank(v.Name) ? 'Default' : v.Name,
                    'sku' => v.StockKeepingUnit,
                    'pricing_type' => 'FIXED_PRICING',
                    'price_money' => new Map<String, Object>{
                        'amount' => amountInCents,
                            'currency' => 'GBP'
                            }
        };
            
            Map<String, Object> itemData = new Map<String, Object>{
                'name' => parentProduct.Name,
                    'variations' => new List<Object>{
                        new Map<String, Object>{
                            'type' => 'ITEM_VARIATION',
                                'id' => variationId,
                                'present_at_all_locations' => true,
                                'item_variation_data' => variationData
                                }
                    }
            };
                
                if (!String.isBlank(parentProduct.Description)) {
                    itemData.put('description', parentProduct.Description);
                }
        
        // Image sync will be handled in a separate Queueable.
        // Do not create ContentDistribution or Square IMAGE object here,
        // because DML before callout causes uncommitted work pending errors.
        
        /*String imageUrl = getPrimaryImageUrl(parentProduct.Id);
if (!String.isBlank(imageUrl)) {
String squareImageId = SquareApiClient.createImageObject(imageUrl);

if (!String.isBlank(squareImageId)) {
itemData.put(
'image_ids',
new List<String>{ squareImageId }
);
}
}*/
        
        Map<String, Object> catalogObject = new Map<String, Object>{
            'type' => 'ITEM',
                'id' => itemId,
                'present_at_all_locations' => true,
                'item_data' => itemData
                };
                    
                    // Fix: Existing Square catalog objects require latest version.
                    catalogObject = addLatestSquareVersionIfNeeded(catalogObject);
        
        Map<String, Object> response =
            SquareApiClient.upsertCatalogObject(catalogObject);
        
        Map<String, Object> obj =
            (Map<String, Object>) response.get('catalog_object');
        
        if (obj == null || obj.get('id') == null) {
            return;
        }
        
        String savedItemId = String.valueOf(obj.get('id'));
        String savedVariationId = v.Square_Catalog_Variation_Id__c;
        
        if (String.isBlank(savedVariationId) && response.containsKey('id_mappings')) {
            List<Object> mappings = (List<Object>) response.get('id_mappings');
            
            for (Object rawMapping : mappings) {
                Map<String, Object> mapping = (Map<String, Object>) rawMapping;
                
                if ((String) mapping.get('client_object_id') == variationId) {
                    savedVariationId = (String) mapping.get('object_id');
                    break;
                }
            }
        }
        
        update new Product2(
            Id = parentProduct.Id,
            Square_Catalog_Item_Id__c = savedItemId
        );
        
        if (!String.isBlank(savedVariationId)) {
            update new Product2(
                Id = v.Id,
                Square_Catalog_Variation_Id__c = savedVariationId,
                Square_Catalog_Item_Id__c = savedItemId
            );
        }
    }
    
    @TestVisible
    private static Map<Id, Decimal> getStandardPrices(List<Id> productIds) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        
        Id standardPricebookId = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = 'Square Pricebook'
            LIMIT 1
        ].Id;
        
        for (PricebookEntry pbe : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
            AND Pricebook2Id = :standardPricebookId
            AND IsActive = true
        ]) {
            result.put(pbe.Product2Id, pbe.UnitPrice);
        }
        
        return result;
    }
    
    @TestVisible
    private static Decimal getVariantPrice(Id productId) {
        
        Id standardPricebookId = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = 'Square Pricebook'
            LIMIT 1
        ].Id;
        
        List<PricebookEntry> entries = [
            SELECT UnitPrice
            FROM PricebookEntry
            WHERE Product2Id = :productId
            AND Pricebook2Id = :standardPricebookId
            AND IsActive = true
            LIMIT 1
        ];
        
        if (!entries.isEmpty()) {
            return entries[0].UnitPrice;
        }
        
        return null;
    }
    
    @TestVisible
    private static String getPrimaryImageUrl(Id parentProductId) {
        
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :parentProductId
            LIMIT 1
        ];
        
        if (links.isEmpty()) {
            return null;
        }
        
        ContentVersion cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        
        List<ContentDistribution> existing = [
            SELECT DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :cv.Id
            LIMIT 1
        ];
        
        if (!existing.isEmpty()) {
            return existing[0].DistributionPublicUrl;
        }
        
        ContentDistribution dist = new ContentDistribution();
        dist.Name = 'Square Product Image';
        dist.ContentVersionId = cv.Id;
        dist.PreferencesAllowViewInBrowser = true;
        dist.PreferencesLinkLatestVersion = true;
        dist.PreferencesNotifyOnVisit = false;
        
        insert dist;
        
        dist = [
            SELECT DistributionPublicUrl
            FROM ContentDistribution
            WHERE Id = :dist.Id
            LIMIT 1
        ];
        
        return dist.DistributionPublicUrl;
    }
    
    @TestVisible
    private static Map<String, Object>
        addLatestSquareVersionIfNeeded(
            Map<String, Object> catalogObject
        ) {
            if (
                catalogObject == null ||
                catalogObject.get('id') == null
            ) {
                return catalogObject;
            }
            
            String itemId = String.valueOf(catalogObject.get('id'));
            
            if (String.isBlank(itemId) || itemId.startsWith('#')) {
                return catalogObject;
            }
            
            try {
                Map<String, Object> latestResponse =
                    SquareApiClient.retrieveCatalogObject(itemId);
                
                Map<String, Object> latestItem =
                    latestResponse == null
                    ? null
                    : (Map<String, Object>) latestResponse.get('object');
                
                if (latestItem == null) {
                    return catalogObject;
                }
                
                applyLatestVersions(catalogObject, latestItem);
                return catalogObject;
                
            } catch (Exception exceptionRecord) {
                if (isSquareCatalogObjectNotFound(exceptionRecord)) {
                    return convertToNewCatalogObject(catalogObject);
                }
                
                throw exceptionRecord;
            }
        }
    @TestVisible
    private static void applyLatestVersions(
        Map<String, Object> outgoingItem,
        Map<String, Object> latestItem
    ) {
        if (latestItem.get('version') != null) {
            outgoingItem.put(
                'version',
                latestItem.get('version')
            );
        }
        
        Map<String, Object> outgoingItemData =
            (Map<String, Object>) outgoingItem.get('item_data');
        
        Map<String, Object> latestItemData =
            (Map<String, Object>) latestItem.get('item_data');
        
        if (outgoingItemData == null || latestItemData == null) {
            return;
        }
        
        List<Object> outgoingVariations =
            (List<Object>) outgoingItemData.get('variations');
        
        List<Object> latestVariations =
            (List<Object>) latestItemData.get('variations');
        
        if (
            outgoingVariations == null ||
            latestVariations == null
        ) {
            return;
        }
        
        Map<String, Map<String, Object>> latestById =
            new Map<String, Map<String, Object>>();
        
        for (Object rawLatest : latestVariations) {
            Map<String, Object> latestVariation =
                (Map<String, Object>) rawLatest;
            
            if (latestVariation.get('id') != null) {
                latestById.put(
                    String.valueOf(latestVariation.get('id')),
                    latestVariation
                );
            }
        }
        
        for (Object rawOutgoing : outgoingVariations) {
            Map<String, Object> outgoingVariation =
                (Map<String, Object>) rawOutgoing;
            
            String variationId =
                outgoingVariation.get('id') == null
                ? null
                : String.valueOf(outgoingVariation.get('id'));
            
            if (
                String.isBlank(variationId) ||
                variationId.startsWith('#') ||
                !latestById.containsKey(variationId)
            ) {
                continue;
            }
            
            Map<String, Object> latestVariation =
                latestById.get(variationId);
            
            if (latestVariation.get('version') != null) {
                outgoingVariation.put(
                    'version',
                    latestVariation.get('version')
                );
            }
        }
    }
    
    @TestVisible
    private static Boolean isSquareCatalogObjectNotFound(
        Exception exceptionRecord
    ) {
        if (
            exceptionRecord == null ||
            String.isBlank(exceptionRecord.getMessage())
        ) {
            return false;
        }
        
        String message = exceptionRecord.getMessage();
        
        return message.contains('Status=404') ||
            message.contains('"code":"NOT_FOUND"') ||
            message.contains('not found');
    }
    
    @TestVisible
    private static Map<String, Object>
        convertToNewCatalogObject(
            Map<String, Object> catalogObject
        ) {
            String newItemId =
                '#ITEM_' +
                String.valueOf(Math.abs(Crypto.getRandomLong()));
            
            catalogObject.put('id', newItemId);
            catalogObject.remove('version');
            
            Map<String, Object> itemData =
                (Map<String, Object>) catalogObject.get('item_data');
            
            if (itemData == null) {
                return catalogObject;
            }
            
            List<Object> variations =
                (List<Object>) itemData.get('variations');
            
            if (variations == null) {
                return catalogObject;
            }
            
            Integer sequenceNumber = 0;
            
            for (Object rawVariation : variations) {
                sequenceNumber++;
                
                Map<String, Object> variation =
                    (Map<String, Object>) rawVariation;
                
                String newVariationId =
                    '#VAR_' +
                    String.valueOf(Math.abs(Crypto.getRandomLong())) +
                    '_' +
                    sequenceNumber;
                
                variation.put('id', newVariationId);
                variation.remove('version');
                
                Map<String, Object> variationData =
                    (Map<String, Object>)
                    variation.get('item_variation_data');
                
                if (variationData != null) {
                    variationData.put('item_id', newItemId);
                }
            }
            
            return catalogObject;
        }
    
    public class SquareCatalogSyncException extends Exception {
    }
}