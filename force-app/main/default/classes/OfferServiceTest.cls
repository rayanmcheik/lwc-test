@isTest
private class OfferServiceTest {

    @testSetup
    static void setupTestData() {
        // Create parent Opportunity records
        List<Opportunity> oppsToInsert = new List<Opportunity>();
        
        oppsToInsert.add(new Opportunity(
            Name = 'Test Opp 1',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Identifier__c = 'OPP-100'
        ));
        
        oppsToInsert.add(new Opportunity(
            Name = 'Test Opp 2',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Identifier__c = 'OPP-200'
        ));
        
        insert oppsToInsert;

        // Create an existing Offer under Opp 1 to test the AggregateResult count logic
        Offer__c existingOffer = new Offer__c(
            Opportunity__c = oppsToInsert[0].Id
            // If Identifier__c is populated by a trigger using this service, 
            // it will be set automatically here.
        );
        insert existingOffer;
    }

    @isTest
    static void testInsertOffersWithOpportunity() {
        // Retrieve the generated Opportunity from setup
        Opportunity opp1 = [SELECT Id, Identifier__c FROM Opportunity WHERE Identifier__c = 'OPP-100' LIMIT 1];
        
        // Prepare a new list of offers mimicking a trigger 'newList' on insert (oldMap is null)
        List<Offer__c> newOffers = new List<Offer__c>{
            new Offer__c(Opportunity__c = opp1.Id),
            new Offer__c(Opportunity__c = opp1.Id)
        };
        
        Test.startTest();
        // Invoke the service method manually simulating an insert trigger context (oldMap = null)
        OfferService.setOfferIdentifier(newOffers, null);
        Test.stopTest();
        
        // Assertions: 
        // Opp 1 already had 1 existing offer (count = 1), so the first new offer should pad '001'
        // The second offer in the loop increments the map, so it should pad '002'
        System.assertEquals('OPP-100-001', newOffers[0].Identifier__c, 'The first new offer identifier did not match expected count.');
        System.assertEquals('OPP-100-002', newOffers[1].Identifier__c, 'The second new offer identifier did not match expected sequential increment.');
    }

    @isTest
    static void testUpdateOfferOpportunityChanged() {
        // Retrieve test Opportunities
        Opportunity opp1 = [SELECT Id FROM Opportunity WHERE Identifier__c = 'OPP-100' LIMIT 1];
        Opportunity opp2 = [SELECT Id, Identifier__c FROM Opportunity WHERE Identifier__c = 'OPP-200' LIMIT 1];
        
        // Get the existing offer currently assigned to Opp 1
        Offer__c targetOffer = [SELECT Id, Opportunity__c, Identifier__c FROM Offer__c WHERE Opportunity__c = :opp1.Id LIMIT 1];
        
        // Clone the record to represent the old state map
        Map<Id, Offer__c> oldMap = new Map<Id, Offer__c>{ targetOffer.Id => targetOffer.clone(true, true, true, true) };
        
        // Modify the record to represent the new state (moving it from Opp 1 to Opp 2)
        targetOffer.Opportunity__c = opp2.Id;
        List<Offer__c> newList = new List<Offer__c>{ targetOffer };
        
        Test.startTest();
        // Invoke service simulating an update context
        OfferService.setOfferIdentifier(newList, oldMap);
        Test.stopTest();
        
        // Assertions:
        // Opp 2 has 0 existing offers, so the count variable starts at 0, resulting in '000'
        System.assertEquals('OPP-200-000', targetOffer.Identifier__c, 'The offer identifier failed to regenerate correctly upon changing the Opportunity lookup.');
    }

    @isTest
    static void testInsertOffersWithoutOpportunity() {
        // Verify code safety when Opportunity__c is left blank
        List<Offer__c> emptyOppOffers = new List<Offer__c>{
            new Offer__c(Opportunity__c = null)
        };
        
        Test.startTest();
        OfferService.setOfferIdentifier(emptyOppOffers, null);
        Test.stopTest();
        
        // Assertions: The collection processing should gracefully return early or skip the entry
        System.assertEquals(null, emptyOppOffers[0].Identifier__c, 'Identifier__c should remain null when no parent Opportunity is linked.');
    }
}