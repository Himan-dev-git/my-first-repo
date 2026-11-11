public without sharing class SquareCatalogPriceSyncService {
    private static final Id SQUARE_PRICEBOOK_ID = '01sS8000008ogx9IAA';
    private static final Integer MAX_CALLOUTS_PER_RUN = 90;

    public static void syncSquarePricesToSalesforce() {

        List<Product2> variants = [
            SELECT Id,
                   Name,
                   Square_Catalog_Variation_Id__c
            FROM Product2
            WHERE Square_Catalog_Variation_Id__c != null
        ];

        System.debug('Mapped variants found: ' + variants.size());

        if (variants.isEmpty()) {
            System.debug('No mapped variants found. Exiting.');
            return;
        }

        Set<Id> productIds = new Set<Id>();
        for (Product2 variant : variants) {
            productIds.add(variant.Id);
        }

        Map<Id, PricebookEntry> pbeByProductId = new Map<Id, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
            AND Pricebook2Id = :SQUARE_PRICEBOOK_ID
            AND IsActive = true
        ]) {
            pbeByProductId.put(pbe.Product2Id, pbe);
        }

        System.debug('Square PricebookEntries found: ' + pbeByProductId.size());

        List<PricebookEntry> updates = new List<PricebookEntry>();
        Integer calloutCount = 0;

        for (Product2 variant : variants) {

            if (calloutCount >= MAX_CALLOUTS_PER_RUN) {
                System.debug('Reached callout limit. Processed: ' + calloutCount);
                break;
            }

            PricebookEntry pbe = pbeByProductId.get(variant.Id);
            if (pbe == null) {
                System.debug('No Square PricebookEntry for variant: ' + variant.Name + ' — skipping.');
                continue;
            }

            Map<String, Object> response;
            try {
                response = SquareApiClient.retrieveCatalogObject(
                    variant.Square_Catalog_Variation_Id__c
                );
                calloutCount++;
            } catch (Exception e) {
                System.debug(
                    'ERROR retrieving catalog object for variant: ' + variant.Name +
                    ', VariationId: ' + variant.Square_Catalog_Variation_Id__c +
                    ', Error: ' + e.getMessage()
                );
                continue;
            }

            try {
                Map<String, Object> obj =
                    (Map<String, Object>) response.get('object');
                if (obj == null) {
                    System.debug('No object in response for variant: ' + variant.Name);
                    continue;
                }

                Map<String, Object> variationData =
                    (Map<String, Object>) obj.get('item_variation_data');
                if (variationData == null) {
                    System.debug('No item_variation_data for variant: ' + variant.Name);
                    continue;
                }

                Map<String, Object> priceMoney =
                    (Map<String, Object>) variationData.get('price_money');
                if (priceMoney == null || priceMoney.get('amount') == null) {
                    System.debug('No price_money for variant: ' + variant.Name);
                    continue;
                }

                Decimal squarePrice =
                    Decimal.valueOf(String.valueOf(priceMoney.get('amount'))) / 100;

                System.debug(
                    'PRICE CHECK => Product=' + variant.Name +
                    ', VariationId=' + variant.Square_Catalog_Variation_Id__c +
                    ', PBE Id=' + pbe.Id +
                    ', SF Price=' + pbe.UnitPrice +
                    ', Square Price=' + squarePrice
                );

                if (pbe.UnitPrice.setScale(2) != squarePrice.setScale(2)) {
                    updates.add(new PricebookEntry(
                        Id = pbe.Id,
                        UnitPrice = squarePrice
                    ));
                }

            } catch (Exception e) {
                System.debug(
                    'ERROR processing price for variant: ' + variant.Name +
                    ', Error: ' + e.getMessage()
                );
                continue;
            }
        }

        System.debug('PricebookEntries to update: ' + updates.size());
        System.debug('PricebookEntry updates: ' + updates);

        if (!updates.isEmpty()) {
            try {
                update updates;
                System.debug('Successfully updated ' + updates.size() + ' PricebookEntries.');
            } catch (DmlException e) {
                System.debug('ERROR updating PricebookEntries: ' + e.getMessage());
            }
        }
    }
}