public with sharing class ShopifyInventoryLookupService {

    public class VariantInventoryContext {
        public String inventoryItemId;
        public Boolean hasLevelAtLocation;
        public Decimal currentAvailable;
    }

    public static VariantInventoryContext resolveVariantLocationContext(
        String shopifyVariantId,
        String shopifyLocationId
    ) {
        VariantInventoryContext ctx = new VariantInventoryContext();
        ctx.hasLevelAtLocation = false;
        ctx.currentAvailable = null;

        String queryText =
            'query VariantInventoryContext($variantId: ID!) {' +
            '  productVariant(id: $variantId) {' +
            '    id ' +
            '    inventoryItem {' +
            '      id ' +
            '      inventoryLevels(first: 50) {' +
            '        nodes {' +
            '          location { id } ' +
            '          quantities(names: ["available"]) { name quantity } ' +
            '        } ' +
            '      } ' +
            '    } ' +
            '  } ' +
            '}';

        Map<String, Object> variables = new Map<String, Object>{
            'variantId' => ShopifyGraphQLHelper.toVariantGid(shopifyVariantId)
        };

        Map<String, Object> responseMap = ShopifyGraphQLHelper.execute(queryText, variables);

        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        Map<String, Object> productVariantMap = dataMap == null ? null : (Map<String, Object>) dataMap.get('productVariant');
        Map<String, Object> inventoryItemMap = productVariantMap == null ? null : (Map<String, Object>) productVariantMap.get('inventoryItem');

        if (inventoryItemMap == null) {
            return ctx;
        }

        String inventoryItemGid = (String) inventoryItemMap.get('id');
        ctx.inventoryItemId = ShopifyGraphQLHelper.extractNumericIdFromGid(inventoryItemGid);

        Map<String, Object> inventoryLevelsMap = (Map<String, Object>) inventoryItemMap.get('inventoryLevels');
        List<Object> nodes = inventoryLevelsMap == null ? null : (List<Object>) inventoryLevelsMap.get('nodes');

        if (nodes == null) {
            return ctx;
        }

        String targetLocationGid = ShopifyGraphQLHelper.toLocationGid(shopifyLocationId);

        for (Object nodeObj : nodes) {
            Map<String, Object> node = (Map<String, Object>) nodeObj;
            Map<String, Object> locMap = (Map<String, Object>) node.get('location');
            if (locMap == null) continue;

            String locationGid = (String) locMap.get('id');
            if (locationGid != targetLocationGid) continue;

            ctx.hasLevelAtLocation = true;

            List<Object> qtyList = (List<Object>) node.get('quantities');
            if (qtyList != null) {
                for (Object qtyObj : qtyList) {
                    Map<String, Object> qtyMap = (Map<String, Object>) qtyObj;
                    String qtyName = (String) qtyMap.get('name');
                    if (qtyName == 'available') {
                        ctx.currentAvailable = toDecimal(qtyMap.get('quantity'));
                    }
                }
            }

            break;
        }

        return ctx;
    }

    private static Decimal toDecimal(Object valueObj) {
        if (valueObj == null) return null;
        try {
            return Decimal.valueOf(String.valueOf(valueObj));
        } catch (Exception e) {
            return null;
        }
    }
}