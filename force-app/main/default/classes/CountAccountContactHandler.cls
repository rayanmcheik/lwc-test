public with sharing class CountAccountContactHandler {
    public static void updateAccount(Map<Id, Contact> oldMap, List<Contact> newList) {
        Set<Id> accountIds = new Set<Id>();

        for (Contact c : newList) {
            
            if (oldMap == null || oldMap.get(c.Id) == null || oldMap.get(c.Id).AccountId != c.AccountId) {
                if (c.AccountId != null) {
                    accountIds.add(c.AccountId);
                }
            }
        }
    
        
        List<Account> accountsToUpdate = [
            SELECT Id, (
                SELECT Id, AccountId, FirstName, LastName 
                FROM Contacts 
                WHERE FirstName = null OR LastName = 'Smith'
            )
            FROM Account
            WHERE Id IN :accountIds
        ];

        for (Account acc : accountsToUpdate) {
            acc.Matching_Contacts__c = acc.Contacts.size();
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
}