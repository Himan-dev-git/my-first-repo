public without sharing class ShopifyInventoryPullService {
    
    @future(callout=true)
    public static void pullInventoryForVariantShopIdsAsync(List<String> variantShopIds) {
        pullInventoryForVariantShopIds(variantShopIds);
    }
    
    public static void pullInventoryForVariantShopIds(List<String> variantShopIds) {
        if (variantShopIds == null || variantShopIds.isEmpty()) return;
        
        List<Product2> variants = [
            SELECT Id, Shop_ID__c, Inventory_Item_Id__c
            FROM Product2
            WHERE Shop_ID__c IN :variantShopIds
        ];
        
        Map<String, Id> locationIdByShopifyId = getCanonicalLocationMap();
        
        for (Product2 variant : variants) {
            pullInventoryForSingleVariant(variant, locationIdByShopifyId);
        }
    }
    
    /**
* Returns one SF Location Id per Shopify_Location_ID__c.
* Ordered by CreatedDate ASC so the oldest (original) record always wins,
* keeping Inventory__c.Location__c stable across runs.
* Once the unique constraint is added to Shopify_Location_ID__c
* this will always return exactly one row per location.
*/
    
    private static Map<String, Id> getCanonicalLocationMap() {
        
        Map<String, Id> result = new Map<String, Id>();  
        for (SObject loc : Database.query(
            
            'SELECT Id, Shopify_Location_ID__c ' +         
            'FROM Location ' +         
            'WHERE Shopify_Location_ID__c != null ' + 
            'ORDER BY CreatedDate ASC'
            
        )) {
            
            String shopifyLocId = (String) loc.get('Shopify_Location_ID__c');    
            // First-write wins = oldest record per location ID     
            if (!result.containsKey(shopifyLocId)) {  
                result.put(shopifyLocId, (Id) loc.get('Id'));
                
            }            
        }        
        return result;        
    }
   
    private static void pullInventoryForSingleVariant(       
        Product2 variant,  
        Map<String, Id> locationIdByShopifyId
        
    ) {
        
        if (variant == null || String.isBlank(variant.Shop_ID__c)) return;
                  
        String queryText =            
            'query VariantInventoryLevels($variantId: ID!) {' +            
            '  productVariant(id: $variantId) {' +            
            '    id ' +            
            '    inventoryItem { ' +            
            '      id ' +            
            '      inventoryLevels(first: 100) { ' +            
            '        nodes { ' +            
            '          location { id name } ' +            
            '          quantities(names: ["available"]) { name quantity } ' +            
            '        } ' +            
            '      } ' +            
            '    } ' +            
            '  } ' +            
            '}';
                        
        Map<String, Object> response = ShopifyGraphQLHelper.execute(            
            queryText,            
            new Map<String, Object>{
                                'variantId' => ShopifyGraphQLHelper.toVariantGid(variant.Shop_ID__c)
                    
                    }            
        );               
        
        Map<String, Object> dataMap = (Map<String, Object>) response.get('data');   
        Map<String, Object> productVariantMap =          
            dataMap == null ? null : (Map<String, Object>) dataMap.get('productVariant');      
        Map<String, Object> inventoryItemMap =            
            productVariantMap == null            
            ? null          
            : (Map<String, Object>) productVariantMap.get('inventoryItem');
    
        if (inventoryItemMap == null) return;
              
        String inventoryItemId = ShopifyGraphQLHelper.extractNumericIdFromGid(           
            (String) inventoryItemMap.get('id')         
        );
                
        Map<String, Object> levelsMap =            
            (Map<String, Object>) inventoryItemMap.get('inventoryLevels');        
        List<Object> nodes =            
            levelsMap == null ? new List<Object>() : (List<Object>) levelsMap.get('nodes');
        
        List<Inventory__c> rowsToUpsert = new List<Inventory__c>();
                
        for (Object nodeObj : nodes) {            
            Map<String, Object> node = (Map<String, Object>) nodeObj;            
            Map<String, Object> locMap = (Map<String, Object>) node.get('location');            
            if (locMap == null) continue;                    
            
            String shopifyLocationId = ShopifyGraphQLHelper.extractNumericIdFromGid(               
                (String) locMap.get('id')                
            );                     
            
            Id sfLocationId = locationIdByShopifyId.get(shopifyLocationId);            
            if (sfLocationId == null) {
                
                System.debug(                  
                    LoggingLevel.WARN,                   
                    'ShopifyInventoryPullService: No SF Location found for ' +                   
                    'Shopify Location Id: ' + shopifyLocationId +                   
                    '. Skipping inventory row for variant: ' + variant.Shop_ID__c                    
                );
                
                continue;                
            }
                                  
            Decimal available = 0;
            
            List<Object> quantities = (List<Object>) node.get('quantities');            
            if (quantities != null) {                
                for (Object qObj : quantities) {                    
                    Map<String, Object> q = (Map<String, Object>) qObj;                    
                    if ('available'.equals((String) q.get('name'))) {                        
                        available = Decimal.valueOf(String.valueOf(q.get('quantity')));
                        
                    }                   
                }                
            }
                             
            Inventory__c inv = new Inventory__c();            
            inv.Variant__c                   = variant.Id;            
            inv.Location__c                  = sfLocationId;            
            inv.Available__c                 = available;            
            inv.Shopify_Inventory_Item_ID__c = inventoryItemId;            
            inv.Shopify_Location_ID__c       = shopifyLocationId;            
            inv.Inventory_Key__c             = variant.Shop_ID__c + '-' + shopifyLocationId;            
            inv.Sync_Status__c               = 'Success';            
            inv.Last_Sync_At__c              = System.now();                 
            
            if (Inventory__c.SObjectType.getDescribe().fields.getMap()
                .containsKey('Shop_ID__c')) {
                   inv.put('Shop_ID__c', variant.Shop_ID__c);
                    
                }                   
            rowsToUpsert.add(inv);       
        }
        
        if (!rowsToUpsert.isEmpty()) {
            InventorySyncControl.skipOutbound = true;
            
            try {
                upsert rowsToUpsert Inventory_Key__c;
            } finally {
                
                InventorySyncControl.skipOutbound = false;
                
            }
        }
    }
}