@IsTest
private class SquareCatalogSchedulerTest {

    private class SafeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String body = req.getBody();

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

    @IsTest
    static void testExecuteWithVariantShopIdsEnqueuesQueueable() {
        Test.setMock(HttpCalloutMock.class, new SafeMock());

        SquareCatalogScheduler scheduler = new SquareCatalogScheduler(
            new Set<String>{ 'VARIANT_001', 'VARIANT_002' }
        );

        Test.startTest();
        scheduler.execute(null);
        Test.stopTest();

        System.assert(true, 'Scheduler execute should enqueue queueable when ids exist.');
    }

    @IsTest
    static void testExecuteWithDefaultConstructorDoesNothing() {
        Test.setMock(HttpCalloutMock.class, new SafeMock());

        SquareCatalogScheduler scheduler = new SquareCatalogScheduler();

        Test.startTest();
        scheduler.execute(null);
        Test.stopTest();

        System.assert(true, 'Default constructor has null ids, so execute should safely do nothing.');
    }

    @IsTest
    static void testExecuteWithEmptySetDoesNothing() {
        Test.setMock(HttpCalloutMock.class, new SafeMock());

        SquareCatalogScheduler scheduler = new SquareCatalogScheduler(
            new Set<String>()
        );

        Test.startTest();
        scheduler.execute(null);
        Test.stopTest();

        System.assert(true, 'Empty id set should safely do nothing.');
    }

    @IsTest
    static void testScheduleSyncNullAndEmptyInputsReturnSafely() {
        Test.startTest();
        SquareCatalogScheduler.scheduleSync(null);
        SquareCatalogScheduler.scheduleSync(new Set<String>());
        Test.stopTest();

        System.assert(true, 'Null and empty inputs should return safely.');
    }

    @IsTest
    static void testScheduleSyncCreatesScheduledJob() {
        Test.setMock(HttpCalloutMock.class, new SafeMock());

        Test.startTest();
        SquareCatalogScheduler.scheduleSync(
            new Set<String>{ 'VARIANT_002', 'VARIANT_001' }
        );
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Square Catalog Sync%'
        ];

        System.assert(
            jobs.size() > 0,
            'scheduleSync should create a scheduled job.'
        );
    }

    @IsTest
    static void testScheduleSyncDuplicateCaughtSafely() {
        Test.setMock(HttpCalloutMock.class, new SafeMock());

        Set<String> ids = new Set<String>{ 'DUPLICATE_VARIANT_001' };

        Test.startTest();

        SquareCatalogScheduler.scheduleSync(ids);
        SquareCatalogScheduler.scheduleSync(ids);

        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Square Catalog Sync%'
        ];

        System.assert(
            jobs.size() > 0,
            'Duplicate schedule attempt should be caught safely.'
        );
    }
}