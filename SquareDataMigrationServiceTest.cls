@IsTest
private class SquareDataMigrationServiceTest {

    /*
     * The service methods only submit Batch Apex jobs.
     *
     * We intentionally do not call Test.stopTest() because that would
     * execute the migration batches and their downstream Square callouts.
     * Those behaviors should be covered in the individual batch and
     * Square service test classes.
     */

    @IsTest
    static void testBackfillCatalog() {
        Test.startTest();

        Id jobId =
            SquareDataMigrationService.backfillCatalog();

        System.assertNotEquals(
            null,
            jobId,
            'Catalog migration should return a Batch Apex job ID.'
        );

        AsyncApexJob job = [
            SELECT Id,
                   JobType,
                   Status,
                   ApexClass.Name
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assertEquals(
            'BatchApex',
            job.JobType,
            'Catalog migration should submit a Batch Apex job.'
        );

        System.assertEquals(
            'SquareCatalogMigrationBatch',
            job.ApexClass.Name,
            'Catalog migration should use SquareCatalogMigrationBatch.'
        );
    }

    @IsTest
    static void testBackfillInventory() {
        Test.startTest();

        Id jobId =
            SquareDataMigrationService.backfillInventory();

        System.assertNotEquals(
            null,
            jobId,
            'Inventory migration should return a Batch Apex job ID.'
        );

        AsyncApexJob job = [
            SELECT Id,
                   JobType,
                   Status,
                   ApexClass.Name
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assertEquals(
            'BatchApex',
            job.JobType,
            'Inventory migration should submit a Batch Apex job.'
        );

        System.assertEquals(
            'SquareInventoryMigrationBatch',
            job.ApexClass.Name,
            'Inventory migration should use SquareInventoryMigrationBatch.'
        );
    }

    @IsTest
    static void testBackfillAll() {
        Test.startTest();

        Id jobId =
            SquareDataMigrationService.backfillAll();

        System.assertNotEquals(
            null,
            jobId,
            'Full migration should return a Batch Apex job ID.'
        );

        AsyncApexJob job = [
            SELECT Id,
                   JobType,
                   Status,
                   ApexClass.Name
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assertEquals(
            'BatchApex',
            job.JobType,
            'Full migration should submit a Batch Apex job.'
        );

        System.assertEquals(
            'SquareCatalogMigrationBatch',
            job.ApexClass.Name,
            'Full migration should begin with SquareCatalogMigrationBatch.'
        );
    }

    @IsTest
    static void testMigrationException() {
        SquareDataMigrationService.SquareDataMigrationException exceptionValue =
            new SquareDataMigrationService.SquareDataMigrationException(
                'Test migration exception'
            );

        System.assertEquals(
            'Test migration exception',
            exceptionValue.getMessage()
        );
    }
}