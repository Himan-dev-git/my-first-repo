public without sharing class InventoryRuleService {

    public class InventoryRuleResult {
        public String orderType;
        public String locationName;
        public Id locationId;
    }

    /**
     * Returns the Inventory Rule based on Order Type.
     *
     * Example metadata:
     * Inventory_Rules__mdt
     * Order_Type__c = 'Shopify Order'
     * Location__c   = 'Warehouse'
     *
     * Order_Type__c = 'POS'
     * Location__c   = 'Warehouse'
     *
     * POS inventory must always resolve to the Salesforce Location named
     * Warehouse. If the POS metadata rule is missing, blank, configured to
     * another location, or points to a Location that does not exist, the
     * method falls back to the Salesforce Location named Warehouse.
     */
    public static InventoryRuleResult getRuleForOrderType(String orderType) {

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getRuleForOrderType START | inputOrderType=' + orderType
        );

        if (String.isBlank(orderType)) {
            System.debug(
                LoggingLevel.WARN,
                'InventoryRuleService.getRuleForOrderType SKIPPED | reason=Blank order type'
            );
            return null;
        }

        List<Inventory_Rules__mdt> rules = [
            SELECT DeveloperName,
                   Order_Type__c,
                   Location__c
            FROM Inventory_Rules__mdt
            WHERE Order_Type__c = :orderType
            LIMIT 1
        ];

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getRuleForOrderType METADATA_QUERY_RESULT | ' +
            'orderType=' + orderType +
            ', rulesFound=' + rules.size()
        );

        if (rules.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'InventoryRuleService.getRuleForOrderType NO_RULE_FOUND | ' +
                'No Inventory_Rules__mdt record found for orderType=' + orderType
            );

            // POS must still use Warehouse when its metadata record is absent.
            return resolvePosWarehouseFallback(orderType, 'Inventory rule not found');
        }

        Inventory_Rules__mdt rule = rules[0];

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getRuleForOrderType RULE_MATCHED | ' +
            'developerName=' + rule.DeveloperName +
            ', metadataOrderType=' + rule.Order_Type__c +
            ', metadataLocationName=' + rule.Location__c
        );

        if (String.isBlank(rule.Location__c)) {
            System.debug(
                LoggingLevel.WARN,
                'InventoryRuleService.getRuleForOrderType INVALID_RULE | ' +
                'Inventory Rule has blank Location__c. ' +
                'orderType=' + orderType +
                ', developerName=' + rule.DeveloperName
            );

            return resolvePosWarehouseFallback(orderType, 'Inventory rule has blank Location__c');
        }

        // A POS order is required to use Warehouse, not Shop Location or any
        // other Salesforce Location configured by mistake in the metadata.
        if (orderType.equalsIgnoreCase('POS') &&
            !rule.Location__c.trim().equalsIgnoreCase('Warehouse')) {

            System.debug(
                LoggingLevel.WARN,
                'InventoryRuleService.getRuleForOrderType POS_LOCATION_OVERRIDE | ' +
                'POS must use Warehouse. Configured metadata location=' + rule.Location__c +
                ', developerName=' + rule.DeveloperName
            );

            return resolvePosWarehouseFallback(
                orderType,
                'POS metadata location is not Warehouse'
            );
        }

        InventoryRuleResult result = new InventoryRuleResult();
        result.orderType = rule.Order_Type__c;
        result.locationName = rule.Location__c;

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getRuleForOrderType LOCATION_LOOKUP_START | ' +
            'locationName=' + rule.Location__c
        );

        List<SObject> locationRows = Database.query(
            'SELECT Id, Name FROM Location WHERE Name = \'' +
            String.escapeSingleQuotes(rule.Location__c) +
            '\' LIMIT 1'
        );

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getRuleForOrderType LOCATION_QUERY_RESULT | ' +
            'locationName=' + rule.Location__c +
            ', locationsFound=' + locationRows.size()
        );

        if (locationRows.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'InventoryRuleService.getRuleForOrderType LOCATION_NOT_FOUND | ' +
                'No Salesforce Location found for Inventory Rule. ' +
                'orderType=' + orderType +
                ', metadataLocationName=' + rule.Location__c
            );

            // Preserve the original return behavior for non-POS order types.
            // For POS, retry against the required Warehouse Location.
            InventoryRuleResult fallbackResult = resolvePosWarehouseFallback(
                orderType,
                'Metadata Location record not found'
            );
            return fallbackResult == null ? result : fallbackResult;
        }

        SObject locationRow = locationRows[0];
        result.locationId = (Id) locationRow.get('Id');

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getRuleForOrderType SUCCESS | ' +
            'inputOrderType=' + orderType +
            ', matchedMetadataOrderType=' + result.orderType +
            ', matchedLocationName=' + result.locationName +
            ', resolvedLocationId=' + result.locationId
        );

        return result;
    }

    /**
     * POS-specific fallback. Resolves the Salesforce Location named Warehouse.
     * Returns null for non-POS order types so their original behavior is retained.
     */
    private static InventoryRuleResult resolvePosWarehouseFallback(
        String orderType,
        String reason
    ) {
        if (String.isBlank(orderType) || !orderType.equalsIgnoreCase('POS')) {
            return null;
        }

        System.debug(
            LoggingLevel.WARN,
            'InventoryRuleService.resolvePosWarehouseFallback START | ' +
            'orderType=' + orderType +
            ', reason=' + reason
        );

        InventoryRuleResult result = new InventoryRuleResult();
        result.orderType = orderType;
        result.locationName = 'Warehouse';

        String warehouseName = 'Warehouse';
        List<SObject> warehouseRows = Database.query(
            'SELECT Id, Name FROM Location WHERE Name = :warehouseName LIMIT 1'
        );

        if (warehouseRows.isEmpty()) {
            System.debug(
                LoggingLevel.ERROR,
                'InventoryRuleService.resolvePosWarehouseFallback LOCATION_NOT_FOUND | ' +
                'The required Salesforce Location named Warehouse does not exist.'
            );
            return result;
        }

        SObject warehouseRow = warehouseRows[0];
        result.locationName = (String) warehouseRow.get('Name');
        result.locationId = (Id) warehouseRow.get('Id');

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.resolvePosWarehouseFallback SUCCESS | ' +
            'orderType=' + orderType +
            ', locationName=' + result.locationName +
            ', locationId=' + result.locationId
        );

        return result;
    }

    /**
     * Convenience method when you have an Order record.
     * Uses Order.Type to find the matching Inventory Rule.
     */
    public static InventoryRuleResult getRuleForOrder(Order orderRecord) {

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getRuleForOrder START | ' +
            'orderId=' + (orderRecord == null ? null : orderRecord.Id) +
            ', orderType=' + (orderRecord == null ? null : orderRecord.Type)
        );

        if (orderRecord == null) {
            System.debug(
                LoggingLevel.WARN,
                'InventoryRuleService.getRuleForOrder SKIPPED | reason=Order record is null'
            );
            return null;
        }

        String orderType = orderRecord.Type;

        if (String.isBlank(orderType)) {
            System.debug(
                LoggingLevel.WARN,
                'InventoryRuleService.getRuleForOrder SKIPPED | ' +
                'reason=Order.Type is blank, orderId=' + orderRecord.Id
            );
            return null;
        }

        InventoryRuleResult result = getRuleForOrderType(orderType);

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getRuleForOrder END | ' +
            'orderId=' + orderRecord.Id +
            ', orderType=' + orderType +
            ', resolvedLocationName=' + (result == null ? null : result.locationName) +
            ', resolvedLocationId=' + (result == null ? null : result.locationId)
        );

        return result;
    }

    /**
     * Returns only the Salesforce Location Id for an Order Type.
     */
    public static Id getLocationIdForOrderType(String orderType) {

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getLocationIdForOrderType START | orderType=' + orderType
        );

        InventoryRuleResult rule = getRuleForOrderType(orderType);
        Id locationId = rule == null ? null : rule.locationId;

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getLocationIdForOrderType END | ' +
            'orderType=' + orderType +
            ', locationName=' + (rule == null ? null : rule.locationName) +
            ', locationId=' + locationId
        );

        return locationId;
    }

    /**
     * Returns only the Salesforce Location Id for an Order.
     */
    public static Id getLocationIdForOrder(Order orderRecord) {

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getLocationIdForOrder START | ' +
            'orderId=' + (orderRecord == null ? null : orderRecord.Id) +
            ', orderType=' + (orderRecord == null ? null : orderRecord.Type)
        );

        InventoryRuleResult rule = getRuleForOrder(orderRecord);
        Id locationId = rule == null ? null : rule.locationId;

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getLocationIdForOrder END | ' +
            'orderId=' + (orderRecord == null ? null : orderRecord.Id) +
            ', orderType=' + (orderRecord == null ? null : orderRecord.Type) +
            ', locationName=' + (rule == null ? null : rule.locationName) +
            ', locationId=' + locationId
        );

        return locationId;
    }

    /**
     * Returns only the Location name from metadata.
     * Useful for debug messages or fallback logic.
     */
    public static String getLocationNameForOrderType(String orderType) {

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getLocationNameForOrderType START | orderType=' + orderType
        );

        InventoryRuleResult rule = getRuleForOrderType(orderType);
        String locationName = rule == null ? null : rule.locationName;

        System.debug(
            LoggingLevel.INFO,
            'InventoryRuleService.getLocationNameForOrderType END | ' +
            'orderType=' + orderType +
            ', locationName=' + locationName
        );

        return locationName;
    }
}