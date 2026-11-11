public without sharing class ProductSalesInsightService {

    public static void refreshForProducts(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return;
        }

        Date startDate = Date.today().addDays(-90);

        Map<Id, Decimal> unitsByProduct = new Map<Id, Decimal>();
        Map<Id, Decimal> netSalesByProduct = new Map<Id, Decimal>();
        Map<Id, Set<Id>> buyerIdsByProduct = new Map<Id, Set<Id>>();

        List<OrderItem> items = [
            SELECT Id,
                   Product2Id,
                   Quantity,
                   UnitPrice,
                   TotalPrice,
                   OrderId,
                   Order.AccountId,
                   Order.EffectiveDate,
                   Order.Status,
                   Order.Type
            FROM OrderItem
            WHERE Product2Id IN :productIds
              AND Order.EffectiveDate >= :startDate
              AND Order.Type = 'Shopify Order'
        ];

        for (OrderItem oi : items) {
            if (oi.Product2Id == null) {
                continue;
            }

            if (!unitsByProduct.containsKey(oi.Product2Id)) {
                unitsByProduct.put(oi.Product2Id, 0);
                netSalesByProduct.put(oi.Product2Id, 0);
                buyerIdsByProduct.put(oi.Product2Id, new Set<Id>());
            }

            unitsByProduct.put(
                oi.Product2Id,
                unitsByProduct.get(oi.Product2Id) + (oi.Quantity == null ? 0 : oi.Quantity)
            );

            Decimal lineNet = oi.TotalPrice != null
                ? oi.TotalPrice
                : ((oi.Quantity == null ? 0 : oi.Quantity) * (oi.UnitPrice == null ? 0 : oi.UnitPrice));

            netSalesByProduct.put(
                oi.Product2Id,
                netSalesByProduct.get(oi.Product2Id) + lineNet
            );

            if (oi.Order != null && oi.Order.AccountId != null) {
                buyerIdsByProduct.get(oi.Product2Id).add(oi.Order.AccountId);
            }
        }

        List<Product2> updates = new List<Product2>();

        for (Id productId : productIds) {
            Decimal units = unitsByProduct.containsKey(productId)
                ? unitsByProduct.get(productId)
                : 0;

            Decimal netSales = netSalesByProduct.containsKey(productId)
                ? netSalesByProduct.get(productId)
                : 0;

            Integer buyers = buyerIdsByProduct.containsKey(productId)
                ? buyerIdsByProduct.get(productId).size()
                : 0;

            updates.add(new Product2(
                Id = productId,
                Sales_Last_90_Days_Unit__c = units,
                Sales_Last_90_Days_Buyer__c = buyers,
                Sales_Last_90_Days_Net_Sales__c = netSales,
                Sales_Insight_Last_Sync__c = System.now()
            ));
        }
        
        if (!updates.isEmpty()) {
            try {
                update updates;
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'ProductSalesInsightService Product2 update failed: ' +
                    e.getMessage()
                );
            }
        }
    }
    
    @future
    public static void refreshForProductsAsync(List<Id> productIds) {
        refreshForProducts(new Set<Id>(productIds));
    }
}