
public with sharing class VGTSBookingVoucherController {

    private static final String QR_PREFIX = 'VGTS_QR_';
    private static final String QUICKCHART_ENDPOINT =
        'https://quickchart.io/qr';

    private static final Integer QR_SIZE = 180;

    // =====================================================
    // VOUCHER DTO
    // =====================================================

    public class Voucher {

        public Id lineId { get; set; }
        public Id productId { get; set; }


        public String serviceName { get; set; }
        public String productCode { get; set; }
        public String category { get; set; }
        public String destination { get; set; }
        public String supplier { get; set; }
        public String description { get; set; }

        public String departure { get; set; }
        public String arrivalAirport { get; set; }

        public Date departureDate { get; set; }
        public Date returnDate { get; set; }

        public Decimal quantity { get; set; }
        public Decimal unitPrice { get; set; }
        public Decimal totalPrice { get; set; }

        public Integer rooms { get; set; }
        public Integer nights { get; set; }

        public String flightType { get; set; }
        public String cabinClass { get; set; }

        public String qrUrl { get; set; }

        public String voucherReference { get; set; }
         
    }

    // =====================================================
    // BOOKING INFORMATION
    // =====================================================

    public Opportunity bookingInfo { get; private set; }

    public Boolean fullyPaid { get; private set; }
    public Boolean hasProducts { get; private set; }

    public Boolean hasHotels { get; private set; }
    public Boolean hasTransfers { get; private set; }
    public Boolean hasAirTickets { get; private set; }
    public Boolean hasAncillaries { get; private set; }

    public Decimal packageTotal { get; private set; }
    public Decimal totalPaid { get; private set; }
    public Decimal remainingBalance { get; private set; }

    public List<Voucher> hotelVouchers { get; private set; }
    public List<Voucher> transferVouchers { get; private set; }
    public List<Voucher> airTicketVouchers { get; private set; }
    public List<Voucher> ancillaryVouchers { get; private set; }

    public String errorMessage { get; private set; }
    public String qrErrorMessage { get; private set; }

   

    // =====================================================
    // CONSTRUCTOR
    // =====================================================

    public VGTSBookingVoucherController(
        ApexPages.StandardController controller
    ) {

        Id bookingId = controller.getId();

        initialize();

        if (bookingId == null) {
            errorMessage = 'Booking ID is required.';
            return;
        }

        loadBooking(bookingId);

        if (bookingInfo == null) {
            return;
        }

        loadBookedProducts(bookingId);

       if (!hasProducts) {

            if (String.isBlank(errorMessage)) {
                errorMessage =
                    'No products were found in the synchronized Quote.';
            }

            return;
        }


        calculatePayment(bookingId);

        
     

        loadExistingQrFiles(bookingId);
    }

    // =====================================================
    // INITIALIZE
    // =====================================================

    private void initialize() {

        fullyPaid = false;
        hasProducts = false;

        hasHotels = false;
        hasTransfers = false;
        hasAirTickets = false;
        hasAncillaries = false;

        packageTotal = 0;
        totalPaid = 0;
        remainingBalance = 0;

        errorMessage = '';
        qrErrorMessage = '';

        hotelVouchers = new List<Voucher>();
        transferVouchers = new List<Voucher>();
        airTicketVouchers = new List<Voucher>();
        ancillaryVouchers = new List<Voucher>();
    }

    // =====================================================
    // LOAD BOOKING
    // =====================================================

    private void loadBooking(Id bookingId) {

        List<Opportunity> bookings = [
            SELECT Id,
                   Name,
                   Booking_Number__c,
                   Account.Name,
                   Traveler__r.Name,
                   Traveler__r.Email,
                   Departure_Date__c,
                   Return_Date__c,
                   Total_Paid__c,
                   CurrencyIsoCode
            FROM Opportunity
            WHERE Id = :bookingId
            LIMIT 1
        ];

        if (bookings.isEmpty()) {
            errorMessage = 'Booking record was not found.';
            return;
        }

        bookingInfo = bookings[0];
    }

    // =====================================================
    // LOAD SAVED TRAVEL PACKAGE
    // =====================================================

 
private void loadBookedProducts(Id bookingId) {

    // Find the synchronized Quote belonging to this Booking.
    List<Quote> syncedQuotes = [
        SELECT Id, Name, CurrencyIsoCode
        FROM Quote
        WHERE OpportunityId = :bookingId
        AND IsSyncing = true
        ORDER BY LastModifiedDate DESC
        LIMIT 1
    ];

    if (syncedQuotes.isEmpty()) {
        errorMessage =
            'No synchronized Quote was found for this Booking.';
        return;
    }

    Id quoteId = syncedQuotes[0].Id;

    // Retrieve selected products from the Quote.
    // Product information comes directly from Product2.
    List<QuoteLineItem> lines = [
        SELECT Id,
               Quantity,
               UnitPrice,
               TotalPrice,
               Description,

               PricebookEntry.Product2Id,
               PricebookEntry.Product2.Name,
               PricebookEntry.Product2.ProductCode,
               PricebookEntry.Product2.Description,
               PricebookEntry.Product2.Package_Type__c,
               PricebookEntry.Product2.Destination__c,
               PricebookEntry.Product2.Departure__c,
               PricebookEntry.Product2.Arrival_Airport__c,
               PricebookEntry.Product2.Departure_Date__c,
               PricebookEntry.Product2.Return_Date__c,
               PricebookEntry.Product2.Supplier__c,
               PricebookEntry.Product2.Flight_Type__c,
               PricebookEntry.Product2.Cabin_Class__c

        FROM QuoteLineItem

        WHERE QuoteId = :quoteId

        ORDER BY CreatedDate ASC
    ];

    for (QuoteLineItem line : lines) {

        if (line.PricebookEntry == null ||
            line.PricebookEntry.Product2 == null) {
            continue;
        }

        Product2 product = line.PricebookEntry.Product2;

        Voucher voucher = new Voucher();

        // Quote line identification
        voucher.lineId = line.Id;

        // Actual Product2 identification
        voucher.productId =
            line.PricebookEntry.Product2Id;

        // Product information
        voucher.serviceName = product.Name;
        voucher.productCode = product.ProductCode;

        voucher.category =
            normalizePackageType(product.Package_Type__c);

        voucher.destination = product.Destination__c;
        voucher.supplier = product.Supplier__c;

        voucher.description =
            String.isNotBlank(line.Description)
                ? line.Description
                : product.Description;

        // Travel information
        voucher.departure = product.Departure__c;
        voucher.arrivalAirport = product.Arrival_Airport__c;

        voucher.departureDate = product.Departure_Date__c;
        voucher.returnDate = product.Return_Date__c;

        voucher.flightType = product.Flight_Type__c;
        voucher.cabinClass = product.Cabin_Class__c;

        // Commercial information from QuoteLineItem
        voucher.quantity = line.Quantity;
        voucher.unitPrice = line.UnitPrice;
        voucher.totalPrice = line.TotalPrice;

        // Default values.
        // See note below about preserving hotel room information.
        voucher.rooms = 1;
        voucher.nights = 1;

        // Unique voucher reference
        voucher.voucherReference =
            'VGTS-' + String.valueOf(line.Id);

        voucher.qrUrl = null;

        // Categorize products
        if (voucher.category == 'Hotels') {

            hotelVouchers.add(voucher);

        } else if (voucher.category == 'Ground') {

            transferVouchers.add(voucher);

        } else if (voucher.category == 'Air_Tickets') {

            airTicketVouchers.add(voucher);

        } else {

            ancillaryVouchers.add(voucher);
        }

        packageTotal += line.TotalPrice;
    }

    hasProducts =
        !hotelVouchers.isEmpty() ||
        !transferVouchers.isEmpty() ||
        !airTicketVouchers.isEmpty() ||
        !ancillaryVouchers.isEmpty();

    hasHotels = !hotelVouchers.isEmpty();
    hasTransfers = !transferVouchers.isEmpty();
    hasAirTickets = !airTicketVouchers.isEmpty();
    hasAncillaries = !ancillaryVouchers.isEmpty();
}



    // =====================================================
    // PAYMENT VERIFICATION
    // =====================================================

    private void calculatePayment(Id bookingId) {

        AggregateResult[] results = [
            SELECT SUM(Amount__c) totalAmount
            FROM Payment__c
            WHERE Booking__c = :bookingId
            AND Status__c = 'Completed'
        ];

        totalPaid = 0;

        if (!results.isEmpty() &&
            results[0].get('totalAmount') != null) {

            totalPaid = (Decimal)results[0].get('totalAmount');
        }

        remainingBalance = packageTotal - totalPaid;

        if (remainingBalance < 0) {
            remainingBalance = 0;
        }

        fullyPaid =
            packageTotal > 0 &&
            totalPaid >= packageTotal;
    }

    // =====================================================
    // GENERATE AND SAVE QR CODES
    // CALLED BY VISUALFORCE PAGE
    // =====================================================

    public PageReference prepare() {

        if (!hasProducts) {
            return null;
        }

        try {

            List<Voucher> allVouchers = getAllVouchers();

            if (allVouchers.isEmpty()) {
                return null;
            }

            Set<String> titles = new Set<String>();

            Map<String, Voucher> voucherByTitle =
                new Map<String, Voucher>();

            for (Voucher voucher : allVouchers) {

                String title = getQrTitle(voucher.lineId);

                titles.add(title);
                voucherByTitle.put(title, voucher);
            }

            // -------------------------------------------------
            // FIND EXISTING QR FILES
            // -------------------------------------------------

            Map<String, Id> existingQrFiles =
                new Map<String, Id>();

            for (ContentDocumentLink linkRecord : [
                SELECT ContentDocument.Title,
                       ContentDocument.LatestPublishedVersionId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :bookingInfo.Id
                AND ContentDocument.Title IN :titles
            ]) {

                existingQrFiles.put(
                    linkRecord.ContentDocument.Title,
                    linkRecord.ContentDocument.LatestPublishedVersionId
                );
            }

            List<ContentVersion> filesToInsert =
                new List<ContentVersion>();

            // -------------------------------------------------
            // GENERATE ONLY MISSING QR CODES
            // -------------------------------------------------

            for (Voucher voucher : allVouchers) {

                String title = getQrTitle(voucher.lineId);

                if (existingQrFiles.containsKey(title)) {
                    continue;
                }

                Blob qrImage = createQrImage(voucher);

                if (qrImage == null) {
                    continue;
                }

                ContentVersion file = new ContentVersion();

                file.Title = title;
                file.PathOnClient = title + '.png';
                file.VersionData = qrImage;

                // Automatically link the file to the Booking.
                file.FirstPublishLocationId = bookingInfo.Id;

                filesToInsert.add(file);
            }

            // All callouts finish before DML.
            if (!filesToInsert.isEmpty()) {

                insert filesToInsert;

                PageReference redirectPage =
                    ApexPages.currentPage();

                redirectPage.setRedirect(true);

                return redirectPage;
            }

            // -------------------------------------------------
            // SET EXISTING QR URLS
            // -------------------------------------------------

            Map<String, Id> finalQrFiles =
                new Map<String, Id>(existingQrFiles);

            for (Voucher voucher : allVouchers) {

                String title = getQrTitle(voucher.lineId);

                if (finalQrFiles.containsKey(title)) {

                    voucher.qrUrl =
                        '/sfc/servlet.shepherd/version/download/' +
                        finalQrFiles.get(title);
                }
            }

            return null;

        } catch (Exception ex) {

            qrErrorMessage =
                'QR generation failed: ' + ex.getMessage();

            System.debug(
                'VGTS QR ERROR: ' + ex.getMessage()
            );

            return null;
        }
    }

    // =====================================================
    // CREATE QUICKCHART QR IMAGE
    // =====================================================

    private static Blob createQrImage(Voucher voucher) {

        String qrText =
            'VGTS BOOKING VOUCHER\n' +
            'Reference: ' + voucher.voucherReference + '\n' +
            'Service: ' + voucher.serviceName + '\n' +
            'Category: ' + voucher.category + '\n' +
            'Destination: ' + safeText(voucher.destination) + '\n' +
            'Supplier: ' + safeText(voucher.supplier) + '\n' +
            'Quantity: ' + String.valueOf(voucher.quantity);

        if (voucher.departureDate != null) {

            qrText +=
                '\nDeparture: ' +
                String.valueOf(voucher.departureDate);
        }

        if (voucher.returnDate != null) {

            qrText +=
                '\nReturn: ' +
                String.valueOf(voucher.returnDate);
        }

        HttpRequest request = new HttpRequest();

        request.setEndpoint(
            QUICKCHART_ENDPOINT +
            '?size=' + QR_SIZE +
            '&margin=2&text=' +
            EncodingUtil.urlEncode(qrText, 'UTF-8')
        );

        request.setMethod('GET');
        request.setTimeout(20000);
        request.setHeader('Accept', 'image/png');

        HttpResponse response =
            new Http().send(request);

        if (response.getStatusCode() != 200) {

            throw new CalloutException(
                'QuickChart returned HTTP ' +
                response.getStatusCode()
            );
        }

        Blob imageBody = response.getBodyAsBlob();

        String encodedImage =
            EncodingUtil.base64Encode(imageBody);

        if (!encodedImage.startsWith('iVBORw0KGgo')) {

            throw new CalloutException(
                'QuickChart did not return a valid PNG image.'
            );
        }

        return imageBody;
    }

    // =====================================================
    // LOAD EXISTING QR FILES
    // =====================================================

    private void loadExistingQrFiles(Id bookingId) {


        List<Voucher> allVouchers = getAllVouchers();

        Set<String> titles = new Set<String>();

        for (Voucher voucher : allVouchers) {
            titles.add(getQrTitle(voucher.lineId));
        }

        if (titles.isEmpty()) {
            return;
        }

        for (ContentDocumentLink linkRecord : [
            SELECT ContentDocument.Title,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :bookingId
            AND ContentDocument.Title IN :titles
        ]) {

            String title = linkRecord.ContentDocument.Title;

            String url =
                '/sfc/servlet.shepherd/version/download/' +
                linkRecord.ContentDocument.LatestPublishedVersionId;

            for (Voucher voucher : allVouchers) {

                if (getQrTitle(voucher.lineId) == title) {
                    voucher.qrUrl = url;
                    break;
                }
            }
        }
    }

    // =====================================================
    // GET ALL VOUCHERS
    // =====================================================

    private List<Voucher> getAllVouchers() {

        List<Voucher> result = new List<Voucher>();

        result.addAll(hotelVouchers);
        result.addAll(transferVouchers);
        result.addAll(airTicketVouchers);
        result.addAll(ancillaryVouchers);

        return result;
    }

    // =====================================================
    // QR FILE TITLE
    // =====================================================

    private static String getQrTitle(Id lineId) {

        return QR_PREFIX + String.valueOf(lineId);
    }

    // =====================================================
    // SAFE TEXT
    // =====================================================

    private static String safeText(String value) {

        return String.isBlank(value) ? '-' : value;
    }

    // =====================================================
    // NORMALIZE PRODUCT TYPE
    // =====================================================

    private static String normalizePackageType(String value) {

        String typeValue =
            String.valueOf(value == null ? '' : value)
                .trim()
                .toLowerCase();

        if (typeValue.contains('air') ||
            typeValue.contains('flight') ||
            typeValue.contains('ticket')) {

            return 'Air_Tickets';
        }

        if (typeValue.contains('hotel') ||
            typeValue.contains('accommodation')) {

            return 'Hotels';
        }

        if (typeValue.contains('ground') ||
            typeValue.contains('transfer') ||
            typeValue.contains('transport')) {

            return 'Ground';
        }

        return 'Ancillary';
    }

    // =====================================================
    // CURRENCY
    // =====================================================

    public String getCurrencyCode() {

        return bookingInfo == null ||
               String.isBlank(bookingInfo.CurrencyIsoCode)
            ? 'USD'
            : bookingInfo.CurrencyIsoCode;
    }

    // =====================================================
    // DISPLAY STATUS
    // =====================================================

    public Boolean getCanGenerateVoucher() {

        return fullyPaid && hasProducts;
    }
}

