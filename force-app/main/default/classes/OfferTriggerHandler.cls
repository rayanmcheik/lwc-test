public with sharing class OfferTriggerHandler {
    public Boolean isDisabled() {
        return false;
    }

    public void beforeInsert() {
        OfferService.setOfferIdentifier((List<Offer__c>) Trigger.new, null);
    }

    public void beforeUpdate() {
        OfferService.setOfferIdentifier((List<Offer__c>) Trigger.new, (Map<Id, Offer__c>) Trigger.oldMap);
    }

}