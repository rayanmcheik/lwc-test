public class OfferService {

    public static void setOfferIdentifier(List<Offer__c> newList, Map<Id, Offer__c> oldMap) {
        Set<Id> opportunityIds = new Set<Id>();

        for (Offer__c offer : newList) {

            if (oldMap == null ) {
                if (offer.Opportunity__c != null) {
                    opportunityIds.add(offer.Opportunity__c);
                }
            }

            else if (offer.Opportunity__c != oldMap.get(offer.Id).Opportunity__c) {
                if (offer.Opportunity__c != null) {
                    opportunityIds.add(offer.Opportunity__c);
                }
            }
        }

        if (opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> opportunitiesMap =
            new Map<Id, Opportunity>([
                SELECT Id, Identifier__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]);

        Map<Id, Integer> offerCountByOpportunity =
            new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT Opportunity__c opportunityId,
                   COUNT(Id) offerCount
            FROM Offer__c
            WHERE Opportunity__c IN :opportunityIds
            GROUP BY Opportunity__c
        ]) {

            offerCountByOpportunity.put(
                (Id) ar.get('opportunityId'),
                (Integer) ar.get('offerCount')
            );
        }

        for (Offer__c offer : newList) {

            Boolean shouldSetIdentifier =
                oldMap == null ||
                offer.Opportunity__c !=
                oldMap.get(offer.Id).Opportunity__c;

            if (shouldSetIdentifier && offer.Opportunity__c != null) {

                Opportunity opp = opportunitiesMap.get(offer.Opportunity__c);

                Integer offerNumber =offerCountByOpportunity.containsKey(offer.Opportunity__c) ? offerCountByOpportunity.get(offer.Opportunity__c): 0;
                offer.Identifier__c =
                    opp.Identifier__c +
                    '-' +
                    String.valueOf(offerNumber).leftPad(3, '0');
                offerCountByOpportunity.put(
                    offer.Opportunity__c,
                    offerNumber + 1
                );
            }
        }
    }
}