public with sharing class EX3 {
    public static void checkCompetitorLinks(List<Competitor__c> newList,Map<Id> oldMap,Map<Id,Competitor__c> newMap){
        Map<Id,List<Competitor__c>> accountIdsToCompetitorsForQuotesMap = new Map<Id,List<Competitor__c>>();
        Map<Id,List<Competitor__c>> accountIdsToCompetitorsForOppsMap = new List<Id,List<Competitor__c>>();


        Set<Id> quoteIDsToProcess = new Set<Id>();
        for(Competitor__c comp : newList){
            if((oldMap != null || oldMap.get(comp.Id).Quote__c != comp.Quote__c || oldMap.get(comp.Id).Account__c != comp.Account__c)&&(comp.quote__c !=null && comp.Account__c != null)){
                if(!accountIdsToCompetitorsForQuotesMap.containsKey(comp.Account__c)){
                    accountIdsToCompetitorsForQuotesMap.put(comp.Account__c,new List<Competitor__c>());
                }
                accountIdsToCompetitorsForQuotesMap.get(comp.Account__c).add(comp);
                quoteIDsToProcess.add(comp.Quote__c);



            }

            if((oldMap != null || oldMap.get(comp.Id).Opportunity__c != comp.Opportunity__c || oldMap.get(comp.Id).Account__c != comp.Account__c)&&(comp.Opportunity__c !=null && comp.Account__c != null)){
                if(!accountIdsToCompetitorsForOppsMap.containsKey(comp.Account__c)){
                    accountIdsToCompetitorsForOppsMap.put(comp.Account__c,new List<Competitor__c>());
                }
                accountIdsToCompetitorsForOppsMap.get(comp.Account__c).add(comp);
            }

        }

        if(!accountIdsToCompetitorsForQuotesMap.isEmpty()){
            for(Competitor__c comp : [SELECT Id,Account__c FROM Competitor__c WHERE Account__c IN :accountIdsToCompetitorsForQuotesMap.keySet() AND Quote__c != null]){
                if(newMap == null || !newMap.containsKey(comp.Id)){
                    for(Competitor__c incomingComp : accountIdsToCompetitorsForQuotesMap.get(comp.Account__c)){
                        incomingComp.addError('This account is already related to a quote through a competitor');
                    }
                }
            }
        }

        if(!accountIdsToCompetitorsForOppsMap.isEmpty()){
            for(Competitor__c comp : [SELECT Id,Account__c FROM Competitor__c WHERE Account__c IN :accountIdsToCompetitorsForOppsMap.keySet() AND Opportunity__c != null]){
                if(newMap == null || !newMap.containsKey(comp.Id)){
                    for(Competitor__c incomingComp : accountIdsToCompetitorsForOppsMap.get(comp.Account__c)){
                        incomingComp.addError('This account is already related to an opportunity through a competitor');
                    }
                }
            }
        }
        if(!quoteIDsToProcess.isEmpty()){
            mirrorCompetitorsToOpportunities(quoteIDsToProcess,accountIdsToCompetitorsForQuotesMap);
        }


    }
    private static void mirrorCompetitorsToOpportunities(Set<Id> quoteIds,Map<Id,List<Competitor__c>> accountIdsToQuotesMap){
Map<Id,Quote> quotesWithhOpps 
    }
}