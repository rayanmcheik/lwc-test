global with sharing class VisaController {

    private static final String ENDPOINT =
        'callout:Visa_Requirements_API';

    private static final String RULE_SELECT =
        'SELECT Passport__c, Destination__c, Visa_Required__c, ' +
        'Visa_Type__c, Allowed_Stay__c, Notes__c FROM Visa__c';

    // =====================================================
    // LOAD BOOKING, PASSPORT AND SAVED TRAVEL PRODUCTS
    // =====================================================

    public static Map<Id, VisaWrapper.Snapshot> loadSnapshots(
        Set<Id> ids
    ) {

        Map<Id, VisaWrapper.Snapshot> states =
            new Map<Id, VisaWrapper.Snapshot>();

        Set<Id> contacts = new Set<Id>();

        for (Opportunity booking : [
            SELECT Id, Name, AccountId,
                   Traveler__c,
                   Departure_Date__c,
                   Return_Date__c,
                   Traveler__r.FirstName,
                   Traveler__r.Email,
                   Traveler__r.HasOptedOutOfEmail,
                   Visa_Check_Request_ID__c
            FROM Opportunity
            WHERE Id IN :ids
        ]) {

            VisaWrapper.Snapshot state =
                new VisaWrapper.Snapshot();

            state.booking = booking;

            state.sources.add(
                'booking|' +
                booking.Traveler__c + '|' +
                booking.Departure_Date__c + '|' +
                booking.Return_Date__c
            );

            states.put(booking.Id, state);

            if (booking.Traveler__c != null) {
                contacts.add(booking.Traveler__c);
            }
        }

        loadPassports(states, contacts);

        // Read only saved products managed by VGTS.
        for (OpportunityLineItem line : [
            SELECT Id,
                   OpportunityId,
                   PricebookEntry.Product2Id,
                   PricebookEntry.Product2.Destination__c,
                   PricebookEntry.Product2.Package_Type__c
            FROM OpportunityLineItem
            WHERE OpportunityId IN :ids
            AND Booking_Service__c = true
        ]) {

            VisaWrapper.Snapshot state =
                states.get(line.OpportunityId);

            if (state == null) {
                continue;
            }

            String raw =
                line.PricebookEntry.Product2.Destination__c;

            String code = destinationCountry(raw);

            if (code == null && String.isNotBlank(raw)) {
                code = destinationCountry(destinationLabel(raw));
            }

            state.sources.add(
                'product|' +
                line.Id + '|' +
                line.PricebookEntry.Product2Id + '|' +
                raw + '|' +
                code + '|' +
                line.PricebookEntry.Product2.Package_Type__c
            );

            if (code == null) {
                state.missingDestination = true;
            } else {
                state.destinations.add(code);
            }
        }

        return states;
    }

    // =====================================================
    // LOAD PRIMARY PASSPORT
    // =====================================================

    public static void loadPassports(
        Map<Id, VisaWrapper.Snapshot> states,
        Set<Id> contacts
    ) {

        Map<Id, List<Passport__c>> byContact =
            new Map<Id, List<Passport__c>>();

        if (!contacts.isEmpty()) {

            for (Passport__c passport : [
                SELECT Id,
                       Contact__c,
                       Passport_Issue_Country__c,
                       Passport_Expiry_Date__c
                FROM Passport__c
                WHERE Contact__c IN :contacts
                AND Primary_Passport__c = true
            ]) {

                if (!byContact.containsKey(passport.Contact__c)) {
                    byContact.put(
                        passport.Contact__c,
                        new List<Passport__c>()
                    );
                }

                byContact.get(passport.Contact__c).add(passport);
            }
        }

        for (VisaWrapper.Snapshot state : states.values()) {

            if (state.booking.Traveler__c == null) {
                state.problem = 'Select a Traveler Contact on the Booking.';
                continue;
            }

            List<Passport__c> matches =
                byContact.get(state.booking.Traveler__c);

            if (matches == null || matches.isEmpty()) {
                state.problem = 'No primary Passport exists for this Traveler.';
                continue;
            }

            if (matches.size() != 1) {
                state.problem =
                    'Select exactly one primary Passport for this Traveler.';
                continue;
            }

            Passport__c passport = matches[0];

            state.passportId = passport.Id;
            state.expiry = passport.Passport_Expiry_Date__c;

            state.country = isoCode(
                passport.Passport_Issue_Country__c
            );

            state.sources.add(
                'passport|' +
                passport.Id + '|' +
                passport.Passport_Issue_Country__c + '|' +
                passport.Passport_Expiry_Date__c
            );

            if (state.country == null) {
                state.problem =
                    'Passport Issue Country must contain a valid ISO-2 country code, such as LB.';
            }
        }
    }

    // =====================================================
    // MANUAL VISA API QUERY
    // =====================================================

    public static List<VisaWrapper.VisaRecordWrapper> queryRules(
        Set<String> passports,
        Set<String> destinations
    ) {

        if (passports == null || passports.isEmpty() ||
            destinations == null || destinations.isEmpty()) {

            throw new VisaWrapper.VisaServiceException(
                'Passport and destination codes are required.'
            );
        }

        String soql = RULE_SELECT +
            ' WHERE Passport__c IN ' + literalList(passports) +
            ' AND Destination__c IN ' + literalList(destinations);

        return executeVisaQuery(soql);
    }

    private static List<VisaWrapper.VisaRecordWrapper> executeVisaQuery(
        String soql
    ) {

        String path =
            '/services/data/v60.0/query/?q=' +
            EncodingUtil.urlEncode(soql, 'UTF-8');

        List<VisaWrapper.VisaRecordWrapper> rows =
            new List<VisaWrapper.VisaRecordWrapper>();

        Integer pages = 0;

        while (path != null) {

            pages++;

            if (pages > 5) {
                throw new VisaWrapper.VisaServiceException(
                    'Visa API response is too large.'
                );
            }

            if (!path.startsWith('/services/data/')) {
                throw new VisaWrapper.VisaServiceException(
                    'Invalid API continuation URL.'
                );
            }

            HttpRequest request = new HttpRequest();

            request.setEndpoint(ENDPOINT + path);
            request.setMethod('GET');
            request.setTimeout(20000);
            request.setHeader('Accept', 'application/json');

            HttpResponse response =
                new Http().send(request);

            if (response.getStatusCode() != 200) {
                throw new VisaWrapper.VisaServiceException(
                    'Visa API HTTP ' +
                    response.getStatusCode()
                );
            }

            VisaWrapper.ExternalQueryResponse page =
                parseResponse(response.getBody());

            rows.addAll(page.records);

            path = page.done ? null : page.nextRecordsUrl;
        }

        return rows;
    }

    private static VisaWrapper.ExternalQueryResponse parseResponse(
        String body
    ) {

        Map<String, Object> payload =
            (Map<String, Object>)JSON.deserializeUntyped(body);

        if (payload == null ||
            !payload.containsKey('records') ||
            !payload.containsKey('done')) {

            throw new VisaWrapper.VisaServiceException(
                'Invalid Visa API response.'
            );
        }

        VisaWrapper.ExternalQueryResponse result =
            new VisaWrapper.ExternalQueryResponse();

        result.totalSize = (Integer)payload.get('totalSize');
        result.done = (Boolean)payload.get('done');
        result.nextRecordsUrl =
            (String)payload.get('nextRecordsUrl');

        result.records =
            new List<VisaWrapper.VisaRecordWrapper>();

        if (result.totalSize == null ||
            result.done == null) {

            throw new VisaWrapper.VisaServiceException(
                'Visa API response metadata is incomplete.'
            );
        }

        if (!result.done &&
            String.isBlank(result.nextRecordsUrl)) {

            throw new VisaWrapper.VisaServiceException(
                'Visa API pagination is incomplete.'
            );
        }

        List<Object> records =
            (List<Object>)payload.get('records');

        if (records == null) {
            throw new VisaWrapper.VisaServiceException(
                'Visa API records are missing.'
            );
        }

        for (Object raw : records) {

            Map<String, Object> fields =
                (Map<String, Object>)raw;

            VisaWrapper.VisaRecordWrapper row =
                new VisaWrapper.VisaRecordWrapper();

            row.Passport_c =
                isoCode((String)fields.get('Passport__c'));

            row.Destination_c =
                isoCode((String)fields.get('Destination__c'));

            row.Visa_Required_c =
                (Boolean)fields.get('Visa_Required__c');

            row.Visa_Type_c =
                (String)fields.get('Visa_Type__c');

            row.Allowed_Stay_c =
                (String)fields.get('Allowed_Stay__c');

            row.Notes_c =
                (String)fields.get('Notes__c');

            if (row.Passport_c == null ||
                row.Destination_c == null) {

                throw new VisaWrapper.VisaServiceException(
                    'Invalid passport or destination code in API record.'
                );
            }

            result.records.add(row);
        }

        return result;
    }

    // =====================================================
    // EVALUATE VISA REQUIREMENTS
    // =====================================================

    public static VisaWrapper.VisaValidationResult evaluate(
        VisaWrapper.Snapshot state,
        List<VisaWrapper.VisaRecordWrapper> rows,
        String failure
    ) {

        Boolean requiresVisa = false;

        Boolean pending =
            state.problem != null ||
            state.country == null ||
            state.destinations.isEmpty() ||
            state.missingDestination ||
            failure != null;

        List<String> notes = new List<String>();

        if (state.problem != null) {
            notes.add(state.problem);
        }

        if (state.destinations.isEmpty()) {
            notes.add('No saved destination was found.');
        }

        if (state.missingDestination) {
            notes.add('A product destination is missing or cannot be mapped.');
        }

        if (failure != null) {
            notes.add(failure);
        }

        List<String> destinations =
            new List<String>(state.destinations);

        destinations.sort();

        if (failure == null && state.country != null) {

            for (String destination : destinations) {

                List<VisaWrapper.VisaRecordWrapper> matches =
                    new List<VisaWrapper.VisaRecordWrapper>();

                for (VisaWrapper.VisaRecordWrapper row : rows) {

                    if (row.Passport_c == state.country &&
                        row.Destination_c == destination) {

                        matches.add(row);
                    }
                }

                if (matches.size() != 1 ||
                    matches[0].Visa_Required_c == null) {

                    pending = true;

                    notes.add(
                        state.country + ' -> ' + destination +
                        ': Missing, duplicate or incomplete visa rule.'
                    );

                    continue;
                }

                VisaWrapper.VisaRecordWrapper rule = matches[0];

                if (rule.Visa_Required_c) {
                    requiresVisa = true;
                }

                notes.add(
                    state.country + ' -> ' + destination +
                    ': ' +
                    (rule.Visa_Required_c ? 'Visa Required' : 'Visa Free') +
                    '\nVisa type: ' + display(rule.Visa_Type_c) +
                    '\nAllowed stay: ' + display(rule.Allowed_Stay_c) +
                    '\nNotes: ' + display(rule.Notes_c)
                );
            }
        }

        VisaWrapper.VisaValidationResult result =
            new VisaWrapper.VisaValidationResult();

        result.visaRequired = requiresVisa;

        result.visaStatus = pending
            ? 'Pending Review'
            : (requiresVisa ? 'Visa Required' : 'Visa Free');

        result.requirements = String.join(notes, '\n\n');

        result.passportRecordId = state.passportId;
        result.passportCountry = state.country;
        result.passportExpiryDate = state.expiry;

        result.passportValid =
            state.expiry != null &&
            state.booking.Return_Date__c != null &&
            state.expiry >= sixMonthsAfter(
                state.booking.Return_Date__c
            );

        result.isAllowed =
            result.visaStatus == 'Visa Free' &&
            result.passportValid;

        if (!result.passportValid) {
            result.blockReason =
                'Passport validity requirement is not satisfied.';
        } else if (pending) {
            result.blockReason =
                'Visa requirements are incomplete.';
        } else if (requiresVisa) {
            result.blockReason =
                'Visa approval is required before proceeding.';
        }

        return result;
    }

    // =====================================================
    // SIGNATURE - DETECT CHANGES
    // =====================================================

    public static String signature(
        VisaWrapper.Snapshot state
    ) {

        List<String> parts = new List<String>();

        parts.addAll(state.sources);
        parts.sort();

        parts.add('problem|' + state.problem);

        return EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(String.join(parts, '\n'))
            )
        );
    }

    // =====================================================
    // COUNTRY CONVERSION
    // =====================================================

    public static String isoCode(String value) {

        if (String.isBlank(value)) {
            return null;
        }

        String code = value.trim().toUpperCase();

        if (Pattern.matches('[A-Z]{2}', code)) {
            return code;
        }

        Map<String, String> countries =
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

        return countries.get(code);
    }

    public static String destinationCountry(String raw) {

        if (String.isBlank(raw)) {
            return null;
        }

        String value = raw.trim().toUpperCase();

        String direct = isoCode(value);

        if (direct != null) {
            return direct;
        }

        Map<String, String> names =
            new Map<String, String>{
                'LEBANON' => 'LB',
                'FRANCE' => 'FR',
                'ITALY' => 'IT',
                'GHANA' => 'GH',
                'UNITED KINGDOM' => 'GB',
                'UNITED STATES' => 'US',
                'UNITED ARAB EMIRATES' => 'AE'
            };

        return names.get(value);
    }

    private static String destinationLabel(String raw) {

        for (Schema.PicklistEntry entry :
            Product2.Destination__c.getDescribe().getPicklistValues()) {

            if (entry.getValue() == raw) {
                return entry.getLabel();
            }
        }

        return raw;
    }

    private static String literalList(Set<String> codes) {

        List<String> quoted = new List<String>();

        for (String value : codes) {

            String code = isoCode(value);

            if (code == null) {
                throw new VisaWrapper.VisaServiceException(
                    'Invalid country code.'
                );
            }

            quoted.add('\'' + code + '\'');
        }

        quoted.sort();

        return '(' + String.join(quoted, ',') + ')';
    }

    // =====================================================
    // PASSPORT VALIDITY
    // =====================================================

    public static Date sixMonthsAfter(Date value) {

        Date target = value.addMonths(6);

        if (value.day() ==
            Date.daysInMonth(value.year(), value.month())) {

            target = Date.newInstance(
                target.year(),
                target.month(),
                Date.daysInMonth(target.year(), target.month())
            );
        }

        return target;
    }

    public static String fit(String value) {

        if (value == null) {
            return '';
        }

        Integer capacity =
            Opportunity.Visa_Requirements__c.getDescribe().getLength();

        return value.length() > capacity
            ? value.substring(0, capacity)
            : value;
    }

    private static String display(String value) {
        return String.isBlank(value) ? '-' : value;
    }
}
