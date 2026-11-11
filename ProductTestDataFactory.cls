@IsTest
public class ProductTestDataFactory {

    // Method to create a single test Product (calls the multiple product method with 1)
    public static Product2 createTestProduct() {
        return createTestProducts(1)[0];
    }

    // Overloaded method to create multiple test Products with variations
    public static List<Product2> createTestProducts(Integer numberOfProducts) {
        // Insert a Standard Price Book
        Id pricebookId = Test.getStandardPricebookId();
        Pricebook2 standardPricebook = new Pricebook2(
            Id = pricebookId,
            IsActive = true
        );
        update standardPricebook;

        // Map of Shop_IDs to Unit Prices for Products
        Map<String, Decimal> productShopIdToPriceMap = new Map<String, Decimal>{
            '44338456789163' => 35.00,
            '43545550651563' => 29.00,
            '43491009855659' => 45.00,
            '43563139137707' => 62.57,
            '39072856' => 199.00,
            '49148385' => 199.00,
            '457924702' => 199.00
        };

        List<Product2> products = new List<Product2>();
        List<PricebookEntry> pricebookEntries = new List<PricebookEntry>();

        // Create Product2 records with variations
        Integer i = 0;
        for (String shopId : productShopIdToPriceMap.keySet()) {
            if (i >= numberOfProducts) break;

            Decimal price = productShopIdToPriceMap.get(shopId);

            Product2 product = new Product2(
                Name = 'Test Product ' + (i + 1),
                ProductCode = 'TP' + (123 + i),
                Shop_ID__c = shopId,
                IsActive = true
            );
            products.add(product);
            i++;
        }
        insert products;

        // Now create corresponding PricebookEntry records after products have been inserted
        for (Product2 product : products) {
            Decimal price = productShopIdToPriceMap.get(product.Shop_ID__c);

            PricebookEntry pbe = new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product.Id,  // Ensure Product2Id is set correctly after insertion
                UnitPrice = price,
                IsActive = true,
                UseStandardPrice = false
            );
            pricebookEntries.add(pbe);
        }
        insert pricebookEntries;

        return products;
    }
}