public with sharing class VGTSBookingPackageController {


    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getTravelPackages() {
        Map<String, Schema.SObjectField> productFields =
            Schema.SObjectType.Product2.fields.getMap();


        Set<String> selectedFields = new Set<String>{
            'Id', 'Name', 'Description', 'IsActive'
        };


        List<String> optionalFields = new List<String>{
            'Destination__c',
            'Departure_Airport__c',
            'Arrival_Airport__c',
            'Origin__c',
            'Package_Type__c',
            'Flight_Type__c',
            'Cabin_Class__c',
            'Departure_Date__c',
            'Return_Date__c',
            'Package_Description__c',
            'Supplier__c',
            'Supplier_Name__c',
            'Base_Price__c',
            'Supplier_Cost__c',
            'Cost__c',
            'Markup__c',
            'Agency_Markup__c',
            'Fees__c',
            'Taxes__c',
            'Selling_Price__c',
            'Retail_Price__c',
            'Price__c',
            'Active__c',
            'Is_Active__c'
        };


        for (String fieldName : optionalFields) {
            if (productFields.containsKey(fieldName)) {
                selectedFields.add(fieldName);
            }
        }


        List<String> fieldList = new List<String>();
        fieldList.addAll(selectedFields);


        String queryString =
            'SELECT ' + String.join(fieldList, ',') +
            ' FROM Product2 WHERE IsActive = true ORDER BY Name';


        List<SObject> products = Database.query(queryString);
        List<Map<String, Object>> results =
            new List<Map<String, Object>>();


        Set<Id> productIds = new Set<Id>();
        for (SObject product : products) {
            productIds.add((Id) product.get('Id'));
        }


        Map<Id, String> imageUrls = new Map<Id, String>();


        if (!productIds.isEmpty()) {
            for (ContentDocumentLink linkRecord : [
                SELECT LinkedEntityId,
                       ContentDocument.LatestPublishedVersionId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :productIds
            ]) {
                if (linkRecord.ContentDocument.LatestPublishedVersionId != null
                    && !imageUrls.containsKey(linkRecord.LinkedEntityId)) {
                    imageUrls.put(
                        linkRecord.LinkedEntityId,
                        '/sfc/servlet.shepherd/version/download/' +
                        linkRecord.ContentDocument.LatestPublishedVersionId
                    );
                }
            }
        }


        for (SObject product : products) {
            Map<String, Object> item = new Map<String, Object>();


            item.put('id', product.get('Id'));
            item.put('name', product.get('Name'));
            item.put('description', firstValue(product, new List<String>{
                'Package_Description__c', 'Description'
            }));


            item.put('destination',
                firstValue(product, new List<String>{'Destination__c'}));


            item.put('departureAirport',
                firstValue(product, new List<String>{
                    'Departure_Airport__c', 'Origin__c'
                }));


            item.put('arrivalAirport',
                firstValue(product, new List<String>{
                    'Arrival_Airport__c'
                }));


            item.put('origin',
                firstValue(product, new List<String>{'Origin__c'}));


            item.put('packageType',
                firstValue(product, new List<String>{'Package_Type__c'}));


            item.put('flightType',
                firstValue(product, new List<String>{'Flight_Type__c'}));


            item.put('cabinClass',
                firstValue(product, new List<String>{'Cabin_Class__c'}));


            item.put('departureDate',
                firstValue(product, new List<String>{'Departure_Date__c'}));


            item.put('arrivalDate',
                firstValue(product, new List<String>{'Return_Date__c'}));


            item.put('supplier',
                firstValue(product, new List<String>{
                    'Supplier__c', 'Supplier_Name__c'
                }));


            Decimal basePrice = toDecimal(firstValue(product, new List<String>{
                'Base_Price__c', 'Supplier_Cost__c', 'Cost__c',
                'Selling_Price__c', 'Retail_Price__c', 'Price__c'
            }));


            Decimal markup = toDecimal(firstValue(product, new List<String>{
                'Markup__c', 'Agency_Markup__c'
            }));


            Decimal fees = toDecimal(firstValue(product, new List<String>{
                'Fees__c'
            }));


            Decimal taxes = toDecimal(firstValue(product, new List<String>{
                'Taxes__c'
            }));


            Decimal sellingPrice = toDecimal(firstValue(product, new List<String>{
                'Selling_Price__c', 'Retail_Price__c', 'Price__c'
            }));


            if (sellingPrice == null || sellingPrice <= 0) {
                sellingPrice = (basePrice == null ? 0 : basePrice)
                    + (markup == null ? 0 : markup)
                    + (fees == null ? 0 : fees)
                    + (taxes == null ? 0 : taxes);
            }


            item.put('basePrice', basePrice == null ? 0 : basePrice);
            item.put('markup', markup == null ? 0 : markup);
            item.put('fees', fees == null ? 0 : fees);
            item.put('taxes', taxes == null ? 0 : taxes);
            item.put('price', sellingPrice == null ? 0 : sellingPrice);
            item.put('imageUrl', imageUrls.get((Id) product.get('Id')));


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
        throw new AuraHandledException(
            'Booking record ID is missing.'
        );
    }


    if (selectedServices == null || selectedServices.isEmpty()) {
        throw new AuraHandledException(
            'Please add at least one travel service.'
        );
    }


    Opportunity booking = [
        SELECT Id, Pricebook2Id, CurrencyIsoCode
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
        FOR UPDATE
    ];


    // Use the Standard Price Book if the booking has none.
    Id pricebookId = booking.Pricebook2Id;


    if (pricebookId == null) {
        Id standardPricebookId = Test.isRunningTest()
            ? Test.getStandardPricebookId()
            : [SELECT Id FROM Pricebook2
               WHERE IsStandard = true LIMIT 1].Id;


        Pricebook2 standardBook = [
            SELECT Id, IsActive
            FROM Pricebook2
            WHERE Id = :standardPricebookId
            LIMIT 1
        ];


        if (!standardBook.IsActive) {
            throw new AuraHandledException(
                'Activate the Standard Price Book first.'
            );
        }


        booking.Pricebook2Id = standardPricebookId;
        update booking;
        pricebookId = standardPricebookId;
    }


    Set<Id> productIds = new Set<Id>();


    for (Map<String, Object> item : selectedServices) {
        Object rawId = item.get('productId');


        if (rawId == null) {
            rawId = item.get('packageId');
        }


        if (rawId == null) {
            throw new AuraHandledException(
                'A selected service is missing its Product2 ID.'
            );
        }


        Id productId;


        try {
            productId = (Id) String.valueOf(rawId);
        } catch (Exception ex) {
            throw new AuraHandledException(
                'A selected service has an invalid product ID.'
            );
        }


        if (productId.getSObjectType() != Product2.SObjectType) {
            throw new AuraHandledException(
                'A selected service ID is not a Product2 record.'
            );
        }


        productIds.add(productId);
    }


    Map<Id, PricebookEntry> entryByProduct =
        new Map<Id, PricebookEntry>();


    for (PricebookEntry entry : [
        SELECT Id, Product2Id, UnitPrice, CurrencyIsoCode
        FROM PricebookEntry
        WHERE Pricebook2Id = :pricebookId
        AND Product2Id IN :productIds
        AND IsActive = true
    ]) {
        entryByProduct.put(entry.Product2Id, entry);
    }


    List<OpportunityLineItem> lines =
        new List<OpportunityLineItem>();


    for (Map<String, Object> item : selectedServices) {
        Id productId = (Id) String.valueOf(
            item.containsKey('productId')
                ? item.get('productId')
                : item.get('packageId')
        );


        PricebookEntry entry = entryByProduct.get(productId);


        if (entry == null) {
            throw new AuraHandledException(
                'A selected product has no active price-book entry. ' +
                'Add an active price for every selected product.'
            );
        }


        Decimal quantity = readDecimal(item.get('quantity'));
        if (quantity == null || quantity <= 0) {
            quantity = 1;
        }


        Decimal unitPrice = readDecimal(item.get('sellingPrice'));
        if (unitPrice == null) {
            unitPrice = readDecimal(item.get('price'));
        }
        if (unitPrice == null || unitPrice < 0) {
            unitPrice = entry.UnitPrice;
        }


        OpportunityLineItem line = new OpportunityLineItem(
            OpportunityId = booking.Id,
            PricebookEntryId = entry.Id,
            Quantity = quantity,
            UnitPrice = unitPrice
        );


        putIfAvailable(line, 'Service_Name__c', item.get('name'));
        putIfAvailable(line, 'Service_Type__c', item.get('serviceType'));
        putIfAvailable(line, 'Supplier__c', item.get('supplier'));
        putIfAvailable(line, 'Description__c', item.get('description'));
        putIfAvailable(line, 'Travel_Package__c', productId);
        putIfAvailable(line, 'Supplier_Cost__c', item.get('basePrice'));
        putIfAvailable(line, 'Selling_Price__c', unitPrice);
        putIfAvailable(line, 'Taxes__c', item.get('taxes'));
        putIfAvailable(line, 'Quantity__c', quantity);
        putIfAvailable(line, 'Hotel_Name__c', item.get('name'));
        putIfAvailable(line, 'Room_Category__c', item.get('roomCategory'));
        putIfAvailable(line, 'Meal_Plan__c', item.get('mealPlan'));
        putIfAvailable(line, 'Number_Of_Rooms__c', item.get('rooms'));
        putIfAvailable(line, 'Number_Of_Nights__c', item.get('nights'));


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