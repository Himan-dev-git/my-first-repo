public without sharing class SquareInventoryDeductionService {

    private static final String ORDER_TYPE_POS = 'POS';

    public static void deductInventoryForPayment(String paymentId) {
        if (String.isBlank(paymentId)) {
            System.debug(LoggingLevel.WARN, 'Square inventory skipped: blank paymentId.');
            return;
        }

        Map<String, Object> payment = SquareApiClient.retrievePayment(paymentId);

        if (payment == null || payment.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'Square inventory skipped: payment not found. paymentId=' + paymentId);
            return;
        }

        String squareOrderId = (String) payment.get('order_id');

        if (String.isBlank(squareOrderId)) {
            System.debug('Square inventory skipped: payment has no order_id. Payment=' + paymentId);
            return;
        }

        Map<String, Object> squareOrder = SquareApiClient.retrieveOrder(squareOrderId);

        if (squareOrder == null || squareOrder.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'Square inventory skipped: Square order not found. Order=' + squareOrderId);
            return;
        }

        List<Object> lineItems = (List<Object>) squareOrder.get('line_items');

        if (lineItems == null || lineItems.isEmpty()) {
            System.debug('Square inventory skipped: order has no line_items. Order=' + squareOrderId);
            return;
        }

        DeductionLocation deductionLocation = getDeductionLocationForOrderType(ORDER_TYPE_POS);

        if (deductionLocation == null || deductionLocation.locationId == null) {
            System.debug(
                LoggingLevel.WARN,
                'Square inventory skipped: no deduction location found from Inventory Rules for order type=' +
                ORDER_TYPE_POS
            );
            return;
        }

        Map<String, Decimal> qtyBySquareVariationId = new Map<String, Decimal>();

        for (Object obj : lineItems) {
            Map<String, Object> line = (Map<String, Object>) obj;

            String catalogObjectId = (String) line.get('catalog_object_id');

            if (String.isBlank(catalogObjectId)) {
                continue;
            }

            Decimal qty = parseDecimal(line.get('quantity'));

            if (qty == null || qty <= 0) {
                continue;
            }

            if (!qtyBySquareVariationId.containsKey(catalogObjectId)) {
                qtyBySquareVariationId.put(catalogObjectId, 0);
            }

            qtyBySquareVariationId.put(
                catalogObjectId,
                qtyBySquareVariationId.get(catalogObjectId) + qty
            );
        }

        if (qtyBySquareVariationId.isEmpty()) {
            System.debug('Square inventory skipped: no catalog_object_id on order lines.');
            return;
        }

        List<Product2> variants = [
            SELECT Id,
                   Name,
                   Square_Catalog_Variation_Id__c,
                   Shop_ID__c
            FROM Product2
            WHERE Square_Catalog_Variation_Id__c IN :qtyBySquareVariationId.keySet()
        ];

        if (variants.isEmpty()) {
            System.debug('Square inventory skipped: no Salesforce variants matched Square variation ids.');
            return;
        }

        Set<Id> variantIds = new Set<Id>();

        for (Product2 variant : variants) {
            variantIds.add(variant.Id);
        }

        Map<Id, Inventory__c> inventoryByVariantId =
            getInventoryByVariantForLocation(variantIds, deductionLocation.locationId);

        List<Inventory__c> updates = new List<Inventory__c>();

        for (Product2 variant : variants) {
            Inventory__c inv = inventoryByVariantId.get(variant.Id);

            if (inv == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'Square inventory skipped: no inventory row found for variant and Inventory Rules location. ' +
                    'variantId=' + variant.Id +
                    ', variantName=' + variant.Name +
                    ', locationId=' + deductionLocation.locationId +
                    ', locationName=' + deductionLocation.locationName
                );
                continue;
            }

            Decimal qtyToDeduct =
                qtyBySquareVariationId.get(variant.Square_Catalog_Variation_Id__c);

            if (qtyToDeduct == null || qtyToDeduct <= 0) {
                continue;
            }

            Decimal currentQty = inv.Salesforce_Available__c == null ? 0 : inv.Salesforce_Available__c;
            Decimal newQty = currentQty - qtyToDeduct;

            if (newQty < 0) {
                System.debug(
                    LoggingLevel.WARN,
                    'Square inventory deduction will make quantity negative. ' +
                    'variantId=' + variant.Id +
                    ', inventoryId=' + inv.Id +
                    ', locationId=' + deductionLocation.locationId +
                    ', locationName=' + deductionLocation.locationName +
                    ', currentQty=' + currentQty +
                    ', qtyToDeduct=' + qtyToDeduct +
                    ', newQty=' + newQty
                );
            }
            
            /*
* NEW INVENTORY MODEL:
* Square popup sales are not visible to Shopify.
* Therefore Square deductions should reduce Salesforce_Available__c only.
* Available__c remains the latest Shopify available quantity snapshot.
*/
            Inventory__c updatedInv = new Inventory__c();
            updatedInv.Id = inv.Id;
			updatedInv.Salesforce_Available__c = newQty;            
            updatedInv.Sync_Status__c = 'Success';
            updatedInv.Last_Sync_At__c = System.now();

            updates.add(updatedInv);

            System.debug(
                LoggingLevel.INFO,
                'Square inventory deducted using Inventory Rules location. ' +
                'orderType=' + ORDER_TYPE_POS +
                ', variantId=' + variant.Id +
                ', inventoryId=' + inv.Id +
                ', locationId=' + deductionLocation.locationId +
                ', locationName=' + deductionLocation.locationName +
                ', currentQty=' + currentQty +
                ', deductQty=' + qtyToDeduct +
                ', newQty=' + newQty
            );
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static Map<Id, Inventory__c> getInventoryByVariantForLocation(
        Set<Id> variantIds,
        Id locationId
    ) {
        Map<Id, Inventory__c> result = new Map<Id, Inventory__c>();

        if (variantIds == null || variantIds.isEmpty() || locationId == null) {
            return result;
        }

        List<Inventory__c> inventoryRows = [
            SELECT Id,
                   Variant__c,
                   Available__c,
                   Salesforce_Available__c,
                   Location__c,
                   Location__r.Name,
                   Shopify_Location_ID__c,
                   Shopify_Inventory_Item_ID__c,
                   Last_Sync_At__c
            FROM Inventory__c
            WHERE Variant__c IN :variantIds
            AND Location__c = :locationId
        ];

        for (Inventory__c inv : inventoryRows) {
            if (inv.Variant__c == null) {
                continue;
            }

            if (result.containsKey(inv.Variant__c)) {
                System.debug(
                    LoggingLevel.WARN,
                    'Duplicate inventory rows found for same variant and location. ' +
                    'variantId=' + inv.Variant__c +
                    ', locationId=' + locationId +
                    '. Please enforce unique Variant + Location inventory rule.'
                );
                continue;
            }

            result.put(inv.Variant__c, inv);
        }

        return result;
    }

    private static DeductionLocation getDeductionLocationForOrderType(String orderType) {
        if (String.isBlank(orderType)) {
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

        if (rules.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'No Inventory Rule found for orderType=' + orderType
            );
            return null;
        }

        String locationName = rules[0].Location__c;

        if (String.isBlank(locationName)) {
            System.debug(
                LoggingLevel.WARN,
                'Inventory Rule has blank Location. orderType=' + orderType
            );
            return null;
        }

        List<SObject> locationRows = Database.query(
            'SELECT Id, Name FROM Location WHERE Name = \'' +
            String.escapeSingleQuotes(locationName) +
            '\' LIMIT 1'
        );

        if (locationRows.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'No Salesforce Location found matching Inventory Rule location. ' +
                'orderType=' + orderType +
                ', locationName=' + locationName
            );
            return null;
        }

        SObject locationRow = locationRows[0];

        DeductionLocation result = new DeductionLocation();
        result.locationId = (Id) locationRow.get('Id');
        result.locationName = (String) locationRow.get('Name');

        return result;
    }

    private static Decimal parseDecimal(Object value) {
        if (value == null) {
            return null;
        }

        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to parse decimal value. value=' + value +
                ', error=' + ex.getMessage()
            );
            return null;
        }
    }

    private class DeductionLocation {
        Id locationId;
        String locationName;
    }
}