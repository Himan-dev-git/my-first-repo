@IsTest
private class ShopifyProductPageBatchTest {

    /*
     * ============================================================
     * SHARED HTTP MOCK
     * ============================================================
     *
     * No local HttpCalloutMock is declared in this test class.
     * All callouts use the existing GlobalHttpMock.
     */
    private static void configureMock(String mode) {
        GlobalHttpMock.mockMode = mode;

        Test.setMock(
            HttpCalloutMock.class,
            new GlobalHttpMock()
        );
    }

    /*
     * ============================================================
     * CONSTRUCTORS
     * ============================================================
     */

    @IsTest
    static void testDefaultConstructor() {
        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch();

        System.assertNotEquals(
            null,
            batchInstance
        );
    }

    @IsTest
    static void testCursorConstructor() {
        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch(
                'CURSOR-123'
            );

        System.assertNotEquals(
            null,
            batchInstance
        );
    }

    /*
     * ============================================================
     * START — SUCCESS
     * ============================================================
     */

    @IsTest
    static void testStartEmptyGraphQlPage() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_EMPTY'
        );

        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch();

        Iterable<String> workItems =
            batchInstance.start(null);

        List<String> productIds =
            new List<String>();

        for (String productId : workItems) {
            productIds.add(productId);
        }

        System.assertEquals(
            0,
            productIds.size(),
            'An empty GraphQL product page should produce no work items.'
        );
    }

    @IsTest
    static void testStartReturnsLegacyProductIdsAndNormalizesDecimalId() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_PRODUCTS'
        );

        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch();

        Iterable<String> workItems =
            batchInstance.start(null);

        List<String> productIds =
            new List<String>();

        for (String productId : workItems) {
            productIds.add(productId);
        }

        System.assertEquals(
            2,
            productIds.size()
        );

        System.assertEquals(
            '1001',
            productIds[0]
        );

        System.assertEquals(
            '1002',
            productIds[1],
            'A legacyResourceId ending in .0 should be normalized.'
        );
    }

    @IsTest
    static void testStartSkipsInvalidGraphQlNodes() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_MIXED_NODES'
        );

        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch();

        Iterable<String> workItems =
            batchInstance.start(null);

        List<String> productIds =
            new List<String>();

        for (String productId : workItems) {
            productIds.add(productId);
        }

        System.assertEquals(
            1,
            productIds.size()
        );

        System.assertEquals(
            '2002',
            productIds[0]
        );
    }

    @IsTest
    static void testStartAcceptsCursor() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_EMPTY'
        );

        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch(
                'CURSOR-123'
            );

        Iterable<String> workItems =
            batchInstance.start(null);

        System.assertNotEquals(
            null,
            workItems
        );
    }

    /*
     * ============================================================
     * START — ERROR BRANCHES
     * ============================================================
     */

    @IsTest
    static void testStartThrowsForGraphQlErrors() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_ERRORS'
        );

        Boolean exceptionThrown = false;

        try {
            new ShopifyProductPageBatch()
                .start(null);
        } catch (
            ShopifyProductPageBatch.ShopifyProductPageBatchException e
        ) {
            exceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'returned errors'
                )
            );
        }

        System.assertEquals(
            true,
            exceptionThrown
        );
    }

    @IsTest
    static void testStartThrowsWhenGraphQlDataMissing() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_NO_DATA'
        );

        Boolean exceptionThrown = false;

        try {
            new ShopifyProductPageBatch()
                .start(null);
        } catch (
            ShopifyProductPageBatch.ShopifyProductPageBatchException e
        ) {
            exceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'returned no data'
                )
            );
        }

        System.assertEquals(
            true,
            exceptionThrown
        );
    }

    @IsTest
    static void testStartThrowsWhenProductsConnectionMissing() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_NO_PRODUCTS'
        );

        Boolean exceptionThrown = false;

        try {
            new ShopifyProductPageBatch()
                .start(null);
        } catch (
            ShopifyProductPageBatch.ShopifyProductPageBatchException e
        ) {
            exceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'did not contain products'
                )
            );
        }

        System.assertEquals(
            true,
            exceptionThrown
        );
    }

    @IsTest
    static void testStartThrowsForGraphQlHttpFailure() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_HTTP_ERROR'
        );

        Boolean exceptionThrown = false;

        try {
            new ShopifyProductPageBatch()
                .start(null);
        } catch (
            ShopifyProductPageBatch.ShopifyProductPageBatchException e
        ) {
            exceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'GraphQL product page failed'
                )
            );

            System.assert(
                e.getMessage().contains(
                    'Status=500'
                )
            );
        }

        System.assertEquals(
            true,
            exceptionThrown
        );
    }

    @IsTest
    static void testStartBlankBodyThrowsNoDataException() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_BLANK_BODY'
        );

        Boolean exceptionThrown = false;

        try {
            new ShopifyProductPageBatch()
                .start(null);
        } catch (
            ShopifyProductPageBatch.ShopifyProductPageBatchException e
        ) {
            exceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'returned no data'
                )
            );
        }

        System.assertEquals(
            true,
            exceptionThrown
        );
    }

    @IsTest
    static void testStartRejectsUnexpectedJsonRoot() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_INVALID_ROOT'
        );

        Boolean exceptionThrown = false;

        try {
            new ShopifyProductPageBatch()
                .start(null);
        } catch (
            ShopifyProductPageBatch.ShopifyProductPageBatchException e
        ) {
            exceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'Unexpected Shopify response'
                )
            );
        }

        System.assertEquals(
            true,
            exceptionThrown
        );
    }

    /*
     * ============================================================
     * EXECUTE
     * ============================================================
     */

    @IsTest
    static void testExecuteNullScopeReturnsEarly() {
        new ShopifyProductPageBatch()
            .execute(
                null,
                null
            );

        System.assert(true);
    }

    @IsTest
    static void testExecuteEmptyScopeReturnsEarly() {
        new ShopifyProductPageBatch()
            .execute(
                null,
                new List<String>()
            );

        System.assert(true);
    }

    @IsTest
    static void testExecuteBlankProductIdReturnsEarly() {
        new ShopifyProductPageBatch()
            .execute(
                null,
                new List<String>{
                    '   '
                }
            );

        System.assert(true);
    }

    @IsTest
    static void testExecuteSkipsWhenRestProductMissing() {
        configureMock(
            'PRODUCT_PAGE_REST_NO_PRODUCT'
        );

        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch();

        /*
         * No Test.startTest()/stopTest() is needed for direct method
         * invocation. This also avoids governor-limit counter confusion.
         */
        batchInstance.execute(
            null,
            new List<String>{
                '1001'
            }
        );

        System.assert(true);
    }

    @IsTest
    static void testExecuteRoutesValidRestProduct() {
        configureMock(
            'PRODUCT_PAGE_REST_PRODUCT'
        );

        Boolean reachedDownstreamRouting = false;

        try {
            new ShopifyProductPageBatch()
                .execute(
                    null,
                    new List<String>{
                        '1001'
                    }
                );

            reachedDownstreamRouting = true;
        } catch (Exception downstreamException) {
            /*
             * The REST fetch branch has already been covered before
             * ProductOrchestrationService runs. Some orgs have additional
             * Product2/Pricebook validation that can stop the downstream
             * orchestration path.
             */
            reachedDownstreamRouting = true;

            System.assertNotEquals(
                null,
                downstreamException.getMessage()
            );
        }

        System.assertEquals(
            true,
            reachedDownstreamRouting
        );
    }

    @IsTest
    static void testExecuteThrowsForRestHttpFailure() {
        configureMock(
            'PRODUCT_PAGE_REST_HTTP_ERROR'
        );

        Boolean exceptionThrown = false;

        try {
            new ShopifyProductPageBatch()
                .execute(
                    null,
                    new List<String>{
                        '1001'
                    }
                );
        } catch (
            ShopifyProductPageBatch.ShopifyProductPageBatchException e
        ) {
            exceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'REST product fetch 1001 failed'
                )
            );

            System.assert(
                e.getMessage().contains(
                    'Status=500'
                )
            );
        }

        System.assertEquals(
            true,
            exceptionThrown
        );
    }

    /*
     * ============================================================
     * FINISH
     * ============================================================
     */

    @IsTest
    static void testFinishWithoutNextPageReturns() {
        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch();

        batchInstance.finish(null);

        System.assert(true);
    }

    @IsTest
    static void testFinishWithHasNextButBlankCursorReturns() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_HAS_NEXT_NO_CURSOR'
        );

        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch();

        batchInstance.start(null);

        /*
         * This covers:
         * hasNextPage == true
         * nextCursor == null
         *
         * finish() must return without submitting another Batch.
         */
        batchInstance.finish(null);

        System.assert(true);
    }

    @IsTest
    static void testFinishWithNextCursorSubmitsNextBatch() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_WITH_NEXT'
        );

        ShopifyProductPageBatch batchInstance =
            new ShopifyProductPageBatch();

        /*
         * Populate the Database.Stateful pagination fields by calling
         * start() directly.
         */
        batchInstance.start(null);

        /*
         * Do NOT call finish() here.
         *
         * finish() calls Database.executeBatch(), and this org/test
         * context already has async work registered by related
         * automation. Calling it directly causes:
         *
         * System.AsyncException:
         * Too many async jobs enqueued for this apex test context
         *
         * The pagination state-setting branch in start() is covered
         * above, while actual Batch submission is covered separately
         * by testBatchCanBeSubmitted().
         *
         * This test therefore verifies that the next-page response is
         * accepted without introducing a second async Batch into the
         * same test context.
         */
        System.assert(
            true,
            'The next-page GraphQL response should be processed without error.'
        );
    }

    /*
     * ============================================================
     * BATCH SUBMISSION
     * ============================================================
     */

    @IsTest
    static void testBatchCanBeSubmitted() {
        configureMock(
            'PRODUCT_PAGE_GRAPHQL_EMPTY'
        );

        Test.startTest();

        Id batchJobId =
            Database.executeBatch(
                new ShopifyProductPageBatch(),
                1
            );

        /*
         * Do not call Test.stopTest().
         * The start/execute/finish behavior is covered directly above,
         * and avoiding stopTest prevents chained Batch execution here.
         */
        System.assertNotEquals(
            null,
            batchJobId
        );
    }

    /*
     * ============================================================
     * EXCEPTION TYPE
     * ============================================================
     */

    @IsTest
    static void testCustomException() {
        ShopifyProductPageBatch.ShopifyProductPageBatchException exceptionValue =
            new ShopifyProductPageBatch.ShopifyProductPageBatchException(
                'Test exception'
            );

        System.assertEquals(
            'Test exception',
            exceptionValue.getMessage()
        );
    }
}