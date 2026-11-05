global with sharing class VisaController {
    private static final String ENDPOINT =
        'callout:Visa_Requirements_API';

    private static final String RULE_SELECT =
        'SELECT Passport__c, Destination__c, Visa_Required__c, ' +
        'Visa_Type__c, Allowed_Stay__c, Notes__c FROM Visa__c';

    @InvocableMethod(
        label='Request Booking Visa Check (VisaController)'
        description='Queues visa requirements and emails the Traveler when a visa is required.'
    )
    global static List<VisaWrapper.VisaCheckOutputWrapper>
        requestVisaCheck(
            List<VisaWrapper.VisaCheckInputWrapper> inputs
        ) {

        List<VisaWrapper.VisaCheckOutputWrapper> outputs =
            new List<VisaWrapper.VisaCheckOutputWrapper>();

        if (inputs == null || inputs.isEmpty()) {
            return outputs;
        }

        Set<Id> ids = new Set<Id>();

        for (
            VisaWrapper.VisaCheckInputWrapper input :
            inputs
        ) {
            if (
                input == null ||
                input.opportunityId == null ||
                input.opportunityId.getSObjectType() !=
                    Opportunity.SObjectType
            ) {
                throw new VisaWrapper.VisaServiceException(
                    'A valid Booking / Opportunity ID is required.'
                );
            }

            ids.add(input.opportunityId);
        }

        List<Opportunity> accessible = [
            SELECT Id
            FROM Opportunity
            WHERE Id IN :ids
            WITH USER_MODE
        ];

        if (accessible.size() != ids.size()) {
            throw new VisaWrapper.VisaServiceException(
                'A Booking is unavailable.'
            );
        }

        String token =
            EncodingUtil.convertToHex(
                Crypto.generateAesKey(128)
            );

        Map<Id, String> tokens =
            new Map<Id, String>();

        List<Opportunity> changes =
            new List<Opportunity>();

        for (Id bookingId : ids) {
            tokens.put(bookingId, token);

            changes.add(new Opportunity(
                Id = bookingId,
                Visa_Status__c = 'Pending Review',
                Visa_Requirements__c =
                    'Visa check queued. Refresh after processing.',
                Visa_Check_Request_Id__c = token
            ));
        }

        update as user changes;

        Id jobId = System.enqueueJob(
            new VisaRequirementsQueueable(tokens)
        );

        for (
            VisaWrapper.VisaCheckInputWrapper input :
            inputs
        ) {
            VisaWrapper.VisaCheckOutputWrapper output =
                new VisaWrapper.VisaCheckOutputWrapper();
 
            output.opportunityId =
                input.opportunityId;

            output.status = 'Pending Review';
            output.message = 'Visa check queued.';
            output.jobId = jobId;

            outputs.add(output);
        }

        return outputs;
    }

    public static List<VisaWrapper.VisaRecordWrapper>
        queryExternalVisaRules(
            String passport,
            String destination
        ) {

        String p = isoCode(passport);
        String d = destinationCountry(destination);

        if (p == null || d == null) {
            throw new VisaWrapper.VisaServiceException(
                'Valid country codes are required, e.g. LB and FR.'
            );
        }

        return queryRules(
            new Set<String>{ p },
            new Set<String>{ d }
        );
    }

    // Read-only diagnostic: retrieves all rules from the API.
    // The number of records is not hardcoded.
    public static List<VisaWrapper.VisaRecordWrapper>
        getAllVisaRules() {

        return executeVisaQuery(RULE_SELECT);
    }

    // Booking checks retrieve only the relevant country combinations.
    public static List<VisaWrapper.VisaRecordWrapper>
        queryRules(
            Set<String> passports,
            Set<String> destinations
        ) {

        if (
            passports == null ||
            passports.isEmpty() ||
            destinations == null ||
            destinations.isEmpty()
        ) {
            throw new VisaWrapper.VisaServiceException(
                'Passport and destination country codes are required.'
            );
        }

        String soql =
            RULE_SELECT +
            ' WHERE Passport__c IN ' +
            literalList(passports) +
            ' AND Destination__c IN ' +
            literalList(destinations);

        return executeVisaQuery(soql);
    }

    private static List<VisaWrapper.VisaRecordWrapper>
        executeVisaQuery(String soql) {

        String path =
            '/services/data/v60.0/query/?q=' +
            EncodingUtil.urlEncode(
                soql,
                'UTF-8'
            );

        List<VisaWrapper.VisaRecordWrapper> rows =
            new List<VisaWrapper.VisaRecordWrapper>();

        Integer pages = 0;

        while (path != null) {
            pages++;

            if (pages > 5) {
                throw new VisaWrapper.VisaServiceException(
                    'Provider response is too large for this check.'
                );
            }

            if (!path.startsWith('/services/data/')) {
                throw new VisaWrapper.VisaServiceException(
                    'Invalid provider continuation URL.'
                );
            }

            HttpRequest request =
                new HttpRequest();

            request.setEndpoint(ENDPOINT + path);
            request.setMethod('GET');
            request.setTimeout(20000);

            request.setHeader(
                'Accept',
                'application/json'
            );

            request.setHeader(
                'Content-Type',
                'application/json'
            );

            // Named Credential supplies the Bearer token.
            HttpResponse response =
                new Http().send(request);

            if (response.getStatusCode() != 200) {
                throw new VisaWrapper.VisaServiceException(
                    'Visa API HTTP ' +
                    response.getStatusCode() +
                    '.'
                );
            }

            VisaWrapper.ExternalQueryResponse page =
                parseResponse(
                    response.getBody()
                );

            rows.addAll(page.records);

            path = page.done
                ? null
                : page.nextRecordsUrl;
        }

        return rows;
    }

    private static VisaWrapper.ExternalQueryResponse
        parseResponse(String body) {

        Map<String, Object> payload =
            (Map<String, Object>)
            JSON.deserializeUntyped(body);

        if (
            payload == null ||
            !payload.containsKey('records') ||
            !payload.containsKey('done')
        ) {
            throw new VisaWrapper.VisaServiceException(
                'Invalid visa API response.'
            );
        }

        VisaWrapper.ExternalQueryResponse result =
            new VisaWrapper.ExternalQueryResponse();

        result.totalSize =
            (Integer) payload.get('totalSize');

        result.done =
            (Boolean) payload.get('done');

        result.nextRecordsUrl =
            (String) payload.get('nextRecordsUrl');

        result.records =
            new List<VisaWrapper.VisaRecordWrapper>();

        if (
            result.totalSize == null ||
            result.totalSize < 0 ||
            result.done == null
        ) {
            throw new VisaWrapper.VisaServiceException(
                'Provider response metadata is incomplete.'
            );
        }

        if (
            !result.done &&
            String.isBlank(result.nextRecordsUrl)
        ) {
            throw new VisaWrapper.VisaServiceException(
                'Provider pagination is incomplete.'
            );
        }

        List<Object> records =
            (List<Object>) payload.get('records');

        if (records == null) {
            throw new VisaWrapper.VisaServiceException(
                'Provider records are missing.'
            );
        }

        for (Object raw : records) {
            Map<String, Object> fields =
                (Map<String, Object>) raw;

            if (fields == null) {
                throw new VisaWrapper.VisaServiceException(
                    'Invalid provider record.'
                );
            }

            VisaWrapper.VisaRecordWrapper row =
                new VisaWrapper.VisaRecordWrapper();

            row.Passport_c = isoCode(
                (String) fields.get('Passport__c')
            );

            row.Destination_c = isoCode(
                (String) fields.get('Destination__c')
            );

            row.Visa_Required_c =
                (Boolean) fields.get('Visa_Required__c');

            row.Visa_Type_c =
                (String) fields.get('Visa_Type__c');

            row.Allowed_Stay_c =
                (String) fields.get('Allowed_Stay__c');

            row.Notes_c =
                (String) fields.get('Notes__c');

            if (
                row.Passport_c == null ||
                row.Destination_c == null
            ) {
                throw new VisaWrapper.VisaServiceException(
                    'Provider rule contains an invalid ' +
                    'passport or destination code.'
                );
            }

            // Allowed stay remains text, including "Unlimited".
            // The REST attributes object is intentionally ignored.
            result.records.add(row);
        }

        return result;
    }

    public static Map<Id, VisaWrapper.Snapshot>
        loadSnapshots(Set<Id> ids) {

        Map<Id, VisaWrapper.Snapshot> states =
            new Map<Id, VisaWrapper.Snapshot>();

        Set<Id> contacts = new Set<Id>();

        // Static local SOQL avoids dynamic query binding errors.
        for (Opportunity booking : [
            SELECT Id, Name, AccountId,
                   Traveler__c, Return_Date__c,
                   Traveler__r.FirstName,
                   Traveler__r.Email,
                   Traveler__r.HasOptedOutOfEmail,
                   Visa_Check_Request_Id__c
            FROM Opportunity
            WHERE Id IN :ids
            WITH USER_MODE
        ]) {
            VisaWrapper.Snapshot state =
                new VisaWrapper.Snapshot();

            state.booking = booking;

            state.sources.add(
                'booking|' +
                booking.Traveler__c +
                '|' +
                booking.Return_Date__c
            );

            states.put(booking.Id, state);

            if (booking.Traveler__c != null) {
                contacts.add(
                    booking.Traveler__c
                );
            }
        }

        loadPassports(states, contacts);

        for (OpportunityLineItem line : [
            SELECT Id, OpportunityId,
                   PricebookEntry.Product2.Destination__c
            FROM OpportunityLineItem
            WHERE OpportunityId IN :ids
            WITH USER_MODE
        ]) {
            VisaWrapper.Snapshot state =
                states.get(line.OpportunityId);

            if (state == null) {
                continue;
            }

            String raw =
                line.PricebookEntry.Product2.Destination__c;

            String code =
                destinationCountry(raw);

            if (
                code == null &&
                String.isNotBlank(raw)
            ) {
                code = destinationCountry(
                    destinationLabel(raw)
                );
            }

            state.sources.add(
                'product|' +
                line.Id +
                '|' +
                raw +
                '|' +
                code
            );

            if (code == null) {
                state.missingDestination = true;
            } else {
                state.destinations.add(code);
            }
        }

        return states;
    }

    public static void loadPassports(
        Map<Id, VisaWrapper.Snapshot> states,
        Set<Id> contacts
    ) {
        Map<Id, List<Passport__c>> byContact =
            new Map<Id, List<Passport__c>>();

        if (!contacts.isEmpty()) {
            for (Passport__c passport : [
                SELECT Id, Contact__c,
                       Passport_Issue_Country__c,
                       Passport_Expiry_Date__c
                FROM Passport__c
                WHERE Contact__c IN :contacts
                  AND Primary_Passport__c = true
                WITH USER_MODE
            ]) {
                if (
                    !byContact.containsKey(
                        passport.Contact__c
                    )
                ) {
                    byContact.put(
                        passport.Contact__c,
                        new List<Passport__c>()
                    );
                }

                byContact.get(
                    passport.Contact__c
                ).add(passport);
            }
        }

        for (
            VisaWrapper.Snapshot state :
            states.values()
        ) {
            if (
                state.booking.Traveler__c == null
            ) {
                state.problem =
                    'Select a Traveler Contact on the Booking.';

                continue;
            }

            List<Passport__c> matches =
                byContact.get(
                    state.booking.Traveler__c
                );

            if (
                matches == null ||
                matches.isEmpty()
            ) {
                state.problem =
                    'No primary Passport exists for this Traveler.';

                continue;
            }

            for (Passport__c passport : matches) {
                state.sources.add(
                    'passport|' +
                    passport.Id +
                    '|' +
                    passport.Passport_Issue_Country__c +
                    '|' +
                    passport.Passport_Expiry_Date__c
                );
            }

            if (matches.size() != 1) {
                state.problem =
                    'Select exactly one primary Passport ' +
                    'for this Traveler.';

                continue;
            }

            state.passportId = matches[0].Id;

            state.expiry =
                matches[0].Passport_Expiry_Date__c;

            // Label Lebanon / API value LB.
            // Apex reads LB.
            state.country = isoCode(
                matches[0].Passport_Issue_Country__c
            );

            if (state.country == null) {
                state.problem =
                    'Passport Issue Country requires an ISO-2 ' +
                    'API value, for example Lebanon = LB.';
            }
        }
    }

    public static VisaWrapper.VisaValidationResult evaluate(
        VisaWrapper.Snapshot state,
        List<VisaWrapper.VisaRecordWrapper> rows,
        String failure
    ) {
        Boolean pending =
            state.country == null ||
            state.destinations.isEmpty() ||
            state.missingDestination ||
            failure != null;

        // The API Boolean determines the visa requirement.
        Boolean requiresVisa = false;

        List<String> notes =
            new List<String>();

        if (state.problem != null) {
            notes.add(state.problem);
        }

        if (state.destinations.isEmpty()) {
            notes.add(
                'No Product destination is available.'
            );
        }

        if (state.missingDestination) {
            notes.add(
                'A Product destination is missing or ' +
                'cannot be mapped to a country.'
            );
        }

        if (failure != null) {
            notes.add(failure);
        }

        List<String> destinations =
            new List<String>(
                state.destinations
            );

        destinations.sort();

        if (
            failure == null &&
            state.country != null
        ) {
            for (String destination : destinations) {
                List<VisaWrapper.VisaRecordWrapper> matches =
                    new List<VisaWrapper.VisaRecordWrapper>();

                for (
                    VisaWrapper.VisaRecordWrapper row :
                    rows
                ) {
                    if (
                        row.Passport_c == state.country &&
                        row.Destination_c == destination
                    ) {
                        matches.add(row);
                    }
                }

                if (
                    matches.size() != 1 ||
                    matches[0].Visa_Required_c == null
                ) {
                    pending = true;

                    notes.add(
                        state.country +
                        ' -> ' +
                        destination +
                        ': missing, duplicate, or incomplete visa rule.'
                    );

                    continue;
                }

                VisaWrapper.VisaRecordWrapper row =
                    matches[0];

                if (row.Visa_Required_c) {
                    requiresVisa = true;
                }

                notes.add(
                    state.country +
                    ' -> ' +
                    destination +
                    ': ' +
                    (
                        row.Visa_Required_c
                        ? 'Visa Required'
                        : 'Visa Free'
                    ) +
                    '\nVisa type: ' +
                    display(row.Visa_Type_c) +
                    '\nAllowed stay: ' +
                    display(row.Allowed_Stay_c) +
                    '\nNotes: ' +
                    display(row.Notes_c)
                );
            }
        }

        VisaWrapper.VisaValidationResult result =
            new VisaWrapper.VisaValidationResult();

        result.visaStatus = pending
            ? 'Pending Review'
            : (
                requiresVisa
                ? 'Visa Required'
                : 'Visa Free'
            );

        result.requirements =
            String.join(notes, '\n\n');

        result.passportRecordId =
            state.passportId;

        result.passportCountry =
            state.country;

        result.passportExpiryDate =
            state.expiry;

        result.passportValid =
            state.expiry != null &&
            state.booking.Return_Date__c != null &&
            state.expiry >= sixMonthsAfter(
                state.booking.Return_Date__c
            );

        // API requirements do not prove an issued visa exists.
        result.isAllowed =
            result.visaStatus == 'Visa Free' &&
            result.passportValid;

        result.blockReason = '';

        if (!result.passportValid) {
            result.blockReason =
                'Primary Passport must be valid for six months ' +
                'after the Return Date.';
        } else if (
            result.visaStatus == 'Pending Review'
        ) {
            result.blockReason =
                'Visa requirements are incomplete or unavailable.';
        } else if (
            result.visaStatus == 'Visa Required'
        ) {
            result.blockReason =
                'Visa required. Issued-visa evidence needs ' +
                'specialist approval.';
        }

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String>
        getVisaContextFromOpportunity(
            Id opportunityId
        ) {

        VisaWrapper.Snapshot state =
            loadOne(opportunityId);

        List<String> destinations =
            new List<String>(
                state.destinations
            );

        destinations.sort();

        Map<String, String> result =
            new Map<String, String>{
                'accountId' =>
                    state.booking.AccountId == null
                    ? null
                    : String.valueOf(
                        state.booking.AccountId
                    ),
                'travelerId' =>
                    state.booking.Traveler__c == null
                    ? null
                    : String.valueOf(
                        state.booking.Traveler__c
                    ),
                'passportRecordId' =>
                    state.passportId == null
                    ? null
                    : String.valueOf(
                        state.passportId
                    ),
                'passport' => state.country,
                'passportProblem' => state.problem,
                'destinations' =>
                    String.join(destinations, ',')
            };

        if (destinations.size() == 1) {
            result.put(
                'destination',
                destinations[0]
            );
        }

        return result;
    }

    @AuraEnabled
    public static VisaWrapper.VisaValidationResult
        validateTravelCompliance(
            Id opportunityId
        ) {

        VisaWrapper.Snapshot state =
            loadOne(opportunityId);

        List<VisaWrapper.VisaRecordWrapper> rules =
            new List<VisaWrapper.VisaRecordWrapper>();

        String failure;

        try {
            if (
                state.country != null &&
                !state.destinations.isEmpty()
            ) {
                rules = queryRules(
                    new Set<String>{
                        state.country
                    },
                    state.destinations
                );
            }
        } catch (Exception error) {
            failure =
                'Visa API check failed. Request another check.';
        }

        return evaluate(
            state,
            rules,
            failure
        );
    }

    private static VisaWrapper.Snapshot loadOne(
        Id opportunityId
    ) {
        if (opportunityId == null) {
            throw new VisaWrapper.VisaServiceException(
                'Booking ID is required.'
            );
        }

        Set<Id> ids = new Set<Id>{
            opportunityId
        };

        Map<Id, VisaWrapper.Snapshot> states =
            loadSnapshots(ids);

        if (
            !states.containsKey(opportunityId)
        ) {
            throw new VisaWrapper.VisaServiceException(
                'Booking is unavailable.'
            );
        }

        return states.get(opportunityId);
    }

    private static String literalList(
        Set<String> codes
    ) {
        List<String> quoted =
            new List<String>();

        for (String value : codes) {
            String code = isoCode(value);

            if (code == null) {
                throw new VisaWrapper.VisaServiceException(
                    'Invalid country code.'
                );
            }

            quoted.add(
                '\'' + code + '\''
            );
        }

        quoted.sort();

        return '(' +
            String.join(quoted, ',') +
            ')';
    }

    public static String signature(
        VisaWrapper.Snapshot state
    ) {
        List<String> parts =
            new List<String>();

        parts.addAll(state.sources);
        parts.sort();

        parts.add(
            'problem|' + state.problem
        );

        return EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(
                    String.join(parts, '\n')
                )
            )
        );
    }

    private static String destinationLabel(
        String raw
    ) {
        for (
            Schema.PicklistEntry entry :
            Product2.Destination__c
                .getDescribe()
                .getPicklistValues()
        ) {
            if (entry.getValue() == raw) {
                return entry.getLabel();
            }
        }

        return raw;
    }

    public static String destinationCountry(
        String raw
    ) {
        if (String.isBlank(raw)) {
            return null;
        }

        String value =
            raw.trim().toUpperCase();

        String direct = isoCode(value);

        if (direct != null) {
            return direct;
        }

        // Location conversions only.
        // Visa requirements are always retrieved from the API.
        Map<String, String> airports =
            new Map<String, String>{
                'BEY' => 'LB',
                'NCE' => 'FR',
                'CDG' => 'FR',
                'ORY' => 'FR',
                'FCO' => 'IT',
                'MXP' => 'IT',
                'ACC' => 'GH',
                'LHR' => 'GB',
                'LGW' => 'GB',
                'DXB' => 'AE',
                'AUH' => 'AE',
                'JFK' => 'US'
            };

        Map<String, String> names =
            new Map<String, String>{
                'LEBANON' => 'LB',
                'FRANCE' => 'FR',
                'ITALY' => 'IT',
                'GHANA' => 'GH',
                'UNITED KINGDOM' => 'GB',
                'UNITED STATES' => 'US',
                'UNITED STATES OF AMERICA' => 'US',
                'UNITED ARAB EMIRATES' => 'AE'
            };

        if (names.containsKey(value)) {
            return names.get(value);
        }

        String airportCountry;
        String namedCountry;

        if (
            value.length() >= 3 &&
            (
                value.length() == 3 ||
                value.substring(3, 4) == ' ' ||
                value.substring(3, 4) == '-'
            )
        ) {
            airportCountry = airports.get(
                value.substring(0, 3)
            );
        }

        Integer comma =
            value.lastIndexOf(',');

        if (comma >= 0) {
            String suffix =
                value.substring(comma + 1).trim();

            namedCountry =
                isoCode(suffix);

            if (namedCountry == null) {
                namedCountry =
                    names.get(suffix);
            }
        }

        if (
            airportCountry != null &&
            namedCountry != null &&
            airportCountry != namedCountry
        ) {
            return null;
        }

        return namedCountry != null
            ? namedCountry
            : airportCountry;
    }

    public static String isoCode(
        String value
    ) {
        if (String.isBlank(value)) {
            return null;
        }

        String code =
            value.trim().toUpperCase();

        return Pattern.matches(
            '[A-Z]{2}',
            code
        ) ? code : null;
    }

    public static Date sixMonthsAfter(
        Date value
    ) {
        Date target =
            value.addMonths(6);

        if (
            value.day() ==
            Date.daysInMonth(
                value.year(),
                value.month()
            )
        ) {
            target = Date.newInstance(
                target.year(),
                target.month(),
                Date.daysInMonth(
                    target.year(),
                    target.month()
                )
            );
        }

        return target;
    }

    public static String fit(
        String value
    ) {
        if (value == null) {
            return '';
        }

        Integer capacity =
            Opportunity.Visa_Requirements__c
                .getDescribe()
                .getLength();

        return value.length() > capacity
            ? value.substring(0, capacity)
            : value;
    }

    private static String display(
        String value
    ) {
        return String.isBlank(value)
            ? '-'
            : value;
    }
}
