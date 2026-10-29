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
            throw new AuraHandledException('Booking record ID is missing.');
        }


        if (selectedServices == null || selectedServices.isEmpty()) {
            throw new AuraHandledException('Please add at least one package.');
        }


        Map<String, Schema.SObjectField> serviceFields =
            Schema.SObjectType.OpportunityLineItem.fields.getMap();


        List<OpportunityLineItem> recordsToInsert =
            new List<OpportunityLineItem>();


        for (Map<String, Object> item : selectedServices) {
            OpportunityLineItem serviceRecord = new OpportunityLineItem();


            // Prefer Booking__c when available; otherwise use Opportunity__c.
            if (serviceFields.containsKey('Booking__c')) {
                serviceRecord.put('Booking__c', bookingId);
            } else if (serviceFields.containsKey('Opportunity__c')) {
                serviceRecord.put('Opportunity__c', bookingId);
            }


            putIfAvailable(serviceRecord, 'Service_Name__c', item.get('name'));
            putIfAvailable(serviceRecord, 'Service_Type__c', item.get('serviceType'));
            putIfAvailable(serviceRecord, 'Supplier__c', item.get('supplier'));
            putIfAvailable(serviceRecord, 'Description__c', item.get('description'));
            putIfAvailable(serviceRecord, 'Details__c', item.get('details'));
            putIfAvailable(serviceRecord, 'Travel_Package__c', item.get('travelPackageId'));


            putIfAvailable(serviceRecord, 'Supplier_Cost__c', item.get('supplierCost'));
            putIfAvailable(serviceRecord, 'Cost__c', item.get('supplierCost'));
            putIfAvailable(serviceRecord, 'Selling_Price__c', item.get('sellingPrice'));
            putIfAvailable(serviceRecord, 'Taxes__c', item.get('taxes'));
            putIfAvailable(serviceRecord, 'Quantity__c', item.get('quantity'));


            putIfAvailable(serviceRecord, 'Hotel_Name__c', item.get('name'));
            putIfAvailable(serviceRecord, 'Room_Category__c', item.get('roomCategory'));
            putIfAvailable(serviceRecord, 'Meal_Plan__c', item.get('mealPlan'));
            putIfAvailable(serviceRecord, 'Number_Of_Rooms__c', item.get('rooms'));
            putIfAvailable(serviceRecord, 'Number_Of_Nights__c', item.get('nights'));


            recordsToInsert.add(serviceRecord);
        }


        insert recordsToInsert;
        return recordsToInsert.size();
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


    @AuraEnabled
    public static Id savePayment(
        Id bookingId,
        Decimal amount,
        String method,
        Date paymentDate,
        String status
    ) {
        if (bookingId == null) {
            throw new AuraHandledException('Booking record ID is missing.');
        }


        if (amount == null || amount <= 0) {
            throw new AuraHandledException('Enter a valid payment amount.');
        }


        Payment__c paymentRecord = new Payment__c();


        Map<String, Schema.SObjectField> paymentFields =
            Schema.SObjectType.Payment__c.fields.getMap();


        if (paymentFields.containsKey('Booking__c')) {
            paymentRecord.put('Booking__c', bookingId);
        } else if (paymentFields.containsKey('Opportunity__c')) {
            paymentRecord.put('Opportunity__c', bookingId);
        }


        paymentRecord.put('Amount__c', amount);
        paymentRecord.put('Method__c', method);
        paymentRecord.put('Payment_Date__c',
            paymentDate == null ? Date.today() : paymentDate);
        paymentRecord.put('Status__c',
            String.isBlank(status) ? 'Pending' : status);


        insert paymentRecord;
        return paymentRecord.Id;
    }
}