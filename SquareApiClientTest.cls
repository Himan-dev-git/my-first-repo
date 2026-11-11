@IsTest
private class SquareApiClientTest {

    private class SquareMock implements HttpCalloutMock {
        private String mode;
        private Integer callCount = 0;

        SquareMock(String mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest req) {
            callCount++;

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String methodName = req.getMethod();

            if (mode == 'VERSION_MISMATCH_RETRY_SUCCESS') {
                if (
                    endpoint != null &&
                    endpoint.contains('/v2/catalog/object/') &&
                    methodName == 'GET'
                ) {
                    res.setStatusCode(200);
                    res.setBody(
                        '{"object":{' +
                        '"id":"ITEM_EXISTING",' +
                        '"type":"ITEM",' +
                        '"version":99,' +
                        '"item_data":{' +
                        '"name":"Existing Item",' +
                        '"variations":[' +
                        '{"id":"VAR_EXISTING","version":55},' +
                        '{"id":"VAR_OTHER","version":77}' +
                        ']}}}'
                    );
                    return res;
                }

                if (
                    endpoint != null &&
                    endpoint.contains('/v2/catalog/object') &&
                    methodName == 'POST'
                ) {
                    if (callCount == 1) {
                        res.setStatusCode(400);
                        res.setBody(
                            '{"errors":[{"code":"VERSION_MISMATCH","detail":"Object version mismatch"}]}'
                        );
                    } else {
                        res.setStatusCode(200);
                        res.setBody(
                            '{"catalog_object":{' +
                            '"id":"ITEM_EXISTING",' +
                            '"type":"ITEM",' +
                            '"version":100}}'
                        );
                    }
                    return res;
                }
            }

            if (mode == 'VERSION_MISMATCH_RETRY_FAILURE') {
                if (
                    endpoint != null &&
                    endpoint.contains('/v2/catalog/object/') &&
                    methodName == 'GET'
                ) {
                    res.setStatusCode(200);
                    res.setBody(
                        '{"object":{' +
                        '"id":"ITEM_EXISTING",' +
                        '"type":"ITEM",' +
                        '"version":99}}'
                    );
                    return res;
                }

                if (
                    endpoint != null &&
                    endpoint.contains('/v2/catalog/object') &&
                    methodName == 'POST'
                ) {
                    res.setStatusCode(400);
                    res.setBody(
                        callCount == 1
                        ? '{"errors":[{"code":"VERSION_MISMATCH"}]}'
                        : '{"errors":[{"code":"BAD_REQUEST","detail":"Retry failed"}]}'
                    );
                    return res;
                }
            }

            if (mode == 'VERSION_MISMATCH_NO_ITEM') {
                if (
                    endpoint != null &&
                    endpoint.contains('/v2/catalog/object/') &&
                    methodName == 'GET'
                ) {
                    res.setStatusCode(200);
                    res.setBody('{}');
                    return res;
                }

                if (
                    endpoint != null &&
                    endpoint.contains('/v2/catalog/object') &&
                    methodName == 'POST'
                ) {
                    res.setStatusCode(400);
                    res.setBody(
                        '{"errors":[{"code":"VERSION_MISMATCH"}]}'
                    );
                    return res;
                }
            }

            if (mode != null && mode.startsWith('ERROR_')) {
                res.setStatusCode(400);
                res.setBody('{"errors":[{"detail":"Mock error"}]}');
                return res;
            }

            res.setStatusCode(200);

            if (endpoint != null && endpoint.contains('/v2/payments/')) {
                res.setBody(
                    '{"payment":{' +
                    '"id":"PAYMENT_123",' +
                    '"order_id":"ORDER_123",' +
                    '"team_member_id":"TEAM_123",' +
                    '"location_id":"LOC_123",' +
                    '"receipt_url":"https://example.com/receipt",' +
                    '"amount_money":{"amount":2500,"currency":"USD"}' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/team-members/')) {
                res.setBody(
                    '{"team_member":{' +
                    '"id":"TEAM_123",' +
                    '"given_name":"John",' +
                    '"family_name":"Doe"' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/catalog/object/') && methodName == 'GET') {
                res.setBody(
                    '{"object":{' +
                    '"id":"ITEM_123",' +
                    '"type":"ITEM",' +
                    '"item_data":{"name":"Test Item"}' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/catalog/object') && methodName == 'POST') {
                if (mode == 'UPSERT_NO_CATALOG_OBJECT') {
                    res.setBody('{"id_mappings":[]}');
                    return res;
                }

                res.setBody(
                    '{"catalog_object":{' +
                    '"id":"IMG_123",' +
                    '"type":"IMAGE",' +
                    '"image_data":{"name":"Product Image"}' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/catalog/images')) {
                res.setBody(
                    '{"image":{' +
                    '"id":"IMG_UPLOAD_123",' +
                    '"type":"IMAGE",' +
                    '"image_data":{"name":"Uploaded Image"}' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/orders/')) {
                res.setBody(
                    '{"order":{' +
                    '"id":"ORDER_123",' +
                    '"location_id":"LOC_123",' +
                    '"line_items":[]' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/refunds/')) {
                res.setBody(
                    '{"refund":{' +
                    '"id":"REFUND_123",' +
                    '"payment_id":"PAYMENT_123",' +
                    '"order_id":"ORDER_123",' +
                    '"status":"COMPLETED"' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/catalog/list')) {
                if (mode == 'CATALOG_PAGED_FIRST') {
                    res.setBody(
                        '{"objects":[' +
                        '{"id":"VAR_1","type":"ITEM_VARIATION"}' +
                        '],"cursor":"NEXT_CURSOR"}'
                    );
                    mode = 'CATALOG_PAGED_SECOND';
                    return res;
                }

                if (mode == 'CATALOG_PAGED_SECOND') {
                    res.setBody(
                        '{"objects":[' +
                        '{"id":"VAR_2","type":"ITEM_VARIATION"}' +
                        ']}'
                    );
                    return res;
                }

                if (mode == 'CATALOG_NO_OBJECTS') {
                    res.setBody('{}');
                    return res;
                }

                res.setBody(
                    '{"objects":[' +
                    '{"id":"VAR_1","type":"ITEM_VARIATION"}' +
                    ']}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/customers/')) {
                res.setBody(
                    '{"customer":{' +
                    '"id":"CUSTOMER_123",' +
                    '"given_name":"Jane",' +
                    '"family_name":"Doe",' +
                    '"email_address":"jane@example.com"' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.endsWith('/v2/locations') && methodName == 'GET') {
                if (mode == 'LOCATIONS_NO_KEY') {
                    res.setBody('{}');
                    return res;
                }

                if (mode == 'LOCATIONS_NULL') {
                    res.setBody('{"locations":null}');
                    return res;
                }

                res.setBody(
                    '{"locations":[' +
                    '{"id":"LOC_1","name":"Location One","status":"ACTIVE"},' +
                    '{"id":"LOC_2","name":"Location Two","status":"INACTIVE"}' +
                    ']}'
                );
                return res;
            }

            if (endpoint != null && endpoint.endsWith('/v2/locations') && methodName == 'POST') {
                res.setBody(
                    '{"location":{' +
                    '"id":"LOC_CREATED",' +
                    '"name":"Created Location",' +
                    '"type":"PHYSICAL",' +
                    '"status":"ACTIVE"' +
                    '}}'
                );
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/locations/') && methodName == 'GET') {
                if (mode == 'ERROR_LOCATION_RETRIEVE') {
                    res.setStatusCode(500);
                    res.setBody('{"errors":[{"detail":"Location API failed"}]}');
                } else {
                    res.setStatusCode(200);
                    res.setBody(
                        '{"location":{' +
                        '"id":"LOC_123",' +
                        '"name":"Test Square Location",' +
                        '"type":"PHYSICAL",' +
                        '"status":"ACTIVE"' +
                        '}}'
                    );
                }
                return res;
            }

            if (endpoint != null && endpoint.contains('/v2/locations/') && methodName == 'PUT') {
                res.setBody(
                    '{"location":{' +
                    '"id":"LOC_UPDATED",' +
                    '"name":"Updated Location",' +
                    '"type":"PHYSICAL",' +
                    '"status":"ACTIVE"' +
                    '}}'
                );
                return res;
            }

            res.setBody('{}');
            return res;
        }
    }

    @IsTest
    static void testRetrievePaymentBlankReturnsNull() {
        Test.startTest();
        Map<String, Object> payment = SquareApiClient.retrievePayment(null);
        Map<String, Object> payment2 = SquareApiClient.retrievePayment('');
        Test.stopTest();

        System.assertEquals(null, payment);
        System.assertEquals(null, payment2);
    }

    @IsTest
    static void testRetrievePaymentSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> payment = SquareApiClient.retrievePayment('PAYMENT 123');
        Test.stopTest();

        System.assertNotEquals(null, payment);
        System.assertEquals('PAYMENT_123', payment.get('id'));
        System.assertEquals('ORDER_123', payment.get('order_id'));
    }

    @IsTest
    static void testRetrievePaymentFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_PAYMENT'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.retrievePayment('PAYMENT_BAD');
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square payment retrieve failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testRetrieveTeamMemberSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> member = SquareApiClient.retrieveTeamMember('TEAM 123');
        Test.stopTest();

        System.assertNotEquals(null, member);
        System.assertEquals('TEAM_123', member.get('id'));
        System.assertEquals('John', member.get('given_name'));
    }

    @IsTest
    static void testRetrieveTeamMemberFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_TEAM'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.retrieveTeamMember('TEAM_BAD');
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square Team Member API failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testUpsertCatalogObjectSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Map<String, Object> catalogObject = new Map<String, Object>{
            'type' => 'ITEM',
            'id' => '#ITEM_TEST',
            'item_data' => new Map<String, Object>{
                'name' => 'Test Item'
            }
        };

        Test.startTest();
        Map<String, Object> response = SquareApiClient.upsertCatalogObject(catalogObject);
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.containsKey('catalog_object'));
    }

    @IsTest
    static void testUpsertCatalogObjectFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_UPSERT'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.upsertCatalogObject(new Map<String, Object>{
                'type' => 'ITEM',
                'id' => '#ITEM_BAD'
            });
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square catalog upsert failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testCreateImageObjectReturnsId() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        String imageId = SquareApiClient.createImageObject('https://example.com/image.jpg');
        Test.stopTest();

        System.assertEquals('IMG_123', imageId);
    }

    @IsTest
    static void testCreateImageObjectReturnsNullWhenNoCatalogObject() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('UPSERT_NO_CATALOG_OBJECT'));

        Test.startTest();
        String imageId = SquareApiClient.createImageObject('https://example.com/image.jpg');
        Test.stopTest();

        System.assertEquals(null, imageId);
    }

    @IsTest
    static void testCreateCatalogImageSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> response = SquareApiClient.createCatalogImage(
            'ITEM_123',
            'Uploaded Image',
            Blob.valueOf('fake image bytes'),
            'image.jpg',
            'image/jpeg'
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.containsKey('image'));
    }

    @IsTest
    static void testCreateCatalogImageDefaultsSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> response = SquareApiClient.createCatalogImage(
            'ITEM_123',
            null,
            Blob.valueOf('fake image bytes'),
            null,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.containsKey('image'));
    }

    @IsTest
    static void testCreateCatalogImageBlankSquareItemIdThrows() {
        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.createCatalogImage(
                '',
                'Image',
                Blob.valueOf('fake image bytes'),
                'image.jpg',
                'image/jpeg'
            );
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('squareItemId is blank'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testCreateCatalogImageBlankBlobThrows() {
        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.createCatalogImage(
                'ITEM_123',
                'Image',
                Blob.valueOf(''),
                'image.jpg',
                'image/jpeg'
            );
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('imageBlob is blank'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testCreateCatalogImageNullBlobThrows() {
        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.createCatalogImage(
                'ITEM_123',
                'Image',
                null,
                'image.jpg',
                'image/jpeg'
            );
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('imageBlob is blank'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testCreateCatalogImageFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_IMAGE'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.createCatalogImage(
                'ITEM_123',
                'Bad Image',
                Blob.valueOf('fake image bytes'),
                'image.jpg',
                'image/jpeg'
            );
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square catalog image upload failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testRetrieveOrderSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> orderMap = SquareApiClient.retrieveOrder('ORDER 123');
        Test.stopTest();

        System.assertNotEquals(null, orderMap);
        System.assertEquals('ORDER_123', orderMap.get('id'));
    }

    @IsTest
    static void testRetrieveOrderFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_ORDER'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.retrieveOrder('ORDER_BAD');
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square order retrieve failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testRetrieveSquareOrderSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> orderMap = SquareApiClient.retrieveSquareOrder('ORDER 123');
        Test.stopTest();

        System.assertNotEquals(null, orderMap);
        System.assertEquals('ORDER_123', orderMap.get('id'));
    }

    @IsTest
    static void testRetrieveSquareOrderFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_SQUARE_ORDER'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.retrieveSquareOrder('ORDER_BAD');
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square order retrieve failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testRetrieveRefundSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> refundMap = SquareApiClient.retrieveRefund('REFUND 123');
        Test.stopTest();

        System.assertNotEquals(null, refundMap);
        System.assertEquals('REFUND_123', refundMap.get('id'));
        System.assertEquals('COMPLETED', refundMap.get('status'));
    }

    @IsTest
    static void testRetrieveRefundFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_REFUND'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.retrieveRefund('REFUND_BAD');
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square refund retrieve failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testSearchCatalogItemVariationsSinglePage() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> result = SquareApiClient.searchCatalogItemVariations();
        Test.stopTest();

        List<Object> objectsList = (List<Object>) result.get('objects');

        System.assertEquals(1, objectsList.size());
    }

    @IsTest
    static void testSearchCatalogItemVariationsPaged() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('CATALOG_PAGED_FIRST'));

        Test.startTest();
        Map<String, Object> result = SquareApiClient.searchCatalogItemVariations();
        Test.stopTest();

        List<Object> objectsList = (List<Object>) result.get('objects');

        System.assertEquals(2, objectsList.size());
    }

    @IsTest
    static void testSearchCatalogItemVariationsNoObjects() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('CATALOG_NO_OBJECTS'));

        Test.startTest();
        Map<String, Object> result = SquareApiClient.searchCatalogItemVariations();
        Test.stopTest();

        List<Object> objectsList = (List<Object>) result.get('objects');

        System.assertEquals(0, objectsList.size());
    }

    @IsTest
    static void testSearchCatalogItemVariationsFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_CATALOG_LIST'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.searchCatalogItemVariations();
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square catalog list failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testRetrieveCatalogObjectSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> response = SquareApiClient.retrieveCatalogObject('ITEM 123');
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.containsKey('object'));
    }

    @IsTest
    static void testRetrieveCatalogObjectFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_CATALOG_OBJECT'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.retrieveCatalogObject('ITEM_BAD');
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square catalog object retrieve failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testRetrieveCustomerSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> customer = SquareApiClient.retrieveCustomer('CUSTOMER 123');
        Test.stopTest();

        System.assertNotEquals(null, customer);
        System.assertEquals('CUSTOMER_123', customer.get('id'));
        System.assertEquals('jane@example.com', customer.get('email_address'));
    }

    @IsTest
    static void testRetrieveCustomerFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_CUSTOMER'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.retrieveCustomer('CUSTOMER_BAD');
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square customer retrieve failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testCreateSquareLocationSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> response = SquareApiClient.createSquareLocation(
            'Created Location',
            true
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.containsKey('location'));

        Map<String, Object> locationMap = (Map<String, Object>) response.get('location');
        System.assertEquals('LOC_CREATED', locationMap.get('id'));
    }

    @IsTest
    static void testCreateSquareLocationBlankNameThrows() {
        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.createSquareLocation('', true);
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('locationName is blank'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testCreateSquareLocationFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_LOCATION_CREATE'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.createSquareLocation('Bad Location', true);
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square location create failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testUpdateSquareLocationSuccessActive() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> response = SquareApiClient.updateSquareLocation(
            'LOC_123',
            'Updated Location',
            true
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.containsKey('location'));

        Map<String, Object> locationMap = (Map<String, Object>) response.get('location');
        System.assertEquals('LOC_UPDATED', locationMap.get('id'));
    }

    @IsTest
    static void testUpdateSquareLocationSuccessInactive() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> response = SquareApiClient.updateSquareLocation(
            'LOC_123',
            'Updated Location',
            false
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.containsKey('location'));
    }

    @IsTest
    static void testUpdateSquareLocationSuccessNullActiveStatus() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> response = SquareApiClient.updateSquareLocation(
            'LOC_123',
            'Updated Location',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.containsKey('location'));
    }

    @IsTest
    static void testUpdateSquareLocationBlankSquareIdThrows() {
        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.updateSquareLocation('', 'Updated Location', true);
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('squareLocationId is blank'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testUpdateSquareLocationBlankNameThrows() {
        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.updateSquareLocation('LOC_123', '', true);
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('locationName is blank'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testUpdateSquareLocationFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_LOCATION_UPDATE'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.updateSquareLocation('LOC_BAD', 'Bad Location', true);
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square location update failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testListSquareLocationsSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        List<Object> locations = SquareApiClient.listSquareLocations();
        Test.stopTest();

        System.assertEquals(2, locations.size());

        Map<String, Object> firstLocation = (Map<String, Object>) locations[0];
        System.assertEquals('LOC_1', firstLocation.get('id'));
    }

    @IsTest
    static void testListSquareLocationsNoKeyReturnsEmptyList() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('LOCATIONS_NO_KEY'));

        Test.startTest();
        List<Object> locations = SquareApiClient.listSquareLocations();
        Test.stopTest();

        System.assertEquals(0, locations.size());
    }

    @IsTest
    static void testListSquareLocationsNullReturnsEmptyList() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('LOCATIONS_NULL'));

        Test.startTest();
        List<Object> locations = SquareApiClient.listSquareLocations();
        Test.stopTest();

        System.assertEquals(0, locations.size());
    }

    @IsTest
    static void testListSquareLocationsFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_LOCATION_LIST'));

        Boolean thrown = false;

        Test.startTest();
        try {
            SquareApiClient.listSquareLocations();
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Square list locations failed'));
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testIsSuccessfulResponseBranches() {
        HttpResponse success = new HttpResponse();
        success.setStatusCode(200);

        HttpResponse redirect = new HttpResponse();
        redirect.setStatusCode(302);

        System.assertEquals(
            true,
            SquareApiClient.isSuccessfulResponse(success)
        );

        System.assertEquals(
            false,
            SquareApiClient.isSuccessfulResponse(redirect)
        );

        System.assertEquals(
            false,
            SquareApiClient.isSuccessfulResponse(null)
        );
    }

    @IsTest
    static void testIsSquareVersionMismatchBranches() {
        HttpResponse mismatch = new HttpResponse();
        mismatch.setStatusCode(400);
        mismatch.setBody(
            '{"errors":[{"code":"VERSION_MISMATCH"}]}'
        );

        HttpResponse wrongStatus = new HttpResponse();
        wrongStatus.setStatusCode(500);
        wrongStatus.setBody(
            '{"errors":[{"code":"VERSION_MISMATCH"}]}'
        );

        HttpResponse blankBody = new HttpResponse();
        blankBody.setStatusCode(400);
        blankBody.setBody('');

        System.assertEquals(
            true,
            SquareApiClient.isSquareVersionMismatch(mismatch)
        );

        System.assertEquals(
            false,
            SquareApiClient.isSquareVersionMismatch(wrongStatus)
        );

        System.assertEquals(
            false,
            SquareApiClient.isSquareVersionMismatch(blankBody)
        );

        System.assertEquals(
            false,
            SquareApiClient.isSquareVersionMismatch(null)
        );
    }

    @IsTest
    static void testUpsertCatalogObjectVersionMismatchRetrySuccess() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareMock('VERSION_MISMATCH_RETRY_SUCCESS')
        );

        Map<String, Object> existingVariation =
            new Map<String, Object>{
                'type' => 'ITEM_VARIATION',
                'id' => 'VAR_EXISTING',
                'item_variation_data' =>
                    new Map<String, Object>{
                        'item_id' => 'ITEM_EXISTING'
                    }
            };

        Map<String, Object> newVariation =
            new Map<String, Object>{
                'type' => 'ITEM_VARIATION',
                'id' => '#VAR_NEW',
                'item_variation_data' =>
                    new Map<String, Object>{
                        'item_id' => 'ITEM_EXISTING'
                    }
            };

        Map<String, Object> catalogObject =
            new Map<String, Object>{
                'type' => 'ITEM',
                'id' => 'ITEM_EXISTING',
                'item_data' =>
                    new Map<String, Object>{
                        'name' => 'Existing Item',
                        'variations' =>
                            new List<Object>{
                                existingVariation,
                                newVariation,
                                null,
                                'invalid variation'
                            }
                    }
            };

        Test.startTest();

        Map<String, Object> response =
            SquareApiClient.upsertCatalogObject(
                catalogObject
            );

        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(99, catalogObject.get('version'));
        System.assertEquals(55, existingVariation.get('version'));
        System.assertEquals(false, newVariation.containsKey('version'));
    }

    @IsTest
    static void testUpsertCatalogObjectVersionMismatchRetryFailure() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareMock('VERSION_MISMATCH_RETRY_FAILURE')
        );

        Map<String, Object> catalogObject =
            new Map<String, Object>{
                'type' => 'ITEM',
                'id' => 'ITEM_EXISTING',
                'item_data' =>
                    new Map<String, Object>{
                        'name' => 'Existing Item'
                    }
            };

        Boolean thrown = false;

        Test.startTest();

        try {
            SquareApiClient.upsertCatalogObject(
                catalogObject
            );
        } catch (CalloutException e) {
            thrown = true;

            System.assert(
                e.getMessage().contains(
                    'failed after refreshing versions'
                )
            );
        }

        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testUpsertCatalogObjectVersionMismatchMissingItemThrows() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareMock('VERSION_MISMATCH_NO_ITEM')
        );

        Boolean thrown = false;

        Test.startTest();

        try {
            SquareApiClient.upsertCatalogObject(
                new Map<String, Object>{
                    'type' => 'ITEM',
                    'id' => 'ITEM_EXISTING'
                }
            );
        } catch (CalloutException e) {
            thrown = true;

            System.assert(
                e.getMessage().contains(
                    'Square catalog item was not returned'
                )
            );
        }

        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testRefreshCatalogObjectVersionsEarlyReturns() {
        Test.startTest();

        SquareApiClient.refreshCatalogObjectVersions(null);

        SquareApiClient.refreshCatalogObjectVersions(
            new Map<String, Object>()
        );

        SquareApiClient.refreshCatalogObjectVersions(
            new Map<String, Object>{
                'id' => ''
            }
        );

        SquareApiClient.refreshCatalogObjectVersions(
            new Map<String, Object>{
                'id' => '#ITEM_NEW'
            }
        );

        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testRefreshCatalogObjectVersionsHandlesMissingCollections() {
        Test.setMock(
            HttpCalloutMock.class,
            new SquareMock('SUCCESS')
        );

        Map<String, Object> noOutgoingItemData =
            new Map<String, Object>{
                'id' => 'ITEM_123',
                'type' => 'ITEM'
            };

        Map<String, Object> invalidOutgoingVariations =
            new Map<String, Object>{
                'id' => 'ITEM_123',
                'type' => 'ITEM',
                'item_data' =>
                    new Map<String, Object>{
                        'name' => 'Test Item',
                        'variations' => 'not-a-list'
                    }
            };

        Test.startTest();

        SquareApiClient.refreshCatalogObjectVersions(
            noOutgoingItemData
        );

        SquareApiClient.refreshCatalogObjectVersions(
            invalidOutgoingVariations
        );

        Test.stopTest();

        System.assert(true);
    }



    // =====================================================================
    // Retrieve Square Location tests
    // =====================================================================

    @IsTest
    static void testRetrieveSquareLocationBlankReturnsNull() {
        Test.startTest();
        Map<String, Object> nullResult = SquareApiClient.retrieveSquareLocation(null);
        Map<String, Object> blankResult = SquareApiClient.retrieveSquareLocation('');
        Test.stopTest();

        System.assertEquals(null, nullResult);
        System.assertEquals(null, blankResult);
    }

    @IsTest
    static void testRetrieveSquareLocationSuccess() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('SUCCESS'));

        Test.startTest();
        Map<String, Object> location = SquareApiClient.retrieveSquareLocation('LOC_123');
        Test.stopTest();

        System.assertNotEquals(null, location);
        System.assertEquals('LOC_123', location.get('id'));
        System.assertEquals('Test Square Location', location.get('name'));
    }

    @IsTest
    static void testRetrieveSquareLocationFailure() {
        Test.setMock(HttpCalloutMock.class, new SquareMock('ERROR_LOCATION_RETRIEVE'));

        Boolean thrown = false;
        Test.startTest();
        try {
            SquareApiClient.retrieveSquareLocation('LOC_BAD');
        } catch (CalloutException e) {
            thrown = true;
            System.assert(
                e.getMessage().contains('Square location retrieve failed'),
                'Expected the Square location retrieval error.'
            );
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected a CalloutException for a failed response.');
    }

}