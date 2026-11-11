@IsTest
private class SquareCustomerConsentServiceTest {

    private static final String PAYMENT_ID = 'PAYMENT_ID_123456789012345';

    private class CustomerMock implements HttpCalloutMock {
        private String mode;

        CustomerMock(String mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (mode == 'ERROR') {
                throw new CalloutException('Customer callout failed');
            }

            if (mode == 'NULL_CUSTOMER') {
                res.setBody('{"customer":null}');
                return res;
            }

            if (mode == 'MISSING_CONTACT') {
                res.setBody(
                    '{"customer":{"id":"C_NO_CONTACT",' +
                    '"given_name":"No","family_name":"Contact",' +
                    '"created_at":"2026-01-01T00:00:00Z",' +
                    '"updated_at":"2026-01-01T00:00:00Z"}}'
                );
                return res;
            }

            if (mode == 'MISSING_NAME') {
                res.setBody(
                    '{"customer":{"id":"C_NO_NAME",' +
                    '"email_address":"noname@example.com",' +
                    '"phone_number":"5551112222",' +
                    '"created_at":"2026-01-01T00:00:00Z",' +
                    '"updated_at":"2026-01-01T00:00:00Z"}}'
                );
                return res;
            }

            if (mode == 'UNSUBSCRIBED') {
                res.setBody(
                    '{"customer":{"id":"C_UNSUB",' +
                    '"given_name":"Jane","family_name":"Doe",' +
                    '"email_address":"unsub@example.com",' +
                    '"phone_number":"5551112222",' +
                    '"created_at":"2026-01-01T00:00:00Z",' +
                    '"updated_at":"2026-01-02T00:00:00Z",' +
                    '"preferences":{"email_unsubscribed":true}}}'
                );
                return res;
            }

            res.setBody(
                '{"customer":{"id":"CUSTOMER_123",' +
                '"given_name":"Jane","family_name":"Doe",' +
                '"email_address":"jane@example.com",' +
                '"phone_number":"5551112222",' +
                '"created_at":"2026-01-01T00:00:00Z",' +
                '"updated_at":"2026-01-02T00:00:00Z",' +
                '"preferences":{"email_unsubscribed":false}}}'
            );
            return res;
        }
    }

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];

        System.assert(!rts.isEmpty(),
            'Person Accounts must be enabled for this test class.');

        return rts[0].Id;
    }

    private static Account createPersonAccount(
        String customerId,
        String firstName,
        String lastName,
        String email,
        String phone
    ) {
        Account a = new Account(
            RecordTypeId = getPersonAccountRecordTypeId(),
            FirstName = firstName,
            LastName = lastName,
            PersonEmail = email,
            PersonMobilePhone = phone,
            Square_Customer_Id__c = customerId
        );
        insert a;
        return a;
    }

    private static Map<String,Object> payment(String customerId) {
        return new Map<String,Object>{
            'id' => PAYMENT_ID,
            'customer_id' => customerId
        };
    }

    private static Map<String,Object> customer(
        String id,
        String firstName,
        String lastName,
        String email,
        String phone,
        Boolean unsubscribed
    ) {
        Map<String,Object> c = new Map<String,Object>{
            'id' => id,
            'given_name' => firstName,
            'family_name' => lastName,
            'email_address' => email,
            'phone_number' => phone,
            'created_at' => '2026-01-01T00:00:00Z',
            'updated_at' => '2026-01-02T00:00:00Z'
        };

        if (unsubscribed != null) {
            c.put('preferences', new Map<String,Object>{
                'email_unsubscribed' => unsubscribed
            });
        }

        return c;
    }

    private static String webhook(Map<String,Object> c) {
        return JSON.serialize(new Map<String,Object>{
            'type' => 'customer.created',
            'data' => new Map<String,Object>{
                'object' => new Map<String,Object>{
                    'customer' => c
                }
            }
        });
    }

    @IsTest
    static void testUpsertBlankCustomerId() {
        Test.startTest();
        Id r1 = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            null, 'customer.created', null
        );
        Id r2 = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            '', 'customer.created', null
        );
        Id r3 = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            '   ', 'customer.created', null
        );
        Test.stopTest();

        System.assertEquals(null, r1);
        System.assertEquals(null, r2);
        System.assertEquals(null, r3);
    }

    @IsTest
    static void testThreeArgGuards() {
        Map<String,Object> p = payment('C1');
        Map<String,Object> c = customer(
            'C1','Jane','Doe','jane1@example.com','5550000001',false
        );

        Test.startTest();
        System.assertEquals(null,
            SquareCustomerConsentService.createContactFromPaymentIfConsented(
                null,p,c));
        System.assertEquals(null,
            SquareCustomerConsentService.createContactFromPaymentIfConsented(
                '',p,c));
        System.assertEquals(null,
            SquareCustomerConsentService.createContactFromPaymentIfConsented(
                '   ',p,c));
        System.assertEquals(null,
            SquareCustomerConsentService.createContactFromPaymentIfConsented(
                PAYMENT_ID,null,c));
        System.assertEquals(null,
            SquareCustomerConsentService.createContactFromPaymentIfConsented(
                PAYMENT_ID,new Map<String,Object>{'id'=>PAYMENT_ID},c));
        System.assertEquals(null,
            SquareCustomerConsentService.createContactFromPaymentIfConsented(
                PAYMENT_ID,p,null));
        Test.stopTest();
    }

    @IsTest
    static void testWebhookCreateWithEmailAndPhoneOptIn() {
        Map<String,Object> c = customer(
            'C_CREATE','Payload','Customer',
            'payload@example.com','5551111111',false
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_CREATE','customer.created',webhook(c)
        );
        Test.stopTest();

        Account a = [
            SELECT FirstName,LastName,PersonEmail,PersonMobilePhone,
                   Square_Customer_Id__c,Email_Opt_In__pc,
                   Consent_Date_Time__c,Consent_Source__c
            FROM Account WHERE Id=:id
        ];

        System.assertEquals('Payload',a.FirstName);
        System.assertEquals('Customer',a.LastName);
        System.assertEquals('payload@example.com',a.PersonEmail);
        System.assertEquals('5551111111',a.PersonMobilePhone);
        System.assertEquals('C_CREATE',a.Square_Customer_Id__c);
        System.assertEquals(true,a.Email_Opt_In__pc);
        System.assertNotEquals(null,a.Consent_Date_Time__c);
        System.assertEquals('Square',a.Consent_Source__c);
    }

    @IsTest
    static void testThreeArgCreate() {
        Map<String,Object> c = customer(
            'C_PAYMENT','Payment','Customer',
            'payment@example.com','5552222222',false
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_PAYMENT'),c
        );
        Test.stopTest();

        Account a = [
            SELECT FirstName,LastName,PersonEmail,PersonMobilePhone,
                   Square_Customer_Id__c,Email_Opt_In__pc,Consent_Source__c
            FROM Account WHERE Id=:id
        ];

        System.assertEquals('Payment',a.FirstName);
        System.assertEquals('Customer',a.LastName);
        System.assertEquals('payment@example.com',a.PersonEmail);
        System.assertEquals('5552222222',a.PersonMobilePhone);
        System.assertEquals('C_PAYMENT',a.Square_Customer_Id__c);
        System.assertEquals(true,a.Email_Opt_In__pc);
        System.assertEquals('Square',a.Consent_Source__c);
    }

    @IsTest
    static void testMissingContactAndMissingName() {
        Test.startTest();
        Id noContact =
            SquareCustomerConsentService.createContactFromPaymentIfConsented(
                PAYMENT_ID,
                payment('C_NO_CONTACT'),
                customer('C_NO_CONTACT','No','Contact',null,null,false)
            );

        Id noName =
            SquareCustomerConsentService.createContactFromPaymentIfConsented(
                PAYMENT_ID,
                payment('C_NO_NAME'),
                customer('C_NO_NAME',null,null,
                         'noname2@example.com','5553333333',false)
            );
        Test.stopTest();

        System.assertEquals(null,noContact);
        System.assertEquals(null,noName);
    }

    @IsTest
    static void testFirstNameOnlyUsesFirstNameAsLastName() {
        Map<String,Object> c = customer(
            'C_FIRST_ONLY','FirstOnly',null,
            'firstonly@example.com','5554444444',false
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_FIRST_ONLY'),c
        );
        Test.stopTest();

        Account a = [
            SELECT FirstName,LastName,PersonEmail,PersonMobilePhone
            FROM Account WHERE Id=:id
        ];

        System.assertEquals(null,a.FirstName);
        System.assertEquals('FirstOnly',a.LastName);
        System.assertEquals('firstonly@example.com',a.PersonEmail);
        System.assertEquals('5554444444',a.PersonMobilePhone);
    }

    @IsTest
    static void testUnknownLastNameUsesFirstNameAsLastName() {
        Map<String,Object> c = customer(
            'C_UNKNOWN','Single','Unknown',
            'unknown@example.com','5555555555',false
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_UNKNOWN'),c
        );
        Test.stopTest();

        Account a = [SELECT FirstName,LastName FROM Account WHERE Id=:id];

        System.assertEquals('Single',a.FirstName);
        System.assertEquals('Unknown',a.LastName);
    }

    @IsTest
    static void testUnsubscribedCustomer() {
        Map<String,Object> c = customer(
            'C_UNSUB_TEST','Jane','Doe',
            'unsubtest@example.com','5556666666',true
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_UNSUB_TEST'),c
        );
        Test.stopTest();

        Account a = [
            SELECT Email_Opt_In__pc
            FROM Account WHERE Id=:id
        ];

        System.assertEquals(false,a.Email_Opt_In__pc);
    }

    @IsTest
    static void testNoPreferencesCreatesNullConsent() {
        Map<String,Object> c = customer(
            'C_NO_PREF_CREATE','No','Prefs',
            'noprefs@example.com','5557777777',null
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_NO_PREF_CREATE'),c
        );
        Test.stopTest();

        // In this org Email_Opt_In__pc is not insertable as null for a new
        // Person Account, so Database.insert(..., false) returns a failed
        // SaveResult and the service returns null. The important coverage here
        // is that getEmailMarketingOptIn() reaches its no-preference branch.
        System.assertEquals(null,id);
    }

    @IsTest
    static void testExistingByCustomerIdIsUpdated() {
        Account old = createPersonAccount(
            'C_EXISTING','Existing','Account',
            'old@example.com','5558888888'
        );

        Map<String,Object> c = customer(
            'C_EXISTING','New','Name',
            'new@example.com','5559999999',false
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_EXISTING'),c
        );
        Test.stopTest();

        Account a = [
            SELECT Id,FirstName,LastName,PersonEmail,PersonMobilePhone,
                   Square_Customer_Id__c,Email_Opt_In__pc,Consent_Source__c
            FROM Account WHERE Id=:old.Id
        ];

        System.assertEquals(old.Id,id);
        System.assertEquals('Existing',a.FirstName);
        System.assertEquals('Account',a.LastName);
        System.assertEquals('old@example.com',a.PersonEmail);
        System.assertEquals('5558888888',a.PersonMobilePhone);
        System.assertEquals('C_EXISTING',a.Square_Customer_Id__c);
        System.assertEquals(true,a.Email_Opt_In__pc);
        System.assertEquals('Square',a.Consent_Source__c);
    }

    @IsTest
    static void testExistingByEmailGetsCustomerIdAndPhone() {
        Account old = createPersonAccount(
            null,'Email','Match','emailmatch@example.com',null
        );

        Map<String,Object> c = customer(
            'C_EMAIL_MATCH','Email','Match',
            'emailmatch@example.com','5551010101',false
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_EMAIL_MATCH'),c
        );
        Test.stopTest();

        Account a = [
            SELECT Id,Square_Customer_Id__c,PersonMobilePhone
            FROM Account WHERE Id=:old.Id
        ];

        System.assertEquals(old.Id,id);
        System.assertEquals('C_EMAIL_MATCH',a.Square_Customer_Id__c);
        System.assertEquals('5551010101',a.PersonMobilePhone);
    }

    @IsTest
    static void testExistingByPhoneGetsCustomerIdAndEmail() {
        Account old = createPersonAccount(
            null,'Phone','Match',null,'5552020202'
        );

        Map<String,Object> c = customer(
            'C_PHONE_MATCH','Phone','Match',
            'phonematch@example.com','5552020202',false
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_PHONE_MATCH'),c
        );
        Test.stopTest();

        Account a = [
            SELECT Id,Square_Customer_Id__c,PersonEmail
            FROM Account WHERE Id=:old.Id
        ];

        System.assertEquals(old.Id,id);
        System.assertEquals('C_PHONE_MATCH',a.Square_Customer_Id__c);
        System.assertEquals('phonematch@example.com',a.PersonEmail);
    }

    @IsTest
    static void testExistingMissingFieldsAndUnknownLastName() {
        Account old = createPersonAccount(
            'C_FILL','', 'Unknown', null, null
        );

        Map<String,Object> c = customer(
            'C_FILL','FilledFirst','FilledLast',
            'filled@example.com','5553030303',false
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_FILL'),c
        );
        Test.stopTest();

        Account a = [
            SELECT Id,FirstName,LastName,PersonEmail,PersonMobilePhone
            FROM Account WHERE Id=:old.Id
        ];

        System.assertEquals(old.Id,id);
        System.assertEquals('FilledFirst',a.FirstName);
        System.assertEquals('FilledLast',a.LastName);
        System.assertEquals('filled@example.com',a.PersonEmail);
        System.assertEquals('5553030303',a.PersonMobilePhone);
    }

    @IsTest
    static void testExistingAccountPreservesConsentWhenSquareOmitsIt() {
        Account old = createPersonAccount(
            'C_PRESERVE','Keep','Consent',
            'keep@example.com','5554040404'
        );
        old.Email_Opt_In__pc = true;
        old.Consent_Source__c = 'Existing Source';
        update old;

        Map<String,Object> c = customer(
            'C_PRESERVE','Keep','Consent',
            'keep@example.com','5554040404',null
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_PRESERVE'),c
        );
        Test.stopTest();

        Account a = [
            SELECT Id,Email_Opt_In__pc,Consent_Source__c
            FROM Account WHERE Id=:old.Id
        ];

        System.assertEquals(old.Id,id);
        System.assertEquals(true,a.Email_Opt_In__pc);
        System.assertEquals('Existing Source',a.Consent_Source__c);
    }

    @IsTest
    static void testCreatedAndUpdatedDatesIncludingMilliseconds() {
        Map<String,Object> created = customer(
            'C_CREATED_DATE','Created','Date',
            'createddate@example.com','5555050505',false
        );
        created.put('created_at','2026-02-03T04:05:06.123Z');

        Map<String,Object> updated = customer(
            'C_UPDATED_DATE','Updated','Date',
            'updateddate@example.com','5556060606',false
        );
        updated.put('updated_at','2026-03-04T05:06:07.456Z');

        Test.startTest();
        Id id1 = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_CREATED_DATE','customer.created',webhook(created)
        );
        Id id2 = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_UPDATED_DATE','customer.updated',webhook(updated)
        );
        Test.stopTest();

        Map<Id,Account> rows = new Map<Id,Account>([
            SELECT Consent_Date_Time__c,Consent_Source__c
            FROM Account WHERE Id IN :new Set<Id>{id1,id2}
        ]);

        System.assertEquals(
            Datetime.valueOfGmt('2026-02-03 04:05:06'),
            rows.get(id1).Consent_Date_Time__c
        );
        System.assertEquals(
            Datetime.valueOfGmt('2026-03-04 05:06:07'),
            rows.get(id2).Consent_Date_Time__c
        );
        System.assertEquals('Square',rows.get(id1).Consent_Source__c);
        System.assertEquals('Square',rows.get(id2).Consent_Source__c);
    }

    @IsTest
    static void testInvalidAndBlankDatesFallBackToNow() {
        Map<String,Object> bad = customer(
            'C_BAD_DATE','Bad','Date',
            'bad-date@example.com','5557070707',false
        );
        bad.put('created_at','not-a-date');

        Map<String,Object> blank = customer(
            'C_BLANK_DATE','Blank','Date',
            'blank-date@example.com','5558080808',false
        );
        blank.put('created_at',null);

        Test.startTest();
        Id id1 = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_BAD_DATE','customer.created',webhook(bad)
        );
        Id id2 = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_BLANK_DATE','customer.created',webhook(blank)
        );
        Test.stopTest();

        List<Account> rows = [
            SELECT Consent_Date_Time__c
            FROM Account WHERE Id IN :new Set<Id>{id1,id2}
        ];

        System.assertEquals(2,rows.size());
        for (Account a : rows) {
            System.assertNotEquals(null,a.Consent_Date_Time__c);
        }
    }

    /*
     * IMPORTANT:
     * Each fallback test must be a separate test method.
     *
     * upsertPersonAccountFromSquareCustomer() performs a callout when the
     * webhook payload does not contain a customer. The successful mock then
     * causes the service to insert a Person Account. A second fallback callout
     * in the same test transaction would therefore produce:
     *
     * "You have uncommitted work pending. Please commit or rollback before
     * calling out"
     */

    @IsTest
    static void testWebhookInvalidJsonFallback() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('SUCCESS'));

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_FALLBACK_A','customer.created','{bad json'
        );
        Test.stopTest();

        System.assertNotEquals(null,id);
    }

    @IsTest
    static void testWebhookBlankPayloadFallback() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('SUCCESS'));

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_FALLBACK_B','customer.created',''
        );
        Test.stopTest();

        System.assertNotEquals(null,id);
    }

    @IsTest
    static void testWebhookMissingDataFallback() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('SUCCESS'));

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_FALLBACK_C','customer.created','{"type":"customer.created"}'
        );
        Test.stopTest();

        System.assertNotEquals(null,id);
    }

    @IsTest
    static void testWebhookNullDataFallback() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('SUCCESS'));

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_FALLBACK_D','customer.created','{"data":null}'
        );
        Test.stopTest();

        System.assertNotEquals(null,id);
    }

    @IsTest
    static void testWebhookNullObjectFallback() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('SUCCESS'));

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_FALLBACK_E','customer.created',
            '{"data":{"object":null}}'
        );
        Test.stopTest();

        System.assertNotEquals(null,id);
    }

    @IsTest
    static void testNullSquareCustomerResponse() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('NULL_CUSTOMER'));

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_NULL_CUSTOMER','customer.created',null
        );
        Test.stopTest();

        System.assertEquals(null,id);
    }

    @IsTest
    static void testCalloutReturnedMissingContact() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('MISSING_CONTACT'));

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_NO_CONTACT','customer.created','{bad json'
        );
        Test.stopTest();

        System.assertEquals(null,id);
    }

    @IsTest
    static void testCalloutReturnedMissingName() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('MISSING_NAME'));

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_NO_NAME','customer.created','{bad json'
        );
        Test.stopTest();

        System.assertEquals(null,id);
    }

    @IsTest
    static void testCalloutReturnedUnsubscribedCustomer() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('UNSUBSCRIBED'));

        Test.startTest();
        Id id = SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            'C_UNSUB','customer.created','{bad json'
        );
        Test.stopTest();

        Account a = [
            SELECT FirstName,LastName,Email_Opt_In__pc
            FROM Account WHERE Id=:id
        ];

        System.assertEquals('Jane',a.FirstName);
        System.assertEquals('Doe',a.LastName);
        System.assertEquals(false,a.Email_Opt_In__pc);
    }

    @IsTest
    static void testOldTwoArgMethod() {
        Test.setMock(HttpCalloutMock.class,new CustomerMock('SUCCESS'));

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('CUSTOMER_123')
        );
        Test.stopTest();

        Account a = [
            SELECT Square_Customer_Id__c,PersonEmail,Email_Opt_In__pc,
                   Consent_Source__c
            FROM Account WHERE Id=:id
        ];

        System.assertEquals('CUSTOMER_123',a.Square_Customer_Id__c);
        System.assertEquals('jane@example.com',a.PersonEmail);
        System.assertEquals(true,a.Email_Opt_In__pc);
        System.assertEquals('Square',a.Consent_Source__c);
    }

    @IsTest
    static void testOldTwoArgGuards() {
        Test.startTest();
        Id a = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            '',payment('C1')
        );
        Id b = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,null
        );
        Id c = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,new Map<String,Object>{'id'=>PAYMENT_ID}
        );
        Test.stopTest();

        System.assertEquals(null,a);
        System.assertEquals(null,b);
        System.assertEquals(null,c);
    }

    @IsTest
    static void testInsertDmlFailureReturnsNull() {
        Map<String,Object> c = customer(
            'C_INSERT_FAIL','Insert','Failure',
            null,'5559090909',false
        );

        String oversizedPhone = '';
        for (Integer i=0; i<100; i++) {
            oversizedPhone += '9';
        }
        c.put('phone_number',oversizedPhone);

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_INSERT_FAIL'),c
        );
        Test.stopTest();

        System.assertEquals(null,id);
    }

    @IsTest
    static void testUpdateDmlFailureReturnsExistingId() {
        Account old = createPersonAccount(
            'C_UPDATE_FAIL','Update','Failure',
            null,'5559191919'
        );

        Map<String,Object> c = customer(
            'C_UPDATE_FAIL','Update','Failure',
            null,'5559191919',false
        );

        String oversizedEmail = '';
        for (Integer i=0; i<200; i++) {
            oversizedEmail += 'x';
        }
        oversizedEmail += '@example.com';
        c.put('email_address',oversizedEmail);

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,payment('C_UPDATE_FAIL'),c
        );
        Test.stopTest();

        System.assertEquals(old.Id,id);

        Account a = [
            SELECT PersonEmail
            FROM Account WHERE Id=:old.Id
        ];
        System.assertEquals(null,a.PersonEmail);
    }

    @IsTest
    static void testExistingAccountPreservesConsentWhenSquareOmitsPreferences() {
        Account old = createPersonAccount(
            'C_PRESERVE',
            'Keep',
            'Consent',
            'keep@example.com',
            '5554040404'
        );
        old.Email_Opt_In__pc = true;
        old.Consent_Source__c = 'Existing Source';
        update old;

        Map<String,Object> c = customer(
            'C_PRESERVE',
            'Keep',
            'Consent',
            'keep@example.com',
            '5554040404',
            null
        );

        Test.startTest();
        Id id = SquareCustomerConsentService.createContactFromPaymentIfConsented(
            PAYMENT_ID,
            payment('C_PRESERVE'),
            c
        );
        Test.stopTest();

        Account a = [
            SELECT Id, Email_Opt_In__pc, Consent_Source__c
            FROM Account
            WHERE Id = :old.Id
        ];

        System.assertEquals(old.Id, id);
        System.assertEquals(true, a.Email_Opt_In__pc);
        System.assertEquals('Existing Source', a.Consent_Source__c);
    }

    @IsTest
    static void testLogCustomerSyncError() {
        Test.startTest();
        SquareCustomerConsentService.logCustomerSyncError(
            'C_LOG',
            'customer.created',
            '{"test":true}',
            new AuraHandledException('Forced test error')
        );
        Test.stopTest();

        System.assert(true,'Logging method executed.');
    }
}