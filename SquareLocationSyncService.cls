public without sharing class SquareLocationSyncService {
    
    private static final String FIELD_SQUARE_LOCATION_ID = 'Square_Location_Id__c';
    private static final String FIELD_SHOPIFY_LOCATION_ID = 'Shopify_Location_ID__c';
    private static final String FIELD_SYNC_STATUS = 'Sync_Status__c';
    //private static final String FIELD_SYNC_ERROR = 'Sync_Error__c';
    private static final String FIELD_IS_INVENTORY_SOURCE = 'Is_Inventory_Source__c';
    private static final String FIELD_IS_FULFILLABLE = 'Is_Fulfillable__c';
    private static final String FIELD_IS_SELLABLE = 'Is_Sellable__c';
    
    public static void syncSalesforceLocationToSquare(
        Id locationId,
        String sourceTopic
    ) {
        if (locationId == null) {
            return;
        }
        
        Schema.SObjectType locationType =
            Schema.getGlobalDescribe().get('Location');
        
        if (locationType == null) {
            System.debug(
                LoggingLevel.ERROR,
                'SquareLocationSyncService: Location object not found.'
            );
            return;
        }
        
        Map<String, Schema.SObjectField> fieldMap =
            locationType.getDescribe().fields.getMap();
        
        String queryText =
            'SELECT Id, Name';
        
        if (fieldMap.containsKey(FIELD_SQUARE_LOCATION_ID.toLowerCase())) {
            queryText += ', ' + FIELD_SQUARE_LOCATION_ID;
        }
        
        if (fieldMap.containsKey(FIELD_SHOPIFY_LOCATION_ID.toLowerCase())) {
            queryText += ', ' + FIELD_SHOPIFY_LOCATION_ID;
        }
        
        if (fieldMap.containsKey(FIELD_IS_INVENTORY_SOURCE.toLowerCase())) {
            queryText += ', ' + FIELD_IS_INVENTORY_SOURCE;
        }
        
        if (fieldMap.containsKey(FIELD_IS_FULFILLABLE.toLowerCase())) {
            queryText += ', ' + FIELD_IS_FULFILLABLE;
        }
        
        if (fieldMap.containsKey(FIELD_IS_SELLABLE.toLowerCase())) {
            queryText += ', ' + FIELD_IS_SELLABLE;
        }
        
        queryText += ' FROM Location WHERE Id = :locationId LIMIT 1';
        
        List<SObject> rows = Database.query(queryText);
        
        if (rows.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'SquareLocationSyncService: no Salesforce Location found. locationId=' +
                locationId
            );
            return;
        }
        
        SObject loc = rows[0];
        
        String name = String.valueOf(loc.get('Name'));
        
        if (String.isBlank(name)) {
            name = 'Salesforce Location ' + String.valueOf(locationId).right(8);
        }
        
        String squareLocationId = null;
        
        if (fieldMap.containsKey(FIELD_SQUARE_LOCATION_ID.toLowerCase())) {
            Object rawSquareLocationId = loc.get(FIELD_SQUARE_LOCATION_ID);
            
            if (rawSquareLocationId != null) {
                squareLocationId = String.valueOf(rawSquareLocationId);
            }
        }
        
        Boolean isActive = true;
        
        if (
            fieldMap.containsKey(FIELD_IS_INVENTORY_SOURCE.toLowerCase()) &&
            loc.get(FIELD_IS_INVENTORY_SOURCE) != null
        ) {
            isActive = (Boolean) loc.get(FIELD_IS_INVENTORY_SOURCE);
        }
        
        if (sourceTopic == 'locations/deactivate') {
            isActive = false;
        }
        
        if (sourceTopic == 'locations/activate') {
            isActive = true;
        }
        
        Map<String, Object> squareResponse;
        
        if (String.isBlank(squareLocationId)) {
            squareLocationId = findSquareLocationIdByName(name);
            
            if (!String.isBlank(squareLocationId)) {
                System.debug(
                    LoggingLevel.INFO,
                    'SquareLocationSyncService: existing Square location found by name. ' +
                    'Updating instead of creating. salesforceLocationId=' +
                    locationId +
                    ', squareLocationId=' +
                    squareLocationId +
                    ', name=' +
                    name
                );
                
                squareResponse = SquareApiClient.updateSquareLocation(
                    squareLocationId,
                    name,
                    isActive
                );
                
            } else {
                System.debug(
                    LoggingLevel.INFO,
                    'SquareLocationSyncService: creating Square location. ' +
                    'salesforceLocationId=' +
                    locationId +
                    ', name=' +
                    name
                );
                
                squareResponse = SquareApiClient.createSquareLocation(
                    name,
                    isActive
                );
            }
            
        } else {
            System.debug(
                LoggingLevel.INFO,
                'SquareLocationSyncService: updating Square location. ' +
                'salesforceLocationId=' +
                locationId +
                ', squareLocationId=' +
                squareLocationId +
                ', name=' +
                name
            );

            squareResponse = SquareApiClient.updateSquareLocation(
                squareLocationId,
                name,
                isActive
            );
        }

        if (squareResponse == null || !squareResponse.containsKey('location')) {
            updateSyncFailure(
                locationId,
                fieldMap,
                'Square location response did not contain location.'
            );
            return;
        }

        Map<String, Object> squareLocation =
            (Map<String, Object>) squareResponse.get('location');

        if (squareLocation == null || squareLocation.get('id') == null) {
            updateSyncFailure(
                locationId,
                fieldMap,
                'Square location response did not contain location.id.'
            );
            return;
        }

        String returnedSquareLocationId = String.valueOf(squareLocation.get('id'));

        SObject updateLoc = locationType.newSObject(locationId);

        if (fieldMap.containsKey(FIELD_SQUARE_LOCATION_ID.toLowerCase())) {
            updateLoc.put(FIELD_SQUARE_LOCATION_ID, returnedSquareLocationId);
        }

        if (fieldMap.containsKey(FIELD_SYNC_STATUS.toLowerCase())) {
            updateLoc.put(FIELD_SYNC_STATUS, 'Synced');
        }

        update updateLoc;

        System.debug(
            LoggingLevel.INFO,
            'SquareLocationSyncService: Square location sync completed. ' +
            'salesforceLocationId=' +
            locationId +
            ', squareLocationId=' +
            returnedSquareLocationId
        );
    }

    private static void updateSyncFailure(
        Id locationId,
        Map<String, Schema.SObjectField> fieldMap,
        String errorMessage
    ) {
        if (locationId == null) {
            return;
        }

        Schema.SObjectType locationType =
            Schema.getGlobalDescribe().get('Location');

        SObject updateLoc = locationType.newSObject(locationId);

        if (fieldMap.containsKey(FIELD_SYNC_STATUS.toLowerCase())) {
            updateLoc.put(FIELD_SYNC_STATUS, 'Failed');
        }

        update updateLoc;

        System.debug(
            LoggingLevel.ERROR,
            'SquareLocationSyncService: sync failed. locationId=' +
            locationId +
            ', error=' +
            errorMessage
        );
    }  
    private static String findSquareLocationIdByName(String locationName) {
    if (String.isBlank(locationName)) {
        return null;
    }

    List<Object> squareLocations = SquareApiClient.listSquareLocations();

    for (Object locationObj : squareLocations) {
        Map<String, Object> squareLocation =
            (Map<String, Object>) locationObj;

        if (squareLocation == null) {
            continue;
        }

        String squareName = squareLocation.get('name') == null
            ? null
            : String.valueOf(squareLocation.get('name'));

        String squareLocationId = squareLocation.get('id') == null
            ? null
            : String.valueOf(squareLocation.get('id'));

        if (
            !String.isBlank(squareName) &&
            !String.isBlank(squareLocationId) &&
            squareName.trim().toLowerCase() == locationName.trim().toLowerCase()
        ) {
            System.debug(
                LoggingLevel.INFO,
                'SquareLocationSyncService: matched existing Square location by name. ' +
                'name=' +
                locationName +
                ', squareLocationId=' +
                squareLocationId
            );

            return squareLocationId;
        }
    }

    return null;
}
}