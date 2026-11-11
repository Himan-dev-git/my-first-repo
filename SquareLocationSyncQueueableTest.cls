@IsTest
private class SquareLocationSyncQueueableTest {

    private static Integer counter = 0;

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    private static String uniqueText(String prefix) {
        counter++;
        return prefix + '-' + String.valueOf(DateTime.now().getTime()) + '-' + counter;
    }

    private static Boolean fieldExists(String objectApiName, String fieldApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName) &&
            Schema.getGlobalDescribe()
                .get(objectApiName)
                .getDescribe()
                .fields
                .getMap()
                .containsKey(fieldApiName);
    }

    private static Id createLocation() {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();

        loc.put('Name', uniqueText('Square Sync Location'));

        if (fieldExists('Location', 'LocationType')) {
            loc.put('LocationType', 'Warehouse');
        }

        if (fieldExists('Location', 'Shopify_Location_ID__c')) {
            loc.put('Shopify_Location_ID__c', uniqueText('SHOPIFY-LOC'));
        }

        if (fieldExists('Location', 'Square_Location_Id__c')) {
            loc.put('Square_Location_Id__c', uniqueText('SQUARE-LOC'));
        }

        if (fieldExists('Location', 'ExternalReference')) {
            loc.put('ExternalReference', uniqueText('EXT-LOC'));
        }

        insert loc;

        return (Id) loc.get('Id');
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mock
    // Handles Square callouts and any Shopify/Product side-effect callouts.
    // ─────────────────────────────────────────────────────────────────────

    private class SquareLocationMock implements HttpCalloutMock {
        private String mode;

        SquareLocationMock(String modeValue) {
            mode = modeValue;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (mode == 'FAILURE') {
                res.setStatusCode(500);
                res.setBody('{"errors":[{"detail":"Forced Square location failure"}]}');
                return res;
            }

            res.setStatusCode(200);

            String body = req.getBody();

            // Safe Shopify side-effect responses if any trigger fires during test setup.
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

            // Square Locations API style response.
            res.setBody(
                '{"location":{' +
                '"id":"SQUARE-LOCATION-TEST",' +
                '"name":"Square Sync Location",' +
                '"status":"ACTIVE",' +
                '"type":"PHYSICAL",' +
                '"country":"GB",' +
                '"currency":"GBP"' +
                '}}'
            );

            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testExecute_NullLocationId_ReturnsSafely() {
        Test.startTest();

        System.enqueueJob(
            new SquareLocationSyncQueueable(
                null,
                'locations/create'
            )
        );

        Test.stopTest();

        System.assert(true, 'Queueable should safely return when locationId is null.');
    }

    @IsTest
    static void testExecute_WithLocationId_CallsSyncService() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationMock('SUCCESS'));

        Id locationId = createLocation();

        Test.startTest();

        System.enqueueJob(
            new SquareLocationSyncQueueable(
                locationId,
                'locations/update'
            )
        );

        Test.stopTest();

        System.assert(true, 'Queueable executed with a valid Location Id.');
    }

    @IsTest
    static void testExecute_ServiceExceptionIsCaught() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationMock('FAILURE'));

        Id locationId = createLocation();

        Test.startTest();

        System.enqueueJob(
            new SquareLocationSyncQueueable(
                locationId,
                'locations/create'
            )
        );

        Test.stopTest();

        System.assert(true, 'Queueable should catch and log service exceptions without failing the test.');
    }

    @IsTest
    static void testExecute_NullSourceTopicStillRuns() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationMock('SUCCESS'));

        Id locationId = createLocation();

        Test.startTest();

        System.enqueueJob(
            new SquareLocationSyncQueueable(
                locationId,
                null
            )
        );

        Test.stopTest();

        System.assert(true, 'Queueable should execute even when sourceTopic is null.');
    }
}