
public with sharing class VisaChecklistController {
    @AuraEnabled
    public static Map<String, Object> checkVisaRequirements(
        Id bookingId
    ) {

        if (bookingId == null) {
            throw new AuraHandledException('Booking ID is required.');
        }

        Opportunity booking = [
            SELECT Id, Traveler__c, Return_Date__c,
                   Visa_Status__c, Booking_Status__c
            FROM Opportunity
            WHERE Id = :bookingId
            LIMIT 1
        ];

        Boolean hasAirTicket = false;

        for (OpportunityLineItem line : [
            SELECT PricebookEntry.Product2.Package_Type__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :bookingId
            AND Booking_Service__c = true
        ]) {

            String typeValue = String.valueOf(
                line.PricebookEntry.Product2.Package_Type__c == null
                ? ''
                : line.PricebookEntry.Product2.Package_Type__c
            ).toLowerCase();

            if (typeValue.contains('air') ||
                typeValue.contains('flight') ||
                typeValue.contains('ticket')) {

                hasAirTicket = true;
            }
        }

        if (!hasAirTicket) {
            throw new AuraHandledException(
                'Save at least one Air Ticket before checking visa requirements.'
            );
        }

        Map<Id, VisaWrapper.Snapshot> snapshots =
            VisaController.loadSnapshots(
                new Set<Id>{ bookingId }
            );

        VisaWrapper.Snapshot state = snapshots.get(bookingId);

        if (state == null) {
            throw new AuraHandledException(
                'Booking information could not be loaded.'
            );
        }

        List<VisaWrapper.VisaRecordWrapper> rules =
            new List<VisaWrapper.VisaRecordWrapper>();

        String failure;

        try {

            if (state.problem == null &&
                state.country != null &&
                !state.destinations.isEmpty() &&
                !state.missingDestination) {

                rules = VisaController.queryRules(
                    new Set<String>{ state.country },
                    state.destinations
                );

            }

        } catch (Exception ex) {

            failure = 'Visa API check failed. Check Named Credential and retry.';
        }

        VisaWrapper.VisaValidationResult result =
            VisaController.evaluate(state, rules, failure);

        upsertDestinationChecklists(
            state,
            rules,
            failure
        );

        Opportunity updateBooking = new Opportunity(
            Id = bookingId,
            Visa_Status__c = result.visaStatus,
            Visa_Required__c = result.visaRequired == true,
            Visa_Requirements__c =
                VisaController.fit(result.requirements),
            Booking_Status__c = 'Visa Review'
        );

        update updateBooking;

        String blockReason = getQuoteBlockReason(bookingId);

        Boolean eligible = String.isBlank(blockReason);

        if (eligible) {
            update new Opportunity(
                Id = bookingId,
                Booking_Status__c = 'Ready to Quote'
            );
        }

        List<Visa_Checklist__c> checklists =
            getActiveVisaChecklists(bookingId);

        return new Map<String, Object>{
            'visaStatus' => result.visaStatus,
            'visaRequired' => result.visaRequired,
            'passportValid' => result.passportValid,
            'passportCountry' => result.passportCountry,
            'passportExpiryDate' => result.passportExpiryDate,
            'requirements' => result.requirements,
            'quoteEligible' => eligible,
            'quoteBlockReason' => blockReason,
            'checklists' => checklists
        };
    }
@AuraEnabled(cacheable=true)
public static Map<String, Object> getVisaSummary(Id bookingId) {

    if (bookingId == null) {
        return new Map<String, Object>();
    }

    Opportunity booking = [
        SELECT Id,
               Visa_Status__c,
               Visa_Required__c,
               Visa_Requirements__c
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
    ];

    String blockReason =
        getQuoteBlockReason(bookingId);

    return new Map<String, Object>{
        'visaStatus' => booking.Visa_Status__c,
        'visaRequired' => booking.Visa_Required__c,
        'requirements' => booking.Visa_Requirements__c,
        'quoteEligible' => String.isBlank(blockReason),
        'quoteBlockReason' => blockReason
    };
}

    // =====================================================
    // CREATE / UPDATE CHECKLISTS
    // =====================================================

    private static void upsertDestinationChecklists(
        VisaWrapper.Snapshot state,
        List<VisaWrapper.VisaRecordWrapper> rules,
        String failure
    ) {

        Id bookingId = state.booking.Id;

        List<Visa_Checklist__c> existingRows = [
            SELECT Id, Checklist_Key__c,
                   Active_for_Cureent_Itineray__c,
                   Passport__c,
                   Passport_Country__c,
                   Passport_Expiry_Date_At_Check__c,
                   Itinerary_Signature__c,
                   Visa_Required__c,
                   Visa_Type__c,
                   Allowed_Stay__c,
                   API_Notes__c,
                   Status__c,
                   Visa_Grant_Received__c,
                   Visa_Expiry_Date__c,
                   Application_Reference__c,
                   Appointment_Date__c,
                   Submission_Date__c,
                   Decision_Date__c,
                   Comments__c,
                   Passport_Copy_Received__c,
                   Passport_Photo_Received__c,
                   Application_Form_Completed__c,
                   Flight_Itinerary_Received__c,
                   Hotel_Confirmation_Received__c,
                   Travel_Insurance_Received__c,
                   Financial_Proof_Received__c,
                   Appointment_Completed__c
            FROM Visa_Checklist__c
            WHERE Booking__c = :bookingId
        ];

        Map<String, Visa_Checklist__c> existingByKey =
            new Map<String, Visa_Checklist__c>();

        for (Visa_Checklist__c oldRow : existingRows) {
            existingByKey.put(oldRow.Checklist_Key__c, oldRow);
        }

        Set<String> currentKeys = new Set<String>();

        List<Visa_Checklist__c> toUpsert =
            new List<Visa_Checklist__c>();

        String currentSignature =
            VisaController.signature(state);

        for (String destination : state.destinations) {

            String keyValue =
                String.valueOf(bookingId) + ':' + destination;

            currentKeys.add(keyValue);

            Visa_Checklist__c previous =
                existingByKey.get(keyValue);

            List<VisaWrapper.VisaRecordWrapper> matches =
                new List<VisaWrapper.VisaRecordWrapper>();

            if (failure == null &&
                state.problem == null &&
                state.country != null) {

                for (VisaWrapper.VisaRecordWrapper rule : rules) {

                    if (rule.Passport_c == state.country &&
                        rule.Destination_c == destination) {

                        matches.add(rule);
                    }
                }
            }

            Visa_Checklist__c row =
                new Visa_Checklist__c();

            if (previous != null) {
                row.Id = previous.Id;
            }

            row.Checklist_Key__c = keyValue;
            row.Booking__c = bookingId;
            row.Traveler__c = state.booking.Traveler__c;
            row.Passport__c = state.passportId;
            row.Passport_Country__c = state.country;
            row.Passport_Expiry_Date_At_Check__c = state.expiry;
            row.Destination_Country__c = destination;
            row.Itinerary_Signature__c = currentSignature;
            row.Active_for_Cureent_Itineray__c = true;

            if (failure != null ||
                state.problem != null ||
                state.country == null ||
                matches.size() != 1 ||
                matches[0].Visa_Required_c == null) {

                row.Visa_Required__c = false;
                row.Status__c = 'Needs Review';
                row.Visa_Grant_Received__c = false;

                row.API_Notes__c = failure != null
                    ? failure
                    : (state.problem != null
                        ? state.problem
                        : 'Missing or incomplete API visa rule.');

            } else {

                VisaWrapper.VisaRecordWrapper rule = matches[0];

                row.Visa_Required__c = rule.Visa_Required_c;
                row.Visa_Type__c = fitText(rule.Visa_Type_c, 100);
                row.Allowed_Stay__c = fitText(rule.Allowed_Stay_c, 100);
                row.API_Notes__c = fitText(rule.Notes_c, 2000);

                Boolean unchanged =
                    previous != null &&
                    previous.Active_for_Cureent_Itineray__c== true &&
                    previous.Passport__c == state.passportId &&
                    previous.Passport_Country__c == state.country &&
                    previous.Passport_Expiry_Date_At_Check__c == state.expiry &&
                    previous.Itinerary_Signature__c == currentSignature &&
                    previous.Visa_Required__c == rule.Visa_Required_c &&
                    previous.Visa_Type__c == row.Visa_Type__c &&
                    previous.Allowed_Stay__c == row.Allowed_Stay__c &&
                    previous.API_Notes__c == row.API_Notes__c;

                if (rule.Visa_Required_c == false) {

                    row.Status__c = 'Not Required';
                    row.Visa_Grant_Received__c = false;
                    row.Visa_Expiry_Date__c = null;

                } else if (unchanged) {

                    row.Status__c = previous.Status__c;
                    row.Visa_Grant_Received__c =
                        previous.Visa_Grant_Received__c;
                    row.Visa_Expiry_Date__c =
                        previous.Visa_Expiry_Date__c;

                    row.Application_Reference__c =
                        previous.Application_Reference__c;
                    row.Appointment_Date__c =
                        previous.Appointment_Date__c;
                    row.Submission_Date__c =
                        previous.Submission_Date__c;
                    row.Decision_Date__c =
                        previous.Decision_Date__c;
                    row.Comments__c = previous.Comments__c;

                    row.Passport_Copy_Received__c =
                        previous.Passport_Copy_Received__c;
                    row.Passport_Photo_Received__c =
                        previous.Passport_Photo_Received__c;
                    row.Application_Form_Completed__c =
                        previous.Application_Form_Completed__c;
                    row.Flight_Itinerary_Received__c =
                        previous.Flight_Itinerary_Received__c;
                    row.Hotel_Confirmation_Received__c =
                        previous.Hotel_Confirmation_Received__c;
                    row.Travel_Insurance_Received__c =
                        previous.Travel_Insurance_Received__c;
                    row.Financial_Proof_Received__c =
                        previous.Financial_Proof_Received__c;
                    row.Appointment_Completed__c =
                        previous.Appointment_Completed__c;

                } else {

                    row.Status__c = 'Not Started';
                    row.Visa_Grant_Received__c = false;
                    row.Visa_Expiry_Date__c = null;
                }
            }

            toUpsert.add(row);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert Checklist_Key__c;
        }

        // Retain old destinations for audit.
        List<Visa_Checklist__c> staleRows =
            new List<Visa_Checklist__c>();

        for (Visa_Checklist__c oldRow : existingRows) {

            if (oldRow.Active_for_Cureent_Itineray__c == true &&
                !currentKeys.contains(oldRow.Checklist_Key__c)) {

                staleRows.add(
                    new Visa_Checklist__c(
                        Id = oldRow.Id,
                        Active_for_Cureent_Itineray__c = false
                    )
                );
            }
        }

        if (!staleRows.isEmpty()) {
            update staleRows;
        }
    }

    // =====================================================
    // GET ACTIVE CHECKLISTS
    // =====================================================

    @AuraEnabled(cacheable=true)
    public static List<Visa_Checklist__c> getActiveVisaChecklists(
        Id bookingId
    ) {

        if (bookingId == null) {
            return new List<Visa_Checklist__c>();
        }

        return [
            SELECT Id, Name,
                   Booking__c,
                   Traveler__c,
                   Passport__c,
                   Passport_Country__c,
                   Passport_Expiry_Date_At_Check__c,
                   Destination_Country__c,
                   Visa_Required__c,
                   Visa_Type__c,
                   Allowed_Stay__c,
                   API_Notes__c,
                   Status__c,
                   Passport_Copy_Received__c,
                   Passport_Photo_Received__c,
                   Application_Form_Completed__c,
                   Flight_Itinerary_Received__c,
                   Hotel_Confirmation_Received__c,
                   Travel_Insurance_Received__c,
                   Financial_Proof_Received__c,
                   Appointment_Completed__c,
                   Visa_Grant_Received__c,
                   Application_Reference__c,
                   Appointment_Date__c,
                   Submission_Date__c,
                   Decision_Date__c,
                   Visa_Expiry_Date__c,
                   Comments__c,
                   Active_for_Cureent_Itineray__c
            FROM Visa_Checklist__c
            WHERE Booking__c = :bookingId
            AND Active_for_Cureent_Itineray__c = true
            ORDER BY Destination_Country__c
        ];
    }

    // =====================================================
    // SAVE VISA APPLICATION INFORMATION
    // THIS METHOD CANNOT APPROVE A VISA
    // =====================================================

    @AuraEnabled
    public static String saveVisaInformation(
        Id bookingId,
        Id checklistId,
        String payloadJson
    ) {

        if (bookingId == null ||
            checklistId == null ||
            String.isBlank(payloadJson)) {

            throw new AuraHandledException(
                'Booking, checklist and visa information are required.'
            );
        }

        Visa_Checklist__c checklist = [
            SELECT Id, Booking__c,
                   Visa_Required__c,
                   Active_for_Cureent_Itineray__c,
                   Status__c
            FROM Visa_Checklist__c
            WHERE Id = :checklistId
            AND Booking__c = :bookingId
            LIMIT 1
        ];

        if (checklist.Active_for_Cureent_Itineray__c != true ||
            checklist.Visa_Required__c != true) {

            throw new AuraHandledException(
                'This checklist does not require a visa.'
            );
        }

        Map<String, Object> data;

        try {
            data = (Map<String, Object>)
                JSON.deserializeUntyped(payloadJson);
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Invalid visa information.'
            );
        }

        String requestedStatus =
            stringValue(data.get('status'));

        Set<String> allowedStatuses = new Set<String>{
            'Not Started',
            'Documents Pending',
            'Documents Complete',
            'Appointment Scheduled',
            'Submitted',
            'Rejected'
        };

        if (String.isBlank(requestedStatus)) {
            requestedStatus = 'Documents Pending';
        }

        if (!allowedStatuses.contains(requestedStatus)) {
            throw new AuraHandledException(
                'Visa approval must be recorded by authorized Visa Operations staff.'
            );
        }

        checklist.Application_Reference__c =
            fitText(data.get('applicationReference'), 100);

        checklist.Status__c = requestedStatus;

        checklist.Appointment_Date__c =
            parseDate(data.get('appointmentDate'));

        checklist.Submission_Date__c =
            parseDate(data.get('submissionDate'));

        checklist.Decision_Date__c =
            parseDate(data.get('decisionDate'));

        checklist.Comments__c =
            fitText(data.get('comments'), 4000);

        checklist.Passport_Copy_Received__c =
            booleanValue(data.get('passportCopyReceived'));

        checklist.Passport_Photo_Received__c =
            booleanValue(data.get('passportPhotoReceived'));

        checklist.Application_Form_Completed__c =
            booleanValue(data.get('applicationFormCompleted'));

        checklist.Flight_Itinerary_Received__c =
            booleanValue(data.get('flightItineraryReceived'));

        checklist.Hotel_Confirmation_Received__c =
            booleanValue(data.get('hotelConfirmationReceived'));

        checklist.Travel_Insurance_Received__c =
            booleanValue(data.get('travelInsuranceReceived'));

        checklist.Financial_Proof_Received__c =
            booleanValue(data.get('financialProofReceived'));

        checklist.Appointment_Completed__c =
            booleanValue(data.get('appointmentCompleted'));

        update checklist;

        update new Opportunity(
            Id = bookingId,
            Booking_Status__c = 'Visa Review'
        );

        return 'Visa application information saved. Visa approval is still pending.';
    }

    // =====================================================
    // QUOTE VALIDATION
    // =====================================================

    public static String getQuoteBlockReason(Id bookingId) {

        Map<Id, String> reasons =
            getQuoteBlockReasons(new Set<Id>{ bookingId });

        return reasons.get(bookingId);
    }

    public static Map<Id, String> getQuoteBlockReasons(
        Set<Id> bookingIds
    ) {

        Map<Id, String> reasons = new Map<Id, String>();

        if (bookingIds == null || bookingIds.isEmpty()) {
            return reasons;
        }

        Map<Id, Opportunity> bookings =
            new Map<Id, Opportunity>([
                SELECT Id, Traveler__c,
                       Return_Date__c,
                       Visa_Status__c
                FROM Opportunity
                WHERE Id IN :bookingIds
            ]);

        Map<Id, VisaWrapper.Snapshot> snapshots =
            VisaController.loadSnapshots(bookingIds);

        Map<Id, Boolean> hasAirTicket =
            new Map<Id, Boolean>();

        for (OpportunityLineItem line : [
            SELECT OpportunityId,
                   PricebookEntry.Product2.Package_Type__c
            FROM OpportunityLineItem
            WHERE OpportunityId IN :bookingIds
            AND Booking_Service__c = true
        ]) {

            String typeValue = String.valueOf(
                line.PricebookEntry.Product2.Package_Type__c == null
                ? ''
                : line.PricebookEntry.Product2.Package_Type__c
            ).toLowerCase();

            if (typeValue.contains('air') ||
                typeValue.contains('flight') ||
                typeValue.contains('ticket')) {

                hasAirTicket.put(line.OpportunityId, true);
            }
        }

        Map<Id, List<Visa_Checklist__c>> byBooking =
            new Map<Id, List<Visa_Checklist__c>>();

        for (Visa_Checklist__c row : [
            SELECT Id, Booking__c,
                   Destination_Country__c,
                   Visa_Required__c,
                   Status__c,
                   Visa_Grant_Received__c,
                   Visa_Expiry_Date__c,
                   Active_for_Cureent_Itineray__c,
                   Passport__c,
                   Passport_Country__c,
                   Passport_Expiry_Date_At_Check__c,
                   Itinerary_Signature__c
            FROM Visa_Checklist__c
            WHERE Booking__c IN :bookingIds
            AND Active_for_Cureent_Itineray__c = true
        ]) {

            if (!byBooking.containsKey(row.Booking__c)) {
                byBooking.put(
                    row.Booking__c,
                    new List<Visa_Checklist__c>()
                );
            }

            byBooking.get(row.Booking__c).add(row);
        }

        for (Id bookingId : bookingIds) {

            Opportunity booking = bookings.get(bookingId);
            VisaWrapper.Snapshot state = snapshots.get(bookingId);

            if (booking == null || state == null) {
                reasons.put(bookingId, 'Booking unavailable.');
                continue;
            }

            if (hasAirTicket.get(bookingId) != true) {
                reasons.put(
                    bookingId,
                    'Save at least one Air Ticket first.'
                );
                continue;
            }

            if (booking.Visa_Status__c != 'Visa Free' &&
                booking.Visa_Status__c != 'Visa Required') {

                reasons.put(
                    bookingId,
                    'Run Check Visa Requirements first.'
                );
                continue;
            }

            if (state.problem != null ||
                state.country == null ||
                state.destinations.isEmpty() ||
                state.missingDestination) {

                reasons.put(
                    bookingId,
                    'Passport or destination information is incomplete.'
                );
                continue;
            }

            if (booking.Return_Date__c == null ||
                state.expiry == null ||
                state.expiry <
                    VisaController.sixMonthsAfter(booking.Return_Date__c)) {

                reasons.put(
                    bookingId,
                    'Passport validity requirement is not satisfied.'
                );
                continue;
            }

            List<Visa_Checklist__c> rows =
                byBooking.get(bookingId);

            if (rows == null ||
                rows.size() != state.destinations.size()) {

                reasons.put(
                    bookingId,
                    'Run Check Visa Requirements again. Destination checklists are incomplete.'
                );
                continue;
            }

            Map<String, Visa_Checklist__c> byDestination =
                new Map<String, Visa_Checklist__c>();

            for (Visa_Checklist__c row : rows) {
                if (byDestination.containsKey(
                    row.Destination_Country__c
                )) {
                    reasons.put(
                        bookingId,
                        'Duplicate destination checklist detected.'
                    );
                    break;
                }

                byDestination.put(
                    row.Destination_Country__c,
                    row
                );
            }

            if (reasons.containsKey(bookingId)) {
                continue;
            }

            String problem;

            for (String destination : state.destinations) {

                Visa_Checklist__c row =
                    byDestination.get(destination);

                if (row == null) {
                    problem =
                        'Missing visa checklist for ' + destination;
                    break;
                }

                if (row.Itinerary_Signature__c !=
                        VisaController.signature(state) ||
                    row.Passport__c != state.passportId ||
                    row.Passport_Country__c != state.country ||
                    row.Passport_Expiry_Date_At_Check__c != state.expiry) {

                    problem =
                        'Passport or itinerary changed. Run the visa check again.';
                    break;
                }

                if (row.Status__c == 'Needs Review') {
                    problem =
                        'Manual visa review required for ' + destination;
                    break;
                }

                if (row.Visa_Required__c == true) {

                    if (row.Status__c != 'Approved' ||
                        row.Visa_Grant_Received__c != true ||
                        row.Visa_Expiry_Date__c == null ||
                        row.Visa_Expiry_Date__c <
                            booking.Return_Date__c) {

                        problem =
                            'Quote blocked: official visa approval and valid visa grant are required for ' +
                            destination;

                        break;
                    }

                } else if (row.Status__c != 'Not Required') {

                    problem =
                        'Visa Free checklist is incomplete for ' + destination;

                    break;
                }
            }

            if (problem != null) {
                reasons.put(bookingId, problem);
            }
        }

        return reasons;
    }

    // =====================================================
    // HELPERS
    // =====================================================

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Boolean booleanValue(Object value) {
        return value != null &&
            String.valueOf(value).toLowerCase() == 'true';
    }

    private static Date parseDate(Object value) {

        if (value == null ||
            String.isBlank(String.valueOf(value))) {
            return null;
        }

        try {
            return Date.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            throw new AuraHandledException('Invalid date.');
        }
    }

    private static String fitText(Object value, Integer length) {

        if (value == null) {
            return null;
        }

        String result = String.valueOf(value);

        return result.length() > length
            ? result.substring(0, length)
            : result;
    }
}

