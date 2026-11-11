@IsTest
global class GlobalHttpMock implements HttpCalloutMock {
    
    global static String mockMode = 'SUCCESS';
    
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/json');
        
        String endpoint = req.getEndpoint();
        String body = req.getBody();


        // ============================================================
        // PRIORITY: Square Catalog Price Sync test modes
        // ============================================================
        //
        // These responses support SquareCatalogPriceSyncServiceTest.
        // They are intentionally evaluated before the older generic
        // Square/Shopify branches below.
        //
        // No existing mock logic below has been removed or changed.
        // ============================================================

        if (
            endpoint != null &&
            endpoint.contains('/v2/catalog/object/') &&
            req.getMethod() == 'GET'
        ) {
            if (mockMode == 'SQUARE_CATALOG_HTTP_ERROR') {
                res.setStatusCode(500);
                res.setBody(
                    '{"errors":[{"code":"INTERNAL_SERVER_ERROR",' +
                    '"detail":"Simulated Square catalog failure"}]}'
                );
                return res;
            }

            if (mockMode == 'SQUARE_CATALOG_NO_OBJECT') {
                res.setStatusCode(200);
                res.setBody('{}');
                return res;
            }

            if (mockMode == 'SQUARE_CATALOG_NULL_OBJECT') {
                res.setStatusCode(200);
                res.setBody(
                    '{"object":null}'
                );
                return res;
            }

            if (mockMode == 'SQUARE_CATALOG_NO_VARIATION_DATA') {
                res.setStatusCode(200);
                res.setBody(
                    '{"object":{' +
                    '"id":"VAR_TEST",' +
                    '"type":"ITEM_VARIATION"' +
                    '}}'
                );
                return res;
            }

            if (mockMode == 'SQUARE_CATALOG_NO_PRICE_MONEY') {
                res.setStatusCode(200);
                res.setBody(
                    '{"object":{' +
                    '"id":"VAR_TEST",' +
                    '"type":"ITEM_VARIATION",' +
                    '"item_variation_data":{}' +
                    '}}'
                );
                return res;
            }

            if (mockMode == 'SQUARE_CATALOG_NULL_PRICE_AMOUNT') {
                res.setStatusCode(200);
                res.setBody(
                    '{"object":{' +
                    '"id":"VAR_TEST",' +
                    '"type":"ITEM_VARIATION",' +
                    '"item_variation_data":{' +
                    '"price_money":{"currency":"USD"}' +
                    '}' +
                    '}}'
                );
                return res;
            }

            if (mockMode == 'SQUARE_CATALOG_BAD_PRICE') {
                res.setStatusCode(200);
                res.setBody(
                    '{"object":{' +
                    '"id":"VAR_TEST",' +
                    '"type":"ITEM_VARIATION",' +
                    '"item_variation_data":{' +
                    '"price_money":{' +
                    '"amount":"NOT_A_NUMBER",' +
                    '"currency":"USD"' +
                    '}' +
                    '}' +
                    '}}'
                );
                return res;
            }

            if (mockMode == 'SQUARE_CATALOG_SAME_PRICE') {
                res.setStatusCode(200);
                res.setBody(
                    '{"object":{' +
                    '"id":"VAR_TEST",' +
                    '"type":"ITEM_VARIATION",' +
                    '"item_variation_data":{' +
                    '"price_money":{' +
                    '"amount":1000,' +
                    '"currency":"USD"' +
                    '}' +
                    '}' +
                    '}}'
                );
                return res;
            }

            if (mockMode == 'SQUARE_CATALOG_NEGATIVE_PRICE') {
                res.setStatusCode(200);
                res.setBody(
                    '{"object":{' +
                    '"id":"VAR_TEST",' +
                    '"type":"ITEM_VARIATION",' +
                    '"item_variation_data":{' +
                    '"price_money":{' +
                    '"amount":-100,' +
                    '"currency":"USD"' +
                    '}' +
                    '}' +
                    '}}'
                );
                return res;
            }

            if (
                mockMode == 'SQUARE_CATALOG_SUCCESS' ||
                mockMode == 'SUCCESS'
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"object":{' +
                    '"id":"VAR_TEST",' +
                    '"type":"ITEM_VARIATION",' +
                    '"item_variation_data":{' +
                    '"price_money":{' +
                    '"amount":2500,' +
                    '"currency":"USD"' +
                    '}' +
                    '}' +
                    '}}'
                );
                return res;
            }
        }


        // ============================================================
        // PRIORITY: current ShopifyProductPageBatch test modes
        // ============================================================
        //
        // These mode-specific responses are intentionally evaluated
        // before all older generic Shopify GraphQL/REST branches.
        // No existing mock logic below has been removed or changed.
        // ============================================================

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_HTTP_ERROR') {
            res.setStatusCode(500);
            res.setBody('{"errors":[{"message":"Simulated GraphQL HTTP failure"}]}');
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_BLANK_BODY') {
            res.setStatusCode(200);
            res.setBody('');
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_INVALID_ROOT') {
            res.setStatusCode(200);
            res.setBody('[{"invalid":true}]');
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_ERRORS') {
            res.setStatusCode(200);
            res.setBody('{"errors":[{"message":"Simulated Shopify GraphQL error"}]}');
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_NO_DATA') {
            res.setStatusCode(200);
            res.setBody('{"errors":[]}');
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_NO_PRODUCTS') {
            res.setStatusCode(200);
            res.setBody('{"data":{}}');
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_PRODUCTS') {
            res.setStatusCode(200);
            res.setBody(
                '{"data":{"products":{' +
                '"nodes":[' +
                '{"id":"gid://shopify/Product/1001","legacyResourceId":1001},' +
                '{"id":"gid://shopify/Product/1002","legacyResourceId":"1002.0"}' +
                '],' +
                '"pageInfo":{"hasNextPage":false,"endCursor":null}' +
                '}}}'
            );
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_MIXED_NODES') {
            res.setStatusCode(200);
            res.setBody(
                '{"data":{"products":{' +
                '"nodes":[' +
                'null,' +
                '"not-a-map",' +
                '{"id":"gid://shopify/Product/2001","legacyResourceId":null},' +
                '{"id":"gid://shopify/Product/2002","legacyResourceId":2002}' +
                '],' +
                '"pageInfo":{"hasNextPage":false,"endCursor":null}' +
                '}}}'
            );
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_HAS_NEXT_NO_CURSOR') {
            res.setStatusCode(200);
            res.setBody(
                '{"data":{"products":{' +
                '"nodes":[],' +
                '"pageInfo":{"hasNextPage":true,"endCursor":null}' +
                '}}}'
            );
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_WITH_NEXT') {
            res.setStatusCode(200);
            res.setBody(
                '{"data":{"products":{' +
                '"nodes":[],' +
                '"pageInfo":{"hasNextPage":true,"endCursor":"NEXT_CURSOR"}' +
                '}}}'
            );
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_GRAPHQL_EMPTY') {
            res.setStatusCode(200);
            res.setBody(
                '{"data":{"products":{' +
                '"nodes":[],' +
                '"pageInfo":{"hasNextPage":false,"endCursor":null}' +
                '}}}'
            );
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_REST_HTTP_ERROR') {
            res.setStatusCode(500);
            res.setBody('{"error":"Simulated Shopify REST product failure"}');
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_REST_NO_PRODUCT') {
            res.setStatusCode(200);
            res.setBody('{"product":null}');
            return res;
        }

        if (mockMode == 'PRODUCT_PAGE_REST_PRODUCT') {
            res.setStatusCode(200);
            res.setBody(
                '{"product":{' +
                '"id":1001,' +
                '"title":"Product Page Batch Test",' +
                '"handle":"product-page-batch-test",' +
                '"product_type":"Ring",' +
                '"status":"draft",' +
                '"variants":[]' +
                '}}'
            );
            return res;
        }

        // Current ShopifyProductPageBatch uses GraphQL for page discovery.
        // SUCCESS must return the products connection for that query rather
        // than fall through to the generic product mutation response.
        if (
            mockMode == 'SUCCESS' &&
            endpoint != null &&
            endpoint.contains('/admin/api/2026-04/graphql.json') &&
            req.getMethod() == 'POST' &&
            body != null &&
            body.contains('ProductBackfill')
        ) {
            res.setStatusCode(200);
            res.setBody(
                '{"data":{"products":{' +
                '"nodes":[],' +
                '"pageInfo":{"hasNextPage":false,"endCursor":null}' +
                '}}}'
            );
            return res;
        }

        // Current execute() fetches one REST product by legacy ID.
        if (
            mockMode == 'SUCCESS' &&
            endpoint != null &&
            endpoint.contains('/admin/api/2026-04/products/') &&
            endpoint.endsWith('.json') &&
            req.getMethod() == 'GET'
        ) {
            res.setStatusCode(200);
            res.setBody('{"product":null}');
            return res;
        }
        
        // ============================================================
        // ShopifyProductPageBatch REST responses
        // ============================================================
        
        if (
            endpoint != null &&
            endpoint.contains('/admin/api/') &&
            endpoint.contains('/products.json') &&
            req.getMethod() == 'GET'
        ) {
            if (mockMode == 'PRODUCT_PAGE_HTTP_ERROR') {
                res.setStatusCode(500);
                res.setBody(
                    '{"error":"Simulated Shopify product-page failure"}'
                );
                return res;
            }
            
            if (mockMode == 'PRODUCT_PAGE_BLANK_BODY') {
                res.setStatusCode(200);
                res.setBody('');
                return res;
            }
            
            if (mockMode == 'PRODUCT_PAGE_INVALID_ROOT') {
                res.setStatusCode(200);
                res.setBody(
                    '[{"id":1001}]'
                );
                return res;
            }
            
            if (mockMode == 'PRODUCT_PAGE_INVALID_PRODUCTS') {
                res.setStatusCode(200);
                res.setBody(
                    '{"products":"not-a-list"}'
                );
                return res;
            }
            
            if (mockMode == 'PRODUCT_PAGE_MIXED_PRODUCTS') {
                res.setStatusCode(200);
                res.setBody(
                    '{"products":[' +
                    'null,' +
                    '"invalid-product",' +
                    '{"id":1001,"title":"Backfill Product","variants":[]}' +
                    ']}'
                );
                return res;
            }
            
            if (mockMode == 'PRODUCT_PAGE_WITH_NEXT') {
                res.setStatusCode(200);
                res.setBody(
                    '{"products":[]}'
                );
                
                /*
* Return another page only for the first-page endpoint.
* This prevents recursive Batch execution in tests.
*/
                if (!endpoint.contains('page_info=NEXT_PAGE')) {
                    res.setHeader(
                        'Link',
                        '<https://test-store.myshopify.com/admin/api/2026-04/' +
                        'products.json?limit=5&page_info=NEXT_PAGE>; rel="next"'
                    );
                }
                
                return res;
            }
            
            res.setStatusCode(200);
            res.setBody(
                '{"products":[]}'
            );
            return res;
        }
        
        // ============================================================
        // Square Inventory Migration API
        // ============================================================
        
        if (
            endpoint != null &&
            endpoint.contains('/v2/inventory/changes/batch-create')
        ) {
            if (mockMode == 'SQUARE_INVENTORY_HTTP_ERROR') {
                res.setStatusCode(500);
                res.setBody(
                    '{"errors":[{"code":"INTERNAL_SERVER_ERROR",' +
                    '"detail":"Simulated Square inventory failure"}]}'
                );
                return res;
            }
            
            if (mockMode == 'SQUARE_INVENTORY_API_ERRORS') {
                res.setStatusCode(200);
                res.setBody(
                    '{"errors":[{"code":"BAD_REQUEST",' +
                    '"detail":"Simulated inventory validation error"}]}'
                );
                return res;
            }
            
            if (mockMode == 'SQUARE_INVENTORY_INVALID_ROOT') {
                res.setStatusCode(200);
                res.setBody('[{"status":"invalid-root"}]');
                return res;
            }
            
            if (mockMode == 'SQUARE_INVENTORY_BLANK_BODY') {
                res.setStatusCode(200);
                res.setBody('');
                return res;
            }
            
            res.setStatusCode(200);
            res.setBody(
                '{"counts":[],"errors":[]}'
            );
            return res;
        }
        
        // ============================================================
        // Shopify REST backfill calls
        // Added for ShopifyBackfillService tests.
        // Existing GlobalHttpMock logic below remains unchanged.
        // ============================================================
        
        if (
            endpoint != null &&
            endpoint.contains('/admin/api/2026-04/orders.json') &&
            req.getMethod() == 'GET'
        ) {
            if (mockMode == 'BACKFILL_HTTP_ERROR') {
                res.setStatusCode(500);
                res.setBody('{"error":"Simulated Shopify failure"}');
                return res;
            }
            
            if (mockMode == 'BACKFILL_BLANK_BODY') {
                res.setBody('');
                return res;
            }
            
            if (mockMode == 'BACKFILL_INVALID_ROOT') {
                res.setBody('[{"id":1}]');
                return res;
            }
            
            if (mockMode == 'BACKFILL_INVALID_ORDERS') {
                res.setBody('{"orders":"not-a-list"}');
                return res;
            }
            
            if (mockMode == 'BACKFILL_PAGINATION') {
                res.setBody('{"orders":[]}');
                res.setHeader(
                    'Link',
                    '<https://test-store.myshopify.com/admin/api/2026-04/' +
                    'orders.json?limit=5&page_info=NEXT_PAGE>; rel="next"'
                );
                return res;
            }
            
            res.setBody('{"orders":[]}');
            return res;
        }
        
        if (
            endpoint != null &&
            endpoint.contains('/admin/api/2026-04/custom_collections.json') &&
            req.getMethod() == 'GET'
        ) {
            res.setBody('{"custom_collections":[]}');
            return res;
        }
        
        if (
            endpoint != null &&
            endpoint.contains('/admin/api/2026-04/smart_collections.json') &&
            req.getMethod() == 'GET'
        ) {
            res.setBody('{"smart_collections":[]}');
            return res;
        }
        
        if (
            endpoint != null &&
            endpoint.contains('/admin/api/2026-04/inventory_levels.json') &&
            req.getMethod() == 'GET'
        ) {
            res.setBody('{"inventory_levels":[]}');
            return res;
        }
        
        if (
            endpoint != null &&
            endpoint.contains('/admin/api/2026-04/products.json') &&
            req.getMethod() == 'GET'
        ) {
            res.setBody('{"products":[]}');
            return res;
        }
        
        // Product image REST calls
        if (endpoint != null && endpoint.contains('/images.json')) {
            if (req.getMethod() == 'GET') {
                res.setBody(
                    '{"images":[{"id":111,"src":"https://cdn.shopify.com/files/Duplicate_Image.jpg?v=123"}]}'
                );
                return res;
            }
            
            if (req.getMethod() == 'POST') {
                res.setBody(
                    '{"image":{"id":222,"src":"https://cdn.shopify.com/files/Uploaded_Image.jpg"}}'
                );
                return res;
            }
        }
        
        /*
* IMPORTANT:
* This block MUST come before productVariant query.
* productVariantsBulkUpdate contains the substring productVariant.
*/
        if (body != null && body.contains('productVariantsBulkUpdate')) {
            res.setBody(
                '{"data":{"productVariantsBulkUpdate":{' +
                '"product":{"id":"gid://shopify/Product/123"},' +
                '"productVariants":[{"id":"gid://shopify/ProductVariant/456","title":"Default Title","sku":"SKU-1"}],' +
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
                '"product":{"id":"gid://shopify/Product/123","title":"Updated Product"},' +
                '"userErrors":[]' +
                '}}}'
            );
            return res;
        }
        
        /*
* Inventory pull query.
* Use a stricter check than contains('productVariant'), otherwise it catches
* productVariantsBulkUpdate by mistake.
*/
        if (
            body != null &&
            body.contains('query GetVariantInventory') &&
            body.contains('productVariant(id:')
        ) {
            if (mockMode == 'NULL_DATA') {
                res.setBody('{"data":null}');
                return res;
            }
            
            if (mockMode == 'NO_VARIANT') {
                res.setBody('{"data":{"productVariant":null}}');
                return res;
            }
            
            if (mockMode == 'NO_INVENTORY_ITEM') {
                res.setBody(
                    '{"data":{"productVariant":{' +
                    '"id":"gid://shopify/ProductVariant/111",' +
                    '"inventoryItem":null' +
                    '}}}'
                );
                return res;
            }
            
            if (mockMode == 'NO_INVENTORY_LEVELS') {
                res.setBody(
                    '{"data":{"productVariant":{' +
                    '"id":"gid://shopify/ProductVariant/111",' +
                    '"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/999",' +
                    '"sku":"SKU-1",' +
                    '"inventoryLevels":null' +
                    '}' +
                    '}}}'
                );
                return res;
            }
            
            if (mockMode == 'NO_MATCHING_LOCATION') {
                res.setBody(
                    '{"data":{"productVariant":{' +
                    '"id":"gid://shopify/ProductVariant/111",' +
                    '"inventoryItem":{' +
                    '"id":"gid://shopify/InventoryItem/999",' +
                    '"sku":"SKU-1",' +
                    '"inventoryLevels":{"nodes":[{' +
                    '"id":"gid://shopify/InventoryLevel/1",' +
                    '"location":{"id":"gid://shopify/Location/NO_MATCH","name":"Missing Location"},' +
                    '"quantities":[{"name":"available","quantity":7},{"name":"on_hand","quantity":9}]' +
                    '}]}' +
                    '}' +
                    '}}}'
                );
                return res;
            }
            
            res.setBody(
                '{"data":{"productVariant":{' +
                '"id":"gid://shopify/ProductVariant/111",' +
                '"inventoryItem":{' +
                '"id":"gid://shopify/InventoryItem/999",' +
                '"sku":"SKU-1",' +
                '"inventoryLevels":{"nodes":[{' +
                '"id":"gid://shopify/InventoryLevel/1",' +
                '"location":{"id":"gid://shopify/Location/LOC1","name":"Main"},' +
                '"quantities":[' +
                '{"name":"available","quantity":7},' +
                '{"name":"on_hand","quantity":9},' +
                '{"name":"committed","quantity":2},' +
                '{"name":"incoming","quantity":3}' +
                ']' +
                '}]}' +
                '}' +
                '}}}'
            );
            return res;
        }
        
        if (body != null && body.contains('collectionCreate')) {
            res.setBody(
                '{"data":{"collectionCreate":{"collection":{"id":"gid://shopify/Collection/123","legacyResourceId":"123"},"userErrors":[]}}}'
            );
            return res;
        }
        
        if (body != null && body.contains('collectionUpdate')) {
            res.setBody(
                '{"data":{"collectionUpdate":{"collection":{"id":"gid://shopify/Collection/123"},"userErrors":[]}}}'
            );
            return res;
        }
        
        if (body != null && body.contains('collectionAddProducts')) {
            res.setBody(
                '{"data":{"collectionAddProducts":{"collection":{"id":"gid://shopify/Collection/123"},"userErrors":[]}}}'
            );
            return res;
        }
        
        if (body != null && body.contains('collectionRemoveProducts')) {
            res.setBody(
                '{"data":{"collectionRemoveProducts":{"job":{"id":"gid://shopify/Job/1"},"userErrors":[]}}}'
            );
            return res;
        }
        
        if (body != null && body.contains('collection(')) {
            res.setBody(
                '{"data":{"collection":{"id":"gid://shopify/Collection/123","title":"Pulled Collection","descriptionHtml":"Desc","ruleSet":null,"products":{"nodes":[]}}}}'
            );
            return res;
        }
        
        if (body != null && body.contains('orderCreate')) {
            if (mockMode == 'NO_DATA') {
                res.setBody('{"errors":[{"message":"bad"}]}');
                return res;
            }
            
            if (mockMode == 'NO_ORDER_CREATE') {
                res.setBody('{"data":{}}');
                return res;
            }
            
            if (mockMode == 'NULL_ORDER_CREATE') {
                res.setBody('{"data":{"orderCreate":null}}');
                return res;
            }
            
            if (mockMode == 'USER_ERRORS') {
                res.setBody(
                    '{"data":{"orderCreate":{"userErrors":[{"field":["order"],"message":"Error"}],"order":null}}}'
                );
                return res;
            }
            
            if (mockMode == 'NO_ORDER_ID') {
                res.setBody(
                    '{"data":{"orderCreate":{"userErrors":[],"order":{"name":"#1001"}}}}'
                );
                return res;
            }
            
            if (mockMode == 'NO_LINE_ITEMS') {
                res.setBody(
                    '{"data":{"orderCreate":{"userErrors":[],"order":{"id":"gid://shopify/Order/999","name":"#1001"}}}}'
                );
                return res;
            }
            
            res.setBody(
                '{"data":{"orderCreate":{"userErrors":[],"order":{' +
                '"id":"gid://shopify/Order/999",' +
                '"name":"#1001",' +
                '"lineItems":{"nodes":[' +
                '{"id":"gid://shopify/LineItem/111","quantity":1,"title":"Item 1"}' +
                ']}' +
                '}}}}'
            );
            return res;
        }
        
        if (
            body != null &&
            (
                body.contains('refundCreate') ||
                body.contains('RefundOrder') ||
                body.contains('RefundInput')
            )
        ) {
            res.setBody(
                '{"data":{"refundCreate":{' +
                '"refund":{"id":"gid://shopify/Refund/1"},' +
                '"userErrors":[]' +
                '}}}'
            );
            return res;
        }
        
        if (endpoint != null && endpoint.contains('/team-members/')) {
            if (endpoint.contains('INVALID')) {
                res.setStatusCode(400);
                res.setBody('{"error":"Invalid team member"}');
                return res;
            }
            
            res.setBody(
                '{"team_member":{"id":"TEAM_MEMBER_123","given_name":"John","family_name":"Doe"}}'
            );
            return res;
        }
        
        if (endpoint != null && endpoint.contains('/payments/')) {
            res.setBody(
                '{"payment":{' +
                '"id":"PAYMENT_ID_123456789012345",' +
                '"order_id":"ORDER_ID_123456789012345",' +
                '"team_member_id":"TEAM_MEMBER_123",' +
                '"location_id":"LOCATION_123",' +
                '"receipt_url":"https://example.com/receipt",' +
                '"amount_money":{"amount":2500,"currency":"USD"}' +
                '}}'
            );
            return res;
        }
        
        // Safe default GraphQL response
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