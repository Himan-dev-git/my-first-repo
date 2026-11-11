public class LeadTriggerHandler {
    public void beforeInsert(List<Lead> newLeads) {
        updateWebsiteForNewLeads(newLeads);
    }
    //public void beforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        // Implement your logic for before update
    //}
    //public void beforeDelete(Map<Id, Lead> oldMap) {
        // Implement your logic for before delete
    //}
    //public void afterInsert(List<Lead> newLeads) {
        // Implement your logic for after insert
    //}
    //public void afterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        // Implement your logic for after update
    //}
    //public void afterDelete(Map<Id, Lead> oldMap) {
        // Implement your logic for after delete
    //}
    //public void afterUndelete(List<Lead> newLeads) {
        // Implement your logic for after undelete
    //}
    private void updateWebsiteForNewLeads(List<Lead> newLeads) {
        for (Lead lead : newLeads) {
            if (String.isBlank(lead.Company)) {
                lead.Company = 'www.testwebsite.com';
            }
        }
    }
}