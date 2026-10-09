trigger PaymentTrigger on Payment__c (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {

    if (Trigger.isBefore) {

        if (Trigger.isInsert) {
            PaymentTriggerHandler.beforeInsert(
                Trigger.new
            );
        }

        if (Trigger.isUpdate) {
            PaymentTriggerHandler.beforeUpdate(
                Trigger.new,
                Trigger.oldMap
            );
        }

        if (Trigger.isDelete) {
            PaymentTriggerHandler.beforeDelete(
                Trigger.old
            );
        }
    }


    if (Trigger.isAfter) {

        if (Trigger.isInsert) {
            PaymentTriggerHandler.afterInsert(
                Trigger.new
            );
        }

        if (Trigger.isUpdate) {
            PaymentTriggerHandler.afterUpdate(
                Trigger.new,
                Trigger.oldMap
            );
        }

        if (Trigger.isDelete) {
            PaymentTriggerHandler.afterDelete(
                Trigger.old
            );
        }

        if (Trigger.isUndelete) {
            PaymentTriggerHandler.afterUndelete(
                Trigger.new
            );
        }
    }
}