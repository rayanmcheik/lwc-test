public with sharing class VGTSQuotePDFDetector
    implements Schedulable {

    public void execute(SchedulableContext context) {

        Datetime cutoff = System.now().addDays(-1);

        List<QuoteDocument> documents = [
            SELECT Id, QuoteId, CreatedDate
            FROM QuoteDocument
            WHERE QuoteId != null
            AND CreatedDate >= :cutoff
        ];

        Set<Id> quoteIds = new Set<Id>();

        for (QuoteDocument doc : documents) {
            quoteIds.add(doc.QuoteId);
        }

        if (quoteIds.isEmpty()) {
            return;
        }

        List<Quote> quotesToUpdate = new List<Quote>();

        for (Quote q : [
            SELECT Id, PDF_Generated__c
            FROM Quote
            WHERE Id IN :quoteIds
            AND PDF_Generated__c = false
        ]) {
            q.PDF_Generated__c = true;
            quotesToUpdate.add(q);
        }

        if (!quotesToUpdate.isEmpty()) {
            Database.update(quotesToUpdate, false);
        }
    }
}

