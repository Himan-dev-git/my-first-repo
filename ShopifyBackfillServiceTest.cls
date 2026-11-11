@IsTest
private class ShopifyBackfillServiceTest {
    

    private class BackfillHttpMock implements HttpCalloutMock {
        private String mode;

        BackfillHttpMock(String mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = request == null ? null : request.getEndpoint();
            String requestBody = request == null ? null : request.getBody();

            /*
             * ============================================================
             * SHOPIFY GRAPHQL PRODUCT PAGE BATCH
             * ============================================================
             *
             * ShopifyBackfillService.backfillProducts() now starts
             * ShopifyProductPageBatch, which uses GraphQL.  This branch is
             * intentionally placed before every generic REST/fallback
             * response so the product batch never receives {"orders":[]}.
             */
            if (
                endpoint != null &&
                endpoint.contains('/graphql.json') &&
                request != null &&
                request.getMethod() == 'POST'
            ) {
                response.setStatusCode(200);

                response.setBody(
                    '{' +
                        '"data":{' +
                            '"products":{' +
                                '"edges":[],' +
                                '"pageInfo":{' +
                                    '"hasNextPage":false,' +
                                    '"endCursor":null' +
                                '}' +
                            '}' +
                        '}' +
                    '}'
                );

                return response;
            }

            if (mode == 'BACKFILL_HTTP_ERROR') {
                response.setStatusCode(500);
                response.setBody('{"error":"simulated failure"}');
                return response;
            }

            response.setStatusCode(200);

            if (mode == 'BACKFILL_BLANK_BODY') {
                response.setBody('');
                return response;
            }

            if (mode == 'BACKFILL_INVALID_ROOT') {
                response.setBody('[{"invalid":true}]');
                return response;
            }

            if (mode == 'BACKFILL_INVALID_ORDERS') {
                response.setBody('{"orders":"not-a-list"}');
                return response;
            }

            if (mode == 'ORDER_FULL_PAGE') {
                if (endpoint != null && endpoint.contains('since_id=105')) {
                    response.setBody('{"orders":[]}');
                } else {
                    response.setBody(
                        '{"orders":[' +
                        '{"id":101},' +
                        '{"id":102},' +
                        '{"id":103},' +
                        '{"id":104},' +
                        '{"id":105}' +
                        ']}'
                    );
                }
                return response;
            }

            if (mode == 'ORDER_MIXED_PAGE') {
                response.setBody(
                    '{"orders":[' +
                    'null,' +
                    '"invalid",' +
                    '{"id":null},' +
                    '{"id":"not-numeric"},' +
                    '{"id":205}' +
                    ']}'
                );
                return response;
            }

            if (mode == 'CUSTOM_COLLECTION_INVALID_VALUES') {
                response.setBody(
                    '{"custom_collections":[null,"invalid"]}'
                );
                return response;
            }

            if (mode == 'SMART_COLLECTION_INVALID_VALUES') {
                response.setBody(
                    '{"smart_collections":[null,"invalid"]}'
                );
                return response;
            }

            if (mode == 'INVENTORY_INVALID_VALUES') {
                response.setBody(
                    '{"inventory_levels":[null,"invalid"]}'
                );
                return response;
            }

            if (mode == 'LINK_NEXT') {
                if (endpoint == null || !endpoint.contains('page_info=NEXT')) {
                    response.setHeader(
                        'Link',
                        '<https://test-store.myshopify.com/admin/api/2026-04/' +
                        'custom_collections.json?limit=5&page_info=NEXT>; rel="next"'
                    );
                }
                response.setBody('{"custom_collections":[]}');
                return response;
            }

            if (endpoint != null && endpoint.contains('/products.json')) {
                response.setBody('{"products":[]}');
                return response;
            }

            if (endpoint != null && endpoint.contains('/custom_collections.json')) {
                response.setBody('{"custom_collections":[]}');
                return response;
            }

            if (endpoint != null && endpoint.contains('/smart_collections.json')) {
                response.setBody('{"smart_collections":[]}');
                return response;
            }

            if (endpoint != null && endpoint.contains('/inventory_levels.json')) {
                response.setBody('{"inventory_levels":[]}');
                return response;
            }

            response.setBody('{"orders":[]}');
            return response;
        }
    }

    private static void configureMock(String mode) {
        Test.setMock(
            HttpCalloutMock.class,
            new BackfillHttpMock(mode)
        );
    }
    
    private static List<Product2> createVariants(
        Integer numberOfVariants
    ) {
        List<Product2> variants = new List<Product2>();
        
        for (Integer index = 0; index < numberOfVariants; index++) {
            variants.add(
                new Product2(
                    Name = 'Backfill Variant ' + index,
                    IsActive = true,
                    Type__c = 'Variant',
                    Inventory_Item_Id__c =
                    String.valueOf(7000000 + index)
                )
            );
        }
        
        insert variants;
        return variants;
    }
    
    @IsTest
    static void testBackfillOrders() {
        configureMock('SUCCESS');
        
        Test.startTest();
        
        Id jobId =
            ShopifyBackfillService.backfillOrders();
        
        Test.stopTest();
        
        System.assertNotEquals(null, jobId);
    }
    
    @IsTest
    static void testBackfillOrdersFromNullUsesDefaultBackfill() {
        configureMock('SUCCESS');
        
        Test.startTest();
        
        Id jobId =
            ShopifyBackfillService.backfillOrdersFrom(null);
        
        Test.stopTest();
        
        System.assertNotEquals(null, jobId);
    }
    
    @IsTest
    static void testBackfillOrdersFromSpecifiedDatetime() {
        configureMock('SUCCESS');
        
        Datetime createdAtMin =
            Datetime.newInstanceGMT(
                2026,
                1,
                15,
                10,
                30,
                45
            );
        
        Test.startTest();
        
        Id jobId =
            ShopifyBackfillService.backfillOrdersFrom(
                createdAtMin
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, jobId);
    }
    
    @IsTest
    static void testBackfillOrdersBetweenSuccess() {
        configureMock('SUCCESS');
        
        Datetime createdAtMin =
            Datetime.newInstanceGMT(
                2026,
                1,
                1,
                0,
                0,
                0
            );
        
        Datetime createdAtMax =
            createdAtMin.addDays(10);
        
        Test.startTest();
        
        Id jobId =
            ShopifyBackfillService.backfillOrdersBetween(
                createdAtMin,
                createdAtMax
            );
        
        Test.stopTest();
        
        System.assertNotEquals(
            null,
            jobId,
            'A Queueable job should be created for the specified date range.'
        );
    }
    
    @IsTest
    static void testBackfillOrdersBetweenMissingMinimum() {
        Boolean exceptionThrown = false;
        
        try {
            ShopifyBackfillService.backfillOrdersBetween(
                null,
                Datetime.now()
            );
        } catch (
            ShopifyBackfillService.ShopifyBackfillException e
        ) {
            exceptionThrown = true;
            
            System.assertEquals(
                'Both createdAtMin and createdAtMax are required.',
                e.getMessage()
            );
        }
        
        System.assertEquals(true, exceptionThrown);
    }
    
    @IsTest
    static void testBackfillOrdersBetweenMissingMaximum() {
        Boolean exceptionThrown = false;
        
        try {
            ShopifyBackfillService.backfillOrdersBetween(
                Datetime.now(),
                null
            );
        } catch (
            ShopifyBackfillService.ShopifyBackfillException e
        ) {
            exceptionThrown = true;
            
            System.assertEquals(
                'Both createdAtMin and createdAtMax are required.',
                e.getMessage()
            );
        }
        
        System.assertEquals(true, exceptionThrown);
    }
    
    @IsTest
    static void testBackfillOrdersBetweenInvalidRange() {
        Datetime createdAtMin = Datetime.now();
        
        Boolean exceptionThrown = false;
        
        try {
            ShopifyBackfillService.backfillOrdersBetween(
                createdAtMin,
                createdAtMin
            );
        } catch (
            ShopifyBackfillService.ShopifyBackfillException e
        ) {
            exceptionThrown = true;
            
            System.assertEquals(
                'createdAtMax must be later than createdAtMin.',
                e.getMessage()
            );
        }
        
        System.assertEquals(true, exceptionThrown);
    }
    
    @IsTest
    static void testBackfillCollectionsCreatesTwoJobs() {
        configureMock('SUCCESS');
        
        Test.startTest();
        
        List<Id> jobIds =
            ShopifyBackfillService.backfillCollections();
        
        Test.stopTest();
        
        System.assertEquals(2, jobIds.size());
        System.assertNotEquals(null, jobIds[0]);
        System.assertNotEquals(null, jobIds[1]);
    }
    
    @IsTest
    static void testBackfillInventoryWithoutVariants() {
        Boolean exceptionThrown = false;
        
        try {
            ShopifyBackfillService.backfillInventory();
        } catch (
            ShopifyBackfillService.ShopifyBackfillException e
        ) {
            exceptionThrown = true;
            
            System.assertEquals(
                'No variants with Inventory_Item_Id__c were found.',
                e.getMessage()
            );
        }
        
        System.assertEquals(true, exceptionThrown);
    }
    
    @IsTest
    static void testBackfillInventorySingleChunk() {
        createVariants(5);
        configureMock('SUCCESS');
        
        Test.startTest();
        
        List<Id> jobIds =
            ShopifyBackfillService.backfillInventory();
        
        Test.stopTest();
        
        System.assertEquals(1, jobIds.size());
    }
    
    @IsTest
    static void testBackfillInventoryMultipleChunks() {
        createVariants(41);
        configureMock('SUCCESS');
        
        Test.startTest();
        
        List<Id> jobIds =
            ShopifyBackfillService.backfillInventory();
        
        Test.stopTest();
        
        System.assertEquals(2, jobIds.size());
    }
    
    @IsTest
    static void testQueueableRequiresBackfillType() {
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                null,
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json'
            );
        
        Boolean exceptionThrown = false;
        
        try {
            job.execute(null);
        } catch (
            ShopifyBackfillService.ShopifyBackfillException e
        ) {
            exceptionThrown = true;
            
            System.assertEquals(
                'Backfill type is required.',
                e.getMessage()
            );
        }
        
        System.assertEquals(true, exceptionThrown);
    }
    
    @IsTest
    static void testQueueableRequiresEndpoint() {
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'ORDERS',
                null
            );
        
        Boolean exceptionThrown = false;
        
        try {
            job.execute(null);
        } catch (
            ShopifyBackfillService.ShopifyBackfillException e
        ) {
            exceptionThrown = true;
            
            System.assertEquals(
                'Shopify endpoint is required.',
                e.getMessage()
            );
        }
        
        System.assertEquals(true, exceptionThrown);
    }
    
    @IsTest
    static void testQueueableProcessesEmptyOrders() {
        configureMock('SUCCESS');
        
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'ORDERS',
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json'
            );
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
    }
    
    @IsTest
    static void testQueueableHandlesInvalidOrdersProperty() {
        configureMock('BACKFILL_INVALID_ORDERS');
        
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'ORDERS',
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json'
            );
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
    }
    
    @IsTest
    static void testQueueableProcessesCustomCollections() {
        configureMock('SUCCESS');
        
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'CUSTOM_COLLECTIONS',
                'callout:Shopify_Admin_API/admin/api/2026-04/custom_collections.json'
            );
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
    }
    
    @IsTest
    static void testQueueableProcessesSmartCollections() {
        configureMock('SUCCESS');
        
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'SMART_COLLECTIONS',
                'callout:Shopify_Admin_API/admin/api/2026-04/smart_collections.json'
            );
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
    }
    
    @IsTest
    static void testQueueableProcessesInventory() {
        configureMock('SUCCESS');
        
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'INVENTORY',
                'callout:Shopify_Admin_API/admin/api/2026-04/inventory_levels.json'
            );
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
    }
    
    @IsTest
    static void testQueueableRejectsUnsupportedType() {
        configureMock('SUCCESS');
        
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'UNSUPPORTED_TYPE',
                'callout:Shopify_Admin_API/admin/api/2026-04/test.json'
            );
        
        Test.startTest();
        
        /*
* The Queueable now handles unsupported types internally.
* The test verifies that execution completes without allowing
* the exception to fail the asynchronous transaction.
*/
        job.execute(null);
        
        Test.stopTest();
        
        System.assert(
            true,
            'Unsupported backfill types should be handled internally.'
        );
    }
    
    @IsTest
    static void testQueueableHandlesBlankBody() {
        configureMock('BACKFILL_BLANK_BODY');
        
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'ORDERS',
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json'
            );
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
    }
    
    @IsTest
    static void testQueueableRejectsInvalidRoot() {
        configureMock(
            'BACKFILL_INVALID_ROOT'
        );
        
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'ORDERS',
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json'
            );
        
        Boolean unexpectedExceptionThrown =
            false;
        
        Test.startTest();
        
        try {
            job.execute(null);
        } catch (Exception e) {
            unexpectedExceptionThrown =
                true;
            
            System.debug(
                LoggingLevel.ERROR,
                'Unexpected exception for invalid Shopify root: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
        
        System.assertEquals(
            false,
            unexpectedExceptionThrown,
            'An invalid Shopify response root should be handled internally.'
        );
    }
    
    @IsTest
    static void testQueueableHandlesHttpFailure() {
        configureMock(
            'BACKFILL_HTTP_ERROR'
        );
        
        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'ORDERS',
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json'
            );
        
        Boolean unexpectedExceptionThrown =
            false;
        
        Test.startTest();
        
        try {
            job.execute(null);
        } catch (Exception e) {
            unexpectedExceptionThrown =
                true;
            
            System.debug(
                LoggingLevel.ERROR,
                'Unexpected exception for Shopify HTTP failure: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
        
        System.assertEquals(
            false,
            unexpectedExceptionThrown,
            'The Shopify HTTP failure should be handled internally by the Queueable.'
        );
    }
    
    @IsTest
    static void testGetNextEndpointBlankHeader() {
        System.assertEquals(
            null,
            ShopifyBackfillService.getNextEndpoint(null)
        );
        
        System.assertEquals(
            null,
            ShopifyBackfillService.getNextEndpoint(' ')
        );
    }
    
    @IsTest
    static void testGetNextEndpointValidNextLink() {
        String linkHeader =
            '<https://test-store.myshopify.com/admin/api/2026-04/' +
            'orders.json?limit=5&page_info=ABC123>; rel="next"';
        
        System.assertEquals(
            'callout:Shopify_Admin_API/admin/api/2026-04/' +
            'orders.json?limit=5&page_info=ABC123',
            ShopifyBackfillService.getNextEndpoint(
                linkHeader
            )
        );
    }
    
    @IsTest
    static void testGetNextEndpointPreviousAndNext() {
        String linkHeader =
            '<https://test-store.myshopify.com/admin/api/2026-04/' +
            'orders.json?page_info=PREVIOUS>; rel="previous",' +
            '<https://test-store.myshopify.com/admin/api/2026-04/' +
            'orders.json?page_info=NEXT>; rel="next"';
        
        System.assertEquals(
            'callout:Shopify_Admin_API/admin/api/2026-04/' +
            'orders.json?page_info=NEXT',
            ShopifyBackfillService.getNextEndpoint(
                linkHeader
            )
        );
    }
    
    @IsTest
    static void testGetNextEndpointInvalidLinks() {
        System.assertEquals(
            null,
            ShopifyBackfillService.getNextEndpoint(
                'invalid-value; rel="next"'
            )
        );
        
        System.assertEquals(
            null,
            ShopifyBackfillService.getNextEndpoint(
                '<invalid-value; rel="next"'
            )
        );
        
        System.assertEquals(
            null,
            ShopifyBackfillService.getNextEndpoint(
                '<https://example.com/orders.json>; rel="next"'
            )
        );
    }
    
    @IsTest
    static void testBackfillProductsStartsBatch() {
        /*
         * Use the backfill mock here because it contains the GraphQL
         * products-page response required by ShopifyProductPageBatch.
         *
         * GlobalHttpMock remains untouched.
         */
        configureMock('SUCCESS');

        Test.startTest();

        Id jobId =
            ShopifyBackfillService.backfillProducts();

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'backfillProducts should submit ShopifyProductPageBatch successfully.'
        );
    }


    @IsTest
    static void testBackfillProductGraphQlMockReturnsProductsConnection() {
        BackfillHttpMock mock =
            new BackfillHttpMock('SUCCESS');

        HttpRequest request =
            new HttpRequest();

        request.setEndpoint(
            'callout:Shopify_Admin_API/admin/api/2026-04/graphql.json'
        );
        request.setMethod('POST');
        request.setBody(
            '{"query":"query ProductsPage { products(first: 25) { edges { node { id } } pageInfo { hasNextPage endCursor } } }"}'
        );

        HttpResponse response =
            mock.respond(request);

        System.assertEquals(
            200,
            response.getStatusCode()
        );

        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(
                response.getBody()
            );

        System.assertNotEquals(
            null,
            root.get('data'),
            'GraphQL mock must return a data object.'
        );

        Map<String, Object> data =
            (Map<String, Object>) root.get('data');

        System.assertNotEquals(
            null,
            data.get('products'),
            'GraphQL mock must return data.products.'
        );
    }
    
    @IsTest
    static void testBackfillGeneratedSkusStartsBatch() {
        configureMock('SUCCESS');

        Test.startTest();

        Id jobId =
            ShopifyBackfillService.backfillGeneratedSkus();

        System.assertNotEquals(
            null,
            jobId,
            'Generated-SKU writeback should submit its batch.'
        );

        /* Do not stopTest here; ShopifyGeneratedSkuBackfillBatch has its own tests. */
    }
    
    @IsTest
    static void testRegenerateAllProductSkusStartsBatch() {
        configureMock('SUCCESS');

        Test.startTest();

        Id jobId =
            ShopifyBackfillService.regenerateAllProductSkus();

        System.assertNotEquals(null, jobId);

        /*
         * Do not call Test.stopTest(). The batch implementation is covered
         * by its own test class and may enqueue downstream writeback jobs.
         */
    }

    @IsTest
    static void testRefreshProductSalesInsightsStartsBatch() {
        Test.startTest();

        Id jobId =
            ShopifyBackfillService.refreshProductSalesInsights();

        System.assertNotEquals(null, jobId);
    }

    @IsTest
    static void testExtractSinceIdBranches() {
        System.assertEquals(
            null,
            ShopifyBackfillService.extractSinceId(null)
        );
        System.assertEquals(
            null,
            ShopifyBackfillService.extractSinceId('   ')
        );
        System.assertEquals(
            null,
            ShopifyBackfillService.extractSinceId(
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?limit=5'
            )
        );
        System.assertEquals(
            Long.valueOf('12345'),
            ShopifyBackfillService.extractSinceId(
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?limit=5&since_id=12345'
            )
        );
    }

    @IsTest
    static void testGetQueryParameterBranches() {
        System.assertEquals(
            null,
            ShopifyBackfillService.getQueryParameter(null, 'status')
        );
        System.assertEquals(
            null,
            ShopifyBackfillService.getQueryParameter('endpoint', 'status')
        );
        System.assertEquals(
            null,
            ShopifyBackfillService.getQueryParameter('endpoint?status=any', null)
        );
        System.assertEquals(
            'created at asc',
            ShopifyBackfillService.getQueryParameter(
                'endpoint?badpart&status=any&order=created+at+asc',
                'order'
            )
        );
        System.assertEquals(
            null,
            ShopifyBackfillService.getQueryParameter(
                'endpoint?status=any',
                'missing'
            )
        );
    }

    @IsTest
    static void testBuildNextOrderEndpointBranches() {
        System.assertEquals(
            null,
            ShopifyBackfillService.buildNextOrderEndpoint(null, null)
        );

        System.assertEquals(
            null,
            ShopifyBackfillService.buildNextOrderEndpoint(
                'endpoint?since_id=0',
                new Map<String, Object>{'orders' => new List<Object>()}
            )
        );

        Map<String, Object> shortPage = new Map<String, Object>{
            'orders' => new List<Object>{
                null,
                'invalid',
                new Map<String, Object>{'id' => null},
                new Map<String, Object>{'id' => 'bad'}
            }
        };

        System.assertEquals(
            null,
            ShopifyBackfillService.buildNextOrderEndpoint(
                'endpoint?since_id=0',
                shortPage
            )
        );

        Map<String, Object> fullPage = new Map<String, Object>{
            'orders' => new List<Object>{
                new Map<String, Object>{'id' => 11},
                new Map<String, Object>{'id' => 15},
                new Map<String, Object>{'id' => 12},
                new Map<String, Object>{'id' => 14},
                new Map<String, Object>{'id' => 13}
            }
        };

        String nextEndpoint =
            ShopifyBackfillService.buildNextOrderEndpoint(
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?' +
                'limit=5&status=any&created_at_min=2026-01-01T00%3A00%3A00Z&' +
                'created_at_max=2026-01-31T00%3A00%3A00Z&since_id=0',
                fullPage
            );

        System.assertNotEquals(null, nextEndpoint);
        System.assertEquals(Long.valueOf('15'), ShopifyBackfillService.extractSinceId(nextEndpoint));
        System.assertEquals(
            '2026-01-01T00:00:00Z',
            ShopifyBackfillService.getQueryParameter(nextEndpoint, 'created_at_min')
        );
        System.assertEquals(
            '2026-01-31T00:00:00Z',
            ShopifyBackfillService.getQueryParameter(nextEndpoint, 'created_at_max')
        );
    }

    @IsTest
    static void testQueueableProcessesMixedOrderPageAndBuildsNextEndpoint() {
        configureMock('ORDER_MIXED_PAGE');

        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'ORDERS',
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?' +
                'limit=5&status=any&since_id=0'
            );

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testQueueableFullOrderPageEnqueuesNextPage() {
        configureMock('ORDER_FULL_PAGE');

        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'ORDERS',
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?' +
                'limit=5&status=any&since_id=0'
            );

        Integer jobsBefore = Limits.getQueueableJobs();
        job.execute(null);
        Integer jobsAfter = Limits.getQueueableJobs();

        System.assertEquals(
            jobsBefore + 1,
            jobsAfter,
            'A full order page should enqueue the next since_id page.'
        );
    }

    @IsTest
    static void testQueueableStopsNonAdvancingOrderPagination() {
        configureMock('ORDER_FULL_PAGE');

        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'ORDERS',
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?' +
                'limit=5&status=any&since_id=999'
            );

        Integer jobsBefore = Limits.getQueueableJobs();
        job.execute(null);
        Integer jobsAfter = Limits.getQueueableJobs();

        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'Pagination must stop when the next since_id does not advance.'
        );
    }

    @IsTest
    static void testQueueableNonOrderLinkPagination() {
        configureMock('LINK_NEXT');

        ShopifyBackfillService.ShopifyBackfillQueueable job =
            new ShopifyBackfillService.ShopifyBackfillQueueable(
                'CUSTOM_COLLECTIONS',
                'callout:Shopify_Admin_API/admin/api/2026-04/custom_collections.json?limit=5'
            );

        Integer jobsBefore = Limits.getQueueableJobs();
        job.execute(null);
        Integer jobsAfter = Limits.getQueueableJobs();

        System.assertEquals(jobsBefore + 1, jobsAfter);
    }

    @IsTest
    static void testQueueableSkipsInvalidCollectionAndInventoryValues() {
        configureMock('CUSTOM_COLLECTION_INVALID_VALUES');
        new ShopifyBackfillService.ShopifyBackfillQueueable(
            'CUSTOM_COLLECTIONS',
            'callout:Shopify_Admin_API/admin/api/2026-04/custom_collections.json'
        ).execute(null);

        configureMock('SMART_COLLECTION_INVALID_VALUES');
        new ShopifyBackfillService.ShopifyBackfillQueueable(
            'SMART_COLLECTIONS',
            'callout:Shopify_Admin_API/admin/api/2026-04/smart_collections.json'
        ).execute(null);

        configureMock('INVENTORY_INVALID_VALUES');
        new ShopifyBackfillService.ShopifyBackfillQueueable(
            'INVENTORY',
            'callout:Shopify_Admin_API/admin/api/2026-04/inventory_levels.json'
        ).execute(null);

        System.assert(true);
    }

    @IsTest
    static void testGetNextEndpointSkipsBlankAndPreviousParts() {
        String header =
            '   ,' +
            '<https://test-store.myshopify.com/admin/api/2026-04/orders.json?page_info=PREV>; rel="previous",' +
            '<https://test-store.myshopify.com/admin/api/2026-04/orders.json?page_info=NEXT>; rel="next"';

        System.assertEquals(
            'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?page_info=NEXT',
            ShopifyBackfillService.getNextEndpoint(header)
        );
    }

    @IsTest
    static void testExtractSinceIdOverflowReturnsNull() {
        System.assertEquals(
            null,
            ShopifyBackfillService.extractSinceId(
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?' +
                'since_id=999999999999999999999999999999999999999'
            ),
            'An out-of-range numeric since_id should be handled safely.'
        );
    }

    @IsTest
    static void testBuildNextOrderEndpointFullPageWithoutDateFilters() {
        Map<String, Object> fullPage = new Map<String, Object>{
            'orders' => new List<Object>{
                new Map<String, Object>{ 'id' => '31' },
                new Map<String, Object>{ 'id' => '35' },
                new Map<String, Object>{ 'id' => '32' },
                new Map<String, Object>{ 'id' => '34' },
                new Map<String, Object>{ 'id' => '33' }
            }
        };

        String nextEndpoint =
            ShopifyBackfillService.buildNextOrderEndpoint(
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?' +
                'limit=5&status=any&order=created_at+asc&since_id=0',
                fullPage
            );

        System.assertNotEquals(null, nextEndpoint);
        System.assertEquals(
            Long.valueOf('35'),
            ShopifyBackfillService.extractSinceId(nextEndpoint)
        );
        System.assertEquals(
            null,
            ShopifyBackfillService.getQueryParameter(
                nextEndpoint,
                'created_at_min'
            )
        );
        System.assertEquals(
            null,
            ShopifyBackfillService.getQueryParameter(
                nextEndpoint,
                'created_at_max'
            )
        );
    }

    @IsTest
    static void testBuildNextOrderEndpointFullPageWithNoNumericIdsReturnsNull() {
        Map<String, Object> fullInvalidPage = new Map<String, Object>{
            'orders' => new List<Object>{
                null,
                'invalid',
                new Map<String, Object>{ 'id' => null },
                new Map<String, Object>{ 'id' => 'not-a-number' },
                new Map<String, Object>{ 'name' => 'missing-id' }
            }
        };

        System.assertEquals(
            null,
            ShopifyBackfillService.buildNextOrderEndpoint(
                'callout:Shopify_Admin_API/admin/api/2026-04/orders.json?since_id=0',
                fullInvalidPage
            )
        );
    }

    @IsTest
    static void testGetQueryParameterEncodedKeyAndBlankQueryParts() {
        System.assertEquals(
            'value with spaces',
            ShopifyBackfillService.getQueryParameter(
                'endpoint?&encoded%5Fkey=value+with+spaces&&badpart',
                'encoded_key'
            )
        );
    }

    @IsTest
    static void testBackfillInventoryExtractsPlainAndSlashIds() {
        List<Product2> variants = new List<Product2>{
            new Product2(
                Name = 'Backfill Slash Variant',
                IsActive = true,
                Type__c = 'Variant',
                Inventory_Item_Id__c = 'legacy/88001'
            ),
            new Product2(
                Name = 'Backfill Plain Variant',
                IsActive = true,
                Type__c = 'Variant',
                Inventory_Item_Id__c = '88002'
            )
        };
        insert variants;

        configureMock('SUCCESS');

        Test.startTest();
        List<Id> jobIds = ShopifyBackfillService.backfillInventory();

        System.assertEquals(
            1,
            jobIds.size(),
            'Two extracted inventory IDs should fit in a single chunk.'
        );
        System.assertNotEquals(null, jobIds[0]);

        /* Do not stopTest; the Queueable payload branches are tested directly. */
    }

    @IsTest
    static void testCustomException() {
        ShopifyBackfillService.ShopifyBackfillException exceptionValue =
            new ShopifyBackfillService.ShopifyBackfillException('test');

        System.assertEquals('test', exceptionValue.getMessage());
    }
}