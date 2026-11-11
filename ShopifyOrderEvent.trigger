trigger ShopifyOrderEvent on Shopify_Order__e (after insert) {
    ShopifyPlatformEventHandler.handleOrderEvents(Trigger.New);
}