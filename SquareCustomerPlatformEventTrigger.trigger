trigger SquareCustomerPlatformEventTrigger on Square_Customer__e (after insert) {
    SquareCustomerPlatformEventHandler.handleAfterInsert(Trigger.New);
}