
public with sharing class VGTSPredefinedTravelPackageController {

    private static final Decimal HOTEL_ROOM_FEE = 50;
    private static final Decimal HOTEL_NIGHT_FEE = 30;

    // =====================================================
    // TRAVEL PACKAGE ITEM DTO
    // =====================================================

    public class PackageItemDTO {

        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String destination { get; set; }
        @AuraEnabled public String supplier { get; set; }
        @AuraEnabled public String imageUrl { get; set; }

        @AuraEnabled public Decimal basePrice { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }

        @AuraEnabled public Integer rooms { get; set; }
        @AuraEnabled public Integer nights { get; set; }

        @AuraEnabled public Decimal lineTotal { get; set; }
        @AuraEnabled public String currencyCode { get; set; }
        @AuraEnabled public Decimal discountAmount { get; set; }
        @AuraEnabled public Decimal discountedLineTotal { get; set; }

    }

    // =====================================================
    // TRAVEL PACKAGE DTO
    // =====================================================

    public class TravelPackageDTO {

        @AuraEnabled public Id packageId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String destination { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String imageUrl { get; set; }

        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }

        @AuraEnabled public Decimal discount { get; set; }
        @AuraEnabled public Decimal subtotal { get; set; }
        @AuraEnabled public Decimal packagePrice { get; set; }

        @AuraEnabled public String currencyCode { get; set; }

        @AuraEnabled public Integer productCount { get; set; }

        @AuraEnabled public List<PackageItemDTO> items { get; set; }
    }

    // =====================================================
    // GET PREDEFINED TRAVEL PACKAGES
    // =====================================================

    @AuraEnabled(cacheable=true)
    public static List<TravelPackageDTO> getPredefinedTravelPackages(
        Id bookingId
    ) {

        if (bookingId == null) {
            throw new AuraHandledException(
                'Booking ID is required.'
            );
        }

        // Retrieve Booking Price Book and Currency.

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

        String currencyCode = booking.CurrencyIsoCode;

        // Retrieve active predefined packages.

        List<Travel_Package__c> packages = [
            SELECT Id, Name, Destination__c,
                   Description__c, Package_Image_URL__c,
                   Start_Date__c, End_Date__c,
                   Active__c, Package_Discount__c
            FROM Travel_Package__c
            WHERE Active__c = true
            ORDER BY Name
        ];

        if (packages.isEmpty()) {
            return new List<TravelPackageDTO>();
        }

        Set<Id> packageIds = new Set<Id>();

        for (Travel_Package__c packageRecord : packages) {
            packageIds.add(packageRecord.Id);
        }

        // Retrieve all products belonging to these packages.

        List<Travel_Package_Item__c> packageItems = [
            SELECT Id, Travel_Package__c,
                   Product__c,
                   Quantity__c,
                   Rooms__c,
                   Nights__c,
                   Display_Order__c,
                   Product__r.Name,
                   Product__r.Description,
                   Product__r.Package_Type__c,
                   Product__r.Destination__c,
                   Product__r.Supplier__c,
                   Product__r.DisplayUrl,
                   Product__r.IsActive
            FROM Travel_Package_Item__c
            WHERE Travel_Package__c IN :packageIds
            AND Product__c != null
            AND Product__r.IsActive = true
            ORDER BY Display_Order__c ASC
        ];

        if (packageItems.isEmpty()) {
            return new List<TravelPackageDTO>();
        }

        // Collect product IDs.


// =====================================================
// COLLECT PRODUCT IDs
// =====================================================

Set<Id> productIds = new Set<Id>();

for (Travel_Package_Item__c item : packageItems) {

    if (item.Product__c != null) {
        productIds.add(item.Product__c);
    }
}

// =====================================================
// RETRIEVE FILES FOR PACKAGES AND PRODUCTS
// =====================================================

// IMPORTANT:
// Collect all IDs AFTER productIds has been populated.

Set<Id> linkedRecordIds = new Set<Id>();

linkedRecordIds.addAll(packageIds);
linkedRecordIds.addAll(productIds);

Map<Id, String> imageUrls = new Map<Id, String>();

for (ContentDocumentLink linkRecord : [

    SELECT LinkedEntityId,
           ContentDocument.LatestPublishedVersionId

    FROM ContentDocumentLink

    WHERE LinkedEntityId IN :linkedRecordIds

]) {

    if (
        !imageUrls.containsKey(linkRecord.LinkedEntityId) &&
        linkRecord.ContentDocument.LatestPublishedVersionId != null
    ) {

        imageUrls.put(
            linkRecord.LinkedEntityId,

            '/sfc/servlet.shepherd/version/download/' +
            linkRecord.ContentDocument.LatestPublishedVersionId
        );
    }
}


        // Retrieve products from the Booking Price Book.

        Map<Id, PricebookEntry> entryByProduct =
            new Map<Id, PricebookEntry>();

        for (PricebookEntry entry : [
            SELECT Id, Product2Id, UnitPrice,
                   CurrencyIsoCode
            FROM PricebookEntry
            WHERE Pricebook2Id = :booking.Pricebook2Id
            AND CurrencyIsoCode = :currencyCode
            AND Product2Id IN :productIds
            AND IsActive = true
            AND Product2.IsActive = true
        ]) {

            entryByProduct.put(
                entry.Product2Id,
                entry
            );
        }

        // Group package items by Travel Package.

        Map<Id, List<Travel_Package_Item__c>> itemsByPackage =
            new Map<Id, List<Travel_Package_Item__c>>();

        for (Travel_Package_Item__c item : packageItems) {

            if (!itemsByPackage.containsKey(item.Travel_Package__c)) {

                itemsByPackage.put(
                    item.Travel_Package__c,
                    new List<Travel_Package_Item__c>()
                );
            }

            itemsByPackage.get(item.Travel_Package__c).add(item);
        }

        List<TravelPackageDTO> results =
            new List<TravelPackageDTO>();

        // Build each complete package.

        for (Travel_Package__c packageRecord : packages) {

            List<Travel_Package_Item__c> includedItems =
                itemsByPackage.get(packageRecord.Id);

            // Do not display packages without products.

            if (includedItems == null || includedItems.isEmpty()) {
                continue;
            }

            TravelPackageDTO packageDTO =
                new TravelPackageDTO();

            packageDTO.packageId = packageRecord.Id;
            packageDTO.name = packageRecord.Name;
            packageDTO.destination = packageRecord.Destination__c;
            packageDTO.description = packageRecord.Description__c;
            packageDTO.imageUrl =
    imageUrls.containsKey(packageRecord.Id)
        ? imageUrls.get(packageRecord.Id)
        : packageRecord.Package_Image_URL__c;


            packageDTO.startDate = packageRecord.Start_Date__c;
            packageDTO.endDate = packageRecord.End_Date__c;

            packageDTO.discount =
                packageRecord.Package_Discount__c == null
                    ? 0
                    : packageRecord.Package_Discount__c;

            packageDTO.currencyCode = currencyCode;

            packageDTO.items = new List<PackageItemDTO>();

            Decimal subtotal = 0;
            Boolean allProductsAvailable = true;

            // Build individual product details.

            for (Travel_Package_Item__c item : includedItems) {

                PricebookEntry entry =
                    entryByProduct.get(item.Product__c);

                // A complete package must have all its products
                // available in the Booking Price Book.

                if (entry == null) {
                    allProductsAvailable = false;
                    break;
                }

                PackageItemDTO itemDTO =
                    new PackageItemDTO();

                itemDTO.productId = item.Product__c;
                itemDTO.name = item.Product__r.Name;

                itemDTO.category =
                    item.Product__r.Package_Type__c;

                itemDTO.description =
                    item.Product__r.Description;

                itemDTO.destination =
                    item.Product__r.Destination__c;

                itemDTO.supplier =
                    item.Product__r.Supplier__c;

              itemDTO.imageUrl = 
              imageUrls.get(item.Product__c);


                itemDTO.basePrice = entry.UnitPrice;

                itemDTO.quantity =
                    item.Quantity__c == null
                        ? 1
                        : item.Quantity__c;

                itemDTO.rooms =
                    item.Rooms__c == null
                        ? 1
                        : item.Rooms__c.intValue();

                itemDTO.nights =
                    item.Nights__c == null
                        ? 1
                        : item.Nights__c.intValue();

                Decimal unitPrice = entry.UnitPrice;

                // Apply existing VGTS hotel pricing logic.

                if (itemDTO.category == 'Hotels') {

                    unitPrice +=
                        ((itemDTO.rooms - 1) * HOTEL_ROOM_FEE) +
                        ((itemDTO.nights - 1) * HOTEL_NIGHT_FEE);
                }

                itemDTO.price = unitPrice;

                itemDTO.lineTotal =
                    unitPrice * itemDTO.quantity;

                itemDTO.currencyCode = currencyCode;

                subtotal += itemDTO.lineTotal;

                packageDTO.items.add(itemDTO);
            }

            // Hide incomplete packages.

            if (!allProductsAvailable) {
                continue;
            }

           
subtotal = subtotal.setScale(
    2,
    RoundingMode.HALF_UP
);

Decimal discountAmount = (
    subtotal * packageDTO.discount / 100
).setScale(2, RoundingMode.HALF_UP);

packageDTO.subtotal = subtotal;

packageDTO.packagePrice = (
    subtotal - discountAmount
).setScale(2, RoundingMode.HALF_UP);

// Allocate discount proportionally across products.

Decimal allocatedDiscount = 0;

for (Integer i = 0; i < packageDTO.items.size(); i++) {

    PackageItemDTO itemDTO = packageDTO.items[i];

    Decimal itemDiscount;

    // Last product absorbs rounding differences.

    if (i == packageDTO.items.size() - 1) {

        itemDiscount = discountAmount - allocatedDiscount;

    } else {

        itemDiscount = (
            itemDTO.lineTotal / subtotal * discountAmount
        ).setScale(2, RoundingMode.HALF_UP);

        allocatedDiscount += itemDiscount;
    }

    itemDTO.discountAmount = itemDiscount;

    itemDTO.discountedLineTotal = (
        itemDTO.lineTotal - itemDiscount
    ).setScale(2, RoundingMode.HALF_UP);
}



            packageDTO.productCount =
                packageDTO.items.size();

            results.add(packageDTO);
        }

        return results;
    }
}

