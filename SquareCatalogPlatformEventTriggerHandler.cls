public without sharing class SquareCatalogPlatformEventTriggerHandler {

    public static void handleAfterInsert(List<Square_Catalog__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        for (Square_Catalog__e evt : events) {
            try {
                processCatalogEvent(evt);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'SquareCatalogPlatformEventTriggerHandler failed. eventType=' +
                    evt.Event_Type__c +
                    ', squareObjectId=' +
                    evt.Square_Object_Id__c +
                    ', error=' +
                    e.getMessage()
                );
            }
        }
    }

    private static void processCatalogEvent(Square_Catalog__e evt) {
        if (evt == null || String.isBlank(evt.Event_Type__c)) {
            return;
        }

        if (evt.Event_Type__c == 'catalog.version.updated') {
            System.debug(
                LoggingLevel.INFO,
                'Square catalog.version.updated platform event received — enqueuing price sync.'
            );

            System.enqueueJob(new SquareCatalogPriceSyncQueueable());
            return;
        }

        if (evt.Event_Type__c == 'catalog.product.sync') {
            Set<String> variantShopIds = parseStringSet(evt.Variant_Shop_Ids__c);

            if (!variantShopIds.isEmpty()) {
                System.enqueueJob(new SquareCatalogQueueable(variantShopIds));
            }

            return;
        }

        if (evt.Event_Type__c == 'catalog.image.sync') {
            Set<Id> productIds = parseIdSet(evt.Product_Ids__c);

            if (!productIds.isEmpty()) {
                System.enqueueJob(new SquareCatalogImageQueueable(productIds));
            }

            return;
        }

        System.debug(
            LoggingLevel.INFO,
            'Square catalog platform event ignored. eventType=' +
            evt.Event_Type__c
        );
    }

    private static Set<String> parseStringSet(String rawValue) {
        Set<String> values = new Set<String>();

        if (String.isBlank(rawValue)) {
            return values;
        }

        for (String value : rawValue.split(',')) {
            if (!String.isBlank(value)) {
                values.add(value.trim());
            }
        }

        return values;
    }

    private static Set<Id> parseIdSet(String rawValue) {
        Set<Id> values = new Set<Id>();

        if (String.isBlank(rawValue)) {
            return values;
        }

        for (String value : rawValue.split(',')) {
            if (!String.isBlank(value)) {
                values.add((Id) value.trim());
            }
        }

        return values;
    }
}