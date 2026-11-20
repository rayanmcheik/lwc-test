
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
        label='Create Booking Deposit Installment'
        description='Creates the 25 percent deposit installment when a Quote is accepted.'
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

        if (quoteIds.isEmpty()) {
            return;
        }

        Map<Id, Quote> quotesById = new Map<Id, Quote>([
            SELECT Id, Name, OpportunityId, Status
            FROM Quote
            WHERE Id IN :quoteIds
        ]);

        Set<Id> bookingIds = new Set<Id>();

        for (Quote quoteRecord : quotesById.values()) {

            if (quoteRecord.Status != 'Accepted') {
                continue;
            }

            if (quoteRecord.OpportunityId != null) {
                bookingIds.add(quoteRecord.OpportunityId);
            }
        }

        if (bookingIds.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> bookings = new Map<Id, Opportunity>([
            SELECT Id, Name, Pricebook2Id,
                   Departure_Date__c,
                   Return_Date__c,
                   Quote_Accepted_At__c,
                   Deposit_Deadline__c,
                   Deposit_Received_Amount__c,
                   Installment_Scheduled_Created__c,
                   Ticket_Issuance_Hold__c
            FROM Opportunity
            WHERE Id IN :bookingIds
            FOR UPDATE
        ]);

        Map<Id, Decimal> totals = calculatePackageTotals(bookingIds);

        List<Installment__c> newInstallments =
            new List<Installment__c>();

        List<Opportunity> bookingUpdates =
            new List<Opportunity>();

        Set<String> expectedKeys = new Set<String>();

        for (Opportunity booking : bookings.values()) {
            expectedKeys.add(scheduleKey(booking.Id, 1));
        }

        Map<String, Installment__c> existingByKey =
            new Map<String, Installment__c>();

        for (Installment__c existing : [
            SELECT Id, Schedule_Key__c
            FROM Installment__c
            WHERE Schedule_Key__c IN :expectedKeys
        ]) {
            existingByKey.put(existing.Schedule_Key__c, existing);
        }

        for (Quote quoteRecord : quotesById.values()) {

            if (quoteRecord.Status != 'Accepted' ||
                quoteRecord.OpportunityId == null) {
                continue;
            }

            Opportunity booking =
                bookings.get(quoteRecord.OpportunityId);

            if (booking == null) {
                continue;
            }

            if (booking.Departure_Date__c == null) {
                throw new AuraHandledException(
                    'Enter the Booking Departure Date before accepting the Quote.'
                );
            }

            Decimal total = totals.get(booking.Id);

            if (total == null || total <= 0) {
                throw new AuraHandledException(
                    'The Booking has no valid saved Travel Package value.'
                );
            }

            String key = scheduleKey(booking.Id, 1);

            // Do not create the deposit twice.
            if (existingByKey.containsKey(key)) {
                continue;
            }

            DateTime acceptedAt =
                booking.Quote_Accepted_At__c == null
                    ? System.now()
                    : booking.Quote_Accepted_At__c;

            DateTime deadline = acceptedAt.addHours(48);

            Decimal depositAmount = percentageAmount(
                total,
                DEPOSIT_PERCENT
            );

            Installment__c deposit = new Installment__c();

            deposit.Booking__c = booking.Id;
            deposit.Quote__c = quoteRecord.Id;
            deposit.Schedule_Key__c = key;
            deposit.Installment_Number__c = 1;
            deposit.Installment_Type__c = 'Deposit';
            deposit.Percentage__c = DEPOSIT_PERCENT;
            deposit.Amount__c = depositAmount;
            deposit.Paid_Amount__c = 0;
            deposit.Due_Date__c = Date.newInstance(
                deadline.year(),
                deadline.month(),
                deadline.day()
            );
            deposit.Status__c = 'Pending';

            newInstallments.add(deposit);

            booking.Quote_Accepted_At__c = acceptedAt;
            booking.Deposit_Deadline__c = deadline;
            booking.Deposit_Received_Amount__c = 0;
            booking.Installment_Scheduled_Created__c= false;
            booking.Ticket_Issuance_Hold__c = true;

            bookingUpdates.add(booking);
        }

        if (!newInstallments.isEmpty()) {
            insert newInstallments;
        }

        if (!bookingUpdates.isEmpty()) {
            update bookingUpdates;
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
public static String createInstallmentSchedule(Id bookingId) {

    if (bookingId == null) {
        throw new AuraHandledException(
            'Booking ID is required.'
        );
    }

    Opportunity booking = [
        SELECT Id, Name, Departure_Date__c,
               Pricebook2Id,
               Installment_Scheduled_Created__c
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
        FOR UPDATE
    ];

    if (booking.Departure_Date__c == null) {
        throw new AuraHandledException(
            'Enter the Departure Date first.'
        );
    }

    Integer daysRemaining =
        Date.today().daysBetween(booking.Departure_Date__c);

    if (daysRemaining <= 45) {
        throw new AuraHandledException(
            'Installments are not allowed. The departure date must be more than 45 days away.'
        );
    }

    if (booking.Installment_Scheduled_Created__c == true) {
        throw new AuraHandledException(
            'The installment schedule already exists.'
        );
    }

    List<OpportunityLineItem> products = [
        SELECT Quantity, UnitPrice
        FROM OpportunityLineItem
        WHERE OpportunityId = :bookingId
        AND Booking_Service__c = true
    ];

    if (products.isEmpty()) {
        throw new AuraHandledException(
            'Save the Travel Package first.'
        );
    }

    Decimal total = 0;

    for (OpportunityLineItem product : products) {
        total += product.Quantity * product.UnitPrice;
    }

    if (total <= 0) {
        throw new AuraHandledException(
            'Invalid Travel Package total.'
        );
    }

    // Calculate amounts with rounding.
    Decimal deposit = (total * 25 / 100)
        .setScale(2, RoundingMode.HALF_UP);

    Decimal second = (total * 35 / 100)
        .setScale(2, RoundingMode.HALF_UP);

    // Final installment absorbs any rounding difference.
    Decimal finalAmount = total - deposit - second;

    Date departure = booking.Departure_Date__c;

    List<Installment__c> schedule =
        new List<Installment__c>();

    schedule.add(new Installment__c(
        Booking__c = booking.Id,
        Schedule_Key__c = booking.Id + '-1',
        Installment_Number__c = 1,
        Installment_Type__c = 'Deposit',
        Percentage__c = 25,
        Amount__c = deposit,
        Paid_Amount__c = 0,
        Due_Date__c = Date.today(),
        Status__c = 'Pending'
    ));

    schedule.add(new Installment__c(
        Booking__c = booking.Id,
        Schedule_Key__c = booking.Id + '-2',
        Installment_Number__c = 2,
        Installment_Type__c = 'Second Installment',
        Percentage__c = 35,
        Amount__c = second,
        Paid_Amount__c = 0,
        Due_Date__c = departure.addDays(-30),
        Status__c = 'Pending'
    ));

    schedule.add(new Installment__c(
        Booking__c = booking.Id,
        Schedule_Key__c = booking.Id + '-3',
        Installment_Number__c = 3,
        Installment_Type__c = 'Final Installment',
        Percentage__c = 40,
        Amount__c = finalAmount,
        Paid_Amount__c = 0,
        Due_Date__c = departure.addDays(-14),
        Status__c = 'Pending'
    ));

    insert schedule;

    booking.Installment_Scheduled_Created__c = true;
    update booking;

    return 'Three installments created successfully.';
}


}

