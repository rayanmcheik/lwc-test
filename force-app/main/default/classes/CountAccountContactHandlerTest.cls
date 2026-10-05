@isTest
private class CountAccountContactHandlerTest {

    @isTest
    static void testUpdateAccountWithNewList() {
        // 1. Setup Test Data
        Account testAcc = new Account(Name = 'Test Account');
        insert testAcc;

        // Create Contacts that will match the subquery filter (LastName = 'Smith' or FirstName = null)
        List<Contact> testContacts = new List<Contact>();
        testContacts.add(new Contact(FirstName = 'John', LastName = 'Smith', AccountId = testAcc.Id));
        testContacts.add(new Contact(FirstName = null, LastName = 'Doe', AccountId = testAcc.Id));
        insert testContacts;

        // 2. Build parameters matching the new signature (Map, List)
        Map<Id, Contact> oldMap = null; // Mimicking an After Insert scenario

        // 3. Execute the target method using the correct signature
        Test.startTest();
        CountAccountContactHandler.updateAccount(oldMap, testContacts);
        Test.stopTest();

        // 4. Verify Results (Assert)
        Account updatedAcc = [SELECT Id, Matching_Contacts__c FROM Account WHERE Id = :testAcc.Id];
        
        // Both contacts created above match the subquery filter criteria
        Assert.areEqual(2, updatedAcc.Matching_Contacts__c, 'The Matching_Contacts__c should match the number of subqueried child contacts.');
    }

    @isTest
    static void testUpdateAccountWithBothMapsAndList() {
        // Test an update scenario where oldMap is provided along with the newList
        Account testAcc = new Account(Name = 'Second Test Account');
        insert testAcc;

        Contact testContact = new Contact(FirstName = 'Jane', LastName = 'Smith', AccountId = testAcc.Id);
        insert testContact;

        // Create oldMap representing the contact before an update
        Map<Id, Contact> oldMap = new Map<Id, Contact>{ testContact.Id => testContact.clone(true, true, true, true) };
        
        // Create the list representing the updated contact list
        List<Contact> newList = new List<Contact>{ testContact };

        Test.startTest();
        CountAccountContactHandler.updateAccount(oldMap, newList);
        Test.stopTest();

        Account updatedAcc = [SELECT Id, Matching_Contacts__c FROM Account WHERE Id = :testAcc.Id];
        Assert.isNotNull(updatedAcc.Matching_Contacts__c, 'The field should be populated.');
    }
}