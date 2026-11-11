trigger FulfilmentTrigger on Fulfilment__c (after insert, after update) {
    Set<Id> fulfillmentIdsToCreate = new Set<Id>();
    Set<Id> fulfillmentIdsToTrack = new Set<Id>();

    if (Trigger.isInsert) {
        for (Fulfilment__c newRec : Trigger.new) {
            // New Salesforce fulfillment -> create in Shopify only if it does not already have Shopify fulfillment id
            if (String.isBlank(newRec.Shop_ID__c) && newRec.Order__c != null) {
                fulfillmentIdsToCreate.add(newRec.Id);
            }
        }
    }

    if (Trigger.isUpdate) {
        for (Fulfilment__c newRec : Trigger.new) {
            Fulfilment__c oldRec = Trigger.oldMap.get(newRec.Id);

            Boolean trackingChanged =
                newRec.Tracking_Number__c != oldRec.Tracking_Number__c ||
                newRec.Tracking_Company__c != oldRec.Tracking_Company__c ||
                newRec.Tracking_URL__c != oldRec.Tracking_URL__c;

            if (trackingChanged && !String.isBlank(newRec.Shop_ID__c)) {
                fulfillmentIdsToTrack.add(newRec.Id);
            }
        }
    }

    if (!fulfillmentIdsToCreate.isEmpty()) {
        ShopifyFulfillmentCreateService.createFulfillmentsAsync(new List<Id>(fulfillmentIdsToCreate));
    }

    if (!fulfillmentIdsToTrack.isEmpty()) {
        ShopifyFulfillmentTrackingService.syncTrackingAsync(new List<Id>(fulfillmentIdsToTrack));
    }
}