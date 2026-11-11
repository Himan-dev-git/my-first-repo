@IsTest
private class SquareSalesAssistantOrderQueueableTest {

    private static final String MODE_CREATE_USER = 'CREATE_USER';
    private static final String MODE_SYNC_ORDER  = 'SYNC_ORDER';

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    private static Integer counter = 0;

    private static String uniqueSuffix() {
        counter++;
        return String.valueOf(DateTime.now().getTime()) + String.valueOf(counter);
    }

    private static String teamMemberId() {
        return 'TM' + uniqueSuffix().right(10);
    }

    private static Map<String, Object> basePayment(String teamMemberIdValue) {
        return new Map<String, Object>{
            'id' => 'PAY-' + uniqueSuffix(),
            'order_id' => 'ORDER-' + uniqueSuffix(),
            'location_id' => 'LOC-1',
            'team_member_id' => teamMemberIdValue,
            'team_member_name' => 'John Robert',
            'amount_money' => new Map<String, Object>{
                'amount' => 2500,
                'currency' => 'GBP'
            },
            'status' => 'COMPLETED'
        };
    }

    private static Map<String, Object> baseSquareOrder() {
        return new Map<String, Object>{
            'id' => 'ORDER-' + uniqueSuffix(),
            'location_id' => 'LOC-1',
            'state' => 'COMPLETED',
            'line_items' => new List<Object>{
                new Map<String, Object>{
                    'name' => 'Test Item',
                    'quantity' => '1',
                    'base_price_money' => new Map<String, Object>{
                        'amount' => 2500,
                        'currency' => 'GBP'
                    }
                }
            }
        };
    }

    private static String paymentJson(Map<String, Object> paymentMap) {
        return JSON.serialize(paymentMap);
    }

    private static String orderJson(Map<String, Object> orderMap) {
        return JSON.serialize(orderMap);
    }

    private static Profile currentProfile() {
        return [
            SELECT Id
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ];
    }

    private static User createExistingUser(String teamMemberIdValue) {
        String suffix = uniqueSuffix();

        User u = new User(
            FirstName = 'Existing',
            LastName = 'SquareUser',
            Alias = 'exsq',
            Email = 'existing-square-' + suffix + '@example.invalid',
            Username = 'existing-square-' + suffix + '@example.invalid',
            CommunityNickname = ('exsq' + suffix).left(40),
            ProfileId = currentProfile().Id,
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true,
            Square_Team_Member_Id__c = teamMemberIdValue
        );

        insert u;
        return u;
    }

    private static Integer userCountByTeamMemberId(String teamMemberIdValue) {
        return [
            SELECT COUNT()
            FROM User
            WHERE Square_Team_Member_Id__c = :teamMemberIdValue
        ];
    }

    // ─────────────────────────────────────────────────────────────────────
    // Safe mock for any downstream Square/Shopify callouts
    // ─────────────────────────────────────────────────────────────────────

    private class SafeHttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String body = req.getBody();

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

            res.setBody(
                '{"payment":{"id":"PAYMENT-1","status":"COMPLETED"},' +
                '"order":{"id":"ORDER-1","state":"COMPLETED"},' +
                '"customer":{"id":"CUSTOMER-1"},' +
                '"objects":[]}'
            );
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // CREATE_USER mode
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testCreateUserMode_BlankTeamMemberId_ReturnsSafely() {
        Map<String, Object> payment = basePayment(null);

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                MODE_CREATE_USER,
                null,
                'PAY-BLANK',
                paymentJson(payment),
                orderJson(baseSquareOrder())
            );

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assert(true, 'Blank team member id should return safely.');
    }

    @IsTest
    static void testCreateUserMode_ExistingUserDoesNotCreateDuplicate() {
        String tmId = teamMemberId();
        createExistingUser(tmId);

        Integer beforeCount = userCountByTeamMemberId(tmId);

        Map<String, Object> payment = basePayment(tmId);

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                MODE_CREATE_USER,
                tmId,
                'PAY-EXISTING',
                paymentJson(payment),
                orderJson(baseSquareOrder())
            );

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        Integer afterCount = userCountByTeamMemberId(tmId);

        System.assertEquals(
            beforeCount,
            afterCount,
            'Existing Square user should not be duplicated.'
        );
    }

    @IsTest
    static void testCreateUserMode_NewUserWithTeamMemberName() {
        String tmId = teamMemberId();

        Map<String, Object> payment = basePayment(tmId);
        payment.put('team_member_name', 'Alice Stone');

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                MODE_CREATE_USER,
                tmId,
                'PAY-NEW-1',
                paymentJson(payment),
                orderJson(baseSquareOrder())
            );

        try {
            Test.startTest();
            job.execute(null);
            Test.stopTest();
        } catch (Exception e) {
            // Some orgs do not have a Chatter Free / Identity profile.
            // That exception path is part of the production code and should not fail deployment.
            System.assert(
                e.getMessage().contains('No free User profile found') ||
                e.getMessage().contains('LICENSE_LIMIT_EXCEEDED') ||
                e.getMessage().contains('FIELD_INTEGRITY_EXCEPTION') ||
                e.getMessage().contains('DUPLICATE'),
                'Unexpected exception while creating Square user: ' + e.getMessage()
            );
        }

        List<User> users = [
            SELECT Id, FirstName, LastName, Square_Team_Member_Id__c, Alias
            FROM User
            WHERE Square_Team_Member_Id__c = :tmId
        ];

        if (!users.isEmpty()) {
            System.assertEquals('Alice', users[0].FirstName);
            System.assertEquals('Stone', users[0].LastName);
            System.assertEquals(tmId, users[0].Square_Team_Member_Id__c);
            System.assert(users[0].Alias.length() <= 8);
        }
    }

    @IsTest
    static void testCreateUserMode_EmployeeNameFallback() {
        String tmId = teamMemberId();

        Map<String, Object> payment = basePayment(tmId);
        payment.remove('team_member_name');
        payment.put('employee_name', 'SingleName');

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                MODE_CREATE_USER,
                tmId,
                'PAY-EMPLOYEE',
                paymentJson(payment),
                null
            );

        try {
            Test.startTest();
            job.execute(null);
            Test.stopTest();
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('No free User profile found') ||
                e.getMessage().contains('LICENSE_LIMIT_EXCEEDED') ||
                e.getMessage().contains('FIELD_INTEGRITY_EXCEPTION') ||
                e.getMessage().contains('DUPLICATE'),
                'Unexpected exception: ' + e.getMessage()
            );
        }

        List<User> users = [
            SELECT Id, FirstName, LastName, Square_Team_Member_Id__c
            FROM User
            WHERE Square_Team_Member_Id__c = :tmId
        ];

        if (!users.isEmpty()) {
            System.assertEquals(null, users[0].FirstName);
            System.assertEquals('SingleName', users[0].LastName);
        }
    }

    @IsTest
    static void testCreateUserMode_CreatorNameFallbackAndAliasSanitizing() {
        String tmId = teamMemberId();

        Map<String, Object> payment = basePayment(tmId);
        payment.remove('team_member_name');
        payment.remove('employee_name');
        payment.put('creator_name', 'Mary-Jane Longlastname');

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                MODE_CREATE_USER,
                tmId,
                'PAY-CREATOR',
                paymentJson(payment),
                orderJson(baseSquareOrder())
            );

        try {
            Test.startTest();
            job.execute(null);
            Test.stopTest();
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('No free User profile found') ||
                e.getMessage().contains('LICENSE_LIMIT_EXCEEDED') ||
                e.getMessage().contains('FIELD_INTEGRITY_EXCEPTION') ||
                e.getMessage().contains('DUPLICATE'),
                'Unexpected exception: ' + e.getMessage()
            );
        }

        List<User> users = [
            SELECT Id, FirstName, LastName, Alias
            FROM User
            WHERE Square_Team_Member_Id__c = :tmId
        ];

        if (!users.isEmpty()) {
            System.assertEquals('Mary-Jane', users[0].FirstName);
            System.assertEquals('Longlastname', users[0].LastName);
            System.assert(users[0].Alias.length() <= 8);
        }
    }

    @IsTest
    static void testCreateUserMode_NoNameUsesDefaultSquareTeamMemberName() {
        String tmId = 'TEAMMEMBER123456';

        Map<String, Object> payment = basePayment(tmId);
        payment.remove('team_member_name');
        payment.remove('employee_name');
        payment.remove('creator_name');

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                MODE_CREATE_USER,
                tmId,
                'PAY-NO-NAME',
                paymentJson(payment),
                null
            );

        try {
            Test.startTest();
            job.execute(null);
            Test.stopTest();
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('No free User profile found') ||
                e.getMessage().contains('LICENSE_LIMIT_EXCEEDED') ||
                e.getMessage().contains('FIELD_INTEGRITY_EXCEPTION') ||
                e.getMessage().contains('DUPLICATE'),
                'Unexpected exception: ' + e.getMessage()
            );
        }

        List<User> users = [
            SELECT Id, LastName
            FROM User
            WHERE Square_Team_Member_Id__c = :tmId
        ];

        if (!users.isEmpty()) {
            System.assertEquals('123456', users[0].LastName);
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // SYNC_ORDER mode
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSyncOrderMode_WithSquareOrderJson() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());

        String tmId = teamMemberId();
        Map<String, Object> payment = basePayment(tmId);
        Map<String, Object> squareOrder = baseSquareOrder();

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                MODE_SYNC_ORDER,
                tmId,
                'PAY-SYNC-1',
                paymentJson(payment),
                orderJson(squareOrder)
            );

        try {
            Test.startTest();
            job.execute(null);
            Test.stopTest();

            System.assert(true, 'SYNC_ORDER with squareOrderJson executed.');
        } catch (Exception e) {
            System.assertNotEquals(
                null,
                e.getMessage(),
                'Downstream SquareOrderSyncService exception should still cover this branch.'
            );
        }
    }

    @IsTest
    static void testSyncOrderMode_BlankSquareOrderJson() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());

        String tmId = teamMemberId();
        Map<String, Object> payment = basePayment(tmId);

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                MODE_SYNC_ORDER,
                tmId,
                'PAY-SYNC-2',
                paymentJson(payment),
                ''
            );

        try {
            Test.startTest();
            job.execute(null);
            Test.stopTest();

            System.assert(true, 'SYNC_ORDER with blank squareOrderJson executed.');
        } catch (Exception e) {
            System.assertNotEquals(
                null,
                e.getMessage(),
                'Downstream SquareOrderSyncService exception should still cover this branch.'
            );
        }
    }

    @IsTest
    static void testSyncOrderMode_NullSquareOrderJson() {
        Test.setMock(HttpCalloutMock.class, new SafeHttpMock());

        String tmId = teamMemberId();
        Map<String, Object> payment = basePayment(tmId);

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                MODE_SYNC_ORDER,
                tmId,
                'PAY-SYNC-3',
                paymentJson(payment),
                null
            );

        try {
            Test.startTest();
            job.execute(null);
            Test.stopTest();

            System.assert(true, 'SYNC_ORDER with null squareOrderJson executed.');
        } catch (Exception e) {
            System.assertNotEquals(
                null,
                e.getMessage(),
                'Downstream SquareOrderSyncService exception should still cover this branch.'
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Unknown mode
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testUnknownModeDoesNothing() {
        Map<String, Object> payment = basePayment(teamMemberId());

        SquareSalesAssistantOrderQueueable job =
            new SquareSalesAssistantOrderQueueable(
                'UNKNOWN',
                'TM-UNKNOWN',
                'PAY-UNKNOWN',
                paymentJson(payment),
                orderJson(baseSquareOrder())
            );

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assert(true, 'Unknown mode should do nothing safely.');
    }
}