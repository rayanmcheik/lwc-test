public with sharing class VisaRequirementsQueueable
    implements Queueable, Database.AllowsCallouts {

    private static final Integer BOOKINGS_PER_JOB = 10;

    private Map<Id, String> tokens;

    public VisaRequirementsQueueable(
        Map<Id, String> requestTokens
    ) {
        tokens = new Map<Id, String>();
        tokens.putAll(requestTokens);
    }

    public void execute(QueueableContext context) {
        Set<Id> ids = new Set<Id>();
        Map<Id, String> remaining = new Map<Id, String>();

        for (Id bookingId : tokens.keySet()) {
            if (ids.size() < BOOKINGS_PER_JOB) {
                ids.add(bookingId);
            } else {
                remaining.put(
                    bookingId,
                    tokens.get(bookingId)
                );
            }
        }

        Map<Id, VisaWrapper.Snapshot> original =
            VisaController.loadSnapshots(ids);

        Set<String> passports = new Set<String>();
        Set<String> destinations = new Set<String>();

        for (VisaWrapper.Snapshot state : original.values()) {
            if (
                state.booking.Visa_Check_Request_Id__c !=
                tokens.get(state.booking.Id)
            ) {
                continue;
            }

            if (state.country != null) {
                passports.add(state.country);
            }

            destinations.addAll(state.destinations);
        }

        List<VisaWrapper.VisaRecordWrapper> rules =
            new List<VisaWrapper.VisaRecordWrapper>();

        String failure;

        try {
            // Requirements are fetched from the external API.
            if (
                !passports.isEmpty() &&
                !destinations.isEmpty()
            ) {
                rules = VisaController.queryRules(
                    passports,
                    destinations
                );
            }
        } catch (Exception error) {
            failure =
                'Visa API check failed. Review the Named Credential ' +
                'and request another check.';
        }

        Map<Id, VisaWrapper.Snapshot> latest =
            VisaController.loadSnapshots(ids);

        // Lock after HTTP requests finish.
        List<Opportunity> locks = [
            SELECT Id, Visa_Check_Request_Id__c
            FROM Opportunity
            WHERE Id IN :ids
            FOR UPDATE
        ];

        List<Opportunity> changes =
            new List<Opportunity>();

        List<Opportunity> emailBookings =
            new List<Opportunity>();

        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();

        for (Opportunity locked : locks) {
            VisaWrapper.Snapshot baseline =
                original.get(locked.Id);

            VisaWrapper.Snapshot current =
                latest.get(locked.Id);

            String expected = tokens.get(locked.Id);

            if (
                baseline == null ||
                current == null ||
                locked.Visa_Check_Request_Id__c != expected ||
                baseline.booking.Visa_Check_Request_Id__c != expected
            ) {
                continue;
            }

            VisaWrapper.VisaValidationResult result;

            if (
                VisaController.signature(baseline) !=
                VisaController.signature(current)
            ) {
                result =
                    new VisaWrapper.VisaValidationResult();

                result.visaStatus = 'Pending Review';

                result.requirements =
                    'Passport or itinerary changed during processing. ' +
                    'Request another check.';
            } else {
                result = VisaController.evaluate(
                    current,
                    rules,
                    failure
                );
            }

            Opportunity change = new Opportunity(
                Id = locked.Id,
                Visa_Status__c = result.visaStatus,
                Visa_Requirements__c =
                    VisaController.fit(result.requirements),
                Visa_Check_Request_Id__c = null
            );

            changes.add(change);

            // This request token is consumed on completion.
            // A new requested check can send another email.
            if (result.visaStatus == 'Visa Required') {
                Contact person =
                    current.booking.Traveler__r;

                if (
                    person == null ||
                    String.isBlank(person.Email)
                ) {
                    change.Visa_Requirements__c =
                        VisaController.fit(
                            result.requirements +
                            '\n\nEmail not sent: Traveler email is missing.'
                        );
                } else if (
                    person.HasOptedOutOfEmail == true
                ) {
                    change.Visa_Requirements__c =
                        VisaController.fit(
                            result.requirements +
                            '\n\nEmail not sent: Traveler has opted out.'
                        );
                } else {
                    emails.add(
                        buildEmail(current, result)
                    );

                    emailBookings.add(change);
                }
            }
        }

        // All HTTP requests finish before DML or email.
        if (!changes.isEmpty()) {
            update as user changes;
        }

        if (!emails.isEmpty()) {
            Map<Id, String> failures =
                sendEmails(emails, emailBookings);

            List<Opportunity> errors =
                new List<Opportunity>();

            for (Opportunity booking : emailBookings) {
                if (failures.containsKey(booking.Id)) {
                    errors.add(new Opportunity(
                        Id = booking.Id,
                        Visa_Requirements__c =
                            VisaController.fit(
                                booking.Visa_Requirements__c +
                                '\n\nEmail failed: ' +
                                failures.get(booking.Id)
                            )
                    ));
                }
            }

            if (!errors.isEmpty()) {
                update as user errors;
            }
        }

        if (!remaining.isEmpty()) {
            System.enqueueJob(
                new VisaRequirementsQueueable(remaining)
            );
        }
    }

    private static Messaging.SingleEmailMessage buildEmail(
        VisaWrapper.Snapshot state,
        VisaWrapper.VisaValidationResult result
    ) {
        String name =
            state.booking.Traveler__r.FirstName;

        if (String.isBlank(name)) {
            name = 'Traveler';
        }

        Messaging.SingleEmailMessage email =
            new Messaging.SingleEmailMessage();

        email.setTargetObjectId(
            state.booking.Traveler__c
        );

        email.setWhatId(state.booking.Id);
        email.setSaveAsActivity(false);

        email.setSubject(
            'Visa required for your booking: ' +
            state.booking.Name
        );

        // Includes visa type, allowed stay, and notes from the API.
        String passportNote = result.passportValid
            ? ''
            : '\n\nPlease contact us to verify your Passport expiry date. ' +
              'Your Passport must be valid for six months after the Return Date.';

        email.setPlainTextBody(
            'Dear ' + name + ',\n\n' +
            'A visa is required for one or more destinations ' +
            'on your booking.\n\n' +
            result.requirements +
            passportNote +
            '\n\nPlease contact our Visa Operations team for the ' +
            'applicable document checklist, application instructions, ' +
            'and submission deadline.' +
            '\n\nKind regards,\nVGTS Travel Team'
        );

        return email;
    }

    private static Map<Id, String> sendEmails(
        List<Messaging.SingleEmailMessage> emails,
        List<Opportunity> bookings
    ) {
        Map<Id, String> failures =
            new Map<Id, String>();

        try {
            List<Messaging.SendEmailResult> results =
                Messaging.sendEmail(emails, false);

            for (
                Integer i = 0;
                i < results.size();
                i++
            ) {
                if (!results[i].isSuccess()) {
                    List<String> errors =
                        new List<String>();

                    for (
                        Messaging.SendEmailError error :
                        results[i].getErrors()
                    ) {
                        errors.add(
                            error.getMessage()
                        );
                    }

                    failures.put(
                        bookings[i].Id,
                        String.join(errors, '; ')
                    );
                }
            }
        } catch (EmailException error) {
            for (Opportunity booking : bookings) {
                failures.put(
                    booking.Id,
                    error.getMessage()
                );
            }
        }

        return failures;
    }
}