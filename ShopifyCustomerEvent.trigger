trigger ShopifyCustomerEvent on Shopify_Customer__e (after insert) {
    System.debug('######## ENTERED ShopifyCustomerEvent TRIGGER ########');
    ShopifyPlatformEventHandler.handleCustomerEvents(Trigger.New);
}