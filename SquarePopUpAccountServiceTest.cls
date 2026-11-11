@IsTest
private class SquarePopUpAccountServiceTest {

    private static SObject createProviderCustomer(String squareLocationId) {
        Schema.SObjectType providerType =
            SquarePopUpAccountService.getProviderCustomerObjectType();
        System.assertNotEquals(
            null,
            providerType,
            'Order.Pop_up_Provider__c must be configured as a lookup to Customer.'
        );

        Map<String, Schema.SObjectField> fields = providerType.getDescribe().fields.getMap();
        System.assert(
            fields.containsKey('Square_Location_Id__c'),
            'The lookup target Customer must contain Square_Location_Id__c.'
        );

        SObject providerCustomer = providerType.newSObject();
        if (fields.containsKey('Name') && fields.get('Name').getDescribe().isCreateable()) {
            providerCustomer.put('Name', 'Provider Test ' + squareLocationId);
        }
        providerCustomer.put('Square_Location_Id__c', squareLocationId);
        insert providerCustomer;
        return providerCustomer;
    }

    @IsTest
    static void testResolvesProviderCustomerByExactSquareLocationIdOnly() {
        SObject providerCustomer = createProviderCustomer('SQ_LOCATION_ABC123');

        Test.startTest();
        Id resolvedProviderId =
            SquarePopUpAccountService.getPopUpProviderCustomerId('SQ_LOCATION_ABC123');
        Test.stopTest();

        System.assertEquals(
            (Id) providerCustomer.get('Id'),
            resolvedProviderId,
            'The resolver must return the Customer record referenced by Order.Pop_up_Provider__c.'
        );
    }

    @IsTest
    static void testLocationNameCompatibilityArgumentIsIgnored() {
        SObject providerCustomer = createProviderCustomer('SQ_LOCATION_ID_ONLY');

        Test.startTest();
        Id resolvedProviderId =
            SquarePopUpAccountService.getOrCreatePopUpProviderAccount(
                'SQ_LOCATION_ID_ONLY',
                'A deliberately unrelated Square Location name'
            );
        Test.stopTest();

        System.assertEquals(
            (Id) providerCustomer.get('Id'),
            resolvedProviderId,
            'Only Square Location ID may be used; the name argument must be ignored.'
        );
    }

    @IsTest
    static void testSquareLocationIdComparisonIsCaseSensitive() {
        createProviderCustomer('SQ_CaseSensitive_123');

        Test.startTest();
        Id wrongCaseProviderId =
            SquarePopUpAccountService.getPopUpProviderCustomerId('sq_casesensitive_123');
        Test.stopTest();

        System.assertEquals(
            null,
            wrongCaseProviderId,
            'A case-only variation must not resolve to a different configured Square Location ID.'
        );
    }

    @IsTest
    static void testDuplicateExactSquareLocationIdsReturnNull() {
        createProviderCustomer('SQ_DUPLICATE_123');
        createProviderCustomer('SQ_DUPLICATE_123');

        Test.startTest();
        Id resolvedProviderId =
            SquarePopUpAccountService.getPopUpProviderCustomerId('SQ_DUPLICATE_123');
        Test.stopTest();

        System.assertEquals(
            null,
            resolvedProviderId,
            'Duplicate Customer mappings must be treated as ambiguous.'
        );
    }

    @IsTest
    static void testUnknownAndBlankSquareLocationIdsReturnNull() {
        Test.startTest();
        Id unknownId =
            SquarePopUpAccountService.getPopUpProviderCustomerId('SQ_ID_NOT_CONFIGURED');
        Id blankId = SquarePopUpAccountService.getPopUpProviderCustomerId(' ');
        Id nullId = SquarePopUpAccountService.getPopUpProviderCustomerId(null);
        Test.stopTest();

        System.assertEquals(null, unknownId);
        System.assertEquals(null, blankId);
        System.assertEquals(null, nullId);
    }
}