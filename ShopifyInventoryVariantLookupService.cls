public with sharing class ShopifyInventoryVariantLookupService {

    public class VariantContext {
        public Id variantSalesforceId;
        public String variantShopifyId;
    }

    public static VariantContext findVariantByInventoryItemId(String inventoryItemId) {
        if (String.isBlank(inventoryItemId)) {
            return null;
        }

        String queryText =
            'query FindVariantByInventoryItem($id: ID!) {' +
            '  inventoryItem(id: $id) {' +
            '    id ' +
            '    variant { id } ' +
            '  }' +
            '}';

        Map<String, Object> variables = new Map<String, Object>{
            'id' => ShopifyGraphQLHelper.toInventoryItemGid(inventoryItemId)
        };

        Map<String, Object> responseMap = ShopifyGraphQLHelper.execute(queryText, variables);
        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        Map<String, Object> inventoryItemMap = dataMap == null ? null : (Map<String, Object>) dataMap.get('inventoryItem');
        Map<String, Object> variantMap = inventoryItemMap == null ? null : (Map<String, Object>) inventoryItemMap.get('variant');

        if (variantMap == null) {
            return null;
        }

        String variantGid = (String) variantMap.get('id');
        String variantShopifyId = ShopifyGraphQLHelper.extractNumericIdFromGid(variantGid);

        List<Product2> variants = [
            SELECT Id, Shop_ID__c
            FROM Product2
            WHERE Shop_ID__c = :variantShopifyId
            LIMIT 1
        ];

        if (variants.isEmpty()) {
            return null;
        }

        VariantContext ctx = new VariantContext();
        ctx.variantSalesforceId = variants[0].Id;
        ctx.variantShopifyId = variantShopifyId;
        return ctx;
    }
}