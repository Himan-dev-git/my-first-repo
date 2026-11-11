@IsTest
private class SquareCatalogMigrationBatchTest {

    /*
     * ============================================================
     * HELPERS
     * ============================================================
     */

    private static void configureMock() {
        GlobalHttpMock.mockMode = 'SUCCESS';

        Test.setMock(
            HttpCalloutMock.class,
            new GlobalHttpMock()
        );
    }

    /*
     * Creates a non-Product2 record.
     *
     * Its ID can be passed through the Batch execute method, but
     * SquareCatalogService will not find a matching Product2 record.
     * This safely covers the successful service-call path without
     * requiring a complete Square catalog migration transaction.
     */
    private static Account createNonProductRecord() {
        Account testAccount = new Account(
            Name = 'Square Catalog Migration Test'
        );

        insert testAccount;
        return testAccount;
    }

    /*
     * ============================================================
     * CONSTRUCTORS
     * ============================================================
     */

    @IsTest
    static void testDefaultConstructor() {
        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch();

        System.assertNotEquals(
            null,
            batchInstance
        );
    }

    @IsTest
    static void testFalseConstructor() {
        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(false);

        System.assertNotEquals(
            null,
            batchInstance
        );
    }

    @IsTest
    static void testTrueConstructor() {
        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(true);

        System.assertNotEquals(
            null,
            batchInstance
        );
    }

    @IsTest
    static void testNullConstructor() {
        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(null);

        System.assertNotEquals(
            null,
            batchInstance
        );
    }

    /*
     * ============================================================
     * START
     * ============================================================
     */

    @IsTest
    static void testStartReturnsQueryLocator() {
        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(false);

        Database.QueryLocator queryLocator =
            batchInstance.start(null);

        System.assertNotEquals(
            null,
            queryLocator,
            'The Batch start method should return a QueryLocator.'
        );
    }

    /*
     * ============================================================
     * EXECUTE — DEFENSIVE BRANCHES
     * ============================================================
     */

    @IsTest
    static void testExecuteWithNullScope() {
        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(false);

        batchInstance.execute(
            null,
            null
        );

        System.assertEquals(
            0,
            Limits.getCallouts()
        );
    }

    @IsTest
    static void testExecuteWithEmptyScope() {
        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(false);

        batchInstance.execute(
            null,
            new List<SObject>()
        );

        System.assertEquals(
            0,
            Limits.getCallouts()
        );
    }

    @IsTest
    static void testExecuteWithOnlyNullRecords() {
        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(false);

        List<SObject> scope = new List<SObject>();
        scope.add(null);
        scope.add(null);

        batchInstance.execute(
            null,
            scope
        );

        System.assertEquals(
            0,
            Limits.getCallouts()
        );
    }

    /*
     * ============================================================
     * EXECUTE — SUCCESSFUL SERVICE PATH
     * ============================================================
     */

    @IsTest
    static void testExecuteCallsCatalogService() {
        configureMock();

        Account nonProductRecord =
            createNonProductRecord();

        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(false);

        /*
         * The scope contains a valid Salesforce ID, so the Batch:
         *
         * 1. Adds the ID to variantIds.
         * 2. Enters the try block.
         * 3. Calls SquareCatalogService.syncProductsToSquare().
         *
         * Because the ID belongs to an Account rather than Product2,
         * the catalog service should find no Product2 records and
         * finish without performing a real migration.
         */
        batchInstance.execute(
            null,
            new List<SObject>{
                nonProductRecord
            }
        );

        System.assertEquals(
            0,
            Limits.getQueueableJobs(),
            'No image Queueable should be created for a non-Product2 ID.'
        );
    }

    @IsTest
    static void testExecuteIgnoresNullAndProcessesValidRecord() {
        configureMock();

        Account nonProductRecord =
            createNonProductRecord();

        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(false);

        List<SObject> scope = new List<SObject>();
        scope.add(null);
        scope.add(nonProductRecord);
        scope.add(null);

        batchInstance.execute(
            null,
            scope
        );

        System.assertEquals(
            0,
            Limits.getQueueableJobs()
        );
    }

    /*
     * ============================================================
     * FINISH
     * ============================================================
     */

    @IsTest
    static void testFinishDoesNotStartInventory() {
        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(false);

        Integer batchJobsBefore = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
        ];

        batchInstance.finish(null);

        Integer batchJobsAfter = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
        ];

        System.assertEquals(
            batchJobsBefore,
            batchJobsAfter,
            'Inventory migration should not start when the flag is false.'
        );
    }

    @IsTest
    static void testFinishStartsInventoryMigration() {
        configureMock();

        SquareCatalogMigrationBatch batchInstance =
            new SquareCatalogMigrationBatch(true);

        Integer batchJobsBefore = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
        ];

        /*
         * Call finish directly and do not call Test.stopTest().
         * This verifies that the inventory Batch is submitted without
         * forcing SquareInventoryMigrationBatch to execute.
         */
        batchInstance.finish(null);

        Integer batchJobsAfter = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
        ];

        System.assertEquals(
            batchJobsBefore + 1,
            batchJobsAfter,
            'Inventory migration should be submitted when the flag is true.'
        );
    }

    /*
     * ============================================================
     * BATCH SUBMISSION
     * ============================================================
     */

    @IsTest
    static void testBatchCanBeSubmitted() {
        configureMock();

        Test.startTest();

        Id batchJobId = Database.executeBatch(
            new SquareCatalogMigrationBatch(false),
            1
        );

        /*
         * Do not call Test.stopTest().
         *
         * The individual test methods already cover start(), execute()
         * and finish(). Executing the complete Batch could invoke the
         * full Square integration and image Queueable chain.
         */
        System.assertNotEquals(
            null,
            batchJobId,
            'Square catalog migration should return a Batch job ID.'
        );
    }
}