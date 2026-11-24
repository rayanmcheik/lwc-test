
public with sharing class VGTSInstallmentPaymentHandler {

    private static Boolean isProcessing = false;

    public static void processPayments(
        List<Payment__c> newPayments,
        List<Payment__c> oldPayments
    ) {

        if (isProcessing) return;

        isProcessing = true;

        try {

            Set<Id> installmentIds = new Set<Id>();

            if (newPayments != null) {
                for (Payment__c p : newPayments) {
                    if (p.Installment__c != null) {
                        installmentIds.add(p.Installment__c);
                    }
                }
            }

            if (oldPayments != null) {
                for (Payment__c p : oldPayments) {
                    if (p.Installment__c != null) {
                        installmentIds.add(p.Installment__c);
                    }
                }
            }

            if (installmentIds.isEmpty()) return;

            Map<Id, Installment__c> installments =
                new Map<Id, Installment__c>([
                    SELECT Id, Booking__c,
                           Installment_Number__c,
                           Amount__c, Paid_Amount__c,
                           Status__c
                    FROM Installment__c
                    WHERE Id IN :installmentIds
                    FOR UPDATE
                ]);

            Map<Id, Decimal> paidAmounts =
                new Map<Id, Decimal>();

            for (AggregateResult ar : [
                SELECT Installment__c installmentId,
                       SUM(Amount__c) totalPaid
                FROM Payment__c
                WHERE Installment__c IN :installmentIds
                AND Status__c = 'Completed'
                GROUP BY Installment__c
            ]) {

                paidAmounts.put(
                    (Id) ar.get('installmentId'),
                    (Decimal) ar.get('totalPaid')
                );
            }

            List<Installment__c> updates =
                new List<Installment__c>();

            Set<Id> bookingIds = new Set<Id>();

            for (Installment__c installment : installments.values()) {

                Decimal paid = paidAmounts.containsKey(installment.Id)
                    ? paidAmounts.get(installment.Id)
                    : 0;

                Decimal amount = installment.Amount__c == null
                    ? 0
                    : installment.Amount__c;

                String status;

                if (paid <= 0) {
                    status = 'Pending';
                } else if (paid < amount) {
                    status = 'Partially Paid';
                } else {
                    status = 'Paid';
                }

                updates.add(new Installment__c(
                    Id = installment.Id,
                    Paid_Amount__c = paid,
                    Status__c = status
                ));

                if (installment.Installment_Number__c == 1 &&
                    installment.Booking__c != null) {

                    bookingIds.add(installment.Booking__c);
                }
            }

            if (!updates.isEmpty()) {
                update updates;
            }

            updateDepositTotals(bookingIds);

        } finally {
            isProcessing = false;
        }
    }

    private static void updateDepositTotals(Set<Id> bookingIds) {

        if (bookingIds == null || bookingIds.isEmpty()) return;

        Map<Id, Decimal> totals = new Map<Id, Decimal>();

        for (Id bookingId : bookingIds) {
            totals.put(bookingId, 0);
        }

        for (AggregateResult ar : [
            SELECT Booking__c bookingId,
                   SUM(Paid_Amount__c) totalPaid
            FROM Installment__c
            WHERE Booking__c IN :bookingIds
            AND Installment_Number__c = 1
            GROUP BY Booking__c
        ]) {

            totals.put(
                (Id) ar.get('bookingId'),
                (Decimal) ar.get('totalPaid')
            );
        }

        List<Opportunity> updates = new List<Opportunity>();

        for (Id bookingId : bookingIds) {

            updates.add(new Opportunity(
                Id = bookingId,
                Deposit_Received_Amount__c = totals.get(bookingId)
            ));
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }
}

