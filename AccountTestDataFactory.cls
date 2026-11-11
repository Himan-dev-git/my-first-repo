@isTest
public class AccountTestDataFactory {

    // Overloaded method to create a single test Person Account (calls the multiple account method with 1)
    public static Account createTestAccount() {
        return createTestAccounts(1)[0];
    }

    // Overloaded method to create multiple test Person Accounts with variations
    public static List<Account> createTestAccounts(Integer numberOfAccounts) {
        List<Account> testAccounts = new List<Account>();

        // Retrieve the RecordTypeId using a describe call
        Id personAccountRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();

        for (Integer i = 1; i <= numberOfAccounts; i++) {
            Account personAccount = new Account();
            personAccount.RecordTypeId = personAccountRecordTypeId;
            personAccount.PersonEmail = 'test.email+' + i + '@example.com';
            personAccount.LastName = 'TestUser' + i;
            personAccount.ShippingStreet = '100 Maple Street, Baker\'s Lane Apt ' + i;
            personAccount.ShippingCity = 'Greenwich';
            personAccount.ShippingState = 'London';
            personAccount.ShippingPostalCode = 'SE10 9NN';
            personAccount.ShippingCountry = 'UK';
            testAccounts.add(personAccount);
        }

        return testAccounts;
    }
}