
public with sharing class VGTSBookingPackageController {

    private static final Decimal HOTEL_ROOM_FEE = 50;
    private static final Decimal HOTEL_NIGHT_FEE = 30;

    public class SavedServiceDTO {
        @AuraEnabled public Id lineId { get; set; }
        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public Id travelPackageId { get; set; }
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
                   Booking_Service__c,Travel_Package__c,
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
            dto.travelPackageId = line.Travel_Package__c;
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
        throw new AuraHandledException(
            'Booking ID is required.'
        );
    }

    if (selectedServices == null || selectedServices.isEmpty()) {
        throw new AuraHandledException(
            'Add at least one product to My Travel Package.'
        );
    }

    // =====================================================
    // 1. VALIDATE BOOKING
    // =====================================================

    Opportunity booking = [
        SELECT Id, Pricebook2Id, CurrencyIsoCode,
               StageName
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

    if (booking.StageName == 'Completed' ||
        booking.StageName == 'Confirmed' ||
        booking.StageName == 'Cancelled') {

        throw new AuraHandledException(
            'This Booking cannot be modified.'
        );
    }

    // =====================================================
    // 2. READ SELECTED PRODUCTS
    // =====================================================

    Map<Id, Map<String, Object>> itemByProduct =
        new Map<Id, Map<String, Object>>();

    Map<Id, Id> packageByProduct = new Map<Id, Id>();

    Set<Id> productIds = new Set<Id>();
    Set<Id> packageIds = new Set<Id>();

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
            throw new AuraHandledException(
                'Invalid Product ID.'
            );
        }

        if (productId.getSObjectType() != Product2.SObjectType) {
            throw new AuraHandledException(
                'Invalid Product ID.'
            );
        }

        if (productIds.contains(productId)) {
            throw new AuraHandledException(
                'Duplicate products are not allowed.'
            );
        }

        productIds.add(productId);
        itemByProduct.put(productId, item);

        // Predefined package relationship.

        Id travelPackageId;

        if (item.get('travelPackageId') != null &&
            String.isNotBlank(
                String.valueOf(item.get('travelPackageId'))
            )) {

            try {
                travelPackageId =
                    (Id)String.valueOf(item.get('travelPackageId'));
            } catch (Exception ex) {
                throw new AuraHandledException(
                    'Invalid Travel Package ID.'
                );
            }

            if (travelPackageId.getSObjectType() !=
                Travel_Package__c.SObjectType) {

                throw new AuraHandledException(
                    'Invalid Travel Package ID.'
                );
            }

            packageByProduct.put(
                productId,
                travelPackageId
            );

            packageIds.add(travelPackageId);
        }
    }

    // =====================================================
    // 3. VALIDATE PREDEFINED PACKAGES
    // =====================================================

    Map<Id, Travel_Package__c> packageById =
        new Map<Id, Travel_Package__c>();

    if (!packageIds.isEmpty()) {

        packageById = new Map<Id, Travel_Package__c>([
            SELECT Id, Name, Active__c,
                   Package_Discount__c
            FROM Travel_Package__c
            WHERE Id IN :packageIds
            AND Active__c = true
        ]);

        if (packageById.size() != packageIds.size()) {
            throw new AuraHandledException(
                'A selected Travel Package is inactive or unavailable.'
            );
        }
    }

    // Retrieve the actual products included in each package.

    Map<Id, Set<Id>> expectedProductsByPackage =
        new Map<Id, Set<Id>>();

    if (!packageIds.isEmpty()) {

        for (Travel_Package_Item__c packageItem : [
            SELECT Travel_Package__c, Product__c
            FROM Travel_Package_Item__c
            WHERE Travel_Package__c IN :packageIds
        ]) {

            if (packageItem.Product__c == null) {
                continue;
            }

            if (!expectedProductsByPackage.containsKey(
                packageItem.Travel_Package__c
            )) {

                expectedProductsByPackage.put(
                    packageItem.Travel_Package__c,
                    new Set<Id>()
                );
            }

            expectedProductsByPackage
                .get(packageItem.Travel_Package__c)
                .add(packageItem.Product__c);
        }

        for (Id packageId : packageIds) {

            Set<Id> expectedProducts =
                expectedProductsByPackage.get(packageId);

            if (expectedProducts == null ||
                expectedProducts.isEmpty()) {

                throw new AuraHandledException(
                    'A selected Travel Package has no products.'
                );
            }

            for (Id expectedProductId : expectedProducts) {

                if (!packageByProduct.containsKey(expectedProductId) ||
                    packageByProduct.get(expectedProductId) != packageId) {

                    throw new AuraHandledException(
                        'All products belonging to a predefined package must be selected together.'
                    );
                }
            }
        }
    }

    // =====================================================
    // 4. RETRIEVE PRICEBOOK ENTRIES
    // =====================================================

    List<PricebookEntry> entries = [
        SELECT Id, Product2Id, UnitPrice,
               CurrencyIsoCode,
               Product2.Name,
               Product2.Package_Type__c
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

    // =====================================================
    // 5. CALCULATE ORIGINAL PRODUCT PRICES
    // =====================================================

    Map<Id, Decimal> quantityByProduct =
        new Map<Id, Decimal>();

    Map<Id, Integer> roomsByProduct =
        new Map<Id, Integer>();

    Map<Id, Integer> nightsByProduct =
        new Map<Id, Integer>();

    Map<Id, Decimal> originalUnitPriceByProduct =
        new Map<Id, Decimal>();

    Map<Id, Decimal> originalLineTotalByProduct =
        new Map<Id, Decimal>();

    Map<Id, Decimal> finalUnitPriceByProduct =
        new Map<Id, Decimal>();

    Map<Id, Decimal> finalLineTotalByProduct =
        new Map<Id, Decimal>();

    for (Id productId : productIds) {

        Map<String, Object> item =
            itemByProduct.get(productId);

        PricebookEntry entry =
            entryByProduct.get(productId);

        Boolean hotel =
            isHotel(entry.Product2.Package_Type__c);

        Decimal quantity =
            readDecimal(item.get('quantity'));

        if (quantity == null) {
            quantity = 1;
        }

        if (quantity <= 0) {
            throw new AuraHandledException(
                'Quantity must be greater than zero.'
            );
        }

        Integer rooms = hotel
            ? readWholeNumber(item.get('rooms'), 1)
            : 1;

        Integer nights = hotel
            ? readWholeNumber(item.get('nights'), 1)
            : 1;

        Decimal unitPrice = entry.UnitPrice;

        if (hotel) {

            unitPrice +=
                ((rooms - 1) * HOTEL_ROOM_FEE) +
                ((nights - 1) * HOTEL_NIGHT_FEE);
        }

        Decimal displayedPrice =
            readDecimal(item.get('price'));

        if (displayedPrice != null &&
            displayedPrice.setScale(2) != unitPrice.setScale(2)) {

            throw new AuraHandledException(
                'The product price changed. Refresh the catalogue and add it again.'
            );
        }

        quantityByProduct.put(productId, quantity);
        roomsByProduct.put(productId, rooms);
        nightsByProduct.put(productId, nights);

        originalUnitPriceByProduct.put(
            productId,
            unitPrice
        );

        originalLineTotalByProduct.put(
            productId,
            (unitPrice * quantity).setScale(
                2,
                RoundingMode.HALF_UP
            )
        );

        finalUnitPriceByProduct.put(
            productId,
            unitPrice
        );
    }

    // =====================================================
    // 6. APPLY PROPORTIONAL PACKAGE DISCOUNTS
    // =====================================================

    for (Id packageId : packageIds) {

        Travel_Package__c packageRecord =
            packageById.get(packageId);

        Decimal discountPercent =
            packageRecord.Package_Discount__c == null
                ? 0
                : packageRecord.Package_Discount__c;

        if (discountPercent < 0 || discountPercent > 100) {
            throw new AuraHandledException(
                'Package discount must be between 0 and 100 percent.'
            );
        }

        Set<Id> packageProducts =
            expectedProductsByPackage.get(packageId);

        Decimal packageSubtotal = 0;

        for (Id productId : packageProducts) {

            packageSubtotal +=
                originalLineTotalByProduct.get(productId);
        }

        if (packageSubtotal <= 0) {
            throw new AuraHandledException(
                'Invalid Travel Package total.'
            );
        }

        Decimal discountAmount = (
            packageSubtotal * discountPercent / 100
        ).setScale(2, RoundingMode.HALF_UP);

        Decimal allocatedDiscount = 0;

        List<Id> orderedProductIds =
            new List<Id>();

        for (Id productId : packageProducts) {
            orderedProductIds.add(productId);
        }

        orderedProductIds.sort();

        for (Integer i = 0;
             i < orderedProductIds.size();
             i++) {

            Id productId = orderedProductIds[i];

            Decimal originalLineTotal =
                originalLineTotalByProduct.get(productId);

            Decimal itemDiscount;

            if (i == orderedProductIds.size() - 1) {

                itemDiscount =
                    discountAmount - allocatedDiscount;

            } else {

                itemDiscount = (
                    originalLineTotal /
                    packageSubtotal *
                    discountAmount
                ).setScale(2, RoundingMode.HALF_UP);

                allocatedDiscount += itemDiscount;
            }

            Decimal discountedLineTotal =
                originalLineTotal - itemDiscount;

            Decimal quantity =
                quantityByProduct.get(productId);

            // OpportunityLineItem.UnitPrice is stored
            // as a currency amount with two decimal places.

            Decimal discountedUnitPrice = (
                discountedLineTotal / quantity
            ).setScale(2, RoundingMode.HALF_UP);

            finalUnitPriceByProduct.put(
                productId,
                discountedUnitPrice
            );

            finalLineTotalByProduct.put(
                productId,
                (discountedUnitPrice * quantity).setScale(
                    2,
                    RoundingMode.HALF_UP
                )
            );
        }
    }

    // Individual products without a predefined package
    // retain their original Pricebook prices.

    for (Id productId : productIds) {

        if (!packageByProduct.containsKey(productId)) {

            finalLineTotalByProduct.put(
                productId,
                originalLineTotalByProduct.get(productId)
            );
        }
    }

    // =====================================================
    // 7. RETRIEVE EXISTING VGTS PRODUCTS
    // =====================================================

    Map<Id, OpportunityLineItem> existingByProduct =
        new Map<Id, OpportunityLineItem>();

    for (OpportunityLineItem line : [
        SELECT Id, PricebookEntry.Product2Id,
               Travel_Package__c
        FROM OpportunityLineItem
        WHERE OpportunityId = :bookingId
        AND Booking_Service__c = true
    ]) {

        existingByProduct.put(
            line.PricebookEntry.Product2Id,
            line
        );
    }

    // =====================================================
    // 8. PREPARE INSERT AND UPDATE RECORDS
    // =====================================================

    List<OpportunityLineItem> toInsert =
        new List<OpportunityLineItem>();

    List<OpportunityLineItem> toUpdate =
        new List<OpportunityLineItem>();

    Set<Id> retainedIds = new Set<Id>();

    for (Id productId : productIds) {

        Map<String, Object> item =
            itemByProduct.get(productId);

        PricebookEntry entry =
            entryByProduct.get(productId);

        Boolean hotel =
            isHotel(entry.Product2.Package_Type__c);

        OpportunityLineItem line =
            existingByProduct.get(productId);

        if (line == null) {

            line = new OpportunityLineItem();

            line.OpportunityId = bookingId;
        }

        line.PricebookEntryId = entry.Id;

        line.Quantity =
            quantityByProduct.get(productId);

        line.UnitPrice =
            finalUnitPriceByProduct.get(productId);

        line.Booking_Service__c = true;

        line.Hotel_Rooms__c = hotel
            ? roomsByProduct.get(productId)
            : null;

        line.Hotel_Nights__c = hotel
            ? nightsByProduct.get(productId)
            : null;

        // Link the Opportunity Product to its
        // predefined Travel Package.

        line.Travel_Package__c =
            packageByProduct.get(productId);

        line.Description = hotel
            ? roomsByProduct.get(productId) +
              ' room(s), ' +
              nightsByProduct.get(productId) +
              ' night(s)'
            : String.valueOf(
                item.get('description') == null
                    ? ''
                    : item.get('description')
            );

        if (line.Id == null) {
            toInsert.add(line);
        } else {
            toUpdate.add(line);
        }

        retainedIds.add(productId);
    }

    // =====================================================
    // 9. REMOVE DESELECTED VGTS PRODUCTS
    // =====================================================

    List<OpportunityLineItem> toDelete =
        new List<OpportunityLineItem>();

    for (Id oldProductId : existingByProduct.keySet()) {

        if (!retainedIds.contains(oldProductId)) {

            toDelete.add(
                existingByProduct.get(oldProductId)
            );
        }
    }

    // =====================================================
    // 10. SAVE CHANGES
    // =====================================================

    if (!toUpdate.isEmpty()) {
        update toUpdate;
    }

    if (!toInsert.isEmpty()) {
        insert toInsert;
    }

    if (!toDelete.isEmpty()) {
        delete toDelete;
    }

    if (booking.StageName != 'Services Saved') {

        booking.StageName = 'Services Saved';

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
    Date paymentDate,
    String paymentDetailsJson,
    String paymentStructure
) {
    if (bookingId == null || String.isBlank(method)) {
        throw new AuraHandledException(
            'Booking and payment method are required.'
        );
    }

    if (paymentStructure != 'Single' &&
        paymentStructure != 'Installments') {
        throw new AuraHandledException(
            'Invalid payment structure.'
        );
    }

    Opportunity booking = [
        SELECT Id, StageName
        FROM Opportunity
        WHERE Id = :bookingId
        FOR UPDATE
    ];

    if (booking.StageName == 'Confirmed' ||
        booking.StageName == 'Completed' ||
        booking.StageName == 'Cancelled') {
        throw new AuraHandledException(
            'This Booking cannot receive another Payment.'
        );
    }

    List<Payment__c> existing = [
        SELECT Id
        FROM Payment__c
        WHERE Booking__c = :bookingId
        AND Installment__c = null
        LIMIT 1
    ];

    if (!existing.isEmpty()) {
        throw new AuraHandledException(
            'A parent Payment already exists.'
        );
    }

    Decimal total = 0;

    for (OpportunityLineItem line : [
        SELECT Quantity, UnitPrice
        FROM OpportunityLineItem
        WHERE OpportunityId = :bookingId
        AND Booking_Service__c = true
    ]) {
        total += line.Quantity * line.UnitPrice;
    }

    total = total.setScale(2, RoundingMode.HALF_UP);

    if (total <= 0) {
        throw new AuraHandledException(
            'Save the Travel Package first.'
        );
    }

    Payment__c parentPayment = new Payment__c();

    parentPayment.Booking__c = bookingId;
    parentPayment.Amount__c = total;
    parentPayment.Method__c = method;
    parentPayment.Payment_Date__c =
        paymentDate == null ? Date.today() : paymentDate;
    parentPayment.Status__c = 'Pending';
    parentPayment.Payment_Structure__c = paymentStructure;

    // Parent Payment is an agreement, not a received transaction.
    // Installment__c must remain blank.

    insert parentPayment;

    return parentPayment.Id;
}





    // =====================================================
    // QUOTE
    // =====================================================



@AuraEnabled
public static Id createBookingQuote(
    Id bookingId,
    Id paymentId
) {
    if (bookingId == null || paymentId == null) {
        throw new AuraHandledException(
            'Booking and Payment are required.'
        );
    }

    Opportunity booking = [
        SELECT Id, Name, Pricebook2Id, StageName
        FROM Opportunity
        WHERE Id = :bookingId
        FOR UPDATE
    ];

    if (booking.StageName == 'Confirmed' ||
        booking.StageName == 'Completed' ||
        booking.StageName == 'Cancelled') {
        throw new AuraHandledException(
            'This Booking is finalized.'
        );
    }

    if (booking.Pricebook2Id == null) {
        throw new AuraHandledException(
            'Assign a Price Book first.'
        );
    }

    Payment__c parentPayment = [
        SELECT Id, Booking__c, Amount__c,
               Status__c, Payment_Structure__c,
               Installment__c
        FROM Payment__c
        WHERE Id = :paymentId
        AND Booking__c = :bookingId
        LIMIT 1
    ];

    if (parentPayment.Installment__c != null ||
        parentPayment.Status__c != 'Pending') {
        throw new AuraHandledException(
            'A Pending parent Payment is required.'
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
            'Save the Travel Package first.'
        );
    }

    Decimal total = 0;

    for (OpportunityLineItem line : lines) {
        total += line.Quantity * line.UnitPrice;
    }

    total = total.setScale(2, RoundingMode.HALF_UP);

    if (parentPayment.Amount__c != total) {
        throw new AuraHandledException(
            'Parent Payment does not match Booking total.'
        );
    }

    List<Installment__c> installments = [
        SELECT Id, Installment_Number__c,
               Amount__c, Parent_Payment__c
        FROM Installment__c
        WHERE Booking__c = :bookingId
        AND Parent_Payment__c = :paymentId
    ];

    if (parentPayment.Payment_Structure__c == 'Single') {

        if (!installments.isEmpty()) {
            throw new AuraHandledException(
                'Single Payment cannot have installments.'
            );
        }

    } else if (
        parentPayment.Payment_Structure__c == 'Installments'
    ) {

        if (installments.size() != 3) {
            throw new AuraHandledException(
                'Create all three installments first.'
            );
        }

        Set<Integer> numbers = new Set<Integer>();
        Decimal scheduleTotal = 0;

        for (Installment__c item : installments) {
            numbers.add(item.Installment_Number__c.intValue());
            scheduleTotal += item.Amount__c;
        }

        if (numbers.size() != 3 ||
            !numbers.contains(1) ||
            !numbers.contains(2) ||
            !numbers.contains(3) ||
            scheduleTotal.setScale(2) != total) {

            throw new AuraHandledException(
                'The installment schedule is invalid.'
            );
        }

    } else {
        throw new AuraHandledException(
            'Invalid Payment Structure.'
        );
    }

    if (![
        SELECT Id
        FROM Quote
        WHERE OpportunityId = :bookingId
        LIMIT 1
    ].isEmpty()) {
        throw new AuraHandledException(
            'A Quote already exists for this Booking.'
        );
    }

    Quote q = new Quote(
        Name = 'Travel Quote - ' + booking.Name,
        OpportunityId = bookingId,
        Pricebook2Id = booking.Pricebook2Id,
        Status = 'Draft'
    );

    insert q;

    List<QuoteLineItem> quoteLines =
        new List<QuoteLineItem>();

    for (OpportunityLineItem line : lines) {
        quoteLines.add(new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = line.PricebookEntryId,
            Quantity = line.Quantity,
            UnitPrice = line.UnitPrice
        ));
    }

    insert quoteLines;

    return q.Id;
}





public class PaymentWorkflowDTO {
    @AuraEnabled public Id paymentId { get; set; }
    @AuraEnabled public String paymentMethod { get; set; }
    @AuraEnabled public String paymentStatus { get; set; }
    @AuraEnabled public Decimal paymentAmount { get; set; }
    @AuraEnabled public Boolean paymentCreated { get; set; }
    @AuraEnabled public Boolean installmentsCreated { get; set; }
    @AuraEnabled public Integer installmentCount { get; set; }
    @AuraEnabled public String paymentStructure { get; set; }
    @AuraEnabled public Boolean quoteCreated { get; set; }
    @AuraEnabled public Id quoteId { get; set; }
    @AuraEnabled public String bookingStatus { get; set; }
    @AuraEnabled public String quoteStatus { get; set; }
    @AuraEnabled public Boolean quoteIsSyncing { get; set; }
    @AuraEnabled public Boolean requiredPaymentReceived { get; set; }
    @AuraEnabled public Decimal depositAmount { get; set; }
    @AuraEnabled public Decimal depositPaidAmount { get; set; }
    @AuraEnabled public String depositStatus { get; set; }

}




@AuraEnabled(cacheable=true)
public static PaymentWorkflowDTO getPaymentWorkflow(Id bookingId) {

    PaymentWorkflowDTO result = new PaymentWorkflowDTO();

    result.paymentCreated = false;
    result.installmentsCreated = false;
    result.installmentCount = 0;
    result.quoteCreated = false;
    result.quoteIsSyncing = false;
    result.requiredPaymentReceived = false;

    if (bookingId == null) return result;

    Opportunity booking = [
        SELECT Id, StageName
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
    ];

    result.bookingStatus = booking.StageName;

    // Find the parent Payment.
    List<Payment__c> parents = [
        SELECT Id, Method__c, Status__c,
               Amount__c, Payment_Structure__c
        FROM Payment__c
        WHERE Booking__c = :bookingId
        AND Installment__c = null
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    if (!parents.isEmpty()) {

        Payment__c parent = parents[0];

        result.paymentId = parent.Id;
        result.paymentMethod = parent.Method__c;
        result.paymentStatus = parent.Status__c;
        result.paymentAmount = parent.Amount__c;
        result.paymentStructure = parent.Payment_Structure__c;
        result.paymentCreated = true;

        // Find installments through the NEW lookup.
        List<Installment__c> installments = [
            SELECT Id, Installment_Number__c,
                   Amount__c, Paid_Amount__c,
                   Status__c, Parent_Payment__c
            FROM Installment__c
            WHERE Booking__c = :bookingId
            AND Parent_Payment__c = :parent.Id
        ];

        Set<Integer> numbers = new Set<Integer>();

        Installment__c deposit;

        for (Installment__c item : installments) {

            if (item.Installment_Number__c == null) {
                continue;
            }

            Integer installmentNo =
                item.Installment_Number__c.intValue();

            numbers.add(installmentNo);

            if (installmentNo == 1) {
                deposit = item;
            }
        }

        result.installmentCount = installments.size();

        result.installmentsCreated =
            installments.size() == 3 &&
            numbers.contains(1) &&
            numbers.contains(2) &&
            numbers.contains(3);

        if (parent.Payment_Structure__c == 'Single') {

            result.requiredPaymentReceived =
                parent.Status__c == 'Completed';

        } else if (
            parent.Payment_Structure__c == 'Installments'
        ) {

            if (deposit != null) {

                result.depositAmount = deposit.Amount__c;
                result.depositPaidAmount = deposit.Paid_Amount__c;
                result.depositStatus = deposit.Status__c;

                result.requiredPaymentReceived =
                    deposit.Status__c == 'Paid' &&
                    deposit.Paid_Amount__c >= deposit.Amount__c;
            }
        }
    }

    // Find the Booking Quote.
    List<Quote> quotes = [
        SELECT Id, Status, IsSyncing
        FROM Quote
        WHERE OpportunityId = :bookingId
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    if (!quotes.isEmpty()) {

        result.quoteCreated = true;
        result.quoteId = quotes[0].Id;
        result.quoteStatus = quotes[0].Status;
        result.quoteIsSyncing = quotes[0].IsSyncing;
    }

    return result;
}





// =====================================================
// Confirm Booking
// =====================================================


@AuraEnabled
public static void confirmBooking(Id bookingId) {

    if (bookingId == null) {
        throw new AuraHandledException(
            'Booking ID is required.'
        );
    }

    Opportunity booking = [
        SELECT Id, StageName
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
        FOR UPDATE
    ];

    if (booking.StageName == 'Cancelled') {
        throw new AuraHandledException(
            'A cancelled Booking cannot be confirmed.'
        );
    }

    if (booking.StageName == 'Confirmed') {
        throw new AuraHandledException(
            'This Booking is already confirmed.'
        );
    }

    List<Quote> quotes = [
        SELECT Id
        FROM Quote
        WHERE OpportunityId = :bookingId
        LIMIT 1
    ];

    if (quotes.isEmpty()) {
        throw new AuraHandledException(
            'Create the Quote before confirming the Booking.'
        );
    }

    List<Payment__c> payments = [
        SELECT Id
        FROM Payment__c
        WHERE Booking__c = :bookingId
        LIMIT 1
    ];

    if (payments.isEmpty()) {
        throw new AuraHandledException(
            'A Payment is required before confirming the Booking.'
        );
    }

    booking.StageName = 'Confirmed';

    update booking;
}

// =====================================================
// Cancel Booking
// =====================================================

@AuraEnabled
public static void cancelBooking(Id bookingId) {

    if (bookingId == null) {
        throw new AuraHandledException(
            'Booking ID is required.'
        );
    }

    Opportunity booking = [
        SELECT Id, StageName
        FROM Opportunity
        WHERE Id = :bookingId
        LIMIT 1
        FOR UPDATE
    ];

    if (booking.StageName == 'Confirmed') {
        throw new AuraHandledException(
            'A confirmed Booking cannot be cancelled through this action.'
        );
    }

    if (booking.StageName == 'Cancelled') {
        throw new AuraHandledException(
            'This Booking is already cancelled.'
        );
    }

    List<Quote> quotes = [
        SELECT Id
        FROM Quote
        WHERE OpportunityId = :bookingId
        LIMIT 1
    ];

    if (quotes.isEmpty()) {
        throw new AuraHandledException(
            'Create the Quote before cancelling the Booking.'
        );
    }

    booking.StageName = 'Cancelled';

    update booking;
}




}

