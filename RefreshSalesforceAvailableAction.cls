public with sharing class RefreshSalesforceAvailableAction {

    public class Request {
        @InvocableVariable(
            label='Confirm Inventory Refresh'
            required=true
        )
        public Boolean confirmed;
    }

    public class Result {
        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public Integer recordsUpdated;

        @InvocableVariable
        public Integer recordsFailed;

        @InvocableVariable
        public String message;
    }

    @InvocableMethod(
        label='Refresh Salesforce Available from Shopify'
        description='Copies Shopify Available into Salesforce Available for eligible inventory records.'
    )
    public static List<Result> refreshInventory(
        List<Request> requests
    ) {
        Result result = new Result();
        List<Result> results = new List<Result>();

        result.success = false;
        result.recordsUpdated = 0;
        result.recordsFailed = 0;

        results.add(result);

        if (
            requests == null ||
            requests.isEmpty() ||
            requests[0].confirmed != true
        ) {
            result.message = 'Inventory refresh was not confirmed.';
            return results;
        }

        try {
            List<Inventory__c> inventoryRecords = [
                SELECT Id,
                       Available__c,
                       Salesforce_Available__c
                FROM Inventory__c
                WHERE Available__c != null
            ];

            List<Inventory__c> recordsToUpdate =
                new List<Inventory__c>();

            for (Inventory__c inv : inventoryRecords) {
                if (
                    inv.Salesforce_Available__c != inv.Available__c
                ) {
                    recordsToUpdate.add(
                        new Inventory__c(
                            Id = inv.Id,
                            Salesforce_Available__c = inv.Available__c
                        )
                    );
                }
            }

            if (recordsToUpdate.isEmpty()) {
                result.success = true;
                result.message =
                    'Refresh completed. No inventory quantities needed updating.';
                return results;
            }

            Boolean previousSkipOutbound =
                InventorySyncControl.skipOutbound;

            try {
                InventorySyncControl.skipOutbound = true;

                Database.SaveResult[] saveResults =
                    Database.update(recordsToUpdate, false);

                for (Integer i = 0; i < saveResults.size(); i++) {
                    if (saveResults[i].isSuccess()) {
                        result.recordsUpdated++;
                    } else {
                        result.recordsFailed++;

                        if (result.recordsFailed <= 5) {
                            for (
                                Database.Error err :
                                saveResults[i].getErrors()
                            ) {
                                result.message =
                                    (result.message == null
                                        ? ''
                                        : result.message + ' ') +
                                    'Record ' +
                                    recordsToUpdate[i].Id +
                                    ': ' + err.getMessage();
                            }
                        }
                    }
                }
            } finally {
                InventorySyncControl.skipOutbound =
                    previousSkipOutbound;
            }

            result.success = result.recordsFailed == 0;

            if (result.success) {
                result.message =
                    'Inventory refresh completed successfully.';
            } else {
                result.message =
                    'Refresh completed with some errors. Review the reported failures.';
            }

        } catch (Exception e) {
            result.success = false;
            result.message =
                'Inventory refresh failed: ' + e.getMessage();
        }

        return results;
    }
}