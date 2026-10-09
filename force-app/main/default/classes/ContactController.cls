// ContactController.cls
public with sharing class ContactController {
    
    // cacheable=true is required if you want to use the method with an LWC @wire adapter
    @AuraEnabled(cacheable=true)
    public static List<Contact> getContactList() {
        try {
            // Querying standard Salesforce Contact fields
            return [
                SELECT Id, Name, Email, Phone 
                FROM Contact 
                WITH USER_MODE
                LIMIT 10
            ];
        } catch (Exception e) {
            // Throwing an AuraHandledException ensures the LWC catches a readable error message
            throw new AuraHandledException('Unable to retrieve contacts: ' + e.getMessage());
        }
    }
}