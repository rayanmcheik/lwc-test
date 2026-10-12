public with sharing class QuoteController {

    @AuraEnabled(cacheable=true)
    public static String getLeaseType(Id opportunityId) {

        Opportunity opp = [
            SELECT Lease_Type__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        return opp.Lease_Type__c;
    }


    @AuraEnabled
    public static Id createQuote(Id opportunityId, Quote quoteRecord) {

        Opportunity opp = [
            SELECT Name
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        quoteRecord.OpportunityId = opportunityId;
        quoteRecord.Name = 'Quote - ' + opp.Name;

        insert quoteRecord;

        return quoteRecord.Id;
    }
}