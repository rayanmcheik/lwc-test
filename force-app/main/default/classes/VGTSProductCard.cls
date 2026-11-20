public class VGTSProductCard {

    @AuraEnabled public String productId { get; set; }
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public String productCode { get; set; }
    @AuraEnabled public String productType { get; set; }
    @AuraEnabled public String departure { get; set; }
    @AuraEnabled public String destination { get; set; }
    @AuraEnabled public String departureDate { get; set; }
    @AuraEnabled public String returnDate { get; set; }
    @AuraEnabled public String flightType { get; set; }
    @AuraEnabled public String cabinClass { get; set; }
    @AuraEnabled public Decimal basePrice { get; set; }
    @AuraEnabled public Decimal sellingPrice { get; set; }
    @AuraEnabled public String currencyCode { get; set; }
    @AuraEnabled public Decimal fees { get; set; }
    @AuraEnabled public Decimal taxes { get; set; }
    @AuraEnabled public String supplier { get; set; }
    @AuraEnabled public String description { get; set; }
}


