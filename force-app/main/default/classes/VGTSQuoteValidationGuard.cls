public with sharing class VGTSQuoteValidationGuard {

    public static void validateBeforeInsert(
        List<Quote> quotes
    ) {

        Set<Id> bookingIds = new Set<Id>();

        for (Quote quoteRecord : quotes) {

            if (quoteRecord.OpportunityId != null) {
                bookingIds.add(quoteRecord.OpportunityId);
            }
        }

        if (bookingIds.isEmpty()) {
            for (Quote quoteRecord : quotes) {
                quoteRecord.addError(
                    'A Booking is required before creating a Quote.'
                );
            }
            return;
        }

        Map<Id, String> reasons =
            VisaChecklistController.getQuoteBlockReasons(
                bookingIds
            );

        for (Quote quoteRecord : quotes) {

            if (quoteRecord.OpportunityId == null) {
                quoteRecord.addError(
                    'A Booking is required.'
                );
                continue;
            }

            String reason =
                reasons.get(quoteRecord.OpportunityId);

            if (!String.isBlank(reason)) {
                quoteRecord.addError(
                    'Quote creation blocked: ' + reason
                );
            }
        }
    }
}
