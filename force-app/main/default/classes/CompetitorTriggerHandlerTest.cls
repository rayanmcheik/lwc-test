@isTest
private class CompetitorTriggerHandlerTest {

    @testSetup
    static void setupTestData() {
        // Create baseline Accounts
        Account acc1 = new Account(Name = 'Test Account 1');
        Account acc2 = new Account(Name = 'Test Account 2');
        insert new List<Account>{acc1, acc2};

        // Create an Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc1.Id
        );
        insert opp;

        // Create a Quote linked to the Opportunity
        Quote q = new Quote(
            Name = 'Test Quote',
            OpportunityId = opp.Id
        );
        insert q;
    }

    @isTest
    static void testCheckCompetitorLinks_InsertDuplicateQuoteLink() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 1' LIMIT 1];
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        // Insert first competitor linked to the quote
        Competitor__c comp1 = new Competitor__c(Account__c = acc.Id, Quote__c = q.Id);
        insert comp1;

        // Attempting to insert a second competitor linked to the same account and a quote should fail
        Competitor__c comp2 = new Competitor__c(Account__c = acc.Id, Quote__c = q.Id);
        
        Test.startTest();
        Database.SaveResult result = Database.insert(comp2, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'The insertion should have failed due to duplicate links.');
        System.assertEquals('This account is already related to a quote through a competitor', result.getErrors()[0].getMessage());
    }

    @isTest
    static void testCheckCompetitorLinks_InsertDuplicateOppLink() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 1' LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // Insert first competitor linked to the opportunity
        Competitor__c comp1 = new Competitor__c(Account__c = acc.Id, Opportunity__c = opp.Id);
        insert comp1;

        // Attempting to insert a second competitor linked to the same account and an opportunity should fail
        Competitor__c comp2 = new Competitor__c(Account__c = acc.Id, Opportunity__c = opp.Id);
        
        Test.startTest();
        Database.SaveResult result = Database.insert(comp2, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'The insertion should have failed due to duplicate links.');
        System.assertEquals('This account is already related to an opportunity through a competitor', result.getErrors()[0].getMessage());
    }

    @isTest
    static void testCheckCompetitorLinks_UpdateToDuplicate() {
        Account acc1 = [SELECT Id FROM Account WHERE Name = 'Test Account 1' LIMIT 1];
        Account acc2 = [SELECT Id FROM Account WHERE Name = 'Test Account 2' LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // comp1 occupies acc1 + Opp combo
        Competitor__c comp1 = new Competitor__c(Account__c = acc1.Id, Opportunity__c = opp.Id);
        insert comp1;

        // comp2 is safe initially on acc2
        Competitor__c comp2 = new Competitor__c(Account__c = acc2.Id, Opportunity__c = opp.Id);
        insert comp2;

        // Update comp2 to target acc1, which should throw a validation error
        comp2.Account__c = acc1.Id;

        Test.startTest();
        Database.SaveResult result = Database.update(comp2, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'The update should have failed.');
        System.assertEquals('This account is already related to an opportunity through a competitor', result.getErrors()[0].getMessage());
    }

    @isTest
    static void testAddCompetitorToOpportunity_Success() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 2' LIMIT 1]; // Use clean account to prevent link validation errors
        Quote q = [SELECT Id, OpportunityId FROM Quote LIMIT 1];

        // Inserting a competitor linked to a Quote should automatically create one for its Opportunity
        Competitor__c comp = new Competitor__c(Account__c = acc.Id, Quote__c = q.Id);

        Test.startTest();
        insert comp;
        Test.stopTest();

        // Verify that a secondary competitor record was created automatically for the Opportunity
        List<Competitor__c> opportunityCompetitors = [
            SELECT Id, Account__c, Opportunity__c 
            FROM Competitor__c 
            WHERE Opportunity__c = :q.OpportunityId AND Account__c = :acc.Id
        ];
        
        System.assertEquals(1, opportunityCompetitors.size(), 'A shadow competitor record should have been auto-inserted for the Opportunity.');
    }
}
