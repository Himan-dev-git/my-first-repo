trigger ShopifyProductEvent on Shopify_Product__e (after insert) {
    System.debug('######## ENTERED ShopifyProductEvent TRIGGER ########');
    ShopifyPlatformEventHandler.handleProductEvents(Trigger.New);
}