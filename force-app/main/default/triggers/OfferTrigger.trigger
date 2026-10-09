trigger OfferTrigger on Offer__c (before insert, before update) {
    OfferTriggerHandler handler = new OfferTriggerHandler();
    if(Trigger.isBefore){
        if(Trigger.isInsert){
            handler.beforeInsert();
        }
        if(Trigger.isUpdate){
            handler.beforeUpdate();
        }
    }
}