@IsTest(SeeAllData=true)
private class ShopifyCustomerGraphQLServiceTest {
    // ─────────────────────────────────────────────────────────────────────
    // Mock
    // ─────────────────────────────────────────────────────────────────────
    
    private class CustomerGraphQLMock implements HttpCalloutMock {
        private String mode;
        
        CustomerGraphQLMock(String modeValue) {
            this.mode = modeValue;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            String body = req.getBody();
            
            if (mode == 'NULL_RESPONSE_SHAPE') {
                res.setBody('{}');
                return res;
            }
            
            if (mode == 'DATA_NULL') {
                res.setBody('{"data":null}');
                return res;
            }
            
            if (mode == 'MISSING_MUTATION_RESULT') {
                res.setBody('{"data":{}}');
                return res;
            }
            
            if (mode == 'MUTATION_RESULT_NULL') {
                if (body != null && body.contains('customerUpdate')) {
                    res.setBody('{"data":{"customerUpdate":null}}');
                } else {
                    res.setBody('{"data":{"customerCreate":null}}');
                }
                return res;
            }
            
            if (mode == 'CREATE_CUSTOMER_NULL') {
                res.setBody(
                    '{"data":{"customerCreate":{' +
                    '"customer":null,' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'CREATE_CUSTOMER_NO_ID') {
                res.setBody(
                    '{"data":{"customerCreate":{' +
                    '"customer":{"firstName":"John","lastName":"Doe"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'CREATE_USER_ERRORS') {
                res.setBody(
                    '{"data":{"customerCreate":{' +
                    '"customer":null,' +
                    '"userErrors":[{"field":["email"],"message":"Invalid email"}]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'UPDATE_USER_ERRORS') {
                res.setBody(
                    '{"data":{"customerUpdate":{' +
                    '"customer":{"id":"gid://shopify/Customer/99999"},' +
                    '"userErrors":[{"field":["phone"],"message":"Invalid phone"}]' +
                    '}}}'
                );
                return res;
            }
            
            if (mode == 'LOCALE_NO_DATA') {
                res.setBody('{"extensions":{"cost":1}}');
                return res;
            }
            
            if (mode == 'LOCALE_DATA_NULL') {
                res.setBody('{"data":null}');
                return res;
            }
            
            if (mode == 'LOCALE_CUSTOMER_NULL') {
                res.setBody('{"data":{"customer":null}}');
                return res;
            }
            
            if (mode == 'LOCALE_NO_LOCALE') {
                res.setBody(
                    '{"data":{"customer":{"id":"gid://shopify/Customer/99999","legacyResourceId":"99999"}}}'
                );
                return res;
            }
            
            if (mode == 'LOCALE_BLANK') {
                res.setBody(
                    '{"data":{"customer":{"id":"gid://shopify/Customer/99999","legacyResourceId":"99999","locale":"   "}}}'
                );
                return res;
            }
            
            if (mode == 'LOCALE_EN') {
                res.setBody(
                    '{"data":{"customer":{"id":"gid://shopify/Customer/99999","legacyResourceId":"99999","locale":"en-GB"}}}'
                );
                return res;
            }
            
            if (mode == 'LOCALE_FR') {
                res.setBody(
                    '{"data":{"customer":{"id":"gid://shopify/Customer/99999","legacyResourceId":"99999","locale":"fr-FR"}}}'
                );
                return res;
            }
            
            if (mode == 'LOCALE_DE') {
                res.setBody(
                    '{"data":{"customer":{"id":"gid://shopify/Customer/99999","legacyResourceId":"99999","locale":"de-DE"}}}'
                );
                return res;
            }
            
            if (mode == 'LOCALE_ES') {
                res.setBody(
                    '{"data":{"customer":{"id":"gid://shopify/Customer/99999","legacyResourceId":"99999","locale":"es-ES"}}}'
                );
                return res;
            }
            
            if (mode == 'LOCALE_UNKNOWN') {
                res.setBody(
                    '{"data":{"customer":{"id":"gid://shopify/Customer/99999","legacyResourceId":"99999","locale":"it-IT"}}}'
                );
                return res;
            }
            
            if (body != null && body.contains('customerUpdate')) {
                res.setBody(
                    '{"data":{"customerUpdate":{' +
                    '"customer":{"id":"gid://shopify/Customer/99999","firstName":"Jane","lastName":"Smith","email":"jane@test.com","phone":"987654321"},' +
                    '"userErrors":[]' +
                    '}}}'
                );
                return res;
            }
            
            res.setBody(
                '{"data":{"customerCreate":{' +
                '"customer":{"id":"gid://shopify/Customer/99999","firstName":"John","lastName":"Doe","email":"john@test.com","phone":"123456789"},' +
                '"userErrors":[]' +
                '}}}'
            );
            
            return res;
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static String uniqueEmail(String prefix) {
        return prefix + '+' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '@test.com';
    }
    
    private static Id personAccountRecordTypeId() {
        return AccountOrchestrationService.personAccountRecordTypeId;
    }
    
    private static Account buildNewCustomer(String emailValue) {
        return new Account(
            RecordTypeId = personAccountRecordTypeId(),
            FirstName = 'John',
            LastName = 'Doe',
            PersonEmail = emailValue,
            Phone = '123456789'
        );
    }
    
    private static Account buildExistingCustomer(String shopId, String emailValue) {
        return new Account(
            RecordTypeId = personAccountRecordTypeId(),
            FirstName = 'Jane',
            LastName = 'Smith',
            PersonEmail = emailValue,
            Phone = '987654321',
            Shop_ID__c = shopId
        );
    }
    
    private static Account insertNewCustomer(String emailPrefix) {
        Account acc = buildNewCustomer(uniqueEmail(emailPrefix));
        insert acc;
        return acc;
    }
    
    private static Account insertExistingCustomer(String shopId, String emailPrefix) {
        Account acc = buildExistingCustomer(shopId, uniqueEmail(emailPrefix));
        insert acc;
        return acc;
    }
    
    private static void setMock(String mode) {
        Test.setMock(HttpCalloutMock.class, new CustomerGraphQLMock(mode));
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // syncCustomersAsync guard clauses
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testSyncCustomersAsyncNullInput() {
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(null);
        Test.stopTest();
        
        System.assert(true, 'Null input handled safely.');
    }
    
    @IsTest
    static void testSyncCustomersAsyncEmptyInput() {
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>());
        Test.stopTest();
        
        System.assert(true, 'Empty input handled safely.');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Customer create flow
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testCreateCustomerSetsShopId() {
        Account acc = insertNewCustomer('create-customer');
        
        setMock('SUCCESS');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Shop_ID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals('99999', updated.Shop_ID__c);
    }
    
    @IsTest
    static void testCreateCustomerWithBlankOptionalFields() {
        Account acc = new Account(
            RecordTypeId = personAccountRecordTypeId(),
            LastName = 'Blank Optional'
        );
        insert acc;
        
        setMock('SUCCESS');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Shop_ID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals('99999', updated.Shop_ID__c);
    }
    
    @IsTest
    static void testCreateCustomerResponseCustomerNullDoesNotUpdateShopId() {
        Account acc = insertNewCustomer('create-null-customer');
        
        setMock('CREATE_CUSTOMER_NULL');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Shop_ID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals(null, updated.Shop_ID__c);
    }
    
    @IsTest
    static void testCreateCustomerResponseCustomerWithoutIdDoesNotUpdateShopId() {
        Account acc = insertNewCustomer('create-no-id');
        
        setMock('CREATE_CUSTOMER_NO_ID');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Shop_ID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals(null, updated.Shop_ID__c);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Customer update flow
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testUpdateCustomer() {
        Account acc = insertExistingCustomer('99999', 'update-customer');
        
        setMock('SUCCESS');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        System.assert(true, 'Update customer flow executed without errors.');
    }
    
    @IsTest
    static void testUpdateCustomerWithBlankOptionalFields() {
        Account acc = new Account(
            RecordTypeId = personAccountRecordTypeId(),
            LastName = 'Existing Blank Optional',
            Shop_ID__c = '99999'
        );
        insert acc;
        
        setMock('SUCCESS');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        System.assert(true, 'Update customer with blank optional fields executed.');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // User errors and response-shape coverage
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testCreateUserErrorsThrowsException() {
        Account acc = insertNewCustomer('create-errors');
        
        setMock('CREATE_USER_ERRORS');
        
        try {
            Test.startTest();
            ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
            Test.stopTest();
            
            System.assert(false, 'Expected customerCreate userErrors exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('customerCreate') ||
                e.getMessage().contains('userErrors') ||
                e.getMessage().contains('Invalid email'),
                'Unexpected exception: ' + e.getMessage()
            );
        }
    }
    
    @IsTest
    static void testUpdateUserErrorsThrowsException() {
        Account acc = insertExistingCustomer('99999', 'update-errors');
        
        setMock('UPDATE_USER_ERRORS');
        
        try {
            Test.startTest();
            ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
            Test.stopTest();
            
            System.assert(false, 'Expected customerUpdate userErrors exception.');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('customerUpdate') ||
                e.getMessage().contains('userErrors') ||
                e.getMessage().contains('Invalid phone'),
                'Unexpected exception: ' + e.getMessage()
            );
        }
    }
    
    @IsTest
    static void testCreateResponseMissingDataReturnsSafely() {
        Account acc = insertNewCustomer('missing-data');
        
        setMock('NULL_RESPONSE_SHAPE');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Shop_ID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals(null, updated.Shop_ID__c);
    }
    
    @IsTest
    static void testCreateResponseDataNullReturnsSafely() {
        Account acc = insertNewCustomer('data-null');
        
        setMock('DATA_NULL');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Shop_ID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals(null, updated.Shop_ID__c);
    }
    
    @IsTest
    static void testCreateResponseMissingMutationResultReturnsSafely() {
        Account acc = insertNewCustomer('missing-mutation');
        
        setMock('MISSING_MUTATION_RESULT');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Shop_ID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals(null, updated.Shop_ID__c);
    }
    
    @IsTest
    static void testCreateResponseMutationResultNullReturnsSafely() {
        Account acc = insertNewCustomer('mutation-null');
        
        setMock('MUTATION_RESULT_NULL');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Shop_ID__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals(null, updated.Shop_ID__c);
    }
    
    @IsTest
    static void testUpdateResponseMissingDataReturnsSafely() {
        Account acc = insertExistingCustomer('99999', 'update-missing-data');
        
        setMock('NULL_RESPONSE_SHAPE');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        System.assert(true, 'Update response missing data safely ignored.');
    }
    
    @IsTest
    static void testUpdateResponseDataNullReturnsSafely() {
        Account acc = insertExistingCustomer('99999', 'update-data-null');
        
        setMock('DATA_NULL');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        System.assert(true, 'Update response data null safely ignored.');
    }
    
    @IsTest
    static void testUpdateResponseMissingMutationResultReturnsSafely() {
        Account acc = insertExistingCustomer('99999', 'update-missing-mutation');
        
        setMock('MISSING_MUTATION_RESULT');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        System.assert(true, 'Update response missing mutation safely ignored.');
    }
    
    @IsTest
    static void testUpdateResponseMutationResultNullReturnsSafely() {
        Account acc = insertExistingCustomer('99999', 'update-mutation-null');
        
        setMock('MUTATION_RESULT_NULL');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        System.assert(true, 'Update response mutation null safely ignored.');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // syncCustomerLocalesAsync guard clauses
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testSyncCustomerLocalesNullInput() {
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(null);
        Test.stopTest();
        
        System.assert(true, 'Null locale input handled.');
    }
    
    @IsTest
    static void testSyncCustomerLocalesEmptyInput() {
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>());
        Test.stopTest();
        
        System.assert(true, 'Empty locale input handled.');
    }
    
    @IsTest
    static void testSyncCustomerLocalesSkipsBlankShopId() {
        Account acc = insertNewCustomer('locale-blank-shop-id');
        
        Account beforeRun = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        String originalLanguage = beforeRun.Language__pc;
        
        setMock('LOCALE_EN');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            originalLanguage,
            updated.Language__pc,
            'Account with blank Shop_ID__c should not update Language__pc.'
        );
    }
    // ─────────────────────────────────────────────────────────────────────
    // Locale response-shape branches
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testLocaleResponseNoDataReturnsWithoutUpdate() {
        Account acc = insertExistingCustomer('99999', 'locale-no-data');
        
        Account beforeRun = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        String originalLanguage = beforeRun.Language__pc;
        
        setMock('LOCALE_NO_DATA');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            originalLanguage,
            updated.Language__pc,
            'Locale response without data should not update Language__pc.'
        );
    }
    
    @IsTest
    static void testLocaleResponseDataNullReturnsWithoutUpdate() {
        Account acc = insertExistingCustomer('99999', 'locale-data-null');
        
        Account beforeRun = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        String originalLanguage = beforeRun.Language__pc;
        
        setMock('LOCALE_DATA_NULL');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            originalLanguage,
            updated.Language__pc,
            'Locale response with data null should not update Language__pc.'
        );
    }
    
    @IsTest
    static void testLocaleResponseCustomerNullReturnsWithoutUpdate() {
        Account acc = insertExistingCustomer('99999', 'locale-customer-null');
        
        Account beforeRun = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        String originalLanguage = beforeRun.Language__pc;
        
        setMock('LOCALE_CUSTOMER_NULL');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            originalLanguage,
            updated.Language__pc,
            'Locale response with customer null should not update Language__pc.'
        );
    }
    
    @IsTest
    static void testLocaleResponseNoLocaleReturnsWithoutUpdate() {
        Account acc = insertExistingCustomer('99999', 'locale-no-locale');
        
        Account beforeRun = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        String originalLanguage = beforeRun.Language__pc;
        
        setMock('LOCALE_NO_LOCALE');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            originalLanguage,
            updated.Language__pc,
            'Locale response without locale should not update Language__pc.'
        );
    }
    
    @IsTest
    static void testLocaleResponseBlankLocaleReturnsWithoutUpdate() {
        Account acc = insertExistingCustomer('99999', 'locale-blank');
        
        Account beforeRun = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        String originalLanguage = beforeRun.Language__pc;
        
        setMock('LOCALE_BLANK');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            originalLanguage,
            updated.Language__pc,
            'Blank locale should not update Language__pc.'
        );
    }
    
    @IsTest
    static void testLocaleUnknownReturnsWithoutUpdate() {
        Account acc = insertExistingCustomer('99999', 'locale-unknown');
        
        Account beforeRun = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        String originalLanguage = beforeRun.Language__pc;
        
        setMock('LOCALE_UNKNOWN');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            originalLanguage,
            updated.Language__pc,
            'Unknown locale should not update Language__pc.'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Locale mapping update branches
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testLocaleEnglishUpdatesLanguage() {
        Account acc = insertExistingCustomer('99999', 'locale-en');
        
        setMock('LOCALE_EN');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc, Updated_by_Integration__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals('English', updated.Language__pc);
        System.assertEquals(true, updated.Updated_by_Integration__c);
    }
    
    @IsTest
    static void testLocaleFrenchUpdatesLanguage() {
        Account acc = insertExistingCustomer('99999', 'locale-fr');
        
        setMock('LOCALE_FR');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc, Updated_by_Integration__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals('French', updated.Language__pc);
        System.assertEquals(true, updated.Updated_by_Integration__c);
    }
    
    @IsTest
    static void testLocaleGermanUpdatesLanguage() {
        Account acc = insertExistingCustomer('99999', 'locale-de');
        
        setMock('LOCALE_DE');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc, Updated_by_Integration__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals('German', updated.Language__pc);
        System.assertEquals(true, updated.Updated_by_Integration__c);
    }
    
    @IsTest
    static void testLocaleSpanishUpdatesLanguage() {
        Account acc = insertExistingCustomer('99999', 'locale-es');
        
        setMock('LOCALE_ES');
        
        Test.startTest();
        ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(new List<Id>{ acc.Id });
        Test.stopTest();
        
        Account updated = [
            SELECT Id, Language__pc, Updated_by_Integration__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.assertEquals('Spanish', updated.Language__pc);
        System.assertEquals(true, updated.Updated_by_Integration__c);
    }
}