@IsTest
private class ShopifyProductImageSyncServiceTest {

    private static Integer counter = 0;
    private static User shopifyWebhookUser;

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    private static String uniqueText(String prefix) {
        counter++;
        return prefix + '-' + String.valueOf(DateTime.now().getTime()) + '-' + counter;
    }

    private static String uniqueNumericText() {
        counter++;
        return String.valueOf(DateTime.now().getTime()) + String.valueOf(counter);
    }

    private static User getShopifyWebhookUser() {
        if (shopifyWebhookUser != null) {
            return shopifyWebhookUser;
        }

        String suffix = String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Math.abs(Crypto.getRandomInteger()));

        User u = new User(
            FirstName = 'Shopify',
            LastName = 'Webhook Site',
            Alias = 'shpwhk',
            Email = 'shopify_webhook_site_' + suffix + '@test.com',
            Username = 'shopify_webhook_site_' + suffix + '@test.com',
            CommunityNickname = ('shopifywebhook' + suffix).left(40),
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert u;
        shopifyWebhookUser = u;
        return shopifyWebhookUser;
    }

    private static Product2 insertProductWithoutOutbound(Product2 p) {
        System.runAs(getShopifyWebhookUser()) {
            insert p;
        }

        return p;
    }

    private static List<Product2> insertProductsWithoutOutbound(List<Product2> products) {
        System.runAs(getShopifyWebhookUser()) {
            insert products;
        }

        return products;
    }

    private static Product2 createParentProduct() {
        Product2 p = new Product2(
            Name = uniqueText('Parent Product'),
            IsActive = true,
            Type__c = 'Product',
            Shop_Id__c = uniqueNumericText(),
            Updated_by_Integration__c = true
        );

        return insertProductWithoutOutbound(p);
    }

    private static Product2 createVariantProduct(Id parentId, String shopifyVariantId, String skuValue) {
        Product2 v = new Product2(
            Name = uniqueText('Variant Product'),
            IsActive = true,
            Type__c = 'Variant',
            Parent__c = parentId,
            Shop_Id__c = shopifyVariantId,
            StockKeepingUnit = skuValue,
            Updated_by_Integration__c = true
        );

        return insertProductWithoutOutbound(v);
    }

    private static Product_Image__c buildProductImage(
        Id productId,
        String shopifyImageId,
        String imageUrl
    ) {
        Product_Image__c img = new Product_Image__c();

        if (Product_Image__c.SObjectType.getDescribe().fields.getMap().containsKey('Name')) {
            Schema.DescribeFieldResult nameDescribe =
                Product_Image__c.SObjectType.getDescribe().fields.getMap().get('Name').getDescribe();

            if (nameDescribe.isCreateable()) {
                img.put('Name', uniqueText('Product Image'));
            }
        }

        img.Product__c = productId;
        img.Shopify_Image_Id__c = shopifyImageId;
        img.Image_URL__c = imageUrl;

        return img;
    }

    private static Integer imageCountForProduct(Id productId) {
        return [
            SELECT COUNT()
            FROM Product_Image__c
            WHERE Product__c = :productId
        ];
    }

    private static Integer imageCountForProductAndImageId(Id productId, String imageId) {
        return [
            SELECT COUNT()
            FROM Product_Image__c
            WHERE Product__c = :productId
            AND Shopify_Image_Id__c = :imageId
        ];
    }

    private static Map<String, Object> imagePayloadWithImages() {
        return new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG1',
                    'src' => 'https://cdn.test.com/image-1.jpg'
                },
                new Map<String, Object>{
                    'id' => 'IMG2',
                    'url' => 'https://cdn.test.com/image-2.jpg'
                }
            }
        };
    }

    private static Map<String, Object> payloadWithDuplicateImages() {
        return new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'DUP1',
                    'src' => 'https://cdn.test.com/dup.jpg'
                },
                new Map<String, Object>{
                    'id' => 'DUP1',
                    'src' => 'https://cdn.test.com/dup-updated.jpg'
                },
                new Map<String, Object>{
                    'src' => 'https://cdn.test.com/no-id.jpg'
                },
                new Map<String, Object>{
                    'url' => 'https://cdn.test.com/no-id.jpg'
                },
                null,
                new Map<String, Object>{
                    'id' => 'NO_URL'
                }
            }
        };
    }

    private static Map<String, Object> singleImagePayload(String imageId, String url) {
        return new Map<String, Object>{
            'id' => '999',
            'image' => new Map<String, Object>{
                'id' => imageId,
                'src' => url
            }
        };
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mock for SKU writeback from InboundShopifyImagesJob
    // ─────────────────────────────────────────────────────────────────────

    private class ShopifyImageJobMock implements HttpCalloutMock {
        private String mode;

        ShopifyImageJobMock(String modeValue) {
            mode = modeValue;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (mode == 'USER_ERROR') {
                res.setBody(
                    '{"data":{"productVariantsBulkUpdate":{' +
                    '"product":null,' +
                    '"productVariants":[],' +
                    '"userErrors":[{"field":["variants"],"message":"SKU failed"}]' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'MISSING_DATA') {
                res.setBody('{}');
                return res;
            }

            res.setBody(
                '{"data":{"productVariantsBulkUpdate":{' +
                '"product":{"id":"gid://shopify/Product/999"},' +
                '"productVariants":[{"id":"gid://shopify/ProductVariant/888","title":"Variant","sku":"SKU-1"}],' +
                '"userErrors":[]' +
                '}}}'
            );
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Retired public method / wrapper compatibility
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSyncSalesforceFilesToShopifyRetiredMethodNullEmptyAndIds() {
        Product2 p = createParentProduct();

        Test.startTest();
        ShopifyProductImageSyncService.syncSalesforceFilesToShopify(null);
        ShopifyProductImageSyncService.syncSalesforceFilesToShopify(new Set<Id>());
        ShopifyProductImageSyncService.syncSalesforceFilesToShopify(new Set<Id>{ p.Id });
        Test.stopTest();

        System.assertEquals(0, imageCountForProduct(p.Id));
    }

    @IsTest
    static void testImageFileWrapperBackwardCompatibility() {
        ShopifyProductImageSyncService.ImageFileWrapper wrapper =
            new ShopifyProductImageSyncService.ImageFileWrapper();

        wrapper.title = 'Old Title';
        wrapper.fileName = 'old-file.jpg';
        wrapper.body = Blob.valueOf('old-body');

        System.assertEquals('Old Title', wrapper.title);
        System.assertEquals('old-file.jpg', wrapper.fileName);
        System.assertNotEquals(null, wrapper.body);
    }

    // ─────────────────────────────────────────────────────────────────────
    // enqueueInboundShopifyImages guard clauses
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testEnqueueInboundShopifyImagesNullBranches() {
        Product2 p = createParentProduct();

        Test.startTest();
        ShopifyProductImageSyncService.enqueueInboundShopifyImages(null, new Map<String, Object>());
        ShopifyProductImageSyncService.enqueueInboundShopifyImages(p.Id, null);
        Test.stopTest();

        System.assertEquals(0, imageCountForProduct(p.Id));
    }

    // ─────────────────────────────────────────────────────────────────────
    // InboundShopifyImagesJob guard/error branches
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testInboundJobNullBlankAndMissingProductBranches() {
        Account nonProduct = new Account(Name = uniqueText('Not Product'));
        insert nonProduct;

        Product2 productOne = createParentProduct();
        Product2 productTwo = createParentProduct();

        Test.startTest();
        System.enqueueJob(new ShopifyProductImageSyncService.InboundShopifyImagesJob(null, '{}'));
        System.enqueueJob(new ShopifyProductImageSyncService.InboundShopifyImagesJob(productOne.Id, null));
        System.enqueueJob(new ShopifyProductImageSyncService.InboundShopifyImagesJob(productTwo.Id, ''));
        System.enqueueJob(new ShopifyProductImageSyncService.InboundShopifyImagesJob(nonProduct.Id, '{}'));
        Test.stopTest();

        System.assertEquals(0, imageCountForProduct(productOne.Id));
        System.assertEquals(0, imageCountForProduct(productTwo.Id));
    }

    @IsTest
    static void testInboundJobInvalidJsonReturnsSafely() {
        Product2 p = createParentProduct();

        Test.startTest();
        System.enqueueJob(new ShopifyProductImageSyncService.InboundShopifyImagesJob(p.Id, '{bad json'));
        Test.stopTest();

        System.assertEquals(0, imageCountForProduct(p.Id));
    }

    @IsTest
    static void testInboundJobNoImagesReturnsSafely() {
        Product2 p = createParentProduct();

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'title' => 'No Images'
        };

        Test.startTest();
        ShopifyProductImageSyncService.enqueueInboundShopifyImages(p.Id, payload);
        Test.stopTest();

        System.assertEquals(0, imageCountForProduct(p.Id));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Direct URL sync branches
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSyncShopifyImagesToSalesforceNullBranches() {
        Product2 p = createParentProduct();

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(null, new Map<String, Object>());
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(new Product2(), new Map<String, Object>());
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(p, null);
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(p, new Map<String, Object>());
        ShopifyProductImageSyncService.syncShopifyImageUrlsToSalesforce(null, new Map<String, Object>());
        ShopifyProductImageSyncService.syncShopifyImageUrlsToSalesforce(new Product2(), new Map<String, Object>());
        ShopifyProductImageSyncService.syncShopifyImageUrlsToSalesforce(p, null);
        ShopifyProductImageSyncService.syncShopifyImageUrlsToSalesforce(p, new Map<String, Object>());
        Test.stopTest();

        System.assertEquals(0, imageCountForProduct(p.Id));
    }

    @IsTest
    static void testSyncImagesListCreatesProductImageRows() {
        Product2 p = createParentProduct();

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(
            p,
            imagePayloadWithImages()
        );
        Test.stopTest();

        System.assertEquals(2, imageCountForProduct(p.Id));
        System.assertEquals(1, imageCountForProductAndImageId(p.Id, 'IMG1'));
        System.assertEquals(1, imageCountForProductAndImageId(p.Id, 'IMG2'));
    }

    @IsTest
    static void testSingleFeaturedImageFallbackCreatesRow() {
        Product2 p = createParentProduct();

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(
            p,
            singleImagePayload('FEATURED1', 'https://cdn.test.com/featured.jpg')
        );
        Test.stopTest();

        Product_Image__c img = [
            SELECT Product__c, Shopify_Image_Id__c, Image_URL__c
            FROM Product_Image__c
            WHERE Product__c = :p.Id
            LIMIT 1
        ];

        System.assertEquals(p.Id, img.Product__c);
        System.assertEquals('FEATURED1', img.Shopify_Image_Id__c);
        System.assertEquals('https://cdn.test.com/featured.jpg', img.Image_URL__c);
    }

    @IsTest
    static void testImagesListTakesPriorityOverFeaturedImage() {
        Product2 p = createParentProduct();

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'LIST1',
                    'src' => 'https://cdn.test.com/list.jpg'
                }
            },
            'image' => new Map<String, Object>{
                'id' => 'FEATURED_SHOULD_NOT_INSERT',
                'src' => 'https://cdn.test.com/featured.jpg'
            }
        };

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(p, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(p.Id));
        System.assertEquals(1, imageCountForProductAndImageId(p.Id, 'LIST1'));
        System.assertEquals(0, imageCountForProductAndImageId(p.Id, 'FEATURED_SHOULD_NOT_INSERT'));
    }

    @IsTest
    static void testDuplicateImageIdsAndUrlsAreSkippedPerProduct() {
        Product2 p = createParentProduct();

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(
            p,
            payloadWithDuplicateImages()
        );
        Test.stopTest();

        System.assertEquals(
            2,
            imageCountForProduct(p.Id),
            'One duplicate image id and one duplicate URL without id should be saved once each.'
        );

        System.assertEquals(1, imageCountForProductAndImageId(p.Id, 'DUP1'));
    }

    @IsTest
    static void testExistingImageRowIsUpdatedInsteadOfDuplicated() {
        Product2 p = createParentProduct();

        Product_Image__c existingImage = buildProductImage(
            p.Id,
            'IMG-EXISTING',
            'https://cdn.test.com/old.jpg'
        );
        insert existingImage;

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-EXISTING',
                    'src' => 'https://cdn.test.com/new.jpg'
                }
            }
        };

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(p, payload);
        Test.stopTest();

        List<Product_Image__c> rows = [
            SELECT Id, Image_URL__c
            FROM Product_Image__c
            WHERE Product__c = :p.Id
            AND Shopify_Image_Id__c = 'IMG-EXISTING'
        ];

        System.assertEquals(1, rows.size());
        System.assertEquals('https://cdn.test.com/new.jpg', rows[0].Image_URL__c);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Target product expansion: variants[] / variant_gids / child fallback
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testImageRowsSyncToPayloadVariantIdsAlso() {
        Product2 parent = createParentProduct();

        String variantShopId = uniqueNumericText();
        Product2 variant = createVariantProduct(parent.Id, variantShopId, uniqueText('SKU'));

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-VARIANT',
                    'src' => 'https://cdn.test.com/variant.jpg'
                }
            },
            'variants' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'gid://shopify/ProductVariant/' + variantShopId
                },
                null,
                'not-a-map'
            }
        };

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(parent, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(parent.Id));
        System.assertEquals(1, imageCountForProduct(variant.Id));
    }

    @IsTest
    static void testImageRowsSyncToVariantGidsAlso() {
        Product2 parent = createParentProduct();

        String variantShopId = uniqueNumericText();
        Product2 variant = createVariantProduct(parent.Id, variantShopId, uniqueText('SKU'));

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-GID',
                    'src' => 'https://cdn.test.com/gid.jpg'
                }
            },
            'variant_gids' => new List<Object>{
                new Map<String, Object>{
                    'admin_graphql_api_id' => 'gid://shopify/ProductVariant/' + variantShopId + '.0'
                },
                null,
                'not-a-map'
            }
        };

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(parent, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(parent.Id));
        System.assertEquals(1, imageCountForProduct(variant.Id));
    }

    @IsTest
    static void testFallbackSyncsImagesToDirectChildVariantsWhenNoVariantIdsInPayload() {
        Product2 parent = createParentProduct();
        Product2 childOne = createVariantProduct(parent.Id, uniqueNumericText(), uniqueText('SKU'));
        Product2 childTwo = createVariantProduct(parent.Id, uniqueNumericText(), uniqueText('SKU'));

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-CHILD',
                    'src' => 'https://cdn.test.com/child.jpg'
                }
            }
        };

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(parent, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(parent.Id));
        System.assertEquals(1, imageCountForProduct(childOne.Id));
        System.assertEquals(1, imageCountForProduct(childTwo.Id));
    }

    @IsTest
    static void testVariantPayloadWithNoMatchingSfVariantStillSyncsOnlyPassedProduct() {
        Product2 parent = createParentProduct();

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-NO-MATCH',
                    'src' => 'https://cdn.test.com/no-match.jpg'
                }
            },
            'variants' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'gid://shopify/ProductVariant/DOES_NOT_MATCH'
                }
            }
        };

        Test.startTest();
        ShopifyProductImageSyncService.syncShopifyImagesToSalesforce(parent, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(parent.Id));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Queueable full flow including SKU writeback branches
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testInboundQueueableWritesImagesAndSkuWritebackSuccess() {
        Product2 parent = createParentProduct();

        String variantShopId = uniqueNumericText();
        Product2 variant = createVariantProduct(parent.Id, variantShopId, 'ES-RG-G-0001-070');

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-JOB',
                    'src' => 'https://cdn.test.com/job.jpg'
                }
            },
            'variants' => new List<Object>{
                new Map<String, Object>{
                    'id' => variantShopId
                }
            }
        };

        Test.setMock(HttpCalloutMock.class, new ShopifyImageJobMock('SUCCESS'));

        Test.startTest();
        ShopifyProductImageSyncService.enqueueInboundShopifyImages(parent.Id, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(parent.Id));
        System.assertEquals(1, imageCountForProduct(variant.Id));
    }

    @IsTest
    static void testInboundQueueableSkuWritebackUserErrorsAreCaughtAndImagesStillSave() {
        Product2 parent = createParentProduct();

        String variantShopId = uniqueNumericText();
        Product2 variant = createVariantProduct(parent.Id, variantShopId, 'ES-RG-G-0002-070');

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-JOB-ERR',
                    'src' => 'https://cdn.test.com/job-error.jpg'
                }
            },
            'variants' => new List<Object>{
                new Map<String, Object>{
                    'id' => variantShopId
                }
            }
        };

        Test.setMock(HttpCalloutMock.class, new ShopifyImageJobMock('USER_ERROR'));

        Test.startTest();
        ShopifyProductImageSyncService.enqueueInboundShopifyImages(parent.Id, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(parent.Id));
        System.assertEquals(1, imageCountForProduct(variant.Id));
    }

    @IsTest
    static void testInboundQueueableSkipsSkuWritebackWhenNoProductId() {
        Product2 p = createParentProduct();

        Map<String, Object> payload = new Map<String, Object>{
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-NO-PRODUCT-ID',
                    'src' => 'https://cdn.test.com/no-product-id.jpg'
                }
            },
            'variants' => new List<Object>{
                new Map<String, Object>{
                    'id' => uniqueNumericText()
                }
            }
        };

        Test.startTest();
        ShopifyProductImageSyncService.enqueueInboundShopifyImages(p.Id, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(p.Id));
    }

    @IsTest
    static void testInboundQueueableSkipsSkuWritebackWhenNoVariantIds() {
        Product2 p = createParentProduct();

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-NO-VARIANTS',
                    'src' => 'https://cdn.test.com/no-variants.jpg'
                }
            }
        };

        Test.startTest();
        ShopifyProductImageSyncService.enqueueInboundShopifyImages(p.Id, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(p.Id));
    }

    @IsTest
    static void testInboundQueueableSkipsSkuWritebackWhenNoSfVariantWithSku() {
        Product2 parent = createParentProduct();

        String variantShopId = uniqueNumericText();
        Product2 variant = createVariantProduct(parent.Id, variantShopId, null);

        Map<String, Object> payload = new Map<String, Object>{
            'id' => '999',
            'images' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'IMG-NO-SKU',
                    'src' => 'https://cdn.test.com/no-sku.jpg'
                }
            },
            'variants' => new List<Object>{
                new Map<String, Object>{
                    'id' => variantShopId
                }
            }
        };

        Test.startTest();
        ShopifyProductImageSyncService.enqueueInboundShopifyImages(parent.Id, payload);
        Test.stopTest();

        System.assertEquals(1, imageCountForProduct(parent.Id));
        System.assertEquals(1, imageCountForProduct(variant.Id));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Bypass flag compatibility
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testBypassFlagCanBeSetForBackwardCompatibility() {
        ShopifyProductImageSyncService.bypassProductFileLinkTrigger = true;
        System.assertEquals(true, ShopifyProductImageSyncService.bypassProductFileLinkTrigger);

        ShopifyProductImageSyncService.bypassProductFileLinkTrigger = false;
        System.assertEquals(false, ShopifyProductImageSyncService.bypassProductFileLinkTrigger);
    }
}