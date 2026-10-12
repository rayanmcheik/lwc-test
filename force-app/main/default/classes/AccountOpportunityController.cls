public with sharing class AccountOpportunityController {

    public class AccountOpportunityWrapper {
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Integer opportunityCount { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }

        @AuraEnabled
        public List<OpportunityWrapper> opportunities { get; set; }

        public AccountOpportunityWrapper() {
            opportunities = new List<OpportunityWrapper>();
            opportunityCount = 0;
            totalAmount = 0;
        }
    }

    public class OpportunityWrapper {
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public String opportunityName { get; set; }
        @AuraEnabled public String stageName { get; set; }
        @AuraEnabled public Decimal amount { get; set; }

        public OpportunityWrapper(Opportunity opp) {
            opportunityId = opp.Id;
            opportunityName = opp.Name;
            stageName = opp.StageName;
            amount = opp.Amount;
        }
    }
    @AuraEnabled(cacheable=true)
    public static List<AccountOpportunityWrapper> getAccountsWithOpportunities() {

        List<AccountOpportunityWrapper> results =
            new List<AccountOpportunityWrapper>();

        for (Account acc : [
            SELECT Id, Name,
                (SELECT Id, Name, StageName, Amount
                 FROM Opportunities
                 ORDER BY Name)
            FROM Account
            ORDER BY Name
        ]) {
            AccountOpportunityWrapper accountData =
                new AccountOpportunityWrapper();

            accountData.accountId = acc.Id;
            accountData.accountName = acc.Name;

            for (Opportunity opp : acc.Opportunities) {
                accountData.opportunities.add(
                    new OpportunityWrapper(opp)
                );

                accountData.opportunityCount++;

                if (opp.Amount != null) {
                    accountData.totalAmount += opp.Amount;
                }
            }

            results.add(accountData);
        }

        return results;
    }
    @AuraEnabled
    public static void updateOpportunityStatus(
        Id opportunityId,
        String newStage
    ) {
        if (opportunityId == null) {
            throw new AuraHandledException(
                'An Opportunity ID is required.'
            );
        }

        if (newStage != 'Closed Won' &&
            newStage != 'Closed Lost') {
            throw new AuraHandledException(
                'Select Closed Won or Closed Lost.'
            );
        }

        Opportunity opp = [
            SELECT Id, StageName
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
            FOR UPDATE
        ];

        if (opp.StageName == 'Closed Won' ||
            opp.StageName == 'Closed Lost') {
            throw new AuraHandledException(
                'This Opportunity is already closed.'
            );
        }

        opp.StageName = newStage;
        update opp;
    }
}