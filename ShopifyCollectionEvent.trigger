trigger ShopifyCollectionEvent on Shopify_Collection__e (after insert) {
    System.debug('######## ENTERED ShopifyCollectionEvent TRIGGER ########');
    ShopifyPlatformEventHandler.handleCollectionEvents(Trigger.New);
}