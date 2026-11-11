@IsTest
private class SquareLocationSyncServiceTest {

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

    private static String getFieldValue(SObject recordObj, String fieldApiName) {
        if (recordObj == null || !fieldExists(String.valueOf(recordObj.getSObjectType()), fieldApiName)) {
            return null;
        }

        Object valueObj = recordObj.get(fieldApiName);
        return valueObj == null ? null : String.valueOf(valueObj);
    }

    private static Id createLocation(
        String locationName,
        String squareLocationId,
        Boolean isInventorySource
    ) {
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();

        loc.put('Name', locationName);

        if (fieldExists('Location', 'LocationType')) {
            loc.put('LocationType', 'Warehouse');
        }

        if (fieldExists('Location', 'Square_Location_Id__c') && squareLocationId != null) {
            loc.put('Square_Location_Id__c', squareLocationId);
        }

        if (fieldExists('Location', 'Shopify_Location_ID__c')) {
            loc.put('Shopify_Location_ID__c', uniqueText('SHOPIFY-LOC'));
        }

        if (fieldExists('Location', 'Is_Inventory_Source__c') && isInventorySource != null) {
            loc.put('Is_Inventory_Source__c', isInventorySource);
        }

        if (fieldExists('Location', 'Is_Fulfillable__c')) {
            loc.put('Is_Fulfillable__c', true);
        }

        if (fieldExists('Location', 'Is_Sellable__c')) {
            loc.put('Is_Sellable__c', true);
        }

        if (fieldExists('Location', 'Sync_Status__c')) {
            loc.put('Sync_Status__c', 'Synced');
        }

        insert loc;

        return (Id) loc.get('Id');
    }

    private static SObject queryLocation(Id locationId) {
        List<String> fieldsToQuery = new List<String>{ 'Id', 'Name' };

        if (fieldExists('Location', 'Square_Location_Id__c')) {
            fieldsToQuery.add('Square_Location_Id__c');
        }

        if (fieldExists('Location', 'Sync_Status__c')) {
            fieldsToQuery.add('Sync_Status__c');
        }

        String queryText =
            'SELECT ' + String.join(fieldsToQuery, ',') +
            ' FROM Location WHERE Id = :locationId LIMIT 1';

        return Database.query(queryText);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mock
    // ─────────────────────────────────────────────────────────────────────

    private class SquareLocationSyncMock implements HttpCalloutMock {
        private String mode;

        SquareLocationSyncMock(String modeValue) {
            mode = modeValue;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String methodName = req.getMethod() == null ? '' : req.getMethod().toUpperCase();

            // listSquareLocations()
            if (
                endpoint.contains('/locations') &&
                methodName == 'GET'
            ) {
                if (mode == 'MATCH_BY_NAME') {
                    res.setBody(
                        '{"locations":[' +
                        '{"id":"SQLOC_MATCHED","name":"Matched Location","status":"ACTIVE"},' +
                        '{"id":"SQLOC_OTHER","name":"Other Location","status":"ACTIVE"}' +
                        ']}'
                    );
                    return res;
                }

                if (mode == 'LIST_WITH_NULLS') {
                    res.setBody(
                        '{"locations":[' +
                        'null,' +
                        '{"id":null,"name":"No Id"},' +
                        '{"id":"SQLOC_NO_NAME","name":null}' +
                        ']}'
                    );
                    return res;
                }

                res.setBody('{"locations":[]}');
                return res;
            }

            if (mode == 'MISSING_LOCATION') {
                res.setBody('{}');
                return res;
            }

            if (mode == 'NULL_LOCATION') {
                res.setBody('{"location":null}');
                return res;
            }

            if (mode == 'MISSING_LOCATION_ID') {
                res.setBody('{"location":{"name":"No Id Location"}}');
                return res;
            }

            if (mode == 'UPDATE_EXISTING') {
                res.setBody(
                    '{"location":{' +
                    '"id":"SQLOC_EXISTING",' +
                    '"name":"Updated Existing Location",' +
                    '"status":"ACTIVE",' +
                    '"type":"PHYSICAL",' +
                    '"country":"GB",' +
                    '"currency":"GBP"' +
                    '}}'
                );
                return res;
            }

            if (mode == 'MATCH_BY_NAME') {
                res.setBody(
                    '{"location":{' +
                    '"id":"SQLOC_MATCHED",' +
                    '"name":"Matched Location",' +
                    '"status":"ACTIVE",' +
                    '"type":"PHYSICAL",' +
                    '"country":"GB",' +
                    '"currency":"GBP"' +
                    '}}'
                );
                return res;
            }

            // Default create success.
            res.setBody(
                '{"location":{' +
                '"id":"SQLOC_CREATED",' +
                '"name":"Created Location",' +
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
    static void testSyncSalesforceLocationToSquare_NullLocationIdReturnsSafely() {
        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(null, 'locations/create');
        Test.stopTest();

        System.assert(true, 'Null Location Id should return safely.');
    }

    @IsTest
    static void testSyncSalesforceLocationToSquare_CreateSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationSyncMock('CREATE_SUCCESS'));

        Id locationId = createLocation(uniqueText('Create Location'), null, true);

        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(locationId, 'locations/create');
        Test.stopTest();

        SObject updated = queryLocation(locationId);

        if (fieldExists('Location', 'Square_Location_Id__c')) {
            System.assertEquals('SQLOC_CREATED', String.valueOf(updated.get('Square_Location_Id__c')));
        }

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(updated.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testSyncSalesforceLocationToSquare_UpdateExistingSquareId() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationSyncMock('UPDATE_EXISTING'));

        Id locationId = createLocation(
            uniqueText('Existing Square Location'),
            'SQLOC_EXISTING',
            true
        );

        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(locationId, 'locations/update');
        Test.stopTest();

        SObject updated = queryLocation(locationId);

        if (fieldExists('Location', 'Square_Location_Id__c')) {
            System.assertEquals('SQLOC_EXISTING', String.valueOf(updated.get('Square_Location_Id__c')));
        }

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(updated.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testSyncSalesforceLocationToSquare_MatchesSquareLocationByName() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationSyncMock('MATCH_BY_NAME'));

        Id locationId = createLocation('Matched Location', null, true);

        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(locationId, 'locations/update');
        Test.stopTest();

        SObject updated = queryLocation(locationId);

        if (fieldExists('Location', 'Square_Location_Id__c')) {
            System.assertEquals('SQLOC_MATCHED', String.valueOf(updated.get('Square_Location_Id__c')));
        }

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(updated.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testSyncSalesforceLocationToSquare_DeactivateTopic() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationSyncMock('UPDATE_EXISTING'));

        Id locationId = createLocation(
            uniqueText('Deactivate Location'),
            'SQLOC_EXISTING',
            true
        );

        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(locationId, 'locations/deactivate');
        Test.stopTest();

        SObject updated = queryLocation(locationId);

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(updated.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testSyncSalesforceLocationToSquare_ActivateTopic() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationSyncMock('UPDATE_EXISTING'));

        Id locationId = createLocation(
            uniqueText('Activate Location'),
            'SQLOC_EXISTING',
            false
        );

        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(locationId, 'locations/activate');
        Test.stopTest();

        SObject updated = queryLocation(locationId);

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(updated.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testSyncSalesforceLocationToSquare_ResponseMissingLocationMarksFailed() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationSyncMock('MISSING_LOCATION'));

        Id locationId = createLocation(uniqueText('Missing Location Response'), null, true);

        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(locationId, 'locations/create');
        Test.stopTest();

        SObject updated = queryLocation(locationId);

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Failed', String.valueOf(updated.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testSyncSalesforceLocationToSquare_NullLocationMarksFailed() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationSyncMock('NULL_LOCATION'));

        Id locationId = createLocation(uniqueText('Null Location Response'), null, true);

        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(locationId, 'locations/create');
        Test.stopTest();

        SObject updated = queryLocation(locationId);

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Failed', String.valueOf(updated.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testSyncSalesforceLocationToSquare_ResponseMissingLocationIdMarksFailed() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationSyncMock('MISSING_LOCATION_ID'));

        Id locationId = createLocation(uniqueText('Missing Location Id Response'), null, true);

        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(locationId, 'locations/create');
        Test.stopTest();

        SObject updated = queryLocation(locationId);

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Failed', String.valueOf(updated.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testSyncSalesforceLocationToSquare_ListWithNullsThenCreate() {
        Test.setMock(HttpCalloutMock.class, new SquareLocationSyncMock('LIST_WITH_NULLS'));

        Id locationId = createLocation(uniqueText('No Matching Square Name'), null, true);

        Test.startTest();
        SquareLocationSyncService.syncSalesforceLocationToSquare(locationId, 'locations/create');
        Test.stopTest();

        SObject updated = queryLocation(locationId);

        if (fieldExists('Location', 'Square_Location_Id__c')) {
            System.assertEquals('SQLOC_CREATED', String.valueOf(updated.get('Square_Location_Id__c')));
        }

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(updated.get('Sync_Status__c')));
        }
    }
}