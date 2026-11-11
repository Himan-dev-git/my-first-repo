public class ProductOrchestrationService {
    
    @TestVisible
    private static List<Id> testInboundPricebookIds;
    
    @TestVisible
    private static List<REST_Field_Mapping__mdt> testFieldMappings;
    
    public static Map<String, List<String>> extIdTagMap = new Map<String, List<String>>();
    
    public static void processProductsFromRestRequest(Map<String, Object> payload, String[] topicNames) {
        
        Map<String, List<SObject>> objectRecordsMap = new Map<String, List<SObject>>{
            'Product' => new List<SObject>(),
                'Variant' => new List<SObject>(),
                'Topic' => new List<SObject>(),
                'PricebookEntry' => new List<SObject>()
                };
                    
                    // Get Product2 RecordType Ids
                    Map<String, Id> recordTypeIds = new Map<String, Id>();
        List<RecordType> recordTypes = [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName IN ('Product', 'Variant')
        ];
        for (RecordType rt : recordTypes) {
            recordTypeIds.put(rt.DeveloperName, rt.Id);
        }
        
        // Shopify inbound price behavior:
        // - Standard Pricebook should update whenever Shopify price changes.
        // - Non-standard pricebooks, such as Square, should be inserted once only.
        // - Square pricebook should later be controlled by Square sync, not Shopify.
        List<Id> inboundPricebookIds = PricebookMappingService.getInboundProductPricebookIds();
        Id standardPriceBookId = PricebookMappingService.getStandardPricebookIdForShopifyPriceSync();
        
        if (standardPriceBookId != null && !inboundPricebookIds.contains(standardPriceBookId)) {
            inboundPricebookIds.add(0, standardPriceBookId);
        }
        
        // Field mappings
        List<REST_Field_Mapping__mdt> fieldMappings = [
            SELECT SF_Field_Name__c, Request_Attribute__c, SF_Object_Name__c, Topic__c
            FROM REST_Field_Mapping__mdt
            WHERE Topic__c IN :topicNames
        ];
        
        Map<String, List<REST_Field_Mapping__mdt>> fieldMappingsGroupedByTopic = new Map<String, List<REST_Field_Mapping__mdt>>();
        for (REST_Field_Mapping__mdt thisMapping : fieldMappings) {
            String topic = thisMapping.Topic__c;
            if (topic != null) {
                if (!fieldMappingsGroupedByTopic.containsKey(topic)) {
                    fieldMappingsGroupedByTopic.put(topic, new List<REST_Field_Mapping__mdt>());
                }
                fieldMappingsGroupedByTopic.get(topic).add(thisMapping);
            }
        }
        
        List<Map<String, Object>> inboundProductsForFileSync = new List<Map<String, Object>>();
        Set<String> successfulVariantShopIds = new Set<String>();
        
        if (payload != null && payload.containsKey('products')) {
            List<Object> products = (List<Object>) payload.get('products');
            if (products != null) {
                for (Object product : products) {
                    Map<String, Object> productMap = (Map<String, Object>) product;
                    if (productMap != null) {
                        Map<String, List<SObject>> processedRecordsMap =
                            processSingleProduct(productMap, fieldMappingsGroupedByTopic, inboundPricebookIds, recordTypeIds);
                        
                        for (String key : objectRecordsMap.keySet()) {
                            objectRecordsMap.get(key).addAll(processedRecordsMap.get(key));
                        }
                        
                        inboundProductsForFileSync.add(productMap);
                    }
                }
            }
        } else if (payload != null && payload.containsKey('product')) {
            Map<String, Object> productMap = (Map<String, Object>) payload.get('product');
            if (productMap != null) {
                objectRecordsMap =
                    processSingleProduct(productMap, fieldMappingsGroupedByTopic, inboundPricebookIds, recordTypeIds);
                
                inboundProductsForFileSync.add(productMap);
            }
        }
        
        // Upsert Products first
        if (!objectRecordsMap.get('Product').isEmpty()) {
            Database.upsert(objectRecordsMap.get('Product'), Product2.Shop_ID__c, false);
        }
        
        //old image sync logic placeholder
        
        // Upsert Topics
        List<Database.UpsertResult> upsertResults = new List<Database.UpsertResult>();
        if (!objectRecordsMap.get('Topic').isEmpty()) {
            upsertResults.addAll(
                Database.upsert(objectRecordsMap.get('Topic'), Custom_Topic__c.External_Id__c, false)
            );
        }
        
        System.debug('upsertResults are ' + upsertResults);
        
        if (extIdTagMap != null && !extIdTagMap.isEmpty()) {
            for (String extID : extIdTagMap.keySet()) {
                Custom_Topic__c relCustTop;
                
                for (SObject thisObj : objectRecordsMap.get('Topic')) {
                    Custom_Topic__c thisCustTop = (Custom_Topic__c) thisObj;
                    if (thisCustTop.External_Id__c == extID) {
                        relCustTop = thisCustTop;
                    }
                }
                
                List<String> tags = extIdTagMap.get(extID);
                if (tags != null) {
                    for (String tag : tags) {
                        System.debug('Id: ' + relCustTop.Id + ' Tag: ' + tag);
                        if (!Test.isRunningTest() && !String.isBlank(tag)) {
                            try {
                                ConnectApi.Topic assign =
                                    ConnectApi.Topics.assignTopicByName(
                                        'internal',
                                        relCustTop.Id,
                                        tag
                                    );
                            } catch (System.NoAccessException e) {
                                System.debug(
                                    LoggingLevel.WARN,
                                    'Skipping Salesforce Topic assignment for tag "' +
                                    tag +
                                    '". Connect API is unavailable for the current user. Error=' +
                                    e.getMessage()
                                );
                            }
                        }
                    }
                }
            }
        }
        
        // Upsert Variants
        if (!objectRecordsMap.get('Variant').isEmpty()) {
            
            List<Product2> inboundVariants = new List<Product2>();
            Set<String> inboundVariantShopIds = new Set<String>();
            
            for (SObject sob : objectRecordsMap.get('Variant')) {
                Product2 v = (Product2) sob;
                
                inboundVariants.add(v);
                
                if (!String.isBlank(v.Shop_ID__c)) {
                    inboundVariantShopIds.add(v.Shop_ID__c);
                }
            }
            
            Set<String> existingVariantShopIds = new Set<String>();
            Map<String, Product2> existingVariantByShopId = new Map<String, Product2>();
            
            if (!inboundVariantShopIds.isEmpty()) {
                for (Product2 existingVariant : [
                    SELECT Id, Shop_ID__c, StockKeepingUnit
                    FROM Product2
                    WHERE Shop_ID__c IN :inboundVariantShopIds
                ]) {
                    existingVariantShopIds.add(existingVariant.Shop_ID__c);
                    existingVariantByShopId.put(existingVariant.Shop_ID__c, existingVariant);
                }
            }
            
            List<Product2> variantsNeedingSku = new List<Product2>();
            
            for (Product2 v : inboundVariants) {
                if (String.isBlank(v.Shop_ID__c)) {
                    continue;
                }
                
                Product2 existingVariant = existingVariantByShopId.get(v.Shop_ID__c);
                
                Boolean isBrandNewVariant = existingVariant == null;
                Boolean isExistingVariantMissingSku =
                    existingVariant != null &&
                    String.isBlank(existingVariant.StockKeepingUnit);
                
                if (isBrandNewVariant || isExistingVariantMissingSku) {
                    variantsNeedingSku.add(v);
                }
            }
            
            // Generate SKU for brand-new variants AND existing variants missing SKU.
            ProductSkuService.assignSkusForNewInboundVariants(variantsNeedingSku);
            
            // Update parent Product SKU with shortened SKU only when parent SKU is blank.
            // Parent SKU is the source of truth.
            // Existing parent SKU must not be overwritten by a newly generated child SKU.
            List<Product2> parentProductsForShortSkuUpdate = new List<Product2>();
            Map<String, String> shortSkuByParentShopId = new Map<String, String>();
            Set<String> parentShopIdsForShortSkuCheck = new Set<String>();
            
            for (Product2 v : variantsNeedingSku) {
                if (v == null) {
                    continue;
                }
                
                if (v.Parent__r == null || String.isBlank(v.Parent__r.Shop_ID__c)) {
                    continue;
                }
                
                if (String.isBlank(v.StockKeepingUnit)) {
                    continue;
                }
                
                parentShopIdsForShortSkuCheck.add(v.Parent__r.Shop_ID__c);
            }
            
            Map<String, Product2> existingParentByShopId = new Map<String, Product2>();
            
            if (!parentShopIdsForShortSkuCheck.isEmpty()) {
                for (Product2 parentProduct : [
                    SELECT Id, Shop_ID__c, StockKeepingUnit
                    FROM Product2
                    WHERE Shop_ID__c IN :parentShopIdsForShortSkuCheck
                    AND Type__c = 'Product'
                ]) {
                    existingParentByShopId.put(parentProduct.Shop_ID__c, parentProduct);
                }
            }
            
            for (Product2 v : variantsNeedingSku) {
                if (v == null) {
                    continue;
                }
                
                if (v.Parent__r == null || String.isBlank(v.Parent__r.Shop_ID__c)) {
                    continue;
                }
                
                if (String.isBlank(v.StockKeepingUnit)) {
                    continue;
                }
                
                Product2 existingParent =
                    existingParentByShopId.get(v.Parent__r.Shop_ID__c);
                
                /*
* Very important:
* If parent already has short SKU, do not overwrite it.
* Example:
* Parent R0050 must remain R0050.
* Child should follow R0050, not change parent to R0049.
*/
                if (
                    existingParent != null &&
                    !String.isBlank(existingParent.StockKeepingUnit)
                ) {
                    continue;
                }
                
                String shortSku = ProductSkuService.buildShortSkuForVariant(v);
                
                if (String.isBlank(shortSku)) {
                    continue;
                }
                
                if (!shortSkuByParentShopId.containsKey(v.Parent__r.Shop_ID__c)) {
                    shortSkuByParentShopId.put(v.Parent__r.Shop_ID__c, shortSku);
                }
            }
            
            for (String parentShopId : shortSkuByParentShopId.keySet()) {
                parentProductsForShortSkuUpdate.add(new Product2(
                    Shop_ID__c = parentShopId,
                    StockKeepingUnit = shortSkuByParentShopId.get(parentShopId)
                ));
            }
            
            if (!parentProductsForShortSkuUpdate.isEmpty()) {
                Database.upsert(
                    parentProductsForShortSkuUpdate,
                    Product2.Shop_ID__c,
                    false
                );
            }
            
            // ── First upsert attempt ──────────────────────────────────────
            Database.UpsertResult[] variantResults =
                Database.upsert(objectRecordsMap.get('Variant'), Product2.Shop_ID__c, false);
            
            // ── Handle results: log errors + collect Shop IDs ─────────────
            Integer variantIndex = 0;
            List<Product2> skuCollisionRetries = new List<Product2>();
            
            for (Database.UpsertResult r : variantResults) {
                Product2 sourceVariant =
                    (Product2) objectRecordsMap.get('Variant')[variantIndex];
                
                if (r.isSuccess()) {
                    if (!String.isBlank(sourceVariant.Shop_ID__c)) {
                        successfulVariantShopIds.add(sourceVariant.Shop_ID__c);
                    }
                } else {
                    Boolean isDuplicateSku = false;
                    for (Database.Error err : r.getErrors()) {
                        if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE &&
                            err.getMessage() != null &&
                            err.getMessage().containsIgnoreCase('SKU')) {
                                isDuplicateSku = true;
                            }
                        System.debug(
                            LoggingLevel.ERROR,
                            'Variant upsert failed for Shopify Variant ' +
                            sourceVariant.Shop_ID__c + ': ' +
                            err.getStatusCode() + ' - ' + err.getMessage()
                        );
                    }
                    // SKU collision: queue for retry with a fresh SKU
                    if (isDuplicateSku) {
                        skuCollisionRetries.add(sourceVariant);
                    }
                }
                variantIndex++;
            }
            
            upsertResults.addAll(variantResults);
            
            // ── Retry any SKU collisions (race-condition recovery) ────────
            if (!skuCollisionRetries.isEmpty()) {
                List<Product2> retryList =
                    ProductSkuService.resolveSkuCollisions(
                        skuCollisionRetries,
                        variantResults
                    );
                
                if (!retryList.isEmpty()) {
                    Database.UpsertResult[] retryResults =
                        Database.upsert(retryList, Product2.Shop_ID__c, false);
                    
                    for (Integer j = 0; j < retryResults.size(); j++) {
                        Database.UpsertResult rr = retryResults[j];
                        Product2 rv = retryList[j];
                        
                        if (rr.isSuccess()) {
                            System.debug(LoggingLevel.INFO,
                                         'Variant SKU collision retry SUCCEEDED for ' +
                                         rv.Shop_ID__c + ' with SKU=' + rv.StockKeepingUnit);
                            if (!String.isBlank(rv.Shop_ID__c)) {
                                successfulVariantShopIds.add(rv.Shop_ID__c);
                            }
                        } else {
                            for (Database.Error err : rr.getErrors()) {
                                System.debug(LoggingLevel.ERROR,
                                             'Variant retry also failed for ' + rv.Shop_ID__c +
                                             ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                            }
                        }
                    }
                    
                    upsertResults.addAll(retryResults);
                }
            }
            
            // ── Build newOnlyVariantIds for SKU sync back to Shopify ──────
            List<Id> newOnlyVariantIds = new List<Id>();
            
            for (SObject sob : objectRecordsMap.get('Variant')) {
                Product2 v = (Product2) sob;
                
                if (
                    v.Id != null &&
                    !String.isBlank(v.StockKeepingUnit) &&
                    !existingVariantShopIds.contains(v.Shop_ID__c)
                ) {
                    newOnlyVariantIds.add(v.Id);
                }
            }
            
            /*
* KEEP ENABLED:
* This is the controlled SKU-only Salesforce -> Shopify writeback.
* General product attribute synchronization is disabled in
* ShopifyProductGraphQLService.syncProductsAsync.
*/
            if (!newOnlyVariantIds.isEmpty()) {
                System.debug(
                    LoggingLevel.INFO,
                    'New inbound variant SKUs generated. SKU writeback variantIds=' +
                    newOnlyVariantIds
                );
                
                if (!System.isFuture() && !System.isBatch() && !System.isQueueable()) {
                    System.enqueueJob(new ShopifySkuWritebackQueueable(newOnlyVariantIds));
                }
            }
            
            // Existing — unchanged
            /*if (!newOnlyVariantIds.isEmpty()) {
ShopifyProductGraphQLService.syncVariantSkuOnlyAsync(newOnlyVariantIds);
}*/
            
            // NEW: Fetch weight from Shopify InventoryItem for all successfully upserted variants.
            // Weight is structurally absent from Shopify REST product webhook payloads.
            // Must be fetched from inventoryItem.measurement.weight via GraphQL.
            List<Id> variantIdsForWeightSync = new List<Id>();
            for (SObject sob : objectRecordsMap.get('Variant')) {
                Product2 v = (Product2) sob;
                if (v.Id != null && !String.isBlank(v.Inventory_Item_Id__c)) {
                    variantIdsForWeightSync.add(v.Id);
                }
            }
            
            if (!variantIdsForWeightSync.isEmpty()) {
                if (System.isFuture() || System.isBatch()) {
                    System.debug(
                        LoggingLevel.INFO,
                        'Skipping syncVariantWeightAsync because ProductOrchestrationService is already running async. ' +
                        'variantIdsForWeightSync=' + variantIdsForWeightSync
                    );
                } else {
                    ShopifyProductGraphQLService.syncVariantWeightAsync(variantIdsForWeightSync);
                }
            }
        }        
        // Insert Pricebook Entries
        // Insert / Update Pricebook Entries
        if (!objectRecordsMap.get('PricebookEntry').isEmpty()) {
            
            List<PricebookEntry> inboundPbes =
                (List<PricebookEntry>) objectRecordsMap.get('PricebookEntry');
            
            Set<String> variantShopIds = new Set<String>();
            
            for (SObject sob : objectRecordsMap.get('Variant')) {
                Product2 v = (Product2) sob;
                if (!String.isBlank(v.Shop_ID__c)) {
                    variantShopIds.add(v.Shop_ID__c);
                }
            }
            
            Map<String, Id> variantIdByShopId = new Map<String, Id>();
            
            if (!variantShopIds.isEmpty()) {
                for (Product2 p : [
                    SELECT Id, Shop_ID__c
                    FROM Product2
                    WHERE Shop_ID__c IN :variantShopIds
                ]) {
                    variantIdByShopId.put(p.Shop_ID__c, p.Id);
                }
            }
            
            Set<Id> productIds = new Set<Id>();
            Set<Id> pricebookIds = new Set<Id>();
            
            Integer pbeIndex = 0;
            
            for (SObject sob : objectRecordsMap.get('Variant')) {
                Product2 v = (Product2) sob;
                
                for (Id pricebookId : inboundPricebookIds) {
                    if (
                        pbeIndex < inboundPbes.size() &&
                        !String.isBlank(v.Shop_ID__c) &&
                        variantIdByShopId.containsKey(v.Shop_ID__c)
                    ) {
                        inboundPbes[pbeIndex].Product2Id = variantIdByShopId.get(v.Shop_ID__c);
                    }
                    
                    pbeIndex++;
                }
            }
            
            for (PricebookEntry pbe : inboundPbes) {
                if (pbe.Product2Id != null) {
                    productIds.add(pbe.Product2Id);
                }
                
                if (pbe.Pricebook2Id != null) {
                    pricebookIds.add(pbe.Pricebook2Id);
                }
            }
            
            Map<String, PricebookEntry> existingPbeMap =
                getExistingPricebookEntries(productIds, pricebookIds);
            
            List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
            List<PricebookEntry> pbesToUpdate = new List<PricebookEntry>();
            
            for (PricebookEntry incoming : inboundPbes) {
                if (incoming.Product2Id == null || incoming.Pricebook2Id == null) {
                    continue;
                }
                
                String key = incoming.Product2Id + '-' + incoming.Pricebook2Id;
                
                if (existingPbeMap.containsKey(key)) {
                    PricebookEntry existing = existingPbeMap.get(key);
                    
                    /*
* Important:
* Shopify price changes should update Standard Pricebook only.
*
* Non-standard pricebooks, such as Square, are inserted once from Shopify
* if missing, but after that Shopify must not update their prices.
* Square pricebook should be controlled by Square sync.
*/
                    if (existing.Pricebook2Id == standardPriceBookId) {
                        existing.UnitPrice = incoming.UnitPrice;
                        existing.IsActive = true;
                        pbesToUpdate.add(existing);
                    } else {
                        System.debug(
                            LoggingLevel.INFO,
                            'Skipping Shopify price update for non-standard PricebookEntry. ' +
                            'Product2Id=' + existing.Product2Id +
                            ', Pricebook2Id=' + existing.Pricebook2Id +
                            ', IncomingUnitPrice=' + incoming.UnitPrice
                        );
                    }
                } else {
                    /*
* One-time insert:
* If Square or another mapped pricebook entry does not exist yet,
* create it from Shopify once.
*/
                    pbesToInsert.add(new PricebookEntry(
                        Pricebook2Id = incoming.Pricebook2Id,
                        Product2Id = incoming.Product2Id,
                        UnitPrice = incoming.UnitPrice,
                        IsActive = true,
                        UseStandardPrice = false
                    ));
                }
            }
            
            if (!pbesToInsert.isEmpty()) {
                Database.insert(pbesToInsert, false);
            }
            
            if (!pbesToUpdate.isEmpty()) {
                Database.update(pbesToUpdate, false);
            }
        }
        // After Product upsert, sync inbound Shopify images as Salesforce Files
        for (Map<String, Object> inboundProduct : inboundProductsForFileSync) {
            syncInboundShopifyFiles(inboundProduct);
        }
        
        // Square Product Sync - use saved Shopify Variant IDs only
        
        if (!successfulVariantShopIds.isEmpty()) {
            SquareCatalogScheduler.scheduleSync(successfulVariantShopIds);
        }
        
        if (!successfulVariantShopIds.isEmpty()) {
            if (System.isFuture() || System.isBatch()) {
                System.debug(
                    LoggingLevel.INFO,
                    'Skipping direct Shopify inventory pull because product sync already performed DML. ' +
                    'Inventory will be handled by Shopify inventory_level webhook. successfulVariantShopIds=' +
                    successfulVariantShopIds
                );
            } else {
                ShopifyInventoryPullService.pullInventoryForVariantShopIdsAsync(
                    new List<String>(successfulVariantShopIds)
                );
            }
        }
    }  // this closes processProductsFromRestRequest
    
    public static Map<String, List<SObject>> processSingleProduct(
        Map<String, Object> payload,
        Map<String, List<REST_Field_Mapping__mdt>>
        fieldMappingsGroupedByTopic,
        List<Id> inboundPricebookIds,
        Map<String, Id> recordTypeIds
    ) {
        Map<String, List<SObject>> objectRecordsMap =
            new Map<String, List<SObject>>{
                'Product' => new List<SObject>(),
                    'Variant' => new List<SObject>(),
                    'Topic' => new List<SObject>(),
                    'PricebookEntry' => new List<SObject>()
                    };
                        
                        if (payload == null) {
                            return objectRecordsMap;
                        }
        
        String incomingShopifyProductId =
            payload.get('id') == null
            ? null
            : String.valueOf(payload.get('id'));
        
        String shopifyProductTitle =
            payload.get('title') == null
            ? null
            : String.valueOf(payload.get('title'));
        
        String sfParentProductName =
            getSfParentProductNameFromPayload(payload);
        
        /*
* Parent Product naming rule:
*
* The Salesforce parent Product Name must come ONLY from the Shopify
* SF Parent Product Name metafield.
*
* Do not derive or overwrite the Salesforce parent Product Name from
* the Shopify product title or from a normalized Shopify title.
*
* If the Shopify SF Parent Product Name metafield is blank, this logic
* does not explicitly change the Salesforce parent Product Name.
*/
        String requestedParentName =
            !String.isBlank(sfParentProductName)
            ? sfParentProductName.trim()
            : null;
        
        Product2 existingCanonicalParent =
            findExistingCanonicalParent(
                requestedParentName,
                shopifyProductTitle,
                payload.get('product_type') == null
                ? null
                : String.valueOf(payload.get('product_type'))
            );
        
        Product2 productReference;
        
        if (existingCanonicalParent != null) {
            productReference = new Product2(
                Id = existingCanonicalParent.Id
            );
        } else {
            productReference = new Product2(
                Shop_ID__c = incomingShopifyProductId
            );
        }
        
        Product2 primaryProductRecord;
        
        /*
* Main Product
*/
        if (
            fieldMappingsGroupedByTopic != null &&
            fieldMappingsGroupedByTopic.containsKey('products')
        ) {
            SObject newProductRecordSobject =
                Utilities.doGenericMapping(
                    'Product2',
                    payload,
                    fieldMappingsGroupedByTopic.get('products')
                );
            
            primaryProductRecord =
                (Product2) newProductRecordSobject;
            
            primaryProductRecord.Type__c = 'Product';
            primaryProductRecord.RecordTypeId =
                recordTypeIds.get('Product');
            
            /*
* When a canonical parent already exists, update that record instead
* of creating another Salesforce parent Product.
*/
            if (existingCanonicalParent != null) {
                primaryProductRecord.Id =
                    existingCanonicalParent.Id;
                
                /*
* Preserve the original Shopify Product ID belonging to the
* existing Salesforce parent. Do not replace it with the new
* Silver/Gold Shopify product ID.
*/
                primaryProductRecord.Shop_ID__c =
                    existingCanonicalParent.Shop_ID__c;
                
                /*
* Preserve the existing shortened SKU.
*/
                primaryProductRecord.StockKeepingUnit =
                    existingCanonicalParent.StockKeepingUnit;
            }
            
            /*
* Use the explicit Shopify SF Parent Product Name metafield as the
* canonical Salesforce parent name.
*
* If the metafield is blank, do not explicitly update the parent
* Product Name from the Shopify product title or a normalized title.
*/
            if (!String.isBlank(requestedParentName)) {
                primaryProductRecord.Name =
                    requestedParentName;
            }
            
            setProductFieldIfPresent(
                primaryProductRecord,
                'SF_Parent_Product_Name__c',
                requestedParentName
            );
            
            /*
* Keep primary image URL for compatibility and thumbnail usage.
*/
            if (
                payload.containsKey('image') &&
                payload.get('image') != null
            ) {
                Map<String, Object> imageMap =
                    (Map<String, Object>) payload.get('image');
                
                if (
                    imageMap.containsKey('src') &&
                    imageMap.get('src') != null
                ) {
                    primaryProductRecord.Image_URL__c =
                        String.valueOf(imageMap.get('src'));
                }
            }
            
            doNuancedMapping(
                primaryProductRecord,
                payload
            );
            
            objectRecordsMap.get('Product').add(
                primaryProductRecord
            );
            
            if (
                payload.containsKey('tags') &&
                payload.get('tags') != null
            ) {
                String tags = String.valueOf(
                    payload.get('tags')
                );
                
                if (!String.isBlank(tags)) {
                    List<String> tagList = tags.split(', ');
                    
                    Custom_Topic__c thisCustomTop =
                        new Custom_Topic__c(
                            External_Id__c =
                            incomingShopifyProductId,
                            Product__r =
                            productReference
                        );
                    
                    extIdTagMap.put(
                        incomingShopifyProductId,
                        tagList
                    );
                    
                    objectRecordsMap.get('Topic').add(
                        thisCustomTop
                    );
                }
            }
        }
        
        /*
* Map image ID to image URL for variants.
*/
        Map<String, String> imageIdToSrcMap =
            new Map<String, String>();
        
        if (
            payload.containsKey('images') &&
            payload.get('images') != null
        ) {
            List<Object> images =
                (List<Object>) payload.get('images');
            
            if (images != null) {
                for (Object image : images) {
                    Map<String, Object> imageMap =
                        (Map<String, Object>) image;
                    
                    if (
                        imageMap != null &&
                        imageMap.get('id') != null &&
                        imageMap.get('src') != null
                    ) {
                        imageIdToSrcMap.put(
                            String.valueOf(imageMap.get('id')),
                            String.valueOf(imageMap.get('src'))
                        );
                    }
                }
            }
        }
        
        /*
* Variants
*/
        if (
            payload.containsKey('variants') &&
            fieldMappingsGroupedByTopic != null &&
            fieldMappingsGroupedByTopic.containsKey('variants')
        ) {
            List<Object> variants =
                (List<Object>) payload.get('variants');
            
            if (variants != null) {
                for (Object variant : variants) {
                    Map<String, Object> variantMap =
                        (Map<String, Object>) variant;
                    
                    if (variantMap == null) {
                        continue;
                    }
                    
                    // ─────────────────────────────────────────────────────────────────────────
                    // Shopify Inventory Policy normalization
                    // ─────────────────────────────────────────────────────────────────────────
                    //
                    // Shopify REST payload:
                    //     continue / deny
                    //
                    // Shopify GraphQL payload:
                    //     CONTINUE / DENY
                    //
                    // Salesforce restricted picklist API values:
                    //     continue / deny
                    //
                    // Normalize the value BEFORE generic metadata mapping so the
                    // REST_Field_Mapping__mdt record can safely map it to
                    // Product2.Inventory_Policy__c.
                    // ─────────────────────────────────────────────────────────────────────────
                    
                    if (
                        variantMap.containsKey('inventory_policy') &&
                        variantMap.get('inventory_policy') != null
                    ) {
                        String inventoryPolicy =
                            String.valueOf(
                                variantMap.get('inventory_policy')
                            ).trim().toLowerCase();
                        
                        if (
                            inventoryPolicy == 'continue' ||
                            inventoryPolicy == 'deny'
                        ) {
                            variantMap.put(
                                'inventory_policy',
                                inventoryPolicy
                            );
                        } else {
                            // Do not pass an unsupported value into the restricted
                            // Salesforce picklist.
                            variantMap.remove('inventory_policy');
                        }
                    }
                    
                    SObject newVariantRecordSobject =
                        Utilities.doGenericMapping(
                            'Product2',
                            variantMap,
                            fieldMappingsGroupedByTopic.get(
                                'variants'
                            )
                        );
                    
                    Product2 thisVariant =
                        (Product2) newVariantRecordSobject;
                    
                    thisVariant.Type__c = 'Variant';
                    thisVariant.RecordTypeId =
                        recordTypeIds.get('Variant');
                    
                    /*
* Parent assignment:
*
* Existing canonical parent:
*   Assign Parent__c directly.
*
* New parent:
*   Assign Parent__r using Shopify external ID because the
*   parent is inserted before the variants.
*/
                    if (existingCanonicalParent != null) {
                        thisVariant.Parent__c =
                            existingCanonicalParent.Id;
                    } else {
                        thisVariant.Parent__r =
                            productReference;
                    }
                    
                    /*
* Populate the field on the variant so ProductSkuService can
* also use it when building its style key.
*/
                    setProductFieldIfPresent(
                        thisVariant,
                        'SF_Parent_Product_Name__c',
                        requestedParentName
                    );
                    
                    if (
                        variantMap.containsKey(
                            'inventory_item_id'
                        ) &&
                        variantMap.get(
                            'inventory_item_id'
                        ) != null
                    ) {
                        thisVariant.Inventory_Item_Id__c =
                            String.valueOf(
                                variantMap.get(
                                    'inventory_item_id'
                                )
                            );
                    }
                    
                    if (primaryProductRecord != null) {
                        thisVariant.Family =
                            primaryProductRecord.Family;
                    }
                    
                    /*
* Shopify weight mapping.
*/
                    if (
                        variantMap.containsKey('weight') &&
                        variantMap.get('weight') != null
                    ) {
                        try {
                            Decimal rawWeight =
                                Decimal.valueOf(
                                    String.valueOf(
                                        variantMap.get('weight')
                                    )
                                );
                            
                            String weightUnit =
                                variantMap.containsKey(
                                    'weight_unit'
                                )
                                ? String.valueOf(
                                    variantMap.get(
                                        'weight_unit'
                                    )
                                ).toLowerCase()
                                : 'g';
                            
                            Decimal gramsValue = rawWeight;
                            
                            if (weightUnit == 'kg') {
                                gramsValue =
                                    rawWeight * 1000;
                            } else if (
                                weightUnit == 'lb' ||
                                weightUnit == 'lbs'
                            ) {
                                gramsValue =
                                    rawWeight * 453.592;
                            } else if (
                                weightUnit == 'oz'
                            ) {
                                gramsValue =
                                    rawWeight * 28.3495;
                            }
                            
                            setProductFieldIfPresent(
                                thisVariant,
                                'Weight__c',
                                gramsValue.setScale(3)
                            );
                            
                            setProductFieldIfPresent(
                                thisVariant,
                                'Weight_Unit__c',
                                normalizeWeightUnitForSalesforce(
                                    weightUnit
                                )
                            );
                        } catch (Exception e) {
                            System.debug(
                                LoggingLevel.WARN,
                                'ProductOrchestrationService.processSingleProduct: ' +
                                'Weight mapping failed for Shopify variant ' +
                                String.valueOf(
                                    variantMap.get('id')
                                ) +
                                '. Error=' +
                                e.getMessage()
                            );
                        }
                    }
                    
                    /*
                     * Material mapping.
                     *
                     * Salesforce Material__c is a multi-select picklist, so all
                     * Shopify jewelry-material references are mapped and stored.
                     *
                     * The first successfully mapped material remains the primary
                     * material used by the existing variant naming logic. SKU
                     * generation continues to use the first semicolon-delimited
                     * Material__c value inside ProductSkuService.getMaterialCode().
                     */
                    List<String> shopifyMaterials =
                        ProductSkuService.deriveMaterialsFromShopifyPayload(
                            payload
                        );

                    List<String> salesforceMaterials =
                        normalizeMaterialsForSalesforce(
                            shopifyMaterials
                        );

                    String normalizedMaterial =
                        salesforceMaterials.isEmpty()
                        ? null
                        : salesforceMaterials[0];
                    
                    System.debug(
                        LoggingLevel.INFO,
                        'MATERIAL NORMALIZATION'
                        + ' | SHOPIFY_MATERIALS=' + shopifyMaterials
                        + ' | SALESFORCE_MATERIALS=' + salesforceMaterials
                        + ' | PRIMARY_MATERIAL=' + normalizedMaterial
                    );
                    
                    if (!String.isBlank(normalizedMaterial)) {
                        setProductFieldIfPresent(
                            thisVariant,
                            'Material__c',
                            normalizedMaterial
                        );
                    }
                    
                    String shopifyVariantTitle =
                        variantMap.get('title') == null
                        ? null
                        : String.valueOf(
                            variantMap.get('title')
                        );
                    
                    String variantSize =
                        getVariantSizeValue(variantMap);
                    
                    if (!String.isBlank(variantSize)) {
                        setProductFieldIfPresent(
                            thisVariant,
                            'Size__c',
                            variantSize
                        );
                    }
                    
                    Boolean isDefaultVariant =
                        String.isBlank(
                            shopifyVariantTitle
                        ) ||
                        shopifyVariantTitle.equalsIgnoreCase(
                            'Default Title'
                        );
                    
                    if (!String.isBlank(variantSize)) {
                        thisVariant.Name =
                            shopifyProductTitle +
                            ' size ' +
                            variantSize;
                    } else if (isDefaultVariant) {
                        thisVariant.Name =
                            shopifyProductTitle;
                    } else {
                        thisVariant.Name =
                            shopifyProductTitle +
                            ' - ' +
                            shopifyVariantTitle;
                    }
                    
                    /*
* Final variant naming rule.
*/
                    String sizeValue =
                        getSelectedOptionValue(
                            variantMap,
                            'Ring size'
                        );
                    
                    if (String.isBlank(sizeValue)) {
                        sizeValue =
                            getSelectedOptionValue(
                                variantMap,
                                'Size'
                            );
                    }
                    
                    if (
                        String.isBlank(sizeValue) &&
                        !String.isBlank(
                            shopifyVariantTitle
                        )
                    ) {
                        sizeValue =
                            shopifyVariantTitle;
                    }
                    
                    if (
                        !String.isBlank(shopifyProductTitle) &&
                        !String.isBlank(normalizedMaterial) &&
                        !String.isBlank(sizeValue) &&
                        !sizeValue.equalsIgnoreCase(
                            'Default Title'
                        )
                    ) {
                        thisVariant.Name =
                            shopifyProductTitle +
                            ' - ' +
                            normalizedMaterial +
                            ' "' +
                            sizeValue +
                            '"';
                    } else if (
                        !String.isBlank(
                            shopifyProductTitle
                        ) &&
                        !String.isBlank(
                            shopifyVariantTitle
                        ) &&
                        !shopifyVariantTitle
                        .equalsIgnoreCase(
                            'Default Title'
                        )
                    ) {
                        thisVariant.Name =
                            shopifyProductTitle +
                            ' - ' +
                            shopifyVariantTitle;
                    } else if (
                        !String.isBlank(
                            shopifyProductTitle
                        )
                    ) {
                        thisVariant.Name =
                            shopifyProductTitle;
                    }
                    
                    if (
                        variantMap.containsKey(
                            'image_id'
                        ) &&
                        variantMap.get(
                            'image_id'
                        ) != null
                    ) {
                        String imageId =
                            String.valueOf(
                                variantMap.get(
                                    'image_id'
                                )
                            );
                        
                        if (
                            imageIdToSrcMap.containsKey(
                                imageId
                            )
                        ) {
                            thisVariant.Image_URL__c =
                                imageIdToSrcMap.get(
                                    imageId
                                );
                        }
                    }
                    
                    thisVariant.Updated_by_Integration__c =
                        true;
                    
                    objectRecordsMap.get('Variant').add(
                        thisVariant
                    );
                    
                    Decimal variantPrice = 0;
                    
                    if (
                        variantMap.containsKey('price') &&
                        variantMap.get('price') != null
                    ) {
                        variantPrice =
                            Decimal.valueOf(
                                String.valueOf(
                                    variantMap.get('price')
                                )
                            );
                    }
                    
                    for (
                        Id pricebookId :
                        inboundPricebookIds
                    ) {
                        PricebookEntry pbe =
                            new PricebookEntry();
                        
                        pbe.Pricebook2Id =
                            pricebookId;
                        
                        pbe.UnitPrice =
                            variantPrice;
                        
                        pbe.IsActive = true;
                        pbe.UseStandardPrice = false;
                        
                        objectRecordsMap
                            .get('PricebookEntry')
                            .add(pbe);
                    }
                }
            }
        }
        
        return objectRecordsMap;
    }
    
    @TestVisible
    private static String getSfParentProductNameFromPayload(
        Map<String, Object> payload
    ) {
        if (payload == null) {
            return null;
        }
        
        /*
* Preferred value added by
* buildRestLikeProductPayloadFromGraphQL.
*/
        Object directValue =
            payload.get('sf_parent_product_name');
        
        if (directValue != null) {
            String value =
                String.valueOf(directValue);
            
            if (!String.isBlank(value)) {
                return value.trim();
            }
        }
        
        /*
* Fallback for REST payloads where the value is available only
* inside the metafields collection.
*/
        Object metafieldsObject =
            payload.get('metafields');
        
        if (!(metafieldsObject instanceof List<Object>)) {
            return null;
        }
        
        for (
            Object metafieldObject :
            (List<Object>) metafieldsObject
        ) {
            if (
                !(metafieldObject
                  instanceof Map<String, Object>)
            ) {
                continue;
            }
            
            Map<String, Object> metafield =
                (Map<String, Object>) metafieldObject;
            
            String namespaceValue =
                metafield.get('namespace') == null
                ? null
                : String.valueOf(
                    metafield.get('namespace')
                );
            
            String keyValue =
                metafield.get('key') == null
                ? null
                : String.valueOf(
                    metafield.get('key')
                );
            
            if (
                namespaceValue != 'custom' ||
                keyValue != 'sf_product_name'
            ) {
                continue;
            }
            
            Object rawValue =
                metafield.get('value');
            
            if (rawValue == null) {
                continue;
            }
            
            String value =
                String.valueOf(rawValue);
            
            if (!String.isBlank(value)) {
                return value.trim();
            }
        }
        
        return null;
    }
    
    @TestVisible
    private static Product2 findExistingCanonicalParent(
        String requestedParentName,
        String incomingProductTitle,
        String incomingFamily
    ) {
        if (
            String.isBlank(requestedParentName) &&
            String.isBlank(incomingProductTitle)
        ) {
            return null;
        }
        
        String requestedNormalized =
            normalizeParentProductName(
                !String.isBlank(requestedParentName)
                ? requestedParentName
                : incomingProductTitle
            );
        
        if (String.isBlank(requestedNormalized)) {
            return null;
        }
        
        Map<String, Schema.SObjectField> fieldMap =
            Product2.SObjectType
            .getDescribe()
            .fields
            .getMap();
        
        List<String> selectFields =
            new List<String>{
                'Id',
                    'Name',
                    'Shop_ID__c',
                    'StockKeepingUnit',
                    'Family',
                    'CreatedDate'
                    };
                        
                        Boolean hasSfParentNameField =
                        fieldMap.containsKey(
                            'SF_Parent_Product_Name__c'
                        );
        
        if (hasSfParentNameField) {
            selectFields.add(
                'SF_Parent_Product_Name__c'
            );
        }
        
        String queryText =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Product2 ' +
            'WHERE Type__c = \'Product\' ';
        
        if (!String.isBlank(incomingFamily)) {
            queryText +=
                'AND Family = :incomingFamily ';
        }
        
        queryText +=
            'ORDER BY CreatedDate ASC ' +
            'LIMIT 2000';
        
        List<Product2> candidates =
            Database.query(queryText);
        
        Product2 normalizedMatch;
        Product2 normalizedMatchWithSku;
        
        for (Product2 candidate : candidates) {
            if (candidate == null) {
                continue;
            }
            
            /*
* Priority 1: exact Product Name.
*/
            if (
                !String.isBlank(candidate.Name) &&
                candidate.Name.trim()
                .equalsIgnoreCase(
                    requestedParentName
                )
            ) {
                return candidate;
            }
            
            /*
* Priority 2: exact SF Parent Product Name field.
*/
            if (hasSfParentNameField) {
                String existingSfParentName =
                    getProductStringField(
                        candidate,
                        'SF_Parent_Product_Name__c'
                    );
                
                if (
                    !String.isBlank(
                        existingSfParentName
                    ) &&
                    existingSfParentName.trim()
                    .equalsIgnoreCase(
                        requestedParentName
                    )
                ) {
                    return candidate;
                }
            }
            
            /*
* Priority 3: normalized design-name match.
*
* Useless Ring Gold   -> useless ring
* Useless Ring Silver -> useless ring
*/
            String candidateNormalized =
                normalizeParentProductName(
                    candidate.Name
                );
            
            String sfParentNormalized;
            
            if (hasSfParentNameField) {
                sfParentNormalized =
                    normalizeParentProductName(
                        getProductStringField(
                            candidate,
                            'SF_Parent_Product_Name__c'
                        )
                    );
            }
            
            Boolean matchesNormalizedName =
                candidateNormalized ==
                requestedNormalized ||
                (
                    !String.isBlank(
                        sfParentNormalized
                    ) &&
                    sfParentNormalized ==
                    requestedNormalized
                );
            
            if (!matchesNormalizedName) {
                continue;
            }
            
            if (
                !String.isBlank(
                    candidate.StockKeepingUnit
                )
            ) {
                normalizedMatchWithSku =
                    candidate;
                break;
            }
            
            if (normalizedMatch == null) {
                normalizedMatch =
                    candidate;
            }
        }
        
        /*
* Prefer the parent that already has a shortened SKU because it is
* already the source of truth for the shared style number.
*/
        if (normalizedMatchWithSku != null) {
            return normalizedMatchWithSku;
        }
        
        return normalizedMatch;
    }
    
    @TestVisible
    private static String normalizeParentProductName(
        String rawName
    ) {
        if (String.isBlank(rawName)) {
            return null;
        }
        
        String normalized =
            rawName.trim().toLowerCase();
        
        normalized =
            normalized.replace('-', ' ');
        
        normalized =
            normalized.replace('_', ' ');
        
        /*
* Remove material descriptions so differently coloured Shopify
* products resolve to the same Salesforce design.
*/
        normalized =
            normalized.replaceAll(
                '(?i)\\b14k\\s+gold[- ]?plated\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\b18k\\s+gold[- ]?plated\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\bgold[- ]?plated\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\bsilver[- ]?plated\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\brose\\s+gold[- ]?plated\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\bwhite\\s+gold\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\bsolid\\s+gold\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\bsterling\\s+silver\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\bgold\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\bsilver\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\brhodium\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '(?i)\\bmaterial\\b',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '[^a-z0-9 ]',
                ' '
            );
        
        normalized =
            normalized.replaceAll(
                '\\s+',
                ' '
            );
        
        return normalized.trim();
    }
    
    private static String getProductStringField(
        Product2 productRecord,
        String fieldApiName
    ) {
        if (
            productRecord == null ||
            String.isBlank(fieldApiName)
        ) {
            return null;
        }
        
        Map<String, Schema.SObjectField> fieldMap =
            Product2.SObjectType
            .getDescribe()
            .fields
            .getMap();
        
        if (!fieldMap.containsKey(fieldApiName)) {
            return null;
        }
        
        try {
            Object value =
                productRecord.get(fieldApiName);
            
            if (value == null) {
                return null;
            }
            
            String stringValue =
                String.valueOf(value);
            
            return String.isBlank(stringValue)
                ? null
                : stringValue;
        } catch (SObjectException e) {
            return null;
        }
    }
    
    private static void setProductFieldIfPresent(
        Product2 productRecord,
        String fieldApiName,
        Object value
    ) {
        if (
            productRecord == null ||
            String.isBlank(fieldApiName) ||
            value == null
        ) {
            return;
        }
        
        Map<String, Schema.SObjectField> fieldMap =
            Product2.SObjectType
            .getDescribe()
            .fields
            .getMap();
        
        if (fieldMap.containsKey(fieldApiName)) {
            productRecord.put(
                fieldApiName,
                value
            );
        }
    }
    
    public static void doNuancedMapping(Product2 thisProduct, Map<String, Object> payload) {
        if (thisProduct != null && payload != null) {
            String productType = (String) payload.get('product_type');
            
            Set<String> earringsTypes = new Set<String>{ 'Dangles', 'Earrings', 'Hoops', 'Studs' };
                
                if (earringsTypes.contains(productType)) {
                    thisProduct.Family = 'Earrings';
                } else {
                    thisProduct.Family = productType;
                }
            
            String status = (String) payload.get('status');
            if (status != null && status.equalsIgnoreCase('active')) {
                thisProduct.IsActive = true;
            } else {
                thisProduct.IsActive = false;
            }
            
            thisProduct.Updated_by_Integration__c = true;
        }
    }
    
    @TestVisible
    private static String getVariantSizeValue(Map<String, Object> variantMap) {
        if (variantMap == null) {
            return null;
        }
        
        List<String> sizeOptionNames = new List<String>{
            'Ring size',
                'Ring Size',
                'Size',
                'Length',
                'Chain length',
                'Chain Length'
                };
                    
                    for (String optionName : sizeOptionNames) {
                        String optionValue = getSelectedOptionValue(variantMap, optionName);
                        
                        if (
                            !String.isBlank(optionValue) &&
                            !optionValue.equalsIgnoreCase('Default Title')
                        ) {
                            return optionValue;
                        }
                    }
        
        String variantTitle = String.valueOf(variantMap.get('title'));
        
        if (
            !String.isBlank(variantTitle) &&
            !variantTitle.equalsIgnoreCase('Default Title')
        ) {
            return variantTitle;
        }
        
        return null;
    }
    
    @TestVisible 
    private static String getSelectedOptionValue(
        Map<String, Object> variantMap,
        String optionName
    ) {
        if (variantMap == null || String.isBlank(optionName)) {
            return null;
        }
        
        Object selectedOptionsObj = variantMap.get('selected_options');
        
        if (!(selectedOptionsObj instanceof List<Object>)) {
            return null;
        }
        
        for (Object optionObj : (List<Object>) selectedOptionsObj) {
            if (!(optionObj instanceof Map<String, Object>)) {
                continue;
            }
            
            Map<String, Object> optionMap =
                (Map<String, Object>) optionObj;
            
            String name = String.valueOf(optionMap.get('name'));
            String value = String.valueOf(optionMap.get('value'));
            
            if (
                !String.isBlank(name) &&
                name.equalsIgnoreCase(optionName) &&
                !String.isBlank(value) &&
                !value.equalsIgnoreCase('Default Title')
            ) {
                return value;
            }
        }
        
        return null;
    }
    
    //Pricebook sync logic Shopify > Salesforce
    @Testvisible
    private static Map<String, PricebookEntry> getExistingPricebookEntries(
        Set<Id> productIds,
        Set<Id> pricebookIds
    ) {
        
        Map<String, PricebookEntry> result = new Map<String, PricebookEntry>();
        
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, Pricebook2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
            AND Pricebook2Id IN :pricebookIds
            AND IsActive = true
        ]) {
            
            String key = pbe.Product2Id + '-' + pbe.Pricebook2Id;
            result.put(key, pbe);
        }
        
        return result;
    }
    
    @Testvisible
    private static void syncInboundShopifyFiles(Map<String, Object> payload) {
        if (payload == null || payload.get('id') == null) {
            return;
        }
        
        String shopId = String.valueOf(payload.get('id'));
        
        List<Product2> products = [
            SELECT Id, Name, Shop_ID__c
            FROM Product2
            WHERE Shop_ID__c = :shopId
            LIMIT 1
        ];
        
        if (!products.isEmpty()) {
            ShopifyProductImageSyncService.enqueueInboundShopifyImages(products[0].Id, payload);
        }
    }
    
    @TestVisible
    private static String normalizeWeightUnitForSalesforce(String rawWeightUnit) {
        if (String.isBlank(rawWeightUnit)) {
            return 'g';
        }
        
        String unitValue = rawWeightUnit.trim().toLowerCase();
        
        if (unitValue == 'pounds' || unitValue == 'pound' || unitValue == 'lbs') {
            return 'lb';
        }
        
        if (unitValue == 'ounces' || unitValue == 'ounce') {
            return 'oz';
        }
        
        if (unitValue == 'kilograms' || unitValue == 'kilogram') {
            return 'kg';
        }
        
        if (unitValue == 'grams' || unitValue == 'gram') {
            return 'g';
        }
        
        return unitValue;
    }
    
    /**
     * Maps Shopify material labels to the exact active Salesforce picklist values.
     *
     * Material__c is a restricted multi-select picklist. Incoming labels may vary
     * only by case, spaces, hyphens, or underscores (for example Gold Plated vs
     * Gold plated). We compare normalized keys but always write Salesforce's exact
     * configured value.
     *
     * Unmapped values are logged and omitted so one unknown Shopify material does
     * not make the entire Product2 variant fail DML.
     */
    @TestVisible
    private static List<String> normalizeMaterialsForSalesforce(
        List<String> incomingMaterials
    ) {
        List<String> result = new List<String>();

        if (incomingMaterials == null || incomingMaterials.isEmpty()) {
            return result;
        }

        Schema.DescribeFieldResult fieldDescribe =
            Product2.Material__c.getDescribe();

        Map<String, String> salesforceValueByKey =
            new Map<String, String>();

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }

            String salesforceValue = entry.getValue();
            String key = normalizeMaterialKey(salesforceValue);

            if (!String.isBlank(key)) {
                salesforceValueByKey.put(key, salesforceValue);
            }
        }

        for (String incomingMaterial : incomingMaterials) {
            if (String.isBlank(incomingMaterial)) {
                continue;
            }

            String incomingKey = normalizeMaterialKey(incomingMaterial);

            if (salesforceValueByKey.containsKey(incomingKey)) {
                String exactSalesforceValue =
                    salesforceValueByKey.get(incomingKey);

                if (!result.contains(exactSalesforceValue)) {
                    result.add(exactSalesforceValue);
                }
            } else {
                System.debug(
                    LoggingLevel.ERROR,
                    'UNMAPPED SHOPIFY MATERIAL'
                    + ' | INCOMING=' + incomingMaterial
                );
            }
        }

        return result;
    }

    @TestVisible
    private static String normalizeMaterialKey(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        return value
            .trim()
            .toLowerCase()
            .replace(' ', '')
            .replace('-', '')
            .replace('_', '');
    }

    public static void backfillInventoryItemIdsFromProductWebhook(Map<String, Object> productPayload) {
    }
}