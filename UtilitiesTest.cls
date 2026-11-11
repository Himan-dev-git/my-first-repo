@IsTest
private class UtilitiesTest {

    @IsTest
    static void testGetPrimitiveDataTypes() {
        // Select an object with a variety of field types. Using Account as an example.
        String objectName = 'Account';
        
        // Call the method under test
        Map<String, String> fieldToDataTypeMap = Utilities.getPrimitiveDataTypes(objectName);
        
        // Define expected field types for the Account object
        Map<String, String> expectedFieldTypes = new Map<String, String>{
            'name' => 'Text',             // STRING type
            'industry' => 'Text',         // PICKLIST type
            'annualrevenue' => 'Number',  // CURRENCY type
            'createddate' => 'DateTime',  // DATETIME type
            'persondonotcall' => 'Checkbox',    // BOOLEAN type
            'site' => 'Text',             // STRING type
            'phone' => 'Phone',           // PHONE type
            'accountnumber' => 'Text',    // STRING type
            'parentid' => 'Reference',    // REFERENCE type
            'description' => 'TextArea'   // TEXTAREA type
        };
        
        // Assert that the result contains the expected keys and values
        for (String fieldName : expectedFieldTypes.keySet()) {
            System.assert(fieldToDataTypeMap.containsKey(fieldName), 'Expected field not found: ' + fieldName);
            System.assertEquals(expectedFieldTypes.get(fieldName), fieldToDataTypeMap.get(fieldName), 'Field type mismatch for field: ' + fieldName);
        }
        
        // Assert that the map is not empty and has at least the fields we tested
        System.assert(fieldToDataTypeMap.size() > 0, 'The map should not be empty');
        System.assert(fieldToDataTypeMap.size() >= expectedFieldTypes.size(), 'The map should contain at least the expected number of fields');
    }

    @IsTest
    static void testDoGenericMapping() {
        // Setup test data
        String sObjectTypeName = 'Account';
        Map<String, Object> payload = new Map<String, Object>{
            'last_name' => 'Test Account',
            'phone' => '1234567890',
            'email' => 'test@test.com'
        };

        // Simulate field mappings (Assume the metadata exists in the org)
        List<REST_Field_Mapping__mdt> fieldMappings = [
            SELECT Request_Attribute__c, SF_Field_Name__c 
            FROM REST_Field_Mapping__mdt 
            WHERE Topic__c = 'customers'
        ];

        // Call the method under test
        SObject newRecord = Utilities.doGenericMapping(sObjectTypeName, payload, fieldMappings);

        // Assertions
        System.assertEquals('Test Account', newRecord.get('LastName'));
        System.assertEquals('1234567890', newRecord.get('PersonMobilePhone'));
        System.assertEquals('test@test.com', newRecord.get('PersonEmail'));
    }

    @IsTest
    static void testAssignValueToSObject() {
        // Setup test data
        Account testAccount = new Account();
        Map<String, String> fieldDataTypeMap = new Map<String, String>{
            'name' => 'Text',
            'phone' => 'Phone',
            'annualrevenue' => 'Number',
            'createddate' => 'DateTime',
            'persondonotcall' => 'Checkbox'
        };

        // Test different data types
        Utilities.assignValueToSObject(testAccount, 'name', 'Test Account', fieldDataTypeMap);
        Utilities.assignValueToSObject(testAccount, 'phone', '1234567890', fieldDataTypeMap);
        Utilities.assignValueToSObject(testAccount, 'annualrevenue', '5000000', fieldDataTypeMap);
        Utilities.assignValueToSObject(testAccount, 'persondonotcall', 'true', fieldDataTypeMap);

        // Assertions
        System.assertEquals('Test Account', testAccount.Name);
        System.assertEquals('1234567890', testAccount.Phone);
        System.assertEquals(5000000, testAccount.AnnualRevenue);
        System.assertEquals(true, testAccount.PersonDoNotCall);
    }

    @IsTest
    static void testConvertShopifyToSalesforceDateTime() {
        String shopifyDateTimeString = '2024-07-01T12:00:00Z';
        DateTime expectedDateTime = DateTime.newInstanceGMT(2024, 7, 1, 12, 0, 0);
        
        DateTime result = Utilities.convertShopifyToSalesforceDateTime(shopifyDateTimeString);
        System.assertEquals(expectedDateTime, result, 'DateTime conversion mismatch');
    }

    @IsTest
    static void testConvertShopifyToSalesforceDate() {
        String shopifyDateString = '2024-07-01';
        Date expectedDate = Date.newInstance(2024, 7, 1);
        
        Date result = Utilities.convertShopifyToSalesforceDate(shopifyDateString);
        System.assertEquals(expectedDate, result, 'Date conversion mismatch');
    }

    @IsTest
    static void testGetShopIdFields() {
        // Call the method under test
        Map<String, Schema.SObjectField> shopIdFieldMap = Utilities.getShopIdFields();

        // Expected fields
        Map<String, Schema.SObjectField> expectedFields = new Map<String, Schema.SObjectField>{
            'Account' => Account.Shop_Id__c,
            'Order' => Order.Shop_Id__c,
            'OrderItem' => OrderItem.Shop_Id__c,
            'Fulfilment__c' => Fulfilment__c.Shop_Id__c,
            'Product2' => Product2.Shop_Id__c
        };

        // Assertions
        for (String objectName : expectedFields.keySet()) {
            System.assert(shopIdFieldMap.containsKey(objectName), 'Expected object not found: ' + objectName);
            System.assertEquals(expectedFields.get(objectName), shopIdFieldMap.get(objectName), 'Field mismatch for object: ' + objectName);
        }
    }
    
    // New Tests

    @IsTest
    static void testGetChangedFieldsMap() {
        Product2 oldProduct = new Product2(Name = 'Old Product Name', IsActive = true);
        Product2 newProduct = new Product2(Name = 'New Product Name', IsActive = false);

        Map<String, String> changedFields = Utilities.getChangedFieldsMap(newProduct, oldProduct);

        System.assertEquals(2, changedFields.size());
        System.assertEquals('New Product Name', changedFields.get('Name'));
        System.assertEquals('false', changedFields.get('IsActive'));
    }

    @IsTest
    static void testBuildShopifyObject() {
        Product2 oldProduct = new Product2(Status__c = 'Active');
        Product2 newProduct = new Product2(Status__c = '');

        Map<String, String> changedFieldsMap = Utilities.getChangedFieldsMap(newProduct, oldProduct);
        
		// Query the mappings from custom metadata
        List<REST_Field_Mapping__mdt> mappings = [SELECT App_Name__c, Request_Attribute__c, SF_Field_Name__c, SF_Object_Name__c, State__c, Topic__c
                                                    FROM REST_Field_Mapping__mdt
                                                    WHERE State__c IN ('Out', 'Both')
                                                    AND Topic__c = 'products'
                                                  ];
        
        String jsonObject = Utilities.buildShopifyObject('product', changedFieldsMap, mappings);

        System.assertEquals('{"product":{"status":""}}', jsonObject);
    }
}