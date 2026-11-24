
public with sharing class VGTSQuoteSyncProductHandler {

    private static Boolean isProcessing = false;

    public static void restoreBookingServiceFlag(
        List<OpportunityLineItem> changedLines
    ) {

        if (isProcessing ||
            changedLines == null ||
            changedLines.isEmpty()) {
            return;
        }

        Set<Id> opportunityIds = new Set<Id>();

        for (OpportunityLineItem line : changedLines) {
            if (line.OpportunityId != null) {
                opportunityIds.add(line.OpportunityId);
            }
        }

        if (opportunityIds.isEmpty()) return;

        isProcessing = true;

        try {

            // Find accepted Quotes currently synchronized.
            Map<Id, Id> quoteToOpportunity =
                new Map<Id, Id>();

            Set<Id> quoteIds = new Set<Id>();

            for (Quote q : [
                SELECT Id, OpportunityId
                FROM Quote
                WHERE OpportunityId IN :opportunityIds
                AND Status = 'Accepted'
                AND IsSyncing = true
            ]) {

                quoteIds.add(q.Id);
                quoteToOpportunity.put(
                    q.Id,
                    q.OpportunityId
                );
            }

            if (quoteIds.isEmpty()) return;

            // Identify products belonging to those Quotes.
            Map<Id, Set<Id>> productsByOpportunity =
                new Map<Id, Set<Id>>();

            for (QuoteLineItem qli : [
                SELECT QuoteId, PricebookEntry.Product2Id
                FROM QuoteLineItem
                WHERE QuoteId IN :quoteIds
            ]) {

                Id opportunityId =
                    quoteToOpportunity.get(qli.QuoteId);

                Id productId =
                    qli.PricebookEntry.Product2Id;

                if (opportunityId == null ||
                    productId == null) {
                    continue;
                }

                if (!productsByOpportunity.containsKey(
                    opportunityId
                )) {
                    productsByOpportunity.put(
                        opportunityId,
                        new Set<Id>()
                    );
                }

                productsByOpportunity.get(opportunityId)
                    .add(productId);
            }

            Set<Id> productIds = new Set<Id>();

            for (Set<Id> ids : productsByOpportunity.values()) {
                productIds.addAll(ids);
            }

            if (productIds.isEmpty()) return;

            // Find matching Opportunity Products.
            List<OpportunityLineItem> updates =
                new List<OpportunityLineItem>();

            for (OpportunityLineItem line : [
                SELECT Id, OpportunityId,
                       PricebookEntry.Product2Id,
                       Booking_Service__c
                FROM OpportunityLineItem
                WHERE OpportunityId IN :opportunityIds
                AND PricebookEntry.Product2Id IN :productIds
            ]) {

                Set<Id> quoteProducts =
                    productsByOpportunity.get(line.OpportunityId);

                if (quoteProducts != null &&
                    quoteProducts.contains(
                        line.PricebookEntry.Product2Id
                    ) &&
                    line.Booking_Service__c != true) {

                    updates.add(new OpportunityLineItem(
                        Id = line.Id,
                        Booking_Service__c = true
                    ));
                }
            }

            if (!updates.isEmpty()) {
                update updates;
            }

        } finally {
            isProcessing = false;
        }
    }
}

