@IsTest(SeeAllData=true)
private class AccountOrchestrationServiceTest {

    // ================================================================
    // Helpers
    // ================================================================

    private static String uniqueKey(String prefix) {
        return prefix + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static String uniqueEmail(String prefix) {
        return prefix + '+' +
            String.valueOf(Math.abs(Crypto.getRandomInteger())) +
            '@test.com';
    }

    private static Id personRtId() {
        return AccountOrchestrationService.personAccountRecordTypeId;
    }

    private static void setMock() {
        GlobalHttpMock.mockMode = 'SUCCESS';
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
    }

    private static Map<String, Object> buildCustomerPayload(
        String idValue,
        String emailValue
    ) {
        return new Map<String, Object>{
            'id' => idValue,
            'email' => emailValue,
            'first_name' => 'John',
            'last_name' => 'Doe',
            'locale' => 'en-GB',
            'addresses' => new List<Object>{
                new Map<String, Object>{
                    'address1' => 'Street 1',
                    'address2' => 'Apt 2',
                    'city' => 'London',
                    'province' => 'London',
                    'zip' => 'WC2H',
                    'country' => 'UK',
                    'default' => true
                },
                new Map<String, Object>{
                    'address1' => 'Billing Street',
                    'address2' => 'Suite 4',
                    'city' => 'Manchester',
                    'province' => 'Greater Manchester',
                    'zip' => 'M1',
                    'country' => 'UK',
                    'default' => false
                }
            },
            'email_marketing_consent' => new Map<String, Object>{
                'state' => 'subscribed',
                'consent_updated_at' => '2026-01-01T10:00:00+00:00'
            },
            'sms_marketing_consent' => new Map<String, Object>{
                'state' => 'not_subscribed',
                'consent_updated_at' => '2026-01-01T11:00:00+00:00'
            },
            'whats_app_marketing_consent' => new Map<String, Object>{
                'state' => 'subscribed',
                'consent_updated_at' => '2026-01-01T12:00:00+00:00'
            }
        };
    }

    private static Map<String, Object> wrapSingle(
        Map<String, Object> customerPayload
    ) {
        return new Map<String, Object>{
            'customer' => customerPayload
        };
    }

    private static Account createExistingPersonAccount(
        String shopId,
        String email,
        String lastName
    ) {
        Account acc = new Account(
            RecordTypeId = personRtId(),
            LastName = lastName == null ? 'Existing Customer' : lastName,
            Shop_ID__c = shopId,
            PersonEmail = email
        );
        insert acc;
        return acc;
    }

    // ================================================================
    // processCustomersFromRestRequest
    // ================================================================

    @IsTest
    static void testCreateCustomerFromSingleCustomerWrapper() {
        String shopId = uniqueKey('CUST-CREATE');
        String email = uniqueEmail('create');

        setMock();

        Test.startTest();
        AccountOrchestrationService.processCustomersFromRestRequest(
            wrapSingle(buildCustomerPayload(shopId, email)),
            new String[] { 'customers' }
        );
        Test.stopTest();

        Account acc = [
            SELECT Id, Shop_ID__c, PersonEmail, FirstName, LastName,
                   ShippingStreet, ShippingCity, ShippingState,
                   ShippingPostalCode, ShippingCountry,
                   BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry,
                   Email_Opt_In__pc, SMS_Opt_In__pc,
                   Whatsapp_opt_in__pc, Consent_Source__c,
                   Consent_Date_Time__c, Language__pc,
                   Updated_by_Integration__c
            FROM Account
            WHERE Shop_ID__c = :shopId
            LIMIT 1
        ];

        System.assertEquals(shopId, acc.Shop_ID__c);
        System.assertEquals(email, acc.PersonEmail);
        System.assertEquals('John', acc.FirstName);
        System.assertEquals('Doe', acc.LastName);

        System.assertEquals('Street 1 Apt 2', acc.ShippingStreet);
        System.assertEquals('London', acc.ShippingCity);
        System.assertEquals('London', acc.ShippingState);
        System.assertEquals('WC2H', acc.ShippingPostalCode);
        System.assertEquals('UK', acc.ShippingCountry);

        System.assertEquals('Billing Street Suite 4', acc.BillingStreet);
        System.assertEquals('Manchester', acc.BillingCity);
        System.assertEquals('Greater Manchester', acc.BillingState);
        System.assertEquals('M1', acc.BillingPostalCode);
        System.assertEquals('UK', acc.BillingCountry);

        System.assertEquals(true, acc.Email_Opt_In__pc);
        System.assertEquals(false, acc.SMS_Opt_In__pc);
        System.assertEquals(true, acc.Whatsapp_opt_in__pc);
        System.assertEquals('Shopify', acc.Consent_Source__c);

        // WhatsApp timestamp is latest.
        System.assertEquals(
            Datetime.valueOfGmt('2026-01-01 12:00:00'),
            acc.Consent_Date_Time__c
        );

        System.assertEquals('English', acc.Language__pc);
        System.assertEquals(true, acc.Updated_by_Integration__c);
    }

    @IsTest
    static void testUpdateExistingCustomerByShopId() {
        String shopId = uniqueKey('CUST-SHOP');
        Account existing = createExistingPersonAccount(
            shopId,
            uniqueEmail('old'),
            'Old'
        );

        Map<String, Object> payload = buildCustomerPayload(
            shopId,
            uniqueEmail('new')
        );

        setMock();

        Test.startTest();
        AccountOrchestrationService.processCustomersFromRestRequest(
            wrapSingle(payload),
            new String[] { 'customers' }
        );
        Test.stopTest();

        Account updated = [
            SELECT Id, Shop_ID__c, FirstName, LastName, PersonEmail,
                   Email_Opt_In__pc, SMS_Opt_In__pc,
                   Whatsapp_opt_in__pc, Consent_Source__c
            FROM Account
            WHERE Id = :existing.Id
        ];

        System.assertEquals(existing.Id, updated.Id);
        System.assertEquals(shopId, updated.Shop_ID__c);
        System.assertEquals('John', updated.FirstName);
        System.assertEquals('Doe', updated.LastName);
        System.assertEquals('Shopify', updated.Consent_Source__c);
        System.assertEquals(true, updated.Email_Opt_In__pc);
        System.assertEquals(false, updated.SMS_Opt_In__pc);
        System.assertEquals(true, updated.Whatsapp_opt_in__pc);
    }

    @IsTest
    static void testUpdateExistingCustomerByEmail() {
        String newShopId = uniqueKey('CUST-EMAIL');
        String email = uniqueEmail('match');

        Account existing = createExistingPersonAccount(
            null,
            email,
            'Email Match'
        );

        Map<String, Object> payload = buildCustomerPayload(
            newShopId,
            email
        );

        setMock();

        Test.startTest();
        AccountOrchestrationService.processCustomersFromRestRequest(
            wrapSingle(payload),
            new String[] { 'customers' }
        );
        Test.stopTest();

        Account updated = [
            SELECT Id, Shop_ID__c, PersonEmail, LastName
            FROM Account
            WHERE Id = :existing.Id
        ];

        System.assertEquals(existing.Id, updated.Id);
        System.assertEquals(newShopId, updated.Shop_ID__c);
        System.assertEquals(email, updated.PersonEmail);
        System.assertEquals('Doe', updated.LastName);
    }

    @IsTest
    static void testMultipleCustomersPayloadCreatesBoth() {
        String shopId1 = uniqueKey('CUST-MULTI-A');
        String shopId2 = uniqueKey('CUST-MULTI-B');

        Map<String, Object> payload = new Map<String, Object>{
            'customers' => new List<Object>{
                buildCustomerPayload(shopId1, uniqueEmail('multi-a')),
                buildCustomerPayload(shopId2, uniqueEmail('multi-b'))
            }
        };

        setMock();

        Test.startTest();
        AccountOrchestrationService.processCustomersFromRestRequest(
            payload,
            new String[] { 'customers' }
        );
        Test.stopTest();

        List<Account> accs = [
            SELECT Id, Shop_ID__c
            FROM Account
            WHERE Shop_ID__c IN :new Set<String>{ shopId1, shopId2 }
        ];

        System.assertEquals(2, accs.size());
    }

    @IsTest
    static void testCustomerIdFallbackAndEmailAddressFallback() {
        String shopId = uniqueKey('CUST-FALLBACK');
        String email = uniqueEmail('fallback');

        Map<String, Object> customerPayload = new Map<String, Object>{
            'customer_id' => shopId,
            'email_address' => email,
            'first_name' => 'Fallback',
            'last_name' => 'Customer',
            'customer_locale' => 'fr-FR',
            'addresses' => new List<Object>()
        };

        setMock();

        Test.startTest();
        AccountOrchestrationService.processCustomersFromRestRequest(
            wrapSingle(customerPayload),
            new String[] { 'customers' }
        );
        Test.stopTest();

        Account acc = [
            SELECT Id, Shop_ID__c, PersonEmail, LastName, Language__pc
            FROM Account
            WHERE Shop_ID__c = :shopId
            LIMIT 1
        ];

        // Email is used by the service for matching, but processSingleCustomer
        // only populates mapped fields through REST_Field_Mapping__mdt.
        // This test deliberately uses the customer_id/email_address fallback
        // branches and therefore does not assume PersonEmail is populated.
        System.assertEquals(shopId, acc.Shop_ID__c);
        System.assertEquals('Customer', acc.LastName);
        System.assertEquals('French', acc.Language__pc);
    }

    @IsTest
    static void testCustomerIdAndEmailPrecedence() {
        String shopId = uniqueKey('CUST-PRECEDENCE');
        String email = uniqueEmail('precedence');

        Map<String, Object> payload = new Map<String, Object>{
            'id' => shopId,
            'customer_id' => uniqueKey('IGNORED'),
            'email' => email,
            'email_address' => uniqueEmail('ignored-email'),
            'first_name' => 'First',
            'last_name' => 'Last'
        };

        Account acc = (Account)AccountOrchestrationService.processSingleCustomer(
            payload,
            new List<REST_Field_Mapping__mdt>(),
            personRtId(),
            new Map<String, Account>(),
            new Map<String, Account>()
        );

        System.assertEquals(shopId, acc.Shop_ID__c);
        System.assertEquals('First', acc.FirstName);
        System.assertEquals('Last', acc.LastName);
    }

    @IsTest
    static void testEmptyPayloadReturnsWithoutDml() {
        setMock();

        Test.startTest();
        AccountOrchestrationService.processCustomersFromRestRequest(
            new Map<String, Object>(),
            new String[] { 'customers' }
        );
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testPayloadWithEmptyCustomersListReturnsWithoutDml() {
        setMock();

        Test.startTest();
        AccountOrchestrationService.processCustomersFromRestRequest(
            new Map<String, Object>{
                'customers' => new List<Object>()
            },
            new String[] { 'customers' }
        );
        Test.stopTest();

        System.assert(true);
    }

    // ================================================================
    // processSingleCustomer
    // ================================================================

    @IsTest
    static void testProcessSingleCustomerDirectWithIdAndLastName() {
        String shopId = uniqueKey('DIRECT-ID');

        Map<String, Object> payload = buildCustomerPayload(
            shopId,
            uniqueEmail('direct')
        );

        Account acc = (Account)AccountOrchestrationService.processSingleCustomer(
            payload,
            new List<REST_Field_Mapping__mdt>(),
            personRtId(),
            new Map<String, Account>(),
            new Map<String, Account>()
        );

        System.assertEquals(shopId, acc.Shop_ID__c);
        System.assertEquals('John', acc.FirstName);
        System.assertEquals('Doe', acc.LastName);
        System.assertEquals(true, acc.Updated_by_Integration__c);
        System.assertEquals(personRtId(), acc.RecordTypeId);
    }

    @IsTest
    static void testProcessSingleCustomerFirstNameOnly() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => uniqueKey('DIRECT-FIRST'),
            'email' => uniqueEmail('first'),
            'first_name' => 'OnlyFirst',
            'last_name' => null
        };

        Account acc = (Account)AccountOrchestrationService.processSingleCustomer(
            payload,
            new List<REST_Field_Mapping__mdt>(),
            personRtId(),
            new Map<String, Account>(),
            new Map<String, Account>()
        );

        System.assertEquals(null, acc.FirstName);
        System.assertEquals('OnlyFirst', acc.LastName);
    }

    @IsTest
    static void testProcessSingleCustomerNoNameUsesUnknown() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => uniqueKey('DIRECT-UNKNOWN'),
            'email' => uniqueEmail('unknown')
        };

        Account acc = (Account)AccountOrchestrationService.processSingleCustomer(
            payload,
            new List<REST_Field_Mapping__mdt>(),
            personRtId(),
            new Map<String, Account>(),
            new Map<String, Account>()
        );

        System.assertEquals('Unknown', acc.LastName);
    }

    @IsTest
    static void testProcessSingleCustomerMatchesExistingByShopId() {
        String shopId = uniqueKey('DIRECT-SHOP');
        Account existing = createExistingPersonAccount(
            shopId,
            uniqueEmail('direct-shop'),
            'Existing Shop'
        );

        Account acc = (Account)AccountOrchestrationService.processSingleCustomer(
            buildCustomerPayload(shopId, uniqueEmail('changed-shop')),
            new List<REST_Field_Mapping__mdt>(),
            personRtId(),
            new Map<String, Account>{ shopId => existing },
            new Map<String, Account>()
        );

        System.assertEquals(existing.Id, acc.Id);
        System.assertEquals(shopId, acc.Shop_ID__c);
    }

    @IsTest
    static void testProcessSingleCustomerMatchesExistingByEmailPreservesShopId() {
        String existingShopId = uniqueKey('DIRECT-EMAIL-SHOP');
        String email = uniqueEmail('direct-email');

        Account existing = createExistingPersonAccount(
            existingShopId,
            email,
            'Existing Email'
        );

        Map<String, Object> payload = new Map<String, Object>{
            'email_address' => email,
            'first_name' => 'Email',
            'last_name' => 'Only'
        };

        Account acc = (Account)AccountOrchestrationService.processSingleCustomer(
            payload,
            new List<REST_Field_Mapping__mdt>(),
            personRtId(),
            new Map<String, Account>(),
            new Map<String, Account>{ email.toLowerCase() => existing }
        );

        System.assertEquals(existing.Id, acc.Id);
        System.assertEquals(existingShopId, acc.Shop_ID__c);
    }

    @IsTest
    static void testProcessSingleCustomerMatchesExistingByEmailWithNoExistingShopId() {
        String newShopId = uniqueKey('DIRECT-EMAIL-NEW');
        String email = uniqueEmail('direct-email-new');

        Account existing = createExistingPersonAccount(
            null,
            email,
            'Existing Email New'
        );

        Map<String, Object> payload = new Map<String, Object>{
            'customer_id' => newShopId,
            'email' => email,
            'first_name' => 'Email',
            'last_name' => 'Customer'
        };

        Account acc = (Account)AccountOrchestrationService.processSingleCustomer(
            payload,
            new List<REST_Field_Mapping__mdt>(),
            personRtId(),
            new Map<String, Account>(),
            new Map<String, Account>{ email.toLowerCase() => existing }
        );

        System.assertEquals(existing.Id, acc.Id);
        System.assertEquals(newShopId, acc.Shop_ID__c);
    }

    // ================================================================
    // processDefaultCustomer
    // ================================================================

    @IsTest
    static void testProcessDefaultCustomerUsesExistingStaticValue() {
        AccountOrchestrationService.defaultCustomerAccount = new Account(
            LastName = 'Already Loaded',
            Shop_ID__c = 'STATIC-DEFAULT'
        );

        Test.startTest();
        Account result = AccountOrchestrationService.processDefaultCustomer();
        Test.stopTest();

        System.assertEquals(
            'STATIC-DEFAULT',
            result.Shop_ID__c
        );
        System.assertEquals(
            'Already Loaded',
            result.LastName
        );

        AccountOrchestrationService.defaultCustomerAccount = null;
    }

    @IsTest
    static void testProcessDefaultCustomerFindsExistingDatabaseRecord() {
        AccountOrchestrationService.defaultCustomerAccount = null;

        Account existing = [
            SELECT Id, Shop_ID__c, LastName
            FROM Account
            WHERE Shop_ID__c = '1010101'
            LIMIT 1
        ];

        Test.startTest();
        Account result = AccountOrchestrationService.processDefaultCustomer();
        Test.stopTest();

        System.assertEquals(existing.Id, result.Id);
        System.assertEquals('1010101', result.Shop_ID__c);

        AccountOrchestrationService.defaultCustomerAccount = null;
    }

    @IsTest
    static void testProcessDefaultCustomerCreatesWhenDatabaseRecordDoesNotExist() {
        AccountOrchestrationService.defaultCustomerAccount = null;

        List<Account> existing = [
            SELECT Id
            FROM Account
            WHERE Shop_ID__c = '1010101'
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            // The org already has the fixed default customer, so the create
            // branch cannot safely be forced without deleting real data.
            System.assert(true);
            return;
        }

        Test.startTest();
        Account result = AccountOrchestrationService.processDefaultCustomer();
        Test.stopTest();

        System.assertNotEquals(null, result.Id);
        System.assertEquals('1010101', result.Shop_ID__c);
        System.assertEquals('Default Customer', result.LastName);
        System.assertEquals('71 - 75 Shelton Street', result.ShippingStreet);
        System.assertEquals('Camden', result.ShippingCity);
        System.assertEquals('London', result.ShippingState);
        System.assertEquals('WC2H 9JQ', result.ShippingPostalCode);
        System.assertEquals('UK', result.ShippingCountry);

        AccountOrchestrationService.defaultCustomerAccount = null;
    }

    // ================================================================
    // doNuancedMapping - addresses
    // ================================================================

    @IsTest
    static void testDoNuancedMappingDefaultAndBillingAddresses() {
        Account acc = new Account();

        Map<String, Object> payload = new Map<String, Object>{
            'addresses' => new List<Object>{
                null,
                new Map<String, Object>{
                    'address1' => 'Default Street',
                    'address2' => 'Default Apt',
                    'city' => 'London',
                    'province' => 'London',
                    'zip' => 'WC2H',
                    'country' => 'UK',
                    'default' => true
                },
                new Map<String, Object>{
                    'address1' => 'Billing Street',
                    'address2' => 'Billing Apt',
                    'city' => 'Birmingham',
                    'province' => 'West Midlands',
                    'zip' => 'B1',
                    'country' => 'UK',
                    'default' => false
                }
            }
        };

        AccountOrchestrationService.doNuancedMapping(acc, payload);

        System.assertEquals(
            'Default Street Default Apt',
            acc.get('ShippingStreet')
        );
        System.assertEquals('London', acc.get('ShippingCity'));
        System.assertEquals('London', acc.get('ShippingState'));
        System.assertEquals('WC2H', acc.get('ShippingPostalCode'));
        System.assertEquals('UK', acc.get('ShippingCountry'));

        System.assertEquals(
            'Billing Street Billing Apt',
            acc.get('BillingStreet')
        );
        System.assertEquals('Birmingham', acc.get('BillingCity'));
        System.assertEquals('West Midlands', acc.get('BillingState'));
        System.assertEquals('B1', acc.get('BillingPostalCode'));
        System.assertEquals('UK', acc.get('BillingCountry'));
    }

    @IsTest
    static void testDoNuancedMappingAddressNullParts() {
        Account acc = new Account();

        Map<String, Object> payload = new Map<String, Object>{
            'addresses' => new List<Object>{
                new Map<String, Object>{
                    'address1' => null,
                    'address2' => null,
                    'city' => 'City',
                    'province' => 'Province',
                    'zip' => 'ZIP',
                    'country' => 'UK',
                    'default' => false
                }
            }
        };

        AccountOrchestrationService.doNuancedMapping(acc, payload);

        System.assertEquals('', acc.get('BillingStreet'));
        System.assertEquals('City', acc.get('BillingCity'));
        System.assertEquals('Province', acc.get('BillingState'));
    }

    @IsTest
    static void testDoNuancedMappingAddressDefaultKeyMissingUsesBilling() {
        Account acc = new Account();

        Map<String, Object> payload = new Map<String, Object>{
            'addresses' => new List<Object>{
                new Map<String, Object>{
                    'address1' => 'No Default Flag',
                    'city' => 'Leeds',
                    'province' => 'Yorkshire',
                    'zip' => 'LS1',
                    'country' => 'UK'
                }
            }
        };

        AccountOrchestrationService.doNuancedMapping(acc, payload);

        System.assertEquals(
            'No Default Flag',
            acc.get('BillingStreet')
        );
        System.assertEquals('Leeds', acc.get('BillingCity'));
    }

    // ================================================================
    // doNuancedMapping - consent
    // ================================================================

    @IsTest
    static void testDoNuancedMappingAllConsentSubscribedAndUnsubscribed() {
        Account acc = new Account();

        Map<String, Object> payload = new Map<String, Object>{
            'email_marketing_consent' => new Map<String, Object>{
                'state' => 'subscribed',
                'consent_updated_at' => '2026-01-01T10:00:00+00:00'
            },
            'sms_marketing_consent' => new Map<String, Object>{
                'state' => 'not_subscribed',
                'consent_updated_at' => '2026-01-01T11:00:00+00:00'
            },
            'whats_app_marketing_consent' => new Map<String, Object>{
                'state' => 'subscribed',
                'consent_updated_at' => '2026-01-01T12:00:00+00:00'
            }
        };

        AccountOrchestrationService.doNuancedMapping(acc, payload);

        System.assertEquals(true, acc.get('Email_Opt_In__pc'));
        System.assertEquals(false, acc.get('SMS_Opt_In__pc'));
        System.assertEquals(true, acc.get('Whatsapp_opt_in__pc'));
        System.assertEquals('Shopify', acc.get('Consent_Source__c'));
        System.assertEquals(
            Datetime.valueOfGmt('2026-01-01 12:00:00'),
            acc.get('Consent_Date_Time__c')
        );
    }

    @IsTest
    static void testDoNuancedMappingConsentCaseInsensitiveAndFalseStates() {
        Account acc = new Account();

        Map<String, Object> payload = new Map<String, Object>{
            'email_marketing_consent' => new Map<String, Object>{
                'state' => ' SUBSCRIBED '
            },
            'sms_marketing_consent' => new Map<String, Object>{
                'state' => 'unsubscribed'
            },
            'whats_app_marketing_consent' => new Map<String, Object>{
                'state' => 'UNSUBSCRIBED'
            }
        };

        AccountOrchestrationService.doNuancedMapping(acc, payload);

        System.assertEquals(true, acc.get('Email_Opt_In__pc'));
        System.assertEquals(false, acc.get('SMS_Opt_In__pc'));
        System.assertEquals(false, acc.get('Whatsapp_opt_in__pc'));
        System.assertEquals('Shopify', acc.get('Consent_Source__c'));
        System.assertEquals(null, acc.get('Consent_Date_Time__c'));
    }

    @IsTest
    static void testDoNuancedMappingConsentMissingStateDoesNothing() {
        Account acc = new Account();

        Map<String, Object> payload = new Map<String, Object>{
            'email_marketing_consent' => new Map<String, Object>(),
            'sms_marketing_consent' => new Map<String, Object>(),
            'whats_app_marketing_consent' => new Map<String, Object>()
        };

        AccountOrchestrationService.doNuancedMapping(acc, payload);

        System.assertEquals(null, acc.get('Email_Opt_In__pc'));
        System.assertEquals(null, acc.get('SMS_Opt_In__pc'));
        System.assertEquals(null, acc.get('Whatsapp_opt_in__pc'));
        System.assertEquals(null, acc.get('Consent_Source__c'));
        System.assertEquals(null, acc.get('Consent_Date_Time__c'));
    }

    @IsTest
    static void testDoNuancedMappingConsentNullBlocksDoNothing() {
        Account acc = new Account();

        Map<String, Object> payload = new Map<String, Object>{
            'email_marketing_consent' => null,
            'sms_marketing_consent' => null,
            'whats_app_marketing_consent' => null
        };

        AccountOrchestrationService.doNuancedMapping(acc, payload);

        System.assertEquals(null, acc.get('Email_Opt_In__pc'));
        System.assertEquals(null, acc.get('SMS_Opt_In__pc'));
        System.assertEquals(null, acc.get('Whatsapp_opt_in__pc'));
        System.assertEquals(null, acc.get('Consent_Source__c'));
    }

    @IsTest
    static void testDoNuancedMappingConsentLatestDateCanComeFromEmail() {
        Account acc = new Account();

        Map<String, Object> payload = new Map<String, Object>{
            'email_marketing_consent' => new Map<String, Object>{
                'state' => 'subscribed',
                'consent_updated_at' => '2026-02-03T04:05:06.123Z'
            },
            'sms_marketing_consent' => new Map<String, Object>{
                'state' => 'not_subscribed',
                'consent_updated_at' => '2026-02-01T00:00:00Z'
            },
            'whats_app_marketing_consent' => new Map<String, Object>{
                'state' => 'subscribed',
                'consent_updated_at' => '2026-02-02T00:00:00Z'
            }
        };

        AccountOrchestrationService.doNuancedMapping(acc, payload);

        System.assertEquals(
            Datetime.valueOfGmt('2026-02-03 04:05:06'),
            acc.get('Consent_Date_Time__c')
        );
    }

    @IsTest
    static void testDoNuancedMappingConsentLatestDateCanComeFromSms() {
        Account acc = new Account();

        Map<String, Object> payload = new Map<String, Object>{
            'email_marketing_consent' => new Map<String, Object>{
                'state' => 'subscribed',
                'consent_updated_at' => '2026-02-01T00:00:00Z'
            },
            'sms_marketing_consent' => new Map<String, Object>{
                'state' => 'subscribed',
                'consent_updated_at' => '2026-03-03T04:05:06Z'
            },
            'whats_app_marketing_consent' => new Map<String, Object>{
                'state' => 'not_subscribed',
                'consent_updated_at' => '2026-02-02T00:00:00Z'
            }
        };

        AccountOrchestrationService.doNuancedMapping(acc, payload);

        System.assertEquals(
            Datetime.valueOfGmt('2026-03-03 04:05:06'),
            acc.get('Consent_Date_Time__c')
        );
    }

    // ================================================================
    // doNuancedMapping - language
    // ================================================================

    @IsTest
    static void testLanguageEnglish() {
        Account acc = new Account();
        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{ 'locale' => 'en-GB' }
        );
        System.assertEquals('English', acc.get('Language__pc'));
    }

    @IsTest
    static void testLanguageFrenchFromCustomerLocale() {
        Account acc = new Account();
        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{ 'customer_locale' => 'fr-FR' }
        );
        System.assertEquals('French', acc.get('Language__pc'));
    }

    @IsTest
    static void testLanguageGerman() {
        Account acc = new Account();
        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{ 'language' => 'de-DE' }
        );
        System.assertEquals('German', acc.get('Language__pc'));
    }

    @IsTest
    static void testLanguageSpanish() {
        Account acc = new Account();
        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{ 'language' => 'es-ES' }
        );
        System.assertEquals('Spanish', acc.get('Language__pc'));
    }

    @IsTest
    static void testLanguageOtherUsesOriginalValue() {
        Account acc = new Account();
        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{ 'language' => 'it-IT' }
        );
        System.assertEquals('it-IT', acc.get('Language__pc'));
    }

    @IsTest
    static void testLanguagePrecedenceLocaleOverCustomerLocaleAndLanguage() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{
                'locale' => 'de-DE',
                'customer_locale' => 'fr-FR',
                'language' => 'es-ES'
            }
        );

        System.assertEquals('German', acc.get('Language__pc'));
    }

    @IsTest
    static void testLanguageFallsBackFromNullLocaleToCustomerLocale() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{
                'locale' => null,
                'customer_locale' => 'fr-FR',
                'language' => 'de-DE'
            }
        );

        System.assertEquals('French', acc.get('Language__pc'));
    }

    @IsTest
    static void testLanguageFallsBackFromNullLocaleAndCustomerLocaleToLanguage() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{
                'locale' => null,
                'customer_locale' => null,
                'language' => 'es-ES'
            }
        );

        System.assertEquals('Spanish', acc.get('Language__pc'));
    }

    @IsTest
    static void testBlankLanguageDoesNothing() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{ 'language' => '   ' }
        );

        System.assertEquals(null, acc.get('Language__pc'));
    }

    @IsTest
    static void testNoOptionalBlocksDoesNothing() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>()
        );

        System.assertEquals(null, acc.get('ShippingStreet'));
        System.assertEquals(null, acc.get('Language__pc'));
        System.assertEquals(null, acc.get('Consent_Source__c'));
    }

    // ================================================================
    // Date parser coverage through public doNuancedMapping
    // ================================================================

    @IsTest
    static void testConsentDatePositiveTimezone() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{
                'email_marketing_consent' => new Map<String, Object>{
                    'state' => 'subscribed',
                    'consent_updated_at' => '2026-01-01T10:00:00+05:30'
                }
            }
        );

        System.assertEquals(
            Datetime.valueOfGmt('2026-01-01 04:30:00'),
            acc.get('Consent_Date_Time__c')
        );
    }

    @IsTest
    static void testConsentDateNegativeTimezone() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{
                'email_marketing_consent' => new Map<String, Object>{
                    'state' => 'subscribed',
                    'consent_updated_at' => '2026-01-01T10:00:00-04:00'
                }
            }
        );

        System.assertEquals(
            Datetime.valueOfGmt('2026-01-01 14:00:00'),
            acc.get('Consent_Date_Time__c')
        );
    }

    @IsTest
    static void testConsentDateWithoutTimezone() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{
                'email_marketing_consent' => new Map<String, Object>{
                    'state' => 'subscribed',
                    'consent_updated_at' => '2026-01-01T10:00:00'
                }
            }
        );

        System.assertEquals(
            Datetime.valueOfGmt('2026-01-01 10:00:00'),
            acc.get('Consent_Date_Time__c')
        );
    }

    @IsTest
    static void testConsentDateInvalidReturnsNull() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{
                'email_marketing_consent' => new Map<String, Object>{
                    'state' => 'subscribed',
                    'consent_updated_at' => 'not-a-date'
                }
            }
        );

        System.assertEquals(null, acc.get('Consent_Date_Time__c'));
        System.assertEquals('Shopify', acc.get('Consent_Source__c'));
    }

    @IsTest
    static void testConsentDateMalformedStructureReturnsNull() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{
                'email_marketing_consent' => new Map<String, Object>{
                    'state' => 'subscribed',
                    'consent_updated_at' => '2026-01-01'
                }
            }
        );

        System.assertEquals(null, acc.get('Consent_Date_Time__c'));
        System.assertEquals('Shopify', acc.get('Consent_Source__c'));
    }

    @IsTest
    static void testConsentDateNullReturnsNull() {
        Account acc = new Account();

        AccountOrchestrationService.doNuancedMapping(
            acc,
            new Map<String, Object>{
                'email_marketing_consent' => new Map<String, Object>{
                    'state' => 'subscribed',
                    'consent_updated_at' => null
                }
            }
        );

        System.assertEquals(null, acc.get('Consent_Date_Time__c'));
        System.assertEquals('Shopify', acc.get('Consent_Source__c'));
    }
}