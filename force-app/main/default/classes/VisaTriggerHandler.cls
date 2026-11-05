public with sharing class VisaTriggerHandler {
    // Use Apex scheduling OR your existing scheduling Flows
    // for the same events, to avoid duplicate requests.

    private static Set<Id> requestedBookings =
        new Set<Id>();

    public static void afterInsert(
        List<Opportunity> bookings
    ) {
        Set<Id> ids = new Set<Id>();

        for (Opportunity booking : bookings) {
            ids.add(booking.Id);
        }

        requestBookings(ids);
    }

    public static void afterUpdate(
        List<Opportunity> bookings,
        Map<Id, Opportunity> oldMap
    ) {
        Set<Id> ids = new Set<Id>();

        for (Opportunity booking : bookings) {
            Opportunity previous =
                oldMap.get(booking.Id);

            if (
                booking.Traveler__c !=
                    previous.Traveler__c ||
                booking.Return_Date__c !=
                    previous.Return_Date__c
            ) {
                ids.add(booking.Id);
            }
        }

        requestBookings(ids);
    }

    public static void afterProductInsert(
        List<OpportunityLineItem> lines
    ) {
        Set<Id> ids = new Set<Id>();

        for (OpportunityLineItem line : lines) {
            ids.add(line.OpportunityId);
        }

        requestBookings(ids);
    }

    public static void afterProductUpdate(
        List<OpportunityLineItem> lines,
        Map<Id, OpportunityLineItem> oldMap
    ) {
        Set<Id> ids = new Set<Id>();

        for (OpportunityLineItem line : lines) {
            OpportunityLineItem previous =
                oldMap.get(line.Id);

            if (
                line.OpportunityId !=
                    previous.OpportunityId ||
                line.PricebookEntryId !=
                    previous.PricebookEntryId
            ) {
                ids.add(
                    line.OpportunityId
                );

                ids.add(
                    previous.OpportunityId
                );
            }
        }

        requestBookings(ids);
    }

    public static void afterProductDelete(
        List<OpportunityLineItem> lines
    ) {
        afterProductInsert(lines);
    }

    public static void requestBookings(
        Set<Id> bookingIds
    ) {
        if (
            bookingIds == null ||
            bookingIds.isEmpty()
        ) {
            return;
        }

        List<VisaWrapper.VisaCheckInputWrapper> inputs =
            new List<VisaWrapper.VisaCheckInputWrapper>();

        for (Id bookingId : bookingIds) {
            if (
                bookingId == null ||
                requestedBookings.contains(bookingId)
            ) {
                continue;
            }

            VisaWrapper.VisaCheckInputWrapper input =
                new VisaWrapper.VisaCheckInputWrapper();

            input.opportunityId = bookingId;
            inputs.add(input);
        }

        if (inputs.isEmpty()) {
            return;
        }

        // Mark before DML to prevent recursive scheduling.
        for (
            VisaWrapper.VisaCheckInputWrapper input :
            inputs
        ) {
            requestedBookings.add(
                input.opportunityId
            );
        }

        VisaController.requestVisaCheck(inputs);
    }

    // Call from an Opportunity before-insert/before-update trigger.
    // Checks Passport validity for won stages.
    // Issued-visa/checklist approval is a separate requirement.
    public static void validatePassportForConfirmation(
        List<Opportunity> bookings
    ) {
        if (
            bookings == null ||
            bookings.isEmpty()
        ) {
            return;
        }

        Set<String> wonStages =
            new Set<String>();

        for (OpportunityStage stage : [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsWon = true
        ]) {
            wonStages.add(
                stage.MasterLabel
            );
        }

        List<Opportunity> candidates =
            new List<Opportunity>();

        Set<Id> contacts =
            new Set<Id>();

        Map<Id, VisaWrapper.Snapshot> byContact =
            new Map<Id, VisaWrapper.Snapshot>();

        for (Opportunity booking : bookings) {
            if (
                !wonStages.contains(
                    booking.StageName
                )
            ) {
                continue;
            }

            if (
                booking.Traveler__c == null ||
                booking.Return_Date__c == null
            ) {
                booking.addError(
                    'Select a Traveler and enter the Return Date ' +
                    'before confirming the Booking.'
                );

                continue;
            }

            candidates.add(booking);

            contacts.add(
                booking.Traveler__c
            );

            if (
                !byContact.containsKey(
                    booking.Traveler__c
                )
            ) {
                VisaWrapper.Snapshot state =
                    new VisaWrapper.Snapshot();

                state.booking = booking;

                byContact.put(
                    booking.Traveler__c,
                    state
                );
            }
        }

        if (candidates.isEmpty()) {
            return;
        }

        VisaController.loadPassports(
            byContact,
            contacts
        );

        for (Opportunity booking : candidates) {
            VisaWrapper.Snapshot state =
                byContact.get(
                    booking.Traveler__c
                );

            if (state.problem != null) {
                booking.addError(
                    state.problem
                );
            } else if (
                state.expiry == null ||
                state.expiry <
                    VisaController.sixMonthsAfter(
                        booking.Return_Date__c
                    )
            ) {
                booking.addError(
                    'Primary Passport must be valid for at least ' +
                    'six months after the Return Date.'
                );
            }
        }
    }
}
