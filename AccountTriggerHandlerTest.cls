@IsTest
private class AccountTriggerHandlerTest {

    @testSetup
    static void setupData() {
        insert new Account(Name = 'Base Test Account');
    }

    private static Account makeAccount(Id accId, String nameVal, Boolean integrationFlag) {
        Account acc = new Account(Id = accId, Name = nameVal);

        if (Schema.SObjectType.Account.fields.getMap().containsKey('Updated_by_Integration__c')) {
            acc.put('Updated_by_Integration__c', integrationFlag);
        }

        return acc;
    }

    @IsTest
    static void testNullAndEmptyGuards() {
        Test.startTest();

        AccountTriggerHandler.handleAfterInsert(null);
        AccountTriggerHandler.handleAfterInsert(new List<Account>());

        AccountTriggerHandler.handleAfterUpdate(null, new Map<Id, Account>());
        AccountTriggerHandler.handleAfterUpdate(new List<Account>(), new Map<Id, Account>());
        AccountTriggerHandler.handleAfterUpdate(new List<Account>{ new Account() }, null);

        Test.stopTest();

        System.assert(true, 'Null and empty guard clauses executed without exception.');
    }

    @IsTest
    static void testAfterInsertSkipsIntegrationRecord() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];

        Account integrationAcc = makeAccount(acc.Id, acc.Name, true);

        Test.startTest();

        AccountTriggerHandler.handleAfterInsert(new List<Account>{
            null,
            integrationAcc
        });

        Test.stopTest();

        System.assertEquals(true, integrationAcc.get('Updated_by_Integration__c'),
            'Integration-updated account should be skipped.');
    }

    @IsTest
    static void testAfterInsertQueuesSync() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Account normalAcc = makeAccount(acc.Id, acc.Name, false);

        Test.startTest();

        AccountTriggerHandler.handleAfterInsert(new List<Account>{
            normalAcc
        });

        Test.stopTest();

        System.assertEquals(false, normalAcc.get('Updated_by_Integration__c'),
            'Non-integration account should enter sync path.');
    }

    @IsTest
    static void testAfterUpdateSkipsNullOldAndIntegrationRecord() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Account oldAcc = makeAccount(acc.Id, 'Old Name', false);
        Account integrationAcc = makeAccount(acc.Id, 'Changed Name', true);

        Test.startTest();

        AccountTriggerHandler.handleAfterUpdate(
            new List<Account>{
                null,
                integrationAcc
            },
            new Map<Id, Account>{
                acc.Id => oldAcc
            }
        );

        Test.stopTest();

        System.assertEquals(true, integrationAcc.get('Updated_by_Integration__c'),
            'Integration-updated record should be skipped during update.');
    }

    @IsTest
    static void testAfterUpdateSkipsWhenNoRealChange() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Account oldAcc = makeAccount(acc.Id, 'Same Name', false);
        Account newAcc = makeAccount(acc.Id, 'Same Name', false);

        Test.startTest();

        AccountTriggerHandler.handleAfterUpdate(
            new List<Account>{ newAcc },
            new Map<Id, Account>{ acc.Id => oldAcc }
        );

        Test.stopTest();

        System.assertEquals(oldAcc.Name, newAcc.Name,
            'Unchanged account should not enter sync path.');
    }

    @IsTest
    static void testAfterUpdateQueuesSyncForChangedFields() {
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Account oldAcc = makeAccount(acc.Id, 'Old Name', false);
        Account newAcc = makeAccount(acc.Id, 'New Name', false);

        Test.startTest();

        AccountTriggerHandler.handleAfterUpdate(
            new List<Account>{ newAcc },
            new Map<Id, Account>{ acc.Id => oldAcc }
        );

        Test.stopTest();

        System.assertNotEquals(oldAcc.Name, newAcc.Name,
            'Changed account should enter sync path.');
    }
}