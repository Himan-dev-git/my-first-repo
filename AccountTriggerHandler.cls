public class AccountTriggerHandler {

    public static void handleAfterInsert(List<Account> newAccounts) {
        if (newAccounts == null || newAccounts.isEmpty()) {
            return;
        }

        if (System.isFuture() || System.isBatch() || System.isQueueable()) {
            return;
        }

        Set<Id> accountIdsToSync = new Set<Id>();

        for (Account acc : newAccounts) {
            if (acc == null) continue;

            if ((Boolean)acc.get('Updated_by_Integration__c') == true) {
                continue;
            }

            accountIdsToSync.add(acc.Id);
        }

        if (!accountIdsToSync.isEmpty()) {
            ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>(accountIdsToSync));
        }
    }

    public static void handleAfterUpdate(List<Account> newAccounts, Map<Id, Account> oldAccountsMap) {
        if (newAccounts == null || newAccounts.isEmpty() || oldAccountsMap == null) {
            return;
        }

        if (System.isFuture() || System.isBatch() || System.isQueueable()) {
            return;
        }

        Set<Id> accountIdsToSync = new Set<Id>();

        for (Account newAcc : newAccounts) {
            if (newAcc == null) continue;

            Account oldAcc = oldAccountsMap.get(newAcc.Id);
            if (oldAcc == null) continue;

            if ((Boolean)newAcc.get('Updated_by_Integration__c') == true) {
                continue;
            }

            Map<String, String> changedFieldsMap = Utilities.getChangedFieldsMap(newAcc, oldAcc);

            changedFieldsMap.remove('Shop_ID__c');
            changedFieldsMap.remove('LastModifiedDate');
            changedFieldsMap.remove('SystemModstamp');
            changedFieldsMap.remove('LastModifiedById');

            if (!changedFieldsMap.isEmpty()) {
                accountIdsToSync.add(newAcc.Id);
            }
        }

        if (!accountIdsToSync.isEmpty()) {
            ShopifyCustomerGraphQLService.syncCustomersAsync(new List<Id>(accountIdsToSync));
        }
    }
}