public with sharing class ShopifyInventoryGraphQLService {

    // ====== CHANGE THESE IF YOUR API NAMES ARE DIFFERENT ======
    private static final String PRODUCT_OBJECT_API = 'Product2';
    private static final String LOCATION_OBJECT_API = 'Location';
    private static final String INVENTORY_OBJECT_API = 'Inventory__c';

    // Product fields
    private static final String PRODUCT_FIELD_ID = 'Id';
    private static final String PRODUCT_FIELD_NAME = 'Name';
    private static final String PRODUCT_FIELD_SHOP_ID = 'Shop_Id__c';
    private static final String PRODUCT_FIELD_TYPE = 'Type__c';

    // Shipping package fields - Shopify to Salesforce only
    private static final String PRODUCT_FIELD_SHIPPING_PACKAGE_ID = 'Shipping_Package_ID__c';
    private static final String PRODUCT_FIELD_SHIPPING_PACKAGE = 'Shipping_Package__c';

    // Location fields
    private static final String LOCATION_FIELD_ID = 'Id';
    private static final String LOCATION_FIELD_NAME = 'Name';
    private static final String LOCATION_FIELD_SHOPIFY_LOCATION_ID = 'Shopify_Location_ID__c';
    private static final String LOCATION_FIELD_ACCOUNT = 'Account__c';

    // Inventory fields
    private static final String INV_FIELD_VARIANT = 'Variant__c';
    private static final String INV_FIELD_LOCATION = 'Location__c';
    private static final String INV_FIELD_ACCOUNT = 'Account__c';
    private static final String INV_FIELD_SHOPIFY_INVENTORY_ITEM_ID = 'Shopify_Inventory_Item_ID__c';
    private static final String INV_FIELD_SHOPIFY_LOCATION_ID = 'Shopify_Location_ID__c';
    private static final String INV_FIELD_AVAILABLE = 'Available__c';
    private static final String INV_FIELD_ON_HAND = 'On_Hand__c';
    private static final String INV_FIELD_COMMITTED = 'Committed__c';
    private static final String INV_FIELD_INCOMING = 'Incoming__c';
    private static final String INV_FIELD_INVENTORY_KEY = 'Inventory_Key__c';
    private static final String INV_FIELD_SYNC_STATUS = 'Sync_Status__c';
    private static final String INV_FIELD_LAST_SYNC = 'Last_Shopify_Sync__c';
    private static final String INV_FIELD_SYNC_ERROR = 'Sync_Error__c';
    private static final String INV_FIELD_ADJUSTMENT_STATUS = 'Inventory_Adjustment_Status__c';

    // ==========================================================

    public static void syncVariantInventoryByProductId(Id productId) {
        if (productId == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('Product Id is required.');
        }

        Schema.SObjectType productType = Schema.getGlobalDescribe().get(PRODUCT_OBJECT_API);
        if (productType == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('Object not found: ' + PRODUCT_OBJECT_API);
        }

        String soql =
            'SELECT ' +
            PRODUCT_FIELD_ID + ', ' +
            PRODUCT_FIELD_NAME + ', ' +
            PRODUCT_FIELD_SHOP_ID + ', ' +
            PRODUCT_FIELD_TYPE +
            ' FROM ' + PRODUCT_OBJECT_API +
            ' WHERE Id = :productId LIMIT 1';

        SObject variantProduct = Database.query(soql);

        String shopifyVariantId = (String) variantProduct.get(PRODUCT_FIELD_SHOP_ID);
        String productTypeValue = (String) variantProduct.get(PRODUCT_FIELD_TYPE);

        if (String.isBlank(shopifyVariantId)) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('Shop_Id__c is blank on Product2.');
        }

        if (productTypeValue != null && productTypeValue != 'Variant') {
            System.debug('Warning: Product Type__c is not Variant. Continuing anyway.');
        }

        syncVariantInventoryByShopifyVariantId(productId, shopifyVariantId);
    }

    public static void syncVariantInventoryByShopifyVariantId(Id salesforceVariantId, String shopifyVariantId) {
        if (salesforceVariantId == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('Salesforce variant Id is required.');
        }
        if (String.isBlank(shopifyVariantId)) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('Shopify variant Id is required.');
        }

        String queryText =
            'query GetVariantInventory($variantId: ID!) {' +
            '  productVariant(id: $variantId) {' +
            '    id ' +
            '    inventoryItem {' +
            '      id ' +
            '      sku ' +
            '      inventoryLevels(first: 50) {' +
            '        nodes {' +
            '          id ' +
            '          location {' +
            '            id ' +
            '            name ' +
            '          } ' +
            '          quantities(names: ["available", "on_hand", "committed", "incoming"]) {' +
            '            name ' +
            '            quantity ' +
            '          } ' +
            '        } ' +
            '      } ' +
            '    } ' +
            '  } ' +
            '}';

        Map<String, Object> variables = new Map<String, Object>{
            'variantId' => ShopifyGraphQLHelper.toVariantGid(shopifyVariantId)
        };

        Map<String, Object> responseMap = ShopifyGraphQLHelper.execute(queryText, variables);

        if (responseMap == null || !responseMap.containsKey('data')) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('No data returned from Shopify inventory query.');
        }

        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        if (dataMap == null || dataMap.get('productVariant') == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('productVariant missing in Shopify response.');
        }

        Map<String, Object> productVariantMap = (Map<String, Object>) dataMap.get('productVariant');
        Map<String, Object> inventoryItemMap = (Map<String, Object>) productVariantMap.get('inventoryItem');

        if (inventoryItemMap == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('inventoryItem missing for variant.');
        }

        String inventoryItemGid = (String) inventoryItemMap.get('id');
        String inventoryItemNumericId = extractNumericIdFromGid(inventoryItemGid);

        Map<String, Object> inventoryLevelsMap = (Map<String, Object>) inventoryItemMap.get('inventoryLevels');
        if (inventoryLevelsMap == null || inventoryLevelsMap.get('nodes') == null) {
            return;
        }

        List<Object> levelNodes = (List<Object>) inventoryLevelsMap.get('nodes');
        if (levelNodes.isEmpty()) {
            return;
        }

        // Build location map from Salesforce Location object
        Schema.SObjectType locationType = Schema.getGlobalDescribe().get(LOCATION_OBJECT_API);
        if (locationType == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('Object not found: ' + LOCATION_OBJECT_API);
        }

        Schema.DescribeSObjectResult locationDescribe = locationType.getDescribe();
        Map<String, Schema.SObjectField> locationFieldMap = locationDescribe.fields.getMap();

        if (!locationFieldMap.containsKey(LOCATION_FIELD_SHOPIFY_LOCATION_ID)) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException(
                'Missing field on Location: ' + LOCATION_FIELD_SHOPIFY_LOCATION_ID
            );
        }

        Set<String> shopifyLocationIds = new Set<String>();
        for (Object levelObj : levelNodes) {
            Map<String, Object> levelMap = (Map<String, Object>) levelObj;
            Map<String, Object> locationMap = (Map<String, Object>) levelMap.get('location');
            if (locationMap != null) {
                String locationGid = (String) locationMap.get('id');
                String locationNumericId = extractNumericIdFromGid(locationGid);
                if (!String.isBlank(locationNumericId)) {
                    shopifyLocationIds.add(locationNumericId);
                }
            }
        }

        Map<String, SObject> sfLocationByShopifyLocationId = new Map<String, SObject>();

        if (!shopifyLocationIds.isEmpty()) {
            String locationSoql =
                'SELECT ' + LOCATION_FIELD_ID + ', ' + LOCATION_FIELD_NAME + ', ' + LOCATION_FIELD_SHOPIFY_LOCATION_ID +
                (locationFieldMap.containsKey(LOCATION_FIELD_ACCOUNT) ? ', ' + LOCATION_FIELD_ACCOUNT : '') +
                ' FROM ' + LOCATION_OBJECT_API +
                ' WHERE ' + LOCATION_FIELD_SHOPIFY_LOCATION_ID + ' IN :shopifyLocationIds';

            for (SObject loc : Database.query(locationSoql)) {
                sfLocationByShopifyLocationId.put((String) loc.get(LOCATION_FIELD_SHOPIFY_LOCATION_ID), loc);
            }
        }

        // Inventory object metadata
        Schema.SObjectType inventoryType = Schema.getGlobalDescribe().get(INVENTORY_OBJECT_API);
        if (inventoryType == null) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException('Object not found: ' + INVENTORY_OBJECT_API);
        }

        Map<String, Schema.SObjectField> inventoryFieldMap = inventoryType.getDescribe().fields.getMap();

        if (!inventoryFieldMap.containsKey(INV_FIELD_INVENTORY_KEY)) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException(
                'Missing external id field on Inventory: ' + INV_FIELD_INVENTORY_KEY
            );
        }

        List<SObject> inventoryRowsToUpsert = new List<SObject>();

        for (Object levelObj : levelNodes) {
            Map<String, Object> levelMap = (Map<String, Object>) levelObj;

            Map<String, Object> locationMap = (Map<String, Object>) levelMap.get('location');
            if (locationMap == null) {
                continue;
            }

            String locationGid = (String) locationMap.get('id');
            String locationNumericId = extractNumericIdFromGid(locationGid);

            Decimal availableQty = 0;
            Decimal onHandQty = 0;
            Decimal committedQty = 0;
            Decimal incomingQty = 0;

            List<Object> qtyList = (List<Object>) levelMap.get('quantities');
            if (qtyList != null) {
                for (Object qtyObj : qtyList) {
                    Map<String, Object> qtyMap = (Map<String, Object>) qtyObj;
                    String qtyName = (String) qtyMap.get('name');
                    Decimal qtyValue = toDecimal(qtyMap.get('quantity'));

                    if (qtyName == 'available') {
                        availableQty = qtyValue;
                    } else if (qtyName == 'on_hand') {
                        onHandQty = qtyValue;
                    } else if (qtyName == 'committed') {
                        committedQty = qtyValue;
                    } else if (qtyName == 'incoming') {
                        incomingQty = qtyValue;
                    }
                }
            }

            String inventoryKey = shopifyVariantId + '-' + locationNumericId;

            SObject inventoryRow = inventoryType.newSObject();
            inventoryRow.put(INV_FIELD_INVENTORY_KEY, inventoryKey);

            if (inventoryFieldMap.containsKey(INV_FIELD_VARIANT)) {
                inventoryRow.put(INV_FIELD_VARIANT, salesforceVariantId);
            }
            if (inventoryFieldMap.containsKey(INV_FIELD_SHOPIFY_INVENTORY_ITEM_ID)) {
                inventoryRow.put(INV_FIELD_SHOPIFY_INVENTORY_ITEM_ID, inventoryItemNumericId);
            }
            if (inventoryFieldMap.containsKey(INV_FIELD_SHOPIFY_LOCATION_ID)) {
                inventoryRow.put(INV_FIELD_SHOPIFY_LOCATION_ID, locationNumericId);
            }
            if (inventoryFieldMap.containsKey(INV_FIELD_AVAILABLE)) {
                inventoryRow.put(INV_FIELD_AVAILABLE, availableQty);
            }
            if (inventoryFieldMap.containsKey(INV_FIELD_ON_HAND)) {
                inventoryRow.put(INV_FIELD_ON_HAND, onHandQty);
            }
            if (inventoryFieldMap.containsKey(INV_FIELD_COMMITTED)) {
                inventoryRow.put(INV_FIELD_COMMITTED, committedQty);
            }
            if (inventoryFieldMap.containsKey(INV_FIELD_INCOMING)) {
                inventoryRow.put(INV_FIELD_INCOMING, incomingQty);
            }
            if (inventoryFieldMap.containsKey(INV_FIELD_SYNC_STATUS)) {
                inventoryRow.put(INV_FIELD_SYNC_STATUS, 'Synced');
            }
            if (inventoryFieldMap.containsKey(INV_FIELD_LAST_SYNC)) {
                inventoryRow.put(INV_FIELD_LAST_SYNC, System.now());
            }
            if (inventoryFieldMap.containsKey(INV_FIELD_ADJUSTMENT_STATUS)) {
                inventoryRow.put(INV_FIELD_ADJUSTMENT_STATUS, 'Not Required');
            }

            SObject matchedLocation = sfLocationByShopifyLocationId.get(locationNumericId);
            if (matchedLocation != null) {
                if (inventoryFieldMap.containsKey(INV_FIELD_LOCATION)) {
                    inventoryRow.put(INV_FIELD_LOCATION, matchedLocation.get(LOCATION_FIELD_ID));
                }
                if (inventoryFieldMap.containsKey(INV_FIELD_ACCOUNT)
                    && locationFieldMap.containsKey(LOCATION_FIELD_ACCOUNT)) {
                    inventoryRow.put(INV_FIELD_ACCOUNT, matchedLocation.get(LOCATION_FIELD_ACCOUNT));
                }
            }

            inventoryRowsToUpsert.add(inventoryRow);
        }

        if (!inventoryRowsToUpsert.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(
                inventoryRowsToUpsert,
                inventoryFieldMap.get(INV_FIELD_INVENTORY_KEY),
                false
            );

            List<SObject> failedRows = new List<SObject>();

            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    SObject failedRow = inventoryRowsToUpsert[i];

                    if (inventoryFieldMap.containsKey(INV_FIELD_SYNC_STATUS)) {
                        failedRow.put(INV_FIELD_SYNC_STATUS, 'Failed');
                    }

                    if (inventoryFieldMap.containsKey(INV_FIELD_SYNC_ERROR)) {
                        String errMsg = '';
                        for (Database.Error err : results[i].getErrors()) {
                            errMsg += err.getMessage() + ' | ';
                        }
                        failedRow.put(INV_FIELD_SYNC_ERROR, errMsg);
                    }

                    failedRows.add(failedRow);
                }
            }
            
            if (!failedRows.isEmpty()) {
                List<SObject> rowsWithId = new List<SObject>();
                
                for (SObject failedRow : failedRows) {
                    if (failedRow.get('Id') != null) {
                        rowsWithId.add(failedRow);
                    }
                }
                
                if (!rowsWithId.isEmpty()) {
                    update rowsWithId;
                }
            }
        }
    }
	
    @TestVisible
    private static String formatShopifyMeasurementValue(Map<String, Object> measurementValue) {
        if (measurementValue == null) {
            return null;
        }

        if (!measurementValue.containsKey('value') || measurementValue.get('value') == null) {
            return null;
        }

        String value = String.valueOf(measurementValue.get('value')).trim();
        String unit = null;

        if (measurementValue.containsKey('unit') && measurementValue.get('unit') != null) {
            unit = String.valueOf(measurementValue.get('unit')).trim().toLowerCase();
        }

        if (String.isBlank(unit)) {
            return value;
        }

        if (unit == 'inches' || unit == 'inch' || unit == 'in') {
            return value + 'in';
        }

        if (unit == 'centimeters' || unit == 'centimeter' || unit == 'cm') {
            return value + 'cm';
        }

        if (unit == 'millimeters' || unit == 'millimeter' || unit == 'mm') {
            return value + 'mm';
        }

        if (unit == 'grams' || unit == 'gram' || unit == 'g') {
            return value + 'g';
        }

        if (unit == 'kilograms' || unit == 'kilogram' || unit == 'kg') {
            return value + 'kg';
        }

        if (unit == 'pounds' || unit == 'pound' || unit == 'lb' || unit == 'lbs') {
            return value + 'lb';
        }

        if (unit == 'ounces' || unit == 'ounce' || unit == 'oz') {
            return value + 'oz';
        }

        return value + ' ' + unit;
    }

    public static String extractNumericIdFromGid(String gid) {
        if (String.isBlank(gid)) return null;
        List<String> parts = gid.split('/');
        return parts.isEmpty() ? null : parts[parts.size() - 1];
    }

    private static Decimal toDecimal(Object valueObj) {
        if (valueObj == null) return 0;
        try {
            return Decimal.valueOf(String.valueOf(valueObj));
        } catch (Exception e) {
            return 0;
        }
    }
}