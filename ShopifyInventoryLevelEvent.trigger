trigger ShopifyInventoryLevelEvent on Shopify_Inventory_Level__e (after insert) {
    System.debug('######## ENTERED ShopifyInventoryLevelEvent TRIGGER ########');
    ShopifyPlatformEventHandler.handleInventoryLevelEvents(Trigger.New);
}