public without sharing class SquareCustomerPlatformEventHandler {

    public static void handleAfterInsert(List<Square_Customer__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        for (Square_Customer__e evt : events) {
            try {
                processCustomerEvent(evt);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'SquareCustomerPlatformEventTriggerHandler failed. eventType=' +
                    evt.Event_Type__c +
                    ', customerId=' +
                    evt.Square_Customer_Id__c +
                    ', error=' +
                    e.getMessage()
                );

                SquareCustomerConsentService.logCustomerSyncError(
                    evt.Square_Customer_Id__c,
                    evt.Event_Type__c,
                    evt.Raw_Payload__c,
                    e
                );
            }
        }
    }

    private static void processCustomerEvent(Square_Customer__e evt) {
        if (
            evt.Event_Type__c != 'customer.created' &&
            evt.Event_Type__c != 'customer.updated'
        ) {
            System.debug(
                LoggingLevel.INFO,
                'Square customer platform event ignored. eventType=' +
                evt.Event_Type__c
            );
            return;
        }

        if (String.isBlank(evt.Square_Customer_Id__c)) {
            System.debug(
                LoggingLevel.WARN,
                'Square customer platform event skipped because customer id is blank.'
            );
            return;
        }

        SquareCustomerConsentService.upsertPersonAccountFromSquareCustomer(
            evt.Square_Customer_Id__c,
            evt.Event_Type__c,
            evt.Raw_Payload__c
        );
    }
}