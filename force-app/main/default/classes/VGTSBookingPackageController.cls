public with sharing class VGTSBookingPackageController {


 @AuraEnabled(cacheable=true)
public static List<Map<String, Object>> getTravelPackages(Id bookingId) {
    if (bookingId == null) {
        throw new AuraHandledException('Open an Opportunity to view its products.');
    }


    Opportunity booking = [
        SELECT Id, Pricebook2Id
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
    ];


    if (booking.Pricebook2Id == null) {
        throw new AuraHandledException(
            'Assign the correct Price Book to this Opportunity first.'
        );
    }


    Id pricebookId = booking.Pricebook2Id;
 //   String currencyCode = booking.CurrencyIsoCode;


    Pricebook2 pricebook = [
        SELECT IsActive
        FROM Pricebook2
        WHERE Id = :pricebookId
        LIMIT 1
    ];


    if (!pricebook.IsActive) {
        throw new AuraHandledException('The Opportunity Price Book is inactive.');
    }


    Map<String, Schema.SObjectField> productFields =
        Schema.SObjectType.Product2.fields.getMap();


    List<String> fields = new List<String>{
        'Id', 'Product2Id', 'UnitPrice',
        'Product2.Name', 'Product2.Description'
    };


    for (String fieldName : new List<String>{
        'Destination__c', 'Departure_Airport__c', 'Arrival_Airport__c',
        'Origin__c', 'Package_Type__c', 'Flight_Type__c',
        'Cabin_Class__c', 'Departure_Date__c', 'Return_Date__c',
        'Package_Description__c', 'Supplier__c', 'Supplier_Name__c'
    }) {
        if (productFields.containsKey(fieldName)) {
            fields.add('Product2.' + fieldName);
        }
    }


    String soql =
        'SELECT ' + String.join(fields, ', ') +
        ' FROM PricebookEntry' +
        ' WHERE Pricebook2Id = :pricebookId' +
        ' AND IsActive = true' +
        ' AND Product2.IsActive = true' +
        ' ORDER BY Product2.Name';


    List<PricebookEntry> entries = Database.query(soql);


    Set<Id> productIds = new Set<Id>();
    for (PricebookEntry entry : entries) {
        productIds.add(entry.Product2Id);
    }


    Map<Id, String> imageUrls = new Map<Id, String>();


    if (!productIds.isEmpty()) {
        for (ContentDocumentLink linkRecord : [
            SELECT LinkedEntityId,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :productIds
        ]) {
            if (!imageUrls.containsKey(linkRecord.LinkedEntityId)
                && linkRecord.ContentDocument.LatestPublishedVersionId != null) {
                imageUrls.put(
                    linkRecord.LinkedEntityId,
                    '/sfc/servlet.shepherd/version/download/' +
                    linkRecord.ContentDocument.LatestPublishedVersionId
                );
            }
        }
    }


    List<Map<String, Object>> results = new List<Map<String, Object>>();


    for (PricebookEntry entry : entries) {
        Product2 product = entry.Product2;
        Map<String, Object> item = new Map<String, Object>();


        item.put('id', entry.Product2Id);
        item.put('name', product.Name);
        item.put('description', firstValue(product, new List<String>{
            'Package_Description__c', 'Description'
        }));
        item.put('destination', firstValue(product, new List<String>{
            'Destination__c'
        }));
        item.put('departureAirport', firstValue(product, new List<String>{
            'Departure_Airport__c', 'Origin__c'
        }));
        item.put('arrivalAirport', firstValue(product, new List<String>{
            'Arrival_Airport__c'
        }));
        item.put('origin', firstValue(product, new List<String>{
            'Origin__c'
        }));
        item.put('packageType', firstValue(product, new List<String>{
            'Package_Type__c'
        }));
        item.put('flightType', firstValue(product, new List<String>{
            'Flight_Type__c'
        }));
        item.put('cabinClass', firstValue(product, new List<String>{
            'Cabin_Class__c'
        }));
        item.put('departureDate', firstValue(product, new List<String>{
            'Departure_Date__c'
        }));
        item.put('arrivalDate', firstValue(product, new List<String>{
            'Return_Date__c'
        }));
        item.put('supplier', firstValue(product, new List<String>{
            'Supplier__c', 'Supplier_Name__c'
        }));


        // The Price Book Entry is the price source.
        item.put('basePrice', entry.UnitPrice);
        item.put('price', entry.UnitPrice);
    //    item.put('currencyCode', currencyCode);
        item.put('imageUrl', imageUrls.get(entry.Product2Id));


        results.add(item);
    }


    return results;
}



    private static Object firstValue(SObject record, List<String> fieldNames) {
        Map<String, Schema.SObjectField> availableFields =
            record.getSObjectType().getDescribe().fields.getMap();


        for (String fieldName : fieldNames) {
            if (availableFields.containsKey(fieldName)) {
                Object value = record.get(fieldName);
                if (value != null && String.valueOf(value).trim() != '') {
                    return value;
                }
            }
        }
        return null;
    }


    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return 0;
        }


        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return 0;
        }
    }


    private static void putIfAvailable(
        SObject record,
        String fieldName,
        Object value
    ) {
        if (value == null) {
            return;
        }


        Map<String, Schema.SObjectField> availableFields =
            record.getSObjectType().getDescribe().fields.getMap();


        if (availableFields.containsKey(fieldName)) {
            record.put(fieldName, value);
        }
    }


@AuraEnabled
public static Integer saveBookingServices(
    Id bookingId,
    List<Map<String, Object>> selectedServices
) {
    if (bookingId == null) {
        throw new AuraHandledException('Booking record ID is missing.');
    }
    if (selectedServices == null || selectedServices.isEmpty()) {
        throw new AuraHandledException('Add at least one travel service.');
    }


    Opportunity booking = [
        SELECT Id, Pricebook2Id, CurrencyIsoCode
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
        FOR UPDATE
    ];


    if (booking.Pricebook2Id == null) {
        throw new AuraHandledException(
            'Assign the correct Price Book to this Opportunity first.'
        );
    }


    Id pricebookId = booking.Pricebook2Id;
   // String currencyCode = booking.CurrencyIsoCode;


    Pricebook2 pricebook = [
        SELECT IsActive
        FROM Pricebook2
        WHERE Id = :pricebookId
        LIMIT 1
    ];
    if (!pricebook.IsActive) {
        throw new AuraHandledException('The Opportunity Price Book is inactive.');
    }


    Set<Id> productIds = new Set<Id>();
    List<Id> selectedProductIds = new List<Id>();


    for (Map<String, Object> item : selectedServices) {
        if (item == null) {
            throw new AuraHandledException('A selected service is empty.');
        }


        Object rawId = item.get('productId');
        if (rawId == null) {
            rawId = item.get('packageId');
        }
        if (rawId == null) {
            throw new AuraHandledException('A service is missing its Product ID.');
        }


        Id productId;
        try {
            productId = (Id) String.valueOf(rawId);
        } catch (Exception ex) {
            throw new AuraHandledException('A service has an invalid Product ID.');
        }


        if (productId.getSObjectType() != Product2.SObjectType) {
            throw new AuraHandledException('A service ID is not a Product record.');
        }


        selectedProductIds.add(productId);
        productIds.add(productId);
    }


    Boolean hasPackageType = Schema.SObjectType.Product2
        .fields.getMap().containsKey('Package_Type__c');


    String soql =
        'SELECT Id, Product2Id, UnitPrice' +
        (hasPackageType ? ', Product2.Package_Type__c' : '') +
        ' FROM PricebookEntry' +
        ' WHERE Pricebook2Id = :pricebookId' +
   //     ' AND CurrencyIsoCode = :currencyCode' +
        ' AND Product2Id IN :productIds' +
        ' AND IsActive = true' +
        ' AND Product2.IsActive = true';


    Map<Id, PricebookEntry> entryByProduct = new Map<Id, PricebookEntry>();
    for (PricebookEntry entry : Database.query(soql)) {
        entryByProduct.put(entry.Product2Id, entry);
    }


    List<OpportunityLineItem> lines = new List<OpportunityLineItem>();


    for (Integer i = 0; i < selectedServices.size(); i++) {
        Map<String, Object> item = selectedServices[i];
        PricebookEntry entry = entryByProduct.get(selectedProductIds[i]);


        if (entry == null) {
            throw new AuraHandledException(
                'A selected product has no active price in this ' +
                'Opportunity Price Book and currency.'
            );
        }


        Decimal quantity = readDecimal(item.get('quantity'));
        if (quantity == null) {
            quantity = 1;
        }
        if (quantity <= 0) {
            throw new AuraHandledException('Quantity must be greater than zero.');
        }


        Decimal unitPrice = entry.UnitPrice;
        String packageType = '';


        if (hasPackageType
            && entry.Product2.get('Package_Type__c') != null) {
            packageType = String.valueOf(
                entry.Product2.get('Package_Type__c')
            ).toLowerCase();
        }


        Boolean isHotel = packageType.contains('hotel')
            || packageType.contains('accommodation');


        Integer rooms = 1;
        Integer nights = 1;


        if (isHotel) {
            Decimal roomValue = readDecimal(item.get('rooms'));
            Decimal nightValue = readDecimal(item.get('nights'));


            if (roomValue != null
                && (roomValue < 1 || roomValue != roomValue.intValue())) {
                throw new AuraHandledException(
                    'Number of rooms must be a whole number greater than zero.'
                );
            }
            if (nightValue != null
                && (nightValue < 1 || nightValue != nightValue.intValue())) {
                throw new AuraHandledException(
                    'Number of nights must be a whole number greater than zero.'
                );
            }


            rooms = roomValue == null ? 1 : roomValue.intValue();
            nights = nightValue == null ? 1 : nightValue.intValue();


            unitPrice += ((rooms - 1) * 50) + ((nights - 1) * 30);
        }


        // Detect a price change since the catalogue was loaded.
        Decimal displayedPrice = readDecimal(item.get('price'));
        if (displayedPrice != null
            && displayedPrice.setScale(2) != unitPrice.setScale(2)) {
            throw new AuraHandledException(
                'A selected price has changed. Refresh the page and add ' +
                'the service again.'
            );
        }


        OpportunityLineItem line = new OpportunityLineItem(
            OpportunityId = booking.Id,
            Product2Id = entry.Product2Id, 
            Quantity = quantity,
            UnitPrice = unitPrice
        );


        if (isHotel) {
            line.Description =
                String.valueOf(rooms) + ' room(s), ' +
                String.valueOf(nights) + ' night(s)';
        }


        lines.add(line);
    }


    insert lines;
    return lines.size();
}


private static Decimal readDecimal(Object value) {
    if (value == null || String.isBlank(String.valueOf(value))) {
        return null;
    }


    try {
        return Decimal.valueOf(String.valueOf(value));
    } catch (Exception ex) {
        return null;
    }
}


@AuraEnabled
public static Id savePayment(
    Id bookingId,
    Decimal amount,
    String method,
    Date paymentDate,
    String status
) {
    if (bookingId == null) {
        throw new AuraHandledException(
            'Booking record ID is missing.'
        );
    }


    if (amount == null || amount <= 0) {
        throw new AuraHandledException(
            'Enter a valid payment amount.'
        );
    }


    if (String.isBlank(method)) {
        throw new AuraHandledException(
            'Select a payment method.'
        );
    }


    // Validate that the booking exists.
    Opportunity booking = [
        SELECT Id
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
    ];


    Payment__c paymentRecord = new Payment__c();


    Map<String, Schema.SObjectField> paymentFields =
        Schema.SObjectType.Payment__c.fields.getMap();


    if (!paymentFields.containsKey('Booking__c')) {
        throw new AuraHandledException(
            'Create Payment__c.Booking__c as a Lookup to Opportunity.'
        );
    }


    paymentRecord.put('Booking__c', booking.Id);
    paymentRecord.put('Amount__c', amount);
    paymentRecord.put('Method__c', method);
    paymentRecord.put(
        'Payment_Date__c',
        paymentDate == null ? Date.today() : paymentDate
    );
    paymentRecord.put(
        'Status__c',
        String.isBlank(status) ? 'Pending' : status
    );


    insert paymentRecord;
    return paymentRecord.Id;
}


/**
 * Creates one Quote from the saved Opportunity Products.
 * Call this method only when the user explicitly requests a quote.
 */
@AuraEnabled
public static Id createBookingQuote(Id bookingId) {
    if (bookingId == null) {
        throw new AuraHandledException(
            'Booking record ID is missing.'
        );
    }


    Opportunity booking = [
        SELECT Id, Name, Pricebook2Id
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
        FOR UPDATE
    ];


    if (booking.Pricebook2Id == null) {
        throw new AuraHandledException(
            'Assign a Price Book to the booking before creating a quote.'
        );
    }


    List<OpportunityLineItem> opportunityLines = [
        SELECT Id, PricebookEntryId, Quantity, UnitPrice
        FROM OpportunityLineItem
        WHERE OpportunityId = :booking.Id
    ];


    if (opportunityLines.isEmpty()) {
        throw new AuraHandledException(
            'Save at least one booking service before creating a quote.'
        );
    }


    Quote quoteRecord = new Quote();
    quoteRecord.Name = 'Travel Quote - ' + booking.Name;
    quoteRecord.OpportunityId = booking.Id;
    quoteRecord.Pricebook2Id = booking.Pricebook2Id;
    quoteRecord.Status = 'Draft';


    insert quoteRecord;


    List<QuoteLineItem> quoteLines = new List<QuoteLineItem>();


    for (OpportunityLineItem opportunityLine : opportunityLines) {
        quoteLines.add(new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = opportunityLine.PricebookEntryId,
            Quantity = opportunityLine.Quantity,
            UnitPrice = opportunityLine.UnitPrice
        ));
    }


    insert quoteLines;
    return quoteRecord.Id;
}


    @AuraEnabled(cacheable=true)
    public static List<OpportunityLineItem> getBookingServices() {
        return [
            SELECT Id, Name
            FROM OpportunityLineItem
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
    }


    // @AuraEnabled
    // public static Id savePayment(
    //     Id bookingId,
    //     Decimal amount,
    //     String method,
    //     Date paymentDate,
    //     String status
    // ) {
    //     if (bookingId == null) {
    //         throw new AuraHandledException('Booking record ID is missing.');
    //     }


    //     if (amount == null || amount <= 0) {
    //         throw new AuraHandledException('Enter a valid payment amount.');
    //     }


    //     Payment__c paymentRecord = new Payment__c();


    //     Map<String, Schema.SObjectField> paymentFields =
    //         Schema.SObjectType.Payment__c.fields.getMap();


    //     if (paymentFields.containsKey('Booking__c')) {
    //         paymentRecord.put('OpportunityLineItem', bookingId);
    //     } else if (paymentFields.containsKey('OpportunityLineItem')) {
    //         paymentRecord.put('OpportunityLineItem', bookingId);
    //     }


    //     paymentRecord.put('Amount__c', amount);
    //     paymentRecord.put('Method__c', method);
    //     paymentRecord.put('Payment_Date__c',
    //         paymentDate == null ? Date.today() : paymentDate);
    //     paymentRecord.put('Status__c',
    //         String.isBlank(status) ? 'Pending' : status);


    //     insert paymentRecord;
    //     return paymentRecord.Id;
    // }
}