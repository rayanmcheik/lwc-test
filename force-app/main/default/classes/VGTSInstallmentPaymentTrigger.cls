
trigger VGTSInstallmentPaymentTrigger on Payment__c (
    after insert,
    after update,
    after delete,
    after undelete
) {

    if (Trigger.isDelete) {

        VGTSInstallmentPaymentHandler.processPayments(
            null,
            Trigger.old
        );

    } else if (Trigger.isInsert || Trigger.isUndelete) {

        VGTSInstallmentPaymentHandler.processPayments(
            Trigger.new,
            null
        );

    } else if (Trigger.isUpdate) {

        VGTSInstallmentPaymentHandler.processPayments(
            Trigger.new,
            Trigger.old
        );
    }
}

