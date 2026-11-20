
public with sharing class VGTSInstallmentPaymentHandler {

    private static Boolean isProcessing = false;

    // =====================================================
    // AFTER INSERT / UPDATE / DELETE / UNDELETE
    // =====================================================

    public static void processPayments(
        List<Payment__c> newPayments,
        List<Payment__c> oldPayments
    ) {

        if (isProcessing) return;

        isProcessing = true;

        try {

            Set<Id> installmentIds = new Set<Id>();

            // New or updated payments.
            if (newPayments != null) {
                for (Payment__c payment : newPayments) {

                    if (payment.Installment__c != null) {
                        installmentIds.add(payment.Installment__c);
                    }
                }
            }

            // Old relationships are also required when a payment
            // is moved to another installment or deleted.
            if (oldPayments != null) {
                for (Payment__c payment : oldPayments) {

                    if (payment.Installment__c != null) {
                        installmentIds.add(payment.Installment__c);
                    }
                }
            }

            if (installmentIds.isEmpty()) return;

            // Retrieve the affected installments.
            Map<Id, Installment__c> installments =
                new Map<Id, Installment__c>([
                    SELECT Id,
                           Booking__c,
                           Installment_Number__c,
                           Amount__c,
                           Paid_Amount__c,
                           Status__c
                    FROM Installment__c
                    WHERE Id IN :installmentIds
                ]);

            // Calculate actual completed payments.
            Map<Id, Decimal> paidAmounts =
                new Map<Id, Decimal>();

            for (AggregateResult result : [
                SELECT Installment__c installmentId,
                       SUM(Amount__c) totalPaid
                FROM Payment__c
                WHERE Installment__c IN :installmentIds
                AND Status__c = 'Completed'
                GROUP BY Installment__c
            ]) {

                paidAmounts.put(
                    (Id)result.get('installmentId'),
                    (Decimal)result.get('totalPaid')
                );
            }

            List<Installment__c> updates =
                new List<Installment__c>();

            Set<Id> depositBookingIds = new Set<Id>();

            for (Installment__c installment : installments.values()) {

                Decimal paid = paidAmounts.containsKey(installment.Id)
                    ? paidAmounts.get(installment.Id)
                    : 0;

                Decimal amount = installment.Amount__c == null
                    ? 0
                    : installment.Amount__c;

                String newStatus;

                if (paid <= 0) {
                    newStatus = 'Pending';
                } else if (paid < amount) {
                    newStatus = 'Partially Paid';
                } else {
                    newStatus = 'Paid';
                }

                updates.add(new Installment__c(
                    Id = installment.Id,
                    Paid_Amount__c = paid,
                    Status__c = newStatus
                ));

                // Only a fully paid deposit creates the remaining schedule.
                if (installment.Installment_Number__c == 1 &&
                    newStatus == 'Paid' &&
                    installment.Booking__c != null) {

                    depositBookingIds.add(installment.Booking__c);
                }
            }

            if (!updates.isEmpty()) {
                update updates;
            }

            // Generate installments 2 and 3 after the deposit is fully paid.
            if (!depositBookingIds.isEmpty()) {
                VGTSInstallmentController.createRemainingInstallments(
                    depositBookingIds
                );
            }

            // Update total deposit received on the Booking.
            updateDepositTotals(installments.values(), paidAmounts);

        } finally {
            isProcessing = false;
        }
    }

    // =====================================================
    // UPDATE BOOKING DEPOSIT TOTAL
    // =====================================================

    private static void updateDepositTotals(
        List<Installment__c> installments,
        Map<Id, Decimal> paidAmounts
    ) {

        Set<Id> bookingIds = new Set<Id>();

        for (Installment__c installment : installments) {

            if (installment.Booking__c != null &&
                installment.Installment_Number__c == 1) {

                bookingIds.add(installment.Booking__c);
            }
        }

        if (bookingIds.isEmpty()) return;

        Map<Id, Decimal> depositTotals =
            new Map<Id, Decimal>();

        for (AggregateResult result : [
            SELECT Booking__c bookingId,
                   SUM(Paid_Amount__c) totalPaid
            FROM Installment__c
            WHERE Booking__c IN :bookingIds
            AND Installment_Number__c = 1
            GROUP BY Booking__c
        ]) {

            depositTotals.put(
                (Id)result.get('bookingId'),
                (Decimal)result.get('totalPaid')
            );
        }

        List<Opportunity> bookingUpdates =
            new List<Opportunity>();

        for (Id bookingId : bookingIds) {

            bookingUpdates.add(new Opportunity(
                Id = bookingId,
                Deposit_Received_Amount__c =
                    depositTotals.containsKey(bookingId)
                        ? depositTotals.get(bookingId)
                        : 0
            ));
        }

        if (!bookingUpdates.isEmpty()) {
            update bookingUpdates;
        }
    }
}

