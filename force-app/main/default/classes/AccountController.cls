public with sharing class AccountController {

    @AuraEnabled
    public static Id createNewAccount(String accountName) {
        if (String.isBlank(accountName)) {
            throw new AuraHandledException(
                'Account Name is required.'
            );
        }

        Account newAccount = new Account(
            Name = accountName.trim()
        );

        insert newAccount;

        return newAccount.Id;
    }

    @AuraEnabled(cacheable=true)
    public static List<Account> getAccounts(Integer maxRecords) {
        Integer recordLimit = maxRecords == null || maxRecords < 1
            ? 10
            : Math.min(maxRecords, 200);

        return [
            SELECT Id, Name
            FROM Account
            ORDER BY CreatedDate DESC
            LIMIT :recordLimit
        ];
    }
}