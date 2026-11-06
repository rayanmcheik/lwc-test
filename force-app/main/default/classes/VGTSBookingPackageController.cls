
public with sharing class VGTSBookingPackageController {

    private static final Decimal HOTEL_ROOM_FEE = 50;
    private static final Decimal HOTEL_NIGHT_FEE = 30;

    public class SavedServiceDTO {
        @AuraEnabled public Id lineId { get; set; }
        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String destination { get; set; }
        @AuraEnabled public String supplier { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Decimal basePrice { get; set; }
        @AuraEnabled public Integer rooms { get; set; }
        @AuraEnabled public Integer nights { get; set; }
        @AuraEnabled public String currencyCode { get; set; }
        @AuraEnabled public String imageUrl { get; set; }
    }

    // =====================================================
    // CATALOGUE
    // =====================================================

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getTravelPackages(
        Id bookingId
    ) {

        if (bookingId == null) {
            throw new AuraHandledException('Booking ID is required.');
        }

        Opportunity booking = [
            SELECT Id, Pricebook2Id, CurrencyIsoCode
            FROM Opportunity
            WHERE Id = :bookingId
            LIMIT 1
        ];

        if (booking.Pricebook2Id == null) {
            throw new AuraHandledException(
                'Assign a Price Book to this Booking first.'
            );
        }

        Id pricebookId = booking.Pricebook2Id;
        String currencyCode = booking.CurrencyIsoCode;

        List<PricebookEntry> entries = [
            SELECT Id, Product2Id, UnitPrice, CurrencyIsoCode,
                   Product2.Name, Product2.Description,
                   Product2.Destination__c,
                   Product2.Departure__c,
                   Product2.Arrival_Airport__c,
                   Product2.Package_Type__c,
                   Product2.Flight_Type__c,
                   Product2.Cabin_Class__c,
                   Product2.Supplier__c,
                   Product2.Departure_Date__c,
                   Product2.Return_Date__c
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
            AND CurrencyIsoCode = :currencyCode
            AND IsActive = true
            AND Product2.IsActive = true
            ORDER BY Product2.Name
        ];

        Set<Id> productIds = new Set<Id>();

        for (PricebookEntry entry : entries) {
            if (entry.Product2Id != null &&
                entry.Product2 != null &&
                String.isNotBlank(entry.Product2.Name) &&
                entry.UnitPrice != null) {
                productIds.add(entry.Product2Id);
            }
        }

        Map<Id, String> imageUrls = new Map<Id, String>();

        if (!productIds.isEmpty()) {
            for (ContentDocumentLink linkRecord : [
                SELECT LinkedEntityId,
                       ContentDocument.LatestPublishedVersionId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :productIds
            ]) {
                if (!imageUrls.containsKey(linkRecord.LinkedEntityId) &&
                    linkRecord.ContentDocument.LatestPublishedVersionId != null) {

                    imageUrls.put(
                        linkRecord.LinkedEntityId,
                        '/sfc/servlet.shepherd/version/download/' +
                        linkRecord.ContentDocument.LatestPublishedVersionId
                    );
                }
            }
        }

        List<Map<String, Object>> results =
            new List<Map<String, Object>>();

        for (PricebookEntry entry : entries) {

            Product2 product = entry.Product2;

            if (product == null ||
                String.isBlank(product.Name) ||
                entry.UnitPrice == null) {
                continue;
            }

            Map<String, Object> item = new Map<String, Object>();

            item.put('id', product.Id);
            item.put('name', product.Name);
            item.put('description', product.Description);
            item.put('destination', product.Destination__c);
            item.put('origin', product.Departure__c);
            item.put('departureAirport', product.Departure__c);
            item.put('arrivalAirport', product.Arrival_Airport__c);
            item.put('packageType', product.Package_Type__c);
            item.put('flightType', product.Flight_Type__c);
            item.put('cabinClass', product.Cabin_Class__c);
            item.put('supplier', product.Supplier__c);
            item.put('departureDate', product.Departure_Date__c);
            item.put('arrivalDate', product.Return_Date__c);
            item.put('basePrice', entry.UnitPrice);
            item.put('price', entry.UnitPrice);
            item.put('currencyCode', entry.CurrencyIsoCode);
            item.put('imageUrl', imageUrls.get(product.Id));

            results.add(item);
        }

        return results;
    }

    // =====================================================
    // CATEGORY HELPERS
    // =====================================================

    private static String normalizePackageType(String value) {

        String v = String.valueOf(
            value == null ? '' : value
        ).trim().toLowerCase();

        if (v.contains('air') ||
            v.contains('flight') ||
            v.contains('ticket')) {
            return 'Air_Tickets';
        }

        if (v.contains('hotel') ||
            v.contains('accommodation')) {
            return 'Hotels';
        }

        if (v.contains('ground') ||
            v.contains('transfer') ||
            v.contains('transport')) {
            return 'Ground';
        }

        return 'Ancillary';
    }

    private static Boolean isAirTicket(String value) {

        String v = String.valueOf(
            value == null ? '' : value
        ).toLowerCase();

        return v.contains('air') ||
            v.contains('flight') ||
            v.contains('ticket');
    }

    private static Boolean isHotel(String value) {

        String v = String.valueOf(
            value == null ? '' : value
        ).toLowerCase();

        return v.contains('hotel') ||
            v.contains('accommodation');
    }

    private static Decimal readDecimal(Object value) {

        if (value == null ||
            String.isBlank(String.valueOf(value))) {
            return null;
        }

        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }

    private static Integer readWholeNumber(
        Object value,
        Integer defaultValue
    ) {
        Decimal numericValue = readDecimal(value);

        if (numericValue == null) return defaultValue;

        if (numericValue < 1 || numericValue != numericValue.intValue()) {
            throw new AuraHandledException(
                'Hotel rooms and nights must be positive whole numbers.'
            );
        }

        return numericValue.intValue();
    }

    // =====================================================
    // RELOAD SAVED PRODUCTS
    // =====================================================

    @AuraEnabled(cacheable=true)
    public static List<SavedServiceDTO> getBookingServices(
        Id bookingId
    ) {

        List<SavedServiceDTO> results =
            new List<SavedServiceDTO>();

        if (bookingId == null) return results;

        List<OpportunityLineItem> lines = [
            SELECT Id, Quantity, UnitPrice, Description,
                   Booking_Service__c,
                   Hotel_Rooms__c, Hotel_Nights__c,
                   PricebookEntry.Product2Id,
                   PricebookEntry.Product2.Name,
                   PricebookEntry.Product2.Description,
                   PricebookEntry.Product2.Package_Type__c,
                   PricebookEntry.Product2.Destination__c,
                   PricebookEntry.Product2.Supplier__c,
                   PricebookEntry.UnitPrice,
                   PricebookEntry.CurrencyIsoCode,
                   PricebookEntry.Product2.DisplayUrl
            FROM OpportunityLineItem
            WHERE OpportunityId = :bookingId
            AND Booking_Service__c = true
            ORDER BY CreatedDate ASC
        ];

        for (OpportunityLineItem line : lines) {

            Product2 product = line.PricebookEntry.Product2;

            if (product == null ||
                String.isBlank(product.Name) ||
                line.PricebookEntry.Product2Id == null ||
                line.Quantity == null ||
                line.UnitPrice == null) {
                continue;
            }

            SavedServiceDTO dto = new SavedServiceDTO();

            dto.lineId = line.Id;
            dto.productId = product.Id;
            dto.name = product.Name;

            dto.category = normalizePackageType(
                product.Package_Type__c
            );

            dto.destination = product.Destination__c;
            dto.supplier = product.Supplier__c;

            dto.description = String.isBlank(line.Description)
                ? product.Description
                : line.Description;

            dto.quantity = line.Quantity;
            dto.price = line.UnitPrice;
            dto.basePrice = line.PricebookEntry.UnitPrice;

            dto.rooms = line.Hotel_Rooms__c == null
                ? 1 : line.Hotel_Rooms__c.intValue();

            dto.nights = line.Hotel_Nights__c == null
                ? 1 : line.Hotel_Nights__c.intValue();

            dto.currencyCode =
                line.PricebookEntry.CurrencyIsoCode;

            dto.imageUrl = product.DisplayUrl;

            results.add(dto);
        }

        return results;
    }

    // =====================================================
    // SAVE PACKAGE
    // =====================================================

    @AuraEnabled
    public static Integer saveBookingServices(
        Id bookingId,
        List<Map<String, Object>> selectedServices
    ) {

        if (bookingId == null) {
            throw new AuraHandledException('Booking ID is required.');
        }

        if (selectedServices == null || selectedServices.isEmpty()) {
            throw new AuraHandledException(
                'Add at least one product to My Travel Package.'
            );
        }

        Opportunity booking = [
            SELECT Id, Pricebook2Id, CurrencyIsoCode,
                   Booking_Status__c
            FROM Opportunity
            WHERE Id = :bookingId
            LIMIT 1
            FOR UPDATE
        ];

        if (booking.Pricebook2Id == null) {
            throw new AuraHandledException(
                'Assign a Price Book before saving.'
            );
        }

        if (booking.Booking_Status__c == 'Confirmed' ||
            booking.Booking_Status__c == 'Cancelled') {
            throw new AuraHandledException(
                'This Booking cannot be modified.'
            );
        }

        Set<Id> productIds = new Set<Id>();

        for (Map<String, Object> item : selectedServices) {

            if (item == null || item.get('productId') == null) {
                throw new AuraHandledException(
                    'A selected product is missing its ID.'
                );
            }

            Id productId;

            try {
                productId = (Id)String.valueOf(item.get('productId'));
            } catch (Exception ex) {
                throw new AuraHandledException('Invalid Product ID.');
            }

            if (productId.getSObjectType() != Product2.SObjectType) {
                throw new AuraHandledException('Invalid Product ID.');
            }

            if (productIds.contains(productId)) {
                throw new AuraHandledException(
                    'Duplicate products are not allowed.'
                );
            }

            productIds.add(productId);
        }

        List<PricebookEntry> entries = [
            SELECT Id, Product2Id, UnitPrice, CurrencyIsoCode,
                   Product2.Name, Product2.Package_Type__c
            FROM PricebookEntry
            WHERE Pricebook2Id = :booking.Pricebook2Id
            AND CurrencyIsoCode = :booking.CurrencyIsoCode
            AND Product2Id IN :productIds
            AND IsActive = true
            AND Product2.IsActive = true
        ];

        Map<Id, PricebookEntry> entryByProduct =
            new Map<Id, PricebookEntry>();

        Boolean hasAirTicket = false;

        for (PricebookEntry entry : entries) {

            entryByProduct.put(entry.Product2Id, entry);

            if (isAirTicket(entry.Product2.Package_Type__c)) {
                hasAirTicket = true;
            }
        }

        if (entryByProduct.size() != productIds.size()) {
            throw new AuraHandledException(
                'A selected product is unavailable in this Booking Price Book.'
            );
        }

        if (!hasAirTicket) {
            throw new AuraHandledException(
                'At least one Air Ticket is required.'
            );
        }

        // Existing VGTS-managed products only.
        Map<Id, OpportunityLineItem> existingByProduct =
            new Map<Id, OpportunityLineItem>();

        for (OpportunityLineItem line : [
            SELECT Id, PricebookEntry.Product2Id
            FROM OpportunityLineItem
            WHERE OpportunityId = :bookingId
            AND Booking_Service__c = true
        ]) {
            existingByProduct.put(
                line.PricebookEntry.Product2Id,
                line
            );
        }

        List<OpportunityLineItem> toInsert =
            new List<OpportunityLineItem>();

        List<OpportunityLineItem> toUpdate =
            new List<OpportunityLineItem>();

        Set<Id> retainedIds = new Set<Id>();

        for (Map<String, Object> item : selectedServices) {

            Id productId = (Id)String.valueOf(item.get('productId'));

            PricebookEntry entry = entryByProduct.get(productId);

            Boolean hotel = isHotel(entry.Product2.Package_Type__c);

            Decimal quantity = readDecimal(item.get('quantity'));

            if (quantity == null) quantity = 1;

            if (quantity <= 0) {
                throw new AuraHandledException(
                    'Quantity must be greater than zero.'
                );
            }

            Integer rooms = hotel
                ? readWholeNumber(item.get('rooms'), 1) : 1;

            Integer nights = hotel
                ? readWholeNumber(item.get('nights'), 1) : 1;

            Decimal unitPrice = entry.UnitPrice;

            if (hotel) {
                unitPrice += ((rooms - 1) * HOTEL_ROOM_FEE) +
                             ((nights - 1) * HOTEL_NIGHT_FEE);
            }

            Decimal displayedPrice = readDecimal(item.get('price'));

            if (displayedPrice != null &&
                displayedPrice.setScale(2) != unitPrice.setScale(2)) {

                throw new AuraHandledException(
                    'The product price changed. Refresh the catalogue and add it again.'
                );
            }

            OpportunityLineItem line =
                existingByProduct.get(productId);

            if (line == null) {
                line = new OpportunityLineItem();
                line.OpportunityId = bookingId;
            }

            line.PricebookEntryId = entry.Id;
            line.Quantity = quantity;
            line.UnitPrice = unitPrice;
            line.Booking_Service__c = true;
            line.Hotel_Rooms__c = hotel ? rooms : null;
            line.Hotel_Nights__c = hotel ? nights : null;

            line.Description = hotel
                ? rooms + ' room(s), ' + nights + ' night(s)'
                : String.valueOf(
                    item.get('description') == null
                        ? '' : item.get('description')
                );

            if (line.Id == null) {
                toInsert.add(line);
            } else {
                toUpdate.add(line);
            }

            retainedIds.add(productId);
        }

        List<OpportunityLineItem> toDelete =
            new List<OpportunityLineItem>();

        for (Id oldProductId : existingByProduct.keySet()) {
            if (!retainedIds.contains(oldProductId)) {
                toDelete.add(existingByProduct.get(oldProductId));
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!toInsert.isEmpty()) insert toInsert;
        if (!toDelete.isEmpty()) delete toDelete;

        if (booking.Booking_Status__c != 'Services Saved') {
            booking.Booking_Status__c = 'Services Saved';
            update booking;
        }

        return toInsert.size() + toUpdate.size();
    }

    // =====================================================
    // PAYMENT
    // =====================================================

    @AuraEnabled
    public static Id savePayment(
        Id bookingId,
        String method,
        Date paymentDate
    ) {

        if (bookingId == null || String.isBlank(method)) {
            throw new AuraHandledException(
                'Booking and payment method are required.'
            );
        }

        List<OpportunityLineItem> lines = [
            SELECT Quantity, UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId = :bookingId
            AND Booking_Service__c = true
        ];

        if (lines.isEmpty()) {
            throw new AuraHandledException(
                'Save the Travel Package first.'
            );
        }

        Decimal total = 0;

        for (OpportunityLineItem line : lines) {
            total += line.Quantity * line.UnitPrice;
        }

        if (total <= 0) {
            throw new AuraHandledException('Invalid payment amount.');
        }

        Payment__c payment = new Payment__c(
            Booking__c = bookingId,
            Amount__c = total,
            Method__c = method,
            Payment_Date__c = paymentDate == null
                ? Date.today() : paymentDate,
            Status__c = 'Pending'
        );

        insert payment;

        return payment.Id;
    }

    // =====================================================
    // QUOTE
    // =====================================================

    @AuraEnabled
    public static Id createBookingQuote(Id bookingId) {

        if (bookingId == null) {
            throw new AuraHandledException('Booking ID is required.');
        }

        String blockReason =
            VisaChecklistController.getQuoteBlockReason(bookingId);

        if (!String.isBlank(blockReason)) {
            throw new AuraHandledException(
                'Quote creation blocked: ' + blockReason
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
                'Assign a Price Book first.'
            );
        }

        List<OpportunityLineItem> lines = [
            SELECT Id, PricebookEntryId, Quantity, UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId = :bookingId
            AND Booking_Service__c = true
        ];

        if (lines.isEmpty()) {
            throw new AuraHandledException(
                'Save the Travel Package before creating a Quote.'
            );
        }

        Integer quoteCount = [
            SELECT COUNT()
            FROM Quote
            WHERE OpportunityId = :bookingId
            AND Status != 'Rejected'
        ];

        if (quoteCount > 0) {
            throw new AuraHandledException(
                'An active Quote already exists.'
            );
        }

        Quote quoteRecord = new Quote(
            Name = 'Travel Quote - ' + booking.Name,
            OpportunityId = booking.Id,
            Pricebook2Id = booking.Pricebook2Id,
            Status = 'Draft'
        );

        insert quoteRecord;

        List<QuoteLineItem> quoteLines =
            new List<QuoteLineItem>();

        for (OpportunityLineItem line : lines) {

            quoteLines.add(new QuoteLineItem(
                QuoteId = quoteRecord.Id,
                PricebookEntryId = line.PricebookEntryId,
                Quantity = line.Quantity,
                UnitPrice = line.UnitPrice
            ));
        }

        insert quoteLines;

        return quoteRecord.Id;
    }
}

