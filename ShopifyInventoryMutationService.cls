public with sharing class ShopifyInventoryMutationService {

    public class ResultWrap {
        public Boolean success;
        public String message;
    }

    public static ResultWrap setAvailableQuantity(
        String inventoryItemId,
        String locationId,
        Decimal qty,
        Decimal changeFromQty,
        String idempotencyKey
    ) {
        ResultWrap result = new ResultWrap();
        result.success = false;
        result.message = '';

        if (String.isBlank(inventoryItemId) || String.isBlank(locationId)) {
            result.message = 'Missing inventory item ID or location ID';
            return result;
        }

        String mutation =
            'mutation InventorySet($input: InventorySetQuantitiesInput!, $idempotencyKey: String!) {' +
            '  inventorySetQuantities(input: $input) @idempotent(key: $idempotencyKey) {' +
            '    inventoryAdjustmentGroup { reason } ' +
            '    userErrors { field message } ' +
            '  } ' +
            '}';

        Integer newQty = Integer.valueOf(String.valueOf(qty == null ? 0 : qty));
        Integer fromQty = Integer.valueOf(String.valueOf(changeFromQty == null ? 0 : changeFromQty));

        Map<String, Object> input = new Map<String, Object>{
            'name' => 'available',
            'reason' => 'correction',
            'quantities' => new List<Object>{
                new Map<String, Object>{
                    'inventoryItemId' => ShopifyGraphQLHelper.toInventoryItemGid(inventoryItemId),
                    'locationId' => ShopifyGraphQLHelper.toLocationGid(locationId),
                    'quantity' => newQty,
                    'changeFromQuantity' => fromQty
                }
            }
        };

        Map<String, Object> response = ShopifyGraphQLHelper.execute(
            mutation,
            new Map<String, Object>{
                'input' => input,
                'idempotencyKey' => String.isBlank(idempotencyKey)
                    ? 'sf-inventory-' + String.valueOf(Crypto.getRandomLong())
                    : idempotencyKey
            }
        );

        Map<String, Object> dataMap = (Map<String, Object>) response.get('data');
        Map<String, Object> rootMap =
            dataMap == null ? null : (Map<String, Object>) dataMap.get('inventorySetQuantities');

        List<Object> userErrors =
            rootMap == null ? null : (List<Object>) rootMap.get('userErrors');

        if (userErrors != null && !userErrors.isEmpty()) {
            result.message = JSON.serialize(userErrors);
            return result;
        }

        result.success = true;
        result.message = 'Inventory updated successfully';
        return result;
    }
}