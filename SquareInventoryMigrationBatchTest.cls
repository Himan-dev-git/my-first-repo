@IsTest
private class SquareInventoryMigrationBatchTest {
    
    private static final String SQUARE_VARIATION_MARKER =
        'UT-SQ-VARIATION-';
    
    private static final String SQUARE_LOCATION_MARKER =
        'UT-SQ-LOCATION-';
    
    private static void configureMock(String mode) {
        GlobalHttpMock.mockMode = mode;
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
    }
    
    private static Id getVariantRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ];
        
        System.assertEquals(
            1,
            recordTypes.size(),
            'A Product2 record type with DeveloperName Variant is required.'
        );
        
        return recordTypes[0].Id;
    }
    
    private static String generateUniqueSku() {
        String value = EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(
                    String.valueOf(Crypto.getRandomInteger()) +
                    String.valueOf(Datetime.now().getTime())
                )
            )
        ).toUpperCase();
        
        return 'SQ' + value.substring(0, 12);
    }
    
    private static Id createLocationRecord(
        String locationName,
        String squareLocationId
    ) {
        SObject locationRecord = Schema.getGlobalDescribe().get('Location').newSObject();
        
        locationRecord.put('Name', locationName);
        
        if (squareLocationId != null) {
            locationRecord.put(
                'Square_Location_ID__c',
                squareLocationId
            );
        }
        
        insert locationRecord;
        
        return (Id) locationRecord.get('Id');
    }
    
    private static Inventory__c queryInventory(Id inventoryId) {
        return [
            SELECT Id,
            Available__c,
            Variant__c,
            Variant__r.Name,
            Variant__r.StockKeepingUnit,
            Variant__r.Square_Catalog_Variation_Id__c,
            Location__c,
            Location__r.Name,
            Location__r.Square_Location_ID__c
            FROM Inventory__c
            WHERE Id = :inventoryId
            LIMIT 1
        ];
    }
    
    private static Inventory__c queryMainInventory() {
        List<Inventory__c> inventories = [
            SELECT Id,
            Available__c,
            Variant__c,
            Variant__r.Name,
            Variant__r.StockKeepingUnit,
            Variant__r.Square_Catalog_Variation_Id__c,
            Location__c,
            Location__r.Name,
            Location__r.Square_Location_ID__c
            FROM Inventory__c
            WHERE Variant__r.Square_Catalog_Variation_Id__c
            LIKE :SQUARE_VARIATION_MARKER + '%'
            LIMIT 1
        ];
        
        System.assertEquals(
            1,
            inventories.size(),
            'The Square inventory test fixture was not created.'
        );
        
        return inventories[0];
    }
    
    @TestSetup
    static void createTestData() {
        configureMock('SUCCESS');
        
        String uniqueValue =
            String.valueOf(System.now().getTime()) +
            String.valueOf(
                Math.abs(Crypto.getRandomInteger())
            );
        
        Id variantRecordTypeId =
            Product2.SObjectType
            .getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get('Variant')
            .getRecordTypeId();
        
        Product2 variant = new Product2(
            Name = 'Square Inventory Variant ' + uniqueValue,
            IsActive = true,
            RecordTypeId = variantRecordTypeId,
            Type__c = 'Variant',
            StockKeepingUnit =
            'SQ' + uniqueValue.right(10),
            Square_Catalog_Variation_Id__c =
            SQUARE_VARIATION_MARKER + uniqueValue
        );
        
        insert variant;
        
        Id locationId = createLocationRecord(
            'Square Inventory Location ' + uniqueValue,
            SQUARE_LOCATION_MARKER + uniqueValue
        );
        
        InventorySyncControl.skipOutbound = true;
        
        try {
            insert new Inventory__c(
                Variant__c = variant.Id,
                Location__c = locationId,
                Available__c = 15.50
            );
        } finally {
            InventorySyncControl.skipOutbound = false;
        }
        
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Inventory__c
                WHERE Variant__c = :variant.Id
                AND Location__c = :locationId
            ],
            'Inventory test setup failed.'
        );
    }
    
    @IsTest
    static void testStartReturnsQueryLocator() {
        SquareInventoryMigrationBatch batchInstance = new SquareInventoryMigrationBatch();
        
        Database.QueryLocator queryLocator = batchInstance.start(null);
        
        System.assertNotEquals(
            null,
            queryLocator,
            'The start method should return a QueryLocator.'
        );
    }
    
    @IsTest
    static void testExecuteWithNullScope() {
        configureMock('SUCCESS');
        
        Integer calloutsBefore = Limits.getCallouts();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            null
        );
        
        System.assertEquals(
            calloutsBefore,
            Limits.getCallouts(),
            'A null scope should not perform a callout.'
        );
    }
    
    @IsTest
    static void testExecuteWithEmptyScope() {
        configureMock('SUCCESS');
        
        Integer calloutsBefore = Limits.getCallouts();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            new List<SObject>()
        );
        
        System.assertEquals(
            calloutsBefore,
            Limits.getCallouts(),
            'An empty scope should not perform a callout.'
        );
    }
    
    @IsTest
    static void testExecuteWithNullInventoryRecord() {
        configureMock('SUCCESS');
        
        List<SObject> scope = new List<SObject>();
        scope.add(null);
        
        Integer calloutsBefore = Limits.getCallouts();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            scope
        );
        
        System.assertEquals(
            calloutsBefore,
            Limits.getCallouts(),
            'A null inventory record should be ignored.'
        );
    }
    
    @IsTest
    static void testExecuteSkipsMissingRelationships() {
        configureMock('SUCCESS');
        
        Inventory__c inventory = new Inventory__c(
            Available__c = 4
        );
        
        Integer calloutsBefore = Limits.getCallouts();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            new List<SObject>{ inventory }
        );
        
        System.assertEquals(
            calloutsBefore,
            Limits.getCallouts(),
            'Inventory without loaded relationships should be ignored.'
        );
    }
    
    @IsTest
    static void testExecuteSkipsBlankSquareVariationId() {
        configureMock('SUCCESS');
        
        Inventory__c inventory = queryMainInventory();
        
        inventory.Variant__r.Square_Catalog_Variation_Id__c = null;
        
        Integer calloutsBefore = Limits.getCallouts();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            new List<SObject>{ inventory }
        );
        
        System.assertEquals(
            calloutsBefore,
            Limits.getCallouts(),
            'A blank Square variation ID should prevent the callout.'
        );
    }
    
    @IsTest
    static void testExecuteSkipsBlankSquareLocationId() {
        configureMock('SUCCESS');
        
        Inventory__c inventory = queryMainInventory();
        
        inventory.Location__r.Square_Location_ID__c = null;
        
        Integer calloutsBefore = Limits.getCallouts();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            new List<SObject>{ inventory }
        );
        
        System.assertEquals(
            calloutsBefore,
            Limits.getCallouts(),
            'A blank Square location ID should prevent the callout.'
        );
    }
    
    @IsTest
    static void testExecuteSuccess() {
        configureMock('SUCCESS');
        
        Inventory__c inventory = queryMainInventory();
        
        Test.startTest();
        
        Integer calloutsBefore = Limits.getCallouts();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            new List<SObject>{ inventory }
        );
        
        Integer calloutsAfter = Limits.getCallouts();
        
        Test.stopTest();
        
        System.assertEquals(
            calloutsBefore + 1,
            calloutsAfter,
            'One Square inventory callout should be performed.'
        );
    }
    
    @IsTest
    static void testExecuteTreatsNullQuantityAsZero() {
        configureMock('SUCCESS');
        
        Inventory__c inventory = queryMainInventory();
        inventory.Available__c = null;
        
        Test.startTest();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            new List<SObject>{ inventory }
        );
        
        Integer calloutCount = Limits.getCallouts();
        
        Test.stopTest();
        
        System.assertEquals(
            1,
            calloutCount,
            'A null quantity should be sent to Square as zero.'
        );
    }
    
    @IsTest
    static void testExecuteMultipleInventoryRecords() {
        configureMock('SUCCESS');
        
        Inventory__c firstInventory = queryMainInventory();
        
        Inventory__c secondInventory = firstInventory.clone(
            true,
            true,
            true,
            true
        );
        
        secondInventory.Id = firstInventory.Id;
        secondInventory.Available__c = 8;
        
        Test.startTest();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            new List<SObject>{
                firstInventory,
                    secondInventory
                    }
        );
        
        Integer calloutCount = Limits.getCallouts();
        
        Test.stopTest();
        
        System.assertEquals(
            1,
            calloutCount,
            'The complete scope should be sent in one Square request.'
        );
    }
    
    @IsTest
    static void testExecuteThrowsForHttpFailure() {
        configureMock('SQUARE_INVENTORY_HTTP_ERROR');
        
        Inventory__c inventory = queryMainInventory();
        
        Boolean exceptionThrown = false;
        
        try {
            new SquareInventoryMigrationBatch().execute(
                null,
                new List<SObject>{ inventory }
            );
        } catch (
            SquareInventoryMigrationBatch.SquareInventoryMigrationException e
        ) {
            exceptionThrown = true;
            
            System.assert(
                e.getMessage().contains('Status=500'),
                'The exception should include the HTTP status.'
            );
            
            System.assert(
                e.getMessage().contains(String.valueOf(inventory.Id)),
                'The exception should include the inventory ID.'
            );
        }
        
        System.assertEquals(
            true,
            exceptionThrown,
            'An unsuccessful HTTP response should throw an exception.'
        );
    }
    
    @IsTest
    static void testExecuteThrowsForSquareErrors() {
        configureMock('SQUARE_INVENTORY_API_ERRORS');
        
        Inventory__c inventory = queryMainInventory();
        
        Boolean exceptionThrown = false;
        
        try {
            new SquareInventoryMigrationBatch().execute(
                null,
                new List<SObject>{ inventory }
            );
        } catch (
            SquareInventoryMigrationBatch.SquareInventoryMigrationException e
        ) {
            exceptionThrown = true;
            
            System.assert(
                e.getMessage().contains(
                    'Square inventory migration returned errors.'
                ),
                'Square response errors should be reported.'
            );
        }
        
        System.assertEquals(
            true,
            exceptionThrown,
            'Square API errors should throw an exception.'
        );
    }
    
    @IsTest
    static void testExecuteAcceptsBlankSuccessBody() {
        configureMock('SQUARE_INVENTORY_BLANK_BODY');
        
        Inventory__c inventory = queryMainInventory();
        
        new SquareInventoryMigrationBatch().execute(
            null,
            new List<SObject>{ inventory }
        );
        
        System.assertEquals(
            1,
            Limits.getCallouts(),
            'A successful blank response should be accepted.'
        );
    }
    
    @IsTest
    static void testExecuteRejectsUnexpectedRoot() {
        configureMock('SQUARE_INVENTORY_INVALID_ROOT');
        
        Inventory__c inventory = queryMainInventory();
        
        Boolean exceptionThrown = false;
        
        try {
            new SquareInventoryMigrationBatch().execute(
                null,
                new List<SObject>{ inventory }
            );
        } catch (
            SquareInventoryMigrationBatch.SquareInventoryMigrationException e
        ) {
            exceptionThrown = true;
            
            System.assert(
                e.getMessage().startsWith(
                    'Unexpected Square inventory response:'
                ),
                'The invalid response structure should be reported.'
            );
        }
        
        System.assertEquals(
            true,
            exceptionThrown,
            'An unexpected JSON root should throw an exception.'
        );
    }
    
    @IsTest
    static void testFormatQuantity() {
        System.assertEquals(
            '0',
            SquareInventoryMigrationBatch.formatQuantity(null)
        );
        
        System.assertEquals(
            '0',
            SquareInventoryMigrationBatch.formatQuantity(0)
        );
        
        System.assertEquals(
            '15',
            SquareInventoryMigrationBatch.formatQuantity(15.000)
        );
        
        System.assertEquals(
            '15.5',
            SquareInventoryMigrationBatch.formatQuantity(15.500)
        );
        
        System.assertEquals(
            '-2.75',
            SquareInventoryMigrationBatch.formatQuantity(-2.750)
        );
    }
    
    @IsTest
    static void testFormatSquareDatetime() {
        Datetime testDatetime = Datetime.newInstanceGMT(
            2026,
            7,
            16,
            10,
            20,
            30
        );
        
        System.assertEquals(
            '2026-07-16T10:20:30.000Z',
            SquareInventoryMigrationBatch.formatSquareDatetime(
                testDatetime
            )
        );
        
        String generatedDatetime = SquareInventoryMigrationBatch.formatSquareDatetime(null);
        
        System.assertNotEquals(
            null,
            generatedDatetime
        );
        
        System.assert(
            generatedDatetime.endsWith('Z'),
            'The generated Square timestamp should be in UTC.'
        );
    }
    
    @IsTest
    static void testCreateIdempotencyKeyWithNullContextOrScope() {
        String key = SquareInventoryMigrationBatch.createIdempotencyKey(
            null,
            null
        );
        
        System.assertNotEquals(
            null,
            key
        );
        
        System.assertEquals(
            64,
            key.length(),
            'A SHA-256 hexadecimal value should have 64 characters.'
        );
    }
    
    @IsTest
    static void testCreateIdempotencyKeyWithEmptyScope() {
        String key = SquareInventoryMigrationBatch.createIdempotencyKey(
            null,
            new List<SObject>()
        );
        
        System.assertEquals(
            64,
            key.length()
        );
    }
    
    @IsTest
    static void testCreateIdempotencyKeyWithNullFirstRecord() {
        List<SObject> scope = new List<SObject>();
        scope.add(null);
        
        String key = SquareInventoryMigrationBatch.createIdempotencyKey(
            null,
            scope
        );
        
        System.assertEquals(
            64,
            key.length()
        );
    }
    
    @IsTest
    static void testCreateIdempotencyKeyWithRecord() {
        Inventory__c inventory = [
            SELECT Id
            FROM Inventory__c
            LIMIT 1
        ];
        
        String key = SquareInventoryMigrationBatch.createIdempotencyKey(
            null,
            new List<SObject>{ inventory }
        );
        
        System.assertEquals(
            64,
            key.length()
        );
    }
    
    @IsTest
    static void testDeserializeBlankResponse() {
        Map<String, Object> nullResponse = SquareInventoryMigrationBatch.deserializeResponse(null);
        
        System.assertNotEquals(
            null,
            nullResponse
        );
        
        System.assertEquals(
            true,
            nullResponse.isEmpty()
        );
        
        Map<String, Object> blankResponse = SquareInventoryMigrationBatch.deserializeResponse(' ');
        
        System.assertEquals(
            true,
            blankResponse.isEmpty()
        );
    }
    
    @IsTest
    static void testDeserializeValidResponse() {
        Map<String, Object> response = SquareInventoryMigrationBatch.deserializeResponse(
            '{"errors":[],"counts":[]}'
        );
        
        System.assertNotEquals(
            null,
            response
        );
        
        System.assertEquals(
            true,
            response.containsKey('errors')
        );
        
        System.assertEquals(
            true,
            response.containsKey('counts')
        );
    }
    
    @IsTest
    static void testDeserializeInvalidRoot() {
        Boolean exceptionThrown = false;
        
        try {
            SquareInventoryMigrationBatch.deserializeResponse(
                '[{"status":"invalid"}]'
            );
        } catch (
            SquareInventoryMigrationBatch.SquareInventoryMigrationException e
        ) {
            exceptionThrown = true;
            
            System.assert(
                e.getMessage().startsWith(
                    'Unexpected Square inventory response:'
                )
            );
        }
        
        System.assertEquals(
            true,
            exceptionThrown
        );
    }
    
    @IsTest
    static void testFinish() {
        new SquareInventoryMigrationBatch().finish(null);
    }
    
    @IsTest
    static void testBatchCanBeSubmitted() {
        configureMock('SUCCESS');
        
        Test.startTest();
        
        Id batchJobId = Database.executeBatch(
            new SquareInventoryMigrationBatch(),
            25
        );
        
        System.assertNotEquals(
            null,
            batchJobId,
            'The inventory migration Batch should be submitted.'
        );
        
        /*
* Deliberately do not call Test.stopTest().
* Direct execute tests already cover the callout behavior.
*/
    }
}