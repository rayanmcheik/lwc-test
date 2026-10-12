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
    public static Id createQuote(
        Id opportunityId,
        Date startDate,
        Date endDate,
        Integer paymentTerms,
        Integer gracePeriod,
        String retailCategory,
        Integer duration,
        Integer rentReviewFrequency
    ) {
        Opportunity opp = [
            SELECT Id, Name, Lease_Type__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        Quote q = new Quote();

        q.Name = 'Quote - ' + opp.Name;
        q.OpportunityId = opp.Id;
        q.Proposed_Start_Date__c = startDate;
        q.Proposed_End_Date__c = endDate;
        q.Payment_Terms__c = paymentTerms;

        if (opp.Lease_Type__c == 'Office' ||
            opp.Lease_Type__c == 'Retail') {
            q.Grace_Period__c = gracePeriod;
        }

        if (opp.Lease_Type__c == 'Retail') {
            q.Retail_Sales_Category__c = retailCategory;
        }

        if (opp.Lease_Type__c == 'Land') {
            q.Proposed_Duration__c = duration;
            q.Rent_Review_Frequency__c = rentReviewFrequency;

            if (startDate != null && duration != null) {
                q.Proposed_End_Date__c =
                    startDate.addYears(duration);
            }
        }

        insert q;

        return q.Id;
    }
}