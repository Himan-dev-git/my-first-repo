/**
 * Resolves the Pop-up Provider Customer record for a Square POS order.
 *
 * Configuration in this org:
 * - Order.Pop_up_Provider__c is a Lookup(Customer).
 * - The referenced Customer object stores the Square Location ID in
 *   Square_Location_Id__c.
 *
 * Matching is based only on Square Location ID. No Salesforce Location
 * records, Account hierarchy, location names, or record creation are used.
 */
public without sharing class SquarePopUpAccountService {

    private static final String ORDER_PROVIDER_FIELD = 'Pop_up_Provider__c';
    private static final String SQUARE_LOCATION_ID_FIELD = 'Square_Location_Id__c';

    /**
     * Resolve the Customer record referenced by Order.Pop_up_Provider__c.
     * The Square order's location_id must exactly match Customer.Square_Location_Id__c.
     */
    public static Id getPopUpProviderCustomerId(String squareLocationId) {
        if (String.isBlank(squareLocationId)) {
            System.debug(LoggingLevel.WARN,
                'SquarePopUpAccountService: Square Location ID is blank; provider resolution skipped.');
            return null;
        }

        Schema.SObjectType providerCustomerType = getProviderCustomerObjectType();
        if (providerCustomerType == null) {
            System.debug(LoggingLevel.ERROR,
                'SquarePopUpAccountService: Order.Pop_up_Provider__c is not configured as a single-object lookup.');
            return null;
        }

        Map<String, Schema.SObjectField> customerFields =
            providerCustomerType.getDescribe().fields.getMap();
        if (!customerFields.containsKey(SQUARE_LOCATION_ID_FIELD)) {
            System.debug(LoggingLevel.ERROR,
                'SquarePopUpAccountService: provider lookup target ' +
                providerCustomerType.getDescribe().getName() +
                ' does not contain ' + SQUARE_LOCATION_ID_FIELD + '.');
            return null;
        }

        Schema.DescribeFieldResult squareIdDescribe =
            customerFields.get(SQUARE_LOCATION_ID_FIELD).getDescribe();
        if (squareIdDescribe.getType() != Schema.DisplayType.String ||
            !squareIdDescribe.isFilterable()) {
            System.debug(LoggingLevel.ERROR,
                'SquarePopUpAccountService: ' +
                providerCustomerType.getDescribe().getName() + '.' +
                SQUARE_LOCATION_ID_FIELD + ' must be a filterable Text field.');
            return null;
        }

        String objectApiName = providerCustomerType.getDescribe().getName();
        String queryString =
            'SELECT Id, ' + SQUARE_LOCATION_ID_FIELD +
            ' FROM ' + objectApiName +
            ' WHERE ' + SQUARE_LOCATION_ID_FIELD + ' = :squareLocationId';

        List<SObject> exactMatches = new List<SObject>();
        try {
            // SOQL text equality can be case-insensitive. Enforce exact ID
            // equality in Apex after retrieving candidates from the indexed field.
            for (SObject candidate : Database.query(queryString)) {
                String storedSquareLocationId =
                    (String) candidate.get(SQUARE_LOCATION_ID_FIELD);
                if (storedSquareLocationId != null &&
                    storedSquareLocationId.compareTo(squareLocationId) == 0) {
                    exactMatches.add(candidate);
                }
            }
        } catch (Exception queryException) {
            System.debug(LoggingLevel.ERROR,
                'SquarePopUpAccountService: provider Customer lookup failed. object=' +
                objectApiName + ', squareLocationId=' + squareLocationId +
                ', error=' + queryException.getMessage());
            return null;
        }

        if (exactMatches.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'SquarePopUpAccountService: no provider Customer found for Square Location ID. ' +
                'object=' + objectApiName + ', squareLocationId=' + squareLocationId);
            return null;
        }

        if (exactMatches.size() > 1) {
            System.debug(LoggingLevel.ERROR,
                'SquarePopUpAccountService: multiple provider Customer records contain the same ' +
                'Square Location ID. Assignment skipped. squareLocationId=' + squareLocationId);
            return null;
        }

        Id providerCustomerId = (Id) exactMatches[0].get('Id');
        System.debug(LoggingLevel.INFO,
            'SquarePopUpAccountService: resolved Pop-up Provider Customer by Square Location ID. ' +
            'providerObject=' + objectApiName +
            ', providerCustomerId=' + providerCustomerId +
            ', squareLocationId=' + squareLocationId);
        return providerCustomerId;
    }

    /**
     * Returns the object type referenced by Order.Pop_up_Provider__c.
     * This avoids guessing the Customer object's API name (for example,
     * Customer__c) from its Setup label.
     */
    public static Schema.SObjectType getProviderCustomerObjectType() {
        Map<String, Schema.SObjectField> orderFields =
            Schema.SObjectType.Order.fields.getMap();
        if (!orderFields.containsKey(ORDER_PROVIDER_FIELD)) {
            return null;
        }

        Schema.DescribeFieldResult providerDescribe =
            orderFields.get(ORDER_PROVIDER_FIELD).getDescribe();
        if (providerDescribe.getType() != Schema.DisplayType.Reference) {
            return null;
        }

        List<Schema.SObjectType> referenceTypes = providerDescribe.getReferenceTo();
        if (referenceTypes == null || referenceTypes.size() != 1) {
            return null;
        }
        return referenceTypes[0];
    }

    /** True when a lookup field points to the same object as Order.Pop_up_Provider__c. */
    public static Boolean isProviderCustomerReference(Schema.SObjectField fieldToken) {
        if (fieldToken == null) {
            return false;
        }
        Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
        if (fieldDescribe.getType() != Schema.DisplayType.Reference) {
            return false;
        }

        Schema.SObjectType expectedType = getProviderCustomerObjectType();
        if (expectedType == null) {
            return false;
        }

        for (Schema.SObjectType referenceType : fieldDescribe.getReferenceTo()) {
            if (referenceType.getDescribe().getName() == expectedType.getDescribe().getName()) {
                return true;
            }
        }
        return false;
    }

    // Backward-compatible method names retained for existing callers. These
    // now return the Customer lookup target ID, not an Account ID.
    public static Id getPopUpProviderAccountId(String squareLocationId) {
        return getPopUpProviderCustomerId(squareLocationId);
    }

    public static Id getOrCreatePopUpProviderAccount(
        String squareLocationId,
        String ignoredSquareLocationName
    ) {
        return getPopUpProviderCustomerId(squareLocationId);
    }

    public static Id getOrCreatePopUpProviderAccount(String squareLocationId) {
        return getPopUpProviderCustomerId(squareLocationId);
    }
}