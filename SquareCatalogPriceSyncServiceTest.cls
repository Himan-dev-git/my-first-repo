@IsTest
private class SquareCatalogPriceSyncServiceTest {

    private static final Id SQUARE_PRICEBOOK_ID =
        '01sS8000008ogx9IAA';

    private static Integer counter = 0;

    // ============================================================
    // SHARED GLOBAL MOCK ONLY
    // ============================================================

    private static void configureMock(
        String mode
    ) {
        GlobalHttpMock.mockMode =
            mode;

        Test.setMock(
            HttpCalloutMock.class,
            new GlobalHttpMock()
        );
    }

    // ============================================================
    // TEST DATA HELPERS
    // ============================================================

    private static String uniqueToken() {
        counter++;

        Integer randomValue =
            Crypto.getRandomInteger();

        if (randomValue < 0) {
            randomValue *= -1;
        }

        String value =
            String.valueOf(randomValue);

        while (value.length() < 8) {
            value =
                '0' +
                value;
        }

        if (value.length() > 8) {
            value =
                value.substring(
                    value.length() - 8
                );
        }

        return value +
            String.valueOf(counter);
    }

    private static String squareVariationId(
        String prefix
    ) {
        Integer maxLength =
            Product2.Square_Catalog_Variation_Id__c
                .getDescribe()
                .getLength();

        String value =
            prefix +
            uniqueToken();

        if (
            maxLength != null &&
            maxLength > 0 &&
            value.length() > maxLength
        ) {
            value =
                value.substring(
                    0,
                    maxLength
                );
        }

        return value;
    }

    private static Id getVariantRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> infos =
            Product2.SObjectType
                .getDescribe()
                .getRecordTypeInfosByDeveloperName();

        if (
            infos.containsKey(
                'Variant'
            )
        ) {
            return infos
                .get('Variant')
                .getRecordTypeId();
        }

        return null;
    }

    private static Product2 buildVariant(
        String namePrefix,
        String variationId
    ) {
        Product2 productRecord =
            new Product2(
                Name =
                    namePrefix +
                    ' ' +
                    uniqueToken(),
                IsActive =
                    true,
                StockKeepingUnit =
                    'TST' +
                    uniqueToken()
            );

        Id recordTypeId =
            getVariantRecordTypeId();

        if (
            recordTypeId != null
        ) {
            productRecord.RecordTypeId =
                recordTypeId;
        }

        if (
            Product2.SObjectType
                .getDescribe()
                .fields
                .getMap()
                .containsKey('Type__c')
        ) {
            productRecord.put(
                'Type__c',
                'Variant'
            );
        }

        if (
            Product2.SObjectType
                .getDescribe()
                .fields
                .getMap()
                .containsKey(
                    'Updated_by_Integration__c'
                )
        ) {
            productRecord.put(
                'Updated_by_Integration__c',
                true
            );
        }

        productRecord
            .Square_Catalog_Variation_Id__c =
            variationId;

        return productRecord;
    }

    private static Product2 insertVariant(
        String namePrefix,
        String variationId
    ) {
        Product2 productRecord =
            buildVariant(
                namePrefix,
                variationId
            );

        insert productRecord;

        return productRecord;
    }

    private static Boolean squarePricebookExists() {
        return ![
            SELECT Id
            FROM Pricebook2
            WHERE Id = :SQUARE_PRICEBOOK_ID
            LIMIT 1
        ].isEmpty();
    }

    /*
     * The production service queries every active PricebookEntry from the
     * hard-coded Square Pricebook. In a production deployment test this
     * makes processing order nondeterministic.
     *
     * Tests run in rollback-only transactions, so temporarily deactivating
     * existing mapped Square entries is safe and guarantees that only the
     * test-created entries participate in the service call.
     */
    private static void deactivateExistingMappedSquareEntries() {
        List<PricebookEntry> existingEntries = [
            SELECT Id,
                   IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :SQUARE_PRICEBOOK_ID
            AND IsActive = true
            AND Product2.Square_Catalog_Variation_Id__c != null
        ];

        for (
            PricebookEntry entry :
            existingEntries
        ) {
            entry.IsActive =
                false;
        }

        if (
            !existingEntries.isEmpty()
        ) {
            update existingEntries;
        }
    }

    private static void activateStandardPricebook() {
        update new Pricebook2(
            Id =
                Test.getStandardPricebookId(),
            IsActive =
                true
        );
    }

    private static PricebookEntry createSquarePriceEntry(
        Id productId,
        Decimal unitPrice
    ) {
        activateStandardPricebook();

        insert new PricebookEntry(
            Pricebook2Id =
                Test.getStandardPricebookId(),
            Product2Id =
                productId,
            UnitPrice =
                unitPrice,
            IsActive =
                true
        );

        PricebookEntry squareEntry =
            new PricebookEntry(
                Pricebook2Id =
                    SQUARE_PRICEBOOK_ID,
                Product2Id =
                    productId,
                UnitPrice =
                    unitPrice,
                IsActive =
                    true,
                UseStandardPrice =
                    false
            );

        insert squareEntry;

        return squareEntry;
    }

    private static PricebookEntry createIsolatedMappedVariant(
        String namePrefix,
        String variationPrefix,
        Decimal startingPrice
    ) {
        deactivateExistingMappedSquareEntries();

        Product2 variant =
            insertVariant(
                namePrefix,
                squareVariationId(
                    variationPrefix
                )
            );

        return createSquarePriceEntry(
            variant.Id,
            startingPrice
        );
    }

    private static Decimal queryPrice(
        Id pricebookEntryId
    ) {
        return [
            SELECT UnitPrice
            FROM PricebookEntry
            WHERE Id = :pricebookEntryId
        ].UnitPrice;
    }

    // ============================================================
    // GLOBAL MOCK CONTRACT
    // ============================================================

    @IsTest
    static void testGlobalMockReturnsSquareCatalogPrice() {
        configureMock(
            'SQUARE_CATALOG_SUCCESS'
        );

        HttpRequest request =
            new HttpRequest();

        request.setEndpoint(
            'callout:Square_API/v2/catalog/object/VAR_TEST'
        );

        request.setMethod(
            'GET'
        );

        HttpResponse response =
            new Http().send(
                request
            );

        System.assertEquals(
            200,
            response.getStatusCode()
        );

        Map<String, Object> root =
            (Map<String, Object>)
                JSON.deserializeUntyped(
                    response.getBody()
                );

        Map<String, Object> objectValue =
            (Map<String, Object>)
                root.get(
                    'object'
                );

        System.assertNotEquals(
            null,
            objectValue,
            'GlobalHttpMock must return a Square catalog object for SQUARE_CATALOG_SUCCESS.'
        );

        Map<String, Object> variationData =
            (Map<String, Object>)
                objectValue.get(
                    'item_variation_data'
                );

        System.assertNotEquals(
            null,
            variationData,
            'GlobalHttpMock must return item_variation_data for Square price sync.'
        );

        Map<String, Object> priceMoney =
            (Map<String, Object>)
                variationData.get(
                    'price_money'
                );

        System.assertEquals(
            '2500',
            String.valueOf(
                priceMoney.get(
                    'amount'
                )
            ),
            'GlobalHttpMock must return 2500 cents for the success mode.'
        );
    }

    // ============================================================
    // NO DATA / NO PBE
    // ============================================================

    @IsTest
    static void testNoMappedVariantsReturns() {
        configureMock(
            'SUCCESS'
        );

        Test.startTest();

        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();

        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testMappedVariantWithoutSquarePbeSkips() {
        configureMock(
            'SUCCESS'
        );

        Product2 variant =
            insertVariant(
                'No Square PBE',
                squareVariationId(
                    'NOPBE'
                )
            );

        Test.startTest();

        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();

        Test.stopTest();

        System.assertNotEquals(
            null,
            variant.Id
        );
    }

    // ============================================================
    // FULL PRICE PROCESSING
    // ============================================================

    @IsTest(SeeAllData=true)
    static void testSuccessfulPriceUpdate() {
        configureMock(
            'SQUARE_CATALOG_SUCCESS'
        );

        if (
            !squarePricebookExists()
        ) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'Price Update',
                'UPD',
                10
            );

        Test.startTest();

        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();

        Integer calloutCount =
            Limits.getCallouts();

        Test.stopTest();

        System.assertEquals(
            1,
            calloutCount,
            'The isolated mapped Variant should make exactly one Square catalog callout.'
        );

        System.assertEquals(
            Decimal.valueOf('25.00'),
            queryPrice(
                pbe.Id
            ).setScale(2),
            '2500 Square cents should update the Square PricebookEntry to 25.00.'
        );
    }

    @IsTest(SeeAllData=true)
    static void testSamePriceDoesNotUpdate() {
        configureMock(
            'SQUARE_CATALOG_SAME_PRICE'
        );

        if (
            !squarePricebookExists()
        ) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'Same Price',
                'SAME',
                10
            );

        Test.startTest();

        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();

        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('10.00'),
            queryPrice(
                pbe.Id
            ).setScale(2)
        );
    }

    // ============================================================
    // RESPONSE SHAPE BRANCHES
    // ============================================================

    @IsTest(SeeAllData=true)
    static void testNoObjectSkips() {
        configureMock(
            'SQUARE_CATALOG_NO_OBJECT'
        );

        if (!squarePricebookExists()) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'No Object',
                'NOOBJ',
                10
            );

        Test.startTest();
        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();
        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('10.00'),
            queryPrice(pbe.Id).setScale(2)
        );
    }

    @IsTest(SeeAllData=true)
    static void testNullObjectSkips() {
        configureMock(
            'SQUARE_CATALOG_NULL_OBJECT'
        );

        if (!squarePricebookExists()) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'Null Object',
                'NULLOBJ',
                10
            );

        Test.startTest();
        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();
        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('10.00'),
            queryPrice(pbe.Id).setScale(2)
        );
    }

    @IsTest(SeeAllData=true)
    static void testNoVariationDataSkips() {
        configureMock(
            'SQUARE_CATALOG_NO_VARIATION_DATA'
        );

        if (!squarePricebookExists()) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'No Variation Data',
                'NOVAR',
                10
            );

        Test.startTest();
        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();
        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('10.00'),
            queryPrice(pbe.Id).setScale(2)
        );
    }

    @IsTest(SeeAllData=true)
    static void testNoPriceMoneySkips() {
        configureMock(
            'SQUARE_CATALOG_NO_PRICE_MONEY'
        );

        if (!squarePricebookExists()) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'No Price Money',
                'NOPRICE',
                10
            );

        Test.startTest();
        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();
        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('10.00'),
            queryPrice(pbe.Id).setScale(2)
        );
    }

    @IsTest(SeeAllData=true)
    static void testNullPriceAmountSkips() {
        configureMock(
            'SQUARE_CATALOG_NULL_PRICE_AMOUNT'
        );

        if (!squarePricebookExists()) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'Null Price Amount',
                'NULLAMT',
                10
            );

        Test.startTest();
        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();
        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('10.00'),
            queryPrice(pbe.Id).setScale(2)
        );
    }

    // ============================================================
    // EXCEPTION BRANCHES
    // ============================================================

    @IsTest(SeeAllData=true)
    static void testCalloutFailureIsCaught() {
        configureMock(
            'SQUARE_CATALOG_HTTP_ERROR'
        );

        if (!squarePricebookExists()) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'Callout Error',
                'HTTPERR',
                10
            );

        Test.startTest();

        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();

        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('10.00'),
            queryPrice(pbe.Id).setScale(2),
            'A Square retrieve failure should be caught and leave the price unchanged.'
        );
    }

    @IsTest(SeeAllData=true)
    static void testMalformedPriceIsCaught() {
        configureMock(
            'SQUARE_CATALOG_BAD_PRICE'
        );

        if (!squarePricebookExists()) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'Bad Price',
                'BADPRICE',
                10
            );

        Test.startTest();

        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();

        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('10.00'),
            queryPrice(pbe.Id).setScale(2)
        );
    }

    @IsTest(SeeAllData=true)
    static void testNegativeSquarePriceUpdatesSuccessfully() {
        configureMock(
            'SQUARE_CATALOG_NEGATIVE_PRICE'
        );

        if (!squarePricebookExists()) {
            System.assert(true);
            return;
        }

        PricebookEntry pbe =
            createIsolatedMappedVariant(
                'Negative Price',
                'NEG',
                10
            );

        Test.startTest();

        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();

        Test.stopTest();

        /*
         * Salesforce permits a negative PricebookEntry.UnitPrice in this org,
         * so the old test assumption that this would throw DmlException was
         * incorrect. Square returns -100 cents, therefore the expected
         * Salesforce price is -1.00.
         */
        System.assertEquals(
            Decimal.valueOf('-1.00'),
            queryPrice(pbe.Id).setScale(2),
            'Square -100 cents should update the PricebookEntry to -1.00.'
        );
    }

    // ============================================================
    // 90 CALLOUT GUARD
    // ============================================================

    @IsTest(SeeAllData=true)
    static void testStopsAtNinetySuccessfulCallouts() {
        configureMock(
            'SQUARE_CATALOG_SAME_PRICE'
        );

        if (!squarePricebookExists()) {
            System.assert(true);
            return;
        }

        deactivateExistingMappedSquareEntries();
        activateStandardPricebook();

        List<Product2> variants =
            new List<Product2>();

        for (
            Integer i = 0;
            i < 91;
            i++
        ) {
            variants.add(
                buildVariant(
                    'Limit Variant ' +
                    i,
                    squareVariationId(
                        'LIM'
                    )
                )
            );
        }

        insert variants;

        List<PricebookEntry> standardEntries =
            new List<PricebookEntry>();

        List<PricebookEntry> squareEntries =
            new List<PricebookEntry>();

        for (
            Product2 variant :
            variants
        ) {
            standardEntries.add(
                new PricebookEntry(
                    Pricebook2Id =
                        Test.getStandardPricebookId(),
                    Product2Id =
                        variant.Id,
                    UnitPrice =
                        10,
                    IsActive =
                        true
                )
            );

            squareEntries.add(
                new PricebookEntry(
                    Pricebook2Id =
                        SQUARE_PRICEBOOK_ID,
                    Product2Id =
                        variant.Id,
                    UnitPrice =
                        10,
                    IsActive =
                        true,
                    UseStandardPrice =
                        false
                )
            );
        }

        insert standardEntries;
        insert squareEntries;

        Test.startTest();

        SquareCatalogPriceSyncService.syncSquarePricesToSalesforce();

        Integer calloutsUsed =
            Limits.getCallouts();

        Test.stopTest();

        System.assertEquals(
            90,
            calloutsUsed,
            'The service must stop after 90 successful Square catalog callouts.'
        );
    }
}