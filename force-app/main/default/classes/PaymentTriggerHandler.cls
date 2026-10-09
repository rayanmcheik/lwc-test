public class PaymentTriggerHandler {

    public static void beforeInsert(List<Payment__c> newPayments) {
        PaymentService.checkTotalPaid(newPayments, null);
    }

    public static void beforeUpdate(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldMap
    ) {
        PaymentService.checkTotalPaid(newPayments, oldMap);
    }

    public static void beforeDelete(List<Payment__c> oldPayments) {
        PaymentService.preventPaidDeletion(oldPayments);
    }

    public static void afterInsert(List<Payment__c> newPayments) {
        PaymentService.updateTotalPaid(newPayments, null);
    }

    public static void afterUpdate(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldMap
    ) {
        PaymentService.updateTotalPaid(newPayments, oldMap);
    }

    public static void afterDelete(List<Payment__c> oldPayments) {
        PaymentService.updateTotalPaid(oldPayments, null);
    }

    public static void afterUndelete(List<Payment__c> newPayments) {
        PaymentService.updateTotalPaid(newPayments, null);
    }
}