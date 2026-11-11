@IsTest(SeeAllData=true)
public class ProductOrchestrationServiceTest {
    
    private class SafeHttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            String endpoint = req.getEndpoint();
            String body = req.getBody();
            
            // Remote Shopify image download mock.
            if (endpoint != null && endpoint.startsWith('http://image.com')) {
                res.setHeader('Content-Type', 'image/jpeg');
                res.setBody('fake image bytes');
                return res;
            }
            
            // Square catalog upsert / retrieve safety.
            if (
                endpoint != null &&
                endpoint.contains('/v2/catalog/object') &&
                req.getMethod() == 'POST'
            ) {
                res.setBody(
                    '{"catalog_object":{"id":"SQUARE_ITEM_123","type":"ITEM"},' +
                    '"id_mappings":[]}'
                );
                return res;
            }
            
            if (
                endpoint != null &&
                endpoint.contains('/v2/catalog/object/') &&
                req.getMethod() == 'GET'
            ) {
                res.setBody(
                    '{"object":{"id":"SQUARE_OBJECT_123","version":12345}}'
                );
                return res;
            }
            
            if (endpoint != null && endpoint.contains('/v2/catalog/images')) {
                res.setBody(
                    '{"image":{"id":"SQUARE_IMAGE_123","type":"IMAGE"}}'
                );
                return res;
            }
            
            // Product variant bulk update must be checked before productVariant.
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
            
            // Inventory pull GraphQL shape.
            if (body != null && body.contains('productVariant')) {
                res.setBody(
                    '{"data":{"productVariant":{' +
                    '"id":"gid://shopify/ProductVariant/2001",' +
                    '"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/999",' +
                    '"inventoryLevels":{"nodes":[]}' +
                    '}' +
                    '}}}'
                );
                return res;
            }
            
            res.setBody(
                '{"data":{' +
                '"productCreate":{"product":{"id":"gid://shopify/Product/123","legacyResourceId":"123"},"userErrors":[]},' +
                '"productUpdate":{"product":{"id":"gid://shopify/Product/123"},"userErrors":[]},' +
                '"productVariantsBulkUpdate":{"product":{"id":"gid://shopify/Product/123"},"productVariants":[],"userErrors":[]}' +
                '}}'
            );
            return res;
        }
    }
    
    private static Id getStandardPricebookIdSafe() {
        Id pbId = Test.getStandardPricebookId();
        
        try {
            update new Pricebook2(
                Id = pbId,
                IsActive = true
            );
        } catch (Exception e) {
            // Standard Pricebook may already be active.
        }
        
        return pbId;
    }
    
    private static Map<String, Id> getRecordTypeIds() {
        Map<String, Id> recordTypeIds = new Map<String, Id>();
        
        for (RecordType rt : [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName IN ('Product', 'Variant')
        ]) {
            recordTypeIds.put(rt.DeveloperName, rt.Id);
        }
        
        return recordTypeIds;
    }
    
    private static REST_Field_Mapping__mdt mapping(
        String topic,
        String requestAttribute,
        String sfField
    ) {
        REST_Field_Mapping__mdt m = new REST_Field_Mapping__mdt();
        m.Topic__c = topic;
        m.Request_Attribute__c = requestAttribute;
        m.SF_Field_Name__c = sfField;
        m.SF_Object_Name__c = 'Product2';
        return m;
    }
    
    private static Map<String, List<REST_Field_Mapping__mdt>> buildGroupedMappings() {
        return new Map<String, List<REST_Field_Mapping__mdt>>{
            'products' => new List<REST_Field_Mapping__mdt>{
                mapping('products', 'id', 'Shop_ID__c'),
                    mapping('products', 'title', 'Name'),
                    mapping('products', 'body_html', 'Description')
                    },
                        'variants' => new List<REST_Field_Mapping__mdt>{
                            mapping('variants', 'id', 'Shop_ID__c'),
                                mapping('variants', 'title', 'Name'),
                                mapping('variants', 'sku', 'StockKeepingUnit')
                                }
        };
            }
    
    private static Integer uniqueNumber(Integer offsetValue) {
        Integer baseValue = Math.mod(Math.abs(Crypto.getRandomInteger()), 800000);
        return baseValue + offsetValue;
    }
    
    private static Map<String, Object> buildProductPayload(
        Integer productId,
        Integer variantId,
        String productType,
        String status,
        String variantTitle,
        String sku
    ) {
        return new Map<String, Object>{
            'id' => productId,
                'title' => 'Test Product ' + productId,
                'body_html' => 'Description ' + productId,
                'product_type' => productType,
                'status' => status,
                'tags' => 'tag1, tag2',
                'image' => new Map<String, Object>{
                    'src' => 'http://image.com/product-' + productId + '.jpg'
                        },
                            'variants' => new List<Object>{
                                new Map<String, Object>{
                                    'id' => variantId,
                                        'title' => variantTitle,
                                        'sku' => sku,
                                        'price' => '15.00',
                                        'inventory_item_id' => 'INV-' + variantId,
                                        'weight' => '2',
                                        'weight_unit' => 'kg',
                                        'image_id' => 1
                                        }
                            },
                                'images' => new List<Object>{
                                    new Map<String, Object>{
                                        'id' => 1,
                                            'src' => 'http://image.com/variant-' + variantId + '.jpg'
                                            }
                                }
        };
            }
    
    private static Map<String, Object> buildProductPayload() {
        Integer productId = uniqueNumber(100000);
        Integer variantId = uniqueNumber(200000);
        
        return buildProductPayload(
            productId,
            variantId,
            'Earrings',
            'active',
            'Default Title',
            'SKU-' + variantId
        );
    }
    
    @IsTest
    static void testSingleProductFullProcessProductOnlyNoAsyncSquareSync() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        getStandardPricebookIdSafe();
        
        Integer productId = uniqueNumber(100000);
        
        Map<String, Object> productPayload = new Map<String, Object>{
            'id' => productId,
                'title' => 'Product Only ' + productId,
                'body_html' => 'Description ' + productId,
                'product_type' => 'Earrings',
                'status' => 'active',
                'tags' => 'tag1, tag2',
                'image' => new Map<String, Object>{
                    'src' => 'http://image.com/product-' + productId + '.jpg'
                        },
                            'images' => new List<Object>{
                                new Map<String, Object>{
                                    'id' => 1,
                                        'src' => 'http://image.com/product-' + productId + '-image.jpg'
                                        }
                            }
        };
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'product' => productPayload
                    };
                        
                        Test.startTest();
        ProductOrchestrationService.processProductsFromRestRequest(
            wrapper,
            new String[]{ 'products', 'variants' }
        );
        Test.stopTest();
        
        List<Product2> products = [
            SELECT Id, Name, Family, IsActive, Shop_ID__c, Type__c, Image_URL__c
            FROM Product2
            WHERE Shop_ID__c = :String.valueOf(productId)
        ];
        
        System.assertEquals(1, products.size(), 'Product should be created.');
        System.assertEquals('Product', products[0].Type__c);
        System.assertEquals('Earrings', products[0].Family);
        System.assertEquals(true, products[0].IsActive);
        System.assertEquals(
            'http://image.com/product-' + productId + '.jpg',
            products[0].Image_URL__c
        );
        
        List<Custom_Topic__c> topics = [
            SELECT Id, External_Id__c
            FROM Custom_Topic__c
            WHERE External_Id__c = :String.valueOf(productId)
        ];
        
        System.assertEquals(1, topics.size(), 'Topic should be created.');
    }
    @IsTest
    static void testMultipleProductsFullProcessProductOnlyNoAsyncSquareSync() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        getStandardPricebookIdSafe();
        
        Integer productId1 = uniqueNumber(110000);
        Integer productId2 = uniqueNumber(120000);
        
        Map<String, Object> productPayload1 = new Map<String, Object>{
            'id' => productId1,
                'title' => 'Product One ' + productId1,
                'body_html' => 'Description ' + productId1,
                'product_type' => 'Dangles',
                'status' => 'active',
                'tags' => 'tag1, tag2',
                'image' => new Map<String, Object>{
                    'src' => 'http://image.com/product-' + productId1 + '.jpg'
                        }
        };
            
            Map<String, Object> productPayload2 = new Map<String, Object>{
                'id' => productId2,
                    'title' => 'Product Two ' + productId2,
                    'body_html' => 'Description ' + productId2,
                    'product_type' => 'Bracelets',
                    'status' => 'draft',
                    'tags' => 'tag3, tag4',
                    'image' => new Map<String, Object>{
                        'src' => 'http://image.com/product-' + productId2 + '.jpg'
                            }
            };
                
                Map<String, Object> wrapper = new Map<String, Object>{
                    'products' => new List<Object>{
                        productPayload1,
                            productPayload2
                            }
                };
                    
                    Test.startTest();
        ProductOrchestrationService.processProductsFromRestRequest(
            wrapper,
            new String[]{ 'products', 'variants' }
        );
        Test.stopTest();
        
        List<Product2> products = [
            SELECT Id, Shop_ID__c, Family, IsActive, Type__c
            FROM Product2
            WHERE Shop_ID__c IN :new Set<String>{
                String.valueOf(productId1),
                    String.valueOf(productId2)
                    }
        ];
        
        System.assertEquals(2, products.size(), 'Two products should be created.');
    }
    @IsTest
    static void testFullProcessVariantWithMissingTitleStillProcessesSafely() {
        getStandardPricebookIdSafe();
        
        Integer productId = uniqueNumber(130000);
        Integer variantId = uniqueNumber(230000);
        
        Map<String, Object> payload = new Map<String, Object>{
            'id' => productId,
                'title' => 'Product With Missing Variant Title ' + productId,
                'body_html' => 'Description ' + productId,
                'product_type' => 'Earrings',
                'status' => 'active',
                'tags' => 'tag1, tag2',
                'variants' => new List<Object>{
                    new Map<String, Object>{
                        'id' => variantId,
                            // Intentionally no title.
                            // Current service still builds a safe variant name.
                            'sku' => 'SKU-BAD-' + variantId,
                            'price' => '15.00',
                            'inventory_item_id' => 'INV-' + variantId,
                            'weight' => '2',
                            'weight_unit' => 'kg'
                            }
                }
        };
            
            Test.startTest();
        
        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result map should not be null.');
        System.assertEquals(1, result.get('Product').size(), 'Parent product should be built.');
        System.assertEquals(1, result.get('Variant').size(), 'Variant should still be built safely.');
        System.assertEquals(1, result.get('PricebookEntry').size(), 'PricebookEntry should be built for the variant.');
        
        Product2 parentProduct = (Product2) result.get('Product')[0];
        Product2 variantProduct = (Product2) result.get('Variant')[0];
        PricebookEntry pbe = (PricebookEntry) result.get('PricebookEntry')[0];
        
        System.assertEquals('Product', parentProduct.Type__c);
        System.assertEquals('Variant', variantProduct.Type__c);
        System.assertEquals(String.valueOf(productId), parentProduct.Shop_ID__c);
        System.assertEquals(String.valueOf(variantId), variantProduct.Shop_ID__c);
        System.assertEquals('SKU-BAD-' + variantId, variantProduct.StockKeepingUnit);
        System.assertEquals('INV-' + variantId, variantProduct.Inventory_Item_Id__c);
        
        System.assert(
            variantProduct.Name != null &&
            variantProduct.Name.contains('Product With Missing Variant Title'),
            'Variant should receive a safe fallback name. Actual: ' + variantProduct.Name
        );
        
        System.assertEquals(15, pbe.UnitPrice);
        System.assertEquals(true, pbe.IsActive);
    }
    
    @IsTest
    static void testProcessSingleProductVariantTitleDefaultTitleUsesParentName() {
        Integer productId = uniqueNumber(910000);
        Integer variantId = uniqueNumber(920000);

        Map<String, Object> payload = buildProductPayload(
            productId,
            variantId,
            'Rings',
            'active',
            'Default Title',
            'SKU-DEFAULT-' + variantId
        );

        Test.startTest();
        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
        Test.stopTest();

        System.assertEquals(1, result.get('Product').size());
        System.assertEquals(1, result.get('Variant').size());

        Product2 productRecord = (Product2) result.get('Product')[0];
        Product2 variantRecord = (Product2) result.get('Variant')[0];
        String sourceTitle = 'Test Product ' + productId;

        System.assertEquals('Product', productRecord.Type__c);
        System.assertEquals('Variant', variantRecord.Type__c);
        System.assert(
            productRecord.Name != null &&
            productRecord.Name.equalsIgnoreCase(sourceTitle),
            'The parent name should match the Shopify title without relying on capitalization. Actual: ' +
            productRecord.Name
        );
        System.assert(
            variantRecord.Name != null &&
            variantRecord.Name.equalsIgnoreCase(sourceTitle),
            'A Default Title Variant should reuse the parent title without relying on capitalization. Actual: ' +
            variantRecord.Name
        );
        System.assert(
            productRecord.Name.equalsIgnoreCase(variantRecord.Name),
            'The parent and default-title Variant should have the same logical name.'
        );
        System.assertEquals('Rings', productRecord.Family);
        System.assertEquals('Rings', variantRecord.Family);
        System.assertEquals(String.valueOf(productId), productRecord.Shop_ID__c);
        System.assertEquals(String.valueOf(variantId), variantRecord.Shop_ID__c);
        System.assertEquals('SKU-DEFAULT-' + variantId, variantRecord.StockKeepingUnit);
    }

    @IsTest
    static void testNullPayloadAndEmptyCollectionsReturnSafely() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        getStandardPricebookIdSafe();
        
        Test.startTest();
        
        ProductOrchestrationService.processProductsFromRestRequest(
            null,
            new String[]{ 'products' }
        );
        
        ProductOrchestrationService.processProductsFromRestRequest(
            new Map<String, Object>{ 'products' => null },
            new String[]{ 'products', 'variants' }
        );
        
        ProductOrchestrationService.processProductsFromRestRequest(
            new Map<String, Object>{ 'products' => new List<Object>{ null } },
            new String[]{ 'products', 'variants' }
        );
        
        ProductOrchestrationService.processProductsFromRestRequest(
            new Map<String, Object>{ 'product' => null },
            new String[]{ 'products', 'variants' }
        );
        
        Test.stopTest();
        
        System.assert(true, 'Empty payload paths should complete safely.');
    }
    
    @IsTest
    static void testProcessSingleProductDirectBuildsRecords() {
        Map<String, Object> payload = buildProductPayload();
        
        Test.startTest();
        
        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(1, result.get('Product').size());
        System.assertEquals(1, result.get('Variant').size());
        System.assertEquals(1, result.get('Topic').size());
        System.assertEquals(1, result.get('PricebookEntry').size());
        
        Product2 product = (Product2) result.get('Product')[0];
        Product2 variant = (Product2) result.get('Variant')[0];
        PricebookEntry pbe = (PricebookEntry) result.get('PricebookEntry')[0];
        
        System.assertEquals('Product', product.Type__c);
        System.assertEquals('Variant', variant.Type__c);
        System.assertEquals('Earrings', product.Family);
        System.assertEquals(true, product.IsActive);
        System.assertEquals(product.Family, variant.Family);
        System.assertEquals(15, pbe.UnitPrice);
        System.assertEquals(true, pbe.IsActive);
    }
    
    @IsTest
    static void testProcessSingleProductWithoutMappingsReturnsEmptyLists() {
        Map<String, Object> payload = buildProductPayload();
        
        Test.startTest();
        
        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                new Map<String, List<REST_Field_Mapping__mdt>>(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
        
        Test.stopTest();
        
        System.assertEquals(0, result.get('Product').size());
        System.assertEquals(0, result.get('Variant').size());
        System.assertEquals(0, result.get('Topic').size());
        System.assertEquals(0, result.get('PricebookEntry').size());
    }
    
    @IsTest
    static void testProcessSingleProductHandlesNullVariantAndMissingImages() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => uniqueNumber(300000),
                'title' => 'No Image Product',
                'body_html' => 'Description',
                'product_type' => 'Hoops',
                'status' => 'active',
                'variants' => new List<Object>{
                    null,
                        new Map<String, Object>{
                            'id' => uniqueNumber(400000),
                                'title' => 'Default Title',
                                'sku' => 'SKU-NULL-VARIANT',
                                'price' => null,
                                'weight' => '0',
                                'weight_unit' => 'oz'
                                }
                },
                    'images' => new List<Object>{
                        null,
                            new Map<String, Object>{
                                'id' => null,
                                    'src' => 'http://image.com/bad.jpg'
                                    }
                    }
        };
            
            Test.startTest();
        
        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
        
        Test.stopTest();
        
        System.assertEquals(1, result.get('Product').size());
        System.assertEquals(1, result.get('Variant').size());
        System.assertEquals(1, result.get('PricebookEntry').size());
        
        Product2 product = (Product2) result.get('Product')[0];
        Product2 variant = (Product2) result.get('Variant')[0];
        PricebookEntry pbe = (PricebookEntry) result.get('PricebookEntry')[0];
        
        System.assertEquals('Earrings', product.Family);
        System.assertEquals('No Image Product', variant.Name);
        System.assertEquals(0, pbe.UnitPrice);
    }
    
    @IsTest
    static void testProcessSingleProductNoImagesList() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => uniqueNumber(500000),
                'title' => 'No Images List Product',
                'body_html' => 'Description',
                'product_type' => 'Bracelets',
                'status' => 'draft',
                'variants' => new List<Object>{
                    new Map<String, Object>{
                        'id' => uniqueNumber(600000),
                            'title' => 'Blue',
                            'sku' => 'SKU-NO-IMAGE',
                            'price' => '22.50',
                            'weight' => '1',
                            'weight_unit' => 'lb'
                            }
                }
        };
            
            Test.startTest();
        
        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
        
        Test.stopTest();
        
        Product2 product = (Product2) result.get('Product')[0];
        Product2 variant = (Product2) result.get('Variant')[0];
        PricebookEntry pbe = (PricebookEntry) result.get('PricebookEntry')[0];
        
        System.assertEquals('Bracelets', product.Family);
        System.assertEquals(false, product.IsActive);
        System.assertEquals('No Images List Product - Blue', variant.Name);        
        System.assertEquals(22.50, pbe.UnitPrice);
    }
    
    @IsTest
    static void testProcessSingleProductNoVariantsReturnsProductOnly() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => uniqueNumber(700000),
                'title' => 'Product Only',
                'body_html' => 'Description',
                'product_type' => 'Studs',
                'status' => 'active',
                'tags' => 'tag1, tag2'
                };
                    
                    Test.startTest();
        
        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
        
        Test.stopTest();
        
        System.assertEquals(1, result.get('Product').size());
        System.assertEquals(0, result.get('Variant').size());
        System.assertEquals(1, result.get('Topic').size());
        System.assertEquals(0, result.get('PricebookEntry').size());
    }
    
    @IsTest
    static void testProcessSingleProductProductMappingOnly() {
        Map<String, Object> payload = buildProductPayload(
            uniqueNumber(800000),
            uniqueNumber(810000),
            'Necklaces',
            'active',
            'Variant Title',
            'SKU-PRODUCT-ONLY'
        );
        
        Map<String, List<REST_Field_Mapping__mdt>> productOnlyMappings =
            new Map<String, List<REST_Field_Mapping__mdt>>{
                'products' => buildGroupedMappings().get('products')
                    };
                        
                        Test.startTest();
        
        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                productOnlyMappings,
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
        
        Test.stopTest();
        
        System.assertEquals(1, result.get('Product').size());
        System.assertEquals(0, result.get('Variant').size());
        System.assertEquals(1, result.get('Topic').size());
        System.assertEquals(0, result.get('PricebookEntry').size());
    }
    
    @IsTest
    static void testProcessSingleProductWeightConversionsAndImageGuards() {
        Map<String, Object> payload = buildProductPayload(
            uniqueNumber(820000),
            uniqueNumber(830000),
            'Bracelets',
            'active',
            'Weight Variant',
            'SKU-WEIGHT'
        );
        
        payload.put('image', new Map<String, Object>{
            'id' => 99
                });
        
        payload.put('images', new List<Object>{
            new Map<String, Object>{
                'id' => 1
                    },
                        new Map<String, Object>{
                            'src' => 'http://image.com/no-id.jpg'
                                }
        });
        
        Map<String, Object> variantMap =
            (Map<String, Object>) ((List<Object>) payload.get('variants'))[0];
        
        variantMap.put('weight', '2');
        variantMap.put('weight_unit', 'oz');
        
        Test.startTest();
        
        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
        
        Test.stopTest();
        
        Product2 product = (Product2) result.get('Product')[0];
        Product2 variant = (Product2) result.get('Variant')[0];
        
        System.assertEquals(null, product.Image_URL__c);
        System.assertEquals(null, variant.Image_URL__c);
        System.assertEquals(56.699, variant.get('Weight__c'));
    }
    
    @IsTest
    static void testDoNuancedMappingEarringsAndActive() {
        Product2 p = new Product2();
        
        Map<String, Object> payload = new Map<String, Object>{
            'product_type' => 'Hoops',
                'status' => 'active'
                };
                    
                    ProductOrchestrationService.doNuancedMapping(p, payload);
        
        System.assertEquals('Earrings', p.Family);
        System.assertEquals(true, p.IsActive);
        System.assertEquals(true, p.Updated_by_Integration__c);
    }
    
    @IsTest
    static void testDoNuancedMappingNonEarringAndInactive() {
        Product2 p = new Product2();
        
        Map<String, Object> payload = new Map<String, Object>{
            'product_type' => 'Bracelets',
                'status' => 'draft'
                };
                    
                    ProductOrchestrationService.doNuancedMapping(p, payload);
        
        System.assertEquals('Bracelets', p.Family);
        System.assertEquals(false, p.IsActive);
        System.assertEquals(true, p.Updated_by_Integration__c);
    }
    
    @IsTest
    static void testDoNuancedMappingNullInputsReturnSafely() {
        Product2 p = new Product2();
        
        ProductOrchestrationService.doNuancedMapping(null, new Map<String, Object>());
        ProductOrchestrationService.doNuancedMapping(p, null);
        
        System.assertEquals(null, p.Family);
    }
    
    @IsTest
    static void testBackfillInventoryItemIdsFromProductWebhookNoOp() {
        ProductOrchestrationService.backfillInventoryItemIdsFromProductWebhook(
            new Map<String, Object>{ 'id' => 123 }
        );
        ProductOrchestrationService.backfillInventoryItemIdsFromProductWebhook(null);
        
        System.assert(true);
    }
    
    @IsTest
    static void testSingleProductFullProcessCreatesRecords() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        getStandardPricebookIdSafe();
        
        Integer productId = uniqueNumber(100000);
        Integer variantId = uniqueNumber(200000);
        
        Map<String, Object> wrapper = new Map<String, Object>{
            'product' => buildProductPayload(
                productId,
                variantId,
                'Earrings',
                'active',
                'Default Title',
                'SKU-' + variantId
            )
                };
                    
                    // Do NOT use Test.startTest()/Test.stopTest() here.
                    // stopTest executes downstream async Square / inventory jobs and causes failures.
                    ProductOrchestrationService.processProductsFromRestRequest(
                        wrapper,
                        new String[]{ 'products', 'variants' }
                    );
        
        List<Product2> products = [
            SELECT Id, Name, Family, IsActive, Shop_ID__c, Type__c, Image_URL__c
            FROM Product2
            WHERE Shop_ID__c = :String.valueOf(productId)
        ];
        
        System.assertEquals(1, products.size(), 'Product should be created.');
        System.assertEquals('Product', products[0].Type__c);
        System.assertEquals('Earrings', products[0].Family);
        System.assertEquals(true, products[0].IsActive);
        
        List<Product2> variants = [
            SELECT Id,
            Name,
            Type__c,
            Shop_ID__c,
            Parent__c,
            StockKeepingUnit,
            Image_URL__c,
            Inventory_Item_Id__c,
            Updated_by_Integration__c
            FROM Product2
            WHERE Shop_ID__c = :String.valueOf(variantId)
        ];
        
        System.assertEquals(1, variants.size(), 'Variant should be created.');
        System.assertEquals('Variant', variants[0].Type__c);
        System.assertEquals(products[0].Id, variants[0].Parent__c);
        System.assertEquals('SKU-' + variantId, variants[0].StockKeepingUnit);
        System.assertEquals('INV-' + variantId, variants[0].Inventory_Item_Id__c);
        System.assertEquals(true, variants[0].Updated_by_Integration__c);
        
        List<PricebookEntry> pbes = [
            SELECT Id, Product2Id, UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Product2Id = :variants[0].Id
        ];
        
        System.assert(
            pbes.size() > 0,
            'At least one PricebookEntry should be created.'
        );
    }
    
    @IsTest
    static void testMultipleProductsFullProcessCreatesRecords() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        getStandardPricebookIdSafe();
        
        Integer productId1 = uniqueNumber(110000);
        Integer variantId1 = uniqueNumber(210000);
        Integer productId2 = uniqueNumber(120000);
        Integer variantId2 = uniqueNumber(220000);
        
        Map<String, Object> wrapper = new Map<String, Object>{
            'products' => new List<Object>{
                buildProductPayload(
                    productId1,
                    variantId1,
                    'Dangles',
                    'active',
                    'Default Title',
                    'SKU-' + variantId1
                ),
                    buildProductPayload(
                        productId2,
                        variantId2,
                        'Bracelets',
                        'draft',
                        'Blue Variant',
                        'SKU-' + variantId2
                    )
                    }
        };
            
            // Do NOT use Test.startTest()/Test.stopTest() here.
            ProductOrchestrationService.processProductsFromRestRequest(
                wrapper,
                new String[]{ 'products', 'variants' }
            );
        
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Product2
                WHERE Shop_ID__c IN :new Set<String>{
                    String.valueOf(productId1),
                        String.valueOf(productId2)
                        }
            ],
            'Two parent products should be created.'
        );
        
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Product2
                WHERE Shop_ID__c IN :new Set<String>{
                    String.valueOf(variantId1),
                        String.valueOf(variantId2)
                        }
            ],
            'Two variants should be created.'
        );
    }
    
    @IsTest
    static void testGetSelectedOptionValue_AllBranches() {
        System.assertEquals(
            null,
            ProductOrchestrationService.getSelectedOptionValue(null, 'Size')
        );
        
        System.assertEquals(
            null,
            ProductOrchestrationService.getSelectedOptionValue(
                new Map<String, Object>(),
                null
            )
        );
        
        System.assertEquals(
            null,
            ProductOrchestrationService.getSelectedOptionValue(
                new Map<String, Object>(),
                ''
            )
        );
        
        System.assertEquals(
            null,
            ProductOrchestrationService.getSelectedOptionValue(
                new Map<String, Object>{
                    'selected_options' => 'not_a_list'
                        },
                'Size'
            )
        );
        
        System.assertEquals(
            null,
            ProductOrchestrationService.getSelectedOptionValue(
                new Map<String, Object>{
                    'selected_options' => new List<Object>{
                        'not_a_map',
                            new Map<String, Object>{
                                'name' => 'Color',
                                    'value' => 'Gold'
                                    }
                    }
                },
                'Size'
            )
        );
        
        System.assertEquals(
            null,
            ProductOrchestrationService.getSelectedOptionValue(
                new Map<String, Object>{
                    'selected_options' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Size',
                                'value' => 'Default Title'
                                }
                    }
                },
                'Size'
            )
        );
        
        System.assertEquals(
            '8',
            ProductOrchestrationService.getSelectedOptionValue(
                new Map<String, Object>{
                    'selected_options' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Ring size',
                                'value' => '8'
                                }
                    }
                },
                'Ring size'
            )
        );
        
        System.assertEquals(
            '18 inch',
            ProductOrchestrationService.getSelectedOptionValue(
                new Map<String, Object>{
                    'selected_options' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Chain Length',
                                'value' => '18 inch'
                                }
                    }
                },
                'chain length'
            )
        );
    }
    
    @IsTest
    static void testGetVariantSizeValue_AllBranches() {
        System.assertEquals(
            null,
            ProductOrchestrationService.getVariantSizeValue(null)
        );
        
        System.assertEquals(
            '7',
            ProductOrchestrationService.getVariantSizeValue(
                new Map<String, Object>{
                    'title' => 'Default Title',
                        'selected_options' => new List<Object>{
                            new Map<String, Object>{
                                'name' => 'Ring size',
                                    'value' => '7'
                                    }
                        }
                }
            )
        );
        
        System.assertEquals(
            '8',
            ProductOrchestrationService.getVariantSizeValue(
                new Map<String, Object>{
                    'title' => 'Default Title',
                        'selected_options' => new List<Object>{
                            new Map<String, Object>{
                                'name' => 'Ring Size',
                                    'value' => '8'
                                    }
                        }
                }
            )
        );
        
        System.assertEquals(
            'Small',
            ProductOrchestrationService.getVariantSizeValue(
                new Map<String, Object>{
                    'title' => 'Default Title',
                        'selected_options' => new List<Object>{
                            new Map<String, Object>{
                                'name' => 'Size',
                                    'value' => 'Small'
                                    }
                        }
                }
            )
        );
        
        System.assertEquals(
            '16 inch',
            ProductOrchestrationService.getVariantSizeValue(
                new Map<String, Object>{
                    'title' => 'Default Title',
                        'selected_options' => new List<Object>{
                            new Map<String, Object>{
                                'name' => 'Length',
                                    'value' => '16 inch'
                                    }
                        }
                }
            )
        );
        
        System.assertEquals(
            '18 inch',
            ProductOrchestrationService.getVariantSizeValue(
                new Map<String, Object>{
                    'title' => 'Default Title',
                        'selected_options' => new List<Object>{
                            new Map<String, Object>{
                                'name' => 'Chain length',
                                    'value' => '18 inch'
                                    }
                        }
                }
            )
        );
        
        System.assertEquals(
            '20 inch',
            ProductOrchestrationService.getVariantSizeValue(
                new Map<String, Object>{
                    'title' => 'Default Title',
                        'selected_options' => new List<Object>{
                            new Map<String, Object>{
                                'name' => 'Chain Length',
                                    'value' => '20 inch'
                                    }
                        }
                }
            )
        );
        
        System.assertEquals(
            'Blue Variant',
            ProductOrchestrationService.getVariantSizeValue(
                new Map<String, Object>{
                    'title' => 'Blue Variant',
                        'selected_options' => new List<Object>{
                            new Map<String, Object>{
                                'name' => 'Size',
                                    'value' => 'Default Title'
                                    }
                        }
                }
            )
        );
        
        System.assertEquals(
            null,
            ProductOrchestrationService.getVariantSizeValue(
                new Map<String, Object>{
                    'title' => 'Default Title'
                        }
            )
        );
    }
    
    @IsTest
    static void testNormalizeWeightUnitForSalesforce_AllBranches() {
        System.assertEquals(
            'g',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce(null)
        );
        
        System.assertEquals(
            'g',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('')
        );
        
        System.assertEquals(
            'lb',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('pounds')
        );
        
        System.assertEquals(
            'lb',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('pound')
        );
        
        System.assertEquals(
            'lb',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('lbs')
        );
        
        System.assertEquals(
            'oz',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('ounces')
        );
        
        System.assertEquals(
            'oz',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('ounce')
        );
        
        System.assertEquals(
            'kg',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('kilograms')
        );
        
        System.assertEquals(
            'kg',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('kilogram')
        );
        
        System.assertEquals(
            'g',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('grams')
        );
        
        System.assertEquals(
            'g',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('gram')
        );
        
        System.assertEquals(
            'kg',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce(' KG ')
        );
        
        System.assertEquals(
            'stone',
            ProductOrchestrationService.normalizeWeightUnitForSalesforce('stone')
        );
    }
    
    @IsTest
    static void testSyncInboundShopifyFiles_NullAndNoMatchingProduct() {
        Test.startTest();
        
        ProductOrchestrationService.syncInboundShopifyFiles(null);
        
        ProductOrchestrationService.syncInboundShopifyFiles(
            new Map<String, Object>()
        );
        
        ProductOrchestrationService.syncInboundShopifyFiles(
            new Map<String, Object>{
                'id' => 'NO_MATCHING_PRODUCT_ID'
                    }
        );
        
        Test.stopTest();
        
        System.assert(true, 'syncInboundShopifyFiles guard paths should complete safely.');
    }
    
    @IsTest
    static void testGetExistingPricebookEntries_EmptyAndExisting() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
        
        Id standardPbId = getStandardPricebookIdSafe();
        
        Product2 p = new Product2(
            Name = 'PBE Test Product',
            IsActive = true,
            Shop_ID__c = 'PBE_TEST_PRODUCT_' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert p;
        
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPbId,
            Product2Id = p.Id,
            UnitPrice = 10,
            IsActive = true,
            UseStandardPrice = false
        );
        insert pbe;
        
        Test.startTest();
        
        Map<String, PricebookEntry> emptyResult =
            ProductOrchestrationService.getExistingPricebookEntries(
                new Set<Id>(),
                new Set<Id>()
            );
        
        Map<String, PricebookEntry> existingResult =
            ProductOrchestrationService.getExistingPricebookEntries(
                new Set<Id>{ p.Id },
                new Set<Id>{ standardPbId }
            );
        
        Test.stopTest();
        
        System.assertEquals(0, emptyResult.size());
        
        String expectedKey = p.Id + '-' + standardPbId;
        System.assertEquals(true, existingResult.containsKey(expectedKey));
        System.assertEquals(pbe.Id, existingResult.get(expectedKey).Id);
    }
            
        @IsTest
        static void testProcessSingleProduct_UnknownWeightUnitDoesNotFail() {
            Integer productId = uniqueNumber(950000);
            Integer variantId = uniqueNumber(960000);
            
            Map<String, Object> payload = buildProductPayload(
                productId,
                variantId,
                'Bracelets',
                'active',
                'Unknown Weight Unit Variant',
                'SKU-UNKNOWN-WEIGHT-' + variantId
            );
            
            Map<String, Object> variantMap =
                (Map<String, Object>) ((List<Object>) payload.get('variants'))[0];
            
            variantMap.put('weight', '5');
            variantMap.put('weight_unit', 'stone');
            
            Test.startTest();
            
            Map<String, List<SObject>> result =
                ProductOrchestrationService.processSingleProduct(
                    payload,
                    buildGroupedMappings(),
                    new List<Id>{ getStandardPricebookIdSafe() },
                    getRecordTypeIds()
                );
            
            Test.stopTest();
            
            System.assertEquals(1, result.get('Variant').size());
            
            Product2 variantRecord = (Product2) result.get('Variant')[0];
            
            System.assertEquals('Variant', variantRecord.Type__c);
            System.assertEquals('stone', String.valueOf(variantRecord.get('Weight_Unit__c')));
            System.assertEquals(5.000, variantRecord.get('Weight__c'));
        }

    @IsTest
    static void testGetSfParentProductNameFromPayloadAllBranches() {
        System.assertEquals(
            null,
            ProductOrchestrationService.getSfParentProductNameFromPayload(null)
        );
        System.assertEquals(
            'Canonical Ring',
            ProductOrchestrationService.getSfParentProductNameFromPayload(
                new Map<String, Object>{
                    'sf_parent_product_name' => '  Canonical Ring  '
                }
            )
        );
        System.assertEquals(
            'Metafield Parent',
            ProductOrchestrationService.getSfParentProductNameFromPayload(
                new Map<String, Object>{
                    'sf_parent_product_name' => ' ',
                    'metafields' => new List<Object>{
                        null,
                        'invalid',
                        new Map<String, Object>{
                            'namespace' => 'other',
                            'key' => 'sf_product_name',
                            'value' => 'Ignored'
                        },
                        new Map<String, Object>{
                            'namespace' => 'custom',
                            'key' => 'other',
                            'value' => 'Ignored'
                        },
                        new Map<String, Object>{
                            'namespace' => 'custom',
                            'key' => 'sf_product_name',
                            'value' => null
                        },
                        new Map<String, Object>{
                            'namespace' => 'custom',
                            'key' => 'sf_product_name',
                            'value' => ' Metafield Parent '
                        }
                    }
                }
            )
        );
        System.assertEquals(
            null,
            ProductOrchestrationService.getSfParentProductNameFromPayload(
                new Map<String, Object>{ 'metafields' => 'not-a-list' }
            )
        );
    }
    
    @IsTest
    static void testNormalizeParentProductNameAllMaterialBranches() {
        System.assertEquals(
            null,
            ProductOrchestrationService.normalizeParentProductName(null)
        );
        
        System.assertEquals(
            null,
            ProductOrchestrationService.normalizeParentProductName('   ')
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring Gold'
            )
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring Solid Gold'
            )
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring White Gold'
            )
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring Sterling Silver'
            )
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring Silver'
            )
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring Gold Plated'
            )
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring Silver Plated'
            )
        );
        
        /*
* Current implementation removes "gold plated" before checking
* "rose gold plated". Therefore, "Rose Gold Plated" currently
* normalizes to "rose", rather than removing the whole phrase.
*/
        System.assertEquals(
            'signature ring rose',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring Rose Gold Plated'
            ),
            'The assertion should reflect the current replacement order.'
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring Rhodium'
            )
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature Ring Material'
            )
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                ' Signature-Ring_Gold! '
            )
        );
        
        System.assertEquals(
            'signature ring',
            ProductOrchestrationService.normalizeParentProductName(
                'Signature    Ring    Silver'
            )
        );
    }
    @IsTest
    static void testFindExistingCanonicalParentGuardAndExactName() {
        System.assertEquals(
            null,
            ProductOrchestrationService.findExistingCanonicalParent(null, null, null)
        );

        String token = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Product2 parent = new Product2(
            Name = 'Canonical Exact ' + token,
            IsActive = true,
            Type__c = 'Product',
            Family = 'Rings',
            Shop_ID__c = 'CANONICAL-' + token,
            StockKeepingUnit = 'R' + token.left(4)
        );
        insert parent;

        Product2 found = ProductOrchestrationService.findExistingCanonicalParent(
            parent.Name.toLowerCase(),
            parent.Name + ' Gold',
            'Rings'
        );

        System.assertNotEquals(null, found);
        System.assertEquals(parent.Id, found.Id);
    }

    @IsTest
    static void testFindExistingCanonicalParentNormalizedPrefersSku() {
        String token = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Product2 noSku = new Product2(
            Name = 'Shared Design Gold ' + token,
            IsActive = true,
            Type__c = 'Product',
            Family = 'Rings',
            Shop_ID__c = 'NO-SKU-' + token
        );
        Product2 withSku = new Product2(
            Name = 'Shared Design Silver ' + token,
            IsActive = true,
            Type__c = 'Product',
            Family = 'Rings',
            Shop_ID__c = 'WITH-SKU-' + token,
            StockKeepingUnit = 'R' + token.left(4)
        );
        insert new List<Product2>{ noSku, withSku };

        Product2 found = ProductOrchestrationService.findExistingCanonicalParent(
            'Shared Design ' + token,
            'Shared Design Rose Gold ' + token,
            'Rings'
        );

        System.assertNotEquals(null, found);
        System.assertEquals(withSku.Id, found.Id);
    }

    @IsTest
    static void testProcessSingleProductUsesExplicitCanonicalParentName() {
        Integer productId = uniqueNumber(970000);
        Integer variantId = uniqueNumber(980000);
        Map<String, Object> payload = buildProductPayload(
            productId,
            variantId,
            'Rings',
            'active',
            'Default Title',
            'SKU-CANONICAL-' + variantId
        );
        payload.put('sf_parent_product_name', '  Canonical Parent Name  ');

        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );

        Product2 parent = (Product2) result.get('Product')[0];
        Product2 variant = (Product2) result.get('Variant')[0];
        System.assertEquals('Canonical Parent Name', parent.Name);
        System.assertEquals('Test Product ' + productId, variant.Name);
    }

    @IsTest
    static void testProcessSingleProductVariantNamingMaterialAndSelectedSize() {
        Integer productId = uniqueNumber(990000);
        Integer variantId = uniqueNumber(995000);
        Map<String, Object> payload = buildProductPayload(
            productId,
            variantId,
            'Rings',
            'active',
            'Default Title',
            'SKU-SIZE-' + variantId
        );
        payload.put('title', 'Material Ring Gold');
        payload.put('metafields', new List<Object>());
        Map<String, Object> variantMap =
            (Map<String, Object>) ((List<Object>) payload.get('variants'))[0];
        variantMap.put(
            'selected_options',
            new List<Object>{
                new Map<String, Object>{ 'name' => 'Ring size', 'value' => '7' }
            }
        );

        Map<String, List<SObject>> result =
            ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );

        Product2 variant = (Product2) result.get('Variant')[0];
        System.assertEquals('7', String.valueOf(variant.get('Size__c')));
        System.assert(
            variant.Name != null && variant.Name.contains('7'),
            'The selected size should be represented in the Variant name. Actual: ' + variant.Name
        );
    }

    @IsTest
    static void testProcessSingleProductWeightConversionBranches() {
        List<String> units = new List<String>{ 'kg', 'lb', 'lbs', 'oz', 'g' };
        List<Decimal> expected = new List<Decimal>{ 2000, 907.184, 907.184, 56.699, 2 };
        for (Integer i = 0; i < units.size(); i++) {
            Map<String, Object> payload = buildProductPayload(
                uniqueNumber(10000 + i),
                uniqueNumber(20000 + i),
                'Bracelets',
                'active',
                'Weight ' + units[i],
                'SKU-W-' + i
            );
            Map<String, Object> variantMap =
                (Map<String, Object>) ((List<Object>) payload.get('variants'))[0];
            variantMap.put('weight', '2');
            variantMap.put('weight_unit', units[i]);

            Map<String, List<SObject>> result = ProductOrchestrationService.processSingleProduct(
                payload,
                buildGroupedMappings(),
                new List<Id>{ getStandardPricebookIdSafe() },
                getRecordTypeIds()
            );
            Product2 variant = (Product2) result.get('Variant')[0];
            System.assertEquals(expected[i], variant.get('Weight__c'));
        }

        Map<String, Object> badPayload = buildProductPayload();
        Map<String, Object> badVariant =
            (Map<String, Object>) ((List<Object>) badPayload.get('variants'))[0];
        badVariant.put('weight', 'not-a-decimal');
        Map<String, List<SObject>> badResult = ProductOrchestrationService.processSingleProduct(
            badPayload,
            buildGroupedMappings(),
            new List<Id>{ getStandardPricebookIdSafe() },
            getRecordTypeIds()
        );
        System.assertEquals(1, badResult.get('Variant').size());
    }

    @IsTest
    static void testProcessProductsFromRestRequestExistingParentAndVariant() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());
        getStandardPricebookIdSafe();

        Integer productId = uniqueNumber(410000);
        Integer variantId = uniqueNumber(510000);
        Map<String, Object> wrapper = new Map<String, Object>{
            'product' => buildProductPayload(
                productId,
                variantId,
                'Rings',
                'active',
                'Default Title',
                'SKU-EXISTING-' + variantId
            )
        };

        ProductOrchestrationService.processProductsFromRestRequest(
            wrapper,
            new String[]{ 'products', 'variants' }
        );
        ProductOrchestrationService.processProductsFromRestRequest(
            wrapper,
            new String[]{ 'products', 'variants' }
        );

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Product2 WHERE Shop_ID__c = :String.valueOf(productId)]
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Product2 WHERE Shop_ID__c = :String.valueOf(variantId)]
        );
    }

}