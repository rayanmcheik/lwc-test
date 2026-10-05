public with sharing class ContactTriggerHandler extends TriggerHandler implements ITriggerHandler{

    private Map<Id, Contact> newMap;
    private Map<Id, Contact> oldMap;
    private List<Contact> TriggerNew;
    private List<Contact> TriggerOld;
    
    public ContactTriggerHandler(){
        this.newMap = (Map<Id, Contact>) Trigger.newMap;
        this.oldMap = (Map<Id, Contact>) Trigger.oldMap;
        this.TriggerNew= (List<Contact>) Trigger.New;
        this.TriggerOld= (List<Contact>) Trigger.Old;
    }
    
    
    //Use this variable to disable this trigger from transaction
    public static Boolean TriggerDisabled = false;
    
    //check if the trigger is disabled from transaction
    public Boolean isDisabled(){
        return TriggerDisabled;
    }
    
    public override void beforeInsert() {

    }
    public override void afterInsert() {
        CountAccountContactHandler.updateAccount(oldMap, TriggerNew);
    }
    public  override void beforeUpdate() {
        
    }
    public override void afterUpdate() {
        CountAccountContactHandler.updateAccount(oldMap, TriggerNew);
    }
    
    public override void beforeDelete() {
        
    }
    
    public override void afterDelete() {
        
    }
    
    public override void afterUnDelete() {
        
    }
}