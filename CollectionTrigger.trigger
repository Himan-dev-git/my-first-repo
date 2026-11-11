trigger CollectionTrigger on Collection__c (after insert, after update) {
    if (ShopifyCollectionGraphQLService.bypassCollectionTrigger) return;

    for (Collection__c c : Trigger.new) {
        Collection__c oldRec = Trigger.isUpdate ? Trigger.oldMap.get(c.Id) : null;

        Boolean shouldSync = Trigger.isInsert;

        if (Trigger.isUpdate && oldRec != null) {
            shouldSync =
                c.Name != oldRec.Name ||
                c.Description__c != oldRec.Description__c ||
                c.Manual__c != oldRec.Manual__c ||
                c.Smart__c != oldRec.Smart__c;
        }

        if (shouldSync) {
            ShopifyCollectionGraphQLService.syncCollectionAsync(c.Id);
        }
    }
}