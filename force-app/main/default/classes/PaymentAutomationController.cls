global with sharing class PaymentAutomationController {
    global class BookingInput {
        @InvocableVariable(required=true label='Booking ID')
        global Id bookingId;
    }

    @InvocableMethod(label='Recalculate Booking Total Paid')
    global static void syncTotalPaid(List<BookingInput> inputs) {
        Set<Id> bookingIds = new Set<Id>();
        if (inputs != null) {
            for (BookingInput input : inputs) {
                if (input != null && input.bookingId != null) bookingIds.add(input.bookingId);
            }
        }
        if (bookingIds.isEmpty()) return;
        Map<Id,Decimal> totals = new Map<Id,Decimal>();
        for (AggregateResult ar : [
            SELECT Booking__c bookingId, SUM(Amount__c) totalAmount
            FROM Payment__c
            WHERE Booking__c IN :bookingIds AND Status__c = 'Completed'
            GROUP BY Booking__c
        ]) totals.put((Id)ar.get('bookingId'), (Decimal)ar.get('totalAmount'));

        List<Opportunity> updates = new List<Opportunity>();
        for (Id bookingId : bookingIds) {
            Decimal amount = totals.containsKey(bookingId) ? totals.get(bookingId) : 0;
            updates.add(new Opportunity(
                Id = bookingId,
                Total_Paid__c = amount.setScale(0),
                Total_Paid_Amount__c = amount
            ));
        }
        if (!updates.isEmpty()) update updates;
    }
}
