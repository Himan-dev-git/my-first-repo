public class SquareCatalogImageQueueable implements Queueable, Database.AllowsCallouts {
    
    private Set<Id> parentProductIds;
    
    public SquareCatalogImageQueueable(Set<Id> parentProductIds) {
        this.parentProductIds = parentProductIds;
    }
    
    public void execute(QueueableContext context) {
        if (parentProductIds == null || parentProductIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'SquareCatalogImageQueueable skipped because parentProductIds is blank.'
            );
            return;
        }
        
        List<Product2> parents = [
            SELECT Id,
            Name,
            Square_Catalog_Item_Id__c
            FROM Product2
            WHERE Id IN :parentProductIds
            AND Square_Catalog_Item_Id__c != null
        ];
        
        if (parents.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'SquareCatalogImageQueueable skipped because no parent products with Square_Catalog_Item_Id__c were found. parentProductIds=' +
                parentProductIds
            );
            return;
        }
        
        Set<Id> validParentProductIds = new Set<Id>();
        
        for (Product2 p : parents) {
            validParentProductIds.add(p.Id);
        }
        
        Map<Id, Product_Image__c> primaryImageByProductId =
            getPrimaryImageUrlByProductId(validParentProductIds);
        
        for (Product2 p : parents) {
            Product_Image__c imageRow = primaryImageByProductId.get(p.Id);
            
            if (imageRow == null || String.isBlank(imageRow.Image_URL__c)) {
                System.debug(
                    LoggingLevel.WARN,
                    'No Product_Image__c image URL found for Square image sync. Product2Id=' +
                    p.Id +
                    ', ProductName=' +
                    p.Name
                );
                continue;
            }
            
            System.debug(
                LoggingLevel.INFO,
                'Starting Square image sync from Product_Image__c URL. Product2Id=' +
                p.Id +
                ', ProductImageId=' +
                imageRow.Id +
                ', ImageUrl=' +
                imageRow.Image_URL__c
            );
            
            ImageDownloadResult downloadedImage =
                downloadImageFromUrl(p.Id, imageRow.Image_URL__c);
            
            if (downloadedImage == null || downloadedImage.body == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'Square image sync skipped because image download failed. Product2Id=' +
                    p.Id +
                    ', ProductImageId=' +
                    imageRow.Id
                );
                continue;
            }
            
            String fileName = buildFileName(p, imageRow, downloadedImage.extension);
            String mimeType = downloadedImage.mimeType;
            
            try {
                SquareApiClient.createCatalogImage(
                    p.Square_Catalog_Item_Id__c,
                    p.Name,
                    downloadedImage.body,
                    fileName,
                    mimeType
                );
                
                System.debug(
                    LoggingLevel.INFO,
                    'Square image sync completed. Product2Id=' +
                    p.Id +
                    ', SquareCatalogItemId=' +
                    p.Square_Catalog_Item_Id__c +
                    ', FileName=' +
                    fileName +
                    ', MimeType=' +
                    mimeType
                );
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Square image sync failed. Product2Id=' +
                    p.Id +
                    ', SquareCatalogItemId=' +
                    p.Square_Catalog_Item_Id__c +
                    ', ProductImageId=' +
                    imageRow.Id +
                    ', Error=' +
                    e.getMessage()
                );
            }
        }
    }
    
    private static Map<Id, Product_Image__c> getPrimaryImageUrlByProductId(
        Set<Id> productIds
    ) {
        Map<Id, Product_Image__c> primaryImageByProductId =
            new Map<Id, Product_Image__c>();
        
        if (productIds == null || productIds.isEmpty()) {
            return primaryImageByProductId;
        }
        
        /*
* New image architecture:
* Product_Image__c.Image_URL__c is the source for outbound Square images.
*
* We take the most recently modified image row per Product2.
*/
        List<Product_Image__c> imageRows = [
            SELECT Id,
            Name,
            Product__c,
            Shopify_Image_Id__c,
            Image_URL__c,
            LastModifiedDate
            FROM Product_Image__c
            WHERE Product__c IN :productIds
            AND Image_URL__c != null
            ORDER BY Product__c, LastModifiedDate DESC
        ];
        
        for (Product_Image__c imageRow : imageRows) {
            if (imageRow.Product__c == null || String.isBlank(imageRow.Image_URL__c)) {
                continue;
            }
            
            if (!primaryImageByProductId.containsKey(imageRow.Product__c)) {
                primaryImageByProductId.put(imageRow.Product__c, imageRow);
            }
        }
        
        return primaryImageByProductId;
    }
    
    private static ImageDownloadResult downloadImageFromUrl(
        Id productId,
        String imageUrl
    ) {
        if (productId == null || String.isBlank(imageUrl)) {
            return null;
        }
        
        /*
* Try smaller Shopify CDN image sizes first.
* This does not resize inside Apex. It asks Shopify CDN for a smaller image.
*/
        List<Integer> widthsToTry = new List<Integer>{800, 600, 400};
            Integer maxImageSizeBytes = 1000000; // 1 MB
        
        for (Integer width : widthsToTry) {
            String optimizedImageUrl = buildShopifyResizedImageUrl(imageUrl, width);
            
            try {
                System.debug(
                    LoggingLevel.INFO,
                    'Downloading optimized image for Square. Product2Id=' +
                    productId +
                    ', Width=' +
                    width +
                    ', OriginalUrl=' +
                    imageUrl +
                    ', OptimizedUrl=' +
                    optimizedImageUrl
                );
                
                HttpRequest req = new HttpRequest();
                req.setEndpoint(optimizedImageUrl);
                req.setMethod('GET');
                req.setTimeout(120000);
                
                HttpResponse res = new Http().send(req);
                
                Integer statusCode = res.getStatusCode();
                
                if (statusCode < 200 || statusCode >= 300) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Optimized image URL download failed for Square sync. Product2Id=' +
                        productId +
                        ', Width=' +
                        width +
                        ', StatusCode=' +
                        statusCode +
                        ', Status=' +
                        res.getStatus() +
                        ', OptimizedUrl=' +
                        optimizedImageUrl
                    );
                    continue;
                }
                
                Blob imageBody = res.getBodyAsBlob();
                
                if (imageBody == null || imageBody.size() == 0) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Optimized image URL download returned empty body for Square sync. Product2Id=' +
                        productId +
                        ', Width=' +
                        width +
                        ', OptimizedUrl=' +
                        optimizedImageUrl
                    );
                    continue;
                }
                
                System.debug(
                    LoggingLevel.INFO,
                    'Optimized image downloaded for Square. Product2Id=' +
                    productId +
                    ', Width=' +
                    width +
                    ', SizeBytes=' +
                    imageBody.size()
                );
                
                if (imageBody.size() > maxImageSizeBytes) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Optimized image is still too large for Square upload. Product2Id=' +
                        productId +
                        ', Width=' +
                        width +
                        ', SizeBytes=' +
                        imageBody.size() +
                        ', MaxAllowedBytes=' +
                        maxImageSizeBytes +
                        ', OptimizedUrl=' +
                        optimizedImageUrl
                    );
                    continue;
                }
                
                String contentType = res.getHeader('Content-Type');
                String extension = getExtensionFromUrlOrContentType(
                    optimizedImageUrl,
                    contentType
                );
                String mimeType = getMimeType(extension, contentType);
                
                ImageDownloadResult result = new ImageDownloadResult();
                result.body = imageBody;
                result.extension = extension;
                result.mimeType = mimeType;
                
                return result;
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Exception while downloading optimized image URL for Square sync. Product2Id=' +
                    productId +
                    ', Width=' +
                    width +
                    ', OptimizedUrl=' +
                    optimizedImageUrl +
                    ', Error=' +
                    e.getMessage()
                );
            }
        }
        
        System.debug(
            LoggingLevel.WARN,
            'No optimized image version was small enough for Square upload. Product2Id=' +
            productId +
            ', OriginalUrl=' +
            imageUrl
        );
        
        return null;
    }
    private static String buildShopifyResizedImageUrl(String imageUrl, Integer width) {
        if (String.isBlank(imageUrl)) {
            return imageUrl;
        }
        
        if (width == null || width <= 0) {
            width = 800;
        }
        
        String cleanUrl = imageUrl.trim();
        
        /*
* Shopify CDN often supports width-based image transformation through
* URL query parameters. If the original URL already has query params,
* append width. Otherwise start query params.
*/
        if (cleanUrl.contains('?')) {
            if (!cleanUrl.contains('width=')) {
                cleanUrl += '&width=' + String.valueOf(width);
            }
        } else {
            cleanUrl += '?width=' + String.valueOf(width);
        }
        
        return cleanUrl;
    }
    
    private static String buildFileName(
        Product2 productRecord,
        Product_Image__c imageRow,
        String extension
    ) {
        String baseName = 'square-product-image';
        
        if (productRecord != null && !String.isBlank(productRecord.Name)) {
            baseName = productRecord.Name;
        }
        
        baseName = sanitizeFileName(baseName);
        
        if (String.isBlank(baseName)) {
            baseName = 'square-product-image';
        }
        
        String safeExtension = String.isBlank(extension)
            ? 'jpg'
            : extension.toLowerCase();
        
        if (
            safeExtension != 'jpg' &&
            safeExtension != 'jpeg' &&
            safeExtension != 'png' &&
            safeExtension != 'gif'
        ) {
            safeExtension = 'jpg';
        }
        
        return baseName + '.' + safeExtension;
    }
    
    private static String sanitizeFileName(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        
        String cleaned = value.trim();
        
        cleaned = cleaned.replaceAll('[^a-zA-Z0-9\\-_ ]', '');
        cleaned = cleaned.replaceAll('\\s+', '-');
        
        if (cleaned.length() > 80) {
            cleaned = cleaned.substring(0, 80);
        }
        
        return cleaned;
    }
    
    private static String getExtensionFromUrlOrContentType(
        String imageUrl,
        String contentType
    ) {
        String extensionFromContentType = getExtensionFromContentType(contentType);
        
        if (!String.isBlank(extensionFromContentType)) {
            return extensionFromContentType;
        }
        
        if (String.isBlank(imageUrl)) {
            return 'jpg';
        }
        
        String cleanUrl = imageUrl;
        
        Integer queryIndex = cleanUrl.indexOf('?');
        
        if (queryIndex > -1) {
            cleanUrl = cleanUrl.substring(0, queryIndex);
        }
        
        Integer hashIndex = cleanUrl.indexOf('#');
        
        if (hashIndex > -1) {
            cleanUrl = cleanUrl.substring(0, hashIndex);
        }
        
        Integer dotIndex = cleanUrl.lastIndexOf('.');
        
        if (dotIndex == -1 || dotIndex == cleanUrl.length() - 1) {
            return 'jpg';
        }
        
        String ext = cleanUrl.substring(dotIndex + 1).toLowerCase();
        
        if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif') {
            return ext;
        }
        
        return 'jpg';
    }
    
    private static String getExtensionFromContentType(String contentType) {
        if (String.isBlank(contentType)) {
            return null;
        }
        
        String normalizedContentType = contentType.toLowerCase();
        
        if (normalizedContentType.contains('image/png')) {
            return 'png';
        }
        
        if (normalizedContentType.contains('image/gif')) {
            return 'gif';
        }
        
        if (normalizedContentType.contains('image/jpg')) {
            return 'jpg';
        }
        
        if (normalizedContentType.contains('image/jpeg')) {
            return 'jpg';
        }
        
        return null;
    }
    
    private static String getMimeType(String extension, String contentType) {
        if (!String.isBlank(contentType)) {
            String normalizedContentType = contentType.toLowerCase();
            
            if (normalizedContentType.contains('image/png')) {
                return 'image/png';
            }
            
            if (normalizedContentType.contains('image/gif')) {
                return 'image/gif';
            }
            
            if (
                normalizedContentType.contains('image/jpg') ||
                normalizedContentType.contains('image/jpeg')
            ) {
                return 'image/jpeg';
            }
        }
        
        if (String.isBlank(extension)) {
            return 'image/jpeg';
        }
        
        String ext = extension.toLowerCase();
        
        if (ext == 'png') {
            return 'image/png';
        }
        
        if (ext == 'gif') {
            return 'image/gif';
        }
        
        if (ext == 'jpg' || ext == 'jpeg') {
            return 'image/jpeg';
        }
        
        return 'image/jpeg';
    }
    
    private class ImageDownloadResult {
        Blob body;
        String extension;
        String mimeType;
    }
}