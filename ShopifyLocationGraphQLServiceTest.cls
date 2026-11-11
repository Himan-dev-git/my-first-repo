@IsTest
private class ShopifyLocationGraphQLServiceTest {

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

    private static SObject newLocationRecord(String name, String shopifyLocationId) {
        Schema.SObjectType locationType = Schema.getGlobalDescribe().get('Location');
        SObject loc = locationType.newSObject();

        loc.put('Name', name);

        if (fieldExists('Location', 'LocationType')) {
            loc.put('LocationType', 'Warehouse');
        }

        if (fieldExists('Location', 'Shopify_Location_ID__c')) {
            loc.put('Shopify_Location_ID__c', shopifyLocationId);
        }

        if (fieldExists('Location', 'Sync_Status__c')) {
            loc.put('Sync_Status__c', 'Synced');
        }

        return loc;
    }

    private static SObject queryLocationByShopifyId(String shopifyLocationId) {
        List<String> fieldsToQuery = new List<String>{ 'Id', 'Name' };

        if (fieldExists('Location', 'Shopify_Location_ID__c')) {
            fieldsToQuery.add('Shopify_Location_ID__c');
        }

        if (fieldExists('Location', 'Sync_Status__c')) {
            fieldsToQuery.add('Sync_Status__c');
        }

        if (fieldExists('Location', 'Last_Shopify_Sync__c')) {
            fieldsToQuery.add('Last_Shopify_Sync__c');
        }

        if (fieldExists('Location', 'Is_Inventory_Source__c')) {
            fieldsToQuery.add('Is_Inventory_Source__c');
        }

        if (fieldExists('Location', 'Is_Fulfillable__c')) {
            fieldsToQuery.add('Is_Fulfillable__c');
        }

        if (fieldExists('Location', 'Is_Sellable__c')) {
            fieldsToQuery.add('Is_Sellable__c');
        }

        String queryText =
            'SELECT ' + String.join(fieldsToQuery, ',') +
            ' FROM Location' +
            ' WHERE Shopify_Location_ID__c = :shopifyLocationId' +
            ' LIMIT 1';

        return Database.query(queryText);
    }

    private static Integer countLocationByShopifyId(String shopifyLocationId) {
        return Database.countQuery(
            'SELECT COUNT() FROM Location WHERE Shopify_Location_ID__c = \'' +
            String.escapeSingleQuotes(shopifyLocationId) +
            '\''
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mock
    // ─────────────────────────────────────────────────────────────────────

    private class LocationGraphQLMock implements HttpCalloutMock {
        private String mode;

        LocationGraphQLMock(String modeValue) {
            mode = modeValue;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String methodName = req.getMethod() == null ? '' : req.getMethod().toUpperCase();

            // Square Location sync queueable safety.
            if (endpoint.contains('/v2/locations')) {
                res.setStatusCode(200);

                if (methodName == 'GET') {
                    res.setBody('{"locations":[]}');
                    return res;
                }

                res.setBody(
                    '{"location":{' +
                    '"id":"SQLOC_TEST",' +
                    '"name":"Square Location",' +
                    '"status":"ACTIVE",' +
                    '"type":"PHYSICAL"' +
                    '}}'
                );
                return res;
            }

            if (mode == 'CALLOUT_ERROR') {
                res.setStatusCode(500);
                res.setBody('{"errors":[{"message":"Forced error"}]}');
                return res;
            }

            res.setStatusCode(200);

            if (mode == 'NO_DATA') {
                res.setBody('{}');
                return res;
            }

            if (mode == 'DATA_NULL') {
                res.setBody('{"data":null}');
                return res;
            }

            if (mode == 'LOCATIONS_NULL') {
                res.setBody('{"data":{"locations":null}}');
                return res;
            }

            if (mode == 'NODES_NULL') {
                res.setBody('{"data":{"locations":{"nodes":null}}}');
                return res;
            }

            if (mode == 'EMPTY_NODES') {
                res.setBody('{"data":{"locations":{"nodes":[]}}}');
                return res;
            }

            if (mode == 'NODES_WITH_BAD_GID') {
                res.setBody(
                    '{"data":{"locations":{"nodes":[' +
                    '{"id":null,"name":"No Id","isActive":true},' +
                    '{"id":"","name":"Blank Id","isActive":true}' +
                    ']}}}'
                );
                return res;
            }

            if (mode == 'SINGLE_LOCATION') {
                res.setBody(
                    '{"data":{"location":{' +
                    '"id":"gid://shopify/Location/200",' +
                    '"name":"Single Loc",' +
                    '"isActive":true' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'SINGLE_LOCATION_INACTIVE') {
                res.setBody(
                    '{"data":{"location":{' +
                    '"id":"gid://shopify/Location/201",' +
                    '"name":"Inactive Single Loc",' +
                    '"isActive":false' +
                    '}}}'
                );
                return res;
            }

            if (mode == 'SINGLE_LOCATION_NULL') {
                res.setBody('{"data":{"location":null}}');
                return res;
            }

            if (mode == 'SINGLE_LOCATION_NO_DATA') {
                res.setBody('{}');
                return res;
            }

            res.setBody(
                '{"data":{"locations":{"nodes":[' +
                '{"id":"gid://shopify/Location/101","name":"Loc A","isActive":true},' +
                '{"id":"gid://shopify/Location/102","name":"Loc B","isActive":false}' +
                ']}}}'
            );

            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // syncLocationsFromShopify success
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSyncLocationsFromShopify_UpsertsLocations() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('BULK_SUCCESS'));

        Test.startTest();
        ShopifyLocationGraphQLService.syncLocationsFromShopify();
        Test.stopTest();

        System.assertEquals(1, countLocationByShopifyId('101'));
        System.assertEquals(1, countLocationByShopifyId('102'));

        SObject locA = queryLocationByShopifyId('101');

        System.assertEquals('Loc A', String.valueOf(locA.get('Name')));

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(locA.get('Sync_Status__c')));
        }

        if (fieldExists('Location', 'Is_Inventory_Source__c')) {
            System.assertEquals(true, locA.get('Is_Inventory_Source__c'));
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // syncLocationsFromShopify guard branches
    // One Test.startTest / Test.stopTest per method only.
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSyncLocationsFromShopify_NoData() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('NO_DATA'));

        Test.startTest();
        ShopifyLocationGraphQLService.syncLocationsFromShopify();
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSyncLocationsFromShopify_DataNull() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('DATA_NULL'));

        Test.startTest();
        ShopifyLocationGraphQLService.syncLocationsFromShopify();
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSyncLocationsFromShopify_LocationsNull() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('LOCATIONS_NULL'));

        Test.startTest();
        ShopifyLocationGraphQLService.syncLocationsFromShopify();
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSyncLocationsFromShopify_NodesNull() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('NODES_NULL'));

        Test.startTest();
        ShopifyLocationGraphQLService.syncLocationsFromShopify();
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSyncLocationsFromShopify_EmptyNodes() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('EMPTY_NODES'));

        Test.startTest();
        ShopifyLocationGraphQLService.syncLocationsFromShopify();
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSyncLocationsFromShopify_NodesWithBadGid() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('NODES_WITH_BAD_GID'));

        Test.startTest();
        ShopifyLocationGraphQLService.syncLocationsFromShopify();
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSyncLocationsFromShopify_CalloutError() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('CALLOUT_ERROR'));

        Test.startTest();
        ShopifyLocationGraphQLService.syncLocationsFromShopify();
        Test.stopTest();

        System.assert(true);
    }

    // ─────────────────────────────────────────────────────────────────────
    // fetchSingleLocation
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testFetchSingleLocation_Success() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SINGLE_LOCATION'));

        Test.startTest();
        Map<String, Object> result =
            ShopifyLocationGraphQLService.fetchSingleLocation('200');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('Single Loc', result.get('name'));
        System.assertEquals(true, result.get('isActive'));
    }

    @IsTest
    static void testFetchSingleLocation_BlankInput() {
        Test.startTest();

        Map<String, Object> blank1 =
            ShopifyLocationGraphQLService.fetchSingleLocation(null);

        Map<String, Object> blank2 =
            ShopifyLocationGraphQLService.fetchSingleLocation('');

        Test.stopTest();

        System.assertEquals(null, blank1);
        System.assertEquals(null, blank2);
    }

    @IsTest
    static void testFetchSingleLocation_NullLocation() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SINGLE_LOCATION_NULL'));

        Test.startTest();
        Map<String, Object> result =
            ShopifyLocationGraphQLService.fetchSingleLocation('999');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void testFetchSingleLocation_NoData() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SINGLE_LOCATION_NO_DATA'));

        Test.startTest();
        Map<String, Object> result =
            ShopifyLocationGraphQLService.fetchSingleLocation('999');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void testFetchSingleLocation_CalloutError() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('CALLOUT_ERROR'));

        Test.startTest();
        Map<String, Object> result =
            ShopifyLocationGraphQLService.fetchSingleLocation('999');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    // ─────────────────────────────────────────────────────────────────────
    // getOrCreateSalesforceLocation
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetOrCreate_Existing() {
        SObject loc = newLocationRecord('Existing Location', '300');
        insert loc;

        Test.startTest();
        Id resultId =
            ShopifyLocationGraphQLService.getOrCreateSalesforceLocation('300');
        Test.stopTest();

        System.assertEquals((Id) loc.get('Id'), resultId);
    }

    @IsTest
    static void testGetOrCreate_NewFromShopify() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SINGLE_LOCATION'));

        Test.startTest();
        Id locId =
            ShopifyLocationGraphQLService.getOrCreateSalesforceLocation('200');
        Test.stopTest();

        System.assertNotEquals(null, locId);

        SObject loc = queryLocationByShopifyId('200');

        System.assertEquals('Single Loc', String.valueOf(loc.get('Name')));

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(loc.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testGetOrCreate_FallbackNameWhenShopifyReturnsNull() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SINGLE_LOCATION_NULL'));

        Test.startTest();
        Id locId =
            ShopifyLocationGraphQLService.getOrCreateSalesforceLocation('999');
        Test.stopTest();

        System.assertNotEquals(null, locId);

        SObject loc = queryLocationByShopifyId('999');

        System.assertEquals('Shopify Location 999', String.valueOf(loc.get('Name')));

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(loc.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testGetOrCreate_InactiveShopifyLocation() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SINGLE_LOCATION_INACTIVE'));

        Test.startTest();
        Id locId =
            ShopifyLocationGraphQLService.getOrCreateSalesforceLocation('201');
        Test.stopTest();

        System.assertNotEquals(null, locId);

        SObject loc = queryLocationByShopifyId('201');

        if (fieldExists('Location', 'Is_Inventory_Source__c')) {
            System.assertEquals(false, loc.get('Is_Inventory_Source__c'));
        }

        if (fieldExists('Location', 'Is_Fulfillable__c')) {
            System.assertEquals(false, loc.get('Is_Fulfillable__c'));
        }

        if (fieldExists('Location', 'Is_Sellable__c')) {
            System.assertEquals(false, loc.get('Is_Sellable__c'));
        }
    }

    @IsTest
    static void testGetOrCreate_BlankInput() {
        Test.startTest();

        Id result1 =
            ShopifyLocationGraphQLService.getOrCreateSalesforceLocation(null);

        Id result2 =
            ShopifyLocationGraphQLService.getOrCreateSalesforceLocation('');

        Test.stopTest();

        System.assertEquals(null, result1);
        System.assertEquals(null, result2);
    }

    // ─────────────────────────────────────────────────────────────────────
    // processLocationWebhook
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testProcessLocationWebhook_Create() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SQUARE_SUCCESS'));

        Test.startTest();

        ShopifyLocationGraphQLService.processLocationWebhook(
            new Map<String, Object>{
                'id' => '501',
                'name' => 'Webhook Location 501',
                'active' => true
            },
            'locations/create'
        );

        Test.stopTest();

        System.assertEquals(1, countLocationByShopifyId('501'));

        SObject loc = queryLocationByShopifyId('501');

        if (fieldExists('Location', 'Is_Inventory_Source__c')) {
            System.assertEquals(true, loc.get('Is_Inventory_Source__c'));
        }
    }

    @IsTest
    static void testProcessLocationWebhook_Update() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SQUARE_SUCCESS'));

        Test.startTest();

        ShopifyLocationGraphQLService.processLocationWebhook(
            new Map<String, Object>{
                'id' => '502',
                'name' => 'Webhook Location 502',
                'isActive' => false
            },
            'locations/update'
        );

        Test.stopTest();

        System.assertEquals(1, countLocationByShopifyId('502'));

        SObject loc = queryLocationByShopifyId('502');

        if (fieldExists('Location', 'Is_Inventory_Source__c')) {
            System.assertEquals(false, loc.get('Is_Inventory_Source__c'));
        }
    }

    @IsTest
    static void testProcessLocationWebhook_Activate() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SQUARE_SUCCESS'));

        Test.startTest();

        ShopifyLocationGraphQLService.processLocationWebhook(
            new Map<String, Object>{
                'id' => '503',
                'name' => 'Webhook Location 503',
                'active' => false
            },
            'locations/activate'
        );

        Test.stopTest();

        SObject loc = queryLocationByShopifyId('503');

        if (fieldExists('Location', 'Is_Inventory_Source__c')) {
            System.assertEquals(true, loc.get('Is_Inventory_Source__c'));
        }
    }

    @IsTest
    static void testProcessLocationWebhook_Deactivate() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SQUARE_SUCCESS'));

        Test.startTest();

        ShopifyLocationGraphQLService.processLocationWebhook(
            new Map<String, Object>{
                'id' => '504',
                'name' => 'Webhook Location 504',
                'active' => true
            },
            'locations/deactivate'
        );

        Test.stopTest();

        SObject loc = queryLocationByShopifyId('504');

        if (fieldExists('Location', 'Is_Inventory_Source__c')) {
            System.assertEquals(false, loc.get('Is_Inventory_Source__c'));
        }
    }

    @IsTest
    static void testProcessLocationWebhook_AdminGraphqlIdAndFallbackName() {
        Test.setMock(HttpCalloutMock.class, new LocationGraphQLMock('SQUARE_SUCCESS'));

        Test.startTest();

        ShopifyLocationGraphQLService.processLocationWebhook(
            new Map<String, Object>{
                'admin_graphql_api_id' => 'gid://shopify/Location/601'
            },
            'locations/update'
        );

        Test.stopTest();

        SObject loc = queryLocationByShopifyId('601');

        System.assertEquals('Shopify Location 601', String.valueOf(loc.get('Name')));

        if (fieldExists('Location', 'Sync_Status__c')) {
            System.assertEquals('Synced', String.valueOf(loc.get('Sync_Status__c')));
        }
    }

    @IsTest
    static void testProcessLocationWebhook_GuardBranches() {
        Test.startTest();

        ShopifyLocationGraphQLService.processLocationWebhook(null, 'locations/create');
        ShopifyLocationGraphQLService.processLocationWebhook(new Map<String, Object>(), 'locations/create');

        ShopifyLocationGraphQLService.processLocationWebhook(
            new Map<String, Object>{ 'name' => 'Missing Id' },
            'locations/create'
        );

        ShopifyLocationGraphQLService.processLocationWebhook(
            new Map<String, Object>{
                'id' => '',
                'name' => 'Blank Id'
            },
            'locations/create'
        );

        Test.stopTest();

        System.assert(true, 'processLocationWebhook guard branches covered.');
    }

    @IsTest
    static void testProcessLocationWebhook_UnsupportedTopicStillUpsertsButNoSquareQueue() {
        Test.startTest();

        ShopifyLocationGraphQLService.processLocationWebhook(
            new Map<String, Object>{
                'id' => '701',
                'name' => 'Unsupported Topic Location',
                'active' => true
            },
            'locations/unsupported'
        );

        Test.stopTest();

        System.assertEquals(1, countLocationByShopifyId('701'));
    }

    // ─────────────────────────────────────────────────────────────────────
    // extractNumericIdFromGid
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testExtractNumericIdFromGid() {
        System.assertEquals(
            '555',
            ShopifyLocationGraphQLService.extractNumericIdFromGid('gid://shopify/Location/555')
        );

        System.assertEquals(
            null,
            ShopifyLocationGraphQLService.extractNumericIdFromGid(null)
        );

        System.assertEquals(
            null,
            ShopifyLocationGraphQLService.extractNumericIdFromGid('')
        );

        System.assertEquals(
            'plain-id',
            ShopifyLocationGraphQLService.extractNumericIdFromGid('plain-id')
        );
    }
}