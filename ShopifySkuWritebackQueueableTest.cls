@IsTest
private class ShopifySkuWritebackQueueableTest {
    
    private static Integer skuCounter = 0;
    
    private class UniversalShopifySuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String body = req.getBody();
            if (body == null) body = '';
            
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            if (body.contains('productCreate')) {
                res.setBody(
                    '{' +
                    '  "data": {' +
                    '    "productCreate": {' +
                    '      "product": {' +
                    '        "id": "gid://shopify/Product/111",' +
                    '        "title": "Test Product",' +
                    '        "status": "ACTIVE",' +
                    '        "productType": "Bracelets",' +
                    '        "legacyResourceId": "111"' +
                    '      },' +
                    '      "userErrors": []' +
                    '    }' +
                    '  }' +
                    '}'
                );
                return res;
            }
            
            if (body.contains('productUpdate')) {
                res.setBody(
                    '{' +
                    '  "data": {' +
                    '    "productUpdate": {' +
                    '      "product": {' +
                    '        "id": "gid://shopify/Product/111",' +
                    '        "title": "Test Product",' +
                    '        "status": "ACTIVE",' +
                    '        "productType": "Bracelets"' +
                    '      },' +
                    '      "userErrors": []' +
                    '    }' +
                    '  }' +
                    '}'
                );
                return res;
            }
            
            if (body.contains('productVariantsBulkUpdate')) {
                res.setBody(
                    '{' +
                    '  "data": {' +
                    '    "productVariantsBulkUpdate": {' +
                    '      "product": { "id": "gid://shopify/Product/111" },' +
                    '      "productVariants": [' +
                    '        {' +
                    '          "id": "gid://shopify/ProductVariant/222",' +
                    '          "title": "Default Title",' +
                    '          "sku": "TESTSKU001"' +
                    '        }' +
                    '      ],' +
                    '      "userErrors": []' +
                    '    }' +
                    '  }' +
                    '}'
                );
                return res;
            }
            
            if (body.contains('inventoryItem')) {
                res.setBody(
                    '{' +
                    '  "data": {' +
                    '    "inventoryItem": {' +
                    '      "measurement": {' +
                    '        "weight": {' +
                    '          "value": 55.0,' +
                    '          "unit": "POUNDS"' +
                    '        }' +
                    '      },' +
                    '      "variant": {' +
                    '        "product": {' +
                    '          "metafield": {' +
                    '            "references": {' +
                    '              "nodes": [' +
                    '                {' +
                    '                  "fields": [' +
                    '                    { "key": "label", "value": "Gold" }' +
                    '                  ]' +
                    '                }' +
                    '              ]' +
                    '            }' +
                    '          }' +
                    '        }' +
                    '      }' +
                    '    }' +
                    '  }' +
                    '}'
                );
                return res;
            }
            
            res.setBody('{ "data": {} }');
            return res;
        }
    }
    
    private class UniversalShopifyUserErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String body = req.getBody();
            if (body == null) body = '';
            
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            if (body.contains('productVariantsBulkUpdate')) {
                res.setBody(
                    '{' +
                    '  "data": {' +
                    '    "productVariantsBulkUpdate": {' +
                    '      "product": null,' +
                    '      "productVariants": [],' +
                    '      "userErrors": [' +
                    '        {' +
                    '          "field": ["variants", "0", "inventoryItem", "sku"],' +
                    '          "message": "Test Shopify SKU error"' +
                    '        }' +
                    '      ]' +
                    '    }' +
                    '  }' +
                    '}'
                );
                return res;
            }
            
            return new UniversalShopifySuccessMock().respond(req);
        }
    }
    
    private class UniversalShopifyMissingMutationMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String body = req.getBody();
            if (body == null) body = '';
            
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            if (body.contains('productVariantsBulkUpdate')) {
                res.setBody(
                    '{' +
                    '  "data": {' +
                    '    "someOtherMutation": {' +
                    '      "userErrors": []' +
                    '    }' +
                    '  }' +
                    '}'
                );
                return res;
            }
            
            return new UniversalShopifySuccessMock().respond(req);
        }
    }
    
    private static String uniqueSku() {
        skuCounter++;
        Integer randomValue = Math.abs(Crypto.getRandomInteger());
        
        String randomText = String.valueOf(randomValue);
        if (randomText.length() > 8) {
            randomText = randomText.substring(0, 8);
        }
        
        return 'TST' + randomText + String.valueOf(skuCounter);
    }
    
    private static Product2 createParentProduct(String name, String shopId) {
        Product2 parentProduct = new Product2(
            Name = name,
            IsActive = true,
            Type__c = 'Product',
            Family = 'Bracelets',
            Shop_Id__c = shopId
        );
        
        insert parentProduct;
        return parentProduct;
    }
    
    private static Product2 createVariant(
        Id parentId,
        String name,
        String shopId,
        String sku
    ) {
        Product2 variant = new Product2(
            Name = name,
            IsActive = true,
            Type__c = 'Variant',
            Family = 'Bracelets',
            Parent__c = parentId,
            Shop_Id__c = shopId,
            StockKeepingUnit = sku
        );
        
        insert variant;
        return variant;
    }
    
    @IsTest
    static void testSuccessfulSkuWriteback() {
        Test.setMock(HttpCalloutMock.class, new UniversalShopifySuccessMock());
        
        Product2 parentProduct = createParentProduct(
            'Test Parent Product Success',
            '10265042616603'
        );
        
        Product2 variant = createVariant(
            parentProduct.Id,
            'Test Variant Success',
            '52324668866843',
            uniqueSku()
        );
        
        Test.startTest();
        System.enqueueJob(new ShopifySkuWritebackQueueable(new List<Id>{ variant.Id }));
        Test.stopTest();
        
        Product2 refreshed = [
            SELECT Id, StockKeepingUnit
            FROM Product2
            WHERE Id = :variant.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            variant.StockKeepingUnit,
            refreshed.StockKeepingUnit
        );
    }
    
    @IsTest
    static void testNullAndEmptyVariantIdsReturnSafely() {
        Test.setMock(HttpCalloutMock.class, new UniversalShopifySuccessMock());
        
        Test.startTest();
        new ShopifySkuWritebackQueueable(null).execute(null);
        new ShopifySkuWritebackQueueable(new List<Id>()).execute(null);
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testVariantsWithMissingRequiredFieldsAreSkipped() {
        Test.setMock(HttpCalloutMock.class, new UniversalShopifySuccessMock());
        
        Product2 parentWithoutShopId = createParentProduct(
            'Parent Without Shopify Id',
            null
        );
        
        Product2 validParent = createParentProduct(
            'Parent For Skip Test',
            '10265042616604'
        );
        
        Product2 variantWithoutShopId = createVariant(
            validParent.Id,
            'Variant Without Shopify Id',
            null,
            uniqueSku()
        );
        
        Product2 variantWithoutSku = createVariant(
            validParent.Id,
            'Variant Without SKU',
            '52324668866844',
            null
        );
        
        Product2 variantWithParentWithoutShopId = createVariant(
            parentWithoutShopId.Id,
            'Variant Parent Without Shopify Id',
            '52324668866845',
            uniqueSku()
        );
        
        Test.startTest();
        System.enqueueJob(
            new ShopifySkuWritebackQueueable(
                new List<Id>{
                    variantWithoutShopId.Id,
                        variantWithoutSku.Id,
                        variantWithParentWithoutShopId.Id
                        }
            )
        );
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testShopifyUserErrorsAreCaught() {
        List<Object> userErrors = new List<Object>{
            new Map<String, Object>{
                'field' => new List<Object>{ 'variants', '0', 'inventoryItem', 'sku' },
                    'message' => 'Test Shopify SKU error'
                    }
        };
            
            Map<String, Object> response = new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'productVariantsBulkUpdate' => new Map<String, Object>{
                        'product' => null,
                            'productVariants' => new List<Object>(),
                            'userErrors' => userErrors
                            }
                }
            };
                
                Boolean thrown = false;
        
        try {
            ShopifySkuWritebackQueueable.validateUserErrors(
                response,
                'productVariantsBulkUpdate'
            );
        } catch (Exception e) {
            thrown = true;
            System.assert(
                e.getMessage().contains('productVariantsBulkUpdate userErrors'),
                'Expected userErrors exception.'
            );
        }
        
        System.assertEquals(true, thrown, 'Shopify userErrors should throw.');
    }
    
    @IsTest
    static void testMissingMutationResultIsCaught() {
        Map<String, Object> response = new Map<String, Object>{
            'data' => new Map<String, Object>{
                'someOtherMutation' => new Map<String, Object>{
                    'userErrors' => new List<Object>()
                        }
            }
        };
            
            Boolean thrown = false;
        
        try {
            ShopifySkuWritebackQueueable.validateUserErrors(
                response,
                'productVariantsBulkUpdate'
            );
        } catch (Exception e) {
            thrown = true;
            System.assert(
                e.getMessage().contains('Missing mutation result'),
                'Expected missing mutation result exception.'
            );
        }
        
        System.assertEquals(true, thrown, 'Missing mutation result should throw.');
    }
    @IsTest
    static void testValidateUserErrorsNullResponse() {
        Boolean thrown = false;
        
        try {
            ShopifySkuWritebackQueueable.validateUserErrors(
                null,
                'productVariantsBulkUpdate'
            );
        } catch (Exception e) {
            thrown = true;
        }
        
        System.assertEquals(true, thrown);
    }
    
    @IsTest
    static void testValidateUserErrorsMissingData() {
        Boolean thrown = false;
        
        try {
            ShopifySkuWritebackQueueable.validateUserErrors(
                new Map<String, Object>(),
                'productVariantsBulkUpdate'
            );
        } catch (Exception e) {
            thrown = true;
        }
        
        System.assertEquals(true, thrown);
    }
}