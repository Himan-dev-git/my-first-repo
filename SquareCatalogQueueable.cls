public class SquareCatalogQueueable implements Queueable, Database.AllowsCallouts {

    private Set<String> variantShopIds;

    public SquareCatalogQueueable(Set<String> variantShopIds) {
        this.variantShopIds = variantShopIds;
    }

    public void execute(QueueableContext context) {
        if (variantShopIds == null || variantShopIds.isEmpty()) return;

        List<Product2> variants = [
            SELECT Id
            FROM Product2
            WHERE Shop_ID__c IN :variantShopIds
            AND Type__c = 'Variant'
        ];

        List<Id> variantIds = new List<Id>();

        for (Product2 v : variants) {
            variantIds.add(v.Id);
        }

        if (!variantIds.isEmpty()) {
            SquareCatalogService.syncProductsToSquare(variantIds);
        }
    }
}