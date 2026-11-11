public class Utilities {

    // Existing methods remain unchanged...

    public static Map<String, String> getPrimitiveDataTypes(String objectName) {
        // Existing implementation
        Map<String, String> fieldToDataTypeMap = new Map<String, String>();
        Schema.DescribeSObjectResult describeResult = Schema.getGlobalDescribe().get(objectName).getDescribe();
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            String fieldType = fieldDescribe.getType().name();

            switch on fieldType {
                when 'STRING', 'PICKLIST', 'MULTIPICKLIST' {
                    fieldType = 'Text';
                }
                when 'REFERENCE' {
                    fieldType = 'Reference';
                }
                when 'BOOLEAN' {
                    fieldType = 'Checkbox';
                }
                when 'CURRENCY', 'DOUBLE', 'INTEGER', 'LONG' {
                    fieldType = 'Number';
                }
                when 'DATE' {
                    fieldType = 'Date';
                }
                when 'DATETIME' {
                    fieldType = 'DateTime';
                }
                when 'EMAIL' {
                    fieldType = 'Email';
                }
                when 'PHONE' {
                    fieldType = 'Phone';
                }
                when 'TEXTAREA' {
                    fieldType = 'TextArea';
                }
            }
            fieldToDataTypeMap.put(fieldName.toLowerCase(), fieldType);
        }
        return fieldToDataTypeMap;
    }

    public static SObject doGenericMapping(String sObjectTypeName, Map<String, Object> payload, List<REST_Field_Mapping__mdt> fieldMappings) {
        Map<String, String> fieldDataTypeMap = Utilities.getPrimitiveDataTypes(sObjectTypeName);

        SObject newRecord = (SObject)Type.forName('Schema.' + sObjectTypeName).newInstance();

        for (REST_Field_Mapping__mdt fieldMapping : fieldMappings) {
            String jsonField = fieldMapping.Request_Attribute__c.toLowerCase();
            String sObjectField = fieldMapping.SF_Field_Name__c.toLowerCase();
            if (payload.containsKey(jsonField)) {
                Object value = payload.get(jsonField);
                Utilities.assignValueToSObject(newRecord, sObjectField, String.valueOf(value), fieldDataTypeMap);
            }
        }

        return newRecord;
    }

    public static void assignValueToSObject(SObject thisRecord, String sObjectField, String value, Map<String, String> fieldDataTypeMap) {
        if (value != null) {
            String fieldType = fieldDataTypeMap.get(sObjectField);
            if (fieldType == 'DateTime') {
                thisRecord.put(sObjectField, Utilities.convertShopifyToSalesforceDateTime(value));
            } else if (fieldType == 'Date') {
                thisRecord.put(sObjectField, Utilities.convertShopifyToSalesforceDate(value));
            } else if (fieldType == 'Checkbox') {
                thisRecord.put(sObjectField, value.toLowerCase() == 'true');
            } else if (fieldType == 'Number') {
                thisRecord.put(sObjectField, Decimal.valueOf(value));
            } else {
                thisRecord.put(sObjectField, value);
            }
        }
    }

    public static DateTime convertShopifyToSalesforceDateTime(String shopifyDateTimeString) {
        String formattedDateTimeString = shopifyDateTimeString.replace('T', ' ')
            .substring(0, shopifyDateTimeString.length() - 3) 
            + shopifyDateTimeString.substring(shopifyDateTimeString.length() - 2);
        return DateTime.valueOfGmt(formattedDateTimeString);
    }

    public static Date convertShopifyToSalesforceDate(String shopifyDateString) {
        return Date.valueOf(shopifyDateString);
    }

    public static Map<String, Schema.SObjectField> getShopIdFields() {
        Map<String, Schema.SObjectField> shopIdFieldMap = new Map<String, Schema.SObjectField>();

        shopIdFieldMap.put('Account', Account.Shop_Id__c);
        shopIdFieldMap.put('Order', Order.Shop_Id__c);
        shopIdFieldMap.put('OrderItem', OrderItem.Shop_Id__c);
        shopIdFieldMap.put('Fulfilment__c', Fulfilment__c.Shop_Id__c);
        shopIdFieldMap.put('Product2', Product2.Shop_Id__c);

        return shopIdFieldMap;
    }

    // New Methods

    // This method compares the old and new record and returns a map of changed fields with their new values as strings.
    public static Map<String, String> getChangedFieldsMap(SObject newRecord, SObject oldRecord) {
        Map<String, String> changedFieldsMap = new Map<String, String>();
    
        // Get the describe result for the SObject type
        Schema.DescribeSObjectResult describeResult = newRecord.getSObjectType().getDescribe();
        
        // Iterate over all the fields in the SObject
        for (Schema.SObjectField field : describeResult.fields.getMap().values()) {
            String fieldName = field.getDescribe().getName();
            system.debug('fieldName now compared is '+fieldName);
            if(oldRecord.isSet(fieldName) || newRecord.isSet(fieldName)){
                Object newValue = newRecord.get(fieldName);
                Object oldValue = oldRecord.get(fieldName);
        
                // Check if the field has changed, including cases where the new value is an empty string or null
                if (newValue != oldValue) {
                    // Special handling for empty strings and nulls
                    if (newValue == null || String.valueOf(newValue).trim() == '') {
                        if (oldValue != null && String.valueOf(oldValue).trim() != '') {
                            changedFieldsMap.put(fieldName, '');
                        }
                    } else {
                        changedFieldsMap.put(fieldName, String.valueOf(newValue));
                    }
                }
            }
        }
        
        return changedFieldsMap;
    }


    public static String buildShopifyObject(String objectName, Map<String, String> changedFieldsMap, List<REST_Field_Mapping__mdt> mappings) {
        Map<String, Object> shopifyObject = new Map<String, Object>();
        Map<String, Object> innerObject = new Map<String, Object>();
        
        // Loop through the mappings and build the Shopify JSON object
        for (REST_Field_Mapping__mdt mapping : mappings) {
            if (changedFieldsMap.containsKey(mapping.SF_Field_Name__c)) {
                innerObject.put(mapping.Request_Attribute__c, changedFieldsMap.get(mapping.SF_Field_Name__c));
            }
        }
    
        // Only add the object if there are any fields to include
        if (!innerObject.isEmpty()) {
            shopifyObject.put(objectName.toLowerCase(), innerObject);
        }
    	
        // Convert the Map to a JSON string
        return JSON.serialize(shopifyObject);
    }
    
    public static Map<String, List<REST_Field_Mapping__mdt>> getRestFieldMappingGroupedByTopic(List<String> topics) {
        // Query the custom metadata mappings based on the provided topics
        List<REST_Field_Mapping__mdt> allMappings = [
            SELECT App_Name__c, Request_Attribute__c, 
                   SF_Field_Name__c, SF_Object_Name__c, 
                   State__c, Topic__c 
            FROM REST_Field_Mapping__mdt 
            WHERE Topic__c IN :topics
            AND State__c IN ('Out', 'Both')
        ];

        // Initialize the map to categorize mappings based on Topic__c
        Map<String, List<REST_Field_Mapping__mdt>> groupedMappings = new Map<String, List<REST_Field_Mapping__mdt>>();

        // Iterate over the mappings and categorize them
        for (REST_Field_Mapping__mdt mapping : allMappings) {
            // Initialize the list if it doesn't exist
            if (!groupedMappings.containsKey(mapping.Topic__c)) {
                groupedMappings.put(mapping.Topic__c, new List<REST_Field_Mapping__mdt>());
            }

            // Add the current mapping to the appropriate list
            groupedMappings.get(mapping.Topic__c).add(mapping);
        }

        return groupedMappings;
    }

}