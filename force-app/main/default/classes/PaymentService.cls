public class PaymentService {

    public static void preventPaidDeletion(
        List<Payment__c> payments
    ) {

        for (Payment__c payment : payments) {

            if (payment.Status__c == 'Paid') {
                payment.addError(
                    'A paid payment cannot be deleted.'
                );
            }
        }
    }


    public static void checkTotalPaid(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldMap
    ) {

        Set<Id> opportunityIds = new Set<Id>();

        for (Payment__c payment : newPayments) {

            if (payment.Opportunity__c != null) {
                opportunityIds.add(payment.Opportunity__c);
            }

            if (oldMap != null && oldMap.containsKey(payment.Id)) {

                Payment__c oldPayment =
                    oldMap.get(payment.Id);

                if (oldPayment.Opportunity__c != null) {
                    opportunityIds.add(
                        oldPayment.Opportunity__c
                    );
                }
            }
        }

        if (opportunityIds.isEmpty()) {
            return;
        }


        Map<Id, Decimal> paidTotals =
            new Map<Id, Decimal>();

        for (AggregateResult result : [
            SELECT Opportunity__c opportunityId,
                   SUM(Amount__c) totalPaid
            FROM Payment__c
            WHERE Opportunity__c IN :opportunityIds
            AND Status__c = 'Paid'
            GROUP BY Opportunity__c
        ]) {

            paidTotals.put(
                (Id) result.get('opportunityId'),
                (Decimal) result.get('totalPaid')
            );
        }


        for (Payment__c payment : newPayments) {

            Payment__c oldPayment;

            if (
                oldMap != null &&
                oldMap.containsKey(payment.Id)
            ) {
                oldPayment = oldMap.get(payment.Id);
            }


            if (
                oldPayment != null &&
                oldPayment.Status__c == 'Paid' &&
                oldPayment.Opportunity__c != null
            ) {

                Decimal currentTotal =
                    paidTotals.containsKey(
                        oldPayment.Opportunity__c
                    )
                    ? paidTotals.get(
                        oldPayment.Opportunity__c
                    )
                    : 0;

                paidTotals.put(
                    oldPayment.Opportunity__c,
                    currentTotal -
                    (oldPayment.Amount__c == null
                        ? 0
                        : oldPayment.Amount__c)
                );
            }


            if (
                payment.Status__c == 'Paid' &&
                payment.Opportunity__c != null
            ) {

                Decimal currentTotal =
                    paidTotals.containsKey(
                        payment.Opportunity__c
                    )
                    ? paidTotals.get(
                        payment.Opportunity__c
                    )
                    : 0;

                paidTotals.put(
                    payment.Opportunity__c,
                    currentTotal +
                    (payment.Amount__c == null
                        ? 0
                        : payment.Amount__c)
                );
            }
        }


        Map<Id, Opportunity> opportunities =
            new Map<Id, Opportunity>([
                SELECT Id, Amount
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]);


        for (Payment__c payment : newPayments) {

            if (
                payment.Opportunity__c == null ||
                !opportunities.containsKey(
                    payment.Opportunity__c
                )
            ) {
                continue;
            }

            Opportunity opp =
                opportunities.get(
                    payment.Opportunity__c
                );

            Decimal total =
                paidTotals.containsKey(
                    payment.Opportunity__c
                )
                ? paidTotals.get(
                    payment.Opportunity__c
                )
                : 0;

            if (
                opp.Amount != null &&
                total > opp.Amount
            ) {

                payment.addError(
                    'Total paid cannot exceed the Opportunity amount.'
                );
            }
        }
    }


    public static void updateTotalPaid(
        List<Payment__c> payments,
        Map<Id, Payment__c> oldMap
    ) {

        Set<Id> opportunityIds = new Set<Id>();


        for (Payment__c payment : payments) {


            if (payment.Opportunity__c != null) {
                opportunityIds.add(
                    payment.Opportunity__c
                );
            }


            if (
                oldMap != null &&
                oldMap.containsKey(payment.Id)
            ) {

                Payment__c oldPayment =
                    oldMap.get(payment.Id);

                if (oldPayment.Opportunity__c != null) {
                    opportunityIds.add(
                        oldPayment.Opportunity__c
                    );
                }
            }
        }


        if (opportunityIds.isEmpty()) {
            return;
        }


        Map<Id, Decimal> paidTotals =
            new Map<Id, Decimal>();

        for (AggregateResult result : [
            SELECT Opportunity__c opportunityId,
                   SUM(Amount__c) totalPaid
            FROM Payment__c
            WHERE Opportunity__c IN :opportunityIds
            AND Status__c = 'Paid'
            GROUP BY Opportunity__c
        ]) {

            paidTotals.put(
                (Id) result.get('opportunityId'),
                (Decimal) result.get('totalPaid')
            );
        }



        List<Opportunity> opportunitiesToUpdate =
            new List<Opportunity>();

        for (Id opportunityId : opportunityIds) {

            Decimal totalPaid =
                paidTotals.containsKey(opportunityId)
                ? paidTotals.get(opportunityId)
                : 0;

            opportunitiesToUpdate.add(
                new Opportunity(
                    Id = opportunityId,
                    Total_Paid__c = totalPaid
                )
            );
        }


        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
    }
}