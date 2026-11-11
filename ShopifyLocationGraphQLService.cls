public without sharing class ShopifyLocationGraphQLService {
    
    private static final String LOCATION_OBJECT_API = 'Location';
    
    // NOTE: fieldMap keys from getDescribe().fields.getMap() are always lowercase.
    // All containsKey() and get() calls on fieldMap must use .toLowerCase() on these constants.
    private static final String FIELD_NAME                = 'Name';
    private static final String FIELD_SHOPIFY_LOCATION_ID = 'Shopify_Location_ID__c';
    private static final String FIELD_SYNC_STATUS         = 'Sync_Status__c';
    private static final String FIELD_LAST_SHOPIFY_SYNC   = 'Last_Shopify_Sync__c';
    private static final String FIELD_IS_INVENTORY_SOURCE = 'Is_Inventory_Source__c';
    private static final String FIELD_IS_FULFILLABLE      = 'Is_Fulfillable__c';
    private static final String FIELD_IS_SELLABLE         = 'Is_Sellable__c';
    private static final String FIELD_SYNC_ERROR          = 'Sync_Error__c';
    
    // Valid Sync_Status__c picklist values (restricted picklist — must match exactly)
    private static final String SYNC_STATUS_SYNCED        = 'Synced';
    private static final String SYNC_STATUS_FAILED        = 'Failed';
    
    // -------------------------------------------------------------------------
    // BULK SYNC — called manually or from a scheduled job
    // -------------------------------------------------------------------------
    public static void syncLocationsFromShopify() {
        
        System.debug('===> [ShopifyLocationGraphQLService.syncLocationsFromShopify] START');
        
        String queryText =
            'query GetAllLocations {' +
            '  locations(first: 100) {' +
            '    nodes {' +
            '      id ' +
            '      name ' +
            '      isActive ' +
            '    }' +
            '  }' +
            '}';
        
        System.debug('[syncLocationsFromShopify] Sending GraphQL query: ' + queryText);
        
        Map<String, Object> responseMap;
        try {
            responseMap = ShopifyGraphQLHelper.execute(queryText, null);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                         '[syncLocationsFromShopify] GraphQL callout FAILED. Error: ' + e.getMessage() +
                         ' | Stack: ' + e.getStackTraceString());
            return;
        }
        
        System.debug('[syncLocationsFromShopify] Raw response: ' + responseMap);
        
        // ── Parse response ────────────────────────────────────────────────────
        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        if (dataMap == null) {
            System.debug(LoggingLevel.ERROR,
                         '[syncLocationsFromShopify] Response has no "data" key. Aborting. Full response: ' + responseMap);
            return;
        }
        
        Map<String, Object> locationsMap = (Map<String, Object>) dataMap.get('locations');
        if (locationsMap == null) {
            System.debug(LoggingLevel.ERROR,
                         '[syncLocationsFromShopify] "data.locations" is null. Aborting.');
            return;
        }
        
        Object rawNodes = locationsMap.get('nodes');
        List<Object> nodes = rawNodes == null ? new List<Object>() : (List<Object>) rawNodes;
        
        System.debug('[syncLocationsFromShopify] Total location nodes received from Shopify: ' + nodes.size());
        
        if (nodes.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                         '[syncLocationsFromShopify] No location nodes returned from Shopify. Nothing to upsert.');
            return;
        }
        
        // ── Describe Location fields (keys are always lowercase) ──────────────
        Schema.SObjectType locationType = Schema.getGlobalDescribe().get(LOCATION_OBJECT_API);
        Map<String, Schema.SObjectField> fieldMap = locationType.getDescribe().fields.getMap();
        
        // ── Build records ─────────────────────────────────────────────────────
        List<SObject> locationsToUpsert = new List<SObject>();
        
        for (Object nodeObj : nodes) {
            Map<String, Object> node = (Map<String, Object>) nodeObj;
            
            String rawGid    = (String)  node.get('id');
            String name      = (String)  node.get('name');
            Boolean isActive = (Boolean) node.get('isActive');
            
            String shopifyId = extractNumericIdFromGid(rawGid);
            
            System.debug('[syncLocationsFromShopify] Processing node — rawGid: ' + rawGid
                         + ' | shopifyId: ' + shopifyId
                         + ' | name: ' + name
                         + ' | isActive: ' + isActive);
            
            if (String.isBlank(shopifyId)) {
                System.debug(LoggingLevel.WARN,
                             '[syncLocationsFromShopify] Could not extract numeric ID from GID "' + rawGid + '". Skipping node.');
                continue;
            }
            
            SObject loc = locationType.newSObject();
            
            // fieldMap keys are lowercase — use .toLowerCase() for all containsKey() checks
            if (fieldMap.containsKey(FIELD_NAME.toLowerCase()))
                loc.put(FIELD_NAME, name);
            
            if (fieldMap.containsKey(FIELD_SHOPIFY_LOCATION_ID.toLowerCase()))
                loc.put(FIELD_SHOPIFY_LOCATION_ID, shopifyId);
            
            if (fieldMap.containsKey(FIELD_SYNC_STATUS.toLowerCase()))
                loc.put(FIELD_SYNC_STATUS, SYNC_STATUS_SYNCED);
            
            if (fieldMap.containsKey(FIELD_LAST_SHOPIFY_SYNC.toLowerCase()))
                loc.put(FIELD_LAST_SHOPIFY_SYNC, System.now());
            
            if (fieldMap.containsKey(FIELD_IS_INVENTORY_SOURCE.toLowerCase()))
                loc.put(FIELD_IS_INVENTORY_SOURCE, isActive);
            
            if (fieldMap.containsKey(FIELD_IS_FULFILLABLE.toLowerCase()))
                loc.put(FIELD_IS_FULFILLABLE, isActive);
            
            if (fieldMap.containsKey(FIELD_IS_SELLABLE.toLowerCase()))
                loc.put(FIELD_IS_SELLABLE, isActive);
            
            System.debug('[syncLocationsFromShopify] Built SObject for shopifyId ' + shopifyId + ': ' + loc);
            
            locationsToUpsert.add(loc);
        }
        
        System.debug('[syncLocationsFromShopify] Total records prepared for upsert: ' + locationsToUpsert.size());
        
        if (locationsToUpsert.isEmpty()) {
            System.debug(LoggingLevel.WARN, '[syncLocationsFromShopify] Nothing to upsert after building records.');
            return;
        }
        
        // ── Upsert ────────────────────────────────────────────────────────────
        // CRITICAL: fieldMap.get() must use lowercase key — NOT the mixed-case constant directly
        Schema.SObjectField upsertField = fieldMap.get(FIELD_SHOPIFY_LOCATION_ID.toLowerCase());
        if (upsertField == null) {
            System.debug(LoggingLevel.ERROR,
                         '[syncLocationsFromShopify] Upsert key field "' + FIELD_SHOPIFY_LOCATION_ID +
                         '" resolved to null from fieldMap. Aborting upsert to avoid duplicate inserts.');
            return;
        }
        
        System.debug('[syncLocationsFromShopify] Upserting ' + locationsToUpsert.size()
                     + ' record(s) using external ID field: ' + upsertField);
        
        List<Database.UpsertResult> results = Database.upsert(locationsToUpsert, upsertField, false);
        
        Integer successCount = 0, failCount = 0;
        for (Integer i = 0; i < results.size(); i++) {
            Database.UpsertResult ur = results[i];
            if (ur.isSuccess()) {
                successCount++;
                System.debug('[syncLocationsFromShopify] Upsert SUCCESS — Id: ' + ur.getId()
                             + ' | isCreated: ' + ur.isCreated());
            } else {
                failCount++;
                System.debug(LoggingLevel.ERROR,
                             '[syncLocationsFromShopify] Upsert FAILED for record index ' + i
                             + ' | Errors: ' + ur.getErrors());
            }
        }
        
        System.debug('===> [syncLocationsFromShopify] DONE. Success: ' + successCount + ' | Failed: ' + failCount);
    }
    
    // -------------------------------------------------------------------------
    // GET OR CREATE — used by inventory webhook to resolve a Location Id
    // -------------------------------------------------------------------------
    public static Id getOrCreateSalesforceLocation(String shopifyLocationId) {
        
        System.debug('===> [getOrCreateSalesforceLocation] START | shopifyLocationId: ' + shopifyLocationId);
        
        if (String.isBlank(shopifyLocationId)) {
            System.debug(LoggingLevel.WARN,
                         '[getOrCreateSalesforceLocation] shopifyLocationId is blank. Returning null.');
            return null;
        }
        
        // ── Check if Location already exists ──────────────────────────────────
        List<SObject> existing = Database.query(
            'SELECT Id FROM Location WHERE Shopify_Location_ID__c = :shopifyLocationId LIMIT 1'
        );
        
        System.debug('[getOrCreateSalesforceLocation] Existing Location records found: ' + existing.size());
        
        if (!existing.isEmpty()) {
            Id existingId = (Id) existing[0].get('Id');
            System.debug('[getOrCreateSalesforceLocation] Found existing Location. Id: ' + existingId + '. Returning.');
            return existingId;
        }
        
        // ── Location not found — fetch from Shopify ───────────────────────────
        System.debug('[getOrCreateSalesforceLocation] No existing Location for shopifyLocationId: '
                     + shopifyLocationId + '. Fetching from Shopify...');
        
        Map<String, Object> shopifyLoc;
        try {
            shopifyLoc = fetchSingleLocation(shopifyLocationId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                         '[getOrCreateSalesforceLocation] fetchSingleLocation threw an exception: ' + e.getMessage()
                         + ' | Stack: ' + e.getStackTraceString());
            shopifyLoc = null;
        }
        
        System.debug('[getOrCreateSalesforceLocation] Shopify location payload: ' + shopifyLoc);
        
        String name = (shopifyLoc != null && shopifyLoc.get('name') != null)
            ? String.valueOf(shopifyLoc.get('name'))
            : 'Shopify Location ' + shopifyLocationId;
        
        Boolean isActive = (shopifyLoc != null && shopifyLoc.get('isActive') != null)
            ? (Boolean) shopifyLoc.get('isActive')
            : true;
        
        System.debug('[getOrCreateSalesforceLocation] Resolved name: "' + name + '" | isActive: ' + isActive);
        
        // ── Build and insert new Location ─────────────────────────────────────
        Schema.SObjectType locationType = Schema.getGlobalDescribe().get(LOCATION_OBJECT_API);
        Map<String, Schema.SObjectField> fieldMap = locationType.getDescribe().fields.getMap();
        
        SObject loc = locationType.newSObject();
        
        // fieldMap keys are lowercase — use .toLowerCase() for all containsKey() checks
        if (fieldMap.containsKey(FIELD_NAME.toLowerCase()))
            loc.put(FIELD_NAME, name);
        
        if (fieldMap.containsKey(FIELD_SHOPIFY_LOCATION_ID.toLowerCase()))
            loc.put(FIELD_SHOPIFY_LOCATION_ID, shopifyLocationId);
        
        if (fieldMap.containsKey(FIELD_SYNC_STATUS.toLowerCase()))
            loc.put(FIELD_SYNC_STATUS, SYNC_STATUS_SYNCED);
        
        if (fieldMap.containsKey(FIELD_LAST_SHOPIFY_SYNC.toLowerCase()))
            loc.put(FIELD_LAST_SHOPIFY_SYNC, System.now());
        
        if (fieldMap.containsKey(FIELD_IS_INVENTORY_SOURCE.toLowerCase()))
            loc.put(FIELD_IS_INVENTORY_SOURCE, isActive);
        
        if (fieldMap.containsKey(FIELD_IS_FULFILLABLE.toLowerCase()))
            loc.put(FIELD_IS_FULFILLABLE, isActive);
        
        if (fieldMap.containsKey(FIELD_IS_SELLABLE.toLowerCase()))
            loc.put(FIELD_IS_SELLABLE, isActive);
        
        System.debug('[getOrCreateSalesforceLocation] Built new Location SObject: ' + loc);
        
        try {
            insert loc;
            Id newId = (Id) loc.get('Id');
            System.debug('===> [getOrCreateSalesforceLocation] INSERT SUCCESS. New Location Id: ' + newId);
            return newId;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR,
                         '[getOrCreateSalesforceLocation] INSERT FAILED. DmlException: ' + e.getMessage()
                         + ' | Stack: ' + e.getStackTraceString());
            return null;
        }
    }
    
    // -------------------------------------------------------------------------
    // FETCH SINGLE LOCATION from Shopify GraphQL
    // -------------------------------------------------------------------------
    public static Map<String, Object> fetchSingleLocation(String shopifyLocationId) {
        
        System.debug('===> [fetchSingleLocation] START | shopifyLocationId: ' + shopifyLocationId);
        
        if (String.isBlank(shopifyLocationId)) {
            System.debug(LoggingLevel.WARN, '[fetchSingleLocation] shopifyLocationId is blank. Returning null.');
            return null;
        }
        
        String queryText =
            'query GetLocation($id: ID!) {' +
            '  location(id: $id) {' +
            '    id name isActive ' +
            '  }' +
            '}';
        
        String locationGid = ShopifyGraphQLHelper.toLocationGid(shopifyLocationId);
        System.debug('[fetchSingleLocation] Resolved GID: ' + locationGid);
        
        Map<String, Object> response;
        try {
            response = ShopifyGraphQLHelper.execute(
                queryText,
                new Map<String, Object>{ 'id' => locationGid }
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                         '[fetchSingleLocation] GraphQL callout FAILED. Error: ' + e.getMessage()
                         + ' | Stack: ' + e.getStackTraceString());
            return null;
        }
        
        System.debug('[fetchSingleLocation] Raw response: ' + response);
        
        Map<String, Object> dataMap = (Map<String, Object>) response.get('data');
        if (dataMap == null) {
            System.debug(LoggingLevel.ERROR,
                         '[fetchSingleLocation] Response "data" key is null. Full response: ' + response);
            return null;
        }
        
        Map<String, Object> locationData = (Map<String, Object>) dataMap.get('location');
        
        if (locationData == null) {
            System.debug(LoggingLevel.WARN,
                         '[fetchSingleLocation] "data.location" is null for GID: ' + locationGid
                         + '. Location may not exist in Shopify.');
        } else {
            System.debug('[fetchSingleLocation] Parsed location data: ' + locationData);
        }
        
        return locationData;
    }
    
    // -------------------------------------------------------------------------
    // HELPERS
    // -------------------------------------------------------------------------
    public static String extractNumericIdFromGid(String gid) {
        if (String.isBlank(gid)) {
            System.debug(LoggingLevel.WARN, '[extractNumericIdFromGid] GID is blank. Returning null.');
            return null;
        }
        
        List<String> parts = gid.split('/');
        
        if (parts.isEmpty()) {
            System.debug(LoggingLevel.WARN, '[extractNumericIdFromGid] Split produced empty list for GID: ' + gid);
            return null;
        }
        
        String numericId = parts[parts.size() - 1];
        System.debug('[extractNumericIdFromGid] GID: ' + gid + ' → numericId: ' + numericId);
        return numericId;
    }
    
    public static void processLocationWebhook(Map<String, Object> payload, String topic) {
        System.debug('===> [ShopifyLocationGraphQLService.processLocationWebhook] START');
        System.debug('[processLocationWebhook] Topic: ' + topic);
        System.debug('[processLocationWebhook] Payload: ' + payload);
        
        if (payload == null || payload.isEmpty()) {
            System.debug(LoggingLevel.WARN, '[processLocationWebhook] Payload is blank. Nothing to process.');
            return;
        }
        
        Object rawId = payload.get('id');
        
        if (rawId == null && payload.get('admin_graphql_api_id') != null) {
            rawId = extractNumericIdFromGid(String.valueOf(payload.get('admin_graphql_api_id')));
        }
        
        String shopifyLocationId = rawId == null ? null : String.valueOf(rawId);
        
        if (String.isBlank(shopifyLocationId)) {
            System.debug(LoggingLevel.WARN, '[processLocationWebhook] Could not resolve Shopify Location Id.');
            return;
        }
        
        String name = payload.get('name') == null
            ? 'Shopify Location ' + shopifyLocationId
            : String.valueOf(payload.get('name'));
        
        Boolean isActive = true;
        
        if (payload.containsKey('active') && payload.get('active') != null) {
            isActive = (Boolean) payload.get('active');
        }
        
        if (payload.containsKey('isActive') && payload.get('isActive') != null) {
            isActive = (Boolean) payload.get('isActive');
        }
        
        if (topic == 'locations/deactivate') {
            isActive = false;
        }
        
        if (topic == 'locations/activate') {
            isActive = true;
        }
        
        Schema.SObjectType locationType = Schema.getGlobalDescribe().get(LOCATION_OBJECT_API);
        
        if (locationType == null) {
            System.debug(LoggingLevel.ERROR, '[processLocationWebhook] Location object not found.');
            return;
        }
        
        Map<String, Schema.SObjectField> fieldMap = locationType.getDescribe().fields.getMap();
        
        SObject loc = locationType.newSObject();
        
        if (fieldMap.containsKey(FIELD_NAME.toLowerCase())) {
            loc.put(FIELD_NAME, name);
        }
        
        if (fieldMap.containsKey(FIELD_SHOPIFY_LOCATION_ID.toLowerCase())) {
            loc.put(FIELD_SHOPIFY_LOCATION_ID, shopifyLocationId);
        }
        
        if (fieldMap.containsKey(FIELD_SYNC_STATUS.toLowerCase())) {
            loc.put(FIELD_SYNC_STATUS, SYNC_STATUS_SYNCED);
        }
        
        if (fieldMap.containsKey(FIELD_LAST_SHOPIFY_SYNC.toLowerCase())) {
            loc.put(FIELD_LAST_SHOPIFY_SYNC, System.now());
        }
        
        if (fieldMap.containsKey(FIELD_IS_INVENTORY_SOURCE.toLowerCase())) {
            loc.put(FIELD_IS_INVENTORY_SOURCE, isActive);
        }
        
        if (fieldMap.containsKey(FIELD_IS_FULFILLABLE.toLowerCase())) {
            loc.put(FIELD_IS_FULFILLABLE, isActive);
        }
        
        if (fieldMap.containsKey(FIELD_IS_SELLABLE.toLowerCase())) {
            loc.put(FIELD_IS_SELLABLE, isActive);
        }
        
        Schema.SObjectField upsertField = fieldMap.get(FIELD_SHOPIFY_LOCATION_ID.toLowerCase());
        
        if (upsertField == null) {
            System.debug(
                LoggingLevel.ERROR,
                '[processLocationWebhook] Upsert field Shopify_Location_ID__c not found. Aborting.'
            );
            return;
        }
        
        try {
            Database.UpsertResult result = Database.upsert(loc, upsertField, false);
            
            if (result.isSuccess()) {
                Id salesforceLocationId = result.getId();
                
                System.debug(
                    '===> [processLocationWebhook] Location upsert SUCCESS. Id: ' +
                    salesforceLocationId +
                    ' | Shopify Location Id: ' +
                    shopifyLocationId +
                    ' | isActive: ' +
                    isActive
                );
                
                /*
* NEW:
* After Shopify location is created/updated in Salesforce,
* sync that Salesforce Location to Square in a separate transaction.
*/
                if (
                    topic == 'locations/create' ||
                    topic == 'locations/update' ||
                    topic == 'locations/activate' ||
                    topic == 'locations/deactivate'
                ) {
                    System.enqueueJob(
                        new SquareLocationSyncQueueable(
                            salesforceLocationId,
                            topic
                        )
                    );
                    
                    System.debug(
                        LoggingLevel.INFO,
                        '[processLocationWebhook] Enqueued SquareLocationSyncQueueable. ' +
                        'locationId=' + salesforceLocationId +
                        ', topic=' + topic
                    );
                }
                
            } else {
                System.debug(
                    LoggingLevel.ERROR,
                    '[processLocationWebhook] Location upsert FAILED: ' +
                    result.getErrors()
                );
            }
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                '[processLocationWebhook] Exception: ' +
                e.getMessage() +
                ' | Stack: ' +
                e.getStackTraceString()
            );
        }
    }
}