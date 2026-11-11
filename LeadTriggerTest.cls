@isTest
public class LeadTriggerTest {
    @isTest
    public static void testBeforeInsert() {
        
        Lead lead = new Lead();
        lead.LastName = 'Doe';
        //lead.Company = 'www.testwebsite.com';
        Test.startTest();
        insert lead;
        Test.stopTest();
        
        Lead newLead = [SELECT Website, Company FROM Lead Limit 1];
        
        // Checking if the company field is blank and the website field is updated

        System.assertEquals('www.testwebsite.com', newLead.Company, 'Website should be updated in before insert');
    }
}