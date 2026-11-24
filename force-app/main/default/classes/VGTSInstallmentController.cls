
public with sharing class VGTSInstallmentController {

    // =====================================================
    // PAYMENT CONFIGURATION
    // =====================================================

    private static final Decimal DEPOSIT_PERCENT = 25;
    private static final Decimal SECOND_PERCENT = 35;
    private static final Decimal FINAL_PERCENT = 40;

    // =====================================================
    // FLOW INPUT
    // =====================================================

    public class QuoteRequest {

        @InvocableVariable(
            label='Accepted Quote ID'
            required=true
        )
        public Id quoteId;
    }

    // =====================================================
    // FLOW ACTION: PROCESS ACCEPTED QUOTES
    // =====================================================

    
@InvocableMethod(
    label='Move Accepted VGTS Quote to Payment Stage'
    description='Moves an accepted and synchronized Quote Booking to Payment.'
)
public static void processAcceptedQuotes(
    List<QuoteRequest> requests
) {
    if (requests == null || requests.isEmpty()) {
        return;
    }

    Set<Id> quoteIds = new Set<Id>();

    for (QuoteRequest request : requests) {
        if (request != null && request.quoteId != null) {
            quoteIds.add(request.quoteId);
        }
    }

    if (quoteIds.isEmpty()) return;

    List<Quote> acceptedQuotes = [
        SELECT Id, OpportunityId, Status, IsSyncing
        FROM Quote
        WHERE Id IN :quoteIds
    ];

    Set<Id> bookingIds = new Set<Id>();

    for (Quote q : acceptedQuotes) {

        if (q.Status != 'Accepted' ||
            q.IsSyncing != true ||
            q.OpportunityId == null) {
            continue;
        }

        bookingIds.add(q.OpportunityId);
    }

    if (bookingIds.isEmpty()) return;

    List<Opportunity> updates = new List<Opportunity>();

    for (Opportunity booking : [
        SELECT Id, StageName, Quote_Accepted_At__c,
               Ticket_Issuance_Hold__c
        FROM Opportunity
        WHERE Id IN :bookingIds
        FOR UPDATE
    ]) {

        if (booking.StageName == 'Cancelled' ||
            booking.StageName == 'Confirmed') {
            continue;
        }

        booking.StageName = 'Payment';

        if (booking.Quote_Accepted_At__c == null) {
            booking.Quote_Accepted_At__c = System.now();
        }

        booking.Ticket_Issuance_Hold__c = true;

        updates.add(booking);
    }

    if (!updates.isEmpty()) {
        update updates;
    }
}




    // =====================================================
    // CREATE INSTALLMENTS 2 AND 3
    // CALLED AFTER THE DEPOSIT IS COMPLETED
    // =====================================================

    public static void createRemainingInstallments(
        Set<Id> bookingIds
    ) {

        if (bookingIds == null || bookingIds.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> bookings = new Map<Id, Opportunity>([
            SELECT Id, Name, Departure_Date__c,
                   Return_Date__c,
                   Installment_Scheduled_Created__c
            FROM Opportunity
            WHERE Id IN :bookingIds
            FOR UPDATE
        ]);

        Map<Id, Decimal> totals =
            calculatePackageTotals(bookingIds);

        // Confirm that the deposit is actually fully paid.
        Map<Id, Installment__c> deposits =
            new Map<Id, Installment__c>();

        for (Installment__c installment : [
            SELECT Id, Booking__c, Amount__c,
                   Paid_Amount__c, Status__c
            FROM Installment__c
            WHERE Booking__c IN :bookingIds
            AND Installment_Number__c = 1
            AND Installment_Type__c = 'Deposit'
        ]) {
            deposits.put(installment.Booking__c, installment);
        }

        List<Installment__c> newInstallments =
            new List<Installment__c>();

        List<Opportunity> bookingUpdates =
            new List<Opportunity>();

        Set<String> keys = new Set<String>();

        for (Id bookingId : bookingIds) {
            keys.add(scheduleKey(bookingId, 2));
            keys.add(scheduleKey(bookingId, 3));
        }

        Set<String> existingKeys = new Set<String>();

        for (Installment__c existing : [
            SELECT Id, Schedule_Key__c
            FROM Installment__c
            WHERE Schedule_Key__c IN :keys
        ]) {
            existingKeys.add(existing.Schedule_Key__c);
        }

        for (Opportunity booking : bookings.values()) {

            Installment__c deposit = deposits.get(booking.Id);

            if (deposit == null ||
                deposit.Status__c != 'Paid' ||
                deposit.Paid_Amount__c < deposit.Amount__c) {
                continue;
            }

            if (booking.Departure_Date__c == null) {
                throw new AuraHandledException(
                    'Departure Date is required to create the installment schedule.'
                );
            }

            Decimal total = totals.get(booking.Id);

            if (total == null || total <= 0) {
                throw new AuraHandledException(
                    'The saved Booking total is invalid.'
                );
            }

            Decimal depositAmount = percentageAmount(
                total,
                DEPOSIT_PERCENT
            );

            Decimal secondAmount = percentageAmount(
                total,
                SECOND_PERCENT
            );

            // Use the remaining balance to avoid rounding differences.
            Decimal finalAmount =
                (total - depositAmount - secondAmount)
                .setScale(2, RoundingMode.HALF_UP);

            // Installment 2: 35%, due 30 days before departure.
            String secondKey = scheduleKey(booking.Id, 2);

            if (!existingKeys.contains(secondKey)) {

                newInstallments.add(
                    buildInstallment(
                        booking.Id,
                        secondKey,
                        2,
                        'Second Installment',
                        SECOND_PERCENT,
                        secondAmount,
                        booking.Departure_Date__c.addDays(-30)
                    )
                );
            }

            // Installment 3: 40%, due 14 days before departure.
            String finalKey = scheduleKey(booking.Id, 3);

            if (!existingKeys.contains(finalKey)) {

                newInstallments.add(
                    buildInstallment(
                        booking.Id,
                        finalKey,
                        3,
                        'Final Installment',
                        FINAL_PERCENT,
                        finalAmount,
                        booking.Departure_Date__c.addDays(-14)
                    )
                );
            }

            if (booking.Installment_Scheduled_Created__c != true) {

                booking.Installment_Scheduled_Created__c = true;
                bookingUpdates.add(booking);
            }
        }

        if (!newInstallments.isEmpty()) {
            insert newInstallments;
        }

        if (!bookingUpdates.isEmpty()) {
            update bookingUpdates;
        }
    }

    // =====================================================
    // BUILD INSTALLMENT RECORD
    // =====================================================

    private static Installment__c buildInstallment(
        Id bookingId,
        String key,
        Integer Name,
        String typeValue,
        Decimal percentage,
        Decimal amount,
        Date dueDate
    ) {

        Installment__c installment = new Installment__c();

        installment.Booking__c = bookingId;
        installment.Schedule_Key__c = key;
        installment.Installment_Number__c = Name;
        installment.Installment_Type__c = typeValue;
        installment.Percentage__c = percentage;
        installment.Amount__c = amount;
        installment.Paid_Amount__c = 0;
        installment.Due_Date__c = dueDate;
        installment.Status__c = 'Pending';

        return installment;
    }

    // =====================================================
    // CALCULATE SAVED PACKAGE TOTAL
    // =====================================================

    private static Map<Id, Decimal> calculatePackageTotals(
        Set<Id> bookingIds
    ) {

        Map<Id, Decimal> totals =
            new Map<Id, Decimal>();

        for (Id bookingId : bookingIds) {
            totals.put(bookingId, 0);
        }

        for (OpportunityLineItem line : [
            SELECT OpportunityId, Quantity, UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId IN :bookingIds
            AND Booking_Service__c = true
        ]) {

            Decimal lineTotal =
                line.Quantity * line.UnitPrice;

            totals.put(
                line.OpportunityId,
                totals.get(line.OpportunityId) + lineTotal
            );
        }

        return totals;
    }

    // =====================================================
    // PERCENTAGE CALCULATION
    // =====================================================

    private static Decimal percentageAmount(
        Decimal total,
        Decimal percentage
    ) {

        return (
            total * percentage / 100
        ).setScale(2, RoundingMode.HALF_UP);
    }

    // =====================================================
    // UNIQUE SCHEDULE KEY
    // =====================================================

    private static String scheduleKey(
        Id bookingId,
        Integer installmentNumber
    ) {

        return String.valueOf(bookingId) +
            '-' +
            String.valueOf(installmentNumber);
    }

    



@AuraEnabled
public static String createInstallmentSchedule(
    Id bookingId,
    Id paymentId
) {
    if (bookingId == null || paymentId == null) {
        throw new AuraHandledException(
            'Booking ID and Payment ID are required.'
        );
    }

    Opportunity booking = [
        SELECT Id, Departure_Date__c, StageName
        FROM Opportunity
        WHERE Id = :bookingId
        FOR UPDATE
    ];

    if (booking.StageName == 'Confirmed' ||
        booking.StageName == 'Completed' ||
        booking.StageName == 'Cancelled') {
        throw new AuraHandledException(
            'This Booking cannot be modified.'
        );
    }

    Payment__c parentPayment = [
        SELECT Id, Booking__c, Status__c,
               Payment_Structure__c, Amount__c,
               Installment__c
        FROM Payment__c
        WHERE Id = :paymentId
        AND Booking__c = :bookingId
        LIMIT 1
    ];

    if (parentPayment.Installment__c != null ||
        parentPayment.Payment_Structure__c != 'Installments' ||
        parentPayment.Status__c != 'Pending') {
        throw new AuraHandledException(
            'A valid Pending parent Installment Payment is required.'
        );
    }

    if (booking.Departure_Date__c == null) {
        throw new AuraHandledException(
            'Enter the Departure Date first.'
        );
    }

    if (Date.today().daysBetween(
        booking.Departure_Date__c
    ) <= 45) {
        throw new AuraHandledException(
            'Installments require departure more than 45 days away.'
        );
    }

    Decimal total = calculatePackageTotals(
        new Set<Id>{bookingId}
    ).get(bookingId);

    if (total == null || total <= 0) {
        throw new AuraHandledException(
            'Save the Travel Package first.'
        );
    }

    total = total.setScale(2, RoundingMode.HALF_UP);

    if (parentPayment.Amount__c == null ||
        parentPayment.Amount__c.setScale(2) != total) {
        throw new AuraHandledException(
            'Payment amount does not match the Booking total.'
        );
    }

    Set<String> keys = new Set<String>{
        scheduleKey(bookingId, 1),
        scheduleKey(bookingId, 2),
        scheduleKey(bookingId, 3)
    };

    Map<Integer, Installment__c> existingByNumber =
        new Map<Integer, Installment__c>();

    for (Installment__c existing : [
        SELECT Id, Booking__c, Parent_Payment__c,
               Installment_Number__c
        FROM Installment__c
        WHERE Schedule_Key__c IN :keys
        FOR UPDATE
    ]) {
        if (existing.Installment_Number__c == null) {
            continue;
        }

        Integer installmentNo =
            existing.Installment_Number__c.intValue();

        existingByNumber.put(installmentNo, existing);
    }

    Decimal deposit = percentageAmount(total, 25);
    Decimal second = percentageAmount(total, 35);

    Decimal finalAmount = (
        total - deposit - second
    ).setScale(2, RoundingMode.HALF_UP);

    List<Decimal> amounts = new List<Decimal>{
        deposit, second, finalAmount
    };

    List<Decimal> percentages = new List<Decimal>{
        25, 35, 40
    };

    List<String> types = new List<String>{
        'Deposit',
        'Second Installment',
        'Final Installment'
    };

    Date departure = booking.Departure_Date__c;

    List<Date> dueDates = new List<Date>{
        Date.today(),
        departure.addDays(-30),
        departure.addDays(-14)
    };

    List<Installment__c> toInsert =
        new List<Installment__c>();

    List<Installment__c> toUpdate =
        new List<Installment__c>();

    for (Integer i = 1; i <= 3; i++) {

        Installment__c existing =
            existingByNumber.get(i);

        if (existing != null) {

            if (existing.Booking__c != bookingId) {
                throw new AuraHandledException(
                    'Existing installment belongs to another Booking.'
                );
            }

            if (existing.Parent_Payment__c != null &&
                existing.Parent_Payment__c != paymentId) {
                throw new AuraHandledException(
                    'Existing installment belongs to another parent Payment.'
                );
            }

            if (existing.Parent_Payment__c == null) {
                existing.Parent_Payment__c = paymentId;
                toUpdate.add(existing);
            }

        } else {

            Installment__c item = new Installment__c();

            item.Booking__c = bookingId;

            // IMPORTANT: Use the custom parent Payment lookup.
            item.Parent_Payment__c = paymentId;

            // Do not assign item.Payment__c.
            item.Schedule_Key__c = scheduleKey(bookingId, i);
            item.Installment_Number__c = i;
            item.Installment_Type__c = types[i - 1];
            item.Percentage__c = percentages[i - 1];
            item.Amount__c = amounts[i - 1];
            item.Paid_Amount__c = 0;
            item.Due_Date__c = dueDates[i - 1];
            item.Status__c = 'Pending';

            toInsert.add(item);
        }
    }

    try {

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }

        return 'Three installments created successfully: 25%, 35%, and 40%.';

    } catch (DmlException e) {

        String errorMessage = '';

        for (Integer i = 0; i < e.getNumDml(); i++) {
            errorMessage += e.getDmlMessage(i) + ' ';
        }

        throw new AuraHandledException(
            'Installment DML failed: ' + errorMessage
        );
    }
}






}

