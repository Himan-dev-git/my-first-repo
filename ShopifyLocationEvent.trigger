trigger ShopifyLocationEvent on Shopify_Location__e (after insert) {
    System.debug('######## ENTERED ShopifyLocationEvent TRIGGER ########');
    ShopifyPlatformEventHandler.handleLocationEvents(Trigger.New);
}