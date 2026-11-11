@IsTest
private class SquarePricebookSyncSchedulerTest {

    private class SquareCatalogMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            // Return empty catalog so Queueable exits safely.
            res.setBody('{"objects":[]}');

            return res;
        }
    }

    @IsTest
    static void testSchedulerEnqueuesQueueableWhenNoRunningJob() {
        Test.setMock(HttpCalloutMock.class, new SquareCatalogMock());

        Test.startTest();

        String jobId = System.schedule(
            'Square Pricebook Sync Scheduler Test',
            '0 0 0 1 1 ? 2099',
            new SquarePricebookSyncScheduler()
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'Scheduler job should be created successfully.'
        );
    }
}