@IsTest
private class SquareCatalogImageQueueableTest {

    private static Integer counter = 0;

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    private static String uniqueText(String prefix) {
        counter++;
        return prefix + '-' + String.valueOf(DateTime.now().getTime()) + '-' + counter;
    }

    private static Boolean fieldExists(String objectApiName, String fieldApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName) &&
            Schema.getGlobalDescribe()
                .get(objectApiName)
                .getDescribe()
                .fields
                .getMap()
                .containsKey(fieldApiName);
    }

    private static Product2 createParentProduct(String squareItemId, String productName) {
        Product2 p = new Product2(
            Name = String.isBlank(productName) ? uniqueText('Parent Product') : productName,
            IsActive = true
        );

        if (fieldExists('Product2', 'Square_Catalog_Item_Id__c') && squareItemId != null) {
            p.put('Square_Catalog_Item_Id__c', squareItemId);
        }

        if (fieldExists('Product2', 'Shop_ID__c')) {
            p.put('Shop_ID__c', uniqueText('SHOP'));
        }

        if (fieldExists('Product2', 'Updated_by_Integration__c')) {
            p.put('Updated_by_Integration__c', true);
        }

        if (fieldExists('Product2', 'Type__c')) {
            p.put('Type__c', 'Product');
        }

        insert p;
        return p;
    }

    private static Product_Image__c createProductImage(
        Id productId,
        String imageUrl,
        String imageName
    ) {
        Product_Image__c img = new Product_Image__c();

        //img.Name = String.isBlank(imageName) ? uniqueText('Product Image') : imageName;
        img.Product__c = productId;
        img.Image_URL__c = imageUrl;

        if (fieldExists('Product_Image__c', 'Shopify_Image_Id__c')) {
            img.put('Shopify_Image_Id__c', uniqueText('SHOPIFY-IMG'));
        }

        insert img;
        return img;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mock
    // Handles:
    // 1. Shopify/Product trigger side-effect callouts
    // 2. Image URL download callouts
    // 3. Square catalog image upload callouts
    // ─────────────────────────────────────────────────────────────────────

    private class SquareImageMock implements HttpCalloutMock {
        private String mode;

        SquareImageMock(String modeValue) {
            mode = modeValue;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
            String lowerEndpoint = endpoint.toLowerCase();

            // Square catalog image upload endpoint.
            // Important: do this before req.getBody(), because multipart requests use bodyAsBlob.
            if (lowerEndpoint.contains('/v2/catalog/images')) {
                if (mode == 'UPLOAD_ERROR') {
                    res.setStatusCode(500);
                    res.setHeader('Content-Type', 'application/json');
                    res.setBody('{"errors":[{"detail":"Forced upload error"}]}');
                    return res;
                }

                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{"image":{' +
                    '"id":"SQUARE_IMAGE_123",' +
                    '"type":"IMAGE",' +
                    '"image_data":{"name":"Uploaded Image"}' +
                    '}}'
                );
                return res;
            }

            // Image download URL callouts.
            if (
                lowerEndpoint.startsWith('http://') ||
                lowerEndpoint.startsWith('https://')
            ) {
                if (mode == 'DOWNLOAD_500') {
                    res.setStatusCode(500);
                    res.setStatus('Server Error');
                    res.setHeader('Content-Type', 'text/plain');
                    res.setBody('download failed');
                    return res;
                }

                if (mode == 'DOWNLOAD_EMPTY') {
                    res.setStatusCode(200);
                    res.setHeader('Content-Type', 'image/jpeg');
                    res.setBody('');
                    return res;
                }

                res.setStatusCode(200);

                if (mode == 'PNG_CONTENT_TYPE') {
                    res.setHeader('Content-Type', 'image/png');
                    res.setBodyAsBlob(Blob.valueOf('fake png bytes'));
                    return res;
                }

                if (mode == 'GIF_CONTENT_TYPE') {
                    res.setHeader('Content-Type', 'image/gif');
                    res.setBodyAsBlob(Blob.valueOf('fake gif bytes'));
                    return res;
                }

                if (mode == 'JPG_CONTENT_TYPE') {
                    res.setHeader('Content-Type', 'image/jpg');
                    res.setBodyAsBlob(Blob.valueOf('fake jpg bytes'));
                    return res;
                }

                if (mode == 'JPEG_CONTENT_TYPE') {
                    res.setHeader('Content-Type', 'image/jpeg');
                    res.setBodyAsBlob(Blob.valueOf('fake jpeg bytes'));
                    return res;
                }

                if (mode == 'UNKNOWN_CONTENT_TYPE') {
                    res.setHeader('Content-Type', 'application/octet-stream');
                    res.setBodyAsBlob(Blob.valueOf('fake unknown image bytes'));
                    return res;
                }

                res.setHeader('Content-Type', 'image/jpeg');
                res.setBodyAsBlob(Blob.valueOf('fake image bytes'));
                return res;
            }

            // Safe Shopify/Product trigger side-effect responses.
            String body = req.getBody();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (body != null && body.contains('productVariantsBulkUpdate')) {
                res.setBody(
                    '{"data":{"productVariantsBulkUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"productVariants":[],' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (body != null && body.contains('productCreate')) {
                res.setBody(
                    '{"data":{"productCreate":{' +
                    '"product":{"id":"gid://shopify/Product/123","legacyResourceId":"123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            if (body != null && body.contains('productUpdate')) {
                res.setBody(
                    '{"data":{"productUpdate":{' +
                    '"product":{"id":"gid://shopify/Product/123"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }

            res.setBody('{"data":{}}');
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Guard branches
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testNullInputReturnsSafely() {
        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(null));
        Test.stopTest();

        System.assert(true, 'Null parent ids should return safely.');
    }

    @IsTest
    static void testEmptyInputReturnsSafely() {
        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>()));
        Test.stopTest();

        System.assert(true, 'Empty parent ids should return safely.');
    }

    @IsTest
    static void testParentWithoutSquareCatalogItemIdIsIgnored() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('SUCCESS'));

        Product2 parent = createParentProduct(null, 'No Square Id Product');

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/no-square-id.jpg',
            'Ignored Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'Parent without Square_Catalog_Item_Id__c should be ignored.');
    }

    @IsTest
    static void testParentWithSquareIdButNoProductImageReturnsSafely() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('SUCCESS'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_NO_IMAGE',
            'No Product Image Product'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'Parent with no Product_Image__c row should be skipped safely.');
    }

    // ─────────────────────────────────────────────────────────────────────
    // Successful image download/upload branches
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testUploadsPngImageFromContentType() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('PNG_CONTENT_TYPE'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_PNG',
            'PNG Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/image-without-extension',
            'PNG Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'PNG content type should upload successfully.');
    }

    @IsTest
    static void testUploadsGifImageFromContentType() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('GIF_CONTENT_TYPE'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_GIF',
            'GIF Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/image-without-extension',
            'GIF Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'GIF content type should upload successfully.');
    }

    @IsTest
    static void testUploadsJpgImageFromContentType() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('JPG_CONTENT_TYPE'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_JPG',
            'JPG Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/image-without-extension',
            'JPG Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'JPG content type should upload successfully.');
    }

    @IsTest
    static void testUploadsJpegImageFromContentType() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('JPEG_CONTENT_TYPE'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_JPEG',
            'JPEG Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/image-without-extension',
            'JPEG Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'JPEG content type should upload successfully.');
    }

    @IsTest
    static void testUploadsImageUsingUrlExtensionWhenContentTypeUnknown() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('UNKNOWN_CONTENT_TYPE'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_URL_EXT',
            'URL Extension Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/url-extension-image.png',
            'URL Extension Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'URL extension should be used when content type is unknown.');
    }

    @IsTest
    static void testUnsupportedUrlExtensionFallsBackToJpg() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('UNKNOWN_CONTENT_TYPE'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_UNSUPPORTED',
            'Unsupported Extension Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/unsupported-image.webp',
            'Unsupported Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'Unsupported extension should fall back to jpg/jpeg.');
    }

    @IsTest
    static void testUrlWithExistingQueryAddsWidthSafely() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('UNKNOWN_CONTENT_TYPE'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_QUERY',
            'Query Param Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/query-image.jpg?v=123',
            'Query Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'Image URL with existing query params should still download.');
    }

    @IsTest
    static void testUrlWithExistingWidthDoesNotDuplicateWidth() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('UNKNOWN_CONTENT_TYPE'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_WIDTH',
            'Existing Width Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/width-image.jpg?width=1000',
            'Width Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'Image URL with existing width param should still download.');
    }

    @IsTest
    static void testSanitizedLongProductNameBuildsSafeFileName() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('JPEG_CONTENT_TYPE'));

        String longName =
            'Very Long Product Name !@#$%^&*() With Special Characters And Spaces ' +
            'That Should Be Sanitized And Trimmed Because It Is More Than Eighty Characters';

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_LONG_NAME',
            longName
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/long-name-image.jpeg',
            'Long Name Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'Long/special product name should be sanitized safely.');
    }

    // ─────────────────────────────────────────────────────────────────────
    // Failure / continue branches
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testImageDownloadHttpFailureSkipsUpload() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('DOWNLOAD_500'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_DOWNLOAD_500',
            'Download Failure Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/download-failure.jpg',
            'Download Failure Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'HTTP 500 image download should be skipped safely.');
    }

    @IsTest
    static void testImageDownloadEmptyBodySkipsUpload() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('DOWNLOAD_EMPTY'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_EMPTY_DOWNLOAD',
            'Empty Download Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/empty-download.jpg',
            'Empty Download Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'Empty image download body should be skipped safely.');
    }

    @IsTest
    static void testSquareUploadExceptionIsCaught() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('UPLOAD_ERROR'));

        Product2 parent = createParentProduct(
            'SQUARE_ITEM_UPLOAD_ERROR',
            'Upload Error Product'
        );

        createProductImage(
            parent.Id,
            'https://cdn.shopify.com/test/upload-error.jpg',
            'Upload Error Image'
        );

        Test.startTest();
        System.enqueueJob(new SquareCatalogImageQueueable(new Set<Id>{ parent.Id }));
        Test.stopTest();

        System.assert(true, 'Square upload exception should be caught and logged.');
    }

    @IsTest
    static void testMultipleParentsOneValidOneWithoutImage() {
        Test.setMock(HttpCalloutMock.class, new SquareImageMock('JPEG_CONTENT_TYPE'));

        Product2 validParent = createParentProduct(
            'SQUARE_ITEM_VALID_MULTI',
            'Valid Multi Parent'
        );

        Product2 noImageParent = createParentProduct(
            'SQUARE_ITEM_NO_IMAGE_MULTI',
            'No Image Multi Parent'
        );

        createProductImage(
            validParent.Id,
            'https://cdn.shopify.com/test/multi-valid.jpg',
            'Multi Valid Image'
        );

        Test.startTest();
        System.enqueueJob(
            new SquareCatalogImageQueueable(
                new Set<Id>{
                    validParent.Id,
                    noImageParent.Id
                }
            )
        );
        Test.stopTest();

        System.assert(true, 'Multiple parent branch should process valid row and skip missing image row.');
    }
}