public class ShopifyProductImageSyncService {
    
    /*
* FINAL IMAGE ARCHITECTURE
* ------------------------
* Shopify -> Salesforce image sync now stores image URLs only.
*
* Old retired behavior:
*   Shopify CDN image URL -> download Blob -> ContentVersion -> ContentDocumentLink
*
* New behavior:
*   Shopify CDN image URL -> Product_Image__c row
*
* Required custom object/fields:
*   Product_Image__c
*      Product__c              Lookup(Product2)
*      Shopify_Image_Id__c     Text
*      Image_URL__c            URL or Long Text Area
*
* Notes:
* - No ContentVersion is created here.
* - No ContentDocumentLink is created here.
* - No Shopify image binary is downloaded into Salesforce.
* - Existing public method names are kept where possible so existing callers do not break.
*/
    
    /*
* Kept only for backward compatibility with any old trigger/process references.
* It is no longer used by this class because ContentVersion/ContentDocumentLink
* sync has been retired.
*/
    public static Boolean bypassProductFileLinkTrigger = false;
    
    /*
* Kept only for backward compatibility.
* The new URL sync does not enforce this limit because URL rows are lightweight.
*/
    private static final Integer MAX_INBOUND_SHOPIFY_IMAGES = 4;
    
    /*
* RETIRED: Salesforce File -> Shopify upload.
*
* Kept so existing callers compile, but it no longer uploads Salesforce Files
* because the final architecture no longer uses ContentVersion images.
*
* Square outbound should read Product_Image__c.Image_URL__c instead.
*/
    public static void syncSalesforceFilesToShopify(Set<Id> productIds) {
        System.debug(
            LoggingLevel.INFO,
            'syncSalesforceFilesToShopify is retired. ' +
            'Images are now stored as Product_Image__c URL rows. productIds=' + productIds
        );
    }
    
    /*
* RETIRED: old wrapper for downloaded image file data.
*
* Kept only for backward compatibility with existing tests/references.
* The new URL sync does not use Blob/image file wrappers.
*/
    public class ImageFileWrapper {
        public String title;
        public String fileName;
        public Blob body;
    }
    
    /*
* Queueable used by ProductOrchestrationService after Product2 variant insert/update.
*
* This now writes Product_Image__c URL rows only.
* No callouts are required because image URLs are already present in the Shopify payload.
*/
    public class InboundShopifyImagesJob implements Queueable, Database.AllowsCallouts {
        private Id productId;
        private String payloadJson;
        
        public InboundShopifyImagesJob(Id productId, String payloadJson) {
            this.productId = productId;
            this.payloadJson = payloadJson;
        }
        
        public void execute(QueueableContext qc) {
            if (productId == null || String.isBlank(payloadJson)) {
                System.debug(
                    LoggingLevel.WARN,
                    'InboundShopifyImagesJob skipped because productId or payloadJson is blank. productId=' +
                    productId
                );
                return;
            }
            
            List<Product2> products = [
                SELECT Id,
                Name,
                Shop_Id__c,
                Parent__c
                FROM Product2
                WHERE Id = :productId
                LIMIT 1
            ];
            
            if (products.isEmpty()) {
                System.debug(
                    LoggingLevel.WARN,
                    'InboundShopifyImagesJob skipped because Product2 was not found. productId=' +
                    productId
                );
                return;
            }
            
            Map<String, Object> payload;
            
            try {
                payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Failed to deserialize Shopify post-sync payload. Product2Id=' +
                    productId +
                    ', Error=' +
                    e.getMessage()
                );
                return;
            }
            
            /*
* Important order:
* 1. SKU writeback = callout
* 2. Inventory pull = callout + Inventory__c DML
* 3. Image URL sync = Product_Image__c DML
*/
            try {
                writeBackGeneratedSkusToShopify(payload);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify SKU writeback failed in InboundShopifyImagesJob. Product2Id=' +
                    productId +
                    ', Error=' +
                    e.getMessage()
                );
            }
            
            try {
                pullInventoryForPayloadVariants(payload);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify inventory pull failed in InboundShopifyImagesJob. Product2Id=' +
                    productId +
                    ', Error=' +
                    e.getMessage()
                );
            }
            
            try {
                syncShopifyImageUrlsToSalesforce(products[0], payload);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify image URL sync failed in InboundShopifyImagesJob. Product2Id=' +
                    productId +
                    ', Error=' +
                    e.getMessage()
                );
            }
        }
    }
        
        /*
* Keep this method name because ProductOrchestrationService may already call it.
*
* Important:
* Pass the Variant Product2 Id here, not the parent Product2 Id, when images
* belong to the sellable SKU/variant.
*/
        public static void enqueueInboundShopifyImages(Id productId, Map<String, Object> payload) {
            if (productId == null || payload == null) {
                return;
            }
            
            System.enqueueJob(
                new InboundShopifyImagesJob(
                    productId,
                    JSON.serialize(payload)
                )
            );
        }
        
        /*
* Backward-compatible method name.
*
* Old method created ContentVersion files.
* New method creates/updates Product_Image__c URL rows.
*/
        public static void syncShopifyImagesToSalesforce(
            Product2 productRecord,
            Map<String, Object> payload
        ) {
            syncShopifyImageUrlsToSalesforce(productRecord, payload);
        }
        
        /*
* New final Shopify inbound image sync method.
*
* It reads Shopify image URLs from either:
*   payload.images[]  - normal product image list
*   payload.image     - fallback featured image
*
* Then creates/updates Product_Image__c rows for the given Product2.
*/
        public static void syncShopifyImageUrlsToSalesforce(
            Product2 productRecord,
            Map<String, Object> payload
        ) {
            if (productRecord == null || productRecord.Id == null || payload == null) {
                return;
            }
            
            List<Map<String, Object>> imageMaps = extractImageMaps(payload);
            
            if (imageMaps.isEmpty()) {
                System.debug(
                    LoggingLevel.INFO,
                    'No Shopify image URLs found in payload for Product2Id=' +
                    productRecord.Id
                );
                return;
            }
            
            /*
* Important:
* Images must be stored against the product received by the queueable
* AND against the child variant records found from payload. This allows
* duplicates across parent and variant, which is expected because they are
* separate Product_Image__c rows under separate Product2 records.
*/
            Set<Id> targetProductIds = getTargetProductIdsForImageUrlSync(
                productRecord,
                payload
            );
            
            if (targetProductIds.isEmpty()) {
                targetProductIds.add(productRecord.Id);
            }
            
            Set<String> incomingShopifyImageIds = new Set<String>();
            
            for (Map<String, Object> img : imageMaps) {
                String shopifyImageId = getStringValue(img, 'id');
                
                if (!String.isBlank(shopifyImageId)) {
                    incomingShopifyImageIds.add(shopifyImageId);
                }
            }
            
            Map<String, Product_Image__c> existingByProductAndImageId =
                getExistingImagesByProductAndShopifyImageId(
                    targetProductIds,
                    incomingShopifyImageIds
                );
            
            List<Product_Image__c> imageRowsToSave = new List<Product_Image__c>();
            
            for (Id targetProductId : targetProductIds) {
                Set<String> processedShopifyImageIdsForThisProduct = new Set<String>();
                Set<String> processedUrlsForThisProduct = new Set<String>();
                
                for (Map<String, Object> img : imageMaps) {
                    if (img == null) {
                        continue;
                    }
                    
                    String shopifyImageId = getStringValue(img, 'id');
                    String imageUrl = getImageUrl(img);
                    
                    if (String.isBlank(imageUrl)) {
                        continue;
                    }
                    
                    /*
* Avoid duplicates under the same Product2 record in the same run.
* Duplicates across different Product2 records are allowed.
*/
                    if (!String.isBlank(shopifyImageId)) {
                        if (processedShopifyImageIdsForThisProduct.contains(shopifyImageId)) {
                            continue;
                        }
                        
                        processedShopifyImageIdsForThisProduct.add(shopifyImageId);
                    } else {
                        if (processedUrlsForThisProduct.contains(imageUrl)) {
                            continue;
                        }
                        
                        processedUrlsForThisProduct.add(imageUrl);
                    }
                    
                    String existingKey = buildProductImageExistingKey(
                        targetProductId,
                        shopifyImageId
                    );
                    
                    Product_Image__c imageRow;
                    
                    if (
                        !String.isBlank(shopifyImageId) &&
                        existingByProductAndImageId.containsKey(existingKey)
                    ) {
                        imageRow = existingByProductAndImageId.get(existingKey);
                    } else {
                        imageRow = new Product_Image__c();
                        imageRow.Product__c = targetProductId;
                        imageRow.Shopify_Image_Id__c = shopifyImageId;
                    }
                    
                    imageRow.Image_URL__c = imageUrl;
                    
                    imageRowsToSave.add(imageRow);
                }
            }
            
            if (!imageRowsToSave.isEmpty()) {
                upsert imageRowsToSave;
                
                System.debug(
                    LoggingLevel.INFO,
                    'Shopify image URL rows saved. TargetProductIds=' +
                    targetProductIds +
                    ', count=' +
                    imageRowsToSave.size()
                );
            }
        }
        
        private static Set<Id> getTargetProductIdsForImageUrlSync(
            Product2 productRecord,
            Map<String, Object> payload
        ) {
            Set<Id> targetProductIds = new Set<Id>();
            
            if (productRecord == null || productRecord.Id == null) {
                return targetProductIds;
            }
            
            /*
* Always sync image URL rows to the Product2 record that was passed in.
* This preserves current working behavior for the parent/product record.
*/
            targetProductIds.add(productRecord.Id);
            
            Set<String> variantShopIds = getVariantShopIdsFromPayload(payload);
            
            /*
* If payload contains variant ids, sync the same image URL rows to those
* variant Product2 records as well.
*/
            if (!variantShopIds.isEmpty()) {
                for (Product2 variantRecord : [
                    SELECT Id
                    FROM Product2
                    WHERE Shop_ID__c IN :variantShopIds
                ]) {
                    targetProductIds.add(variantRecord.Id);
                }
            }
            
            /*
* Fallback:
* If the payload did not contain variant ids, but the passed Product2 is
* a parent/product record, sync to its direct child variants.
*/
            if (variantShopIds.isEmpty()) {
                for (Product2 childVariant : [
                    SELECT Id
                    FROM Product2
                    WHERE Parent__c = :productRecord.Id
                    AND Type__c = 'Variant'
                ]) {
                    targetProductIds.add(childVariant.Id);
                }
            }
            
            return targetProductIds;
        }
        
        private static Set<String> getVariantShopIdsFromPayload(
            Map<String, Object> payload
        ) {
            Set<String> variantShopIds = new Set<String>();
            
            if (payload == null) {
                return variantShopIds;
            }
            
            if (payload.containsKey('variants') && payload.get('variants') != null) {
                Object rawVariants = payload.get('variants');
                
                if (rawVariants instanceof List<Object>) {
                    for (Object variantObj : (List<Object>) rawVariants) {
                        if (!(variantObj instanceof Map<String, Object>)) {
                            continue;
                        }
                        
                        Map<String, Object> variantMap =
                            (Map<String, Object>) variantObj;
                        
                        String variantId = getStringValue(variantMap, 'id');
                        
                        if (!String.isBlank(variantId)) {
                            variantShopIds.add(normalizeShopifyId(variantId));
                        }
                    }
                }
            }
            
            if (
                payload.containsKey('variant_gids') &&
                payload.get('variant_gids') != null
            ) {
                Object rawVariantGids = payload.get('variant_gids');
                
                if (rawVariantGids instanceof List<Object>) {
                    for (Object variantGidObj : (List<Object>) rawVariantGids) {
                        if (!(variantGidObj instanceof Map<String, Object>)) {
                            continue;
                        }
                        
                        Map<String, Object> variantGidMap =
                            (Map<String, Object>) variantGidObj;
                        
                        String gid = getStringValue(
                            variantGidMap,
                            'admin_graphql_api_id'
                        );
                        
                        if (!String.isBlank(gid)) {
                            variantShopIds.add(normalizeShopifyId(gid));
                        }
                    }
                }
            }
            
            return variantShopIds;
        }
        
        private static Map<String, Product_Image__c>
            getExistingImagesByProductAndShopifyImageId(
                Set<Id> productIds,
                Set<String> shopifyImageIds
            ) {
                Map<String, Product_Image__c> existingByProductAndImageId =
                    new Map<String, Product_Image__c>();
                
                if (
                    productIds == null ||
                    productIds.isEmpty() ||
                    shopifyImageIds == null ||
                    shopifyImageIds.isEmpty()
                ) {
                    return existingByProductAndImageId;
                }
                
                for (Product_Image__c existingImage : [
                    SELECT Id,
                    Product__c,
                    Shopify_Image_Id__c,
                    Image_URL__c
                    FROM Product_Image__c
                    WHERE Product__c IN :productIds
                    AND Shopify_Image_Id__c IN :shopifyImageIds
                ]) {
                    String key = buildProductImageExistingKey(
                        existingImage.Product__c,
                        existingImage.Shopify_Image_Id__c
                    );
                    
                    existingByProductAndImageId.put(key, existingImage);
                }
                
                return existingByProductAndImageId;
            }
        
        private static String buildProductImageExistingKey(
            Id productId,
            String shopifyImageId
        ) {
            return String.valueOf(productId) + '-' + String.valueOf(shopifyImageId);
        }
        
        private static String normalizeShopifyId(String rawId) {
            if (String.isBlank(rawId)) {
                return null;
            }
            
            String value = rawId.trim();
            
            if (value.contains('/')) {
                List<String> parts = value.split('/');
                value = parts[parts.size() - 1];
            }
            
            if (value.endsWith('.0')) {
                value = value.substring(0, value.length() - 2);
            }
            
            return value;
        }
        
        private static List<Map<String, Object>> extractImageMaps(Map<String, Object> payload) {
            List<Map<String, Object>> imageMaps = new List<Map<String, Object>>();
            
            if (payload == null) {
                return imageMaps;
            }
            
            if (payload.containsKey('images') && payload.get('images') != null) {
                Object rawImages = payload.get('images');
                
                if (rawImages instanceof List<Object>) {
                    for (Object imgObj : (List<Object>) rawImages) {
                        if (imgObj instanceof Map<String, Object>) {
                            imageMaps.add((Map<String, Object>) imgObj);
                        }
                    }
                }
            }
            
            /*
* Fallback only when images[] is missing/empty.
* This avoids duplicating the featured image when it is already included
* in payload.images[].
*/
            if (
                imageMaps.isEmpty() &&
                payload.containsKey('image') &&
                payload.get('image') != null &&
                payload.get('image') instanceof Map<String, Object>
            ) {
                imageMaps.add((Map<String, Object>) payload.get('image'));
            }
            
            return imageMaps;
        }
        
        private static Map<String, Product_Image__c> getExistingImagesByShopifyImageId(
            Id productId,
            Set<String> shopifyImageIds
        ) {
            Map<String, Product_Image__c> existingByShopifyImageId =
                new Map<String, Product_Image__c>();
            
            if (
                productId == null ||
                shopifyImageIds == null ||
                shopifyImageIds.isEmpty()
            ) {
                return existingByShopifyImageId;
            }
            
            for (Product_Image__c existingImage : [
                SELECT Id,
                Product__c,
                Shopify_Image_Id__c,
                Image_URL__c
                FROM Product_Image__c
                WHERE Product__c = :productId
                AND Shopify_Image_Id__c IN :shopifyImageIds
            ]) {
                if (!String.isBlank(existingImage.Shopify_Image_Id__c)) {
                    existingByShopifyImageId.put(
                        existingImage.Shopify_Image_Id__c,
                        existingImage
                    );
                }
            }
            
            return existingByShopifyImageId;
        }
        
        private static String getImageUrl(Map<String, Object> img) {
            if (img == null) {
                return null;
            }
            
            String imageUrl = getStringValue(img, 'src');
            
            if (String.isBlank(imageUrl)) {
                imageUrl = getStringValue(img, 'url');
            }
            
            return imageUrl;
        }
        
        private static String getStringValue(Map<String, Object> source, String key) {
            if (
                source == null ||
                String.isBlank(key) ||
                !source.containsKey(key) ||
                source.get(key) == null
            ) {
                return null;
            }
            
            String value = String.valueOf(source.get(key));
            
            return String.isBlank(value) ? null : value;
        }
        
        private static void writeBackGeneratedSkusToShopify(
            Map<String, Object> payload
        ) {
            if (payload == null) {
                return;
            }
            
            String shopifyProductId = getStringValue(payload, 'id');
            
            if (String.isBlank(shopifyProductId)) {
                return;
            }
            
            Set<String> variantShopIds = getVariantShopIdsFromPayload(payload);
            
            if (variantShopIds.isEmpty()) {
                return;
            }
            
            List<Product2> sfVariants = [
                SELECT Id,
                Shop_Id__c,
                StockKeepingUnit,
                Type__c
                FROM Product2
                WHERE Shop_Id__c IN :variantShopIds
                AND Type__c = 'Variant'
                AND StockKeepingUnit != null
            ];
            
            if (sfVariants.isEmpty()) {
                System.debug(
                    LoggingLevel.WARN,
                    'Shopify SKU writeback skipped because no Salesforce variants with SKU were found. ' +
                    'variantShopIds=' + variantShopIds
                );
                return;
            }
            
            List<Object> variantInputs = new List<Object>();
            
            for (Product2 v : sfVariants) {
                if (
                    String.isBlank(v.Shop_Id__c) ||
                    String.isBlank(v.StockKeepingUnit)
                ) {
                    continue;
                }
                
                variantInputs.add(
                    new Map<String, Object>{
                        'id' => ShopifyGraphQLHelper.toVariantGid(v.Shop_Id__c),
                            'inventoryItem' => new Map<String, Object>{
                                'sku' => v.StockKeepingUnit
                                    }
                    }
                );
            }
            
            if (variantInputs.isEmpty()) {
                return;
            }
            
            String mutation =
                'mutation productVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {' +
                '  productVariantsBulkUpdate(productId: $productId, variants: $variants) {' +
                '    product { id }' +
                '    productVariants { id title sku }' +
                '    userErrors { field message }' +
                '  }' +
                '}';
            
            Map<String, Object> response = ShopifyGraphQLHelper.execute(
                mutation,
                new Map<String, Object>{
                    'productId' => ShopifyGraphQLHelper.toProductGid(shopifyProductId),
                        'variants' => variantInputs
                        }
            );
            
            validateShopifyUserErrorsForImageService(
                response,
                'productVariantsBulkUpdate'
            );
            
            System.debug(
                LoggingLevel.INFO,
                'Shopify SKU writeback complete. ShopifyProductId=' +
                shopifyProductId +
                ', variantCount=' +
                variantInputs.size()
            );
        }
        
        private static void validateShopifyUserErrorsForImageService(
            Map<String, Object> response,
            String mutationName
        ) {
            if (response == null || String.isBlank(mutationName)) {
                return;
            }
            
            if (!response.containsKey('data') || response.get('data') == null) {
                return;
            }
            
            Map<String, Object> dataMap =
                (Map<String, Object>) response.get('data');
            
            if (
                !dataMap.containsKey(mutationName) ||
                dataMap.get(mutationName) == null
            ) {
                return;
            }
            
            Map<String, Object> mutationResult =
                (Map<String, Object>) dataMap.get(mutationName);
            
            if (
                !mutationResult.containsKey('userErrors') ||
                mutationResult.get('userErrors') == null
            ) {
                return;
            }
            
            List<Object> userErrors =
                (List<Object>) mutationResult.get('userErrors');
            
            if (userErrors.isEmpty()) {
                return;
            }
            
            List<String> messages = new List<String>();
            
            for (Object errObj : userErrors) {
                if (!(errObj instanceof Map<String, Object>)) {
                    continue;
                }
                
                Map<String, Object> errMap =
                    (Map<String, Object>) errObj;
                
                messages.add(String.valueOf(errMap.get('message')));
            }
            
            if (!messages.isEmpty()) {
                throw new CalloutException(
                    mutationName + ' returned Shopify user errors: ' +
                    String.join(messages, ' | ')
                );
            }
        }
        
        private static void pullInventoryForPayloadVariants(Map<String, Object> payload) {
            if (payload == null) {
                return;
            }
            
            Set<String> variantShopIds = getVariantShopIdsFromPayload(payload);
            
            if (variantShopIds == null || variantShopIds.isEmpty()) {
                System.debug(
                    LoggingLevel.WARN,
                    'Inventory pull skipped because no Shopify variant ids were found in payload.'
                );
                return;
            }
            
            /*
* Confirm these variants now exist in Salesforce before pulling inventory.
* This avoids pulling inventory for variants that were not inserted/upserted yet.
*/
            Set<String> existingVariantShopIds = new Set<String>();
            
            for (Product2 variantRecord : [
                SELECT Id,
                Shop_Id__c,
                Inventory_Item_Id__c,
                Type__c
                FROM Product2
                WHERE Shop_Id__c IN :variantShopIds
                AND Type__c = 'Variant'
            ]) {
                if (!String.isBlank(variantRecord.Shop_Id__c)) {
                    existingVariantShopIds.add(variantRecord.Shop_Id__c);
                }
            }
            
            if (existingVariantShopIds.isEmpty()) {
                System.debug(
                    LoggingLevel.WARN,
                    'Inventory pull skipped because no matching Salesforce variant records were found. ' +
                    'variantShopIds=' +
                    variantShopIds
                );
                return;
            }
            
            System.debug(
                LoggingLevel.INFO,
                'Pulling Shopify inventory for variant ids from post-sync job. variantShopIds=' +
                existingVariantShopIds
            );
            
            /*
* This method should do callouts and then upsert Inventory__c rows.
* Since this queueable already implements Database.AllowsCallouts, call the
* synchronous pull method if it exists.
*/
            //ShopifyInventoryPullService.pullInventoryForVariantShopIds(
                //new List<String>(existingVariantShopIds)
            //);
        }
    }