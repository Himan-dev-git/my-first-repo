trigger ProductFileLinkTrigger on ContentDocumentLink (after insert) {
    if (ShopifyProductImageSyncService.bypassProductFileLinkTrigger) {
        System.debug('Skipping ProductFileLinkTrigger because bypass flag is true');
        return;
    }

    Set<Id> productIds = new Set<Id>();

    for (ContentDocumentLink cdl : Trigger.new) {
        if (cdl.LinkedEntityId != null &&
            String.valueOf(cdl.LinkedEntityId).startsWith('01t')) {
            productIds.add(cdl.LinkedEntityId);
        }
    }

    if (!productIds.isEmpty()) {
        ShopifyProductImageSyncService.syncSalesforceFilesToShopify(productIds);
    }
}